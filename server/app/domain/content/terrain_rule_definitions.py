"""Immutable terrain rule definitions. Parity: game/domain/content/terrain_rule_definitions.gd."""

from __future__ import annotations

import copy
from typing import Any

TERRAIN_ID_UNKNOWN: str = ""

# Parity with game/domain/hex_map.gd Terrain enum order: PLAINS=0, WATER=1, GRASSLAND=2
_TERRAIN_PLAINS = 0
_TERRAIN_WATER = 1
_TERRAIN_GRASSLAND = 2

_ORDERED_IDS: list[str] = ["plains", "water", "grassland"]

_DEFINITIONS: dict[str, dict[str, Any]] = {
    "plains": {
        "id": "plains",
        "display_name": "Plains",
        "passable": True,
        "movement_cost": 1,
        "role": "default_land",
    },
    "water": {
        "id": "water",
        "display_name": "Water",
        "passable": False,
        "movement_cost": 999,
        "role": "blocked",
    },
    "grassland": {
        "id": "grassland",
        "display_name": "Grassland",
        "passable": True,
        "movement_cost": 1,
        "role": "default_land",
    },
}


def has(terrain_id: str) -> bool:
    return terrain_id in _DEFINITIONS


def ids() -> list[str]:
    return list(_ORDERED_IDS)


def get_definition(terrain_id: str) -> dict[str, Any] | None:
    if not has(terrain_id):
        return None
    return copy.deepcopy(_DEFINITIONS[terrain_id])


def is_passable(terrain_id: str) -> bool:
    if not has(terrain_id):
        return False
    return bool(_DEFINITIONS[terrain_id].get("passable", False))


def movement_cost(terrain_id: str) -> int:
    if not has(terrain_id):
        return 999
    return int(_DEFINITIONS[terrain_id].get("movement_cost", 999))


def terrain_id_for_hex_map_value(value: int) -> str:
    if value == _TERRAIN_PLAINS:
        return "plains"
    if value == _TERRAIN_WATER:
        return "water"
    if value == _TERRAIN_GRASSLAND:
        return "grassland"
    return TERRAIN_ID_UNKNOWN


def is_passable_hex_map_value(value: int) -> bool:
    return is_passable(terrain_id_for_hex_map_value(value))
