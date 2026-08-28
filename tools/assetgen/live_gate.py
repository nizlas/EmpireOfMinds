"""The three barriers between a normal run and a paid provider call.

WHY THREE AND NOT ONE. `--live` alone was the whole barrier, which made the
safety of every run depend on one flag being absent. That is too easy to satisfy
by accident: a flag can be copied out of a doc, pasted from shell history, or
added by an agent that read the help text and wanted the command to "work". A
configured credential made it worse, because a machine with `UTHANA_API_KEY`
exported was one word away from spending money.

So spending now needs three INDEPENDENT things that no single mistake produces:

1. `--live` on the command line          - this run intends to reach a provider
2. `EOM_ALLOW_PAID_PROVIDER_CALLS=1`     - this MACHINE is allowed to spend
3. `--confirm-plan <sha256>`             - this EXACT plan was read and approved

The three are deliberately different kinds of evidence. The flag is per-command,
the opt-in is per-machine and cannot travel in a command, and the digest is
per-plan and cannot be guessed - it has to be copied from a plan that was
generated offline and inspected. A stale digest is a refusal, so editing the
asset, the timeout, the destination or the submission limit after approval
invalidates the approval instead of silently widening it.

ORDER MATTERS. The barriers are checked in the order above and the credential is
read only after all three pass, so a run that is not authorized never touches a
key at all - there is nothing to leak from a run that was refused.

WHAT THIS MODULE MAY NOT DO. It never reads a credential, never opens a socket,
and never prompts. An interactive question would be answered `yes` by CI, so
there is no question: absent authorization is a classified refusal.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

#: Per-machine opt-in. A name in this repository's own namespace, so it cannot
#: collide with a provider variable and cannot be set as a side effect of
#: configuring credentials.
OPT_IN_ENV_VAR = "EOM_ALLOW_PAID_PROVIDER_CALLS"
OPT_IN_REQUIRED_VALUE = "1"

#: Classified refusals. Distinct causes stay distinct: "you did not ask for
#: live", "this machine may not spend", "you approved nothing", "you approved
#: something else" and "the key is missing" are five different operator actions.
LIVE_PROVIDER_MODE_REQUIRED = "LIVE_PROVIDER_MODE_REQUIRED"
PAID_PROVIDER_OPT_IN_REQUIRED = "PAID_PROVIDER_OPT_IN_REQUIRED"
PROVIDER_PLAN_CONFIRMATION_REQUIRED = "PROVIDER_PLAN_CONFIRMATION_REQUIRED"
PROVIDER_PLAN_DIGEST_MISMATCH = "PROVIDER_PLAN_DIGEST_MISMATCH"
PROVIDER_PLAN_NOT_EXECUTABLE = "PROVIDER_PLAN_NOT_EXECUTABLE"
PROVIDER_CREDENTIAL_MISSING = "PROVIDER_CREDENTIAL_MISSING"
PROVIDER_NETWORK_FORBIDDEN = "PROVIDER_NETWORK_FORBIDDEN"
PROVIDER_SUBMISSION_ALREADY_RECORDED = "PROVIDER_SUBMISSION_ALREADY_RECORDED"
PROVIDER_SUBMISSION_OUTCOME_UNKNOWN = "PROVIDER_SUBMISSION_OUTCOME_UNKNOWN"
#: Added by the live-safety repair: the destination is now part of what an
#: approval covers, so a moved or insecure endpoint has its own named refusal.
PROVIDER_ENDPOINT_NOT_APPROVED = "PROVIDER_ENDPOINT_NOT_APPROVED"
PROVIDER_ENDPOINT_INSECURE = "PROVIDER_ENDPOINT_INSECURE"
PROVIDER_SUBMISSION_CLAIM_REQUIRED = "PROVIDER_SUBMISSION_CLAIM_REQUIRED"

#: Every refusal this module and its callers can raise, so a test can assert the
#: set is closed rather than matching on message text.
REFUSAL_CODES: frozenset[str] = frozenset(
    {
        LIVE_PROVIDER_MODE_REQUIRED,
        PAID_PROVIDER_OPT_IN_REQUIRED,
        PROVIDER_PLAN_CONFIRMATION_REQUIRED,
        PROVIDER_PLAN_DIGEST_MISMATCH,
        PROVIDER_PLAN_NOT_EXECUTABLE,
        PROVIDER_CREDENTIAL_MISSING,
        PROVIDER_NETWORK_FORBIDDEN,
        PROVIDER_SUBMISSION_ALREADY_RECORDED,
        PROVIDER_SUBMISSION_OUTCOME_UNKNOWN,
        PROVIDER_ENDPOINT_NOT_APPROVED,
        PROVIDER_ENDPOINT_INSECURE,
        PROVIDER_SUBMISSION_CLAIM_REQUIRED,
    }
)


class LiveGateRefusal(RuntimeError):
    """A classified refusal raised before any network or credential access.

    Carries the machine-readable `code` plus the exact operator action that
    would change the outcome. It never carries a credential: the barriers run
    before any key is read, so there is nothing here to redact.
    """

    def __init__(self, code: str, message: str, *, operation: str = "", detail: dict | None = None):
        self.code = code
        self.operation = operation
        self.detail = detail or {}
        super().__init__(f"[{code}] {message}")
        self.message = message

    def to_dict(self) -> dict:
        return {
            "refused": self.code,
            "operation": self.operation,
            "message": self.message,
            "detail": self.detail,
            "network_reached": False,
            "credential_read": False,
        }


@dataclass(frozen=True)
class LiveAuthorization:
    """What this run is allowed to do. Closed by default in every field.

    `opt_in_value` is the RAW environment value rather than a boolean, so the
    comparison against the required value happens here in one place and a
    surprising value such as `0`, `false` or `yes` cannot be coerced into
    permission somewhere else.
    """

    live: bool = False
    opt_in_value: str = ""
    confirmed_plan_digest: str = ""

    @classmethod
    def from_environment(cls, *, live: bool, confirmed_plan_digest: str = "", env=None):
        """Read the per-machine opt-in. Reads no credential."""
        source = os.environ if env is None else env
        return cls(
            live=bool(live),
            opt_in_value=str(source.get(OPT_IN_ENV_VAR, "") or "").strip(),
            confirmed_plan_digest=str(confirmed_plan_digest or "").strip().lower(),
        )

    @property
    def opted_in(self) -> bool:
        return self.opt_in_value == OPT_IN_REQUIRED_VALUE

    # ------------------------------------------------------------------ barriers

    def authorize_network(self, operation: str) -> None:
        """Barriers 1 and 2: may this run reach a provider at all?

        Applies to every network operation including the free ones, because a
        read-only probe is still traffic to a paid account and still proves a
        credential works. Poll and download stop here rather than at barrier 3:
        they act on an ALREADY paid task and create nothing new.
        """
        if not self.live:
            raise LiveGateRefusal(
                LIVE_PROVIDER_MODE_REQUIRED,
                f"'{operation}' would reach a provider. Re-run with --live to intend that. "
                "Nothing was sent and no credential was read.",
                operation=operation,
            )
        if not self.opted_in:
            raise LiveGateRefusal(
                PAID_PROVIDER_OPT_IN_REQUIRED,
                f"'{operation}' needs this machine to be opted in: set "
                f"{OPT_IN_ENV_VAR}={OPT_IN_REQUIRED_VALUE}. --live alone is not enough, and a "
                "configured credential is not permission. No credential was read.",
                operation=operation,
                detail={"env_var": OPT_IN_ENV_VAR, "required_value": OPT_IN_REQUIRED_VALUE},
            )

    def authorize_submission(self, plan: dict, *, operation: str = "submit") -> None:
        """All three barriers plus the plan's own executability.

        Required for anything that CREATES paid work. The digest is recomputed
        from the plan being submitted, so approving a plan and then editing it
        fails closed: the approval names a document that no longer exists.
        """
        from .provider_plan import plan_digest

        self.authorize_network(operation)
        expected = plan_digest(plan)
        if not self.confirmed_plan_digest:
            raise LiveGateRefusal(
                PROVIDER_PLAN_CONFIRMATION_REQUIRED,
                f"'{operation}' creates paid work and needs the exact plan confirmed: re-run "
                f"with --confirm-plan {expected} after reading the plan. No credential was read.",
                operation=operation,
                detail={"expected_plan_digest": expected},
            )
        if self.confirmed_plan_digest != expected:
            raise LiveGateRefusal(
                PROVIDER_PLAN_DIGEST_MISMATCH,
                "the confirmed digest does not match this plan. Either the plan changed after "
                "it was approved or a digest from another plan was pasted. Regenerate the plan, "
                "read it again and confirm the new digest. No credential was read.",
                operation=operation,
                detail={
                    "confirmed_plan_digest": self.confirmed_plan_digest,
                    "actual_plan_digest": expected,
                },
            )
        if not bool(plan.get("executable", False)):
            raise LiveGateRefusal(
                PROVIDER_PLAN_NOT_EXECUTABLE,
                "this plan is a document, not an authorization: its own preflight refuses the "
                "input. Fix what the preflight names and regenerate the plan. "
                "No credential was read.",
                operation=operation,
                detail={
                    "preflight": plan.get("preflight", {}),
                    "not_executable_because": plan.get("not_executable_because", []),
                },
            )
        endpoint = plan.get("endpoint")
        if not isinstance(endpoint, dict) or not endpoint.get("canonical"):
            raise LiveGateRefusal(
                PROVIDER_ENDPOINT_NOT_APPROVED,
                "this plan names no provider endpoint, so approving it would approve an "
                "unspecified destination. Regenerate it under the current plan schema.",
                operation=operation,
                detail={"plan_schema": plan.get("schema")},
            )

    # ---------------------------------------------------------------- capabilities

    def mint_network_capability(
        self, *, provider: str, operation: str, endpoint, operation_class=None
    ):
        """Barriers 1 and 2, then a ticket for one non-paid operation.

        The capability is what the adapters and the transport actually check, so
        the barriers now sit at the outbound boundary rather than in whichever
        command remembered to call them.
        """
        from .capability import OperationClass, mint

        target = operation_class or OperationClass.NETWORK_READ
        if target is OperationClass.PAID_CREATE:
            raise LiveGateRefusal(
                PROVIDER_PLAN_CONFIRMATION_REQUIRED,
                "paid work cannot be authorized by the network barriers alone; it needs a "
                "confirmed plan and a submission claim.",
                operation=operation,
            )
        self.authorize_network(operation)
        self.require_endpoint_approved(endpoint, operation=operation)
        return mint(
            operation_class=target,
            provider=provider,
            operation=operation,
            endpoint=endpoint,
        )

    def mint_paid_capability(self, *, plan: dict, endpoint, claim_id: str, operation: str = ""):
        """All three barriers, the plan's executability, the endpoint AND a claim.

        `claim_id` is the ledger claim the caller already acquired exclusively. It
        is required here rather than checked later, because a paid capability that
        does not name an unspent claim is exactly the object that let one approval
        buy two creates.
        """
        from .capability import OperationClass, mint
        from .provider_plan import plan_digest

        name = operation or str(plan.get("operation", "submit"))
        self.authorize_submission(plan, operation=name)
        self.require_endpoint_approved(endpoint, operation=name, plan=plan)
        if not str(claim_id or "").strip():
            raise LiveGateRefusal(
                PROVIDER_SUBMISSION_CLAIM_REQUIRED,
                f"'{name}' may not create paid work without an exclusive submission claim. "
                "The claim is what makes one approval buy exactly one job.",
                operation=name,
            )
        return mint(
            operation_class=OperationClass.PAID_CREATE,
            provider=str(plan.get("provider", "")),
            operation=name,
            endpoint=endpoint,
            plan_digest=plan_digest(plan),
            claim_id=str(claim_id).strip(),
        )

    def require_endpoint_approved(self, endpoint, *, operation: str, plan: dict | None = None):
        """The destination must be https, and must be the one the plan approved."""
        from .endpoint import REQUIRED_LIVE_SCHEME

        if endpoint is None:
            raise LiveGateRefusal(
                PROVIDER_ENDPOINT_NOT_APPROVED,
                f"'{operation}' has no resolvable provider endpoint. A request with no "
                "approved destination is never sent.",
                operation=operation,
            )
        if endpoint.scheme != REQUIRED_LIVE_SCHEME:
            raise LiveGateRefusal(
                PROVIDER_ENDPOINT_INSECURE,
                f"'{operation}' resolves to {endpoint.canonical}, which is not https. A "
                "credential is never sent in clear text. No credential was read.",
                operation=operation,
                detail={"endpoint": endpoint.canonical},
            )
        if plan is not None:
            approved = str((plan.get("endpoint") or {}).get("canonical", ""))
            if approved != endpoint.canonical:
                raise LiveGateRefusal(
                    PROVIDER_ENDPOINT_NOT_APPROVED,
                    "the provider endpoint changed after this plan was approved. The plan "
                    f"approved {approved or '<none>'}; the current configuration resolves to "
                    f"{endpoint.canonical}. Regenerate the plan and approve the new digest. "
                    "No credential was read.",
                    operation=operation,
                    detail={"approved": approved, "current": endpoint.canonical},
                )


def credential_state(env_var: str, *, env=None) -> str:
    """`present` or `missing`, and never the value.

    This is the ONLY thing any report, log or plan is allowed to say about a
    credential. It is called after the barriers, so a refused run never reaches
    even this much.
    """
    source = os.environ if env is None else env
    return "present" if str(source.get(env_var, "") or "").strip() else "missing"


def require_credential_present(env_var: str, *, operation: str = "submit", env=None) -> None:
    """Barrier 4, after authorization: is the key actually configured?

    A missing key is its own classified refusal rather than an auth failure from
    the provider, because it costs nothing to detect locally and a 401 would
    have been a real request.
    """
    if credential_state(env_var, env=env) != "present":
        raise LiveGateRefusal(
            PROVIDER_CREDENTIAL_MISSING,
            f"{env_var} is not set in this environment, so '{operation}' cannot authenticate. "
            "Set it in your shell (see .env.example); never place it in a tracked file, "
            "a plan or a command argument.",
            operation=operation,
            detail={"credential_env_var": env_var, "credential_state": "missing"},
        )
