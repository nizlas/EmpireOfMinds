"""Deprecated Scenario/HexMap adapter for production tick + delivery (frozen legacy path).

N8R: this module contains NO tick or delivery algorithm. The production
tick/completion decisions, delivery eligibility, project clearing, unit-id
allocation, and engine-event construction live exclusively in the canonical
app.domain.city_production_rules — this adapter only extracts Scenario city
facts, supplies the legacy worked-tile yields (city_yields.py, a frozen
snapshot-v2 yield POLICY) as the explicit yield input, and materializes the
returned project states and spawn effects into Scenario City/Unit rows.
The N8c WorldMap path feeds the SAME canonical loop with the flat yield
constant and snapshot-v3 materialization — never a copy of this adapter.
Do not extend this path.
"""

from __future__ import annotations

from typing import Any

from app.domain import city_production_rules
from app.domain.city import City
from app.domain.city_yields import production_per_turn
from app.domain.scenario import Scenario
from app.domain.unit import Unit

PRODUCE_UNIT_TYPE = city_production_rules.PROJECT_TYPE_PRODUCE_UNIT
ENGINE_SCHEMA_VERSION = city_production_rules.ENGINE_EVENT_SCHEMA_VERSION


def _city_facts(scenario: Scenario) -> list[city_production_rules.ProducingCityFacts]:
    return [
        city_production_rules.ProducingCityFacts(
            city_id=int(c.id),
            owner_id=int(c.owner_id),
            position=(int(c.position.q), int(c.position.r)),
            current_project=c.current_project if isinstance(c.current_project, dict) else None,
        )
        for c in scenario.cities()
    ]


def _with_project(c: City, project: dict[str, Any] | None) -> City:
    return City(
        id=c.id,
        owner_id=c.owner_id,
        position=c.position,
        current_project=project,
        city_name=c.city_name,
        is_capital=c.is_capital,
        building_ids=c.building_ids,
        owned_tiles=c.owned_tiles,
        population=c.population,
        manual_worked_tiles=c.manual_worked_tiles,
        food_stored=c.food_stored,
        worked_tiles_mode=c.worked_tiles_mode,
    )


def apply_production_tick_for_player(scenario: Scenario, owner_id: int) -> tuple[Scenario, list[dict[str, Any]]]:
    """Scenario materialization of the canonical tick: legacy worked-tile
    yields in, updated City rows and production_progress events out."""
    yields = {
        int(c.id): production_per_turn(scenario, c)
        for c in scenario.cities()
        if int(c.owner_id) == int(owner_id)
    }
    new_project_by_id, events = city_production_rules.tick_production(
        _city_facts(scenario), owner_id, yields
    )
    if not new_project_by_id:
        return scenario, []

    new_cities = tuple(
        _with_project(c, new_project_by_id[c.id]) if c.id in new_project_by_id else c
        for c in scenario.cities()
    )
    new_scenario = Scenario(
        scenario.map,
        scenario.units(),
        new_cities,
        scenario.peek_next_unit_id(),
        scenario.peek_next_city_id(),
        scenario.lightning_tree_hex,
    )
    return new_scenario, events


def deliver_pending_for_player(scenario: Scenario, owner_id: int) -> tuple[Scenario, list[dict[str, Any]]]:
    """Scenario materialization of the canonical delivery: spawn effects
    become Unit rows at the city center, delivered cities' projects clear,
    next_unit_id advances by the canonical allocation."""
    spawns, events, new_next_unit_id = city_production_rules.deliver_completed_production(
        _city_facts(scenario), owner_id, scenario.peek_next_unit_id()
    )
    if not spawns:
        return scenario, []

    delivered_city_ids = {int(s["city_id"]) for s in spawns}
    new_units: list[Unit] = list(scenario.units())
    for s in spawns:
        cty = scenario.city_by_id(int(s["city_id"]))
        assert cty is not None
        # Legacy path uses the default city-center placement (no resolver).
        new_units.append(
            Unit.make(
                int(s["unit_id"]),
                int(s.get("owner_id", cty.owner_id)),
                cty.position,
                str(s["unit_type_id"]),
                -1,
                -1,
            )
        )

    new_cities = tuple(
        _with_project(c, None) if c.id in delivered_city_ids else c
        for c in scenario.cities()
    )
    new_scenario = Scenario(
        scenario.map,
        tuple(new_units),
        new_cities,
        new_next_unit_id,
        scenario.peek_next_city_id(),
        scenario.lightning_tree_hex,
    )
    return new_scenario, events
