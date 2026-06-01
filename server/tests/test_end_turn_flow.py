"""Cloud 0.1 end_turn flow tests."""

from __future__ import annotations

from fastapi.testclient import TestClient


def test_healthz(client: TestClient) -> None:
    r = client.get("/v1/healthz")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


def test_create_match_default_players(client: TestClient) -> None:
    r = client.post("/v1/matches", json={})
    assert r.status_code == 200
    data = r.json()
    assert "match_id" in data
    snap = data["snapshot"]
    assert snap["revision"] == 0
    assert snap["schema_version"] == 2
    assert snap["turn_state"]["players"] == [0, 1]
    assert snap["turn_state"]["current_index"] == 0
    assert data["state_hash"]


def test_load_match(client: TestClient) -> None:
    c = client.post("/v1/matches", json={}).json()
    mid = c["match_id"]
    r = client.get(f"/v1/matches/{mid}")
    assert r.status_code == 200
    data = r.json()
    assert data["match_id"] == mid
    assert data["snapshot"] == c["snapshot"]
    assert data["state_hash"] == c["state_hash"]


def test_p0_end_turn_advances_to_p1(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] is True
    assert body["reason"] == ""
    assert body["index"] == 0
    assert body["revision"] == 1
    assert body["snapshot"]["turn_state"]["current_index"] == 1
    assert body["snapshot"]["turn_state"]["turn_number"] == 1
    assert body["state_hash"]


def test_repeated_p0_end_turn_rejects(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    assert r.status_code == 200
    assert r.json() == {
        "accepted": False,
        "reason": "not_current_player",
        "index": -1,
    }


def test_p1_end_turn_wraps_turn_number(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 1},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] is True
    ts = body["snapshot"]["turn_state"]
    assert ts["current_index"] == 0
    assert ts["turn_number"] == 2
    assert ts["players"] == [0, 1]


def test_unknown_action_type_rejects(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "teleport_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.status_code == 200
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "unknown_action_type"
    assert r.json()["index"] == -1


def test_event_log_only_accepted_actions(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "not_a_real_action",
            "actor_id": 0,
        },
    )
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert len(ev) == 1
    assert ev[0]["action_type"] == "end_turn"


def test_events_since_filters(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 1},
    )
    tail = client.get(f"/v1/matches/{mid}/events", params={"since": 0}).json()["events"]
    assert len(tail) == 1
    assert tail[0]["index"] == 1


def test_state_hash_stable_and_changes_on_accept(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={}).json()["match_id"]
    g1 = client.get(f"/v1/matches/{mid}").json()
    g2 = client.get(f"/v1/matches/{mid}").json()
    assert g1["state_hash"] == g2["state_hash"]

    after = client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    ).json()
    assert after["state_hash"] != g1["state_hash"]

    g3 = client.get(f"/v1/matches/{mid}").json()
    assert g3["state_hash"] == after["state_hash"]
