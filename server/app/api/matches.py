"""HTTP API: Cloud 0.1 matches and actions."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query

from app.domain import match_state
from app.domain.actions import end_turn
from app.domain.state_hash import state_hash
from app.storage import file_store

router = APIRouter(tags=["matches"])


def _reject(reason: str) -> dict[str, Any]:
    return {"accepted": False, "reason": reason, "index": -1}


def _map_validate_reason(vr_reason: str) -> str:
    if vr_reason == "unsupported_schema_version":
        return "unsupported_schema_version"
    if vr_reason == "malformed_action":
        return "malformed_action"
    return "unknown_action_type"


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

    mid = match_state.make_match_id()
    snap = match_state.initial_snapshot(mid, player_ids)
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


@router.post("/matches/{match_id}/actions")
def post_action(match_id: str, action: dict[str, Any] = Body(...)) -> dict[str, Any]:
    snap = file_store.read_snapshot(match_id)
    if snap is None:
        raise HTTPException(status_code=404, detail="match not found")

    if action is None or not isinstance(action, dict):
        return _reject("unknown_action_type")
    if "action_type" not in action or not isinstance(action["action_type"], str):
        return _reject("unknown_action_type")
    if action["action_type"] != end_turn.ACTION_TYPE:
        return _reject("unknown_action_type")
    if "actor_id" not in action or not isinstance(action["actor_id"], int):
        return _reject("malformed_action")
    if action["actor_id"] != match_state.current_player_id(snap):
        return _reject("not_current_player")

    vr = end_turn.validate(snap["turn_state"], action)
    if not vr["ok"]:
        return _reject(_map_validate_reason(str(vr["reason"])))

    prev_turn_number = int(snap["turn_state"]["turn_number"])
    new_turn = match_state.advance_turn_state(snap["turn_state"])
    new_revision = int(snap["revision"]) + 1
    new_snap = {
        **snap,
        "revision": new_revision,
        "turn_state": new_turn,
    }
    next_player = match_state.current_player_id(new_snap)
    log_index = len(file_store.read_events(match_id))
    accepted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    event = {
        "index": log_index,
        "revision": new_revision,
        "schema_version": int(action["schema_version"]),
        "action_type": end_turn.ACTION_TYPE,
        "actor_id": int(action["actor_id"]),
        "turn_number_before": prev_turn_number,
        "next_player_id": next_player,
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
