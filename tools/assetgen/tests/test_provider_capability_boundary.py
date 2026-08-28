"""Regressions for every BLOCKER and HIGH the forensic review measured.

Each test here names the finding it closes. They are written the way the review
measured the defects rather than the way the fix is structured, so a future
refactor that reintroduces a defect fails these tests even if it satisfies the new
code's own internal expectations.

TWO RULES, SAME AS THE OTHER BARRIER SUITE:

* Count at the OUTBOUND BOUNDARY. `transport.sent == []` is evidence. A refusal
  that is only reported is not: the review found `auth-smoke --live` reporting
  correctly-shaped JSON while a request had already gone out.
* Assert the exact refusal CODE. "It refused somewhere" would keep passing if the
  ordering regressed and, say, a credential were read before authorization.
"""

from __future__ import annotations

import base64
import contextlib
import json
import os
from pathlib import Path

import pytest

from tools.assetgen import capability as capability_module
from tools.assetgen import cli, command_risk
from tools.assetgen.artifact_paths import (
    UNSAFE_OUTPUT_PATH,
    UnsafeOutputPath,
    resolve_within,
    trusted_artifact_name,
)
from tools.assetgen.capability import (
    CAPABILITY_ALREADY_CONSUMED,
    CAPABILITY_CLASS_INSUFFICIENT,
    CAPABILITY_INVALID,
    CAPABILITY_REQUIRED,
    CAPABILITY_SCOPE_MISMATCH,
    CapabilityRefused,
    OperationClass,
    ProviderCapability,
)
from tools.assetgen.command_risk import COMMAND_RISK, UnclassifiedCommand
from tools.assetgen.endpoint import EndpointRefused, parse_endpoint
from tools.assetgen.errors import ErrorKind, ProviderError
from tools.assetgen.live_gate import (
    LIVE_PROVIDER_MODE_REQUIRED,
    OPT_IN_ENV_VAR,
    OPT_IN_REQUIRED_VALUE,
    PAID_PROVIDER_OPT_IN_REQUIRED,
    PROVIDER_ENDPOINT_INSECURE,
    PROVIDER_ENDPOINT_NOT_APPROVED,
    PROVIDER_SUBMISSION_OUTCOME_UNKNOWN,
    LiveGateRefusal,
)
from tools.assetgen.orchestrator import JobOrchestrator
from tools.assetgen.paid_executor import PaidSubmission, execute_paid_submission
from tools.assetgen.provider_plan import PLAN_DIGEST_KEY, build_plan, plan_digest
from tools.assetgen.providers import build_provider
from tools.assetgen.providers.base import ImageInput, JobRequest, TaskType
from tools.assetgen.providers.uthana import CREDENTIAL_ENV_VAR as UTHANA_KEY
from tools.assetgen.providers.uthana import DEFAULT_BASE_URL as UTHANA_BASE
from tools.assetgen.secret_guard import (
    REDACTED,
    redact_headers,
    register_secret,
    reset_registered_secrets_for_tests,
    scrub,
    scrub_obj,
)
from tools.assetgen.store import JobStore
from tools.assetgen.tests.authorization_support import granted_authorization
from tools.assetgen.tests.multipart_oracle import MultipartProtocolError, read_graphql_upload
from tools.assetgen.tests.provider_double import UthanaDouble, synthetic_glb_bytes
from tools.assetgen.transport import HttpRequest, HttpResponse, RetryPolicy, UrllibTransport

SYNTHETIC_UTHANA_KEY = "uth_synthetic_test_key_0123456789abcdef"
UTHANA_ENDPOINT = parse_endpoint("uthana", UTHANA_BASE)


# ---------------------------------------------------------------------- fixtures


class CountingTransport:
    """Counts at the real outbound boundary and answers nothing.

    Any request that reaches `send` WOULD have left the process in production. The
    review used exactly this instrument to prove that commands which reported a
    refusal had already sent something.
    """

    def __init__(self) -> None:
        self.sent: list[HttpRequest] = []

    def send(self, request: HttpRequest) -> HttpResponse:
        self.sent.append(request)
        raise AssertionError(
            f"an outbound request escaped: {request.method} {request.url}. "
            "Nothing in this suite may reach a provider."
        )


@pytest.fixture
def mesh(tmp_path: Path) -> Path:
    path = tmp_path / "candidate.glb"
    path.write_bytes(synthetic_glb_bytes())
    return path


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


def executable_plan(mesh: Path, repo_root: Path, **overrides) -> dict:
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


def orchestrator_over(transport, store: JobStore, **kwargs) -> JobOrchestrator:
    cache: dict = {}

    def factory(name: str):
        if name not in cache:
            cache[name] = build_provider(
                name,
                transport=transport,
                retry_policy=RetryPolicy(max_attempts=3, base_delay_s=0.0, max_delay_s=0.0),
                require_credential=False,
            )
        return cache[name]

    defaults = {"authorization": granted_authorization(), "sleep": lambda _s: None}
    defaults.update(kwargs)
    return JobOrchestrator(store=store, provider_factory=factory, **defaults)


def cli_run(argv: list[str], capsys) -> tuple[int, dict]:
    code = cli.main(argv)
    return code, json.loads(capsys.readouterr().out)


class _WatchedEnvironment(dict):
    """A stand-in for `os.environ` that records lookups of watched names.

    The point is to observe the ENVIRONMENT ACCESS itself rather than one loader
    function. Review MEDIUM 12 noted that patching `load_credential` proves only
    that a single function was not called; a future adapter that reads
    `os.environ[...]` directly - which is exactly the sabotage the repair brief
    asks us to detect - would sail past that. Every read route a caller could
    plausibly use is recorded here.
    """

    def __init__(self, source, watched: tuple[str, ...], reads: list[str]) -> None:
        super().__init__(source)
        self._watched = watched
        self._reads = reads

    def _note(self, key) -> None:
        if key in self._watched:
            self._reads.append(str(key))

    def __getitem__(self, key):
        self._note(key)
        return super().__getitem__(key)

    def get(self, key, default=None):
        self._note(key)
        return super().get(key, default)

    def setdefault(self, key, default=None):
        self._note(key)
        return super().setdefault(key, default)

    def pop(self, key, *args):
        self._note(key)
        return super().pop(key, *args)


@contextlib.contextmanager
def watching_environment(*watched: str):
    """Replace `os.environ` with a recorder for the duration of the block.

    `os.getenv`, `os.environ.get` and subscript access all resolve through
    `os.environ` at call time, so swapping the object catches all of them. The
    real environment is restored unconditionally, and nothing inside a `with`
    block may spawn a subprocess that relies on inherited variables.
    """
    reads: list[str] = []
    real = os.environ
    spy = _WatchedEnvironment(real, watched, reads)
    os.environ = spy  # type: ignore[assignment]
    try:
        yield reads
    finally:
        os.environ = real  # type: ignore[assignment]


# ------------------------------------------------- BLOCKER 1: auth-smoke bypass


def test_auth_smoke_with_only_live_reaches_neither_credential_nor_network(
    monkeypatch, capsys
):
    """BLOCKER 1. The review measured a real request here with `--live` alone."""
    transport = CountingTransport()
    monkeypatch.setattr(cli, "UrllibTransport", lambda: transport)
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkeypatch.delenv(OPT_IN_ENV_VAR, raising=False)

    code, payload = cli_run(["--live", "auth-smoke", "--providers", "uthana"], capsys)

    assert transport.sent == [], "auth-smoke must not reach the network without the opt-in"
    result = payload["results"][0]
    assert result["refused"] == PAID_PROVIDER_OPT_IN_REQUIRED
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(payload)
    assert code == 0


def test_auth_smoke_without_live_refuses_for_the_flag_not_the_key(monkeypatch, capsys):
    transport = CountingTransport()
    monkeypatch.setattr(cli, "UrllibTransport", lambda: transport)
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkeypatch.setenv(OPT_IN_ENV_VAR, OPT_IN_REQUIRED_VALUE)

    _code, payload = cli_run(["auth-smoke", "--providers", "uthana"], capsys)

    assert transport.sent == []
    assert payload["results"][0]["refused"] == LIVE_PROVIDER_MODE_REQUIRED


def test_a_read_only_probe_refuses_before_the_adapter_can_read_a_credential(monkeypatch):
    """The refusal precedes credential access, observed on `os.environ` itself.

    Patching `load_credential` would only prove that ONE function was not called.
    Watching the environment lookup proves the value was never materialised by any
    route, which is what review MEDIUM 12 asked for.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    with watching_environment(UTHANA_KEY) as reads:
        provider = build_provider(
            "uthana", transport=CountingTransport(), require_credential=False
        )
        assert reads == [], f"adapter construction read the credential via {reads}"
        with pytest.raises(CapabilityRefused) as caught:
            provider.auth_smoke(None)
        assert caught.value.code == CAPABILITY_REQUIRED
        assert reads == [], f"a refused probe read the credential via {reads}"


def test_offline_planning_never_materialises_a_credential_value(monkeypatch, mesh, tmp_path):
    """A plan names the variables it will need; it must never look inside them."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    with watching_environment(UTHANA_KEY) as reads:
        plan = executable_plan(mesh, tmp_path)
    assert UTHANA_KEY in plan["credentials"]["env_vars"]
    assert reads == [], f"offline planning read the credential via {reads}"
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(plan)


def test_every_refused_live_permutation_leaves_the_credential_unread(monkeypatch, capsys):
    """Barriers 1 and 2 both refuse strictly before any environment value access."""
    transport = CountingTransport()
    monkeypatch.setattr(cli, "UrllibTransport", lambda: transport)
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    for argv, opt_in in (
        (["auth-smoke", "--providers", "uthana"], None),
        (["--live", "auth-smoke", "--providers", "uthana"], None),
        (["--live", "auth-smoke", "--providers", "uthana"], "true"),
        (["--live", "auth-smoke", "--providers", "uthana"], "0"),
        (["auth-smoke", "--providers", "uthana"], OPT_IN_REQUIRED_VALUE),
    ):
        if opt_in is None:
            monkeypatch.delenv(OPT_IN_ENV_VAR, raising=False)
        else:
            monkeypatch.setenv(OPT_IN_ENV_VAR, opt_in)
        with watching_environment(UTHANA_KEY) as reads:
            cli.main(argv)
            capsys.readouterr()
            assert reads == [], f"{argv} with opt-in {opt_in!r} read the credential"
        assert transport.sent == []


# ------------------------------------- BLOCKER 2: paid Meshy without plan/claim


@pytest.mark.parametrize("command", sorted(command_risk.paid_commands()))
def test_every_paid_command_declares_the_paid_class_and_offers_confirm_plan(command):
    """BLOCKER 2. `--confirm-plan` existed only on autorig, so only autorig could be
    asked to confirm anything. All three must expose barrier 3 identically."""
    assert COMMAND_RISK[command] is OperationClass.PAID_CREATE
    parser = cli.build_parser()
    subparsers = [
        node
        for action in parser._actions
        for node in (getattr(action, "choices", None) or {}).values()
    ]
    node = next(n for n in subparsers if n.prog.endswith(command))
    options = {opt for action in node._actions for opt in action.option_strings}
    assert "--confirm-plan" in options
    assert "--submit" in options


def test_a_paid_meshy_submit_without_a_confirmed_plan_sends_nothing(
    monkeypatch, tmp_path, capsys
):
    """The exact scenario the review executed: two barriers, no plan, paid create."""
    transport = CountingTransport()
    monkeypatch.setattr(cli, "UrllibTransport", lambda: transport)
    monkeypatch.setenv("MESHY_API_KEY", "msy_synthetic_test_key_00000000000000")
    monkeypatch.setenv(OPT_IN_ENV_VAR, OPT_IN_REQUIRED_VALUE)
    reference = tmp_path / "shield_front.png"
    reference.write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 64)

    code, payload = cli_run(
        ["--live", "shield-multiview", "--front", str(reference), "--submit"], capsys
    )

    assert transport.sent == [], "a paid Meshy create escaped without a confirmed plan"
    assert code == 4
    assert payload["error"] in {
        "PROVIDER_PLAN_CONFIRMATION_REQUIRED",
        "PROVIDER_PLAN_NOT_EXECUTABLE",
    }


def test_all_three_paid_commands_go_through_the_one_executor():
    """Structural: no paid command may keep a private submit path.

    Asserted on the source of `cli.py` because the property is about which function
    the commands CALL, and a behavioural test would need three live-ish runs to say
    the same thing less clearly.
    """
    source = Path(cli.__file__).read_text(encoding="utf-8")
    assert source.count("run_paid_command(") == 1 + len(command_risk.paid_commands())
    # `orchestrator.submit(` must not appear in any command body: the executor is
    # the only caller.
    assert "orchestrator.submit(" not in source
    assert "orch.submit(" not in source


# ------------------------------------------- BLOCKER 4 / HIGH 4: capability boundary


def test_a_direct_orchestrator_paid_submit_without_a_capability_refuses(
    autorig_request, store
):
    """HIGH 4. `JobOrchestrator(live=True, opt_in=True).submit(...)` used to build a
    paid request with no plan and no claim. There are no such booleans now, and the
    ticket is mandatory."""
    transport = CountingTransport()
    orch = orchestrator_over(transport, store)
    with pytest.raises(CapabilityRefused) as caught:
        orch.submit(autorig_request)
    assert caught.value.code == CAPABILITY_REQUIRED
    assert transport.sent == []


def test_a_direct_provider_submit_without_a_capability_refuses(autorig_request):
    transport = CountingTransport()
    provider = build_provider("uthana", transport=transport, require_credential=False)
    with pytest.raises(CapabilityRefused) as caught:
        provider.submit(autorig_request)
    assert caught.value.code == CAPABILITY_REQUIRED
    assert transport.sent == []


def test_the_production_transport_refuses_an_unauthorized_request():
    """The lowest boundary this repository owns."""
    with pytest.raises(CapabilityRefused) as caught:
        UrllibTransport().send(HttpRequest(method="GET", url="https://uthana.com/graphql"))
    assert caught.value.code == CAPABILITY_REQUIRED


def test_a_hand_built_capability_is_not_a_capability(autorig_request):
    """A dataclass with the right fields is not authorization.

    Honest about what this proves: it stops an alternative repository call path from
    fabricating authority, not a hostile process that imports the private mint
    token. That distinction is documented in `capability.py`.
    """
    forged = ProviderCapability(
        operation_class=OperationClass.PAID_CREATE,
        provider="uthana",
        operation="character_autorig",
        endpoint=UTHANA_ENDPOINT,
        plan_digest="0" * 64,
        claim_id="forged",
    )
    transport = CountingTransport()
    provider = build_provider("uthana", transport=transport, require_credential=False)
    with pytest.raises(CapabilityRefused) as caught:
        provider.submit(autorig_request, forged)
    assert caught.value.code == CAPABILITY_INVALID
    assert transport.sent == []


def test_a_network_read_capability_cannot_create_paid_work(autorig_request):
    read_only = granted_authorization().mint_network_capability(
        provider="uthana", operation="character_autorig", endpoint=UTHANA_ENDPOINT
    )
    transport = CountingTransport()
    provider = build_provider("uthana", transport=transport, require_credential=False)
    with pytest.raises(CapabilityRefused) as caught:
        provider.submit(autorig_request, read_only)
    assert caught.value.code == CAPABILITY_CLASS_INSUFFICIENT
    assert transport.sent == []


def test_the_network_barriers_alone_cannot_mint_a_paid_capability():
    with pytest.raises(LiveGateRefusal):
        granted_authorization().mint_network_capability(
            provider="uthana",
            operation="character_autorig",
            endpoint=UTHANA_ENDPOINT,
            operation_class=OperationClass.PAID_CREATE,
        )


def test_a_paid_capability_cannot_be_minted_without_a_plan_and_a_claim(mesh, tmp_path):
    plan = executable_plan(mesh, tmp_path)
    authorization = granted_authorization(confirmed=plan[PLAN_DIGEST_KEY])
    with pytest.raises(LiveGateRefusal) as caught:
        authorization.mint_paid_capability(plan=plan, endpoint=UTHANA_ENDPOINT, claim_id="")
    assert caught.value.code == "PROVIDER_SUBMISSION_CLAIM_REQUIRED"


def test_a_capability_for_one_operation_does_not_authorize_another(autorig_request):
    poll_ticket = granted_authorization().mint_network_capability(
        provider="uthana", operation="poll", endpoint=UTHANA_ENDPOINT
    )
    transport = CountingTransport()
    provider = build_provider("uthana", transport=transport, require_credential=False)
    with pytest.raises(CapabilityRefused) as caught:
        provider.download("https://uthana.com/motion/bundle/x/character.glb", Path("x"), poll_ticket)
    assert caught.value.code == CAPABILITY_SCOPE_MISMATCH
    assert transport.sent == []


def test_the_same_paid_capability_cannot_be_used_twice(autorig_request, store, monkeypatch):
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble()
    orch = orchestrator_over(double, store)
    plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
    )
    digest = plan_digest(plan)
    claim = store.claim_submission(digest, {"plan_sha256": digest, "state": "CLAIMED"})
    ticket = granted_authorization(confirmed=digest).mint_paid_capability(
        plan=plan, endpoint=UTHANA_ENDPOINT, claim_id=str(claim)
    )

    orch.submit(autorig_request, capability=ticket)
    assert double.create_calls == 1

    with pytest.raises(CapabilityRefused) as caught:
        orch.submit(autorig_request, capability=ticket, force_new_attempt=True)
    assert caught.value.code == CAPABILITY_ALREADY_CONSUMED
    assert double.create_calls == 1


# -------------------------------------------------- HIGH 5: UNKNOWN is universal


def test_an_unknown_outcome_refuses_a_second_create_for_the_same_identity(
    autorig_request, store, monkeypatch
):
    """HIGH 5. The review measured create_calls going 1 -> 2 across this boundary:
    the ambiguity was recorded and then nothing consulted it."""
    from tools.assetgen.tests.provider_double import transport_fault

    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    ambiguous = UthanaDouble(create_raises=transport_fault())
    orch = orchestrator_over(ambiguous, store)
    plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
    )
    submission = PaidSubmission(
        command="autorig",
        provider="uthana",
        build_plan=lambda: plan,
        build_request=lambda: autorig_request,
    )
    authorization = granted_authorization(confirmed=plan[PLAN_DIGEST_KEY])
    execute_paid_submission(
        submission,
        authorization=authorization,
        orchestrator=orch,
        provider_factory=orch.provider_factory,
    )
    assert ambiguous.create_calls == 1

    # A brand-new run over the same store, with a brand-new plan and claim, so the
    # ledger's "already claimed" refusal cannot be what stops it. The UNKNOWN
    # manifest must.
    fresh = orchestrator_over(ambiguous, store)
    other_plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
        output_destination="artifacts/assetgen/jobs/y/outputs/rigged.glb",
    )
    other_digest = plan_digest(other_plan)
    claim = store.claim_submission(other_digest, {"plan_sha256": other_digest, "state": "CLAIMED"})
    ticket = granted_authorization(confirmed=other_digest).mint_paid_capability(
        plan=other_plan, endpoint=UTHANA_ENDPOINT, claim_id=str(claim)
    )
    with pytest.raises(LiveGateRefusal) as caught:
        fresh.submit(autorig_request, capability=ticket)
    assert caught.value.code == PROVIDER_SUBMISSION_OUTCOME_UNKNOWN
    assert ambiguous.create_calls == 1, "an UNKNOWN identity must never be resubmitted"


def test_concurrent_commands_for_one_approved_plan_create_exactly_once(
    autorig_request, store, monkeypatch
):
    """Two processes are simulated by two orchestrators over one store; the O_EXCL
    claim is what makes the second one lose, and it must lose BEFORE the create."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble()
    plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
    )
    submission = PaidSubmission(
        command="autorig",
        provider="uthana",
        build_plan=lambda: plan,
        build_request=lambda: autorig_request,
    )
    authorization = granted_authorization(confirmed=plan[PLAN_DIGEST_KEY])
    outcomes = []
    for _ in range(2):
        orch = orchestrator_over(double, store)
        try:
            execute_paid_submission(
                submission,
                authorization=authorization,
                orchestrator=orch,
                provider_factory=orch.provider_factory,
            )
            outcomes.append("submitted")
        except LiveGateRefusal as exc:
            outcomes.append(exc.code)
    assert double.create_calls == 1
    assert outcomes[0] == "submitted"
    assert outcomes[1] == "PROVIDER_SUBMISSION_ALREADY_RECORDED"


def test_the_ledger_records_a_claim_for_every_paid_command(store, mesh, tmp_path):
    """All three paid commands acquire the SAME kind of claim, in one place.

    Proved by observing that the shared executor is the only thing that claims, and
    that its claim shape carries the command name - so a new paid command cannot
    invent its own ledger.
    """
    plan = executable_plan(mesh, store.repo_root)
    digest = plan_digest(plan)
    double = UthanaDouble()
    orch = orchestrator_over(double, store)
    request = JobRequest(
        provider="uthana",
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=mesh),),
        parameters={"name": "x", "auto_rig": True, "include_fingers": True},
        label="humanoid_autorig",
    )
    os.environ[UTHANA_KEY] = SYNTHETIC_UTHANA_KEY
    try:
        execute_paid_submission(
            PaidSubmission(
                command="autorig",
                provider="uthana",
                build_plan=lambda: plan,
                build_request=lambda: request,
            ),
            authorization=granted_authorization(confirmed=digest),
            orchestrator=orch,
            provider_factory=orch.provider_factory,
        )
    finally:
        os.environ.pop(UTHANA_KEY, None)
    record = store.read_submission(digest)
    assert record["command"] == "autorig"
    assert record["endpoint"] == UTHANA_ENDPOINT.canonical
    assert record["state"] == "CREATED"


# ------------------------------------------------- HIGH 6: endpoint is approved


def test_changing_the_provider_base_url_changes_the_plan_digest(mesh, tmp_path):
    """HIGH 6. The review changed `UTHANA_API_BASE` and the digest did not move."""
    approved = executable_plan(mesh, tmp_path)
    moved = executable_plan(
        mesh, tmp_path, endpoint=parse_endpoint("uthana", "https://evil.example.test")
    )
    assert moved[PLAN_DIGEST_KEY] != approved[PLAN_DIGEST_KEY]


def test_an_approval_does_not_survive_a_moved_endpoint(mesh, tmp_path):
    plan = executable_plan(mesh, tmp_path)
    authorization = granted_authorization(confirmed=plan[PLAN_DIGEST_KEY])
    with pytest.raises(LiveGateRefusal) as caught:
        authorization.mint_paid_capability(
            plan=plan,
            endpoint=parse_endpoint("uthana", "https://evil.example.test"),
            claim_id="claim",
        )
    assert caught.value.code == PROVIDER_ENDPOINT_NOT_APPROVED


def test_live_traffic_requires_https(mesh, tmp_path):
    insecure = parse_endpoint("uthana", "http://uthana.com", require_https=False)
    with pytest.raises(LiveGateRefusal) as caught:
        granted_authorization().mint_network_capability(
            provider="uthana", operation="poll", endpoint=insecure
        )
    assert caught.value.code == PROVIDER_ENDPOINT_INSECURE


def test_an_insecure_base_url_is_refused_when_it_is_resolved():
    with pytest.raises(EndpointRefused) as caught:
        parse_endpoint("uthana", "http://uthana.com")
    assert caught.value.code == "PROVIDER_ENDPOINT_INSECURE"


def test_endpoint_normalisation_does_not_invent_differences():
    """A cosmetic change must not force a re-approval, and a real one must."""
    a = parse_endpoint("uthana", "https://Uthana.com:443/")
    b = parse_endpoint("uthana", "https://uthana.com")
    assert a == b
    assert parse_endpoint("uthana", "https://uthana.com:8443") != b
    assert parse_endpoint("uthana", "https://uthana.com/v2") != b


def test_an_authenticated_request_may_not_leave_the_approved_origin():
    capability = granted_authorization().mint_network_capability(
        provider="uthana", operation="download", endpoint=UTHANA_ENDPOINT
    )
    with pytest.raises(CapabilityRefused) as caught:
        UrllibTransport().send(
            HttpRequest(
                method="GET",
                url="https://elsewhere.example.test/bundle.glb",
                headers={"Authorization": "Basic Zm9vOg=="},
                capability=capability,
            )
        )
    assert caught.value.code == CAPABILITY_SCOPE_MISMATCH


def test_a_cross_host_redirect_is_refused_rather_than_followed():
    """urllib follows 3xx by default; the handler must refuse instead."""
    from tools.assetgen.transport import RefuseRedirects

    handler = RefuseRedirects()
    with pytest.raises(ProviderError) as caught:
        handler.redirect_request(
            None, None, 302, "Found", {}, "https://elsewhere.example.test/steal"
        )
    assert caught.value.kind is ErrorKind.CONTRACT


def test_environment_proxies_cannot_route_provider_traffic(monkeypatch):
    """MEDIUM 15. A loopback proxy is a permitted connection, so the tripwire would
    not have caught this: the transport must refuse to consult the variables."""
    import urllib.request

    monkeypatch.setenv("HTTPS_PROXY", "http://127.0.0.1:8888")
    monkeypatch.setenv("ALL_PROXY", "http://127.0.0.1:8888")

    # First prove the test is meaningful: stdlib default behaviour DOES see the
    # variable, so a passing assertion below is not vacuous.
    assert urllib.request.getproxies(), "the environment proxy was not visible at all"

    transport = UrllibTransport()
    configured = [
        getattr(handler, "proxies", None)
        for handler in transport._opener.handlers
        if getattr(handler, "proxies", None)
    ]
    assert configured == [], f"the transport would route through {configured}"


# ------------------------------------------- HIGH 3: provider-controlled paths


@pytest.mark.parametrize(
    "hostile",
    [
        "C:/Windows/Temp/EOM_ESCAPED.glb",
        "C:\\Windows\\Temp\\EOM_ESCAPED.glb",
        "/tmp/EOM_ESCAPED.glb",
        "\\\\server\\share\\EOM_ESCAPED.glb",
        "../../escape.glb",
        "..\\..\\escape.glb",
        "sub/dir/escape.glb",
        "sub\\dir\\escape.glb",
        "character.glb:hidden",
        "CON",
        "NUL.glb",
        "..",
        "",
    ],
)
def test_a_provider_controlled_name_can_never_become_a_path(hostile, tmp_path):
    """HIGH 3. The review wrote a file into C:\\Windows\\Temp through this field."""
    outputs = tmp_path / "outputs"
    outputs.mkdir()
    with pytest.raises(UnsafeOutputPath) as caught:
        resolve_within(outputs, hostile)
    assert caught.value.code == UNSAFE_OUTPUT_PATH
    assert not (tmp_path.parent / "EOM_ESCAPED.glb").exists()


def test_a_trusted_local_name_is_built_from_our_own_data_only():
    name = trusted_artifact_name(run_id="uthana_job_a1_abc123", kind="rigged_character_glb", extension="glb")
    assert name.endswith(".glb")
    assert "/" not in name and "\\" not in name and ":" not in name


@pytest.mark.parametrize(
    "provider_id",
    ["C:/Windows/Temp/x", "../../../../ESCAPED", "chr:with:colons", "CON", "a/b"],
)
def test_a_hostile_provider_id_produces_a_safe_local_name(provider_id):
    """The id is scrubbed into an inert component rather than trusted or rejected:
    a real provider id is opaque, so refusing one would break legitimate jobs."""
    name = trusted_artifact_name(run_id=provider_id, kind="model_glb", extension="glb")
    assert "/" not in name and "\\" not in name and ":" not in name
    assert not name.startswith(".")


def test_a_download_writes_only_the_trusted_name_under_the_outputs_directory(
    autorig_request, store, monkeypatch
):
    """End to end: the provider suggests a hostile filename and it goes nowhere."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    double = UthanaDouble(pending_polls=0, character_id="C:/Windows/Temp/EOM_MUST_NOT_EXIST")
    orch = orchestrator_over(double, store)
    plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
    )
    digest = plan_digest(plan)
    claim = store.claim_submission(digest, {"plan_sha256": digest, "state": "CLAIMED"})
    ticket = granted_authorization(confirmed=digest).mint_paid_capability(
        plan=plan, endpoint=UTHANA_ENDPOINT, claim_id=str(claim)
    )
    manifest = orch.submit(autorig_request, capability=ticket)
    final = orch.poll(manifest.job_id, interval_s=0.0)

    assert not Path("C:/Windows/Temp/EOM_MUST_NOT_EXIST").exists()
    reference = final.outputs[0]
    written = store.repo_root / reference.relative_path
    assert written.is_file()
    assert written.parent == store.outputs_dir(manifest.job_id)
    # The provider's own suggestion survives as metadata, which is where it belongs.
    assert "EOM_MUST_NOT_EXIST" in reference.provider_suggested_filename


@pytest.mark.parametrize(
    "hostile_url",
    [
        "https://uthana.com/motion/bundle/C:/Windows/Temp/EOM_MUST_NOT_EXIST.glb",
        "https://uthana.com/motion/bundle/../../../../EOM_MUST_NOT_EXIST.glb",
        "https://uthana.com/motion/bundle/%2e%2e%2f%2e%2e%2fEOM_MUST_NOT_EXIST.glb",
        "https://uthana.com/motion/bundle/x?name=/tmp/EOM_MUST_NOT_EXIST.glb",
    ],
)
def test_an_adapter_writes_only_where_the_orchestrator_told_it_to(
    hostile_url, tmp_path, monkeypatch
):
    """The adapter must treat its `destination` as final, never re-derive one.

    This is the other half of HIGH 3: the trusted-name derivation upstream is
    worthless if the adapter helpfully rebuilds a filename from the URL it was
    handed. The probe therefore asserts on the FILESYSTEM - exactly one new file,
    at exactly the path the caller chose - rather than on a return value.
    """
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkey_root = tmp_path / "outputs"
    monkey_root.mkdir()
    destination = monkey_root / "trusted__model_glb.glb"
    payload = synthetic_glb_bytes()
    double = UthanaDouble(pending_polls=0, glb_bytes=payload)
    provider = build_provider("uthana", transport=double, require_credential=False)
    ticket = granted_authorization().mint_network_capability(
        provider="uthana", operation="download", endpoint=UTHANA_ENDPOINT
    )

    provider.download(hostile_url, destination, ticket)

    written = sorted(p for p in monkey_root.rglob("*") if p.is_file())
    assert written == [destination], f"the adapter chose its own path: {written}"
    assert destination.read_bytes() == payload
    assert not Path("C:/Windows/Temp/EOM_MUST_NOT_EXIST.glb").exists()
    assert not (tmp_path.parent / "EOM_MUST_NOT_EXIST.glb").exists()


def _link_directory(link: Path, target: Path) -> str:
    """Create a directory reparse point, however this platform allows it.

    A plain symlink needs elevation or Developer Mode on Windows, which is exactly
    the condition under which this check used to skip - on the operating system the
    repository is developed on. A junction needs neither and is the same class of
    escape, so it is tried second rather than giving up.
    """
    try:
        link.symlink_to(target, target_is_directory=True)
        return "symlink"
    except (OSError, NotImplementedError):
        pass
    try:
        import _winapi

        _winapi.CreateJunction(str(target), str(link))
        return "junction"
    except (ImportError, AttributeError, OSError):
        pytest.skip("this platform cannot create any directory reparse point")


def test_a_reparse_point_in_the_outputs_directory_cannot_be_used_to_escape(tmp_path):
    outputs = tmp_path / "outputs"
    outputs.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    kind = _link_directory(outputs / "escape", outside)

    with pytest.raises(UnsafeOutputPath):
        resolve_within(outputs, "escape/loot.glb")
    assert not (outside / "loot.glb").exists(), f"the {kind} was followed out of the root"


# --------------------------------------- HIGH 7 / MEDIUM 9: secret-safe diagnostics


def test_a_request_repr_never_exposes_an_authorization_header():
    """HIGH 7. The dataclass repr printed the base64 Basic token verbatim."""
    token = base64.b64encode(f"{SYNTHETIC_UTHANA_KEY}:".encode()).decode()
    request = HttpRequest(
        method="POST",
        url="https://uthana.com/graphql",
        headers={"Authorization": f"Basic {token}", "Cookie": "session=abc"},
    )
    for rendered in (repr(request), str(request), f"{request}", "%s" % (request,)):
        assert token not in rendered
        assert SYNTHETIC_UTHANA_KEY not in rendered
        assert "session=abc" not in rendered
    assert "authenticated" in repr(request)


def test_a_basic_auth_token_derived_from_a_credential_is_scrubbed():
    """The registered value is the raw key; the wire form is base64 of `key:`."""
    reset_registered_secrets_for_tests()
    from tools.assetgen.secret_guard import register_derived_forms

    register_secret(SYNTHETIC_UTHANA_KEY)
    register_derived_forms(SYNTHETIC_UTHANA_KEY)
    token = base64.b64encode(f"{SYNTHETIC_UTHANA_KEY}:".encode()).decode()
    assert token not in scrub(f"upstream said: Basic {token}")
    assert token not in json.dumps(scrub_obj({"headers": {"Authorization": f"Basic {token}"}}))
    reset_registered_secrets_for_tests()


def test_a_bare_bearer_or_basic_token_is_scrubbed_even_when_unregistered():
    """A serialised header dict carries the token with no header name in sight."""
    reset_registered_secrets_for_tests()
    assert "abcdefghijkl" not in scrub("Bearer abcdefghijkl")
    assert "YWJjZGVmOg==" not in scrub("Basic YWJjZGVmOg==")
    reset_registered_secrets_for_tests()


def test_headers_are_redacted_by_semantics_not_by_pattern():
    redacted = redact_headers(
        {
            "Authorization": "Basic anything-at-all",
            "X-API-Key": "whatever",
            "Cookie": "a=b",
            "Content-Type": "application/json",
        }
    )
    assert redacted["Authorization"] == REDACTED
    assert redacted["X-API-Key"] == REDACTED
    assert redacted["Cookie"] == REDACTED
    assert redacted["Content-Type"] == "application/json"


def test_a_short_credential_is_still_masked():
    """MEDIUM 9. The old 8-character floor let a truncated key through verbatim."""
    reset_registered_secrets_for_tests()
    register_secret("ab12")
    assert "ab12" not in scrub("auth failed for ab12")
    reset_registered_secrets_for_tests()


def test_a_percent_encoded_credential_is_scrubbed():
    reset_registered_secrets_for_tests()
    from tools.assetgen.secret_guard import register_derived_forms
    from urllib.parse import quote

    secret = "key/with+special=chars"
    register_secret(secret)
    register_derived_forms(secret)
    assert quote(secret, safe="") not in scrub(f"?token={quote(secret, safe='')}")
    reset_registered_secrets_for_tests()


def test_a_nested_exception_chain_is_scrubbed():
    reset_registered_secrets_for_tests()
    register_secret(SYNTHETIC_UTHANA_KEY)
    inner = ValueError(f"inner mentions {SYNTHETIC_UTHANA_KEY}")
    outer = RuntimeError(f"outer wraps: {inner}")
    payload = scrub_obj(
        {"error": str(outer), "cause": {"message": str(inner), "args": list(inner.args)}}
    )
    assert SYNTHETIC_UTHANA_KEY not in json.dumps(payload)
    reset_registered_secrets_for_tests()


# ---------------------------------------------- HIGH 8: independent multipart oracle


def _valid_upload_body(boundary: str = "----eomtest") -> tuple[bytes, str]:
    """A specification-correct upload, assembled here rather than by the adapter."""
    operations = json.dumps(
        {
            "query": "mutation create_character($file: Upload!) { create_character }",
            "variables": {
                "name": "double",
                "auto_rig": True,
                "include_fingers": True,
                "file": None,
            },
        }
    )
    mapping = json.dumps({"0": ["variables.file"]})
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="operations"\r\n\r\n{operations}\r\n',
        f'--{boundary}\r\nContent-Disposition: form-data; name="map"\r\n\r\n{mapping}\r\n',
        f'--{boundary}\r\nContent-Disposition: form-data; name="0"; filename="c.glb"\r\n'
        f"Content-Type: model/gltf-binary\r\n\r\nGLBDATA\r\n",
        f"--{boundary}--\r\n",
    ]
    return "".join(parts).encode("utf-8"), f"multipart/form-data; boundary={boundary}"


def test_the_oracle_accepts_a_specification_correct_upload():
    body, content_type = _valid_upload_body()
    upload = read_graphql_upload(body, content_type)
    assert upload.file_field == "0"
    assert upload.file_bytes == b"GLBDATA"
    assert upload.variables["include_fingers"] is True


@pytest.mark.parametrize(
    "sabotage, expected_phrase",
    [
        (('name="operations"', 'name="ops"'), "'operations'"),
        (('name="map"', 'name="m"'), "'map'"),
        (("variables.file", "variables.nowhere"), "does not exist"),
        (('{"0": ["variables.file"]}', '{"9": ["variables.file"]}'), "not in the request"),
    ],
)
def test_renaming_a_required_multipart_field_fails_for_the_right_reason(
    sabotage, expected_phrase
):
    """HIGH 8. Each of these left `create_character` in the body, so the old
    substring routing accepted all four."""
    body, content_type = _valid_upload_body()
    broken = body.replace(sabotage[0].encode(), sabotage[1].encode())
    assert broken != body, "the sabotage did not apply; the test would prove nothing"
    with pytest.raises(MultipartProtocolError) as caught:
        read_graphql_upload(broken, content_type)
    assert expected_phrase in str(caught.value)


def test_a_non_null_mapped_variable_is_refused():
    body, content_type = _valid_upload_body()
    broken = body.replace(b'"file": null', b'"file": "inline"')
    with pytest.raises(MultipartProtocolError, match="must be null"):
        read_graphql_upload(broken, content_type)


def test_a_malformed_multipart_body_is_refused():
    body, content_type = _valid_upload_body()
    with pytest.raises(MultipartProtocolError):
        read_graphql_upload(body[:-20], content_type)
    with pytest.raises(MultipartProtocolError):
        read_graphql_upload(body, "application/json")


def test_the_oracle_shares_no_constants_with_the_production_encoder():
    """A test that imports its own expectations proves only self-consistency."""
    from tools.assetgen.tests import multipart_oracle

    source = Path(multipart_oracle.__file__).read_text(encoding="utf-8")
    assert "providers.uthana" not in source
    assert "_build_multipart" not in source
    assert "CREATE_CHARACTER_MUTATION" not in source


def test_the_double_rejects_a_create_whose_fields_were_renamed(autorig_request, store, monkeypatch):
    """The double now refuses the request the adapter would actually send if a
    required field were renamed - end to end, through the production encoder."""
    monkeypatch.setenv(UTHANA_KEY, SYNTHETIC_UTHANA_KEY)
    monkeypatch.setattr(
        "tools.assetgen.providers.uthana._build_multipart",
        lambda **kwargs: _renamed_multipart(**kwargs),
    )
    double = UthanaDouble()
    orch = orchestrator_over(double, store)
    plan = executable_plan(
        autorig_request.inputs[0].path,
        store.repo_root,
        operation_parameters=dict(autorig_request.parameters),
    )
    digest = plan_digest(plan)
    claim = store.claim_submission(digest, {"plan_sha256": digest, "state": "CLAIMED"})
    ticket = granted_authorization(confirmed=digest).mint_paid_capability(
        plan=plan, endpoint=UTHANA_ENDPOINT, claim_id=str(claim)
    )
    with pytest.raises(MultipartProtocolError, match="'operations'"):
        orch.submit(autorig_request, capability=ticket)


def _renamed_multipart(*, operations: dict, file_field: str, file_path: Path):
    """The `operations -> ops` sabotage, as a drop-in for the production encoder."""
    boundary = "----eomsabotage"
    mapping = json.dumps({"0": [file_field]})
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="ops"\r\n\r\n'
        f"{json.dumps(operations)}\r\n"
        f'--{boundary}\r\nContent-Disposition: form-data; name="map"\r\n\r\n{mapping}\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="0"; filename="c.glb"\r\n\r\n'
    ).encode("utf-8")
    body += file_path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("utf-8")
    return body, f"multipart/form-data; boundary={boundary}"


# ------------------------------------------------ the command-risk model itself


def test_every_registered_cli_command_has_a_declared_risk_class():
    """Adding a command without a class must fail structurally, not silently."""
    parser = cli.build_parser()
    registered = {
        name
        for action in parser._actions
        for name in getattr(action, "choices", {}) or {}
    }
    assert registered, "the parser exposes no subcommands; this test would prove nothing"
    undeclared = sorted(registered - set(COMMAND_RISK))
    assert undeclared == [], f"these CLI commands declare no risk class: {undeclared}"


def test_the_risk_registry_declares_nothing_that_does_not_exist():
    parser = cli.build_parser()
    registered = {
        name
        for action in parser._actions
        for name in getattr(action, "choices", {}) or {}
    }
    stale = sorted(set(COMMAND_RISK) - registered)
    assert stale == [], f"the registry names commands the CLI does not have: {stale}"


def test_an_unknown_command_is_refused_rather_than_defaulted():
    with pytest.raises(UnclassifiedCommand):
        command_risk.risk_for("some-future-command")


def test_the_declared_classes_match_the_documented_contract():
    """The table is the contract, so the load-bearing rows are asserted verbatim."""
    assert COMMAND_RISK["provider-plan"] is OperationClass.OFFLINE
    assert COMMAND_RISK["auth-smoke"] is OperationClass.NETWORK_READ
    assert COMMAND_RISK["poll"] is OperationClass.NETWORK_READ
    assert COMMAND_RISK["download"] is OperationClass.NETWORK_READ
    assert COMMAND_RISK["cancel"] is OperationClass.REMOTE_MUTATION
    for paid in ("autorig", "shield-multiview", "shield-3d"):
        assert COMMAND_RISK[paid] is OperationClass.PAID_CREATE


def test_no_command_keeps_a_local_substitute_for_the_central_authorization():
    """MEDIUM: `if not args.live:` inside a command was how BLOCKER 1 happened."""
    source = Path(cli.__file__).read_text(encoding="utf-8")
    assert "args.live" not in source, (
        "a command is reading the flag directly again; authorization must come from "
        "the central gate"
    )


def test_production_provider_code_never_launches_a_networking_subprocess():
    """The tripwire is a Python hook and cannot see a child process's sockets, so
    the absence of child processes on the provider path is asserted structurally."""
    provider_modules = [
        "orchestrator.py",
        "transport.py",
        "paid_executor.py",
        "capability.py",
        "endpoint.py",
        "providers/meshy.py",
        "providers/uthana.py",
    ]
    root = Path(capability_module.__file__).parent
    for relative in provider_modules:
        source = (root / relative).read_text(encoding="utf-8")
        for forbidden in ("subprocess", "os.system", "os.popen", "os.execv"):
            assert forbidden not in source, f"{relative} references {forbidden}"
