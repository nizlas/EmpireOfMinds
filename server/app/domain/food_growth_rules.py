"""Food surplus -> food_stored -> population growth. Parity: food_growth_tick.gd."""

from __future__ import annotations

import math
from typing import Any

from app.domain.city import City
from app.domain.city_yields import city_total_yield, get_yield
from app.domain.scenario import Scenario

SCHEMA_VERSION = 1
EVENT_TYPE_PROGRESS = "food_growth_progress"
EVENT_TYPE_GREW = "city_grew"


def growth_threshold(pop: int) -> int:
    p = max(1, int(pop))
    j = p - 1
    return 15 + j * 8 + int(math.floor(math.pow(float(j), 1.5)))


def apply_food_growth_for_player(scenario: Scenario, owner_id: int) -> tuple[Scenario, list[dict[str, Any]]]:
    owned = scenario.cities_owned_by(owner_id)
    if not owned:
        return scenario, []

    ids_sorted = sorted(c.id for c in owned if c is not None)
    updates: dict[int, dict[str, int]] = {}
    events: list[dict[str, Any]] = []

    for cid in ids_sorted:
        city = scenario.city_by_id(cid)
        if city is None:
            continue
        y = city_total_yield(scenario, city)
        total_food = get_yield(y, "food")
        consumption = int(city.population) * 2
        surplus = int(total_food) - consumption
        if surplus <= 0:
            continue

        old_pop = int(city.population)
        old_stored = int(city.food_stored)
        threshold = growth_threshold(old_pop)
        new_stored = old_stored + surplus
        new_pop = old_pop
        if new_stored >= threshold:
            new_pop = old_pop + 1
            new_stored -= threshold

        prog: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "action_type": EVENT_TYPE_PROGRESS,
            "source": "engine",
            "result": "accepted",
            "actor_id": owner_id,
            "city_id": cid,
            "food_stored_before": old_stored,
            "food_stored_after": new_stored,
            "population_before": old_pop,
            "population_after": new_pop,
            "total_food": total_food,
            "consumption": consumption,
            "surplus": surplus,
            "growth_threshold": threshold,
        }
        events.append(prog)

        if new_pop > old_pop:
            grew: dict[str, Any] = {
                "schema_version": SCHEMA_VERSION,
                "action_type": EVENT_TYPE_GREW,
                "source": "engine",
                "result": "accepted",
                "actor_id": owner_id,
                "city_id": cid,
                "population_before": old_pop,
                "population_after": new_pop,
                "food_stored_after": new_stored,
            }
            events.append(grew)

        updates[cid] = {"population": new_pop, "food_stored": new_stored}

    if not updates:
        return scenario, []

    clist = list(scenario.cities())
    new_cities: list[City] = []
    for c2 in clist:
        if c2.id in updates:
            u = updates[c2.id]
            new_cities.append(
                City(
                    id=c2.id,
                    owner_id=c2.owner_id,
                    position=c2.position,
                    current_project=c2.current_project,
                    city_name=c2.city_name,
                    is_capital=c2.is_capital,
                    building_ids=c2.building_ids,
                    owned_tiles=c2.owned_tiles,
                    population=int(u["population"]),
                    manual_worked_tiles=c2.manual_worked_tiles,
                    food_stored=int(u["food_stored"]),
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
