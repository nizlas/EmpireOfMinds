"""Local filenames are derived from trusted data, never from a provider string.

WHY. The forensic review (HIGH 3) demonstrated a real arbitrary-write primitive:
the Uthana adapter built its download filename as
`f"{provider_task_id}_rigged.glb"`, and the orchestrator joined that onto the
outputs directory. `pathlib` discards the left operand when the right is
absolute, so a character id of `C:/Windows/Temp/EOM_AUDIT_ABS` wrote a file into
`C:\\Windows\\Temp`. A relative id of `../../../../ESCAPED` escaped upward. The
audit verified both, then deleted the evidence.

THE FIX IS NOT SANITISATION. Sanitising a hostile string is a losing game across
two operating systems: separators, alternate separators, drive letters, UNC
paths, NTFS alternate data streams, reserved device names, percent-encoding and
Unicode normalisation are all in play. So the provider string is not used at all.

A local filename is now built from data WE own - the plan digest or local run id,
our neutral artifact `kind`, and a fixed extension - and the provider's own
suggestion is kept beside it as metadata for the audit trail. There is nothing to
escape with, because nothing from the provider reaches the path.

The validation below is therefore a second line, not the first: it exists so that
a future caller who does pass an untrusted name gets a classified refusal instead
of a write.
"""

from __future__ import annotations

import os
import re
import unicodedata
from pathlib import Path, PurePosixPath, PureWindowsPath

UNSAFE_OUTPUT_PATH = "PROVIDER_OUTPUT_PATH_UNSAFE"

#: Windows device names, refused with or without an extension. Writing to `CON`
#: or `LPT1` is not a file operation at all.
RESERVED_DEVICE_NAMES: frozenset[str] = frozenset(
    {"CON", "PRN", "AUX", "NUL"}
    | {f"COM{i}" for i in range(1, 10)}
    | {f"LPT{i}" for i in range(1, 10)}
)

#: Characters that may never appear in a name we generate or accept. `:` covers
#: both drive letters and NTFS alternate data streams (`file.glb:hidden`).
FORBIDDEN_NAME_CHARS = set('<>:"|?*\\/\x00')

#: What a trusted generated name is allowed to look like, and nothing else.
SAFE_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")

#: `os.open` defaults to TEXT mode on Windows, where every 0x0A in the payload is
#: written as 0x0D 0x0A. A GLB, a PNG or a provider bundle written that way is
#: silently corrupted and longer than its own declared header says. `O_BINARY`
#: does not exist on POSIX, hence the lookup.
_BINARY_FLAG = getattr(os, "O_BINARY", 0)


class UnsafeOutputPath(ValueError):
    """A destination that is not provably inside the intended artifact root."""

    code = UNSAFE_OUTPUT_PATH

    def __init__(self, reason: str, *, offending: str = "") -> None:
        self.reason = reason
        self.offending = offending
        super().__init__(
            f"[{UNSAFE_OUTPUT_PATH}] {reason}"
            + (f" (offending value: {offending!r})" if offending else "")
        )


def trusted_artifact_name(*, run_id: str, kind: str, extension: str) -> str:
    """Build a local filename entirely from data this repository controls.

    `run_id` is a local job id or plan digest, `kind` is our neutral artifact
    name. Neither comes from a provider response. The result is asserted safe
    before it is returned, so a bug in the caller's inputs fails here rather than
    at the filesystem.
    """
    cleaned_kind = re.sub(r"[^A-Za-z0-9]+", "_", str(kind)).strip("_").lower() or "artifact"
    cleaned_run = re.sub(r"[^A-Za-z0-9]+", "_", str(run_id)).strip("_") or "run"
    suffix = str(extension or "").lstrip(".").lower()
    suffix = re.sub(r"[^a-z0-9]+", "", suffix) or "bin"
    name = f"{cleaned_run[:80]}__{cleaned_kind[:60]}.{suffix}"
    if not SAFE_NAME_PATTERN.match(name):
        raise UnsafeOutputPath(
            "generated artifact name is not in the trusted form", offending=name
        )
    if name.split(".")[0].upper() in RESERVED_DEVICE_NAMES:
        raise UnsafeOutputPath("generated artifact name is a reserved device name", offending=name)
    return name


def assert_safe_component(candidate: str) -> str:
    """Refuse anything that is not a single, ordinary path component.

    Checked against both POSIX and Windows interpretations, because a name that
    is inert on one is a traversal on the other and this repository is developed
    on Windows and run in CI.
    """
    raw = str(candidate or "")
    if not raw:
        raise UnsafeOutputPath("empty output name")
    # Normalise first: a decomposed or full-width character that folds to `/`
    # or `.` must be judged by what it becomes, not by how it was written.
    normalised = unicodedata.normalize("NFKC", raw)
    if normalised != raw:
        raise UnsafeOutputPath(
            "output name changes under Unicode normalisation", offending=raw
        )
    if any(ch in FORBIDDEN_NAME_CHARS for ch in raw):
        raise UnsafeOutputPath("output name contains a path or stream separator", offending=raw)
    if raw in (".", "..") or raw.startswith(".."):
        raise UnsafeOutputPath("output name is a traversal", offending=raw)
    for flavour in (PurePosixPath, PureWindowsPath):
        parsed = flavour(raw)
        if parsed.is_absolute() or parsed.anchor:
            raise UnsafeOutputPath("output name is an absolute path", offending=raw)
        if len(parsed.parts) != 1:
            raise UnsafeOutputPath("output name contains more than one component", offending=raw)
    if PureWindowsPath(raw).drive or raw.startswith("\\\\") or raw.startswith("//"):
        raise UnsafeOutputPath("output name is a drive or UNC path", offending=raw)
    if raw.split(".")[0].upper() in RESERVED_DEVICE_NAMES:
        raise UnsafeOutputPath("output name is a reserved device name", offending=raw)
    return raw


def resolve_within(root: Path, name: str) -> Path:
    """Join a single trusted component to `root` and prove the result is inside.

    The proof is done on RESOLVED paths, so a symlinked or junctioned outputs
    directory pointing elsewhere is refused rather than followed. `root` itself is
    resolved first, so a legitimately symlinked artifact root still works while a
    symlink that leaves it does not.
    """
    assert_safe_component(name)
    resolved_root = Path(root).resolve()
    candidate = resolved_root / name
    final = candidate.resolve() if candidate.exists() else _resolve_parent(candidate)
    if final != resolved_root / name and not _is_within(final, resolved_root):
        raise UnsafeOutputPath(
            f"destination resolves to {final} which is outside {resolved_root}", offending=name
        )
    if not _is_within(final, resolved_root):
        raise UnsafeOutputPath(
            f"destination resolves to {final} which is outside {resolved_root}", offending=name
        )
    return final


def _resolve_parent(candidate: Path) -> Path:
    """Resolve a path whose leaf does not exist yet, following parent symlinks."""
    parent = candidate.parent
    resolved_parent = parent.resolve() if parent.exists() else parent
    return resolved_parent / candidate.name


def _is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def write_verified_bytes(destination: Path, payload: bytes) -> Path:
    """Write to a destination the CALLER already proved safe, atomically.

    Adapters get a fully-formed `Path` from the orchestrator, which derived it from
    trusted data. They must not re-derive or re-interpret it, so this helper only
    adds atomicity and durability: temporary file beside the target, fsync, then
    replace. A truncated download is never visible under the artifact name.
    """
    target = Path(destination)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".partial")
    handle = os.open(temporary, os.O_CREAT | os.O_TRUNC | os.O_WRONLY | _BINARY_FLAG)
    try:
        os.write(handle, payload)
        os.fsync(handle)
    finally:
        os.close(handle)
    os.replace(temporary, target)
    return target


def write_bytes_within(root: Path, name: str, payload: bytes) -> Path:
    """Write `payload` to a proven-safe destination beneath `root`, atomically.

    The temporary file is created beside the final destination, inside the same
    proven root, so the rename never crosses a filesystem and a partial write is
    never visible at the artifact path.
    """
    destination = resolve_within(root, name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".partial")
    handle = os.open(temporary, os.O_CREAT | os.O_TRUNC | os.O_WRONLY | _BINARY_FLAG)
    try:
        os.write(handle, payload)
        os.fsync(handle)
    finally:
        os.close(handle)
    os.replace(temporary, destination)
    return destination
