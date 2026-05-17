"""HTTP API: Cloud 0.1 matches and actions."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query

from app.domain import match_state, snapshot
from app.domain.actions import end_turn, found_city, move_unit, set_city_production
from app.domain.food_growth_rules import apply_food_growth_for_player
from app.domain.movement_rules import refresh_movement_for_owner
from app.domain.production_rules import apply_production_tick_for_player, deliver_pending_for_player
from app.domain.progress_state import ProgressState
from app.domain.science_tick_rules import apply_science_tick_for_player
from app.domain.state_hash import state_hash
from app.domain.turn_state import advance_turn_state
from app.storage import file_store

router = APIRouter(tags=["matches"])


def _reject(reason: str) -> dict[str, Any]:
    return {"accepted": False, "reason": reason, "index": -1}


def _map_end_turn_validate_reason(vr_reason: str) -> str:
    if vr_reason == "unsupported_schema_version":
        return "unsupported_schema_version"
    if vr_reason == "malformed_action":
        return "malformed_action"
    return "unknown_action_type"


def _map_move_validate_reason(vr_reason: str) -> str:
    if vr_reason == "wrong_action_type":
        return "unknown_action_type"
    return vr_reason


def _map_found_city_validate_reason(vr_reason: str) -> str:
    if vr_reason == "wrong_action_type":
        return "unknown_action_type"
    if vr_reason == "actor_not_owner":
        return "unit_not_owned_by_player"
    if vr_reason == "unit_type_cannot_found":
        return "unit_cannot_found_city"
    return vr_reason


def _map_set_city_production_reason(vr_reason: str) -> str:
    if vr_reason == "wrong_action_type":
        return "unknown_action_type"
    if vr_reason == "actor_not_owner":
        return "city_not_owned_by_player"
    if vr_reason == "unsupported_project_id":
        return "unknown_city_project"
    return vr_reason


def _actor_gate(snap: dict[str, Any], action: dict[str, Any]) -> str | None:
    if "actor_id" not in action or not isinstance(action["actor_id"], int):
        return "malformed_action"
    if int(action["actor_id"]) != match_state.current_player_id(snap):
        return "not_current_player"
    return None


@router.get("/healthz")
def healthz() -> dict[str, bool]:
    return {"ok": True}


@router.post("/matches")
def create_match(
    body: dict[str, Any] | None = Body(default=None),
) -> dict[str, Any]:
    if body is None:
        body = {}
    player_ids = body.get("player_ids")
    if player_ids is None:
        player_ids = [0, 1]
    if not isinstance(player_ids, list) or len(player_ids) < 1:
        raise HTTPException(status_code=400, detail="player_ids must be a non-empty list")
    for pid in player_ids:
        if not isinstance(pid, int):
            raise HTTPException(status_code=400, detail="player_ids must be integers")

    scenario_id = body.get("scenario_id", "prototype_play")
    if scenario_id not in ("prototype_play", "tiny_test"):
        raise HTTPException(status_code=400, detail="unknown scenario_id")

    mid = match_state.make_match_id()
    snap = match_state.initial_snapshot(mid, player_ids, str(scenario_id))
    file_store.write_snapshot(mid, snap)
    return {
        "match_id": mid,
        "snapshot": snap,
        "revision": snap["revision"],
        "state_hash": state_hash(snap),
    }


@router.get("/matches/{match_id}")
def get_match(match_id: str) -> dict[str, Any]:
    snap = file_store.read_snapshot(match_id)
    if snap is None:
        raise HTTPException(status_code=404, detail="match not found")
    return {
        "match_id": match_id,
        "snapshot": snap,
        "revision": snap["revision"],
        "state_hash": state_hash(snap),
    }


def _handle_end_turn(match_id: str, snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    gate = _actor_gate(snap, action)
    if gate is not None:
        return _reject(gate)

    vr = end_turn.validate(snap["turn_state"], action)
    if not vr["ok"]:
        return _reject(_map_end_turn_validate_reason(str(vr["reason"])))

    prev_turn_number = int(snap["turn_state"]["turn_number"])
    ending_player = match_state.current_player_id(snap)

    scenario = snapshot.scenario_from_snapshot_dict(snap["scenario"])
    progress = ProgressState.from_snapshot_dict(snap["progress_state"])
    scenario, tick_events_raw = apply_production_tick_for_player(scenario, ending_player)
    scenario, food_events_raw = apply_food_growth_for_player(scenario, ending_player)
    progress, science_events_raw = apply_science_tick_for_player(progress, scenario, ending_player)

    new_turn = advance_turn_state(snap["turn_state"])
    new_revision = int(snap["revision"]) + 1
    next_player = int(new_turn["players"][int(new_turn["current_index"])])

    scenario, delivery_events_raw = deliver_pending_for_player(scenario, next_player)
    scenario = refresh_movement_for_owner(scenario, next_player)

    new_snap: dict[str, Any] = {
        **snap,
        "revision": new_revision,
        "turn_state": new_turn,  # type: ignore[dict-item]
        "scenario": snapshot.serialize_scenario(scenario),
        "progress_state": snapshot.serialize_progress_state(progress),
    }

    file_store.write_snapshot(match_id, new_snap)

    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    base = len(file_store.read_events(match_id))
    engine_before_end = [*tick_events_raw, *food_events_raw, *science_events_raw]
    tick_base = base
    for i, te in enumerate(engine_before_end):
        row = {
            **te,
            "index": tick_base + i,
            "revision": new_revision,
            "accepted_at": accepted_at,
        }
        file_store.append_event(match_id, row)

    end_turn_index = base + len(engine_before_end)
    end_turn_event = {
        "index": end_turn_index,
        "revision": new_revision,
        "schema_version": int(action["schema_version"]),
        "action_type": end_turn.ACTION_TYPE,
        "actor_id": int(action["actor_id"]),
        "turn_number_before": prev_turn_number,
        "next_player_id": next_player,
        "result": "accepted",
        "accepted_at": accepted_at,
    }
    file_store.append_event(match_id, end_turn_event)

    del_base = end_turn_index + 1
    for i, de in enumerate(delivery_events_raw):
        row = {
            **de,
            "index": del_base + i,
            "revision": new_revision,
            "accepted_at": accepted_at,
        }
        file_store.append_event(match_id, row)

    return {
        "accepted": True,
        "reason": "",
        "index": end_turn_index,
        "revision": new_revision,
        "snapshot": new_snap,
        "state_hash": state_hash(new_snap),
    }


def _handle_move_unit(match_id: str, snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    gate = _actor_gate(snap, action)
    if gate is not None:
        return _reject(gate)

    scenario = snapshot.scenario_from_snapshot_dict(snap["scenario"])
    vr = move_unit.validate(scenario, action)
    if not vr["ok"]:
        return _reject(_map_move_validate_reason(str(vr["reason"])))

    new_scenario = move_unit.apply_move(scenario, action)
    new_revision = int(snap["revision"]) + 1
    new_snap: dict[str, Any] = {
        **snap,
        "revision": new_revision,
        "scenario": snapshot.serialize_scenario(new_scenario),
    }

    moved = new_scenario.unit_by_id(int(action["unit_id"]))
    if moved is None:
        return _reject("unknown_unit")
    log_index = len(file_store.read_events(match_id))
    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    event = {
        "index": log_index,
        "revision": new_revision,
        "schema_version": int(action["schema_version"]),
        "action_type": move_unit.ACTION_TYPE,
        "actor_id": int(action["actor_id"]),
        "unit_id": int(action["unit_id"]),
        "from": [int(action["from"][0]), int(action["from"][1])],
        "to": [int(action["to"][0]), int(action["to"][1])],
        "remaining_movement": int(moved.remaining_movement),
        "result": "accepted",
        "accepted_at": accepted_at,
    }
    file_store.write_snapshot(match_id, new_snap)
    file_store.append_event(match_id, event)
    return {
        "accepted": True,
        "reason": "",
        "index": log_index,
        "revision": new_revision,
        "snapshot": new_snap,
        "state_hash": state_hash(new_snap),
    }


def _handle_found_city(match_id: str, snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    gate = _actor_gate(snap, action)
    if gate is not None:
        return _reject(gate)

    scenario = snapshot.scenario_from_snapshot_dict(snap["scenario"])
    vr = found_city.validate(scenario, action)
    if not vr["ok"]:
        return _reject(_map_found_city_validate_reason(str(vr["reason"])))

    new_scenario = found_city.apply_found_city(scenario, action)
    new_revision = int(snap["revision"]) + 1
    new_snap: dict[str, Any] = {
        **snap,
        "revision": new_revision,
        "scenario": snapshot.serialize_scenario(new_scenario),
    }

    new_city_id = new_scenario.peek_next_city_id() - 1
    city = new_scenario.city_by_id(new_city_id)
    if city is None:
        return _reject("malformed_action")

    log_index = len(file_store.read_events(match_id))
    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    event = {
        "index": log_index,
        "revision": new_revision,
        "schema_version": int(action["schema_version"]),
        "action_type": found_city.ACTION_TYPE,
        "actor_id": int(action["actor_id"]),
        "unit_id": int(action["unit_id"]),
        "city_id": int(city.id),
        "city_name": str(city.city_name),
        "at": [city.position.q, city.position.r],
        "settler_consumed": True,
        "result": "accepted",
        "accepted_at": accepted_at,
    }
    file_store.write_snapshot(match_id, new_snap)
    file_store.append_event(match_id, event)
    return {
        "accepted": True,
        "reason": "",
        "index": log_index,
        "revision": new_revision,
        "snapshot": new_snap,
        "state_hash": state_hash(new_snap),
    }


def _handle_set_city_production(match_id: str, snap: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    gate = _actor_gate(snap, action)
    if gate is not None:
        return _reject(gate)

    scenario = snapshot.scenario_from_snapshot_dict(snap["scenario"])
    progress = ProgressState.from_snapshot_dict(snap["progress_state"])
    vr = set_city_production.validate(scenario, progress, action)
    if not vr["ok"]:
        return _reject(_map_set_city_production_reason(str(vr["reason"])))

    new_scenario = set_city_production.apply_set_city_production(scenario, action)
    new_revision = int(snap["revision"]) + 1
    new_snap: dict[str, Any] = {
        **snap,
        "revision": new_revision,
        "scenario": snapshot.serialize_scenario(new_scenario),
    }

    city = new_scenario.city_by_id(int(action["city_id"]))
    if city is None:
        return _reject("unknown_city")

    log_index = len(file_store.read_events(match_id))
    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    ev_progress = set_city_production.project_progress_for_event(city)
    event: dict[str, Any] = {
        "index": log_index,
        "revision": new_revision,
        "schema_version": int(action["schema_version"]),
        "action_type": set_city_production.ACTION_TYPE,
        "actor_id": int(action["actor_id"]),
        "city_id": int(action["city_id"]),
        "project_id": str(action["project_id"]),
        "result": "accepted",
        "accepted_at": accepted_at,
    }
    if ev_progress is not None:
        event["project_progress"] = ev_progress
    else:
        event["project_progress"] = None

    file_store.write_snapshot(match_id, new_snap)
    file_store.append_event(match_id, event)
    return {
        "accepted": True,
        "reason": "",
        "index": log_index,
        "revision": new_revision,
        "snapshot": new_snap,
        "state_hash": state_hash(new_snap),
    }


@router.post("/matches/{match_id}/actions")
def post_action(match_id: str, action: dict[str, Any] = Body(...)) -> dict[str, Any]:
    snap = file_store.read_snapshot(match_id)
    if snap is None:
        raise HTTPException(status_code=404, detail="match not found")

    if action is None or not isinstance(action, dict):
        return _reject("unknown_action_type")
    if "action_type" not in action or not isinstance(action["action_type"], str):
        return _reject("unknown_action_type")

    at = action["action_type"]
    if at == end_turn.ACTION_TYPE:
        return _handle_end_turn(match_id, snap, action)
    if at == move_unit.ACTION_TYPE:
        return _handle_move_unit(match_id, snap, action)
    if at == found_city.ACTION_TYPE:
        return _handle_found_city(match_id, snap, action)
    if at == set_city_production.ACTION_TYPE:
        return _handle_set_city_production(match_id, snap, action)
    return _reject("unknown_action_type")


@router.get("/matches/{match_id}/events")
def get_events(
    match_id: str,
    since: int | None = Query(default=None),
) -> dict[str, Any]:
    if file_store.read_snapshot(match_id) is None:
        raise HTTPException(status_code=404, detail="match not found")
    events = file_store.read_events(match_id)
    if since is not None:
        events = [e for e in events if int(e["index"]) > since]
    return {"match_id": match_id, "events": events}
