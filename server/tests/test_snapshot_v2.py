from __future__ import annotations

import json
from pathlib import Path

from app.domain.snapshot import build_initial_snapshot
from app.domain.state_hash import state_hash

_GOLDEN = Path(__file__).resolve().parent / "golden" / "initial_snapshot_tiny_test_v2.json"


def test_build_initial_snapshot_tiny_matches_golden() -> None:
    expected = json.loads(_GOLDEN.read_text(encoding="utf-8"))
    got = build_initial_snapshot("m_golden_tiny_fixture", [0, 1], "tiny_test")
    assert got == expected


def test_schema_version_and_unlocks() -> None:
    snap = build_initial_snapshot("m_x", [0, 1], "prototype_play")
    assert snap["schema_version"] == 2
    assert snap["scenario_id"] == "prototype_play"
    owners = snap["progress_state"]["by_owner"]
    assert [row["owner_id"] for row in owners] == [0, 1]
    for row in owners:
        ids = [t["target_id"] for t in row["unlocked_targets"]]
        assert "produce_unit:warrior" in ids
        assert "produce_unit:settler" in ids


def test_state_hash_stable_and_differs_by_scenario() -> None:
    a = build_initial_snapshot("m_same", [0, 1], "tiny_test")
    b = build_initial_snapshot("m_same", [0, 1], "tiny_test")
    assert state_hash(a) == state_hash(b)
    c = build_initial_snapshot("m_same", [0, 1], "prototype_play")
    assert state_hash(c) != state_hash(a)
