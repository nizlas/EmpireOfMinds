"""Deprecated Scenario/HexMap adapter for found_city (frozen legacy path).

N8R: this module contains NO founding algorithm. The founding decision
sequence, naming, and the complete map-independent founding transition
(founder consumption, city-id allocation, next-city-id advancement, owner/
position/name/capital/empty project) live exclusively in the canonical
app.domain.city_founding_rules — this adapter only parses the legacy wire
envelope, extracts Scenario/HexMap facts (unit row, tile-on-map, water,
existing city, territory ownership), and materializes the canonical
transition into the rich snapshot-v2 City. The legacy-only extras are
representation (palace/population storage fields derived from the
transition) plus ONE frozen legacy gameplay policy: the HexMap initial-
territory rule (initial_owned_tiles_for_city), which is deprecated-path
territory behavior, never shared WorldMap gameplay. Rejection reasons are
the canonical literal strings. Do not extend this path.
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
    """FROZEN legacy HexMap territory policy (deprecated path only): center
    then legal neighbors, skip already-owned. This is legacy-only gameplay
    behavior coupled to the HexMap territory layer — NOT shared WorldMap
    gameplay and NOT generic storage materialization; the WorldMap schema has
    no territory, so this policy never moves into the canonical core or the
    world path."""
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
    """Materialize the ONE canonical founding transition into snapshot-v2
    state. Only call after validate ok. The transition decides founder
    consumption, city-id allocation, and next-city-id advancement — this
    adapter only reshapes it into the rich legacy ``City`` (palace derives
    from the transition's capital semantic; initial territory comes from the
    frozen legacy HexMap territory policy above) and rebuilds the Scenario."""
    actor_id = int(action["actor_id"])
    t = city_founding_rules.found_city_transition(
        owner_id=actor_id,
        founder_unit_id=int(action["unit_id"]),
        position=(int(action["position"][0]), int(action["position"][1])),
        owned_city_count=len(scenario.cities_owned_by(actor_id)),
        next_city_id=scenario.peek_next_city_id(),
    )
    center = HexCoord(t.position[0], t.position[1])

    new_units = tuple(u for u in scenario.units() if u.id != t.consumed_unit_id)
    new_city = City(
        id=t.city_id,
        owner_id=t.owner_id,
        position=center,
        current_project=t.current_project,
        city_name=t.name,
        is_capital=t.is_capital,
        building_ids=("palace",) if t.is_capital else (),
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
        next_city_id=t.next_city_id,
        lightning_tree_hex=scenario.lightning_tree_hex,
    )
