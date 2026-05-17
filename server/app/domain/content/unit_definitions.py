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
