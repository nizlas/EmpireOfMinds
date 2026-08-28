"""The capability that an outbound provider call must present.

WHY BOOLEANS WERE NOT ENOUGH. The forensic review (HIGH 4) measured a paid
request being built by `JobOrchestrator(live=True, opt_in=True).submit(...)` with
no plan confirmation and no ledger claim. Two loose booleans carried the whole
authority, they were trivially constructible, and the third barrier lived one
layer above them in the CLI. Any call path that did not go through that CLI
function silently lost a third of the policy.

WHAT REPLACES THEM. A `ProviderCapability` is an immutable ticket that states
exactly one operation class, one provider, one operation and one endpoint. It can
only be produced by `mint()`, which runs the central checks first, and it carries
a module-private token so a hand-built look-alike is refused. Adapters demand one
before they read a credential, and the production transport demands one before it
sends. The capability is therefore checked at the real egress boundary rather than
at the most convenient one.

WHAT A PAID CAPABILITY ADDITIONALLY BINDS. A verified plan digest and an acquired
submission claim. It cannot be minted without both, and it is single-use: once
consumed it refuses reuse, so one approval buys one create even if the same
object is passed twice.

THE ACTUAL THREAT MODEL - STATED HONESTLY. This is not a sandbox and makes no
cryptographic claim. Python cannot stop code in this process from importing
`_MINT_TOKEN`, monkeypatching `verify`, or reading `os.environ` and calling
`urllib` itself. A hostile local process with repository access can always spend
money, because it can always read the same credential the legitimate path reads.

What this design does defend against is the failure mode that actually happened
here: an ALTERNATIVE, INCOMPLETE or NEW repository call path reaching a provider
with less policy than the documented one. `auth-smoke` bypassing barrier 2, the
shield commands bypassing barrier 3, a direct orchestrator call bypassing the
ledger - all three were accidents of structure, not attacks, and all three become
impossible to write by accident when the ticket is required at the boundary.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from enum import Enum

from .endpoint import REQUIRED_LIVE_SCHEME, EndpointIdentity

#: Private mint marker. Presence proves the object came from `mint()` in this
#: module rather than from a caller that constructed the dataclass directly.
_MINT_TOKEN = object()

#: Paid capabilities that are mid-flight, and paid capabilities that are finished.
#: Two sets rather than one, because "in use right now" and "already spent" must be
#: distinguishable: the adapter re-checks the ticket AFTER the orchestrator has
#: committed to sending, and a single flag would make the ticket refuse its own
#: request. Ids only - no secrets.
_RESERVED_PAID: set[str] = set()
_CONSUMED_PAID: set[str] = set()


class OperationClass(str, Enum):
    """How dangerous one operation is. Exhaustive and ordered by consequence."""

    #: No provider contact whatsoever. Needs no capability and cannot mint one.
    OFFLINE = "OFFLINE"
    #: Reaches the provider but changes nothing there. Still real traffic on a
    #: paid account, and still proves a credential works, so it is gated.
    NETWORK_READ = "NETWORK_READ"
    #: Changes remote state without creating a new billable artifact.
    REMOTE_MUTATION = "REMOTE_MUTATION"
    #: Creates billable work. The only class that requires a confirmed plan and
    #: a submission claim.
    PAID_CREATE = "PAID_CREATE"


#: Classes that require a live capability before any request may be built.
NETWORK_CLASSES: frozenset[OperationClass] = frozenset(
    {OperationClass.NETWORK_READ, OperationClass.REMOTE_MUTATION, OperationClass.PAID_CREATE}
)

CAPABILITY_REQUIRED = "PROVIDER_CAPABILITY_REQUIRED"
CAPABILITY_INVALID = "PROVIDER_CAPABILITY_INVALID"
CAPABILITY_SCOPE_MISMATCH = "PROVIDER_CAPABILITY_SCOPE_MISMATCH"
CAPABILITY_ALREADY_CONSUMED = "PROVIDER_CAPABILITY_ALREADY_CONSUMED"
CAPABILITY_CLASS_INSUFFICIENT = "PROVIDER_CAPABILITY_CLASS_INSUFFICIENT"

CAPABILITY_REFUSAL_CODES: frozenset[str] = frozenset(
    {
        CAPABILITY_REQUIRED,
        CAPABILITY_INVALID,
        CAPABILITY_SCOPE_MISMATCH,
        CAPABILITY_ALREADY_CONSUMED,
        CAPABILITY_CLASS_INSUFFICIENT,
    }
)


class CapabilityRefused(RuntimeError):
    """An outbound operation was attempted without adequate authorization."""

    def __init__(self, code: str, message: str, *, detail: dict | None = None) -> None:
        self.code = code
        self.detail = detail or {}
        super().__init__(f"[{code}] {message}")
        self.message = message

    def to_dict(self) -> dict:
        return {
            "refused": self.code,
            "message": self.message,
            "detail": self.detail,
            "network_reached": False,
            "credential_read": False,
        }


@dataclass(frozen=True)
class ProviderCapability:
    """Authority for exactly one operation against exactly one endpoint."""

    operation_class: OperationClass
    provider: str
    operation: str
    endpoint: EndpointIdentity
    #: PAID_CREATE only: the digest of the plan that was read and confirmed.
    plan_digest: str = ""
    #: PAID_CREATE only: the ledger claim proving this approval is unspent.
    claim_id: str = ""
    #: Identity for single-use accounting. Never a secret.
    capability_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    _token: object = None

    # ------------------------------------------------------------------ queries

    @property
    def is_paid(self) -> bool:
        return self.operation_class is OperationClass.PAID_CREATE

    @property
    def consumed(self) -> bool:
        return self.capability_id in _CONSUMED_PAID

    def describe(self) -> dict:
        """Loggable. Contains no credential and no plan content."""
        return {
            "operation_class": self.operation_class.value,
            "provider": self.provider,
            "operation": self.operation,
            "endpoint": self.endpoint.canonical,
            "plan_digest": self.plan_digest,
            "claim_id": self.claim_id,
            "capability_id": self.capability_id,
        }

    # ------------------------------------------------------------------ checks

    def authorizes(
        self,
        *,
        provider: str,
        operation: str,
        operation_class: OperationClass,
        endpoint: EndpointIdentity | None = None,
    ) -> None:
        """Refuse unless this ticket covers exactly what is being attempted."""
        if self._token is not _MINT_TOKEN:
            raise CapabilityRefused(
                CAPABILITY_INVALID,
                "this capability was not produced by the live gate. Authorization is minted "
                "after the barriers, never constructed by a caller.",
            )
        if self.operation_class is not operation_class:
            raise CapabilityRefused(
                CAPABILITY_CLASS_INSUFFICIENT,
                f"this capability authorizes {self.operation_class.value}, but the operation "
                f"is {operation_class.value}. A read ticket can never create paid work.",
                detail={"held": self.operation_class.value, "needed": operation_class.value},
            )
        if self.provider != provider or self.operation != operation:
            raise CapabilityRefused(
                CAPABILITY_SCOPE_MISMATCH,
                f"this capability authorizes {self.provider}/{self.operation}, not "
                f"{provider}/{operation}. One approval covers one operation.",
                detail={
                    "authorized": f"{self.provider}/{self.operation}",
                    "attempted": f"{provider}/{operation}",
                },
            )
        if endpoint is not None and endpoint != self.endpoint:
            raise CapabilityRefused(
                CAPABILITY_SCOPE_MISMATCH,
                "the provider endpoint changed after this capability was minted. The approved "
                f"destination was {self.endpoint.canonical}; the current configuration resolves "
                f"to {endpoint.canonical}. A credential is never sent to an unapproved host.",
                detail={"approved": self.endpoint.canonical, "current": endpoint.canonical},
            )
        if self.is_paid and self.consumed:
            raise CapabilityRefused(
                CAPABILITY_ALREADY_CONSUMED,
                "this paid capability was already spent. One approved plan buys exactly one "
                "create; a second create needs a new plan, read and confirmed again.",
                detail={"capability_id": self.capability_id, "plan_digest": self.plan_digest},
            )

    def reserve(self) -> None:
        """Claim this ticket for one in-flight request. Called before sending.

        Reserving BEFORE the request rather than consuming after it is what makes a
        crash mid-flight safe: the ticket is already unusable, so nothing in this
        process can retry with it, and the on-disk claim stops a new process.
        """
        if not self.is_paid:
            return
        if self.capability_id in _RESERVED_PAID or self.capability_id in _CONSUMED_PAID:
            raise CapabilityRefused(
                CAPABILITY_ALREADY_CONSUMED,
                "this paid capability was already used. One approved plan buys exactly one "
                "create; a second create needs a new plan, read and confirmed again.",
                detail={"capability_id": self.capability_id, "plan_digest": self.plan_digest},
            )
        _RESERVED_PAID.add(self.capability_id)

    def consume(self) -> None:
        """Mark a reserved ticket finished, whatever the outcome was."""
        if not self.is_paid:
            return
        _CONSUMED_PAID.add(self.capability_id)


def mint(
    *,
    operation_class: OperationClass,
    provider: str,
    operation: str,
    endpoint: EndpointIdentity,
    plan_digest: str = "",
    claim_id: str = "",
) -> ProviderCapability:
    """Produce a capability. Only `live_gate` should call this.

    Every precondition that does not depend on the caller's intent is enforced
    here, so a capability cannot exist in an invalid shape: https is mandatory,
    and a paid ticket without a digest and a claim is refused outright.
    """
    if operation_class is OperationClass.OFFLINE:
        raise CapabilityRefused(
            CAPABILITY_INVALID,
            "OFFLINE operations must not hold a capability: needing one would mean the "
            "operation can reach a provider, which contradicts its declared class.",
        )
    if endpoint.scheme != REQUIRED_LIVE_SCHEME:
        raise CapabilityRefused(
            CAPABILITY_INVALID,
            f"live traffic requires {REQUIRED_LIVE_SCHEME}; {endpoint.canonical} is insecure.",
            detail={"endpoint": endpoint.canonical},
        )
    if operation_class is OperationClass.PAID_CREATE and not (plan_digest and claim_id):
        raise CapabilityRefused(
            CAPABILITY_INVALID,
            "a paid capability must bind both a confirmed plan digest and an acquired "
            "submission claim. Without them nothing limits the approval to one create.",
            detail={"has_plan_digest": bool(plan_digest), "has_claim": bool(claim_id)},
        )
    return ProviderCapability(
        operation_class=operation_class,
        provider=str(provider),
        operation=str(operation),
        endpoint=endpoint,
        plan_digest=str(plan_digest),
        claim_id=str(claim_id),
        _token=_MINT_TOKEN,
    )


def require(
    capability: ProviderCapability | None,
    *,
    provider: str,
    operation: str,
    operation_class: OperationClass,
    endpoint: EndpointIdentity | None = None,
) -> ProviderCapability:
    """The single check every outbound code path performs.

    Called BEFORE a credential is read and before a request is built, so a
    refusal has nothing to leak and nothing half-formed to send.
    """
    if capability is None:
        raise CapabilityRefused(
            CAPABILITY_REQUIRED,
            f"'{operation}' on {provider} would reach a provider and no authorization was "
            "presented. Authorization is minted by the live gate after --live, the machine "
            "opt-in and (for paid work) a confirmed plan. No credential was read.",
            detail={"provider": provider, "operation": operation,
                    "operation_class": operation_class.value},
        )
    capability.authorizes(
        provider=provider,
        operation=operation,
        operation_class=operation_class,
        endpoint=endpoint,
    )
    return capability


def reset_consumed_for_tests() -> None:
    """Test-only hook so single-use accounting does not leak between tests."""
    _RESERVED_PAID.clear()
    _CONSUMED_PAID.clear()
