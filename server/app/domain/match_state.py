"""Minimal match snapshot + turn advancement (TurnState mirror for Cloud 0.1)."""

from __future__ import annotations

import uuid
from typing import Any


def make_match_id() -> str:
    return f"m_{uuid.uuid4().hex}"


def initial_snapshot(match_id: str, player_ids: list[int]) -> dict[str, Any]:
    return {
        "match_id": match_id,
        "schema_version": 1,
        "revision": 0,
        "ruleset": {
            "id": "stub_v0",
            "content_hash": "stub",
            "schema_version": 0,
        },
        "turn_state": {
            "players": list(player_ids),
            "current_index": 0,
            "turn_number": 1,
        },
    }


def current_player_id(snapshot: dict[str, Any]) -> int:
    ts = snapshot["turn_state"]
    players: list[int] = ts["players"]
    return players[int(ts["current_index"])]


def advance_turn_state(turn_state: dict[str, Any]) -> dict[str, Any]:
    """Mirror game/domain/turn_state.gd advance()."""
    players: list[int] = list(turn_state["players"])
    n = len(players)
    current_index = int(turn_state["current_index"])
    turn_number = int(turn_state["turn_number"])
    next_i = (current_index + 1) % n
    next_n = turn_number
    if next_i == 0:
        next_n = turn_number + 1
    return {
        "players": players,
        "current_index": next_i,
        "turn_number": next_n,
    }
