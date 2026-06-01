"""Attack unit action (Local Combat 0.1). Parity: game/domain/actions/attack_unit.gd."""

from __future__ import annotations

from typing import Any

from app.domain.combat_rules import resolve_attack
from app.domain.hex_coord import HexCoord
from app.domain.scenario import Scenario
from app.domain.unit import Unit

SCHEMA_VERSION = 1
ACTION_TYPE = "attack_unit"
WARRIOR_TYPE = "warrior"


def validate(scenario: Scenario | None, action: dict[str, Any] | None) -> dict[str, Any]:
    """Returns {\"ok\": bool, \"reason\": str}. current_player checked in API layer."""
    if scenario is None:
        return {"ok": False, "reason": "scenario_null"}
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
        or "attacker_id" not in action
        or "defender_id" not in action
    ):
        return {"ok": False, "reason": "malformed_action"}
    if not all(isinstance(action[k], int) for k in ("actor_id", "attacker_id", "defender_id")):
        return {"ok": False, "reason": "malformed_action"}

    attacker = scenario.unit_by_id(int(action["attacker_id"]))
    if attacker is None:
        return {"ok": False, "reason": "unknown_attacker"}
    defender = scenario.unit_by_id(int(action["defender_id"]))
    if defender is None:
        return {"ok": False, "reason": "unknown_defender"}
    if attacker.owner_id != int(action["actor_id"]):
        return {"ok": False, "reason": "actor_not_owner"}
    if str(attacker.type_id) != WARRIOR_TYPE:
        return {"ok": False, "reason": "attacker_not_warrior"}
    if str(defender.type_id) != WARRIOR_TYPE:
        return {"ok": False, "reason": "defender_not_warrior"}
    if attacker.owner_id == defender.owner_id:
        return {"ok": False, "reason": "cannot_attack_own_unit"}
    if HexCoord.axial_distance(attacker.position, defender.position) != 1:
        return {"ok": False, "reason": "defender_not_adjacent"}
    if attacker.remaining_movement < 1:
        return {"ok": False, "reason": "movement_exhausted"}
    return {"ok": True, "reason": ""}


def apply_with_result(
    scenario: Scenario, action: dict[str, Any], combat_result: dict[str, Any]
) -> Scenario:
    """Rebuild scenario after combat; only call after validate ok and resolve_attack."""
    vr = validate(scenario, action)
    assert vr["ok"], "attack_unit.apply_with_result called with invalid action"
    attacker_id = int(action["attacker_id"])
    defender_id = int(action["defender_id"])
    atk_killed = bool(combat_result["attacker_killed"])
    def_killed = bool(combat_result["defender_killed"])
    atk_hp_after = int(combat_result["attacker_hp_after"])
    def_hp_after = int(combat_result["defender_hp_after"])
    new_units: list[Unit] = []
    for u in scenario.units():
        if atk_killed and u.id == attacker_id:
            continue
        if def_killed and u.id == defender_id:
            continue
        if not atk_killed and u.id == attacker_id:
            new_units.append(
                Unit.make(
                    u.id,
                    u.owner_id,
                    u.position,
                    u.type_id,
                    remaining_movement=0,
                    current_hp=atk_hp_after,
                )
            )
            continue
        if not def_killed and u.id == defender_id:
            new_units.append(
                Unit.make(
                    u.id,
                    u.owner_id,
                    u.position,
                    u.type_id,
                    remaining_movement=u.remaining_movement,
                    current_hp=def_hp_after,
                )
            )
            continue
        new_units.append(u)
    return scenario.with_units(tuple(new_units))
