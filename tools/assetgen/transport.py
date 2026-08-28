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
from .secret_guard import SECRET_HEADER_NAMES, redact_headers, scrub

DEFAULT_TIMEOUT_S = 60.0


@dataclass(frozen=True)
class HttpRequest:
    method: str
    url: str
    headers: dict[str, str] = field(default_factory=dict)
    body: bytes | None = None
    timeout_s: float = DEFAULT_TIMEOUT_S
    #: The authorization this request was built under. The production transport
    #: refuses to send without one; the offline double ignores it.
    capability: object | None = None

    def describe(self) -> str:
        """Loggable description. Headers are never included - they carry auth."""
        return f"{self.method} {scrub(self.url)}"

    def safe_headers(self) -> dict:
        """Header names with secret-bearing values redacted by semantics."""
        return redact_headers(self.headers)

    def __repr__(self) -> str:
        """Never print headers or body.

        A dataclass' generated `__repr__` prints every field, and the review
        (HIGH 7) measured the base64 Basic token leaking through exactly that
        route - one `logging.debug(request)` or one traceback with locals is
        enough. Body is omitted too: a multipart upload embeds a whole mesh, and
        an image job body inlines a base64 data URI.
        """
        auth = "authenticated" if any(
            k.lower() in SECRET_HEADER_NAMES for k in self.headers
        ) else "unauthenticated"
        size = len(self.body) if self.body else 0
        return (
            f"HttpRequest(method={self.method!r}, url={scrub(self.url)!r}, "
            f"headers=<{len(self.headers)} headers, {auth}, redacted>, "
            f"body=<{size} bytes>, timeout_s={self.timeout_s})"
        )

    __str__ = __repr__


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


class RefuseRedirects(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect on an authenticated provider request.

    A 3xx that moves an authenticated request to another origin hands the
    credential to a host the plan never approved, and urllib follows redirects by
    default. Same-origin redirects are refused too: every endpoint this repository
    talks to is documented and stable, so a redirect is a change of contract, not
    a routine hop, and refusing is cheaper than reasoning about which hop is safe.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ProviderError(
            ErrorKind.CONTRACT,
            f"provider answered HTTP {code} redirecting to {scrub(str(newurl))}. An "
            "authenticated request is never followed to another location: the approved "
            "plan named one endpoint and the credential belongs only to it.",
            status=int(code),
        )


class UrllibTransport:
    """Real transport, stdlib only so no new dependency is introduced.

    Two policies are enforced here because this is the last place they can be:

    ENVIRONMENT PROXIES ARE DISABLED. `urllib` silently honours `HTTP_PROXY`,
    `HTTPS_PROXY` and `ALL_PROXY`, which means a variable nobody audited could
    route an authenticated upload through an arbitrary host - and the socket
    tripwire would not fire, because a loopback proxy is a permitted connection
    (review MEDIUM 15). An empty `ProxyHandler` removes that channel entirely. A
    proxy is not supported; if one is ever needed it must be an explicit,
    plan-bound configuration rather than an inherited variable.

    A CAPABILITY IS REQUIRED. This is the real egress boundary, so the ticket is
    checked here as well as in the adapters. A request that reaches this method
    without authorization is a bug in a call path, and it fails loudly instead of
    reaching the network.
    """

    def __init__(self) -> None:
        # No ProxyHandler entries => no environment proxy lookup at all.
        self._opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), RefuseRedirects()
        )

    def send(self, request: HttpRequest) -> HttpResponse:
        from .capability import CAPABILITY_REQUIRED, CapabilityRefused, ProviderCapability

        capability = request.capability
        if not isinstance(capability, ProviderCapability):
            raise CapabilityRefused(
                CAPABILITY_REQUIRED,
                f"the production transport refused {request.describe()}: no provider "
                "capability was attached. Every outbound request must carry authorization "
                "minted by the live gate.",
            )
        capability.authorizes(
            provider=capability.provider,
            operation=capability.operation,
            operation_class=capability.operation_class,
        )
        authenticated = any(k.lower() in SECRET_HEADER_NAMES for k in request.headers)
        if authenticated and not capability.endpoint.covers(request.url):
            # An artifact download from a signed CDN URL legitimately leaves the
            # API origin, and carries no credential. An AUTHENTICATED request may
            # not: that is how a redirected or misconfigured base URL would hand
            # the key to someone else.
            raise CapabilityRefused(
                "PROVIDER_CAPABILITY_SCOPE_MISMATCH",
                f"an authenticated request targets {scrub(request.url)} which is not on the "
                f"approved origin {capability.endpoint.origin}. A credential is never sent "
                "to an unapproved host.",
                detail={"approved_origin": capability.endpoint.origin},
            )
        if not request.url.lower().startswith("https://"):
            raise CapabilityRefused(
                "PROVIDER_CAPABILITY_INVALID",
                f"refusing plaintext request {request.describe()}: live provider traffic "
                "requires https.",
            )

        req = urllib.request.Request(
            url=request.url,
            data=request.body,
            headers=dict(request.headers),
            method=request.method,
        )
        try:
            with self._opener.open(req, timeout=request.timeout_s) as resp:
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


#: The policy every CREATING call must use. One attempt, so a transport failure
#: on a paid create can never be turned into a second paid task by this layer.
#: Poll and download keep the retrying policy: they read a task that has already
#: been paid for and cannot create another one.
NO_RETRY = RetryPolicy(max_attempts=1)


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
