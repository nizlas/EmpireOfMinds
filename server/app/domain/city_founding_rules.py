"""Canonical city-founding rules (N8R) — the ONE gameplay implementation.

Map-neutral pure module: the founding decision sequence, default city naming,
and the founding semantic transition are independent of presentation,
transport, snapshot format, and map rendering. This module never imports
Scenario, HexMap, WorldMap, snapshot, storage, or API code — callers pass
plain facts (actor/current player ids, founder unit facts, tile facts) and
materialize the returned effect into their own state representation. The only
allowed dependency is the shared canonical unit registry (which unit types
may found cities).

There is exactly ONE founding validator. State-specific callers are fact
adapters, never separate algorithms:

- the active WorldMap path (world_actions.py) answers only ``tile_has_city``
  — snapshot v3 has neither water nor territory layers, so the tile-fact
  defaults (on map, not water, not owned) apply and those reasons never fire;
  founding legality never reads elevation;
- the deprecated Scenario/HexMap adapter (actions/found_city.py) additionally
  answers the map-dependent tile facts its richer map model has
  (``tile_on_map``, ``tile_is_water``, ``tile_is_owned``).

Locked decision chain and literal rejection reasons (after the caller's
wire/envelope checks): not_current_player -> unknown_unit ->
unit_not_owned_by_player -> unit_cannot_found_city -> unit_not_at_position
-> tile_not_on_map -> tile_is_water -> tile_already_has_city ->
tile_already_owned. On the WorldMap path the chain is observably the locked
N8a order (… -> unit_not_at_position -> tile_already_has_city) because the
absent map layers cannot fail. Wire-string differences are resolved: the
rule owns the canonical strings; adapters add none.

Canonical naming rule: a player's first city is "Capital", every later city
"Settlement N" (N = owned count + 1). Extracted from the proven legacy
implementation — never copy this rule into a state-specific module again.

Founding effect (semantics owned here, storage owned by the caller): the
founder unit is consumed, and one new city appears at the founder's tile
owned by the actor, named by the canonical rule, capital iff it is the
owner's first city, with no production project selected. Revision,
persistence, event stamping, and id allocation stay in the caller's
authority/orchestration layer; adapters materialize only the fields their
snapshot schema stores (snapshot v3 stores no capital flag).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.domain.content import unit_definitions


@dataclass(frozen=True)
class FounderFacts:
    """Minimal facts about the founding unit, independent of state shape."""

    owner_id: int
    type_id: str
    position: tuple[int, int]


def default_city_name(owned_city_count: int) -> str:
    """Canonical naming: first city Capital, then Settlement 2, ... per owner."""
    if owned_city_count == 0:
        return "Capital"
    return f"Settlement {owned_city_count + 1}"


def _ok() -> dict[str, Any]:
    return {"ok": True, "reason": ""}


def _fail(reason: str) -> dict[str, Any]:
    return {"ok": False, "reason": reason}


def validate_found_city(
    *,
    actor_id: int,
    current_player_id: int,
    founder: FounderFacts | None,
    position: tuple[int, int],
    tile_has_city: bool,
    tile_on_map: bool = True,
    tile_is_water: bool = False,
    tile_is_owned: bool = False,
) -> dict[str, Any]:
    """The canonical founding decision in the locked first-failure order.

    ``founder`` is None when the unit id does not resolve (missing, dead, or
    already consumed — duplicate/stale founding posts land here with no
    partial mutation on the prior accept). The tile facts are the map/state
    adapter's answers for ``position``; the defaults describe a map model
    without water or territory layers (the WorldMap schema v1 path), so an
    existing city on the tile is then the only placement restriction after
    the unit checks.
    """
    if actor_id != current_player_id:
        return _fail("not_current_player")
    if founder is None:
        return _fail("unknown_unit")
    if founder.owner_id != actor_id:
        return _fail("unit_not_owned_by_player")
    if not unit_definitions.can_found_city(founder.type_id):
        return _fail("unit_cannot_found_city")
    if founder.position != position:
        return _fail("unit_not_at_position")
    if not tile_on_map:
        return _fail("tile_not_on_map")
    if tile_is_water:
        return _fail("tile_is_water")
    if tile_has_city:
        return _fail("tile_already_has_city")
    if tile_is_owned:
        return _fail("tile_already_owned")
    return _ok()


def found_city_effect(
    *,
    owner_id: int,
    position: tuple[int, int],
    owned_city_count: int,
) -> dict[str, Any]:
    """Semantic founding transition: what the new city IS, not how it is stored.

    Only call after validate_found_city returned ok. The caller allocates the
    id, consumes the founder unit, keeps its collections sorted, and bumps
    revision — those are state/authority concerns, not gameplay rules.
    ``is_capital`` is the canonical first-city semantic; adapters whose
    snapshot schema has no capital concept (snapshot v3) simply do not store
    it, while the Scenario adapter derives its capital flag and palace from
    it instead of re-deciding.
    """
    return {
        "owner_id": owner_id,
        "position": (int(position[0]), int(position[1])),
        "name": default_city_name(owned_city_count),
        "is_capital": owned_city_count == 0,
        "current_project": None,
    }
