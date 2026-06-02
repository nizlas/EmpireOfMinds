"""Slice C5: food growth on end_turn (Godot FoodGrowthTick ordering)."""

from __future__ import annotations

import copy
import json

from fastapi.testclient import TestClient

from app.domain.city import City, WORKED_TILES_MODE_AUTO
from app.domain.city_yields import city_total_yield, get_yield
from app.domain.food_growth_rules import (
    EVENT_TYPE_GREW,
    EVENT_TYPE_PROGRESS,
    apply_food_growth_for_player,
    growth_threshold,
)
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import make_tiny_test_map
from app.domain.scenario import Scenario
from app.domain import snapshot as snapshot_mod
from app.storage import file_store

from tick_test_helpers import inject_p1_city_for_tick_tests
from match_helpers import create_seated_match, post_match_action



def _tiny_founded(client: TestClient) -> tuple[str, dict[str, str]]:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    hdr = m["headers"]
    r_f = post_match_action(
        client,
        mid,
        {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        },
        headers=hdr,
    ).json()
    assert r_f.get("accepted") is True, json.dumps(r_f)
    return mid, hdr


def _end(client: TestClient, mid: str, actor_id: int, headers: dict[str, str]) -> dict:
    return post_match_action(
        client,
        mid,
        {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id},
        headers=headers,
    ).json()


def test_growth_threshold_matches_godot() -> None:
    assert growth_threshold(1) == 15
    assert growth_threshold(2) == 24
    assert growth_threshold(3) == 33
    assert growth_threshold(4) == 44


def test_apply_food_growth_godot_fixtures() -> None:
    """Port of game/domain/tests/test_food_growth_tick.gd core cases."""

    def _proj() -> dict:
        return {
            "project_type": "produce_unit",
            "project_id": "produce_unit:warrior",
            "progress": 0,
            "cost": 10,
            "ready": False,
        }

    m0 = make_tiny_test_map()
    own1 = (HexCoord(0, 0), HexCoord(1, 0))
    cx = City(
        id=1,
        owner_id=0,
        position=HexCoord(0, 0),
        current_project=_proj(),
        city_name="X",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=own1,
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc0 = Scenario(m0, (), (cx,), 5, 9, None)
    r0, ev0 = apply_food_growth_for_player(sc0, 0)
    assert r0 is not sc0
    assert len(ev0) == 1
    assert ev0[0]["action_type"] == EVENT_TYPE_PROGRESS
    assert ev0[0]["food_stored_after"] == 1
    c_after = r0.city_by_id(1)
    assert c_after is not None
    assert c_after.population == 1
    assert c_after.food_stored == 1

    m1 = make_tiny_test_map()
    c_g = City(
        id=3,
        owner_id=0,
        position=HexCoord(0, 0),
        current_project=_proj(),
        city_name="G",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=own1,
        population=1,
        manual_worked_tiles=(),
        food_stored=14,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc1 = Scenario(m1, (), (c_g,), 5, 10, None)
    r1, ev1 = apply_food_growth_for_player(sc1, 0)
    assert len(ev1) == 2
    assert ev1[0]["action_type"] == EVENT_TYPE_PROGRESS
    assert ev1[1]["action_type"] == EVENT_TYPE_GREW
    c_g2 = r1.city_by_id(3)
    assert c_g2 is not None
    assert c_g2.population == 2
    assert c_g2.food_stored == 0

    m2 = make_tiny_test_map()
    c_rem = City(
        id=4,
        owner_id=0,
        position=HexCoord(0, 0),
        current_project=_proj(),
        city_name="R",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=own1,
        population=1,
        manual_worked_tiles=(),
        food_stored=15,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc2 = Scenario(m2, (), (c_rem,), 5, 11, None)
    r2, _ev2 = apply_food_growth_for_player(sc2, 0)
    c_rem_after = r2.city_by_id(4)
    assert c_rem_after is not None
    assert c_rem_after.population == 2
    assert c_rem_after.food_stored == 1

    m3 = make_tiny_test_map()
    o_center = (HexCoord(1, -1),)
    c_starve = City(
        id=8,
        owner_id=0,
        position=HexCoord(1, -1),
        current_project=None,
        city_name="",
        is_capital=False,
        building_ids=(),
        owned_tiles=o_center,
        population=1,
        manual_worked_tiles=(),
        food_stored=5,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc3 = Scenario(m3, (), (c_starve,), 5, 20, None)
    r3, ev3 = apply_food_growth_for_player(sc3, 0)
    assert ev3 == []
    assert r3 is sc3
    assert r3.city_by_id(8).food_stored == 5

    m4 = make_tiny_test_map()
    o2 = (HexCoord(1, -1), HexCoord(0, -1))
    c2 = City(
        id=2,
        owner_id=0,
        position=HexCoord(1, -1),
        current_project=_proj(),
        city_name="B",
        is_capital=False,
        building_ids=("palace",),
        owned_tiles=o2,
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    c1 = City(
        id=1,
        owner_id=0,
        position=HexCoord(0, 0),
        current_project=_proj(),
        city_name="A",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=own1,
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc_pair = Scenario(m4, (), (c2, c1), 5, 9, None)
    _rp, evp = apply_food_growth_for_player(sc_pair, 0)
    assert len(evp) == 2
    assert evp[0]["city_id"] == 1
    assert evp[1]["city_id"] == 2


def test_end_turn_food_only_for_ending_player(client: TestClient) -> None:
    """FoodGrowthTick runs only for the ending player; the other owner's city is unchanged."""
    mid, action_headers = _tiny_founded(client)
    fs0 = client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0]["food_stored"]
    r_e0 = _end(client, mid, 0, action_headers)
    assert r_e0.get("accepted") is True, json.dumps(r_e0)
    snap0 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    by0 = {c["id"]: c for c in snap0["scenario"]["cities"]}
    assert len(by0) == 1
    assert by0[1]["food_stored"] > fs0, "P0 ending turn should tick P0 city's food only"

    inject_p1_city_for_tick_tests(mid)
    snap1 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    by_m = {c["id"]: c for c in snap1["scenario"]["cities"]}
    assert by_m[2]["food_stored"] == 0, "P1 city should start with no food stored"
    fs1 = by_m[1]["food_stored"]

    sc_pre = snapshot_mod.scenario_from_snapshot_dict(snap1["scenario"])
    city2 = sc_pre.city_by_id(2)
    assert city2 is not None
    y2 = city_total_yield(sc_pre, city2)
    total_food = int(get_yield(y2, "food"))
    pop2 = int(city2.population)
    surplus_pre = total_food - 2 * pop2
    assert surplus_pre > 0, json.dumps(
        {
            "city_id": 2,
            "total_food": total_food,
            "population": pop2,
            "surplus": surplus_pre,
            "position": [city2.position.q, city2.position.r],
            "owned_tiles": [[h.q, h.r] for h in city2.owned_tiles],
            "worked_tiles_mode": city2.worked_tiles_mode,
            "yield": y2,
        }
    )
    r_e1 = _end(client, mid, 1, action_headers)
    assert r_e1.get("accepted") is True, json.dumps(r_e1)
    snap2 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    by2 = {c["id"]: c for c in snap2["scenario"]["cities"]}
    assert by2[1]["food_stored"] == fs1, "P0 city's food must not change when P1 ends turn"
    assert by2[2]["food_stored"] > 0, "P1 ending turn should tick P1 city's food only"


def test_food_growth_independent_of_current_project(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers)
    fb = client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0]["food_stored"]
    body = _end(client, mid, 0, action_headers)
    assert body["accepted"] is True
    c = body["snapshot"]["scenario"]["cities"][0]
    assert c["current_project"]["progress"] > 0
    assert c["food_stored"] > fb


def test_end_turn_no_food_event_when_surplus_not_positive(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["scenario"]["cities"][0]["population"] = 50
    file_store.write_snapshot(mid, snap)
    _end(client, mid, 0, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert not any(e["action_type"] == EVENT_TYPE_PROGRESS for e in ev)


def test_city_grew_via_end_turn(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["scenario"]["cities"][0]["food_stored"] = 14
    file_store.write_snapshot(mid, snap)

    from app.domain import snapshot as snap_mod
    from app.domain.city_yields import city_total_yield, get_yield
    from app.domain.food_growth_rules import growth_threshold

    sc = snap_mod.scenario_from_snapshot_dict(snap["scenario"])
    city = sc.city_by_id(1)
    assert city is not None
    total_food = get_yield(city_total_yield(sc, city), "food")
    surplus = int(total_food) - int(city.population) * 2
    assert surplus > 0
    thr = growth_threshold(int(city.population))
    new_stored = 14 + surplus
    exp_pop = int(city.population) + 1 if new_stored >= thr else int(city.population)
    exp_food = new_stored - thr if new_stored >= thr else new_stored

    _end(client, mid, 0, action_headers)
    c = client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0]
    assert c["population"] == exp_pop
    assert c["food_stored"] == exp_food
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    if exp_pop > int(city.population):
        assert any(e["action_type"] == EVENT_TYPE_GREW for e in ev)


def test_rejected_end_turn_no_food_change(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    sh = client.get(f"/v1/matches/{mid}").json()["state_hash"]
    r = post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 1}, headers=action_headers).json()
    assert r["accepted"] is False
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap["scenario"]["cities"][0]["food_stored"] == 0
    assert client.get(f"/v1/matches/{mid}").json()["state_hash"] == sh


def test_engine_event_order_production_then_food_then_end_turn(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers)
    _end(client, mid, 0, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    kinds = [e["action_type"] for e in ev]
    i_pp = kinds.index("production_progress")
    i_fg = kinds.index("food_growth_progress")
    i_sc = kinds.index("science_progress")
    i_et = kinds.index("end_turn")
    assert i_pp < i_fg < i_sc < i_et


def test_delivery_and_movement_still_after_advance(client: TestClient) -> None:
    """Regression: C4 delivery for new current player after end_turn row."""
    mid, action_headers = _tiny_founded(client)
    post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers)
    _end(client, mid, 0, action_headers)
    _end(client, mid, 1, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    kinds = [e["action_type"] for e in ev]
    assert "unit_produced" in kinds
    last_et = max(i for i, k in enumerate(kinds) if k == "end_turn")
    up_idx = kinds.index("unit_produced")
    assert up_idx > last_et


def test_progress_state_includes_science_after_end_turn(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    before = copy.deepcopy(client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"])
    _end(client, mid, 0, action_headers)
    after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    assert after != before
    row0 = next(r for r in after["by_owner"] if r["owner_id"] == 0)
    assert int(row0["science_progress"].get("controlled_fire", 0)) >= 1


def test_identical_setup_identical_state_hash(client: TestClient) -> None:
    from app.domain.state_hash import state_hash

    def _world_fp(mid: str) -> str:
        snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
        return state_hash({k: v for k, v in snap.items() if k != "match_id"})

    hashes: list[str] = []
    for _ in range(2):
        mid, action_headers = _tiny_founded(client)
        _end(client, mid, 0, action_headers)
        hashes.append(_world_fp(mid))
    assert hashes[0] == hashes[1]

