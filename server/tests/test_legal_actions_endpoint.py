"""Slice C7: GET /v1/matches/{id}/legal-actions (read-only, submit-ready payloads)."""

from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.domain.actions import move_unit
from app.domain.snapshot import scenario_from_snapshot_dict
from app.storage import file_store
from match_helpers import create_seated_match, post_match_action



def _tiny_seated(client: TestClient) -> dict:
    return create_seated_match(client, {"scenario_id": "tiny_test"})


def _get_legal(client: TestClient, mid: str, **params: int | None) -> dict:
    q = {k: v for k, v in params.items() if v is not None}
    r = client.get(f"/v1/matches/{mid}/legal-actions", params=q)
    assert r.status_code == 200, r.text
    return r.json()


def test_summary_current_actor_includes_end_turn_and_summaries(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    before = client.get(f"/v1/matches/{mid}").json()
    rev0 = before["revision"]
    sh0 = before["state_hash"]

    g = _get_legal(client, mid, actor_id=0)
    after = client.get(f"/v1/matches/{mid}").json()

    assert after["revision"] == rev0
    assert after["state_hash"] == sh0
    assert g["is_current_player"] is True
    assert g["revision"] == rev0
    assert g["selection_error"] is None
    et = [a for a in g["actions"] if a["action_type"] == "end_turn"]
    assert len(et) == 1
    assert et[0] == {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}
    assert "unit_summaries" in g and isinstance(g["unit_summaries"], list)
    assert "city_summaries" in g and isinstance(g["city_summaries"], list)
    assert all("unit_id" in x and "legal_action_count" in x for x in g["unit_summaries"])


def test_non_current_actor_empty_actions(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    before = client.get(f"/v1/matches/{mid}").json()
    g = _get_legal(client, mid, actor_id=1)
    after = client.get(f"/v1/matches/{mid}").json()

    assert after["revision"] == before["revision"]
    assert g["is_current_player"] is False
    assert g["actions"] == []
    assert g.get("selection_error") is None


def test_selected_settler_move_actions_adjacent(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=1)
    moves = [a for a in g["actions"] if a["action_type"] == "move_unit"]
    assert g["selection_error"] is None
    assert len(moves) >= 1
    for a in moves:
        assert a["schema_version"] == 1
        assert a["actor_id"] == 0
        assert a["unit_id"] == 1
        assert a["from"] == [0, 0]
        assert len(a["to"]) == 2
        snap = file_store.read_snapshot(mid)
        assert snap is not None
        vr = move_unit.validate(scenario_from_snapshot_dict(snap["scenario"]), a)
        assert vr["ok"], vr


def test_movement_exhausted_no_move_unit(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    snap = file_store.read_snapshot(mid)
    for u in snap["scenario"]["units"]:
        if int(u["id"]) == 1:
            u["remaining_movement"] = 0
    file_store.write_snapshot(mid, snap)

    g = _get_legal(client, mid, actor_id=0, selected_unit_id=1)
    assert g["selection_error"] is None
    assert not any(a["action_type"] == "move_unit" for a in g["actions"])


def test_moves_exclude_water_destinations(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=1)
    moves = [a for a in g["actions"] if a["action_type"] == "move_unit"]
    snap = file_store.read_snapshot(mid)["scenario"]
    cells = {(int(c["q"]), int(c["r"])): c for c in snap["map"]["cells"]}
    for a in moves:
        t = tuple(a["to"])
        assert cells[t]["terrain"] != "water"


def test_moves_exclude_occupied_destinations(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=1)
    moves = [a for a in g["actions"] if a["action_type"] == "move_unit"]
    occ = {(int(u["position"][0]), int(u["position"][1])) for u in file_store.read_snapshot(mid)["scenario"]["units"]}
    for a in moves:
        assert (int(a["to"][0]), int(a["to"][1])) not in occ


def test_found_city_legal_shape(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=1)
    fc = [a for a in g["actions"] if a["action_type"] == "found_city"]
    assert len(fc) == 1
    assert fc[0] == {
        "schema_version": 1,
        "action_type": "found_city",
        "actor_id": 0,
        "unit_id": 1,
        "position": [0, 0],
    }


def test_warrior_no_found_city(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=2)
    assert g["selection_error"] is None
    assert not any(a["action_type"] == "found_city" for a in g["actions"])


def test_found_city_illegal_tile_already_owned(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    r = post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers).json()
    assert r["accepted"] is True
    post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}, headers=action_headers)
    g = _get_legal(client, mid, actor_id=1, selected_unit_id=3)
    assert g["selection_error"] is None
    assert not any(a["action_type"] == "found_city" for a in g["actions"])


def test_city_production_unlocked_projects(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    g = _get_legal(client, mid, actor_id=0, selected_city_id=1)
    assert g["selection_error"] is None
    prods = [a for a in g["actions"] if a["action_type"] == "set_city_production"]
    ids = [a["project_id"] for a in prods]
    assert "produce_unit:warrior" in ids
    assert "produce_unit:settler" in ids
    for a in prods:
        assert a["schema_version"] == 2
        assert a["actor_id"] == 0
        assert a["city_id"] == 1


def test_city_production_locked_warrior_excluded(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    snap = file_store.read_snapshot(mid)
    for row in snap["progress_state"]["by_owner"]:
        if int(row["owner_id"]) == 0:
            row["unlocked_targets"] = [
                t
                for t in row["unlocked_targets"]
                if not (
                    t.get("target_type") == "city_project"
                    and t.get("target_id") == "produce_unit:warrior"
                )
            ]
    file_store.write_snapshot(mid, snap)

    g = _get_legal(client, mid, actor_id=0, selected_city_id=1)
    ids = [a["project_id"] for a in g["actions"] if a["action_type"] == "set_city_production"]
    assert "produce_unit:warrior" not in ids
    assert "produce_unit:settler" in ids


def test_project_already_set_excluded(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers)
    g = _get_legal(client, mid, actor_id=0, selected_city_id=1)
    ids = [a["project_id"] for a in g["actions"] if a["action_type"] == "set_city_production"]
    assert "produce_unit:warrior" not in ids
    assert "produce_unit:settler" in ids
    assert "none" in ids


def test_no_current_project_no_none_option(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    g = _get_legal(client, mid, actor_id=0, selected_city_id=1)
    ids = [a["project_id"] for a in g["actions"] if a["action_type"] == "set_city_production"]
    assert "none" not in ids


def test_selected_opponent_unit_empty(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=3)
    assert g["actions"] == []
    assert g["selection_error"] == "selection_not_owned"


def test_selected_opponent_city_empty(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}, headers=action_headers)
    g = _get_legal(client, mid, actor_id=1, selected_city_id=1)
    assert g["actions"] == []
    assert g["selection_error"] == "selection_not_owned_city"


def test_unknown_unit_selection(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    g = _get_legal(client, mid, actor_id=0, selected_unit_id=99)
    assert g["actions"] == []
    assert g["selection_error"] == "unknown_unit"


def test_determinism_repeated_get(client: TestClient) -> None:
    m = _tiny_seated(client)
    mid = m["match_id"]
    action_headers = m["headers"]
    a = json.dumps(_get_legal(client, mid, actor_id=0, selected_unit_id=1), sort_keys=True)
    b = json.dumps(_get_legal(client, mid, actor_id=0, selected_unit_id=1), sort_keys=True)
    assert a == b
