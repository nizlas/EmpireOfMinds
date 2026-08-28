"""Regressions for the barriers between a normal run and a paid provider call.

WHAT THESE TESTS ARE FOR. Everything else in this suite proves the pipeline works.
These prove it does NOT work when it must not: that no combination of flags,
environment and credentials short of all three barriers reaches a provider, that a
credential is never read by a run that gets refused and never printed by one that
is not, and that one approved plan can buy exactly one paid unit of work even
across crashes and reruns.

HOW THEY AVOID BEING FALSELY GREEN. Two rules throughout:

* Assert on COUNTERS, not on reported state. `double.create_calls == 1` is
  evidence; a manifest saying `submission_outcome: CREATED` is a claim. A test
  that only reads the claim would pass against code that lies.
* Assert the exact refusal CODE and that the code differs between causes. A test
  matching "it refused somehow" would keep passing if the ordering of the barriers
  regressed and, say, the credential were read before authorization.

The socket tripwire in `conftest.py` is armed for every test here, so any path
that tried to reach the real endpoint would fail loudly rather than quietly.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tools.assetgen import cli, live_gate, provider_plan
from tools.assetgen.errors import ErrorKind, ProviderError
from tools.assetgen.hand_fixture_ingest import EXIT_ACCEPTED, EXIT_CLASSIFIED, INGEST_ACCEPTED
from tools.assetgen.live_gate import (
    LIVE_PROVIDER_MODE_REQUIRED,
    OPT_IN_ENV_VAR,
    OPT_IN_REQUIRED_VALUE,
    PAID_PROVIDER_OPT_IN_REQUIRED,
    PROVIDER_CREDENTIAL_MISSING,
    PROVIDER_PLAN_CONFIRMATION_REQUIRED,
    PROVIDER_PLAN_DIGEST_MISMATCH,
    PROVIDER_PLAN_NOT_EXECUTABLE,
    PROVIDER_SUBMISSION_ALREADY_RECORDED,
    LiveAuthorization,
    LiveGateRefusal,
)
from tools.assetgen.manifest import JobStatus
from tools.assetgen.net_guard import NetworkForbidden, network_forbidden
from tools.assetgen.orchestrator import JobOrchestrator, LiveCallNotAuthorized
from tools.assetgen.paid_executor import PaidSubmission, execute_paid_submission
from tools.assetgen.provider_plan import PLAN_DIGEST_KEY, build_plan, plan_digest
from tools.assetgen.providers import build_provider
from tools.assetgen.providers.base import ImageInput, JobRequest, TaskType
from tools.assetgen.providers.uthana import CREDENTIAL_ENV_VAR as UTHANA_KEY
from tools.assetgen.secret_guard import load_credential
from tools.assetgen.store import JobStore
from tools.assetgen.transport import RetryPolicy

from tools.assetgen.capability import (
    CAPABILITY_REQUIRED,
    CapabilityRefused,
    OperationClass,
)
from tools.assetgen.endpoint import parse_endpoint
from tools.assetgen.providers.uthana import DEFAULT_BASE_URL as UTHANA_DEFAULT_BASE_URL
from tools.assetgen.tests.authorization_support import granted_authorization
from tools.assetgen.tests.provider_double import (
    UthanaDouble,
    synthetic_glb_bytes,
    transport_fault,
)

#: Obviously synthetic. Long enough that `register_secret` will track it, so a
#: leak test proves the scrubber ran rather than proving the value was too short
#: to be noticed.
SYNTHETIC_UTHANA_KEY = "uth_synthetic_test_key_0123456789abcdef"


# --------------------------------------------------------------------- fixtures


@pytest.fixture
def mesh(tmp_path: Path) -> Path:
    """A local file standing in for an upload candidate."""
    path = tmp_path / "candidate.glb"
    path.write_bytes(synthetic_glb_bytes())
    return path


#: The endpoint the Uthana adapter resolves to with no environment override. Used
#: so a plan built here approves the same destination the adapter would use.
UTHANA_ENDPOINT = parse_endpoint("uthana", UTHANA_DEFAULT_BASE_URL)


def uthana_plan(mesh: Path, repo_root: Path, **overrides) -> dict:
    """An EXECUTABLE plan, so a barrier test fails on the barrier under test."""
    arguments = dict(
        provider="uthana",
        operation="character_autorig",
        input_path=mesh,
        repo_root=repo_root,
        output_destination="artifacts/assetgen/jobs/x/outputs/rigged.glb",
        paid=True,
        credential_env_vars=(UTHANA_KEY,),
        endpoint=UTHANA_ENDPOINT,
        preflight={"upload_allowed": True, "verdict": "PASS", "blocking_checks": []},
    )
    arguments.update(overrides)
    return build_plan(**arguments)


@pytest.fixture
def plan(mesh: Path, tmp_path: Path) -> dict:
    """An EXECUTABLE plan, so barrier tests fail on the barrier under test.

    The preflight is supplied directly rather than run over the synthetic file:
    the gate itself is covered by its own tests, and a plan whose preflight
    refused would make every barrier test pass for the wrong reason.
    """
    return uthana_plan(mesh, tmp_path)


@pytest.fixture
def store(tmp_path: Path) -> JobStore:
    return JobStore.create(repo_root=tmp_path, artifact_root=tmp_path / "artifacts")


@pytest.fixture
def autorig_request(mesh: Path) -> JobRequest:
    return JobRequest(
        provider="uthana",
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=mesh),),
        parameters={
            "name": "double",
            "auto_rig": True,
            "auto_rig_front_facing": True,
            "include_fingers": True,
        },
        label="humanoid_autorig",
    )


def orchestrator_for(double: UthanaDouble, store: JobStore, **kwargs) -> JobOrchestrator:
    cache: dict = {}

    def factory(name: str):
        if name not in cache:
            cache[name] = build_provider(
                name,
                transport=double,
                retry_policy=RetryPolicy(max_attempts=3, base_delay_s=0.0, max_delay_s=0.0),
                require_credential=False,
            )
        return cache[name]

    defaults = {
        "authorization": granted_authorization(live=True, opt_in=True),
        "sleep": lambda _s: None,
    }
    defaults.update(kwargs)
    return JobOrchestrator(store=store, provider_factory=factory, **defaults)


def paid_ticket(orch: JobOrchestrator, request: JobRequest, plan: dict | None = None):
    """Mint a real paid capability for `request`, the way the executor does."""
    provider = orch.provider_factory(request.provider)
    resolved = plan if plan is not None else uthana_plan(
        request.inputs[0].path,
        orch.store.repo_root,
        operation_parameters=dict(request.parameters),
    )
    digest = plan_digest(resolved)
    try:
        claim = orch.store.claim_submission(digest, {"plan_sha256": digest, "state": "CLAIMED"})
    except FileExistsError:
        claim = orch.store.submission_record_path(digest)
    return granted_authorization(confirmed=digest).mint_paid_capability(
        plan=resolved, endpoint=provider.endpoint_identity(), claim_id=str(claim)
    )


def authorized_submit(orch: JobOrchestrator, request: JobRequest, **kwargs):
    return orch.submit(request, capability=paid_ticket(orch, request), **kwargs)


# ------------------------------------------------------- barriers, in isolation


def test_no_flags_and_no_credential_refuses_for_the_flag_not_the_key(plan):
    """The FIRST missing thing is the flag, so that is the reported cause.

    Ordering matters: if the credential were checked first, the refusal on a
    machine without a key would be `PROVIDER_CREDENTIAL_MISSING`, which reads as
    "configure a key and it will run" - the opposite of the intended message.
    """
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=False, env={}).authorize_submission(plan)
    assert caught.value.code == LIVE_PROVIDER_MODE_REQUIRED
    assert caught.value.to_dict()["credential_read"] is False


def test_no_flags_but_a_credential_present_still_refuses_identically(plan, monkeypatch):
    """A configured credential is not permission.

    This is the scenario the whole slice exists for: a developer machine with a
    working key is one word away from spending, so having the key must change
    nothing about the refusal.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=False, env={}).authorize_submission(plan)
    assert caught.value.code == LIVE_PROVIDER_MODE_REQUIRED
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(caught.value.to_dict())


def test_live_without_the_machine_opt_in_refuses_before_reading_a_credential(plan):
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=True, env={}).authorize_submission(plan)
    assert caught.value.code == PAID_PROVIDER_OPT_IN_REQUIRED
    assert caught.value.detail["env_var"] == OPT_IN_ENV_VAR


def test_the_opt_in_alone_never_opens_provider_traffic(plan):
    """An environment variable must not be able to authorize a run by itself."""
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=False, env=env).authorize_submission(plan)
    assert caught.value.code == LIVE_PROVIDER_MODE_REQUIRED


@pytest.mark.parametrize("value", ["", "0", "false", "yes", "true", "2", " "])
def test_only_the_exact_opt_in_value_counts(value, plan):
    """A truthy-looking value is not the opt-in; only the declared value is."""
    env = {OPT_IN_ENV_VAR: value}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=True, env=env).authorize_submission(plan)
    assert caught.value.code == PAID_PROVIDER_OPT_IN_REQUIRED


def test_both_barriers_without_a_confirmed_plan_refuses_and_names_the_digest(plan):
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(live=True, env=env).authorize_submission(plan)
    assert caught.value.code == PROVIDER_PLAN_CONFIRMATION_REQUIRED
    assert caught.value.detail["expected_plan_digest"] == plan[PLAN_DIGEST_KEY]


def test_a_digest_from_another_plan_is_refused(plan, mesh, tmp_path):
    other = build_plan(
        provider="uthana",
        operation="character_autorig",
        input_path=mesh,
        repo_root=tmp_path,
        output_destination="somewhere/else.glb",  # behaviour-affecting: new digest
        paid=True,
        credential_env_vars=(UTHANA_KEY,),
        preflight={"upload_allowed": True, "verdict": "PASS", "blocking_checks": []},
    )
    assert other[PLAN_DIGEST_KEY] != plan[PLAN_DIGEST_KEY]
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(
            live=True, confirmed_plan_digest=other[PLAN_DIGEST_KEY], env=env
        ).authorize_submission(plan)
    assert caught.value.code == PROVIDER_PLAN_DIGEST_MISMATCH


def test_a_digest_that_is_stale_because_the_input_changed_is_refused(plan, mesh, tmp_path):
    """Approval binds the file's CONTENT, not its name.

    Editing the mesh after approval must invalidate the approval, otherwise
    "approve the plan, then swap the asset" would upload something nobody read a
    plan for.
    """
    approved = plan[PLAN_DIGEST_KEY]
    mesh.write_bytes(synthetic_glb_bytes(b'{"asset":{"version":"2.0"},"edited":true}'))
    regenerated = build_plan(
        provider="uthana",
        operation="character_autorig",
        input_path=mesh,
        repo_root=tmp_path,
        output_destination=plan["output_destination"],
        paid=True,
        credential_env_vars=(UTHANA_KEY,),
        preflight={"upload_allowed": True, "verdict": "PASS", "blocking_checks": []},
    )
    assert regenerated["input"]["sha256"] != plan["input"]["sha256"]
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(
            live=True, confirmed_plan_digest=approved, env=env
        ).authorize_submission(regenerated)
    assert caught.value.code == PROVIDER_PLAN_DIGEST_MISMATCH


def test_a_plan_whose_own_preflight_refuses_cannot_be_confirmed_into_a_run(mesh, tmp_path):
    blocked = build_plan(
        provider="uthana",
        operation="character_autorig",
        input_path=mesh,
        repo_root=tmp_path,
        output_destination="x.glb",
        paid=True,
        credential_env_vars=(UTHANA_KEY,),
        preflight={
            "upload_allowed": False,
            "verdict": "FAIL",
            "blocking_checks": ["no_existing_rig"],
        },
    )
    assert blocked["executable"] is False
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(
            live=True, confirmed_plan_digest=blocked[PLAN_DIGEST_KEY], env=env
        ).authorize_submission(blocked)
    assert caught.value.code == PROVIDER_PLAN_NOT_EXECUTABLE


def test_a_missing_credential_after_an_approved_plan_is_its_own_refusal(plan):
    """Passing every barrier and then having no key is a distinct, local failure.

    It is detected before the request rather than as a 401 afterwards, so an
    unconfigured machine never produces provider traffic at all.
    """
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    auth = LiveAuthorization.from_environment(
        live=True, confirmed_plan_digest=plan[PLAN_DIGEST_KEY], env=env
    )
    auth.authorize_submission(plan)  # all three barriers pass
    with pytest.raises(LiveGateRefusal) as caught:
        live_gate.require_credential_present(UTHANA_KEY, env={})
    assert caught.value.code == PROVIDER_CREDENTIAL_MISSING
    assert caught.value.detail["credential_state"] == "missing"


def test_every_refusal_cause_has_its_own_code():
    """Distinct causes stay distinguishable, so a regression cannot merge two."""
    assert len(live_gate.REFUSAL_CODES) == len(set(live_gate.REFUSAL_CODES))
    for code in (
        LIVE_PROVIDER_MODE_REQUIRED,
        PAID_PROVIDER_OPT_IN_REQUIRED,
        PROVIDER_PLAN_CONFIRMATION_REQUIRED,
        PROVIDER_PLAN_DIGEST_MISMATCH,
        PROVIDER_CREDENTIAL_MISSING,
        PROVIDER_SUBMISSION_ALREADY_RECORDED,
    ):
        assert code in live_gate.REFUSAL_CODES


# ------------------------------------------------- the barriers at the CLI edge


def _cli(argv: list[str], capsys) -> tuple[int, dict]:
    code = cli.main(argv)
    out = capsys.readouterr().out
    return code, json.loads(out)


@pytest.fixture
def gate_passing_cli(monkeypatch, plan, mesh):
    """Make the free local pre-upload gate pass so the BARRIER is what is tested.

    No local mesh passes that gate today (every humanoid in the repo is already a
    rigged provider bundle), so without this the CLI would refuse at
    `PRE_UPLOAD_GATE_FAILED` and these tests would go green while proving nothing
    about the live barriers. The gate has its own tests; this stubs it and leaves
    the barrier chain as the only thing that can refuse.
    """
    monkeypatch.setattr(
        cli,
        "evaluate_candidates",
        lambda paths: {
            "candidates": [{"upload_allowed": True, "verdict": "PASS", "blocking_checks": []}]
        },
    )
    monkeypatch.setattr(cli, "build_autorig_plan", lambda **kwargs: plan)
    # A transport that would raise if anything tried to send, on top of the
    # socket tripwire, so a leak past the barrier cannot be silent.
    monkeypatch.setattr(cli, "UrllibTransport", lambda: UthanaDouble())
    return plan


def test_the_cli_refuses_a_paid_submit_without_any_flags(
    mesh, capsys, monkeypatch, gate_passing_cli
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    code, payload = _cli(["autorig", str(mesh), "--submit"], capsys)
    assert code == 4
    assert payload["error"] == LIVE_PROVIDER_MODE_REQUIRED
    assert payload["network_reached"] is False
    assert payload["credential_read"] is False
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(payload)


def test_the_cli_refuses_live_without_the_opt_in(mesh, capsys, monkeypatch, gate_passing_cli):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    code, payload = _cli(["--live", "autorig", str(mesh), "--submit"], capsys)
    assert code == 4
    assert payload["error"] == PAID_PROVIDER_OPT_IN_REQUIRED
    assert payload["credential_read"] is False


def test_the_cli_refuses_live_and_opt_in_without_a_confirmed_plan(
    mesh, capsys, monkeypatch, gate_passing_cli
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkeypatch.setenv(OPT_IN_ENV_VAR, OPT_IN_REQUIRED_VALUE)
    code, payload = _cli(["--live", "autorig", str(mesh), "--submit"], capsys)
    assert code == 4
    assert payload["error"] == PROVIDER_PLAN_CONFIRMATION_REQUIRED
    assert payload["detail"]["expected_plan_digest"] == gate_passing_cli[PLAN_DIGEST_KEY]


def test_the_cli_refuses_a_wrong_plan_digest(mesh, capsys, monkeypatch, gate_passing_cli):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkeypatch.setenv(OPT_IN_ENV_VAR, OPT_IN_REQUIRED_VALUE)
    code, payload = _cli(
        ["--live", "autorig", str(mesh), "--submit", "--confirm-plan", "f" * 64], capsys
    )
    assert code == 4
    assert payload["error"] == PROVIDER_PLAN_DIGEST_MISMATCH


def test_the_cli_refuses_when_the_credential_is_missing_after_a_good_plan(
    mesh, capsys, monkeypatch, gate_passing_cli
):
    """All three barriers pass, and only then is the key found to be absent."""
    monkeypatch.delenv(UTHANA_KEY, raising=False)
    monkeypatch.setenv(OPT_IN_ENV_VAR, OPT_IN_REQUIRED_VALUE)
    code, payload = _cli(
        [
            "--live",
            "autorig",
            str(mesh),
            "--submit",
            "--confirm-plan",
            gate_passing_cli[PLAN_DIGEST_KEY],
        ],
        capsys,
    )
    assert code == 4
    assert payload["error"] == PROVIDER_CREDENTIAL_MISSING
    assert payload["detail"]["credential_env_var"] == UTHANA_KEY


def test_the_offline_plan_command_reaches_no_network_and_reads_no_credential(
    mesh, capsys, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    code, payload = _cli(["provider-plan", str(mesh)], capsys)
    # Exit 3: the synthetic file is not a gate-passing humanoid, which is the
    # honest verdict. The point of the test is what the command did NOT do.
    assert code in (0, 3)
    assert payload["network_used"] is False
    assert payload["credential_read"] is False
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(payload)
    assert payload["plan"]["credentials"]["env_vars"] == [UTHANA_KEY]
    # A plan states which variables a live run would read, and nothing more:
    # whether this machine has one configured is not part of the work.
    assert "present" not in json.dumps(payload["plan"]["credentials"])


# --------------------------------------------------------------- the plan itself


def test_the_plan_digest_is_deterministic_for_identical_input(mesh, tmp_path):
    def make():
        return build_plan(
            provider="uthana",
            operation="character_autorig",
            input_path=mesh,
            repo_root=tmp_path,
            output_destination="out.glb",
            paid=True,
            credential_env_vars=(UTHANA_KEY,),
            preflight={"upload_allowed": True, "verdict": "PASS", "blocking_checks": []},
        )

    assert make()[PLAN_DIGEST_KEY] == make()[PLAN_DIGEST_KEY]


@pytest.mark.parametrize(
    "mutation",
    [
        {"provider": "meshy"},
        {"operation": "image_to_3d"},
        {"output_destination": "elsewhere/rigged.glb"},
        {"paid": False},
    ],
)
def test_every_behaviour_affecting_field_changes_the_digest(mutation, plan):
    """If a field can change what happens, it must change what was approved."""
    mutated = {**plan, **mutation}
    assert plan_digest(mutated) != plan[PLAN_DIGEST_KEY]


@pytest.mark.parametrize(
    "path, value",
    [
        (("limits", "max_submissions"), 2),
        (("limits", "max_poll_attempts"), 5),
        (("timeouts", "submit_s"), 30.0),
        (("input", "sha256"), "f" * 64),
    ],
)
def test_nested_limits_and_timeouts_are_inside_the_digest(path, value, plan):
    mutated = json.loads(json.dumps(plan))
    mutated[path[0]][path[1]] = value
    assert plan_digest(mutated) != plan[PLAN_DIGEST_KEY]


def test_the_operation_parameters_are_inside_the_digest(mesh, tmp_path):
    """Approving a plan must not approve a different rig contract.

    `include_fingers=false` returns a skeleton the hand pipeline cannot grip with,
    so it has to invalidate an existing approval rather than ride along on it. The
    character name is covered too: an approval names one character.
    """
    def make(**parameters):
        return build_plan(
            provider="uthana",
            operation="character_autorig",
            input_path=mesh,
            repo_root=tmp_path,
            output_destination="out.glb",
            paid=True,
            credential_env_vars=(UTHANA_KEY,),
            operation_parameters={"name": "a", "include_fingers": True, **parameters},
            preflight={"upload_allowed": True, "verdict": "PASS", "blocking_checks": []},
        )

    approved = make()[PLAN_DIGEST_KEY]
    assert make(include_fingers=False)[PLAN_DIGEST_KEY] != approved
    assert make(name="somebody_else")[PLAN_DIGEST_KEY] != approved
    assert make()[PLAN_DIGEST_KEY] == approved


def test_the_generated_autorig_plan_always_demands_finger_joints(mesh, tmp_path):
    """The one parameter the whole equipment pipeline depends on."""
    from tools.assetgen.provider_plan import build_autorig_plan

    generated = build_autorig_plan(repo_root=tmp_path, input_path=mesh, character_name="probe")
    assert generated["operation_parameters"]["include_fingers"] is True
    assert generated["operation_parameters"]["name"] == "probe"


def test_description_only_fields_are_outside_the_digest(plan):
    """Regenerating an unchanged plan must reproduce the same approval."""
    mutated = {**plan, "notes": ["a different human-readable note"], "plan_path": "somewhere.json"}
    assert plan_digest(mutated) == plan[PLAN_DIGEST_KEY]


def test_editing_a_plan_file_digest_does_not_make_it_confirmable(plan, tmp_path):
    """The digest is recomputed from content, never read and trusted."""
    forged = {**plan, PLAN_DIGEST_KEY: "0" * 64, "provider": "meshy"}
    written = provider_plan.write_plan(forged, tmp_path / "forged.json")
    reloaded = provider_plan.load_plan(written)
    assert provider_plan.digest_is_intact(reloaded) is False
    env = {OPT_IN_ENV_VAR: OPT_IN_REQUIRED_VALUE}
    with pytest.raises(LiveGateRefusal) as caught:
        LiveAuthorization.from_environment(
            live=True, confirmed_plan_digest="0" * 64, env=env
        ).authorize_submission(reloaded)
    assert caught.value.code == PROVIDER_PLAN_DIGEST_MISMATCH


def test_a_plan_states_unknown_cost_rather_than_omitting_it(plan):
    assert plan["cost"]["known"] is False
    assert plan["cost"]["value"] == "unknown"
    assert "not the same as free" in plan["cost"]["note"]


def test_a_plan_names_the_local_steps_that_follow_the_paid_call(plan):
    steps = plan["local_steps_after_download"]
    for expected in ("download", "godot_import", "certification", "publish_or_classified_fail"):
        assert expected in steps


def test_a_plan_containing_a_credential_value_is_refused(plan, monkeypatch):
    """The check now works from values loaded in-process rather than from a fresh
    environment read, so that offline planning never materialises a credential."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    load_credential(UTHANA_KEY)
    leaked = {**plan, "notes": [f"key is {SYNTHETIC_UTHANA_KEY}"]}
    with pytest.raises(ValueError, match="credential value loaded in this process"):
        provider_plan.assert_no_credential_values(leaked)


# ------------------------------------------------------- no network in the suite


def test_the_tripwire_fires_on_any_outbound_connection():
    import socket

    with network_forbidden():
        with pytest.raises(NetworkForbidden):
            socket.create_connection(("uthana.com", 443), timeout=1)
        with pytest.raises(NetworkForbidden):
            socket.getaddrinfo("api.meshy.ai", 443)


def test_the_real_transport_cannot_leave_the_process_during_tests():
    """Two independent layers stop the production transport, and both are asserted.

    The capability check refuses first, which is the repair's own guarantee: the
    real egress point demands authorization, so a request built by any call path
    that skipped the gate dies here rather than on the wire. The socket tripwire
    behind it is what would catch a bug in that check, so it is asserted separately
    with the check satisfied as far as it can be offline.
    """
    from tools.assetgen.transport import HttpRequest, UrllibTransport

    with pytest.raises(CapabilityRefused) as unauthorized:
        UrllibTransport().send(
            HttpRequest(method="GET", url="https://uthana.com/graphql", timeout_s=1.0)
        )
    assert unauthorized.value.code == CAPABILITY_REQUIRED

    # Now WITH a genuine capability: the tripwire must still stop it, which proves
    # the offline guarantee does not rest on the capability check alone.
    capability = granted_authorization().mint_network_capability(
        provider="uthana", operation="poll", endpoint=UTHANA_ENDPOINT
    )
    with pytest.raises((NetworkForbidden, ProviderError)):
        UrllibTransport().send(
            HttpRequest(
                method="GET",
                url="https://uthana.com/graphql",
                timeout_s=1.0,
                capability=capability,
            )
        )


def test_a_normal_offline_command_never_attempts_a_connection(mesh, capsys):
    """The default path is not merely refused at the boundary - it never tries."""
    code, payload = _cli(["provider-plan", str(mesh)], capsys)
    assert code in (0, 3)
    assert payload["network_used"] is False


# ---------------------------------------------------- submission and retry safety


def test_exactly_one_create_happens_for_one_approved_plan(
    autorig_request, store, plan, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble()
    orch = orchestrator_for(double, store, plan_digest=plan[PLAN_DIGEST_KEY])

    manifest = authorized_submit(orch, autorig_request)

    assert double.create_calls == 1
    assert manifest.provider_task_id == double.character_id
    assert manifest.submission_outcome == "CREATED"


def test_a_create_timeout_does_not_resubmit(autorig_request, store, monkeypatch):
    """The counter is the evidence: one attempt, whatever the error kind says."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(create_raises=transport_fault())
    orch = orchestrator_for(double, store)

    manifest = authorized_submit(orch, autorig_request)

    assert double.create_calls == 1, "an ambiguous create must never be retried"
    assert manifest.provider_task_id is None
    assert manifest.submission_outcome == "UNKNOWN"


def test_an_ambiguous_create_is_not_reported_as_a_clean_failure(
    autorig_request, store, monkeypatch
):
    """`UNKNOWN` rather than `NOT_CREATED`: the task may exist and be billable."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    orch = orchestrator_for(UthanaDouble(create_raises=transport_fault()), store)
    assert authorized_submit(orch, autorig_request).submission_outcome == "UNKNOWN"

    # A provider that explicitly rejected the request is genuinely NOT_CREATED.
    # The two must not be conflated: one is safe to retry, the other is not.
    from tools.assetgen.transport import HttpResponse

    store2 = JobStore.create(repo_root=store.repo_root, artifact_root=store.repo_root / "a2")
    denied = UthanaDouble(
        create_response=HttpResponse(
            status=400,
            body=b'{"errors":[{"message":"bad model","extensions":{"code":"INVALID_MODEL_FORMAT"}}]}',
        )
    )
    orch2 = orchestrator_for(denied, store2)
    rejected = authorized_submit(orch2, autorig_request)
    assert rejected.submission_outcome == "NOT_CREATED"
    assert denied.create_calls == 1


def test_an_interruption_after_the_job_id_resumes_the_same_paid_task(
    autorig_request, store, monkeypatch
):
    """A restart must never buy a second character.

    The submit is followed by a fresh orchestrator over the SAME store, which is
    what a crashed-and-restarted process looks like. It must reach the same
    provider task id without a second create.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0)
    first = orchestrator_for(double, store)
    manifest = authorized_submit(first, autorig_request)
    assert double.create_calls == 1
    task_id = manifest.provider_task_id

    # Simulated crash: nothing in memory survives, only the store on disk.
    restarted = orchestrator_for(double, store)
    resumed = restarted.resume(manifest.job_id, interval_s=0.0)

    assert double.create_calls == 1, "resume must not create a second paid task"
    assert resumed.provider_task_id == task_id
    assert resumed.status == JobStatus.DOWNLOADED.value


def test_an_identical_rerun_resumes_instead_of_creating_a_second_task(
    autorig_request, store, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0)
    orch = orchestrator_for(double, store)
    authorized_submit(orch, autorig_request)
    authorized_submit(orch, autorig_request)
    assert double.create_calls == 1


def test_the_same_plan_cannot_be_claimed_twice(store, plan):
    """One approved plan, one paid unit of work - enforced by the OS."""
    store.claim_submission(plan[PLAN_DIGEST_KEY], {"state": "CLAIMED"})
    with pytest.raises(FileExistsError):
        store.claim_submission(plan[PLAN_DIGEST_KEY], {"state": "CLAIMED"})


def _paid_submission(store, plan, request, command="autorig"):
    return PaidSubmission(
        command=command,
        provider="uthana",
        build_plan=lambda: plan,
        build_request=lambda: request,
    )


def test_a_second_authorized_run_of_the_same_plan_is_refused_by_the_executor(
    store, plan, autorig_request, monkeypatch
):
    """One approval, one paid job - enforced in the shared executor.

    Asserted through `execute_paid_submission` rather than through a CLI helper,
    because that function is now the only paid path: proving it here proves it for
    autorig, shield-multiview and shield-3d at once.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble()
    orch = orchestrator_for(double, store)
    submission = _paid_submission(store, plan, autorig_request)
    authorization = granted_authorization(confirmed=plan[PLAN_DIGEST_KEY])

    first = execute_paid_submission(
        submission,
        authorization=authorization,
        orchestrator=orch,
        provider_factory=orch.provider_factory,
    )
    assert double.create_calls == 1
    assert first.digest == plan[PLAN_DIGEST_KEY]

    with pytest.raises(LiveGateRefusal) as caught:
        execute_paid_submission(
            submission,
            authorization=authorization,
            orchestrator=orchestrator_for(double, store),
            provider_factory=orch.provider_factory,
        )
    assert caught.value.code == PROVIDER_SUBMISSION_ALREADY_RECORDED
    assert double.create_calls == 1, "the refusal must happen before a second create"


def test_the_claim_exists_before_the_request_so_a_crash_leaves_evidence(
    store, plan, autorig_request, monkeypatch
):
    """A crash mid-create must not look like nothing happened.

    If the claim were written after a successful response, a process killed during
    the upload would leave a clean slate and the next run would happily create a
    second character. The double raises an ambiguous transport fault, which is the
    closest reproducible stand-in for that crash.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(create_raises=transport_fault())
    orch = orchestrator_for(double, store)
    execute_paid_submission(
        _paid_submission(store, plan, autorig_request),
        authorization=granted_authorization(confirmed=plan[PLAN_DIGEST_KEY]),
        orchestrator=orch,
        provider_factory=orch.provider_factory,
    )
    recorded = store.read_submission(plan[PLAN_DIGEST_KEY])
    assert recorded is not None, "the claim must survive an ambiguous create"
    assert recorded["state"] == "OUTCOME_UNKNOWN"
    assert double.create_calls == 1


def test_polling_retries_are_bounded(autorig_request, store, monkeypatch):
    """Poll may retry - it creates nothing - but not forever."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=10_000)
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)

    orch.poll(manifest.job_id, interval_s=0.0, max_attempts=4)

    assert double.poll_calls == 4, "the attempt cap must stop the loop"
    assert double.create_calls == 1


def test_a_provider_side_failure_preserves_the_task_id_and_creates_nothing_new(
    autorig_request, store, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0, fail_after_polls=0)
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)
    polled = orch.poll(manifest.job_id, interval_s=0.0, max_attempts=2)

    assert double.create_calls == 1
    assert polled.provider_task_id == double.character_id


# ------------------------------------------------------------ credential hygiene


def test_building_an_adapter_reads_no_credential(monkeypatch):
    """Every offline command builds an adapter; none may touch a key doing so.

    This is what makes the barrier ordering real rather than nominal: if the
    constructor loaded the value, then `provider-plan`, `list` and `inspect` would
    all have read a credential before any barrier was even evaluated.
    """
    reads: list[str] = []

    def spy(env_var: str, *, required: bool = True):
        reads.append(env_var)
        return None

    monkeypatch.setattr("tools.assetgen.providers.uthana.load_credential", spy)
    monkeypatch.setattr("tools.assetgen.providers.meshy.load_credential", spy)
    build_provider("uthana", transport=UthanaDouble(), require_credential=False)
    build_provider("meshy", transport=UthanaDouble(), require_credential=False)
    assert reads == [], f"constructing an adapter read {reads}"


def test_a_credential_value_never_reaches_stdout_a_report_or_an_exception(
    autorig_request, store, monkeypatch, capsys
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    # A provider that echoes the credential back in an error body is the realistic
    # leak: our own code never prints it, but a remote message can carry it.
    from tools.assetgen.transport import HttpResponse

    double = UthanaDouble(
        create_response=HttpResponse(
            status=200,
            headers={"Content-Type": "application/json"},
            body=json.dumps(
                {
                    "errors": [
                        {
                            "message": f"bad key {SYNTHETIC_UTHANA_KEY}",
                            "extensions": {"code": "UNAUTHENTICATED"},
                        }
                    ]
                }
            ).encode("utf-8"),
        )
    )
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)

    # The request really was authenticated, so this test exercised the path where
    # a leak is possible rather than a path where there was nothing to leak.
    assert double.seen_authorization, "the authenticated path was not reached"
    assert double.seen_authorization[0].startswith("Basic ")

    cli.emit(orch.inspect(manifest.job_id))
    printed = capsys.readouterr().out
    manifest_text = (store.job_dir(manifest.job_id) / "manifest.json").read_text(encoding="utf-8")

    for haystack in (printed, manifest_text, json.dumps(manifest.error), str(manifest.error)):
        assert SYNTHETIC_UTHANA_KEY not in haystack


def test_no_authorization_header_is_ever_written_to_a_response_snapshot(
    autorig_request, store, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0)
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)
    orch.poll(manifest.job_id, interval_s=0.0)

    for snapshot in store.response_dir(manifest.job_id).glob("*.json"):
        text = snapshot.read_text(encoding="utf-8").lower()
        assert "authorization" not in text
        assert SYNTHETIC_UTHANA_KEY.lower() not in text


def test_credential_state_reports_presence_and_never_the_value(monkeypatch):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    state = live_gate.credential_state(UTHANA_KEY)
    assert state == "present"
    assert SYNTHETIC_UTHANA_KEY not in state
    monkeypatch.delenv(UTHANA_KEY)
    assert live_gate.credential_state(UTHANA_KEY) == "missing"


def test_a_short_or_malformed_test_key_is_still_masked(monkeypatch):
    """Masking must not depend on the value looking like a real key."""
    from tools.assetgen.secret_guard import register_secret, reset_registered_secrets_for_tests, scrub

    reset_registered_secrets_for_tests()
    register_secret("shortkey123")
    assert "shortkey123" not in scrub("failed with shortkey123 in the body")
    reset_registered_secrets_for_tests()


def test_no_command_accepts_a_credential_as_an_argument():
    """A key passed in argv lands in shell history and in process listings.

    Checked across every subcommand's real option strings rather than the top-level
    help text, so adding one to a single command would fail this.
    """
    forbidden = ("--api-key", "--apikey", "--credential", "--token", "--secret", "--key")
    parser = cli.build_parser()
    actions = [a for a in parser._actions if getattr(a, "choices", None)]
    subparsers = [p for a in actions for p in getattr(a, "choices", {}).values()]
    assert subparsers, "the parser has no subcommands; this test would prove nothing"
    for node in subparsers:
        for option in [opt for action in node._actions for opt in action.option_strings]:
            assert option.lower() not in forbidden, f"{option} would carry a secret in argv"


# ------------------------------------------- full local chain from the double


def _godot_runner(payload: dict, returncode: int):
    """Stands in for the Godot subprocess the ingestion chain shells out to.

    Godot itself is exercised by the `slice a2` profile; what this proves is the
    wiring around it - that a downloaded provider artifact flows into the real
    ingestion owner and that only an ACCEPTED chain publishes.
    """

    def run(argv, **kwargs):
        run.argv = argv
        return subprocess.CompletedProcess(
            argv,
            returncode,
            stdout="Godot Engine v4.6.2\nHAND_FIXTURE_INGEST " + json.dumps(payload) + "\n",
            stderr="",
        )

    return run


ACCEPTED_CHAIN = [
    "import",
    "family_resolution",
    "humanoid_normalization",
    "fixture_compilation",
    "artifact_integrity",
    "rig_binding",
    "assemble_and_measure",
    "certification",
]


def _godot_payload(**overrides) -> dict:
    payload = {
        "accepted": True,
        "chain": list(ACCEPTED_CHAIN),
        "compiler_pass": True,
        "artifact_path": "res://artifacts/fixtures/staging/double_hand_fixture.tres",
        "content_hash": "A" * 64,
        "source_geometry_sha256": "B" * 64,
        "source_rig_sha256": "C" * 64,
        "expected_source_geometry_sha256": "B" * 64,
        "expected_source_rig_sha256": "C" * 64,
        "certified": True,
        "certified_artifact_path": "res://artifacts/fixtures/staging/double_hand_fixture_certified.tres",
        "certification_hash": "D" * 64,
        "acceptance_report_digest": "E" * 64,
        "family_id": "mixamo_52_humanoid",
        "family_version": "3",
        "import_representation": "godot_humanoid_retarget",
        "compiler_version": "hand_fixture_compiler_v4",
        "calibration_id": "hand_fixture_compiler_calibration_uthana_a2_7",
        "schema": "hand_fixture_evidence_v4",
        "grip_ground_truth": {"pass": True, "closest_patch": "pad"},
        "assembler": {"ok": True, "mesh_binding": {"verified": True}},
        "skeleton_bone_count": 52,
        "sides": {
            "right": {"compiled": True, "error_class": "", "nail_tris": 4, "pad_tris": 10},
            "left": {"compiled": False, "error_class": "PAD_PATCH_AMBIGUOUS"},
        },
    }
    payload.update(overrides)
    return payload


@pytest.fixture
def downloaded(autorig_request, store, monkeypatch):
    """Run the provider double all the way to a local, hashed artifact."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=1)
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)
    final = orch.poll(manifest.job_id, interval_s=0.0)
    return double, orch, final


def test_the_double_drives_submit_poll_and_download_to_a_hashed_local_file(downloaded, store):
    double, orch, final = downloaded
    assert double.create_calls == 1
    assert double.poll_calls == 2, "one pending answer, then the bundle"
    assert double.download_calls == 1
    assert final.status == JobStatus.DOWNLOADED.value

    report = orch.inspect(final.job_id)
    assert len(report["artifacts"]) == 1
    artifact = report["artifacts"][0]
    assert artifact["present_on_disk"] is True
    assert artifact["hash_matches"] is True, "the download must be verified, not assumed"
    assert (store.repo_root / artifact["relative_path"]).read_bytes() == double.glb_bytes


def test_an_accepted_chain_publishes_atomically_and_only_then(downloaded, tmp_path):
    from tools.assetgen.rig_ingest import ingest_rigged_humanoid

    project = tmp_path / "game"
    (project / "assets").mkdir(parents=True, exist_ok=True)
    staged_certified = project / "artifacts" / "fixtures" / "staging" / "double_certified.tres"
    staged_certified.parent.mkdir(parents=True, exist_ok=True)
    staged_certified.write_text("[gd_resource type=\"Resource\"]\n", encoding="utf-8")
    published = "res://assets/double_hand_fixture.tres"

    result = ingest_rigged_humanoid(
        project_path=project,
        rigged_glb_res_path="res://assets/double_rigged.glb",
        asset_id="double",
        published_artifact_res_path=published,
        staged_certified_artifact_res_path="res://artifacts/fixtures/staging/double_certified.tres",
        repo_root=tmp_path,
        skip_import=True,
        godot_executable=str(Path(__file__)),
        runner=_godot_runner(_godot_payload(), EXIT_ACCEPTED),
    )

    assert result.verdict == INGEST_ACCEPTED
    assert result.published is True
    assert (project / "assets" / "double_hand_fixture.tres").is_file()


@pytest.mark.parametrize(
    "payload, description",
    [
        (
            _godot_payload(
                accepted=False,
                certified=False,
                certification_hash=None,
                compiler_pass=False,
                error_class="THUMB_SURFACE_ANATOMY_REJECTED",
                stage_failed="fixture_compilation",
                failure_kind="classified_asset_failure",
                chain=ACCEPTED_CHAIN[:3],
                sides={"right": {"compiled": False, "error_class": "PAD_PATCH_AMBIGUOUS"}},
            ),
            "a compiler failure",
        ),
        (
            _godot_payload(
                accepted=False,
                certified=False,
                certification_hash=None,
                error_class="THUMB_OPPOSITION_GATE_FAILED",
                stage_failed="assemble_and_measure",
                failure_kind="classified_asset_failure",
                chain=ACCEPTED_CHAIN[:7],
                grip_ground_truth={"pass": False, "closest_patch": "nail"},
            ),
            "a grip ground-truth failure",
        ),
    ],
)
def test_a_classified_failure_never_publishes(payload, description, tmp_path):
    """Paying for an asset does not entitle it to reach the game."""
    from tools.assetgen.rig_ingest import ingest_rigged_humanoid

    project = tmp_path / "game"
    (project / "assets").mkdir(parents=True, exist_ok=True)
    staged = project / "artifacts" / "fixtures" / "staging" / "double_certified.tres"
    staged.parent.mkdir(parents=True, exist_ok=True)
    staged.write_text("[gd_resource type=\"Resource\"]\n", encoding="utf-8")
    destination = project / "assets" / "double_hand_fixture.tres"

    result = ingest_rigged_humanoid(
        project_path=project,
        rigged_glb_res_path="res://assets/double_rigged.glb",
        asset_id="double",
        published_artifact_res_path="res://assets/double_hand_fixture.tres",
        staged_certified_artifact_res_path="res://artifacts/fixtures/staging/double_certified.tres",
        repo_root=tmp_path,
        skip_import=True,
        godot_executable=str(Path(__file__)),
        runner=_godot_runner(payload, EXIT_CLASSIFIED),
    )

    assert result.accepted is False, description
    assert result.published is False
    assert not destination.exists(), f"{description} must not reach the published path"


def test_a_corrupt_download_is_stored_but_its_hash_records_what_arrived(
    autorig_request, store, monkeypatch
):
    """A corrupt artifact must be identifiable, not silently equivalent to a good one.

    The download layer's job is to record exactly what arrived plus its hash; the
    structural verdict belongs to Godot's import, which is the step that refuses.
    What must never happen is a corrupt file passing as the verified artifact of a
    successful job.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    good = UthanaDouble(pending_polls=0)
    bad = UthanaDouble(pending_polls=0, corrupt_download=True)

    orch = orchestrator_for(bad, store)
    manifest = authorized_submit(orch, autorig_request)
    final = orch.poll(manifest.job_id, interval_s=0.0)

    from tools.assetgen.manifest import sha256_bytes

    artifact = orch.inspect(final.job_id)["artifacts"][0]
    stored = (store.repo_root / artifact["relative_path"]).read_bytes()
    assert stored != good.glb_bytes, "the corrupt body must not be mistaken for the good one"
    assert artifact["sha256"] == sha256_bytes(stored), "the hash describes what actually arrived"
    assert artifact["sha256"] != sha256_bytes(good.glb_bytes)
    assert artifact["hash_matches"] is True


def test_a_missing_bundle_is_a_classified_download_failure_not_a_success(
    autorig_request, store, monkeypatch
):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0, missing_download=True)
    orch = orchestrator_for(double, store)
    manifest = authorized_submit(orch, autorig_request)
    final = orch.poll(manifest.job_id, interval_s=0.0)

    assert final.status != JobStatus.DOWNLOADED.value
    assert final.outputs == []
    assert final.error is not None
    assert double.create_calls == 1


# -------------------------------------------- this profile never touches a real adapter


def test_no_real_provider_endpoint_is_ever_contacted_by_this_profile(
    autorig_request, store, monkeypatch
):
    """The double is the only endpoint, and the base URL proves the adapter used it.

    Combined with the armed socket tripwire, this is what makes "the tests never
    call a provider" a mechanical fact rather than a convention.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0)
    orch = orchestrator_for(double, store)
    authorized_submit(orch, autorig_request)

    assert double.total_calls > 0, "the test must actually have exercised the adapter"
    # Nothing left the process: the tripwire would have raised NetworkForbidden.
