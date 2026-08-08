"""Deprecated Scenario/HexMap adapter for found_city (frozen legacy path).

N8R: this module contains NO founding algorithm. The founding decision
sequence, naming, and founding semantics live exclusively in the canonical
app.domain.city_founding_rules — this adapter only parses the legacy wire
envelope, extracts Scenario/HexMap facts (unit row, tile-on-map, water,
existing city, territory ownership), and materializes the canonical founding
effect into the rich snapshot-v2 City (territory, palace, population are
legacy state-model materialization, not gameplay decisions). Rejection
reasons are the canonical literal strings. Do not extend this path.
"""

from __future__ import annotations

from typing import Any

from app.domain import city_founding_rules
from app.domain.city import WORKED_TILES_MODE_AUTO, City
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import Terrain
from app.domain.scenario import Scenario

SCHEMA_VERSION = 1
ACTION_TYPE = "found_city"


def initial_owned_tiles_for_city(scenario: Scenario, center: HexCoord) -> tuple[HexCoord, ...]:
    """Legacy territory materialization (map-dependent, snapshot-v2 only):
    center then legal neighbors, skip already-owned."""
    seen: set[tuple[int, int]] = {(center.q, center.r)}
    out: list[HexCoord] = [HexCoord(center.q, center.r)]
    for nb in center.neighbors():
        if not scenario.map.has(nb):
            continue
        nk = (nb.q, nb.r)
        if nk in seen:
            continue
        if scenario.tile_is_owned(nb):
            continue
        seen.add(nk)
        out.append(HexCoord(nb.q, nb.r))
    return tuple(out)


def default_city_name_for_owner(scenario: Scenario, owner_id: int) -> str:
    """Scenario adapter over the ONE canonical naming rule."""
    return city_founding_rules.default_city_name(len(scenario.cities_owned_by(owner_id)))


def _founder_facts(scenario: Scenario, unit_id: int) -> city_founding_rules.FounderFacts | None:
    u = scenario.unit_by_id(unit_id)
    if u is None:
        return None
    return city_founding_rules.FounderFacts(
        owner_id=int(u.owner_id),
        type_id=str(u.type_id),
        position=(int(u.position.q), int(u.position.r)),
    )


def validate(scenario: Scenario | None, action: dict[str, Any] | None) -> dict[str, Any]:
    """Legacy envelope checks, then the canonical founding decision over
    Scenario/HexMap facts. current_player is checked in the API layer, so the
    adapter passes actor as current (the canonical chain owns the check on
    paths that gate in-domain)."""
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
    if "unit_id" not in action or not isinstance(action["unit_id"], int):
        return {"ok": False, "reason": "malformed_action"}
    pos_a = action.get("position")
    if not isinstance(pos_a, list) or len(pos_a) != 2:
        return {"ok": False, "reason": "malformed_action"}
    if not isinstance(pos_a[0], int) or not isinstance(pos_a[1], int):
        return {"ok": False, "reason": "malformed_action"}

    actor_id = int(action["actor_id"])
    pos_c = HexCoord(int(pos_a[0]), int(pos_a[1]))
    tile_on_map = scenario.map.has(pos_c)
    return city_founding_rules.validate_found_city(
        actor_id=actor_id,
        current_player_id=actor_id,
        founder=_founder_facts(scenario, int(action["unit_id"])),
        position=(pos_c.q, pos_c.r),
        tile_has_city=len(scenario.cities_at(pos_c)) > 0,
        tile_on_map=tile_on_map,
        tile_is_water=tile_on_map and scenario.map.terrain_at(pos_c) == Terrain.WATER,
        tile_is_owned=scenario.tile_is_owned(pos_c),
    )


def apply_found_city(scenario: Scenario, action: dict[str, Any]) -> Scenario:
    """Materialize the canonical founding effect into snapshot-v2 state:
    remove founder unit, append rich City, bump next_city_id. Only call after
    validate ok."""
    pos_a = action["position"]
    center = HexCoord(int(pos_a[0]), int(pos_a[1]))
    uid = int(action["unit_id"])
    actor_id = int(action["actor_id"])

    effect = city_founding_rules.found_city_effect(
        owner_id=actor_id,
        position=(center.q, center.r),
        owned_city_count=len(scenario.cities_owned_by(actor_id)),
    )

    new_units = tuple(u for u in scenario.units() if u.id != uid)
    new_city_id = scenario.peek_next_city_id()
    is_cap = bool(effect["is_capital"])

    new_city = City(
        id=new_city_id,
        owner_id=int(effect["owner_id"]),
        position=center,
        current_project=effect["current_project"],
        city_name=str(effect["name"]),
        is_capital=is_cap,
        building_ids=("palace",) if is_cap else (),
        owned_tiles=initial_owned_tiles_for_city(scenario, center),
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    new_cities = (*scenario.cities(), new_city)
    return Scenario(
        map=scenario.map,
        _units=new_units,
        _cities=new_cities,
        next_unit_id=scenario.next_unit_id,
        next_city_id=scenario.peek_next_city_id() + 1,
        lightning_tree_hex=scenario.lightning_tree_hex,
    )
