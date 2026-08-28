"""The canonical, offline, machine-readable plan for one provider operation.

WHAT A PLAN IS FOR. Barrier 3 needs something specific to approve. "Yes, run the
autorig" is not approval of anything checkable; approving a digest over an exact
document is. So the plan states, before any network access exists, precisely what
would be sent, which local file would be sent, how many times it could be sent,
what happens afterwards, and what it might cost - and then hashes the fields that
change behaviour into one digest an operator can read once and paste back.

WHAT THE DIGEST COVERS. Every field that changes what happens: the provider, the
operation, the input's own SHA-256, the output destination, the submission and
retry limits, the timeouts, whether it is paid, the credential variable NAMES,
the declared cost, the local steps that follow, and whether the preflight allows
the upload. Change any of them and the digest changes, so an approval cannot
survive an edit. Fields that are pure description - when the plan was written,
where it was written to, the human-readable notes - are deliberately outside the
digest so that regenerating an unchanged plan reproduces the same digest.

WHAT A PLAN MAY NEVER CONTAIN. A credential value. The plan names the ENVIRONMENT
VARIABLES a live run would read and says nothing else about them - not even
whether they are set, because a plan is a document that can be committed, pasted
into a review or attached to a report, and "present" is information about the
machine rather than about the work.

`cost: unknown` MEANS UNKNOWN, NOT FREE. When a provider does not publish a
per-operation price and none is declared locally, the plan says so explicitly
rather than omitting the field, so an operator can never read silence as free.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

from .manifest import canonical_json, sha256_file

#: Bumped by the live-safety repair: a v1 plan has no endpoint identity, so its
#: digest cannot express where the request goes. Refusing it is correct - an old
#: approval must not be reinterpreted under the new contract.
PLAN_SCHEMA = "provider_plan_v2"

#: The local chain that runs on a downloaded rig, in order. These are OUR steps,
#: they cost nothing, and every one of them can refuse. Named in the plan so the
#: approval covers what happens after the money is spent as well.
LOCAL_STEPS_AFTER_DOWNLOAD: tuple[str, ...] = (
    "download",
    "godot_import",
    "family_resolution",
    "fixture_compilation",
    "independent_surface_validation",
    "geometry_rig_binding",
    "equipment_assembler",
    "achieved_grip_ground_truth",
    "certification",
    "publish_or_classified_fail",
)

#: Exactly one creating submission per plan. A plan is approval for one paid
#: unit of work, so this is 1 and a retry is not a second unit.
MAX_SUBMISSIONS = 1

#: Poll and download may retry: they read an already-paid task and create
#: nothing. Bounded so a stuck provider cannot become an unbounded wait.
DEFAULT_MAX_POLL_ATTEMPTS = 60
DEFAULT_MAX_DOWNLOAD_ATTEMPTS = 3

DEFAULT_SUBMIT_TIMEOUT_S = 600.0
DEFAULT_POLL_TIMEOUT_S = 1800.0
DEFAULT_DOWNLOAD_TIMEOUT_S = 600.0

#: Keys of the plan that the digest is computed over. Listed explicitly, and
#: recorded in the plan itself, so what an approval binds is auditable rather
#: than implied by whatever the serialiser happened to include.
DIGESTED_KEYS: tuple[str, ...] = (
    "schema",
    "provider",
    "operation",
    "operation_parameters",
    "paid",
    "input",
    "output_destination",
    "limits",
    "timeouts",
    "credentials",
    "cost",
    "local_steps_after_download",
    "preflight_verdict",
    "executable",
    # Added by the live-safety repair. The review (HIGH 6) measured an approval
    # surviving a change of `UTHANA_API_BASE`: the digest was identical while the
    # authenticated upload moved to another host. WHERE a request goes is as
    # behaviour-affecting as what it contains, so the normalised endpoint identity
    # is now inside the digest and is recompared at submission time.
    "endpoint",
)

PLAN_DIGEST_KEY = "plan_sha256"


def build_plan(
    *,
    provider: str,
    operation: str,
    input_path: Path,
    repo_root: Path,
    output_destination: str,
    paid: bool,
    credential_env_vars: tuple[str, ...],
    endpoint=None,
    operation_parameters: dict | None = None,
    preflight: dict | None = None,
    declared_cost: dict | None = None,
    submit_timeout_s: float = DEFAULT_SUBMIT_TIMEOUT_S,
    poll_timeout_s: float = DEFAULT_POLL_TIMEOUT_S,
    download_timeout_s: float = DEFAULT_DOWNLOAD_TIMEOUT_S,
    max_poll_attempts: int = DEFAULT_MAX_POLL_ATTEMPTS,
    max_download_attempts: int = DEFAULT_MAX_DOWNLOAD_ATTEMPTS,
    request_description: dict | None = None,
    notes: tuple[str, ...] = (),
) -> dict:
    """Build the plan. Reads the input file to hash it; touches nothing else."""
    resolved = Path(input_path)
    if not resolved.is_file():
        raise FileNotFoundError(f"plan input does not exist: {resolved}")
    try:
        relative = resolved.resolve().relative_to(Path(repo_root).resolve()).as_posix()
    except ValueError:
        relative = resolved.name

    gate = dict(preflight or {})
    upload_allowed = bool(gate.get("upload_allowed", False)) if gate else False
    blockers: list[str] = []
    if not gate:
        blockers.append("NO_PREFLIGHT_EVALUATED")
    elif not upload_allowed:
        blockers.extend(str(name) for name in gate.get("blocking_checks", []) or [])
        if not blockers:
            blockers.append("PREFLIGHT_REFUSED")
    if endpoint is None:
        blockers.append("PROVIDER_ENDPOINT_UNRESOLVED")

    plan: dict = {
        "schema": PLAN_SCHEMA,
        "provider": str(provider),
        "operation": str(operation),
        # Inside the digest: these change what comes back. `include_fingers=false`
        # would return a rig the hand pipeline cannot use, and an approval must
        # not survive that edit.
        "operation_parameters": dict(operation_parameters or {}),
        "paid": bool(paid),
        "input": {
            "path": relative,
            "sha256": sha256_file(resolved),
            "size_bytes": resolved.stat().st_size,
        },
        "output_destination": str(output_destination),
        # The normalised destination. `None` only for a plan built without a
        # resolvable endpoint, which is never executable.
        "endpoint": endpoint.to_dict() if endpoint is not None else None,
        "limits": {
            "max_submissions": MAX_SUBMISSIONS,
            "max_poll_attempts": int(max_poll_attempts),
            "max_download_attempts": int(max_download_attempts),
            "create_retries_allowed": 0,
        },
        "timeouts": {
            "submit_s": float(submit_timeout_s),
            "poll_total_s": float(poll_timeout_s),
            "download_s": float(download_timeout_s),
        },
        "credentials": {
            "required": bool(credential_env_vars),
            # NAMES ONLY, and no presence: a plan is a document, and whether this
            # machine has a key configured is not part of the work.
            "env_vars": sorted(str(v) for v in credential_env_vars),
        },
        "cost": _normalise_cost(declared_cost),
        "local_steps_after_download": list(LOCAL_STEPS_AFTER_DOWNLOAD),
        "preflight_verdict": {
            "upload_allowed": upload_allowed,
            "verdict": str(gate.get("verdict", "NOT_EVALUATED")),
            "blocking_checks": sorted(str(c) for c in (gate.get("blocking_checks", []) or [])),
        },
        "executable": bool(upload_allowed and not blockers),
        # ---- outside the digest from here down: description, not behaviour.
        "not_executable_because": blockers,
        "preflight": gate,
        "request_description": dict(request_description or {}),
        "digest_covers": list(DIGESTED_KEYS),
        "notes": list(notes),
    }
    plan[PLAN_DIGEST_KEY] = plan_digest(plan)
    assert_no_credential_values(plan)
    return plan


def build_autorig_plan(
    *,
    repo_root: Path,
    input_path: Path,
    character_name: str = "",
    output_destination: str = "",
    base_url: str = "",
) -> dict:
    """The plan for the one operation the first live smoke would perform.

    Built here rather than in the CLI so that the plan an operator READS and the
    plan the submission is CHECKED against are produced by the same code. If they
    were built separately, an approval could bind a document that differs from
    what runs.
    """
    from .humanoid_gate import evaluate_humanoid_candidate
    from .providers.base import ImageInput, JobRequest, TaskType
    from .providers.uthana import CREDENTIAL_ENV_VAR as UTHANA_CREDENTIAL
    from .providers.uthana import PROVIDER_NAME as UTHANA
    from .providers.uthana import MAX_UPLOAD_BYTES, UthanaProvider

    resolved = Path(input_path)
    name = character_name or resolved.stem
    gate = evaluate_humanoid_candidate(resolved)
    endpoint = _resolve_endpoint_or_none(UTHANA, explicit_base_url=base_url)
    parameters = {
        "name": name,
        "auto_rig": True,
        "auto_rig_front_facing": True,
        # Non-negotiable: the equipment pipeline grips with fingers.
        "include_fingers": True,
    }

    # An adapter is built only to DESCRIBE the call. `require_credential=False`
    # plus lazy credential loading means constructing it reads no key, and no
    # transport is used because nothing is sent.
    adapter = UthanaProvider(
        transport=_NoTransport(), require_credential=False, base_url=base_url
    )
    request = JobRequest(
        provider=UTHANA,
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=resolved),),
        parameters=dict(parameters),
        label="humanoid_autorig",
    )
    try:
        description = adapter.describe_submission(request)
    except Exception as exc:  # a description must never be the thing that crashes
        description = {"describe_failed": type(exc).__name__}

    destination = output_destination or (
        "artifacts/assetgen/jobs/<job_id>/outputs/<job_id>__rigged_character_glb.glb"
    )
    return build_plan(
        provider=UTHANA,
        operation="character_autorig",
        input_path=resolved,
        repo_root=repo_root,
        output_destination=destination,
        paid=True,
        credential_env_vars=(UTHANA_CREDENTIAL,),
        endpoint=endpoint,
        operation_parameters=parameters,
        preflight=gate,
        declared_cost=None,  # Uthana publishes no per-character price locally.
        request_description=description,
        notes=(
            f"consumes one character slot; upload ceiling {MAX_UPLOAD_BYTES} bytes",
            "include_fingers is mandatory: the hand/equipment pipeline grips with finger joints",
            "no cancel exists for an in-flight character upload; deletion is a manual web-UI step",
        ),
    )


def _resolve_endpoint_or_none(provider: str, *, explicit_base_url: str = ""):
    """The normalised endpoint, or `None` when it cannot be used for live traffic.

    Returning `None` rather than raising keeps `provider-plan` a document-producing
    command: an insecure or malformed base URL yields a plan that states why it is
    not executable, which is more useful to an operator than a traceback.
    """
    from .endpoint import EndpointRefused, resolve_endpoint
    from .providers import provider_endpoint_config

    try:
        config = provider_endpoint_config(provider)
    except KeyError:
        return None
    try:
        return resolve_endpoint(
            provider,
            default_base_url=config["default_base_url"],
            base_url_env_var=config["base_url_env_var"],
            explicit_base_url=explicit_base_url,
        )
    except EndpointRefused:
        return None


def build_meshy_multiview_plan(
    *,
    repo_root: Path,
    front_reference: Path,
    base_url: str = "",
    output_destination: str = "",
) -> dict:
    """Plan for the paid Meshy image job that must show the shield's rear grip.

    Exists because the review (BLOCKER 2) found this command submitting with no
    plan at all. A paid command without a plan cannot be approved, only triggered.
    """
    from .providers.meshy import CREDENTIAL_ENV_VAR as MESHY_CREDENTIAL
    from .providers.meshy import PROVIDER_NAME as MESHY
    from .providers.meshy import MeshyProvider, paid_operation_name
    from .shield_pipeline import build_multiview_request

    resolved = Path(front_reference)
    endpoint = _resolve_endpoint_or_none(MESHY, explicit_base_url=base_url)
    request = build_multiview_request(provider=MESHY, front_reference=resolved)
    adapter = MeshyProvider(
        transport=_NoTransport(), require_credential=False, base_url=base_url
    )
    try:
        description = adapter.describe_submission(request)
        preflight = {"upload_allowed": True, "verdict": "MESHY_IMAGE_CONTRACT_OK",
                     "blocking_checks": []}
    except Exception as exc:  # noqa: BLE001 - a refusal is a plan outcome, not a crash
        description = {"describe_failed": type(exc).__name__}
        preflight = {
            "upload_allowed": False,
            "verdict": "MESHY_IMAGE_CONTRACT_REFUSED",
            "blocking_checks": ["provider_contract_validation"],
        }
    return build_plan(
        provider=MESHY,
        operation=paid_operation_name(request),
        input_path=resolved,
        repo_root=repo_root,
        output_destination=output_destination
        or "artifacts/assetgen/jobs/<job_id>/outputs/<job_id>__view_N.png",
        paid=True,
        credential_env_vars=(MESHY_CREDENTIAL,),
        endpoint=endpoint,
        operation_parameters=dict(request.parameters),
        preflight=preflight,
        declared_cost=None,
        request_description=description,
        notes=(
            "paid image task; consumes Meshy credits whose per-task price is not declared locally",
            "the rear grip must be visible in the generated views or the 3D step has no truth source",
        ),
    )


def build_meshy_shield_3d_plan(
    *,
    repo_root: Path,
    ordered_views: tuple[Path, ...],
    input_task_id: str | None = None,
    base_url: str = "",
    output_destination: str = "",
) -> dict:
    """Plan for the paid Meshy multi-image-to-3D job.

    The plan's input is the FIRST ordered view, because that is the file whose
    bytes the digest must bind; every view is listed in the operation parameters,
    so changing any of them changes the digest too.
    """
    from .providers.meshy import CREDENTIAL_ENV_VAR as MESHY_CREDENTIAL
    from .providers.meshy import PROVIDER_NAME as MESHY
    from .providers.meshy import MeshyProvider, paid_operation_name
    from .shield_pipeline import build_shield_3d_request

    views = tuple(Path(v) for v in ordered_views)
    endpoint = _resolve_endpoint_or_none(MESHY, explicit_base_url=base_url)
    request = build_shield_3d_request(
        provider=MESHY, ordered_views=views, input_task_id=input_task_id
    )
    adapter = MeshyProvider(
        transport=_NoTransport(), require_credential=False, base_url=base_url
    )
    blocking: list[str] = []
    if not views:
        blocking.append("no_ordered_views_supplied")
    try:
        description = adapter.describe_submission(request)
    except Exception as exc:  # noqa: BLE001
        description = {"describe_failed": type(exc).__name__}
        blocking.append("provider_contract_validation")
    preflight = {
        "upload_allowed": not blocking,
        "verdict": "MESHY_3D_CONTRACT_OK" if not blocking else "MESHY_3D_CONTRACT_REFUSED",
        "blocking_checks": blocking,
    }
    # Every view's identity is inside the digest, not just the one hashed as
    # `input`, so swapping the second view invalidates the approval.
    parameters = dict(request.parameters)
    parameters["ordered_view_names"] = [v.name for v in views]
    parameters["ordered_view_sha256"] = [
        sha256_file(v) if v.is_file() else "MISSING" for v in views
    ]
    parameters["input_task_id"] = input_task_id or ""
    return build_plan(
        provider=MESHY,
        operation=paid_operation_name(request),
        input_path=views[0] if views else Path(repo_root) / "pyproject.toml",
        repo_root=repo_root,
        output_destination=output_destination
        or "artifacts/assetgen/jobs/<job_id>/outputs/<job_id>__model_glb.glb",
        paid=True,
        credential_env_vars=(MESHY_CREDENTIAL,),
        endpoint=endpoint,
        operation_parameters=parameters,
        preflight=preflight,
        declared_cost=None,
        request_description=description,
        notes=(
            "paid 3D task; consumes Meshy credits whose per-task price is not declared locally",
            "a human must have verified the multiview images by eye before this is approved",
        ),
    )


class _NoTransport:
    """A transport that proves the plan path is offline by refusing to send."""

    def send(self, request):  # pragma: no cover - reaching this is the bug
        raise AssertionError(
            "building a provider plan must never send a request; "
            f"something tried {request.method} on the plan path"
        )


def digest_payload(plan: dict) -> dict:
    """The exact subset the digest is taken over."""
    return {key: plan.get(key) for key in DIGESTED_KEYS}


def plan_digest(plan: dict) -> str:
    """Deterministic SHA-256 over the behaviour-affecting fields.

    Computed from the plan's own content, never stored-and-trusted, so a plan
    file whose recorded digest was edited still fails barrier 3.
    """
    return hashlib.sha256(canonical_json(digest_payload(plan)).encode("utf-8")).hexdigest()


def digest_is_intact(plan: dict) -> bool:
    """Does the plan's recorded digest still match its own content?"""
    return str(plan.get(PLAN_DIGEST_KEY, "")).lower() == plan_digest(plan)


def write_plan(plan: dict, destination: Path) -> Path:
    """Write the plan atomically. The digest is recomputed, never carried over."""
    assert_no_credential_values(plan)
    target = Path(destination)
    target.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    temp = target.with_suffix(target.suffix + ".tmp")
    temp.write_text(body, encoding="utf-8")
    os.replace(temp, target)
    return target


def load_plan(path: Path) -> dict:
    plan = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(plan, dict):
        raise ValueError(f"{path} does not contain a provider plan object")
    if str(plan.get("schema", "")) != PLAN_SCHEMA:
        raise ValueError(
            f"{path} has plan schema {plan.get('schema')!r}; this tool understands {PLAN_SCHEMA}"
        )
    return plan


def assert_no_credential_values(plan: dict) -> None:
    """Fail loudly if anything credential-shaped reached the plan.

    A belt-and-braces check on top of the fact that no code path puts a value
    here: a plan is the document most likely to be copied into a chat, a review
    or a report, so a leak in it would travel furthest.

    The check deliberately does NOT read the environment. An earlier version
    looked each declared variable up and compared its value against the plan
    body, which meant offline planning materialised every credential it merely
    named - the exact eager read the review asked us to keep out of the offline
    path. Instead it uses the credential-shaped patterns plus the registry of
    values something in this process has already loaded, which covers the only
    way a value could have reached a plan in the first place.
    """
    from .secret_guard import KEY_PATTERNS, scrub

    body = canonical_json(plan)
    for name, pattern in KEY_PATTERNS:
        if pattern.search(body):
            raise ValueError(f"provider plan contains credential-shaped content ({name})")
    if scrub(body) != body:
        raise ValueError("provider plan contains a credential value loaded in this process")


def _normalise_cost(declared: dict | None) -> dict:
    """`unknown` is stated, never implied by omission, and never means free."""
    if not declared:
        return {
            "known": False,
            "value": "unknown",
            "unit": "unknown",
            "note": (
                "cost is UNKNOWN, which is not the same as free: this operation consumes a "
                "paid provider slot or credits whose price is not declared locally"
            ),
        }
    return {
        "known": True,
        "value": declared.get("value"),
        "unit": str(declared.get("unit", "credits")),
        "note": str(declared.get("note", "declared locally; verify against the provider invoice")),
    }
