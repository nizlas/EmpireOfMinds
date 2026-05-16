"""End turn action validation (structural only; current-player gate is in API layer)."""

from __future__ import annotations

from typing import Any

SCHEMA_VERSION = 1
ACTION_TYPE = "end_turn"


def validate(turn_state: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Returns {"ok": bool, "reason": str}. Mirrors game/domain/actions/end_turn.gd."""
    if turn_state is None:
        return {"ok": False, "reason": "turn_state_null"}
    if action is None:
        return {"ok": False, "reason": "wrong_action_type"}
    if not isinstance(action, dict):
        return {"ok": False, "reason": "wrong_action_type"}
    if "action_type" not in action:
        return {"ok": False, "reason": "wrong_action_type"}
    if action["action_type"] != ACTION_TYPE:
        return {"ok": False, "reason": "wrong_action_type"}
    if "schema_version" not in action:
        return {"ok": False, "reason": "unsupported_schema_version"}
    if action["schema_version"] != SCHEMA_VERSION:
        return {"ok": False, "reason": "unsupported_schema_version"}
    if "actor_id" not in action:
        return {"ok": False, "reason": "malformed_action"}
    if not isinstance(action["actor_id"], int):
        return {"ok": False, "reason": "malformed_action"}
    return {"ok": True, "reason": ""}
