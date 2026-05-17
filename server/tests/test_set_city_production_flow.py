"""Slice C3: server set_city_production."""

from __future__ import annotations

import copy

from fastapi.testclient import TestClient

from app.domain import snapshot
from app.domain.progress_state import ProgressState, _normalize_unlocked_targets
from app.storage import file_store


def _tiny_match_with_capital(client: TestClient) -> str:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        },
    )
    return mid


def _scp(
    client: TestClient,
    mid: str,
    *,
    actor_id: int = 0,
    city_id: int = 1,
    project_id: str = "produce_unit:warrior",
    schema_version: int = 2,
) -> dict:
    return client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": schema_version,
            "action_type": "set_city_production",
            "actor_id": actor_id,
            "city_id": city_id,
            "project_id": project_id,
        },
    ).json()


def test_accepted_warrior_project(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    prog_after_found = copy.deepcopy(
        client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    )
    g0 = client.get(f"/v1/matches/{mid}").json()["state_hash"]
    body = _scp(client, mid, project_id="produce_unit:warrior")
    assert body["accepted"] is True
    assert body["revision"] == 2
    assert body["state_hash"] != g0
    c = body["snapshot"]["scenario"]["cities"][0]
    cp = c["current_project"]
    assert cp is not None
    assert cp["project_id"] == "produce_unit:warrior"
    assert cp["project_type"] == "produce_unit"
    assert cp["progress"] == 0
    assert cp["cost"] == 2
    assert cp["ready"] is False
    nu = len(body["snapshot"]["scenario"]["units"])
    assert nu == 2
    assert body["snapshot"]["progress_state"] == prog_after_found


def test_accepted_settler_project(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    body = _scp(client, mid, project_id="produce_unit:settler")
    assert body["accepted"] is True
    assert body["snapshot"]["scenario"]["cities"][0]["current_project"]["project_id"] == "produce_unit:settler"


def test_set_city_production_event(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    _scp(client, mid, project_id="produce_unit:warrior")
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert len(ev) == 2
    prod = ev[1]
    assert prod["action_type"] == "set_city_production"
    assert prod["actor_id"] == 0
    assert prod["city_id"] == 1
    assert prod["project_id"] == "produce_unit:warrior"
    assert prod["project_progress"] == 0


def test_not_current_player(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    r = _scp(client, mid, actor_id=1)
    assert r == {"accepted": False, "reason": "not_current_player", "index": -1}


def test_city_not_owned(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    client.post(
        f"/v1/matches/{mid}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
    )
    r = _scp(client, mid, actor_id=1, project_id="produce_unit:warrior")
    assert r["reason"] == "city_not_owned_by_player"


def test_unknown_city(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    r = _scp(client, mid, city_id=99)
    assert r["reason"] == "unknown_city"


def test_unknown_city_project(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    r = _scp(client, mid, project_id="produce_unit:invalid")
    assert r["reason"] == "unknown_city_project"


def test_city_project_not_unlocked(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    ps = ProgressState.from_snapshot_dict(snap["progress_state"])
    ps._by_owner[0]["unlocked_targets"] = _normalize_unlocked_targets(
        [{"target_type": "city_project", "target_id": "produce_unit:warrior"}]
    )
    snap["progress_state"] = snapshot.serialize_progress_state(ps)
    file_store.write_snapshot(mid, snap)
    rev_before = snap["revision"]
    r = _scp(client, mid, project_id="produce_unit:settler")
    assert r["accepted"] is False
    assert r["reason"] == "city_project_not_unlocked"
    assert file_store.read_snapshot(mid)["revision"] == rev_before


def test_changing_project_resets_progress(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    _scp(client, mid, project_id="produce_unit:warrior")
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["scenario"]["cities"][0]["current_project"]["progress"] = 5
    file_store.write_snapshot(mid, snap)
    r = _scp(client, mid, project_id="produce_unit:settler")
    assert r["accepted"] is True
    assert r["snapshot"]["scenario"]["cities"][0]["current_project"]["progress"] == 0


def test_project_already_set_rejected(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    _scp(client, mid, project_id="produce_unit:warrior")
    r = _scp(client, mid, project_id="produce_unit:warrior")
    assert r["accepted"] is False
    assert r["reason"] == "project_already_set"


def test_clear_production_none(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    _scp(client, mid, project_id="produce_unit:warrior")
    r = _scp(client, mid, project_id="none")
    assert r["accepted"] is True
    assert r["snapshot"]["scenario"]["cities"][0]["current_project"] is None
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"][-1]
    assert ev["project_id"] == "none"
    assert ev["project_progress"] is None


def test_unsupported_schema_version_rejects(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    r = _scp(client, mid, schema_version=1)
    assert r["reason"] == "unsupported_schema_version"


def test_snapshot_v2_progress_preserved_after(client: TestClient) -> None:
    mid = _tiny_match_with_capital(client)
    prog_before = copy.deepcopy(
        client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    )
    _scp(client, mid)
    prog_after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    assert prog_after == prog_before
    assert client.get(f"/v1/matches/{mid}").json()["snapshot"]["schema_version"] == 2


def test_none_does_not_require_unlock(client: TestClient) -> None:
    """Clearing production must not be gated by unlock (mirrors GameState)."""
    mid = _tiny_match_with_capital(client)
    _scp(client, mid, project_id="produce_unit:warrior")
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    ps = ProgressState.from_snapshot_dict(snap["progress_state"])
    ps._by_owner[0]["unlocked_targets"] = []
    snap["progress_state"] = snapshot.serialize_progress_state(ps)
    file_store.write_snapshot(mid, snap)
    r = _scp(client, mid, project_id="none")
    assert r["accepted"] is True
