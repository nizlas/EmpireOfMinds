"""Deprecated Scenario/HexMap adapter for set_city_production (frozen legacy path).

N8R: this module contains NO selection algorithm. The selection decision
sequence, canonical project state, and event progress representation live
exclusively in the canonical app.domain.city_production_rules — this adapter
only parses the legacy wire envelope, extracts Scenario facts, passes the
progress-unlock gate as an explicit policy input, and materializes the
canonical project state into the snapshot-v2 dict shape (adding the
storage-only project_type and materialized ready keys the legacy tick
representation keeps). Rejection reasons are the canonical literal strings.
Impossible-state defensive branches of the pre-N8R validator (a project dict
without project_id) were dropped with the recovery. Do not extend this path.
"""

from __future__ import annotations

from typing import Any

from app.domain import city_production_rules
from app.domain.city import City
from app.domain.content import city_project_definitions as cpd
from app.domain.progress_state import ProgressState
from app.domain.scenario import Scenario

SCHEMA_VERSION = 2
ACTION_TYPE = "set_city_production"
PROJECT_TYPE_PRODUCE_UNIT = city_production_rules.PROJECT_TYPE_PRODUCE_UNIT


def _city_facts(city: City | None) -> city_production_rules.CityProductionFacts | None:
    if city is None:
        return None
    return city_production_rules.CityProductionFacts(
        owner_id=int(city.owner_id),
        active_project_id=city_production_rules.active_project_id(city.current_project),
    )


def validate(
    scenario: Scenario | None,
    progress_state: ProgressState | None,
    action: dict[str, Any] | None,
) -> dict[str, Any]:
    """Legacy envelope checks, then the canonical selection decision over
    Scenario facts with the legacy unlock gate as the policy input.
    current_player is checked in the API layer, so the adapter passes actor
    as current."""
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

    actor_id = int(action["actor_id"])
    return city_production_rules.validate_set_city_production(
        actor_id=actor_id,
        current_player_id=actor_id,
        city=_city_facts(scenario.city_by_id(int(action["city_id"]))),
        project_id=str(action["project_id"]),
        is_project_unlocked=lambda pid: (
            progress_state is not None
            and progress_state.has_unlocked_target(actor_id, "city_project", pid)
        ),
    )


def apply_set_city_production(scenario: Scenario, action: dict[str, Any]) -> Scenario:
    """Materialize the canonical project state into snapshot-v2 city rows
    (storage keys project_type/ready added around the canonical core). Only
    call after validate ok."""
    target_id = int(action["city_id"])
    project_id = str(action["project_id"])
    canonical = city_production_rules.new_project_state(project_id)
    new_project: dict[str, Any] | None
    if canonical is None:
        new_project = None
    else:
        defn = cpd.get_definition(project_id)
        assert defn is not None
        new_project = {
            "project_type": str(defn["project_type"]),
            **canonical,
            "ready": city_production_rules.project_is_complete(canonical),
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
    """Scenario adapter over the ONE canonical representation."""
    return city_production_rules.project_progress_for_event(city.current_project)
