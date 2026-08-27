"""HTTP transport seam plus the shared retry policy.

Adapters never call urllib directly. They are handed an `HttpTransport`, which
in tests is a deterministic fake. That is what makes every provider path
unit-testable without touching a paid endpoint.
"""

from __future__ import annotations

import json
import random
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Callable, Protocol

from .errors import ErrorKind, ProviderError
from .secret_guard import scrub

DEFAULT_TIMEOUT_S = 60.0


@dataclass(frozen=True)
class HttpRequest:
    method: str
    url: str
    headers: dict[str, str] = field(default_factory=dict)
    body: bytes | None = None
    timeout_s: float = DEFAULT_TIMEOUT_S

    def describe(self) -> str:
        """Loggable description. Headers are never included - they carry auth."""
        return f"{self.method} {scrub(self.url)}"


@dataclass(frozen=True)
class HttpResponse:
    status: int
    headers: dict[str, str] = field(default_factory=dict)
    body: bytes = b""

    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

    def json(self) -> dict:
        try:
            parsed = json.loads(self.body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as exc:
            raise ProviderError(
                ErrorKind.CONTRACT,
                f"Response body was not valid JSON: {exc}",
                status=self.status,
            ) from exc
        if not isinstance(parsed, dict):
            raise ProviderError(
                ErrorKind.CONTRACT,
                f"Expected a JSON object, got {type(parsed).__name__}",
                status=self.status,
            )
        return parsed

    def header(self, name: str) -> str | None:
        lowered = name.lower()
        for key, value in self.headers.items():
            if key.lower() == lowered:
                return value
        return None


class HttpTransport(Protocol):
    def send(self, request: HttpRequest) -> HttpResponse: ...


class UrllibTransport:
    """Real transport, stdlib only so no new dependency is introduced."""

    def send(self, request: HttpRequest) -> HttpResponse:
        req = urllib.request.Request(
            url=request.url,
            data=request.body,
            headers=dict(request.headers),
            method=request.method,
        )
        try:
            with urllib.request.urlopen(req, timeout=request.timeout_s) as resp:
                return HttpResponse(
                    status=int(resp.status),
                    headers={k: v for k, v in resp.headers.items()},
                    body=resp.read(),
                )
        except urllib.error.HTTPError as exc:
            # An HTTP error status is a normal response for us: the adapter
            # classifies it. Only genuine transport faults raise.
            return HttpResponse(
                status=int(exc.code),
                headers={k: v for k, v in (exc.headers or {}).items()},
                body=exc.read() if hasattr(exc, "read") else b"",
            )
        except urllib.error.URLError as exc:
            raise ProviderError(
                ErrorKind.TRANSPORT,
                f"Transport failure for {request.describe()}: {exc.reason}",
            ) from exc
        except TimeoutError as exc:
            raise ProviderError(
                ErrorKind.TIMEOUT,
                f"Timed out after {request.timeout_s}s for {request.describe()}",
            ) from exc


@dataclass(frozen=True)
class RetryPolicy:
    """Bounded exponential backoff with equal jitter.

    `max_attempts` counts the first try. The cap exists so a rate-limited or
    briefly failing provider can never turn into an unbounded spend or an
    unbounded wall-clock hang.
    """

    max_attempts: int = 5
    base_delay_s: float = 1.0
    max_delay_s: float = 30.0
    respect_retry_after: bool = True

    def delay_for(
        self,
        attempt: int,
        *,
        retry_after_s: float | None,
        rng: random.Random,
    ) -> float:
        """Delay before the attempt following `attempt` (1-based)."""
        if self.respect_retry_after and retry_after_s is not None:
            return max(0.0, min(float(retry_after_s), self.max_delay_s))
        uncapped = self.base_delay_s * (2 ** max(0, attempt - 1))
        ceiling = min(uncapped, self.max_delay_s)
        half = ceiling / 2.0
        return half + rng.uniform(0.0, half)


def parse_retry_after(response: HttpResponse) -> float | None:
    raw = response.header("Retry-After")
    if not raw:
        return None
    try:
        return max(0.0, float(raw.strip()))
    except ValueError:
        return None  # HTTP-date form; fall back to exponential backoff.


def send_with_retry(
    transport: HttpTransport,
    request: HttpRequest,
    *,
    policy: RetryPolicy,
    provider: str,
    classify: Callable[[HttpResponse], ProviderError | None],
    sleep: Callable[[float], None] = time.sleep,
    rng: random.Random | None = None,
) -> tuple[HttpResponse, int]:
    """Send `request`, retrying only kinds that can succeed on the same task.

    Returns the successful response and the number of retries consumed. Raises
    the last classified `ProviderError` when attempts run out or the error is
    not retryable.
    """
    generator = rng if rng is not None else random.Random()
    retries = 0
    last_error: ProviderError | None = None

    for attempt in range(1, max(1, policy.max_attempts) + 1):
        try:
            response = transport.send(request)
            error = classify(response)
            if error is None:
                return response, retries
        except ProviderError as exc:
            error = exc

        error.provider = error.provider or provider
        last_error = error
        if not error.retryable or attempt >= policy.max_attempts:
            break

        retry_after = error.retry_after_s
        sleep(policy.delay_for(attempt, retry_after_s=retry_after, rng=generator))
        retries += 1

    assert last_error is not None
    last_error.detail = {**last_error.detail, "attempts": retries + 1}
    raise last_error
