"""The one path that may spend money.

WHY ONE PATH. The forensic review found three paid commands with three different
amounts of policy. `autorig` had all three barriers, a plan and a ledger claim.
`shield-multiview --submit` and `shield-3d --submit` had two barriers, no plan and
no claim - the review submitted a paid Meshy task through a counting transport
with nothing but `--live` and the machine opt-in. Nobody decided that; the two
shield commands were simply written before the plan existed and never revisited.

Three implementations of "spend money safely" will always drift to the weakest
one, so there is now exactly one. Every paid command supplies its own plan builder
and its own request, and this module owns the ordering that actually matters:

  1. recompute the plan from CURRENT files and CURRENT configuration
  2. refuse unless the plan is executable
  3. refuse unless the operator confirmed THIS plan's digest
  4. refuse unless the resolved endpoint is the approved one
  5. acquire the exclusive submission claim, durably, BEFORE any request
  6. mint the paid capability, which binds the digest and the claim
  7. one create request, no retries
  8. record the task id - or a permanent UNKNOWN - durably

Step 1 is what makes step 3 meaningful. The digest is recomputed here rather than
read from the plan file, so a plan whose input has changed since it was written
produces a different digest and the confirmation no longer matches. A correctly
hashed old document cannot approve a different current asset.

THE LIMIT THAT CANNOT BE ENGINEERED AWAY. Neither Meshy nor Uthana documents an
idempotency key or a lookup by client submission id. If the connection dies after
the provider accepted the create but before we read the task id, no local record
can distinguish "accepted and billed" from "never arrived". This module therefore
records a PERMANENT `UNKNOWN` and refuses to submit that identity again. That is
at-most-once locally, not exactly-once globally, and the difference is stated
rather than glossed: resolving an UNKNOWN means a human looking at the provider's
own task list.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .live_gate import (
    PROVIDER_SUBMISSION_ALREADY_RECORDED,
    PROVIDER_SUBMISSION_OUTCOME_UNKNOWN,
    LiveAuthorization,
    LiveGateRefusal,
    require_credential_present,
)
from .manifest import JobManifest
from .orchestrator import JobOrchestrator
from .provider_plan import plan_digest
from .store import LedgerUnavailable


@dataclass(frozen=True)
class PaidSubmission:
    """What a paid command asks for, in the only shape the executor accepts."""

    #: CLI command name, for the ledger and the refusal messages.
    command: str
    #: Neutral provider name.
    provider: str
    #: Rebuilds the plan from current files and configuration. Called HERE, not by
    #: the command, so no command can hand over a stale document.
    build_plan: Callable[[], dict]
    #: The provider-neutral request the plan describes.
    build_request: Callable[[], object]


@dataclass(frozen=True)
class PaidSubmissionResult:
    manifest: JobManifest
    plan: dict
    digest: str
    claim_path: str


def execute_paid_submission(
    submission: PaidSubmission,
    *,
    authorization: LiveAuthorization,
    orchestrator: JobOrchestrator,
    provider_factory: Callable[[str], object],
) -> PaidSubmissionResult:
    """Run the single approved paid path. Returns the manifest, or raises."""
    plan = submission.build_plan()
    digest = plan_digest(plan)
    request = submission.build_request()
    provider = provider_factory(submission.provider)
    endpoint = provider.endpoint_identity()

    # Barriers 1-3, executability and endpoint agreement, all before the claim so
    # a refused run leaves no ledger entry to clean up.
    authorization.authorize_submission(plan, operation=submission.command)
    authorization.require_endpoint_approved(
        endpoint, operation=submission.command, plan=plan
    )

    existing = orchestrator.store.read_submission(digest)
    if existing is not None:
        raise LiveGateRefusal(
            _outcome_code(existing),
            f"this exact plan ({digest}) was already submitted by job "
            f"{existing.get('job_id', '<unknown>')} in state {existing.get('state', 'UNKNOWN')}. "
            "One approval buys one job. To do this work again, regenerate the plan, read it and "
            "confirm the new digest. Nothing was sent.",
            operation=submission.command,
            detail={"plan_sha256": digest, "existing": existing},
        )

    # The credential is checked for PRESENCE only, and only now: everything above
    # is refusable without a key existing at all.
    require_credential_present(
        provider.credential_env_var, operation=submission.command
    )

    try:
        claim_path = orchestrator.store.claim_submission(
            digest,
            {
                "plan_sha256": digest,
                "command": submission.command,
                "provider": submission.provider,
                "operation": plan.get("operation"),
                "endpoint": endpoint.canonical,
                "state": "CLAIMED",
            },
        )
    except FileExistsError as exc:
        raise LiveGateRefusal(
            PROVIDER_SUBMISSION_ALREADY_RECORDED,
            f"another run already claimed this plan ({digest}). Exactly one submission per "
            "approval, so this one stops here. Nothing was sent.",
            operation=submission.command,
            detail={"plan_sha256": digest},
        ) from exc
    except LedgerUnavailable as exc:
        raise LiveGateRefusal(
            PROVIDER_SUBMISSION_ALREADY_RECORDED,
            f"the submission ledger could not be written: {exc}. Without a durable claim "
            "nothing prevents a second charge, so nothing was sent.",
            operation=submission.command,
            detail={"plan_sha256": digest},
        ) from exc

    capability = authorization.mint_paid_capability(
        plan=plan,
        endpoint=endpoint,
        claim_id=str(claim_path),
        operation=str(plan.get("operation", submission.command)),
    )
    orchestrator.plan_digest = digest
    manifest = orchestrator.submit(request, capability=capability)
    return PaidSubmissionResult(
        manifest=manifest, plan=plan, digest=digest, claim_path=str(claim_path)
    )


def _outcome_code(record: dict) -> str:
    """An UNKNOWN outcome is its own refusal, because its remedy is different.

    "Already recorded" tells an operator the work is done or in flight. "Outcome
    unknown" tells them a human has to look at the provider before anything else
    happens. Collapsing the two would make the dangerous case look routine.
    """
    state = str(record.get("state", "")).upper()
    if state in ("OUTCOME_UNKNOWN", "UNKNOWN"):
        return PROVIDER_SUBMISSION_OUTCOME_UNKNOWN
    return PROVIDER_SUBMISSION_ALREADY_RECORDED
