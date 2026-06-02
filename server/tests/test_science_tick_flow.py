"""Slice C6: ScienceTick on end_turn."""

from __future__ import annotations

import copy

from fastapi.testclient import TestClient

from app.domain.content import progress_definitions as pd
from app.domain.science_tick_rules import apply_science_tick_for_player
from app.domain.scenario import make_tiny_test_scenario
from app.storage import file_store
from match_helpers import create_seated_match, post_match_action



def _tiny_founded(client: TestClient) -> tuple[str, dict[str, str]]:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    hdr = m["headers"]
    post_match_action(
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
    )
    return mid, hdr


def _end(client: TestClient, mid: str, actor_id: int, headers: dict[str, str]) -> dict:
    return post_match_action(
        client,
        mid,
        {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id},
        headers=headers,
    ).json()


def test_apply_science_delta_zero_no_events() -> None:
    """No cities -> science_for_player 0 -> no rows (target id still resolved)."""
    from app.domain.progress_state import ProgressState

    sc = make_tiny_test_scenario()
    ps = ProgressState.with_default_unlocks_for_players([0, 1])
    p2, ev = apply_science_tick_for_player(ps, sc, 0)
    assert p2 is ps
    assert ev == []


def test_science_no_target_when_all_completed(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    all_sci = [x for x in pd.ids() if pd.is_science(x)]
    snap["progress_state"]["by_owner"][0]["completed_progress_ids"] = all_sci
    file_store.write_snapshot(mid, snap)
    _end(client, mid, 0, action_headers)
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert any(e["action_type"] == "science_no_target" for e in ev)


def test_science_accumulates_controlled_fire(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    _end(client, mid, 0, action_headers)
    ps = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    row0 = next(r for r in ps["by_owner"] if r["owner_id"] == 0)
    assert row0["science_progress"]["controlled_fire"] == 1


def test_rejected_end_turn_progress_unchanged(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    before = copy.deepcopy(client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"])
    r = post_match_action(client, mid, {"schema_version": 1, "action_type": "end_turn", "actor_id": 1}, headers=action_headers).json()
    assert r["accepted"] is False
    after = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    assert after == before


def test_controlled_fire_completion_unlocks(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["progress_state"]["by_owner"][0]["science_progress"] = {"controlled_fire": 5}
    file_store.write_snapshot(mid, snap)
    _end(client, mid, 0, action_headers)
    ps = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    row0 = next(r for r in ps["by_owner"] if r["owner_id"] == 0)
    assert "controlled_fire" in row0["completed_progress_ids"]
    ut = {(t["target_type"], t["target_id"]) for t in row0["unlocked_targets"]}
    assert ("building", "hearth") in ut
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"]
    assert any(e["action_type"] == "science_completed" for e in ev)
    sc_ev = next(e for e in ev if e["action_type"] == "science_completed")
    assert sc_ev["progress_id"] == "controlled_fire"
    assert isinstance(sc_ev["unlocked_targets"], list)
    assert len(sc_ev["unlocked_targets"]) >= 1


def test_engine_order_includes_science_before_end_turn(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    post_match_action(client, mid, {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        }, headers=action_headers)
    _end(client, mid, 0, action_headers)
    kinds = [e["action_type"] for e in client.get(f"/v1/matches/{mid}/events").json()["events"]]
    i_pp = kinds.index("production_progress")
    i_fg = kinds.index("food_growth_progress")
    i_sc = kinds.index("science_progress")
    i_et = kinds.index("end_turn")
    assert i_pp < i_fg < i_sc < i_et


def test_snapshot_schema_v2_after_science(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    _end(client, mid, 0, action_headers)
    assert client.get(f"/v1/matches/{mid}").json()["snapshot"]["schema_version"] == 2


def test_deterministic_state_hash_science(client: TestClient) -> None:
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


def test_current_research_respected_when_available(client: TestClient) -> None:
    mid, action_headers = _tiny_founded(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    snap["progress_state"]["by_owner"][0]["current_research_id"] = "foraging_systems"
    file_store.write_snapshot(mid, snap)
    _end(client, mid, 0, action_headers)
    ps = client.get(f"/v1/matches/{mid}").json()["snapshot"]["progress_state"]
    row0 = next(r for r in ps["by_owner"] if r["owner_id"] == 0)
    assert row0["science_progress"].get("foraging_systems", 0) >= 1
    assert row0["science_progress"].get("controlled_fire", 0) == 0
