"""Slice C2: server found_city parity with Godot."""

from __future__ import annotations

import copy

from fastapi.testclient import TestClient

from app.domain.actions import found_city
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap, Terrain
from app.domain.scenario import Scenario
from app.domain.unit import Unit
from match_helpers import create_seated_match, post_match_action



def _post_fc(
    client: TestClient,
    mid: str,
    headers: dict[str, str],
    *,
    actor_id: int = 0,
    unit_id: int = 1,
    position: list[int] | None = None,
) -> dict:
    if position is None:
        position = [0, 0]
    return post_match_action(
        client,
        mid,
        {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": actor_id,
            "unit_id": unit_id,
            "position": position,
        },
        headers=headers,
    ).json()


def test_accepted_found_city_tiny_test(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    g0 = client.get(f"/v1/matches/{mid}").json()
    h0 = g0["state_hash"]
    body = _post_fc(client, mid, action_headers)
    assert body["accepted"] is True
    assert body["revision"] == 1
    assert body["state_hash"] != h0
    snap = body["snapshot"]
    assert snap["schema_version"] == 2
    assert len(snap["scenario"]["cities"]) == 1
    c0 = snap["scenario"]["cities"][0]
    assert c0["id"] == 1
    assert c0["position"] == [0, 0]
    assert c0["city_name"] == "Capital"
    assert c0["is_capital"] is True
    assert "palace" in c0["building_ids"]
    assert c0["population"] == 1
    assert c0["food_stored"] == 0
    assert c0["worked_tiles_mode"] == "auto"
    assert c0["current_project"] is None
    assert snap["scenario"]["next_city_id"] == 2
    ids = [u["id"] for u in snap["scenario"]["units"]]
    assert 1 not in ids
    assert set(ids) == {2, 3}


def test_found_city_event_shape(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    _post_fc(client, mid, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert len(ev) == 1
    e = ev[0]
    assert e["action_type"] == "found_city"
    assert e["actor_id"] == 0
    assert e["unit_id"] == 1
    assert e["city_id"] == 1
    assert e["city_name"] == "Capital"
    assert e["at"] == [0, 0]
    assert e["settler_consumed"] is True


def test_found_city_not_current_player(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = _post_fc(client, mid, action_headers, actor_id=1, unit_id=3, position=[0, -1])
    assert r == {"accepted": False, "reason": "not_current_player", "index": -1}


def test_found_city_unit_not_owned_by_player(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = _post_fc(client, mid, action_headers, unit_id=3, position=[0, -1])
    assert r["accepted"] is False
    assert r["reason"] == "unit_not_owned_by_player"
    assert r["index"] == -1


def test_found_city_warrior_cannot_found(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = _post_fc(client, mid, action_headers, unit_id=2, position=[1, 0])
    assert r["reason"] == "unit_cannot_found_city"


def test_found_city_unknown_unit(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = _post_fc(client, mid, action_headers, unit_id=99, position=[0, 0])
    assert r["reason"] == "unknown_unit"


def test_found_city_unit_not_at_position(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = _post_fc(client, mid, action_headers, position=[1, 0])
    assert r["reason"] == "unit_not_at_position"
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap["revision"] == 0


def test_found_city_tile_already_has_city(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    _post_fc(client, mid, action_headers)
    post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}, headers=action_headers)
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 1,
            "unit_id": 3,
            "from": [0, -1],
            "to": [0, 0],
        }, headers=action_headers)
    rev_before = client.get(f"/v1/matches/{mid}").json()["snapshot"]["revision"]
    r = _post_fc(client, mid, action_headers, actor_id=1, unit_id=3, position=[0, 0])
    assert r["accepted"] is False
    assert r["reason"] == "tile_already_has_city"
    assert r["index"] == -1
    assert client.get(f"/v1/matches/{mid}").json()["snapshot"]["revision"] == rev_before


def test_found_city_tile_already_owned(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    _post_fc(client, mid, action_headers)
    post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}, headers=action_headers)
    r = _post_fc(client, mid, action_headers, actor_id=1, unit_id=3, position=[0, -1])
    assert r["accepted"] is False
    assert r["reason"] == "tile_already_owned"


def test_found_city_tile_is_water_domain() -> None:
    m = HexMap({(0, 0): Terrain.WATER})
    u = Unit.make(1, 0, HexCoord(0, 0), "settler", 2, 100)
    sc = Scenario(m, (u,), (), 4, 1, None)
    act = {
        "schema_version": 1,
        "action_type": "found_city",
        "actor_id": 0,
        "unit_id": 1,
        "position": [0, 0],
    }
    vr = found_city.validate(sc, act)
    assert vr["ok"] is False
    assert vr["reason"] == "tile_is_water"


def test_found_city_progress_unchanged(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    prog = copy.deepcopy(client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"])
    _post_fc(client, mid, action_headers)
    after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    assert after == prog
