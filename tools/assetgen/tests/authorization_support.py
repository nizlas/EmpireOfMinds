"""Test-owned helpers for minting real provider capabilities.

The capability boundary refuses any outbound call without a ticket minted by the
live gate, so tests must mint real tickets. There is deliberately NO test backdoor
into `capability.mint`: these helpers walk the same path a paid command walks -
build a plan, hash it, confirm the digest, claim it exclusively, mint. If that path
ever weakens, these helpers weaken with it, which is what makes them honest.

What keeps this safe is not the authorization being fake - it is real - but the
DESTINATION being fake. Every test injects a fake transport and a `.test` base URL,
and the socket tripwire in `conftest.py` fails any test that tries to leave the
process anyway.

This lives outside `conftest.py` so test modules can import it by name without
importing the conftest module twice under two different names.
"""

from __future__ import annotations

from tools.assetgen.live_gate import LiveAuthorization
from tools.assetgen.provider_plan import build_plan, plan_digest


def granted_authorization(*, live: bool = True, opt_in: bool = True, confirmed: str = ""):
    """A real `LiveAuthorization` with exactly the barriers a test wants set."""
    return LiveAuthorization(
        live=live,
        opt_in_value="1" if opt_in else "",
        confirmed_plan_digest=confirmed,
    )


def synthetic_paid_plan(orchestrator, request, **overrides):
    """A real, executable plan for `request`, built offline from real files.

    Uses the production plan builder rather than a hand-written dict, so a test's
    approval is the same kind of document an operator would read - and a change to
    what the digest covers cannot be invisible here.
    """
    provider = orchestrator.provider_factory(request.provider)
    # A chained job has no local input at all - it names a previous provider task -
    # so the plan hashes a stable local marker instead. The plan still binds the
    # chained task id through `operation_parameters`.
    if request.inputs:
        input_path = request.inputs[0].path
    else:
        input_path = orchestrator.store.repo_root / "chained_input.marker"
        input_path.parent.mkdir(parents=True, exist_ok=True)
        input_path.write_text(str(request.input_task_id or ""), encoding="utf-8")
    arguments = dict(
        provider=provider.name,
        operation=provider.paid_operation_name(request),
        input_path=input_path,
        repo_root=orchestrator.store.repo_root,
        output_destination="artifacts/assetgen/jobs/<job_id>/outputs/<trusted-name>",
        paid=True,
        credential_env_vars=(provider.credential_env_var,),
        endpoint=provider.endpoint_identity(),
        operation_parameters=dict(request.parameters),
        preflight={
            "upload_allowed": True,
            "verdict": "TEST_PREFLIGHT_ACCEPTED",
            "blocking_checks": [],
        },
    )
    arguments.update(overrides)
    return build_plan(**arguments)


def paid_capability(orchestrator, request, *, live: bool = True, opt_in: bool = True, plan=None):
    """Walk the real paid path: plan, digest, claim, mint. No shortcuts."""
    provider = orchestrator.provider_factory(request.provider)
    resolved = plan if plan is not None else synthetic_paid_plan(orchestrator, request)
    digest = plan_digest(resolved)
    authorization = granted_authorization(live=live, opt_in=opt_in, confirmed=digest)
    try:
        claim = orchestrator.store.claim_submission(
            digest, {"plan_sha256": digest, "state": "CLAIMED"}
        )
    except FileExistsError:
        # A lifecycle test may deliberately submit the same identity twice to prove
        # that the ORCHESTRATOR resumes rather than pays again. Reusing the existing
        # claim keeps that test about resumption. The ledger's own once-only
        # behaviour is asserted directly in `test_provider_live_barriers.py`, where
        # it is the subject rather than the scaffolding.
        claim = orchestrator.store.submission_record_path(digest)
    return authorization.mint_paid_capability(
        plan=resolved, endpoint=provider.endpoint_identity(), claim_id=str(claim)
    )


def submit_authorized(orchestrator, request, **kwargs):
    """`submit` with a freshly minted paid capability, as the executor would."""
    return orchestrator.submit(
        request, capability=paid_capability(orchestrator, request), **kwargs
    )
