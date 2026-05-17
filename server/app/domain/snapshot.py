"""Match snapshot v2 builders."""

from __future__ import annotations

import copy
from typing import Any

from app.domain.city import City
from app.domain.progress_state import ProgressState
from app.domain.scenario import Scenario, scenario_for_id
from app.domain.turn_state import turn_state_from_players
from app.domain.unit import Unit


def serialize_scenario(scenario: Scenario) -> dict[str, Any]:
    lt = scenario.lightning_tree_hex
    cities_sorted = sorted(scenario.cities(), key=lambda c: c.id)
    units_sorted = sorted(scenario.units(), key=lambda u: u.id)
    return {
        "next_unit_id": scenario.peek_next_unit_id(),
        "next_city_id": scenario.peek_next_city_id(),
        "lightning_tree_hex": None
        if lt is None
        else [lt.q, lt.r],
        "map": {"cells": scenario.map.to_json_cells()},
        "units": [_serialize_unit(u) for u in units_sorted],
        "cities": [_serialize_city(c) for c in cities_sorted],
    }


def _serialize_unit(u: Unit) -> dict[str, Any]:
    return {
        "id": u.id,
        "owner_id": u.owner_id,
        "position": [u.position.q, u.position.r],
        "type_id": u.type_id,
        "remaining_movement": u.remaining_movement,
        "current_hp": u.current_hp,
    }


def _serialize_city(c: City) -> dict[str, Any]:
    proj = None if c.current_project is None else copy.deepcopy(c.current_project)
    return {
        "id": c.id,
        "owner_id": c.owner_id,
        "position": [c.position.q, c.position.r],
        "current_project": proj,
        "city_name": c.city_name,
        "is_capital": c.is_capital,
        "building_ids": list(c.building_ids),
        "owned_tiles": [[h.q, h.r] for h in c.owned_tiles],
        "population": c.population,
        "manual_worked_tiles": [[h.q, h.r] for h in c.manual_worked_tiles],
        "food_stored": c.food_stored,
        "worked_tiles_mode": c.worked_tiles_mode,
    }


def serialize_progress_state(ps: ProgressState) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for owner_id in sorted(ps._by_owner.keys()):
        inner = ps._by_owner[owner_id]
        sp = inner.get("science_progress", {})
        if not isinstance(sp, dict):
            sp = {}
        sp_out = {k: int(sp[k]) for k in sorted(sp.keys(), key=str)}
        obs = inner.get("science_observation_flags", {})
        if not isinstance(obs, dict):
            obs = {}
        obs_out = {k: True for k in sorted(obs.keys(), key=str) if bool(obs[k])}
        rows.append(
            {
                "owner_id": owner_id,
                "unlocked_targets": copy.deepcopy(inner["unlocked_targets"]),
                "completed_progress_ids": list(inner["completed_progress_ids"]),
                "science_progress": sp_out,
                "science_observation_flags": obs_out,
                "current_research_id": str(inner.get("current_research_id", "")),
            }
        )
    return {"by_owner": rows}


def build_initial_snapshot(
    match_id: str,
    player_ids: list[int],
    scenario_id: str,
) -> dict[str, Any]:
    scenario = scenario_for_id(scenario_id)
    progress = ProgressState.with_default_unlocks_for_players(player_ids)
    return {
        "match_id": match_id,
        "schema_version": 2,
        "revision": 0,
        "ruleset": {
            "id": "stub_v0",
            "content_hash": "stub",
            "schema_version": 0,
        },
        "scenario_id": scenario_id,
        "scenario": serialize_scenario(scenario),
        "turn_state": turn_state_from_players(player_ids),
        "progress_state": serialize_progress_state(progress),
    }
