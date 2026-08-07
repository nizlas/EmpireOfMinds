"""N7 world actions: move_unit + end_turn + attack_unit on world_map matches
(snapshot v3).

Deliberately separate from the frozen legacy action modules (no Scenario, no
HexMap, no adapter). World movement v1 legality comes exclusively from the
authoritative WorldMap: destination tile must exist, must be adjacent via the
canonical neighbor deltas, the connecting edge must be smooth (cliff blocks;
a missing edge record between existing adjacent tiles rejects fail-closed),
and the destination must be unoccupied. There are NO movement points, moved
flags, or terrain-category passability on the world path (docs/PHASE_PLAN.md
N7, docs/MOVEMENT_RULES.md).

N7g.1 World Combat 0.1 (warrior-vs-warrior only, locked): attack_unit keeps
the exact legacy wire shape (schema_version 1, actor_id, attacker_id,
defender_id) and resolves through the SHARED pure Local Combat 0.1 core
(combat_rules.resolve_combat — one formula, never a drifting duplicate):
BASE_DAMAGE 30, exp((atk-def)/25) scaling, clamp 1..100, retaliation only if
the defender survives, elimination at 0 HP. Tile occupation after combat
(locked N7g.3 correction): a surviving defender leaves the attacker on its
original tile; eliminating the defender moves the surviving attacker onto
the defender's former tile (authoritative capture in the resulting snapshot);
an attacker killed by retaliation captures nothing and is removed. Melee
requires a traversable (smooth) edge — cliff or missing edge record blocks
fail-closed, the SAME edge-legality source as movement. A surviving
attacker's has_attacked becomes true: it can neither move nor attack again
until its owner's next turn (accepted world end_turn clears every unit's
has_attacked). Pre-attack movement stays budget-free.

Validation is two-phase so the API layer can resolve + identity-verify the
canonical WorldMap between them (world_match.resolve_world_map_for_snapshot):
  move_unit:   envelope/unit/from checks  ->  map resolve  ->  destination checks
  attack_unit: envelope/unit/state checks ->  map resolve  ->  adjacency/edge checks
  end_turn:    envelope/current-player    ->  map resolve  ->  apply

Locked first-failure reject order (docs/CLOUD_API_V0.md):
  move_unit: wrong_action_type -> unsupported_schema_version -> malformed_action
    -> not_current_player -> unknown_unit -> unit_not_owned_by_player
    -> from_does_not_match_unit_position -> unit_already_attacked
    -> destination_not_on_map -> destination_not_adjacent
    -> destination_edge_missing -> destination_cliff_blocked
    -> destination_occupied
  attack_unit: wrong_action_type -> unsupported_schema_version
    -> malformed_action -> not_current_player -> unknown_attacker
    -> unknown_defender -> actor_not_owner -> attacker_not_warrior
    -> defender_not_warrior -> cannot_attack_own_unit
    -> attacker_already_attacked -> defender_not_adjacent
    -> attack_edge_missing -> attack_cliff_blocked
  end_turn: wrong_action_type -> unsupported_schema_version -> malformed_action
    -> not_current_player
"""

from __future__ import annotations

from typing import Any

from app.domain.combat_rules import resolve_combat
from app.domain.content import unit_definitions
from app.domain.hex_coord import DIRECTIONS
from app.domain.turn_state import advance_turn_state
from app.domain.world_map import EDGE_CLIFF, WorldMap

SCHEMA_VERSION = 1
MOVE_UNIT_ACTION_TYPE = "move_unit"
END_TURN_ACTION_TYPE = "end_turn"
ATTACK_UNIT_ACTION_TYPE = "attack_unit"
WARRIOR_TYPE = "warrior"

# Known legacy action types with no world-path support (N8+ decides their
# world equivalents); everything else is unknown_action_type.
LEGACY_ONLY_ACTION_TYPES = ("found_city", "set_city_production")


def _is_exact_int(value: Any) -> bool:
    """Exact JSON integer: booleans are ints in Python and must not pass."""
    return isinstance(value, int) and not isinstance(value, bool)


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


def unit_by_id(snap: dict[str, Any], unit_id: int) -> dict[str, Any] | None:
    return _unit_by_id(snap, int(unit_id))


def unit_at(snap: dict[str, Any], pos: tuple[int, int]) -> dict[str, Any] | None:
    for u in snap.get("units", []):
        if int(u["position"][0]) == pos[0] and int(u["position"][1]) == pos[1]:
            return u
    return None


def _is_coord_pair(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(_is_exact_int(x) for x in value)
    )


def validate_move_unit_pre_map(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Envelope, current-player, unit, and from checks (no WorldMap needed)."""
    if action.get("action_type") != MOVE_UNIT_ACTION_TYPE:
        return _fail("wrong_action_type")
    schema = action.get("schema_version")
    if not _is_exact_int(schema) or schema != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if (
        "actor_id" not in action
        or "unit_id" not in action
        or "from" not in action
        or "to" not in action
    ):
        return _fail("malformed_action")
    if not _is_exact_int(action["actor_id"]) or not _is_exact_int(action["unit_id"]):
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
    # N7g.1: a unit that already attacked this turn can no longer move
    # (mirrors legacy "attack zeroes remaining_movement" without movement
    # points). Movement BEFORE attacking stays budget-free.
    if bool(unit.get("has_attacked", False)):
        return _fail("unit_already_attacked")
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


def validate_attack_unit_pre_map(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Envelope, current-player, unit, and combat-state checks (no WorldMap
    needed). Locked order through attacker_already_attacked; adjacency/edge
    checks run after the caller resolved + identity-verified the map."""
    if action.get("action_type") != ATTACK_UNIT_ACTION_TYPE:
        return _fail("wrong_action_type")
    schema = action.get("schema_version")
    if not _is_exact_int(schema) or schema != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if (
        "actor_id" not in action
        or "attacker_id" not in action
        or "defender_id" not in action
    ):
        return _fail("malformed_action")
    if not all(
        _is_exact_int(action[k]) for k in ("actor_id", "attacker_id", "defender_id")
    ):
        return _fail("malformed_action")

    if int(action["actor_id"]) != _current_player_id(snap):
        return _fail("not_current_player")

    attacker = _unit_by_id(snap, int(action["attacker_id"]))
    if attacker is None:
        return _fail("unknown_attacker")
    defender = _unit_by_id(snap, int(action["defender_id"]))
    if defender is None:
        return _fail("unknown_defender")
    if int(attacker["owner_id"]) != int(action["actor_id"]):
        return _fail("actor_not_owner")
    # Combat 0.1 is warrior-vs-warrior ONLY (locked): attacks on or by any
    # other type are outside N7g by decision, not an open question.
    if str(attacker["type_id"]) != WARRIOR_TYPE:
        return _fail("attacker_not_warrior")
    if str(defender["type_id"]) != WARRIOR_TYPE:
        return _fail("defender_not_warrior")
    if int(attacker["owner_id"]) == int(defender["owner_id"]):
        return _fail("cannot_attack_own_unit")
    if bool(attacker.get("has_attacked", False)):
        return _fail("attacker_already_attacked")
    return _ok()


def validate_attack_unit_target(
    world_map: WorldMap,
    snap: dict[str, Any],
    action: dict[str, Any],
) -> dict[str, Any]:
    """Adjacency + edge legality from the authoritative WorldMap only — the
    SAME single edge-legality source movement uses: melee requires a smooth
    connecting edge; a cliff or a missing record blocks fail-closed."""
    attacker = _unit_by_id(snap, int(action["attacker_id"]))
    defender = _unit_by_id(snap, int(action["defender_id"]))
    a_pos = (int(attacker["position"][0]), int(attacker["position"][1]))
    d_pos = (int(defender["position"][0]), int(defender["position"][1]))
    delta = (d_pos[0] - a_pos[0], d_pos[1] - a_pos[1])
    if delta not in DIRECTIONS:
        return _fail("defender_not_adjacent")
    if not world_map.has_edge_between(a_pos, d_pos):
        return _fail("attack_edge_missing")
    if world_map.edge_between(a_pos, d_pos).transition == EDGE_CLIFF:
        return _fail("attack_cliff_blocked")
    return _ok()


def resolve_attack_combat(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Deterministic combat result via the SHARED pure Local Combat 0.1 core
    (exact legacy parity); strengths come from the server unit registry.
    Only after both validation phases returned ok."""
    attacker = _unit_by_id(snap, int(action["attacker_id"]))
    defender = _unit_by_id(snap, int(action["defender_id"]))
    return {
        "attacker_id": int(attacker["id"]),
        "defender_id": int(defender["id"]),
        **resolve_combat(
            unit_definitions.combat_strength_for_type(str(attacker["type_id"])),
            unit_definitions.combat_strength_for_type(str(defender["type_id"])),
            int(attacker["current_hp"]),
            int(defender["current_hp"]),
        ),
    }


def apply_attack_unit(
    snap: dict[str, Any],
    action: dict[str, Any],
    combat_result: dict[str, Any],
) -> dict[str, Any]:
    """New snapshot after resolved combat, revision bumped exactly once.

    Units at 0 HP are eliminated. A surviving attacker gets has_attacked =
    true. Tile occupation (authoritative, in the snapshot position only —
    no presentation fields): surviving defender → attacker stays on its
    original tile; defender eliminated and attacker survives → attacker
    captures the defender's former tile; attacker killed by retaliation →
    no capture (attacker removed). A surviving defender only takes damage.
    Units stay sorted ascending by id."""
    attacker_id = int(action["attacker_id"])
    defender_id = int(action["defender_id"])
    attacker_killed = bool(combat_result["attacker_killed"])
    defender_killed = bool(combat_result["defender_killed"])
    defender = _unit_by_id(snap, defender_id)
    captured_position = (
        [int(defender["position"][0]), int(defender["position"][1])]
        if defender_killed and not attacker_killed
        else None
    )
    new_units: list[dict[str, Any]] = []
    for u in snap["units"]:
        uid = int(u["id"])
        if attacker_killed and uid == attacker_id:
            continue
        if defender_killed and uid == defender_id:
            continue
        if uid == attacker_id:
            row = {
                **u,
                "current_hp": int(combat_result["attacker_hp_after"]),
                "has_attacked": True,
            }
            if captured_position is not None:
                row["position"] = list(captured_position)
            new_units.append(row)
        elif uid == defender_id:
            new_units.append(
                {**u, "current_hp": int(combat_result["defender_hp_after"])}
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
    schema = action.get("schema_version")
    if not _is_exact_int(schema) or schema != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if "actor_id" not in action or not _is_exact_int(action["actor_id"]):
        return _fail("malformed_action")
    if int(action["actor_id"]) != _current_player_id(snap):
        return _fail("not_current_player")
    return _ok()


def apply_end_turn(snap: dict[str, Any]) -> dict[str, Any]:
    """Turn advance + N7g.1 has_attacked reset for ALL units - no economy
    ticks, no movement refresh (there are no movement points), no production
    or delivery on the world path. Rows without the flag (pre-N7g snapshots;
    alpha-store policy recreates those matches) pass through unchanged."""
    new_units = [
        {**u, "has_attacked": False} if "has_attacked" in u else dict(u)
        for u in snap["units"]
    ]
    return {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "turn_state": advance_turn_state(snap["turn_state"]),
        "units": new_units,
    }
