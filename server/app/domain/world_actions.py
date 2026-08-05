"""N7 world actions: move_unit + end_turn on world_map matches (snapshot v3).

Deliberately separate from the frozen legacy action modules (no Scenario, no
HexMap, no adapter). World movement v1 legality comes exclusively from the
authoritative WorldMap: destination tile must exist, must be adjacent via the
canonical neighbor deltas, the connecting edge must be smooth (cliff blocks;
a missing edge record between existing adjacent tiles rejects fail-closed),
and the destination must be unoccupied. There are NO movement points, moved
flags, or terrain-category passability on the world path (docs/PHASE_PLAN.md
N7, docs/MOVEMENT_RULES.md).

Validation is two-phase so the API layer can resolve + identity-verify the
canonical WorldMap between them (world_match.resolve_world_map_for_snapshot):
  move_unit: envelope/unit/from checks  ->  map resolve  ->  destination checks
  end_turn:  envelope/current-player    ->  map resolve  ->  apply

Locked first-failure reject order (docs/CLOUD_API_V0.md):
  move_unit: wrong_action_type -> unsupported_schema_version -> malformed_action
    -> not_current_player -> unknown_unit -> unit_not_owned_by_player
    -> from_does_not_match_unit_position -> destination_not_on_map
    -> destination_not_adjacent -> destination_edge_missing
    -> destination_cliff_blocked -> destination_occupied
  end_turn: wrong_action_type -> unsupported_schema_version -> malformed_action
    -> not_current_player
"""

from __future__ import annotations

from typing import Any

from app.domain.hex_coord import DIRECTIONS
from app.domain.turn_state import advance_turn_state
from app.domain.world_map import EDGE_CLIFF, WorldMap

SCHEMA_VERSION = 1
MOVE_UNIT_ACTION_TYPE = "move_unit"
END_TURN_ACTION_TYPE = "end_turn"

# Known legacy action types with no world-path support (N8+ decides their
# world equivalents); everything else is unknown_action_type.
LEGACY_ONLY_ACTION_TYPES = ("found_city", "set_city_production", "attack_unit")


def _ok() -> dict[str, Any]:
    return {"ok": True, "reason": ""}


def _fail(reason: str) -> dict[str, Any]:
    return {"ok": False, "reason": reason}


def _current_player_id(snap: dict[str, Any]) -> int:
    ts = snap["turn_state"]
    return int(ts["players"][int(ts["current_index"])])


def _unit_by_id(snap: dict[str, Any], unit_id: int) -> dict[str, Any] | None:
    for u in snap.get("units", []):
        if int(u["id"]) == unit_id:
            return u
    return None


def unit_at(snap: dict[str, Any], pos: tuple[int, int]) -> dict[str, Any] | None:
    for u in snap.get("units", []):
        if int(u["position"][0]) == pos[0] and int(u["position"][1]) == pos[1]:
            return u
    return None


def _is_coord_pair(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(x, int) and not isinstance(x, bool) for x in value)
    )


def validate_move_unit_pre_map(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Envelope, current-player, unit, and from checks (no WorldMap needed)."""
    if action.get("action_type") != MOVE_UNIT_ACTION_TYPE:
        return _fail("wrong_action_type")
    if action.get("schema_version") != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if (
        "actor_id" not in action
        or "unit_id" not in action
        or "from" not in action
        or "to" not in action
    ):
        return _fail("malformed_action")
    if not isinstance(action["actor_id"], int) or not isinstance(action["unit_id"], int):
        return _fail("malformed_action")
    if not _is_coord_pair(action["from"]) or not _is_coord_pair(action["to"]):
        return _fail("malformed_action")

    if int(action["actor_id"]) != _current_player_id(snap):
        return _fail("not_current_player")

    unit = _unit_by_id(snap, int(action["unit_id"]))
    if unit is None:
        return _fail("unknown_unit")
    if int(unit["owner_id"]) != int(action["actor_id"]):
        return _fail("unit_not_owned_by_player")
    if [int(unit["position"][0]), int(unit["position"][1])] != [
        int(action["from"][0]),
        int(action["from"][1]),
    ]:
        return _fail("from_does_not_match_unit_position")
    return _ok()


def validate_move_unit_destination(
    world_map: WorldMap,
    snap: dict[str, Any],
    action: dict[str, Any],
) -> dict[str, Any]:
    """Destination legality from the authoritative WorldMap only."""
    from_c = (int(action["from"][0]), int(action["from"][1]))
    to_c = (int(action["to"][0]), int(action["to"][1]))

    if not world_map.has_tile_coord(to_c):
        return _fail("destination_not_on_map")
    delta = (to_c[0] - from_c[0], to_c[1] - from_c[1])
    if delta not in DIRECTIONS:
        return _fail("destination_not_adjacent")
    # Both tiles exist and are adjacent => the derived edge record must exist.
    # A missing record is a content/derivation invariant violation: fail
    # closed as a rejection, never treat it as passable.
    if not world_map.has_edge_between(from_c, to_c):
        return _fail("destination_edge_missing")
    if world_map.edge_between(from_c, to_c).transition == EDGE_CLIFF:
        return _fail("destination_cliff_blocked")
    if unit_at(snap, to_c) is not None:
        return _fail("destination_occupied")
    return _ok()


def apply_move_unit(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """New snapshot with the unit moved and revision bumped. Only after both
    validation phases returned ok. Units stay sorted ascending by id."""
    uid = int(action["unit_id"])
    new_units: list[dict[str, Any]] = []
    for u in snap["units"]:
        if int(u["id"]) == uid:
            new_units.append(
                {
                    **u,
                    "position": [int(action["to"][0]), int(action["to"][1])],
                }
            )
        else:
            new_units.append(dict(u))
    new_units.sort(key=lambda u: int(u["id"]))
    return {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "units": new_units,
    }


def validate_end_turn(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    if action.get("action_type") != END_TURN_ACTION_TYPE:
        return _fail("wrong_action_type")
    if action.get("schema_version") != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if "actor_id" not in action or not isinstance(action["actor_id"], int):
        return _fail("malformed_action")
    if int(action["actor_id"]) != _current_player_id(snap):
        return _fail("not_current_player")
    return _ok()


def apply_end_turn(snap: dict[str, Any]) -> dict[str, Any]:
    """Turn advance only - no economy ticks and no movement refresh on the
    world path (there are no movement points to refresh)."""
    return {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "turn_state": advance_turn_state(snap["turn_state"]),
    }
