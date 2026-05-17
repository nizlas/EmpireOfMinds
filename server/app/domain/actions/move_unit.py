"""Move unit action. Parity: game/domain/actions/move_unit.gd (cloud rejection strings differ where specified)."""

from __future__ import annotations

from typing import Any

from app.domain.hex_coord import HexCoord
from app.domain.movement_rules import MOVEMENT_COST_PER_STEP
from app.domain.scenario import Scenario
from app.domain.unit import Unit

SCHEMA_VERSION = 1
ACTION_TYPE = "move_unit"


def validate(scenario: Scenario | None, action: dict[str, Any] | None) -> dict[str, Any]:
    """Returns {\"ok\": bool, \"reason\": str}. current_player checked in API layer."""
    if scenario is None:
        return {"ok": False, "reason": "malformed_action"}
    if action is None:
        return {"ok": False, "reason": "wrong_action_type"}
    if not isinstance(action, dict):
        return {"ok": False, "reason": "wrong_action_type"}
    if action.get("action_type") != ACTION_TYPE:
        return {"ok": False, "reason": "wrong_action_type"}
    if action.get("schema_version") != SCHEMA_VERSION:
        return {"ok": False, "reason": "unsupported_schema_version"}

    if (
        "actor_id" not in action
        or "unit_id" not in action
        or "from" not in action
        or "to" not in action
    ):
        return {"ok": False, "reason": "malformed_action"}
    if not isinstance(action["actor_id"], int) or not isinstance(action["unit_id"], int):
        return {"ok": False, "reason": "malformed_action"}
    from_a = action["from"]
    to_a = action["to"]
    if not isinstance(from_a, list) or not isinstance(to_a, list):
        return {"ok": False, "reason": "malformed_action"}
    if len(from_a) != 2 or len(to_a) != 2:
        return {"ok": False, "reason": "malformed_action"}
    if not all(isinstance(x, int) for x in (*from_a, *to_a)):
        return {"ok": False, "reason": "malformed_action"}

    u = scenario.unit_by_id(int(action["unit_id"]))
    if u is None:
        return {"ok": False, "reason": "unknown_unit"}
    if u.owner_id != int(action["actor_id"]):
        return {"ok": False, "reason": "unit_not_owned_by_player"}

    from_c = HexCoord(int(from_a[0]), int(from_a[1]))
    if u.position != from_c:
        return {"ok": False, "reason": "from_does_not_match_unit_position"}

    if u.remaining_movement < MOVEMENT_COST_PER_STEP:
        return {"ok": False, "reason": "movement_exhausted"}

    to_c = HexCoord(int(to_a[0]), int(to_a[1]))
    vr_dest = _validate_destination(scenario, u, to_c)
    if vr_dest is not None:
        return {"ok": False, "reason": vr_dest}

    return {"ok": True, "reason": ""}


def _validate_destination(scenario: Scenario, unit: Unit, to_c: HexCoord) -> str | None:
    if not scenario.map.has(to_c):
        return "destination_not_on_map"
    if HexCoord.axial_distance(unit.position, to_c) != 1:
        return "destination_not_adjacent"
    t = scenario.map.terrain_at(to_c)
    from app.domain.content import terrain_rule_definitions as trd

    if not trd.is_passable_hex_map_value(int(t)):
        return "destination_not_passable"
    if len(scenario.units_at(to_c)) != 0:
        return "destination_occupied"
    return None


def apply_move(scenario: Scenario, action: dict[str, Any]) -> Scenario:
    """Rebuild scenario with moved unit; only call after validate ok."""
    to_a = action["to"]
    to_c = HexCoord(int(to_a[0]), int(to_a[1]))
    uid = int(action["unit_id"])
    new_units: list[Unit] = []
    for u in scenario.units():
        if u.id != uid:
            new_units.append(u)
            continue
        new_units.append(
            Unit.make(
                u.id,
                u.owner_id,
                to_c,
                u.type_id,
                remaining_movement=u.remaining_movement - MOVEMENT_COST_PER_STEP,
                current_hp=u.current_hp,
            )
        )
    return scenario.with_units(tuple(new_units))
