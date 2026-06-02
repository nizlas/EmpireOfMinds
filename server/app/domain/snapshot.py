"""Match snapshot v2 builders."""

from __future__ import annotations

import copy
from typing import Any

from app.domain.city import WORKED_TILES_MODE_AUTO, City
from app.domain.progress_state import ProgressState
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap
from app.domain import player_visibility
from app.domain.scenario import Scenario, scenario_for_id
from app.domain.turn_state import turn_state_from_players
from app.domain.unit import Unit


def scenario_from_snapshot_dict(d: dict[str, Any]) -> Scenario:
    """Rebuild Scenario from snapshot v2 `scenario` object (round-trip with serialize_scenario)."""
    m = HexMap.from_json_cells(list(d["map"]["cells"]))
    units = tuple(
        Unit.make(
            int(u["id"]),
            int(u["owner_id"]),
            HexCoord(int(u["position"][0]), int(u["position"][1])),
            str(u["type_id"]),
            int(u["remaining_movement"]),
            int(u["current_hp"]),
        )
        for u in sorted(d["units"], key=lambda x: int(x["id"]))
    )
    cities = tuple(
        _city_from_snapshot_row(c) for c in sorted(d["cities"], key=lambda x: int(x["id"]))
    )
    lt_raw = d.get("lightning_tree_hex")
    lt: HexCoord | None
    if lt_raw is None:
        lt = None
    else:
        lt = HexCoord(int(lt_raw[0]), int(lt_raw[1]))
    return Scenario(
        map=m,
        _units=units,
        _cities=cities,
        next_unit_id=int(d["next_unit_id"]),
        next_city_id=int(d["next_city_id"]),
        lightning_tree_hex=lt,
    )


def _city_from_snapshot_row(c: dict[str, Any]) -> City:
    owned = tuple(
        HexCoord(int(t[0]), int(t[1])) for t in c.get("owned_tiles", []) if len(t) >= 2
    )
    manual = tuple(
        HexCoord(int(t[0]), int(t[1])) for t in c.get("manual_worked_tiles", []) if len(t) >= 2
    )
    proj = c.get("current_project")
    proj_copy = None if proj is None else copy.deepcopy(proj)
    return City(
        id=int(c["id"]),
        owner_id=int(c["owner_id"]),
        position=HexCoord(int(c["position"][0]), int(c["position"][1])),
        current_project=proj_copy,
        city_name=str(c.get("city_name", "")),
        is_capital=bool(c.get("is_capital", False)),
        building_ids=tuple(str(x) for x in c.get("building_ids", [])),
        owned_tiles=owned,
        population=int(c.get("population", 1)),
        manual_worked_tiles=manual,
        food_stored=int(c.get("food_stored", 0)),
        worked_tiles_mode=str(c.get("worked_tiles_mode", WORKED_TILES_MODE_AUTO)),
    )


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
    vis = player_visibility.empty_for_players(player_ids)
    vis = player_visibility.seed_all_players(vis, scenario, player_ids)
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
        "visibility_state": player_visibility.serialize_visibility(vis),
    }
