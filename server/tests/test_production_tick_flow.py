"""Slice C4: production tick + delivery on end_turn (Godot ordering)."""

from __future__ import annotations

import copy
import json

from fastapi.testclient import TestClient

from app.domain.city import City, WORKED_TILES_MODE_AUTO
from app.domain.content import unit_definitions
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import make_tiny_test_map
from app.domain.production_rules import apply_production_tick_for_player
from app.domain.scenario import Scenario
from app.storage import file_store

from tick_test_helpers import inject_p1_city_for_tick_tests
from match_helpers import create_seated_match, post_match_action



def _tiny_capital_warrior_project(client: TestClient) -> tuple[str, dict[str, str]]:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    hdr = m["headers"]
    r1 = post_match_action(
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
    assert r1.get("accepted") is True, json.dumps(r1)
    r2 = post_match_action(
        client,
        mid,
        {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        },
        headers=hdr,
    ).json()
    assert r2.get("accepted") is True, json.dumps(r2)
    return mid, hdr


def _end(client: TestClient, mid: str, actor_id: int, headers: dict[str, str]) -> dict:
    return post_match_action(
        client,
        mid,
        {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id},
        headers=headers,
    ).json()


def test_tick_only_for_ending_player_not_other_city(client: TestClient) -> None:
    """Production tick runs for the player who ended; other owners' cities do not tick.

    Use a high production cost so one P0 tick does not mark the project ready; otherwise
    when P1 ends and P0 becomes current again, C4 ProductionDelivery would clear P0's project.
    """
    mid, action_headers = _tiny_capital_warrior_project(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["scenario"]["cities"][0]["current_project"]["cost"] = 100
    file_store.write_snapshot(mid, snap)

    r_e0 = _end(client, mid, 0, action_headers)
    assert r_e0.get("accepted") is True, json.dumps(r_e0)
    inject_p1_city_for_tick_tests(mid)
    r_scp = post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 1,
            "city_id": 2,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers).json()
    assert r_scp.get("accepted") is True, json.dumps(r_scp)
    p0_prog = client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0][
        "current_project"
    ]["progress"]
    r_e1 = _end(client, mid, 1, action_headers)
    assert r_e1.get("accepted") is True, json.dumps(r_e1)
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    c_by_id = {c["id"]: c for c in snap["scenario"]["cities"]}
    assert c_by_id[1]["current_project"]["progress"] == p0_prog
    assert c_by_id[2]["current_project"]["progress"] > 0


def test_city_without_project_unchanged_on_end_turn(client: TestClient) -> None:
    """No production tick without current_project; food growth may still apply (Slice C5)."""
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "found_city",
            "actor_id": 0,
            "unit_id": 1,
            "position": [0, 0],
        }, headers=action_headers)
    before = copy.deepcopy(client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0])
    body = _end(client, mid, 0, action_headers)
    assert body["accepted"] is True
    after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["scenario"]["cities"][0]
    assert after["current_project"] is None and before["current_project"] is None
    assert after["food_stored"] > before["food_stored"]


def test_partial_progress_no_unit_no_ready(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["scenario"]["cities"][0]["current_project"]["cost"] = 100
    file_store.write_snapshot(mid, snap)
    nu_before = snap["scenario"]["next_unit_id"]
    body = _end(client, mid, 0, action_headers)
    assert body["accepted"] is True
    c = body["snapshot"]["scenario"]["cities"][0]
    assert c["current_project"]["ready"] is False
    assert 0 < c["current_project"]["progress"] < 100
    assert body["snapshot"]["scenario"]["next_unit_id"] == nu_before
    assert len(body["snapshot"]["scenario"]["units"]) == 2


def test_completion_warrior_delivery_next_current_player_turn(client: TestClient) -> None:
    """Godot: tick makes ready; deliver when that owner becomes current again."""
    mid, action_headers = _tiny_capital_warrior_project(client)
    snap0 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    nu = snap0["scenario"]["next_unit_id"]
    city_pos = snap0["scenario"]["cities"][0]["position"]
    assert snap0["scenario"]["cities"][0]["current_project"]["cost"] == 2

    _end(client, mid, 0, action_headers)
    snap1 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap1["scenario"]["cities"][0]["current_project"]["ready"] is True

    _end(client, mid, 1, action_headers)
    snap2 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap2["scenario"]["cities"][0]["current_project"] is None
    units = {u["id"]: u for u in snap2["scenario"]["units"]}
    assert nu in units
    w = units[nu]
    assert w["type_id"] == "warrior"
    assert w["owner_id"] == 0
    assert w["position"] == city_pos
    assert w["remaining_movement"] == unit_definitions.max_movement_for_type("warrior")
    assert snap2["scenario"]["next_unit_id"] == nu + 1


def test_completion_settler(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
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
            "project_id": "produce_unit:settler",
        }, headers=action_headers)
    snap0 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    nu = snap0["scenario"]["next_unit_id"]
    city_pos = snap0["scenario"]["cities"][0]["position"]
    _end(client, mid, 0, action_headers)
    _end(client, mid, 1, action_headers)
    snap2 = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    w = next(u for u in snap2["scenario"]["units"] if u["id"] == nu)
    assert w["type_id"] == "settler"
    assert w["position"] == city_pos
    assert w["remaining_movement"] == unit_definitions.max_movement_for_type("settler")


def test_end_turn_events_order_progress_then_end_turn_then_delivery(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    _end(client, mid, 0, action_headers)
    _end(client, mid, 1, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    kinds = [e["action_type"] for e in ev]
    assert kinds[:2] == ["found_city", "set_city_production"]
    assert kinds[2] == "production_progress"
    assert kinds[3] == "food_growth_progress"
    assert kinds[4] == "science_progress"
    assert kinds[5] == "end_turn"
    assert kinds[6] == "end_turn"
    assert kinds[7] == "unit_produced"

    pp = ev[2]
    assert pp["city_id"] == 1
    assert pp["progress_before"] == 0
    assert "project_id" in pp
    assert pp["source"] == "engine"

    up = ev[7]
    assert up["action_type"] == "unit_produced"
    assert up["unit_type_id"] == "warrior"
    assert up["city_id"] == 1
    assert "project_id" in up


def test_movement_refresh_includes_new_unit_and_not_ending_player(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    _ = post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 2,
            "from": [1, 0],
            "to": [1, -1],
        }, headers=action_headers).json()
    _end(client, mid, 0, action_headers)
    snap_m = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    w2 = next(u for u in snap_m["scenario"]["units"] if u["id"] == 2)
    assert w2["remaining_movement"] < unit_definitions.max_movement_for_type("warrior")
    _end(client, mid, 1, action_headers)
    final = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    w2b = next(u for u in final["scenario"]["units"] if u["id"] == 2)
    assert w2b["remaining_movement"] == unit_definitions.max_movement_for_type("warrior")
    nu = 4
    new_u = next(u for u in final["scenario"]["units"] if u["id"] == nu)
    assert new_u["remaining_movement"] == unit_definitions.max_movement_for_type("warrior")


def test_progress_state_accumulates_science_after_end_turn(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    _end(client, mid, 0, action_headers)
    ps = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    row0 = next(r for r in ps["by_owner"] if r["owner_id"] == 0)
    assert int(row0["science_progress"].get("controlled_fire", 0)) >= 1


def test_rejected_end_turn_leaves_production_unchanged(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    sh0 = client.get(f"/v1/matches/{mid}").json()["state_hash"]
    r = post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 1}, headers=action_headers).json()
    assert r == {"accepted": False, "reason": "not_current_player", "index": -1}
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap["scenario"]["cities"][0]["current_project"]["progress"] == 0
    assert client.get(f"/v1/matches/{mid}").json()["state_hash"] == sh0


def test_production_tick_events_sorted_by_city_id() -> None:
    """Regression: multiple cities tick in ascending city_id order (Godot / stable log)."""

    def _proj() -> dict:
        return {
            "project_type": "produce_unit",
            "project_id": "produce_unit:warrior",
            "progress": 0,
            "cost": 50,
            "ready": False,
        }

    m = make_tiny_test_map()
    c5 = City(
        id=5,
        owner_id=0,
        position=HexCoord(1, -1),
        current_project=_proj(),
        city_name="B",
        is_capital=False,
        building_ids=(),
        owned_tiles=(HexCoord(1, -1),),
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    c3 = City(
        id=3,
        owner_id=0,
        position=HexCoord(0, 0),
        current_project=_proj(),
        city_name="A",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=(HexCoord(0, 0),),
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    sc = Scenario(m, (), (c5, c3), 4, 6, None)
    _, events = apply_production_tick_for_player(sc, 0)
    assert [e["city_id"] for e in events] == [3, 5]


def test_deterministic_snapshot_hash_repeatable(client: TestClient) -> None:
    from app.domain.state_hash import state_hash

    def _world_fp(m: str) -> str:
        snap = client.get(f"/v1/matches/{m}").json()["snapshot"]
        return state_hash({k: v for k, v in snap.items() if k != "match_id"})

    hashes: list[str] = []
    for _ in range(2):
        mid, action_headers = _tiny_capital_warrior_project(client)
        _end(client, mid, 0, action_headers)
        _end(client, mid, 1, action_headers)
        hashes.append(_world_fp(mid))
    assert hashes[0] == hashes[1]


def test_end_turn_response_index_points_at_end_turn_event(client: TestClient) -> None:
    mid, action_headers = _tiny_capital_warrior_project(client)
    body = _end(client, mid, 0, action_headers)
    assert body["accepted"] is True
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    end_row = next(e for e in ev if e["index"] == body["index"])
    assert end_row["action_type"] == "end_turn"
