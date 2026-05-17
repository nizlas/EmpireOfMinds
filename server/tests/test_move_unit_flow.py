"""Slice C1: server move_unit and end_turn movement refresh."""

from __future__ import annotations

import copy

from fastapi.testclient import TestClient


def _u_by_id(snap: dict, uid: int) -> dict:
    for u in snap["scenario"]["units"]:
        if u["id"] == uid:
            return u
    raise AssertionError(uid)


def test_prototype_match_units_start_with_full_movement(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap["schema_version"] == 2
    for u in snap["scenario"]["units"]:
        assert u["remaining_movement"] == 2


def test_accepted_move_updates_position_revision_hash_and_event(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    snap0 = client.get(f"/v1/matches/{mid}").json()
    h0 = snap0["state_hash"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] is True
    assert body["revision"] == 1
    assert body["state_hash"] != h0
    u1 = _u_by_id(body["snapshot"], 1)
    assert u1["position"] == [1, -1]
    assert u1["remaining_movement"] == 1

    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert len(ev) == 1
    assert ev[0]["action_type"] == "move_unit"
    assert ev[0]["unit_id"] == 1
    assert ev[0]["from"] == [0, 0]
    assert ev[0]["to"] == [1, -1]
    assert ev[0]["remaining_movement"] == 1


def test_second_move_reduces_movement_to_zero(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [1, -1],
            "to": [0, 0],
        },
    )
    assert r.status_code == 200
    assert r.json()["accepted"] is True
    assert _u_by_id(r.json()["snapshot"], 1)["remaining_movement"] == 0


def test_third_move_rejected_movement_exhausted(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [1, -1],
            "to": [0, 0],
        },
    )
    snap_before = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    rev_before = snap_before["revision"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] is False
    assert body["reason"] == "movement_exhausted"
    assert body["index"] == -1
    snap_after = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap_after["revision"] == rev_before
    assert _u_by_id(snap_after, 1) == _u_by_id(snap_before, 1)


def test_not_current_player_rejected(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 1,
            "unit_id": 3,
            "from": [0, -1],
            "to": [1, -1],
        },
    )
    assert r.json() == {"accepted": False, "reason": "not_current_player", "index": -1}


def test_unit_not_owned_by_player(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 3,
            "from": [0, -1],
            "to": [1, -1],
        },
    )
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "unit_not_owned_by_player"
    assert r.json()["index"] == -1


def test_destination_not_adjacent(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [0, 0],
        },
    )
    assert r.json()["reason"] == "destination_not_adjacent"


def test_destination_not_on_map(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [99, 99],
        },
    )
    assert r.json()["reason"] == "destination_not_on_map"


def test_destination_not_passable_water(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [-1, 0],
        },
    )
    assert r.json()["reason"] == "destination_not_passable"


def test_destination_occupied(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, 0],
        },
    )
    assert r.json()["reason"] == "destination_occupied"


def test_end_turn_refreshes_movement_for_new_current_player(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    u1_partial = _u_by_id(client.get(f"/v1/matches/{mid}").json()["snapshot"], 1)
    assert u1_partial["remaining_movement"] == 1

    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    snap_p1 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap_p1["turn_state"]["current_index"] == 1
    u1_still = _u_by_id(snap_p1, 1)
    assert u1_still["remaining_movement"] == 1
    u2 = _u_by_id(snap_p1, 2)
    assert u2["remaining_movement"] == 2
    u3 = _u_by_id(snap_p1, 3)
    assert u3["remaining_movement"] == 2

    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 1},
    )
    snap_p0_again = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap_p0_again["turn_state"]["current_index"] == 0
    u1_full = _u_by_id(snap_p0_again, 1)
    u2_full = _u_by_id(snap_p0_again, 2)
    assert u1_full["remaining_movement"] == 2
    assert u2_full["remaining_movement"] == 2


def test_snapshot_v2_progress_state_unchanged_by_move_and_end_turn(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    prog_before = copy.deepcopy(
        client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    )
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        },
    )
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    prog_after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    assert prog_after == prog_before
    assert client.get(f"/v1/matches/{mid}").json()["snapshot"]["schema_version"] == 2

