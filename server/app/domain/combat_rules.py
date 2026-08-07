"""Deterministic melee resolution (Local Combat 0.1). Parity: game/domain/combat_rules.gd."""

from __future__ import annotations

import math
from typing import Any

from app.domain.content import unit_definitions
from app.domain.scenario import Scenario

BASE_DAMAGE = 30
STRENGTH_DIVISOR = 25.0
MIN_DAMAGE = 1
MAX_DAMAGE = 100


def effective_strength(unit, _scenario: Scenario) -> int:
    if unit is None:
        return 0
    return unit_definitions.combat_strength_for_type(str(unit.type_id))


def damage_for_strengths(attacker_strength: int, defender_strength: int) -> int:
    diff = attacker_strength - defender_strength
    raw = float(BASE_DAMAGE) * math.exp(float(diff) / STRENGTH_DIVISOR)
    d = round(raw)
    return max(MIN_DAMAGE, min(MAX_DAMAGE, d))


def resolve_combat(
    attacker_strength: int,
    defender_strength: int,
    attacker_hp: int,
    defender_hp: int,
) -> dict[str, Any]:
    """Pure Local Combat 0.1 core, shared by the legacy Scenario path and the
    N7g world path (single formula — never a drifting duplicate): defender
    takes clamped exponential damage first, retaliation only if the defender
    survives, elimination at 0 HP."""
    def_dmg = damage_for_strengths(attacker_strength, defender_strength)
    def_hp_after = max(0, int(defender_hp) - def_dmg)
    atk_hp_after = int(attacker_hp)
    retaliated = False
    if def_hp_after > 0:
        atk_dmg = damage_for_strengths(defender_strength, attacker_strength)
        atk_hp_after = max(0, int(attacker_hp) - atk_dmg)
        retaliated = True
    return {
        "attacker_strength": int(attacker_strength),
        "defender_strength": int(defender_strength),
        "attacker_damage_taken": int(attacker_hp) - atk_hp_after,
        "defender_damage_taken": int(defender_hp) - def_hp_after,
        "attacker_hp_before": int(attacker_hp),
        "defender_hp_before": int(defender_hp),
        "attacker_hp_after": atk_hp_after,
        "defender_hp_after": def_hp_after,
        "attacker_killed": atk_hp_after <= 0,
        "defender_killed": def_hp_after <= 0,
        "retaliated": retaliated,
    }


def resolve_attack(scenario: Scenario, action: dict[str, Any]) -> dict[str, Any]:
    """Assumes attack_unit.validate succeeded."""
    attacker = scenario.unit_by_id(int(action["attacker_id"]))
    defender = scenario.unit_by_id(int(action["defender_id"]))
    assert attacker is not None and defender is not None
    return {
        "attacker_id": int(attacker.id),
        "defender_id": int(defender.id),
        **resolve_combat(
            effective_strength(attacker, scenario),
            effective_strength(defender, scenario),
            int(attacker.current_hp),
            int(defender.current_hp),
        ),
    }
