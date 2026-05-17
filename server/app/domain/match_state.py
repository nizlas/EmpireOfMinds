"""Match id + snapshot v2 envelope helpers."""

from __future__ import annotations

import uuid
from typing import Any

from app.domain import snapshot


def make_match_id() -> str:
    return f"m_{uuid.uuid4().hex}"


def initial_snapshot(
    match_id: str,
    player_ids: list[int],
    scenario_id: str = "prototype_play",
) -> dict[str, Any]:
    return snapshot.build_initial_snapshot(match_id, player_ids, scenario_id)


def current_player_id(snap: dict[str, Any]) -> int:
    ts = snap["turn_state"]
    players: list[int] = ts["players"]  # type: ignore[assignment]
    return players[int(ts["current_index"])]
