"""N7/N8a/N8b/N8c world actions on world_map matches (snapshot v3).

Deliberately separate from the frozen legacy action modules (no Scenario, no
HexMap, no adapter). World movement v1 legality comes exclusively from the
authoritative WorldMap: destination tile must exist, must be adjacent via the
canonical neighbor deltas, the connecting edge must be smooth (cliff blocks;
a missing edge record between existing adjacent tiles rejects fail-closed),
and the destination must be unoccupied. There are NO movement points, moved
flags, or terrain-category passability on the world path (docs/PHASE_PLAN.md
N7, docs/MOVEMENT_RULES.md). Cities never block unit movement (N8a locked).

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

N8a found_city and N8b set_city_production are thin snapshot-v3 adapters
over the CANONICAL gameplay rules (N8R single-gameplay-core recovery):
the founding decision chain, default Capital / Settlement N naming, and
the COMPLETE founding transition (founder consumption, city-id allocation,
next-city-id advancement) live in city_founding_rules; the production-selection
decision chain, the canonical {project_id, progress, cost} project state,
and the event progress representation live in city_production_rules. This
module owns only the wire/envelope checks (schema, malformed shapes) and
the snapshot-v3 state adaptation (row lookups, list materialization,
sorting, revision bump) — never a second copy of a gameplay rule.

found_city (legacy wire shape: schema_version 1, actor_id, unit_id,
position): consumes an eligible settler and appends a minimal city row
({id, owner_id, position, name, current_project}) allocated from snapshot
next_city_id. Newly founded cities start with current_project null. After
the standard action/unit checks, an existing city on the founding tile is
the ONLY city-placement restriction (no water/territory/elevation/minimum-
distance reasons on schema v1). No population, science, or territory.

set_city_production (legacy wire parity: schema_version 2, actor_id,
city_id, project_id ∈ produce_unit:warrior | produce_unit:settler | none):
sets or clears city current_project. Costs come from CityProjectDefinitions
(Warrior 2, Settler 2). Both unit projects are always selectable — no
progress_state / unlock gating on the WorldMap path. Progress resets to 0
on set/switch; none clears. Selecting the already-active project or
clearing an already-empty project rejects project_already_set with no
mutation. Flat production yield (1 per city on owner end_turn) lives in
city_production_rules. N8c feeds that SAME tick/delivery loop from world
end_turn (flat yields + WorldMap spawn placement / defer) — never a copy.

Validation is two-phase so the API layer can resolve + identity-verify the
canonical WorldMap between them (world_match.resolve_world_map_for_snapshot):
  move_unit:            envelope/unit/from checks  ->  map resolve  ->  destination
  attack_unit:          envelope/unit/state checks ->  map resolve  ->  adjacency
  found_city:           envelope/unit/tile checks  ->  map resolve  ->  apply
  set_city_production:  envelope/city/project      ->  map resolve  ->  apply
  end_turn:             envelope/current-player    ->  map resolve  ->  apply

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
  found_city: wrong_action_type -> unsupported_schema_version
    -> malformed_action -> not_current_player -> unknown_unit
    -> unit_not_owned_by_player -> unit_cannot_found_city
    -> unit_not_at_position -> tile_already_has_city
  set_city_production: wrong_action_type -> unsupported_schema_version
    -> malformed_action -> not_current_player -> unknown_city
    -> city_not_owned_by_player -> unknown_city_project
    -> project_already_set
  end_turn: wrong_action_type -> unsupported_schema_version -> malformed_action
    -> not_current_player
"""

from __future__ import annotations

from typing import Any

from app.domain import city_founding_rules, city_production_rules
from app.domain.combat_rules import resolve_combat
from app.domain.content import unit_definitions
from app.domain.hex_coord import DIRECTIONS
from app.domain.turn_state import advance_turn_state
from app.domain.world_map import EDGE_CLIFF, EDGE_SMOOTH, WorldMap

SCHEMA_VERSION = 1
SET_CITY_PRODUCTION_SCHEMA_VERSION = 2
MOVE_UNIT_ACTION_TYPE = "move_unit"
END_TURN_ACTION_TYPE = "end_turn"
ATTACK_UNIT_ACTION_TYPE = "attack_unit"
FOUND_CITY_ACTION_TYPE = "found_city"
SET_CITY_PRODUCTION_ACTION_TYPE = "set_city_production"
WARRIOR_TYPE = "warrior"

# Empty after N8b: every previously deferred legacy action type that the world
# path now supports is dispatched explicitly. Unknown types still reject as
# unknown_action_type.
LEGACY_ONLY_ACTION_TYPES: tuple[str, ...] = ()


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


def city_at(snap: dict[str, Any], pos: tuple[int, int]) -> dict[str, Any] | None:
    for c in snap.get("cities", []):
        if int(c["position"][0]) == pos[0] and int(c["position"][1]) == pos[1]:
            return c
    return None


def city_by_id(snap: dict[str, Any], city_id: int) -> dict[str, Any] | None:
    for c in snap.get("cities", []):
        if int(c["id"]) == city_id:
            return c
    return None


def _owned_city_count(snap: dict[str, Any], owner_id: int) -> int:
    return sum(1 for c in snap.get("cities", []) if int(c["owner_id"]) == owner_id)


def _founder_facts(
    snap: dict[str, Any], unit_id: int
) -> city_founding_rules.FounderFacts | None:
    """Snapshot-v3 adapter: minimal founder facts for the canonical rules."""
    unit = _unit_by_id(snap, unit_id)
    if unit is None:
        return None
    return city_founding_rules.FounderFacts(
        owner_id=int(unit["owner_id"]),
        type_id=str(unit["type_id"]),
        position=(int(unit["position"][0]), int(unit["position"][1])),
    )


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
    # Combat 0.1 is melee-combatant only (locked): production warrior plus
    # debug generated_warrior (same role/stats). Settlers and other types stay
    # outside N7g — rejection reasons keep the historical warrior wording.
    if not unit_definitions.is_melee_combatant(str(attacker["type_id"])):
        return _fail("attacker_not_warrior")
    if not unit_definitions.is_melee_combatant(str(defender["type_id"])):
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


def validate_found_city(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """N8a found_city wire/envelope checks, then the CANONICAL founding
    decision chain (city_founding_rules) over snapshot-v3 facts.

    Locked first-failure order through tile_already_has_city (owned by the
    canonical rules). No WorldMap reads: an existing city on the tile is the
    only city-placement restriction after the unit checks.
    """
    if action.get("action_type") != FOUND_CITY_ACTION_TYPE:
        return _fail("wrong_action_type")
    schema = action.get("schema_version")
    if not _is_exact_int(schema) or schema != SCHEMA_VERSION:
        return _fail("unsupported_schema_version")
    if (
        "actor_id" not in action
        or "unit_id" not in action
        or "position" not in action
    ):
        return _fail("malformed_action")
    if not _is_exact_int(action["actor_id"]) or not _is_exact_int(action["unit_id"]):
        return _fail("malformed_action")
    if not _is_coord_pair(action["position"]):
        return _fail("malformed_action")

    pos = (int(action["position"][0]), int(action["position"][1]))
    # A missing, dead, or already-consumed unit yields founder=None →
    # unknown_unit from the canonical chain (duplicate/stale founding posts
    # after a successful consume land there; no partial mutation).
    return city_founding_rules.validate_found_city(
        actor_id=int(action["actor_id"]),
        current_player_id=_current_player_id(snap),
        founder=_founder_facts(snap, int(action["unit_id"])),
        position=pos,
        tile_has_city=city_at(snap, pos) is not None,
    )


def apply_found_city(snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    """Atomic founding: materialize the ONE canonical founding transition
    into snapshot v3. Only after validate_found_city returned ok. The
    transition decides founder consumption, city-id allocation, and
    next-city-id advancement — this adapter only reshapes it into v3 rows
    (cities sorted ascending by id; remaining units keep all combat fields
    unchanged) and bumps revision."""
    actor_id = int(action["actor_id"])
    t = city_founding_rules.found_city_transition(
        owner_id=actor_id,
        founder_unit_id=int(action["unit_id"]),
        position=(int(action["position"][0]), int(action["position"][1])),
        owned_city_count=_owned_city_count(snap, actor_id),
        next_city_id=int(snap["next_city_id"]),
    )
    new_city = {
        "id": t.city_id,
        "owner_id": t.owner_id,
        "position": [t.position[0], t.position[1]],
        "name": t.name,
        "current_project": t.current_project,
    }
    new_cities = [dict(c) for c in snap.get("cities", [])]
    new_cities.append(new_city)
    new_cities.sort(key=lambda c: int(c["id"]))
    new_units = [
        dict(u) for u in snap["units"] if int(u["id"]) != t.consumed_unit_id
    ]
    new_units.sort(key=lambda u: int(u["id"]))
    return {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "units": new_units,
        "cities": new_cities,
        "next_city_id": t.next_city_id,
    }


def _city_production_facts(
    snap: dict[str, Any], city_id: int
) -> city_production_rules.CityProductionFacts | None:
    """Snapshot-v3 adapter: minimal city facts for the canonical rules."""
    city = city_by_id(snap, city_id)
    if city is None:
        return None
    return city_production_rules.CityProductionFacts(
        owner_id=int(city["owner_id"]),
        active_project_id=city_production_rules.active_project_id(
            city.get("current_project", None)
        ),
    )


def validate_set_city_production(
    snap: dict[str, Any], action: dict[str, Any]
) -> dict[str, Any]:
    """N8b set_city_production wire/envelope checks, then the CANONICAL
    selection decision chain (city_production_rules) over snapshot-v3 facts.

    Locked first-failure order through project_already_set (owned by the
    canonical rules). No WorldMap reads, no unlock / progress_state gating —
    both produce_unit projects are always selectable.
    """
    if action.get("action_type") != SET_CITY_PRODUCTION_ACTION_TYPE:
        return _fail("wrong_action_type")
    schema = action.get("schema_version")
    if (
        not _is_exact_int(schema)
        or schema != SET_CITY_PRODUCTION_SCHEMA_VERSION
    ):
        return _fail("unsupported_schema_version")
    if (
        "actor_id" not in action
        or "city_id" not in action
        or "project_id" not in action
    ):
        return _fail("malformed_action")
    if not _is_exact_int(action["actor_id"]) or not _is_exact_int(action["city_id"]):
        return _fail("malformed_action")
    if not isinstance(action["project_id"], str):
        return _fail("malformed_action")

    return city_production_rules.validate_set_city_production(
        actor_id=int(action["actor_id"]),
        current_player_id=_current_player_id(snap),
        city=_city_production_facts(snap, int(action["city_id"])),
        project_id=str(action["project_id"]),
    )


def apply_set_city_production(
    snap: dict[str, Any], action: dict[str, Any]
) -> dict[str, Any]:
    """Atomic production selection: materialize the canonical project state
    into snapshot v3 (set/switch/clear current_project), bump revision. Only
    after validate_set_city_production returned ok. New and switched projects
    start at progress 0 with registry cost; none clears.
    """
    city_id = int(action["city_id"])
    new_project = city_production_rules.new_project_state(str(action["project_id"]))

    new_cities: list[dict[str, Any]] = []
    for c in snap.get("cities", []):
        row = dict(c)
        if int(row["id"]) == city_id:
            row["current_project"] = new_project
        new_cities.append(row)
    new_cities.sort(key=lambda c: int(c["id"]))
    return {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "cities": new_cities,
    }


def project_progress_for_event(city: dict[str, Any]) -> int | None:
    """Event project_progress via the canonical representation rule."""
    return city_production_rules.project_progress_for_event(
        city.get("current_project", None)
    )


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


def _producing_city_facts(
    cities: list[dict[str, Any]],
) -> list[city_production_rules.ProducingCityFacts]:
    facts: list[city_production_rules.ProducingCityFacts] = []
    for row in cities:
        proj = row.get("current_project", None)
        facts.append(
            city_production_rules.ProducingCityFacts(
                city_id=int(row["id"]),
                owner_id=int(row["owner_id"]),
                position=(int(row["position"][0]), int(row["position"][1])),
                current_project=proj if isinstance(proj, dict) else None,
            )
        )
    return facts


def resolve_production_spawn_tile(
    world_map: WorldMap,
    city_pos: tuple[int, int],
    occupied: set[tuple[int, int]],
) -> tuple[int, int] | None:
    """N8c WorldMap placement fact: city tile if unit-unoccupied, else first
    unit-unoccupied smooth-adjacent tile in canonical DIRECTIONS order.
    Missing edge records and cliffs fail closed (skip that candidate)."""
    if world_map.has_tile_coord(city_pos) and city_pos not in occupied:
        return city_pos
    cq, cr = int(city_pos[0]), int(city_pos[1])
    for dq, dr in DIRECTIONS:
        cand = (cq + dq, cr + dr)
        if cand in occupied:
            continue
        if not world_map.has_tile_coord(cand):
            continue
        if not world_map.has_edge_between(city_pos, cand):
            continue
        if world_map.edge_between(city_pos, cand).transition != EDGE_SMOOTH:
            continue
        return cand
    return None


def apply_end_turn(
    snap: dict[str, Any], world_map: WorldMap
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    """N8c locked end_turn apply (legacy-equivalent timing):

    (1) production tick for the ending player's eligible cities via the
        canonical loop + FLAT_PRODUCTION_PER_CITY;
    (2) turn advance + N7g.1 has_attacked reset for ALL units;
    (3) delivery for the player who has just become current, with WorldMap
        spawn placement / defer through the SAME canonical delivery loop.

    Returns (new_snap, unstamped production_progress events, unstamped
    unit_produced events). The API stamps events and keeps the POST primary
    event/index on the accepted end_turn row. No movement refresh (there
    are no movement points on the world path).
    """
    ending_player = _current_player_id(snap)
    city_rows = [dict(c) for c in snap.get("cities", [])]
    city_facts = _producing_city_facts(city_rows)
    yields = {
        c.city_id: city_production_rules.FLAT_PRODUCTION_PER_CITY
        for c in city_facts
        if c.owner_id == ending_player
    }
    new_project_by_id, tick_events = city_production_rules.tick_production(
        city_facts, ending_player, yields
    )
    if new_project_by_id:
        updated: list[dict[str, Any]] = []
        for row in city_rows:
            cid = int(row["id"])
            if cid in new_project_by_id:
                updated.append({**row, "current_project": new_project_by_id[cid]})
            else:
                updated.append(row)
        city_rows = updated

    new_units: list[dict[str, Any]] = [
        {**u, "has_attacked": False} if "has_attacked" in u else dict(u)
        for u in snap["units"]
    ]
    new_turn = advance_turn_state(snap["turn_state"])
    next_player = int(new_turn["players"][int(new_turn["current_index"])])

    after_tick_facts = _producing_city_facts(city_rows)
    occupied: set[tuple[int, int]] = {
        (int(u["position"][0]), int(u["position"][1])) for u in new_units
    }

    def _resolve(
        city: city_production_rules.ProducingCityFacts,
        occ: set[tuple[int, int]],
    ) -> tuple[int, int] | None:
        return resolve_production_spawn_tile(world_map, city.position, occ)

    # Alpha-store recreates matches on shape extension; defensive max+1 only
    # covers hand-seeded fixtures that omit next_unit_id.
    if "next_unit_id" in snap and _is_exact_int(snap["next_unit_id"]):
        next_unit_id = int(snap["next_unit_id"])
    elif new_units:
        next_unit_id = max(int(u["id"]) for u in new_units) + 1
    else:
        next_unit_id = 1

    spawns, delivery_events, new_next_unit_id = (
        city_production_rules.deliver_completed_production(
            after_tick_facts,
            next_player,
            next_unit_id,
            occupied_positions=occupied,
            resolve_spawn_position=_resolve,
        )
    )
    delivered_city_ids = {int(s["city_id"]) for s in spawns}
    if delivered_city_ids:
        city_rows = [
            {**row, "current_project": None}
            if int(row["id"]) in delivered_city_ids
            else row
            for row in city_rows
        ]
    for s in spawns:
        unit_type = str(s["unit_type_id"])
        pos = s["position"]
        new_units.append(
            {
                "id": int(s["unit_id"]),
                "owner_id": int(s["owner_id"]),
                "position": [int(pos[0]), int(pos[1])],
                "type_id": unit_type,
                "current_hp": unit_definitions.max_hp_for_type(unit_type),
                "has_attacked": False,
            }
        )
    new_units.sort(key=lambda u: int(u["id"]))
    city_rows.sort(key=lambda c: int(c["id"]))

    new_snap = {
        **snap,
        "revision": int(snap["revision"]) + 1,
        "turn_state": new_turn,
        "units": new_units,
        "cities": city_rows,
        "next_unit_id": int(new_next_unit_id),
    }
    return new_snap, tick_events, delivery_events
