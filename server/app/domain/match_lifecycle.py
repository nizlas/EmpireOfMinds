"""Staging → ongoing lifecycle: auto-start and deterministic first player (C14d-2)."""

from __future__ import annotations

import copy
import hashlib
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from app.domain.seats import (
    STATUS_ONGOING,
    STATUS_STAGING,
    derive_ready_to_start,
    match_status,
    player_factions_from_meta,
)

MATCH_STARTED_ACTION_TYPE = "match_started"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def first_player_seed_source(meta: dict[str, Any], match_id: str) -> str:
    seed = meta.get("match_seed")
    if isinstance(seed, str) and seed.strip():
        return seed.strip()
    return str(match_id)


def deterministic_first_player_index(
    meta: dict[str, Any],
    match_id: str,
    players: list[int],
) -> int:
    """Index into turn_state.players order (C14d-0)."""
    if not players:
        return 0
    source = first_player_seed_source(meta, match_id)
    digest = hashlib.sha256(f"{source}:first_player".encode()).hexdigest()
    return int(digest, 16) % len(players)


def deterministic_first_player(
    meta: dict[str, Any],
    match_id: str,
    players: list[int],
) -> tuple[int, int]:
    idx = deterministic_first_player_index(meta, match_id, players)
    return idx, int(players[idx])


def first_player_id_from_meta(meta: dict[str, Any]) -> int | None:
    raw = meta.get("first_player_id")
    if isinstance(raw, int):
        return int(raw)
    return None


@dataclass(frozen=True)
class StartMatchResult:
    started: bool
    meta: dict[str, Any]
    snapshot: dict[str, Any]
    match_started_event: dict[str, Any] | None = None


def try_start_match_if_ready(
    match_id: str,
    meta: dict[str, Any],
    snap: dict[str, Any],
) -> StartMatchResult:
    """Transition staging → ongoing when all seats ready; idempotent if already ongoing."""
    if match_status(meta) != STATUS_STAGING:
        return StartMatchResult(started=False, meta=meta, snapshot=snap, match_started_event=None)
    if not derive_ready_to_start(meta):
        return StartMatchResult(started=False, meta=meta, snapshot=snap, match_started_event=None)

    ts = snap.get("turn_state")
    if not isinstance(ts, dict):
        return StartMatchResult(started=False, meta=meta, snapshot=snap, match_started_event=None)
    players_raw = ts.get("players")
    if not isinstance(players_raw, list) or len(players_raw) < 1:
        return StartMatchResult(started=False, meta=meta, snapshot=snap, match_started_event=None)
    players = [int(p) for p in players_raw]

    started_at = _utc_now_iso()
    first_index, first_player_id = deterministic_first_player(meta, match_id, players)

    new_meta = copy.deepcopy(meta)
    new_meta["status"] = STATUS_ONGOING
    new_meta["started_at"] = started_at
    new_meta["first_player_id"] = first_player_id

    new_snap = copy.deepcopy(snap)
    new_ts = copy.deepcopy(ts)
    new_ts["current_index"] = first_index
    new_snap["turn_state"] = new_ts
    new_snap["player_factions"] = player_factions_from_meta(new_meta)

    event = {
        "action_type": MATCH_STARTED_ACTION_TYPE,
        "first_player_id": first_player_id,
        "started_at": started_at,
        "result": "accepted",
        "accepted_at": started_at,
    }
    return StartMatchResult(
        started=True,
        meta=new_meta,
        snapshot=new_snap,
        match_started_event=event,
    )
