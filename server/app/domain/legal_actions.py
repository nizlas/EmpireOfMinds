"""Read-only legal action enumeration for Cloud Slice C7 (query-only, no mutation).

Deterministic ordering:
- action_type buckets: attack_unit, end_turn, found_city, move_unit, set_city_production (lexicographic).
- attack_unit: attacker_id, then defender_id.
- move_unit: unit_id, then destination (q, r); destinations from movement_rules.legal_move_destinations
  (already sorted by q, r).
- found_city: unit_id, then position (q, r).
- set_city_production: city_id, then project_id (lexicographic; \"none\" precedes produce_unit:*).
"""

from __future__ import annotations

from typing import Any

from app.domain import snapshot
from app.domain.actions import attack_unit, end_turn, found_city, move_unit, set_city_production
from app.domain.content import city_project_definitions as cpd
from app.domain.match_state import current_player_id
from app.domain.movement_rules import legal_move_destinations
from app.domain.progress_state import ProgressState
from app.domain.scenario import Scenario

LEGAL_ACTIONS_SCHEMA_VERSION = 1

_TYPE_ORDER = {
    "attack_unit": 0,
    "end_turn": 1,
    "found_city": 2,
    "move_unit": 3,
    "set_city_production": 4,
}


def _sort_actions(actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(a: dict[str, Any]) -> tuple:
        at = str(a["action_type"])
        bucket = _TYPE_ORDER[at]
        if at == "end_turn":
            return (bucket, int(a["actor_id"]))
        if at == "attack_unit":
            return (bucket, int(a["attacker_id"]), int(a["defender_id"]))
        if at == "found_city":
            pos = a["position"]
            return (bucket, int(a["unit_id"]), int(pos[0]), int(pos[1]))
        if at == "move_unit":
            to = a["to"]
            return (bucket, int(a["unit_id"]), int(to[0]), int(to[1]))
        return (bucket, int(a["city_id"]), str(a["project_id"]))

    return sorted(actions, key=key)


def _end_turn_action(actor_id: int) -> dict[str, Any]:
    return {
        "schema_version": end_turn.SCHEMA_VERSION,
        "action_type": end_turn.ACTION_TYPE,
        "actor_id": actor_id,
    }


def _attack_actions_for_unit(scenario: Scenario, actor_id: int, unit_id: int) -> list[dict[str, Any]]:
    attacker = scenario.unit_by_id(unit_id)
    if attacker is None or attacker.owner_id != actor_id:
        return []
    if str(attacker.type_id) != attack_unit.WARRIOR_TYPE:
        return []
    out: list[dict[str, Any]] = []
    for defender in sorted(scenario.units(), key=lambda u: u.id):
        if defender.owner_id == actor_id:
            continue
        if str(defender.type_id) != attack_unit.WARRIOR_TYPE:
            continue
        act = {
            "schema_version": attack_unit.SCHEMA_VERSION,
            "action_type": attack_unit.ACTION_TYPE,
            "actor_id": actor_id,
            "attacker_id": unit_id,
            "defender_id": defender.id,
        }
        if attack_unit.validate(scenario, act)["ok"]:
            out.append(act)
    return out


def _move_actions_for_unit(scenario: Scenario, actor_id: int, unit_id: int) -> list[dict[str, Any]]:
    u = scenario.unit_by_id(unit_id)
    if u is None or u.owner_id != actor_id:
        return []
    out: list[dict[str, Any]] = []
    for dest in legal_move_destinations(scenario, unit_id):
        act = {
            "schema_version": move_unit.SCHEMA_VERSION,
            "action_type": move_unit.ACTION_TYPE,
            "actor_id": actor_id,
            "unit_id": unit_id,
            "from": [u.position.q, u.position.r],
            "to": [dest.q, dest.r],
        }
        vr = move_unit.validate(scenario, act)
        if vr["ok"]:
            out.append(act)
    return out


def _found_city_action_if_legal(scenario: Scenario, actor_id: int, unit_id: int) -> list[dict[str, Any]]:
    u = scenario.unit_by_id(unit_id)
    if u is None or u.owner_id != actor_id:
        return []
    act = {
        "schema_version": found_city.SCHEMA_VERSION,
        "action_type": found_city.ACTION_TYPE,
        "actor_id": actor_id,
        "unit_id": unit_id,
        "position": [u.position.q, u.position.r],
    }
    if found_city.validate(scenario, act)["ok"]:
        return [act]
    return []


def _set_city_production_actions_for_city(
    scenario: Scenario, progress: ProgressState, actor_id: int, city_id: int
) -> list[dict[str, Any]]:
    city = scenario.city_by_id(city_id)
    if city is None or city.owner_id != actor_id:
        return []
    project_ids = [cpd.PROJECT_ID_NONE, *sorted(c for c in cpd.ids())]
    out: list[dict[str, Any]] = []
    for pid in project_ids:
        act = {
            "schema_version": set_city_production.SCHEMA_VERSION,
            "action_type": set_city_production.ACTION_TYPE,
            "actor_id": actor_id,
            "city_id": city_id,
            "project_id": pid,
        }
        if set_city_production.validate(scenario, progress, act)["ok"]:
            out.append(act)
    return out


def _unit_action_count(scenario: Scenario, actor_id: int, unit_id: int) -> int:
    return (
        len(_attack_actions_for_unit(scenario, actor_id, unit_id))
        + len(_move_actions_for_unit(scenario, actor_id, unit_id))
        + len(_found_city_action_if_legal(scenario, actor_id, unit_id))
    )


def _city_action_count(scenario: Scenario, progress: ProgressState, actor_id: int, city_id: int) -> int:
    return len(_set_city_production_actions_for_city(scenario, progress, actor_id, city_id))


def compute_legal_actions_payload(
    snap: dict[str, Any],
    actor_id: int,
    selected_unit_id: int | None,
    selected_city_id: int | None,
) -> dict[str, Any]:
    """Build legal-actions JSON body (read-only). Caller supplies match_id on the wire layer."""
    match_id = str(snap["match_id"])
    revision = int(snap["revision"])
    current = current_player_id(snap)
    is_current = actor_id == current

    out: dict[str, Any] = {
        "match_id": match_id,
        "revision": revision,
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

    scenario = snapshot.scenario_from_snapshot_dict(snap["scenario"])
    progress = ProgressState.from_snapshot_dict(snap["progress_state"])

    selection_error: str | None = None
    actions: list[dict[str, Any]] = []

    if selected_unit_id is not None:
        u = scenario.unit_by_id(selected_unit_id)
        if u is None:
            selection_error = "unknown_unit"
        elif u.owner_id != actor_id:
            selection_error = "selection_not_owned"
        else:
            actions.extend(_attack_actions_for_unit(scenario, actor_id, selected_unit_id))
            actions.extend(_move_actions_for_unit(scenario, actor_id, selected_unit_id))
            actions.extend(_found_city_action_if_legal(scenario, actor_id, selected_unit_id))

    if selected_city_id is not None and selection_error is None:
        c = scenario.city_by_id(selected_city_id)
        if c is None:
            selection_error = "unknown_city"
        elif c.owner_id != actor_id:
            selection_error = "selection_not_owned_city"
        else:
            actions.extend(
                _set_city_production_actions_for_city(scenario, progress, actor_id, selected_city_id)
            )

    if selection_error is not None:
        out["selection_error"] = selection_error
        out["actions"] = []
        return out

    if selected_unit_id is not None or selected_city_id is not None:
        out["actions"] = _sort_actions(actions)
        return out

    # Actor summary: end_turn + compact per-entity counts (no bulk move enumeration).
    actions.append(_end_turn_action(actor_id))

    unit_summaries: list[dict[str, int]] = []
    for u in sorted(scenario.units(), key=lambda x: x.id):
        if u.owner_id != actor_id:
            continue
        n = _unit_action_count(scenario, actor_id, u.id)
        unit_summaries.append({"unit_id": u.id, "legal_action_count": n})

    city_summaries: list[dict[str, int]] = []
    for c in sorted(scenario.cities(), key=lambda x: x.id):
        if c.owner_id != actor_id:
            continue
        n = _city_action_count(scenario, progress, actor_id, c.id)
        city_summaries.append({"city_id": c.id, "legal_action_count": n})

    out["actions"] = _sort_actions(actions)
    out["unit_summaries"] = unit_summaries
    out["city_summaries"] = city_summaries
    return out
