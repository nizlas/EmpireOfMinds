"""N7b/N7g.2: read-only legal-actions enumeration for world_map matches.

Separate from the frozen legacy legal_actions.py (no Scenario, no HexMap, no
movement_rules import) but wire-compatible: the response envelope, selection
precedence, and selection errors mirror the legacy endpoint exactly so
clients consume one schema.

Move AND attack rows are DERIVED, never re-implemented: candidates are
constructed in canonical DIRECTIONS order and filtered through the SAME
world validators the POST path uses (N7a
world_actions.validate_move_unit_pre_map + validate_move_unit_destination;
N7g.1 validate_attack_unit_pre_map + validate_attack_unit_target) against
the resolved authoritative WorldMap. Every returned action is therefore
submit-ready by construction — cliffs, occupied tiles, missing edges,
non-adjacent and off-map destinations are excluded from moves, and
friendly/settler/non-adjacent/cliff/missing-edge/already-attacked targets
are excluded from attacks, by the same code that judges POSTed actions.

Selected-unit ordering is deterministic (N7g.2): ALL legal attack_unit rows
first (canonical DIRECTIONS order of the defender tile), then all legal
move_unit rows (canonical DIRECTIONS order of the destination tile). Unit
summaries count attacks + moves; settlers stay move-only and a unit with
has_attacked true advertises neither (both enforced by the validators, not
re-implemented here).

Strictly read-only: no snapshot, revision, hash, or event changes.
"""

from __future__ import annotations

from typing import Any

from app.domain import world_actions
from app.domain.hex_coord import DIRECTIONS
from app.domain.world_map import WorldMap

LEGAL_ACTIONS_SCHEMA_VERSION = 1


def _current_player_id(snap: dict[str, Any]) -> int:
    ts = snap["turn_state"]
    return int(ts["players"][int(ts["current_index"])])


def _unit_by_id(snap: dict[str, Any], unit_id: int) -> dict[str, Any] | None:
    for u in snap.get("units", []):
        if int(u["id"]) == unit_id:
            return u
    return None


def _end_turn_action(actor_id: int) -> dict[str, Any]:
    return {
        "schema_version": world_actions.SCHEMA_VERSION,
        "action_type": world_actions.END_TURN_ACTION_TYPE,
        "actor_id": actor_id,
    }


def _move_actions_for_unit(
    snap: dict[str, Any],
    world_map: WorldMap,
    actor_id: int,
    unit: dict[str, Any],
) -> list[dict[str, Any]]:
    """Submit-ready move_unit rows (exact N7a POST shape), DIRECTIONS order."""
    from_q = int(unit["position"][0])
    from_r = int(unit["position"][1])
    out: list[dict[str, Any]] = []
    for dq, dr in DIRECTIONS:
        act = {
            "schema_version": world_actions.SCHEMA_VERSION,
            "action_type": world_actions.MOVE_UNIT_ACTION_TYPE,
            "actor_id": actor_id,
            "unit_id": int(unit["id"]),
            "from": [from_q, from_r],
            "to": [from_q + dq, from_r + dr],
        }
        if not world_actions.validate_move_unit_pre_map(snap, act)["ok"]:
            continue
        if not world_actions.validate_move_unit_destination(world_map, snap, act)["ok"]:
            continue
        out.append(act)
    return out


def _attack_actions_for_unit(
    snap: dict[str, Any],
    world_map: WorldMap,
    actor_id: int,
    unit: dict[str, Any],
) -> list[dict[str, Any]]:
    """Submit-ready attack_unit rows (exact N7g.1 POST shape) in canonical
    DIRECTIONS order of the defender tile — derived through the N7g.1
    validators only (never a second attack-legality implementation)."""
    from_q = int(unit["position"][0])
    from_r = int(unit["position"][1])
    out: list[dict[str, Any]] = []
    for dq, dr in DIRECTIONS:
        defender = world_actions.unit_at(snap, (from_q + dq, from_r + dr))
        if defender is None:
            continue
        act = {
            "schema_version": world_actions.SCHEMA_VERSION,
            "action_type": world_actions.ATTACK_UNIT_ACTION_TYPE,
            "actor_id": actor_id,
            "attacker_id": int(unit["id"]),
            "defender_id": int(defender["id"]),
        }
        if not world_actions.validate_attack_unit_pre_map(snap, act)["ok"]:
            continue
        if not world_actions.validate_attack_unit_target(world_map, snap, act)["ok"]:
            continue
        out.append(act)
    return out


def compute_world_legal_actions_payload(
    snap: dict[str, Any],
    world_map: WorldMap,
    actor_id: int,
    selected_unit_id: int | None,
    selected_city_id: int | None,
) -> dict[str, Any]:
    """Legacy-shaped legal-actions body for a world match (read-only).

    Out-of-turn actors get is_current_player false with empty actions (no
    rejection — credential gating is the API layer's job). Selection
    precedence and errors mirror legal_actions.compute_legal_actions_payload;
    city selections have no world behavior beyond unknown_city (there are no
    world cities in N7).
    """
    current = _current_player_id(snap)
    is_current = actor_id == current

    out: dict[str, Any] = {
        "match_id": str(snap["match_id"]),
        "revision": int(snap["revision"]),
        "schema_version": LEGAL_ACTIONS_SCHEMA_VERSION,
        "actor_id": actor_id,
        "is_current_player": is_current,
        "selected_unit_id": selected_unit_id,
        "selected_city_id": selected_city_id,
        "selection_error": None,
        "actions": [],
    }

    if not is_current:
        return out

    selection_error: str | None = None
    actions: list[dict[str, Any]] = []

    if selected_unit_id is not None:
        unit = _unit_by_id(snap, selected_unit_id)
        if unit is None:
            selection_error = "unknown_unit"
        elif int(unit["owner_id"]) != actor_id:
            selection_error = "selection_not_owned"
        else:
            # N7g.2 deterministic ordering: attacks first, then moves.
            actions.extend(_attack_actions_for_unit(snap, world_map, actor_id, unit))
            actions.extend(_move_actions_for_unit(snap, world_map, actor_id, unit))

    if selected_city_id is not None and selection_error is None:
        selection_error = "unknown_city"

    if selection_error is not None:
        out["selection_error"] = selection_error
        out["actions"] = []
        return out

    if selected_unit_id is not None or selected_city_id is not None:
        out["actions"] = actions
        return out

    # Actor summary: submit-ready end_turn + per-unit action counts (N7g.2:
    # legal attacks + legal moves — exactly the selected-unit row count).
    # Snapshot units are already sorted ascending by id (N7a invariant).
    out["actions"] = [_end_turn_action(actor_id)]
    unit_summaries: list[dict[str, int]] = []
    for u in snap.get("units", []):
        if int(u["owner_id"]) != actor_id:
            continue
        n = len(_attack_actions_for_unit(snap, world_map, actor_id, u)) + len(
            _move_actions_for_unit(snap, world_map, actor_id, u)
        )
        unit_summaries.append({"unit_id": int(u["id"]), "legal_action_count": n})
    out["unit_summaries"] = unit_summaries
    out["city_summaries"] = []
    return out
