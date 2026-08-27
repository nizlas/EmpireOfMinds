"""Credential loading and outbound-text scrubbing.

Two rules this module exists to enforce:

1. Credentials are only ever read from the environment, never from a file that
   could be committed and never from a CLI argument that would land in shell
   history.
2. A credential value that has been loaded is registered here, and every string
   that is about to be written to a manifest, log, report or exception passes
   through `scrub()`. That way a provider echoing the key back in an error body
   still cannot leak it into the repository.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass

REDACTED = "***REDACTED***"

# Values registered as secret. Only the values are held; nothing writes them out.
_REGISTERED: set[str] = set()

# Patterns that look like provider credentials regardless of registration. These
# catch a key that was pasted into a file by hand rather than loaded by us.
KEY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("meshy_api_key", re.compile(r"\bmsy_[A-Za-z0-9_\-]{16,}")),
    ("openai_style_key", re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}")),
    ("bearer_header", re.compile(r"(?i)\bauthorization\s*[:=]\s*bearer\s+[A-Za-z0-9._\-]{12,}")),
    ("basic_header", re.compile(r"(?i)\bauthorization\s*[:=]\s*basic\s+[A-Za-z0-9+/=]{12,}")),
)


class MissingCredentialError(RuntimeError):
    """Raised when a provider job needs a credential that is not configured."""

    def __init__(self, env_var: str) -> None:
        super().__init__(
            f"Credential environment variable {env_var} is not set. "
            "Set it in your shell (see .env.example) and retry; "
            "never place it in a tracked file."
        )
        self.env_var = env_var


@dataclass(frozen=True)
class Credential:
    """A loaded provider credential.

    The value is deliberately kept out of `__repr__` so that accidentally
    printing a credential, a dataclass containing one, or a traceback frame
    holding one cannot expose it.
    """

    env_var: str
    _value: str

    def __post_init__(self) -> None:
        register_secret(self._value)

    @property
    def value(self) -> str:
        return self._value

    def __repr__(self) -> str:  # pragma: no cover - trivial
        return f"Credential(env_var={self.env_var!r}, value={REDACTED})"

    __str__ = __repr__


def register_secret(value: str | None) -> None:
    """Register a value so that `scrub()` removes it from any outbound text."""
    if value and len(value) >= 8:
        _REGISTERED.add(value)


def load_credential(env_var: str, *, required: bool = True) -> Credential | None:
    """Read a credential from the environment.

    Returns None when the variable is absent and `required` is False, so callers
    can build an adapter, run mock tests and mark the external job blocked
    instead of failing the whole run.
    """
    raw = os.environ.get(env_var, "")
    value = raw.strip()
    if not value:
        if required:
            raise MissingCredentialError(env_var)
        return None
    return Credential(env_var=env_var, _value=value)


def scrub(text: str) -> str:
    """Remove registered secrets and credential-shaped substrings from `text`."""
    if not text:
        return text
    out = text
    # Longest first so a key that contains another registered value still goes.
    for secret in sorted(_REGISTERED, key=len, reverse=True):
        out = out.replace(secret, REDACTED)
    for _name, pattern in KEY_PATTERNS:
        out = pattern.sub(REDACTED, out)
    return out


def scrub_obj(obj: object) -> object:
    """Recursively scrub strings inside dicts/lists/tuples for manifest writing."""
    if isinstance(obj, str):
        return scrub(obj)
    if isinstance(obj, dict):
        return {scrub(str(k)): scrub_obj(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [scrub_obj(v) for v in obj]
    return obj


def reset_registered_secrets_for_tests() -> None:
    """Test-only hook; production code never clears the registry."""
    _REGISTERED.clear()
