"""Unit tests for player_visibility (explored-tile memory)."""

from __future__ import annotations

from app.domain import player_visibility
from app.domain.scenario import scenario_for_id


def test_seed_and_serialize_round_trip() -> None:
    scenario = scenario_for_id("tiny_test")
    vis = player_visibility.empty_for_players([0, 1])
    vis = player_visibility.seed_all_players(vis, scenario, [0, 1])
    raw = player_visibility.serialize_visibility(vis)
    loaded = player_visibility.visibility_from_snapshot_dict(raw, scenario, [0, 1])
    assert loaded[0] == vis[0]
    assert loaded[1] == vis[1]
