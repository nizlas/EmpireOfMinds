"""Production tick + delivery. Parity: production_tick.gd + production_delivery.gd."""

from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any

from app.domain.city import City
from app.domain.city_yields import production_per_turn
from app.domain.content import city_project_definitions as cpd
from app.domain.scenario import Scenario
from app.domain.unit import Unit

PRODUCE_UNIT_TYPE = "produce_unit"
ENGINE_SCHEMA_VERSION = 1


def _eligible_for_tick(city: City, owner_id: int) -> bool:
    if city.owner_id != owner_id:
        return False
    if city.current_project is None or not isinstance(city.current_project, dict):
        return False
    if bool(city.current_project.get("ready", False)):
        return False
    return True


def apply_production_tick_for_player(scenario: Scenario, owner_id: int) -> tuple[Scenario, list[dict[str, Any]]]:
    """Increment progress for ending player's cities; emits production_progress events (Godot order by city id)."""
    clist = list(scenario.cities())
    ids_to_tick = sorted(
        c.id
        for c in clist
        if _eligible_for_tick(c, owner_id) and production_per_turn(scenario, c) > 0
    )
    if not ids_to_tick:
        return scenario, []

    events: list[dict[str, Any]] = []
    new_project_by_id: dict[int, dict[str, Any]] = {}

    for cid in ids_to_tick:
        c = scenario.city_by_id(cid)
        if c is None:
            continue
        proj_src = c.current_project
        assert isinstance(proj_src, dict)
        project = copy.deepcopy(proj_src)
        old_progress = int(project["progress"])
        delta_p = production_per_turn(scenario, c)
        new_progress = old_progress + delta_p
        project["progress"] = new_progress
        cost_v = int(project["cost"])
        ptype_str = str(project["project_type"])
        if ptype_str == PRODUCE_UNIT_TYPE and new_progress >= cost_v:
            project["ready"] = True
        else:
            project["ready"] = False
        new_project_by_id[cid] = project

        ev_prog: dict[str, Any] = {
            "schema_version": ENGINE_SCHEMA_VERSION,
            "action_type": "production_progress",
            "actor_id": owner_id,
            "city_id": cid,
            "project_type": ptype_str,
            "progress_before": old_progress,
            "progress_after": new_progress,
            "cost": cost_v,
            "source": "engine",
            "result": "accepted",
        }
        if "project_id" in proj_src:
            ev_prog["project_id"] = str(proj_src["project_id"])
        events.append(ev_prog)

    new_cities: list[City] = []
    for c2 in clist:
        if c2.id in new_project_by_id:
            pr = new_project_by_id[c2.id]
            new_cities.append(
                City(
                    id=c2.id,
                    owner_id=c2.owner_id,
                    position=c2.position,
                    current_project=pr,
                    city_name=c2.city_name,
                    is_capital=c2.is_capital,
                    building_ids=c2.building_ids,
                    owned_tiles=c2.owned_tiles,
                    population=c2.population,
                    manual_worked_tiles=c2.manual_worked_tiles,
                    food_stored=c2.food_stored,
                    worked_tiles_mode=c2.worked_tiles_mode,
                )
            )
        else:
            new_cities.append(c2)

    new_scenario = Scenario(
        scenario.map,
        scenario.units(),
        tuple(new_cities),
        scenario.peek_next_unit_id(),
        scenario.peek_next_city_id(),
        scenario.lightning_tree_hex,
    )
    return new_scenario, events


def deliver_pending_for_player(scenario: Scenario, owner_id: int) -> tuple[Scenario, list[dict[str, Any]]]:
    """Spawn units at city center for ready produce_unit projects; clear current_project. Mirrors production_delivery.gd."""
    clist = list(scenario.cities())
    ready_ids = sorted(
        c.id
        for c in clist
        if c.owner_id == owner_id
        and c.current_project is not None
        and isinstance(c.current_project, dict)
        and bool(c.current_project.get("ready", False))
        and str(c.current_project.get("project_type", "")) == PRODUCE_UNIT_TYPE
    )
    if not ready_ids:
        return scenario, []

    delivered = {cid: True for cid in ready_ids}
    events: list[dict[str, Any]] = []
    running_next_unit_id = scenario.peek_next_unit_id()
    completion_order: list[tuple[int, int]] = []

    for rcid in ready_ids:
        cty = scenario.city_by_id(rcid)
        if cty is None:
            continue
        unit_id = running_next_unit_id
        running_next_unit_id += 1
        proj_id = ""
        produced_type = "warrior"
        if cty.current_project and isinstance(cty.current_project, dict):
            proj_id = str(cty.current_project.get("project_id", ""))
        if proj_id and cpd.has(proj_id):
            t = cpd.produces_unit_type(proj_id)
            if t:
                produced_type = t
        up_ev: dict[str, Any] = {
            "schema_version": 1,
            "action_type": "unit_produced",
            "actor_id": owner_id,
            "city_id": rcid,
            "unit_id": unit_id,
            "position": [cty.position.q, cty.position.r],
            "project_type": PRODUCE_UNIT_TYPE,
            "unit_type_id": produced_type,
            "source": "engine",
            "result": "accepted",
        }
        if proj_id:
            up_ev["project_id"] = proj_id
        events.append(up_ev)
        completion_order.append((rcid, unit_id))

    new_units: list[Unit] = list(scenario.units())
    for rcid, uid_assigned in completion_order:
        cy = scenario.city_by_id(rcid)
        if cy is None:
            continue
        produced_type = "warrior"
        if cy.current_project and isinstance(cy.current_project, dict):
            pid = str(cy.current_project.get("project_id", ""))
            if pid and cpd.has(pid):
                t = cpd.produces_unit_type(pid)
                if t:
                    produced_type = t
        new_units.append(
            Unit.make(uid_assigned, cy.owner_id, cy.position, produced_type, -1, -1)
        )

    new_cities: list[City] = []
    for c2 in clist:
        if c2.id in delivered:
            new_cities.append(
                City(
                    id=c2.id,
                    owner_id=c2.owner_id,
                    position=c2.position,
                    current_project=None,
                    city_name=c2.city_name,
                    is_capital=c2.is_capital,
                    building_ids=c2.building_ids,
                    owned_tiles=c2.owned_tiles,
                    population=c2.population,
                    manual_worked_tiles=c2.manual_worked_tiles,
                    food_stored=c2.food_stored,
                    worked_tiles_mode=c2.worked_tiles_mode,
                )
            )
        else:
            new_cities.append(c2)

    new_scenario = Scenario(
        scenario.map,
        tuple(new_units),
        tuple(new_cities),
        running_next_unit_id,
        scenario.peek_next_city_id(),
        scenario.lightning_tree_hex,
    )
    return new_scenario, events


def stamp_events(
    events: list[dict[str, Any]],
    *,
    base_index: int,
    revision: int,
) -> list[dict[str, Any]]:
    """Attach index/revision/accepted_at for Cloud API persistence."""
    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return [
        {
            **ev,
            "index": base_index + i,
            "revision": revision,
            "accepted_at": accepted_at,
        }
        for i, ev in enumerate(events)
    ]
