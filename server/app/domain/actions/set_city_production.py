"""Set city production. Parity: game/domain/actions/set_city_production.gd + GameState unlock gate."""

from __future__ import annotations

from typing import Any

from app.domain.city import City
from app.domain.content import city_project_definitions as cpd
from app.domain.progress_state import ProgressState
from app.domain.scenario import Scenario

SCHEMA_VERSION = 2
ACTION_TYPE = "set_city_production"
PROJECT_TYPE_PRODUCE_UNIT = "produce_unit"


def _city_already_has_matching_produce_project(city: City, requested_project_id: str) -> bool:
    if city.current_project is None:
        return False
    d = city.current_project
    if not isinstance(d, dict):
        return False
    if d.get("project_type") != PROJECT_TYPE_PRODUCE_UNIT:
        return False
    if "project_id" in d:
        return str(d["project_id"]) == requested_project_id
    return True


def validate(
    scenario: Scenario | None,
    progress_state: ProgressState | None,
    action: dict[str, Any] | None,
) -> dict[str, Any]:
    """Unlock gate mirrors GameState.try_apply after structural SetCityProduction.validate."""
    if scenario is None:
        return {"ok": False, "reason": "malformed_action"}
    if action is None or not isinstance(action, dict):
        return {"ok": False, "reason": "wrong_action_type"}
    if action.get("action_type") != ACTION_TYPE:
        return {"ok": False, "reason": "wrong_action_type"}
    if action.get("schema_version") != SCHEMA_VERSION:
        return {"ok": False, "reason": "unsupported_schema_version"}
    if "actor_id" not in action or not isinstance(action["actor_id"], int):
        return {"ok": False, "reason": "malformed_action"}
    if "city_id" not in action or not isinstance(action["city_id"], int):
        return {"ok": False, "reason": "malformed_action"}
    if "project_id" not in action or not isinstance(action["project_id"], str):
        return {"ok": False, "reason": "malformed_action"}

    target = scenario.city_by_id(int(action["city_id"]))
    if target is None:
        return {"ok": False, "reason": "unknown_city"}
    if target.owner_id != int(action["actor_id"]):
        return {"ok": False, "reason": "actor_not_owner"}

    project_id = str(action["project_id"])
    if project_id != cpd.PROJECT_ID_NONE and not cpd.has(project_id):
        return {"ok": False, "reason": "unsupported_project_id"}

    if project_id != cpd.PROJECT_ID_NONE:
        if progress_state is None:
            return {"ok": False, "reason": "city_project_not_unlocked"}
        if not progress_state.has_unlocked_target(
            int(action["actor_id"]), "city_project", project_id
        ):
            return {"ok": False, "reason": "city_project_not_unlocked"}

    if project_id != cpd.PROJECT_ID_NONE and _city_already_has_matching_produce_project(
        target, project_id
    ):
        return {"ok": False, "reason": "project_already_set"}
    if project_id == cpd.PROJECT_ID_NONE and target.current_project is None:
        return {"ok": False, "reason": "project_already_set"}

    return {"ok": True, "reason": ""}


def apply_set_city_production(scenario: Scenario, action: dict[str, Any]) -> Scenario:
    """Replace target city's current_project; progress resets to 0 for new projects."""
    target_id = int(action["city_id"])
    project_id = str(action["project_id"])
    new_project: dict[str, Any] | None
    if project_id == cpd.PROJECT_ID_NONE:
        new_project = None
    else:
        defn = cpd.get_definition(project_id)
        assert defn is not None
        new_project = {
            "project_type": str(defn["project_type"]),
            "project_id": project_id,
            "progress": 0,
            "cost": int(defn["cost"]),
            "ready": False,
        }

    new_cities: list[City] = []
    for c in scenario.cities():
        if c.id != target_id:
            new_cities.append(c)
            continue
        new_cities.append(
            City(
                id=c.id,
                owner_id=c.owner_id,
                position=c.position,
                current_project=new_project,
                city_name=c.city_name,
                is_capital=c.is_capital,
                building_ids=c.building_ids,
                owned_tiles=c.owned_tiles,
                population=c.population,
                manual_worked_tiles=c.manual_worked_tiles,
                food_stored=c.food_stored,
                worked_tiles_mode=c.worked_tiles_mode,
            )
        )
    return scenario.with_cities(tuple(new_cities))


def project_progress_for_event(city: City) -> int | None:
    if city.current_project is None:
        return None
    p = city.current_project.get("progress")
    if p is None:
        return None
    return int(p)
