"""Per-match snapshot.json + append-only events.jsonl."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

_LINE_SEP = "\n"


def _server_root() -> Path:
    # server/app/storage/file_store.py -> server/
    return Path(__file__).resolve().parent.parent.parent


def matches_root() -> Path:
    env = os.environ.get("EMPIRE_SERVER_DATA_DIR")
    if env:
        return Path(env) / "matches"
    return _server_root() / "data" / "matches"


def match_dir(match_id: str) -> Path:
    return matches_root() / match_id


def snapshot_path(match_id: str) -> Path:
    return match_dir(match_id) / "snapshot.json"


def events_path(match_id: str) -> Path:
    return match_dir(match_id) / "events.jsonl"


def meta_path(match_id: str) -> Path:
    return match_dir(match_id) / "meta.json"


def ensure_match_dir(match_id: str) -> Path:
    d = match_dir(match_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def write_snapshot(match_id: str, snapshot: dict[str, Any]) -> None:
    ensure_match_dir(match_id)
    p = snapshot_path(match_id)
    p.write_text(json.dumps(snapshot, indent=2) + _LINE_SEP, encoding="utf-8")


def read_snapshot(match_id: str) -> dict[str, Any] | None:
    p = snapshot_path(match_id)
    if not p.is_file():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def write_meta(match_id: str, meta: dict[str, Any]) -> None:
    ensure_match_dir(match_id)
    p = meta_path(match_id)
    p.write_text(json.dumps(meta, indent=2) + _LINE_SEP, encoding="utf-8")


def read_meta(match_id: str) -> dict[str, Any] | None:
    p = meta_path(match_id)
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def append_event(match_id: str, event: dict[str, Any]) -> None:
    ensure_match_dir(match_id)
    line = json.dumps(event, separators=(",", ":"), ensure_ascii=False)
    with events_path(match_id).open("a", encoding="utf-8") as f:
        f.write(line + _LINE_SEP)


def list_match_ids() -> list[str]:
    """Match directory names under matches_root (unordered scan)."""
    root = matches_root()
    if not root.is_dir():
        return []
    out: list[str] = []
    for entry in root.iterdir():
        if entry.is_dir():
            out.append(entry.name)
    return sorted(out)


def read_events(match_id: str) -> list[dict[str, Any]]:
    p = events_path(match_id)
    if not p.is_file():
        return []
    out: list[dict[str, Any]] = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out
