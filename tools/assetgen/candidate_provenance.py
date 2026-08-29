"""Finding the provenance record that describes a specific candidate file.

Shared by the pre-upload gate and the plan builder so both answer "what is this
file, and where did it come from" the same way. The rule that matters is the
matching rule: a provenance record is accepted only when its recorded output
digest equals the digest of the bytes on disk. A record beside a regenerated file
describes something that no longer exists, and inheriting its description would be
the quiet kind of wrong.
"""

from __future__ import annotations

import json
from pathlib import Path

from .manifest import sha256_file

#: Suffix the static export writes beside its candidate.
PROVENANCE_SUFFIX = ".provenance.json"


def provenance_path_for(candidate: Path) -> Path | None:
    """The provenance file that would describe this candidate, if it exists."""
    resolved = Path(candidate)
    beside = resolved.parent / (resolved.stem + PROVENANCE_SUFFIX)
    return beside if beside.is_file() else None


def read_provenance(candidate: Path) -> tuple[dict | None, Path | None]:
    """The provenance record for these exact bytes, or `(None, None)`.

    Returns `None` for a missing, unreadable, malformed or **stale** record. A
    caller cannot tell those apart on purpose: every one of them means the same
    thing, which is that nothing here describes this file.
    """
    path = provenance_path_for(candidate)
    if path is None:
        return None, None
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None, None
    if not isinstance(record, dict):
        return None, None
    output = record.get("output")
    recorded = str(output.get("sha256", "")) if isinstance(output, dict) else ""
    if not recorded or recorded != sha256_file(Path(candidate)):
        return None, None
    return record, path


def provenance_digest(candidate: Path) -> str | None:
    """SHA-256 of the provenance FILE itself, for a plan to bind.

    The candidate digest says which bytes would be uploaded; this says which
    account of their origin was read while deciding to upload them. Editing the
    record therefore invalidates an approval, which is the intended behaviour: the
    classification and the human review both rest on it.
    """
    record, path = read_provenance(candidate)
    if record is None or path is None:
        return None
    return sha256_file(path)


def derived_from(candidate: Path) -> dict | None:
    """The source asset a derived candidate was produced from, if declared."""
    record, _ = read_provenance(candidate)
    if record is None:
        return None
    source = record.get("source")
    if not isinstance(source, dict):
        return None
    return {"path": source.get("path"), "sha256": source.get("sha256")}


__all__ = [
    "PROVENANCE_SUFFIX",
    "derived_from",
    "provenance_digest",
    "provenance_path_for",
    "read_provenance",
]
