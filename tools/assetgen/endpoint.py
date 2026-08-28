"""Canonical provider endpoint identity.

WHY THIS EXISTS. The forensic review (HIGH 6) found that an approved plan
survived a change to `UTHANA_API_BASE`: the digest stayed byte-identical while
the adapter's base URL — and therefore the destination of an authenticated
upload — moved to another host. An approval that does not name where the request
goes is not an approval of the request.

So the destination is now a first-class, normalised value that goes INTO the plan
digest and is recomputed and compared at submission time. Changing the base URL
changes the digest, which invalidates the approval rather than silently widening
it.

NORMALISATION MATTERS. `https://Uthana.com:443/` and `https://uthana.com` are the
same endpoint and must produce the same identity, or an operator would be asked
to re-approve a plan that did not change. Conversely `http://` and a different
port are genuinely different destinations and must not collapse together.

TRANSPORT SECURITY. A live capability requires `https`. A credential may not be
sent in clear text, and an `http://` base URL — however it got set — is refused
rather than downgraded silently.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import urlsplit

#: Scheme required for any live provider traffic. Not configurable.
REQUIRED_LIVE_SCHEME = "https"

DEFAULT_PORTS = {"https": 443, "http": 80}


class EndpointRefused(ValueError):
    """A base URL that may not be used for live provider traffic."""

    def __init__(self, code: str, message: str) -> None:
        self.code = code
        super().__init__(f"[{code}] {message}")


@dataclass(frozen=True)
class EndpointIdentity:
    """Where a provider call goes, in a form that can be compared and hashed.

    Frozen and fully normalised, so two identities are equal exactly when they
    name the same destination.
    """

    provider: str
    scheme: str
    host: str
    port: int
    base_path: str

    @property
    def canonical(self) -> str:
        """One string that changes whenever the destination changes."""
        return f"{self.provider}|{self.scheme}://{self.host}:{self.port}{self.base_path}"

    @property
    def origin(self) -> str:
        """Scheme, host and port - what a redirect must not cross."""
        return f"{self.scheme}://{self.host}:{self.port}"

    def to_dict(self) -> dict:
        return {
            "provider": self.provider,
            "scheme": self.scheme,
            "host": self.host,
            "port": self.port,
            "base_path": self.base_path,
            "canonical": self.canonical,
        }

    def base_url(self) -> str:
        """The URL an adapter should build requests from."""
        default = DEFAULT_PORTS.get(self.scheme)
        authority = self.host if self.port == default else f"{self.host}:{self.port}"
        return f"{self.scheme}://{authority}{self.base_path}"

    def covers(self, url: str) -> bool:
        """Is `url` on this exact origin? Used to refuse cross-host redirects."""
        try:
            parsed = urlsplit(url)
        except ValueError:
            return False
        scheme = (parsed.scheme or "").lower()
        host = (parsed.hostname or "").lower()
        port = parsed.port or DEFAULT_PORTS.get(scheme, 0)
        return scheme == self.scheme and host == self.host and port == self.port


def parse_endpoint(provider: str, base_url: str, *, require_https: bool = True) -> EndpointIdentity:
    """Normalise a base URL into a comparable identity.

    `require_https` is only relaxed for offline description, never for a live
    capability: `mint` in `capability.py` always demands https.
    """
    raw = str(base_url or "").strip()
    if not raw:
        raise EndpointRefused(
            "PROVIDER_ENDPOINT_MISSING", f"no base URL configured for provider {provider!r}"
        )
    parsed = urlsplit(raw if "//" in raw else f"//{raw}", scheme=REQUIRED_LIVE_SCHEME)
    scheme = (parsed.scheme or "").lower()
    host = (parsed.hostname or "").lower()
    if not host:
        raise EndpointRefused(
            "PROVIDER_ENDPOINT_INVALID", f"base URL {raw!r} for {provider!r} has no host"
        )
    if scheme not in DEFAULT_PORTS:
        raise EndpointRefused(
            "PROVIDER_ENDPOINT_SCHEME_UNSUPPORTED",
            f"base URL {raw!r} uses scheme {scheme!r}; only http and https are understood",
        )
    if require_https and scheme != REQUIRED_LIVE_SCHEME:
        raise EndpointRefused(
            "PROVIDER_ENDPOINT_INSECURE",
            f"base URL {raw!r} for {provider!r} is not https. A credential is never sent "
            "in clear text, and an insecure base URL is refused rather than downgraded.",
        )
    port = parsed.port or DEFAULT_PORTS[scheme]
    base_path = (parsed.path or "").rstrip("/")
    return EndpointIdentity(
        provider=str(provider), scheme=scheme, host=host, port=int(port), base_path=base_path
    )


def resolve_endpoint(
    provider: str,
    *,
    default_base_url: str,
    base_url_env_var: str,
    explicit_base_url: str = "",
    env=None,
    require_https: bool = True,
) -> EndpointIdentity:
    """Resolve the endpoint exactly the way the adapter will use it.

    Precedence is `explicit_base_url` (code-owned, used by tests) then the
    environment variable then the documented default. The environment variable is
    still honoured — it is a legitimate way to point at a staging host — but it
    now flows into the plan digest, so it can no longer move the destination
    behind an existing approval.
    """
    source = os.environ if env is None else env
    chosen = explicit_base_url or str(source.get(base_url_env_var, "") or "") or default_base_url
    return parse_endpoint(provider, chosen, require_https=require_https)
