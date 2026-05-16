"""Canonical JSON + SHA-256 for Cloud 0.1 snapshots."""

from __future__ import annotations

import hashlib
import json
from typing import Any


def canonical_json_bytes(obj: dict[str, Any]) -> bytes:
    """Sorted keys, compact separators, UTF-8. Matches CLOUD_API_V0.md."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )


def state_hash(snapshot: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json_bytes(snapshot)).hexdigest()
