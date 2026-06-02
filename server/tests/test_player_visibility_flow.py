"""Slice C12b: explored-tile memory persisted in snapshot v2 visibility_state."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain.hex_coord import HexCoord
from app.domain.player_visibility import visibility_from_snapshot_dict
from app.domain.snapshot import scenario_from_snapshot_dict
from match_helpers import create_seated_match, post_match_action



def _explored_pairs(snap: dict, owner_id: int) -> set[tuple[int, int]]:
    scenario = scenario_from_snapshot_dict(snap["scenario"])
    players: list[int] = list(snap["turn_state"]["players"])
    vis = visibility_from_snapshot_dict(snap.get("visibility_state"), scenario, players)
    return vis.get(owner_id, set())


def test_initial_snapshot_includes_visibility_state(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    snap = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert "visibility_state" in snap
    assert isinstance(snap["visibility_state"].get("by_owner"), list)
    p0 = _explored_pairs(snap, 0)
    assert len(p0) > 0


def test_move_persists_visibility_state_in_snapshot_and_get(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    action_headers = m["headers"]
    r = post_match_action(client, mid, {
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 1,
            "from": [0, 0],
            "to": [1, -1],
        }, headers=action_headers)
    assert r.json()["accepted"] is True
    vis_after = r.json()["snapshot"]["visibility_state"]
    assert vis_after is not None

    snap_reload = client.get(f"/v1/matches/{mid}").json()["snapshot"]
    assert snap_reload["visibility_state"] == vis_after


def test_recompute_accumulates_explored_beyond_prior_set() -> None:
    from app.domain import player_visibility
    from app.domain.scenario import scenario_for_id

    scenario = scenario_for_id("prototype_play")
    vis = player_visibility.empty_for_players([0, 1])
    vis[0] = {(0, 0)}
    before_len = len(vis[0])
    vis = player_visibility.recompute_for_actor(vis, scenario, 0)
    assert len(vis[0]) > before_len


def test_legacy_snapshot_without_visibility_seeds_on_read() -> None:
    snap = {
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "scenario": {
            "next_unit_id": 4,
            "next_city_id": 1,
            "lightning_tree_hex": None,
            "map": {
                "cells": [
                    {"q": 0, "r": 0, "terrain": "plains", "landform": "flat", "woods": False},
                    {"q": 1, "r": 0, "terrain": "plains", "landform": "flat", "woods": False},
                ]
            },
            "units": [
                {
                    "id": 1,
                    "owner_id": 0,
                    "position": [0, 0],
                    "type_id": "warrior",
                    "remaining_movement": 2,
                    "current_hp": 100,
                }
            ],
            "cities": [],
        },
    }
    scenario = scenario_from_snapshot_dict(snap["scenario"])
    vis = visibility_from_snapshot_dict(None, scenario, [0, 1])
    assert (0, 0) in vis[0]
