"""Neutral provider-error classification.

Every provider adapter maps its own HTTP statuses and error payloads onto this
one taxonomy. The orchestrator, retry policy and manifests only ever see these
kinds, so retry and blocking behaviour is identical across providers.

Nothing in here influences gameplay: a provider failure can only ever block an
asset job, never change a rule.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .secret_guard import scrub


class ErrorKind(str, Enum):
    AUTH = "AUTH"                          # 401/403 - bad or missing credential
    PAYMENT = "PAYMENT"                    # 402 - insufficient credits
    INVALID_REQUEST = "INVALID_REQUEST"    # 400 - our request is wrong
    NOT_FOUND = "NOT_FOUND"                # 404 - unknown task/resource
    UNPROCESSABLE = "UNPROCESSABLE"        # 422 - valid request, unusable input
    RATE_LIMIT = "RATE_LIMIT"              # 429
    TRANSIENT = "TRANSIENT"                # 5xx
    TIMEOUT = "TIMEOUT"                    # our own deadline elapsed
    TRANSPORT = "TRANSPORT"                # socket/DNS/TLS failure
    PROVIDER_FAILURE = "PROVIDER_FAILURE"  # task reached FAILED status
    CONTRACT = "CONTRACT"                  # response missing fields we require
    EXPIRED_URL = "EXPIRED_URL"            # signed output URL no longer valid
    MISSING_OUTPUT = "MISSING_OUTPUT"      # task SUCCEEDED without the artifact


#: Kinds where retrying the SAME task id can still succeed. Retrying these must
#: never create a second provider task - see `orchestrator.resume`.
RETRYABLE_KINDS: frozenset[ErrorKind] = frozenset(
    {
        ErrorKind.RATE_LIMIT,
        ErrorKind.TRANSIENT,
        ErrorKind.TIMEOUT,
        ErrorKind.TRANSPORT,
    }
)

#: Kinds that block the job and require a human decision.
BLOCKING_KINDS: frozenset[ErrorKind] = frozenset(
    {
        ErrorKind.AUTH,
        ErrorKind.PAYMENT,
        ErrorKind.INVALID_REQUEST,
        ErrorKind.UNPROCESSABLE,
        ErrorKind.PROVIDER_FAILURE,
        ErrorKind.CONTRACT,
        ErrorKind.MISSING_OUTPUT,
    }
)


class ProviderError(Exception):
    """A classified provider failure. Message and detail are always scrubbed."""

    def __init__(
        self,
        kind: ErrorKind,
        message: str,
        *,
        provider: str = "",
        status: int | None = None,
        retry_after_s: float | None = None,
        detail: dict | None = None,
    ) -> None:
        self.kind = kind
        self.provider = provider
        self.status = status
        self.retry_after_s = retry_after_s
        self.message = scrub(message)
        self.detail = detail or {}
        super().__init__(f"[{provider or 'provider'}:{kind.value}] {self.message}")

    @property
    def retryable(self) -> bool:
        return self.kind in RETRYABLE_KINDS

    def to_manifest_dict(self) -> dict:
        return {
            "kind": self.kind.value,
            "provider": self.provider,
            "http_status": self.status,
            "message": self.message,
            "retryable": self.retryable,
        }


@dataclass(frozen=True)
class PreflightFailure:
    """A refusal produced by a local gate before any network call is made."""

    code: str
    message: str
    detail: dict = field(default_factory=dict)


def classify_http_status(status: int, *, provider: str, body_text: str = "") -> ProviderError:
    """Map an HTTP status onto the neutral taxonomy.

    Providers may override for endpoint-specific semantics, but the status
    mapping itself is shared so retry behaviour cannot drift between adapters.
    """
    message = body_text.strip() or f"HTTP {status}"
    if status in (401, 403):
        kind = ErrorKind.AUTH
    elif status == 402:
        kind = ErrorKind.PAYMENT
    elif status == 400:
        kind = ErrorKind.INVALID_REQUEST
    elif status == 404:
        kind = ErrorKind.NOT_FOUND
    elif status == 422:
        kind = ErrorKind.UNPROCESSABLE
    elif status == 429:
        kind = ErrorKind.RATE_LIMIT
    elif status >= 500:
        kind = ErrorKind.TRANSIENT
    else:
        kind = ErrorKind.CONTRACT
    return ProviderError(kind, message, provider=provider, status=status)
