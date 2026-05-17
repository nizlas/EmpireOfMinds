"""Found city action. Parity: game/domain/actions/found_city.gd."""

from __future__ import annotations

from typing import Any

from app.domain.city import WORKED_TILES_MODE_AUTO, City
from app.domain.content import unit_definitions
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import Terrain
from app.domain.scenario import Scenario

SCHEMA_VERSION = 1
ACTION_TYPE = "found_city"


def initial_owned_tiles_for_city(scenario: Scenario, center: HexCoord) -> tuple[HexCoord, ...]:
    """Mirror FoundCity._initial_owned_tiles_for_city: center then legal neighbors, skip already-owned."""
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
    owned = scenario.cities_owned_by(owner_id)
    n = len(owned)
    if n == 0:
        return "Capital"
    return f"Settlement {n + 1}"


def validate(scenario: Scenario | None, action: dict[str, Any] | None) -> dict[str, Any]:
    """current_player checked in API layer. Reason strings align with Godot where noted; API maps some."""
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

    u = scenario.unit_by_id(int(action["unit_id"]))
    if u is None:
        return {"ok": False, "reason": "unknown_unit"}
    if u.owner_id != int(action["actor_id"]):
        return {"ok": False, "reason": "actor_not_owner"}
    if not unit_definitions.can_found_city(u.type_id):
        return {"ok": False, "reason": "unit_type_cannot_found"}

    pos_c = HexCoord(int(pos_a[0]), int(pos_a[1]))
    if u.position != pos_c:
        return {"ok": False, "reason": "unit_not_at_position"}
    if not scenario.map.has(pos_c):
        return {"ok": False, "reason": "tile_not_on_map"}
    if scenario.map.terrain_at(pos_c) == Terrain.WATER:
        return {"ok": False, "reason": "tile_is_water"}
    if len(scenario.cities_at(pos_c)) > 0:
        return {"ok": False, "reason": "tile_already_has_city"}
    if scenario.tile_is_owned(pos_c):
        return {"ok": False, "reason": "tile_already_owned"}

    return {"ok": True, "reason": ""}


def apply_found_city(scenario: Scenario, action: dict[str, Any]) -> Scenario:
    """Remove founder unit, append city, bump next_city_id. Only call after validate ok."""
    pos_a = action["position"]
    q, r = int(pos_a[0]), int(pos_a[1])
    center = HexCoord(q, r)
    uid = int(action["unit_id"])
    actor_id = int(action["actor_id"])

    new_units = tuple(u for u in scenario.units() if u.id != uid)
    new_city_id = scenario.peek_next_city_id()

    cname = default_city_name_for_owner(scenario, actor_id)
    owned_before = scenario.cities_owned_by(actor_id)
    is_cap = len(owned_before) == 0
    bld: tuple[str, ...] = ("palace",) if is_cap else ()
    initial_owned = initial_owned_tiles_for_city(scenario, center)

    new_city = City(
        id=new_city_id,
        owner_id=actor_id,
        position=center,
        current_project=None,
        city_name=cname,
        is_capital=is_cap,
        building_ids=bld,
        owned_tiles=initial_owned,
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
