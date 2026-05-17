"""Turn order state. Parity: game/domain/turn_state.gd."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TurnState:
    players: tuple[int, ...]
    current_index: int
    turn_number: int

    def current_player_id(self) -> int:
        return self.players[self.current_index]


def advance_turn_state(turn_state: dict[str, object]) -> dict[str, object]:
    """Mirror TurnState.advance -> plain dict for snapshot storage."""
    players: list[int] = list(turn_state["players"])  # type: ignore[arg-type]
    n = len(players)
    current_index = int(turn_state["current_index"])
    turn_number = int(turn_state["turn_number"])
    next_i = (current_index + 1) % n
    next_n = turn_number
    if next_i == 0:
        next_n = turn_number + 1
    return {"players": players, "current_index": next_i, "turn_number": next_n}


def turn_state_from_players(player_ids: list[int]) -> dict[str, object]:
    return {
        "players": list(player_ids),
        "current_index": 0,
        "turn_number": 1,
    }
