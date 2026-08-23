"""Immutable unit type definitions. Parity: game/domain/content/unit_definitions.gd."""

from __future__ import annotations

import copy
from typing import Any

_ORDERED_IDS: list[str] = ["settler", "warrior"]

_DEFINITIONS: dict[str, dict[str, Any]] = {
    "settler": {
        "id": "settler",
        "display_name": "Settler",
        "can_found_city": True,
        "production_cost": 2,
        "role": "founder",
        "max_movement": 2,
        "combat_strength": 0,
        "max_hp": 100,
    },
    "warrior": {
        "id": "warrior",
        "display_name": "Warrior",
        "can_found_city": False,
        "production_cost": 2,
        "role": "basic_melee",
        "max_movement": 2,
        "combat_strength": 20,
        "max_hp": 100,
    },
    # Debug-only melee type (not in ids()/production roster). Same combat
    # contract as warrior so world attack_unit / legal-actions treat it as a
    # combatant; presentation uses its own GLB on the Godot client.
    "generated_warrior": {
        "id": "generated_warrior",
        "display_name": "Generated Warrior",
        "can_found_city": False,
        "production_cost": 2,
        "role": "basic_melee",
        "max_movement": 2,
        "combat_strength": 20,
        "max_hp": 100,
    },
}


def has(type_id: str) -> bool:
    return type_id in _DEFINITIONS


def get_definition(type_id: str) -> dict[str, Any] | None:
    if not has(type_id):
        return None
    return copy.deepcopy(_DEFINITIONS[type_id])


def ids() -> list[str]:
    return list(_ORDERED_IDS)


def can_found_city(type_id: str) -> bool:
    d = get_definition(type_id)
    return d is not None and bool(d.get("can_found_city", False))


def max_movement_for_type(type_id: str) -> int:
    d = get_definition(type_id)
    if d is None:
        return 0
    return int(d.get("max_movement", 0))


def max_hp_for_type(type_id: str) -> int:
    d = get_definition(type_id)
    if d is None:
        return 0
    return int(d.get("max_hp", 0))


def combat_strength_for_type(type_id: str) -> int:
    d = get_definition(type_id)
    if d is None:
        return 0
    return int(d.get("combat_strength", 0))


def is_melee_combatant(type_id: str) -> bool:
    """World Combat 0.1 eligible attackers/defenders (warrior + debug melee)."""
    d = get_definition(type_id)
    return d is not None and str(d.get("role", "")) == "basic_melee"
