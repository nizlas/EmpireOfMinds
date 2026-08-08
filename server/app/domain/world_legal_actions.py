"""N7b/N7g.2/N8a: read-only legal-actions enumeration for world_map matches.

Separate from the frozen legacy legal_actions.py (no Scenario, no HexMap, no
movement_rules import) but wire-compatible: the response envelope, selection
precedence, and selection errors mirror the legacy endpoint exactly so
clients consume one schema.

Move, attack, and found_city rows are DERIVED, never re-implemented:
candidates are constructed and filtered through the SAME world validators
the POST path uses against the resolved authoritative WorldMap (moves /
attacks) or the snapshot (found_city). Every returned action is therefore
submit-ready by construction.

Selected-unit ordering is deterministic: ALL legal attack_unit rows first
(canonical DIRECTIONS order of the defender tile), then the found_city row
when legal, then all legal move_unit rows (canonical DIRECTIONS order of
the destination tile). Unit summaries count attacks + found_city + moves;
settlers stay non-attacking and a unit with has_attacked true advertises
neither attacks nor moves (both enforced by the validators).

N8a: city_summaries list the actor's cities with legal_action_count 0
(production selection is N8b). A selected own city returns empty actions
without error until N8b; unknown/unowned city selections keep the legacy
selection_error strings.

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


def _found_city_action_if_legal(
    snap: dict[str, Any],
    actor_id: int,
    unit: dict[str, Any],
) -> list[dict[str, Any]]:
    """Submit-ready found_city row (exact N8a POST shape) when legal."""
    act = {
        "schema_version": world_actions.SCHEMA_VERSION,
        "action_type": world_actions.FOUND_CITY_ACTION_TYPE,
        "actor_id": actor_id,
        "unit_id": int(unit["id"]),
        "position": [int(unit["position"][0]), int(unit["position"][1])],
    }
    if world_actions.validate_found_city(snap, act)["ok"]:
        return [act]
    return []


def _unit_action_count(
    snap: dict[str, Any],
    world_map: WorldMap,
    actor_id: int,
    unit: dict[str, Any],
) -> int:
    return (
        len(_attack_actions_for_unit(snap, world_map, actor_id, unit))
        + len(_found_city_action_if_legal(snap, actor_id, unit))
        + len(_move_actions_for_unit(snap, world_map, actor_id, unit))
    )


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
    precedence and errors mirror legal_actions.compute_legal_actions_payload.
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
            # Deterministic ordering: attacks, found_city, then moves.
            actions.extend(_attack_actions_for_unit(snap, world_map, actor_id, unit))
            actions.extend(_found_city_action_if_legal(snap, actor_id, unit))
            actions.extend(_move_actions_for_unit(snap, world_map, actor_id, unit))

    if selected_city_id is not None and selection_error is None:
        city = world_actions.city_by_id(snap, int(selected_city_id))
        if city is None:
            selection_error = "unknown_city"
        elif int(city["owner_id"]) != actor_id:
            selection_error = "selection_not_owned_city"
        # N8a: known own city — empty actions until N8b production selection.

    if selection_error is not None:
        out["selection_error"] = selection_error
        out["actions"] = []
        return out

    if selected_unit_id is not None or selected_city_id is not None:
        out["actions"] = actions
        return out

    # Actor summary: submit-ready end_turn + per-unit action counts
    # (attacks + found_city + moves) and city summaries (count 0 until N8b).
    out["actions"] = [_end_turn_action(actor_id)]
    unit_summaries: list[dict[str, int]] = []
    for u in snap.get("units", []):
        if int(u["owner_id"]) != actor_id:
            continue
        unit_summaries.append(
            {
                "unit_id": int(u["id"]),
                "legal_action_count": _unit_action_count(snap, world_map, actor_id, u),
            }
        )
    out["unit_summaries"] = unit_summaries
    city_summaries: list[dict[str, int]] = []
    for c in snap.get("cities", []):
        if int(c["owner_id"]) != actor_id:
            continue
        city_summaries.append({"city_id": int(c["id"]), "legal_action_count": 0})
    out["city_summaries"] = city_summaries
    return out
