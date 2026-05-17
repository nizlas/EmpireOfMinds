"""Immutable city project definitions. Parity: game/domain/content/city_project_definitions.gd."""

from __future__ import annotations

import copy
from typing import Any

PROJECT_ID_NONE: str = "none"

_ORDERED_IDS: list[str] = ["produce_unit:warrior", "produce_unit:settler"]

_DEFINITIONS: dict[str, dict[str, Any]] = {
    "produce_unit:warrior": {
        "id": "produce_unit:warrior",
        "display_name": "Train Warrior",
        "project_type": "produce_unit",
        "produces_unit_type": "warrior",
        "cost": 2,
        "role": "basic_unit_training",
    },
    "produce_unit:settler": {
        "id": "produce_unit:settler",
        "display_name": "Train Settler",
        "project_type": "produce_unit",
        "produces_unit_type": "settler",
        "cost": 2,
        "role": "founder_unit_training",
    },
}


def has(project_id: str) -> bool:
    return project_id in _DEFINITIONS


def ids() -> list[str]:
    return list(_ORDERED_IDS)


def get_definition(project_id: str) -> dict[str, Any] | None:
    if not has(project_id):
        return None
    return copy.deepcopy(_DEFINITIONS[project_id])


def project_type(project_id: str) -> str:
    if not has(project_id):
        return ""
    return str(_DEFINITIONS[project_id]["project_type"])


def cost(project_id: str) -> int:
    if not has(project_id):
        return 0
    return int(_DEFINITIONS[project_id]["cost"])


def produces_unit_type(project_id: str) -> str:
    if not has(project_id):
        return ""
    return str(_DEFINITIONS[project_id]["produces_unit_type"])


def is_supported_project_id(project_id: str) -> bool:
    if project_id == PROJECT_ID_NONE:
        return False
    return has(project_id)
