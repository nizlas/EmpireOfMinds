"""Test-only snapshot helpers for combat flow tests."""

from __future__ import annotations

from app.storage import file_store


def inject_adjacent_warriors_for_combat_tests(match_id: str) -> None:
    """P0 warrior id=2 at (1,0); P1 warrior id=3 at (1,-1) — adjacent on tiny_test."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None, match_id
    units = snap["scenario"]["units"]
    for u in units:
        if int(u["id"]) == 3:
            u["type_id"] = "warrior"
            u["position"] = [1, -1]
            u["current_hp"] = 100
            u["remaining_movement"] = 2
    file_store.write_snapshot(match_id, snap)


def inject_friendly_adjacent_warrior_defender(match_id: str) -> None:
    """Same as inject_adjacent_warriors but defender id=3 is P0-owned (cannot_attack_own_unit)."""
    inject_adjacent_warriors_for_combat_tests(match_id)
    snap = file_store.read_snapshot(match_id)
    assert snap is not None, match_id
    for u in snap["scenario"]["units"]:
        if int(u["id"]) == 3:
            u["owner_id"] = 0
    file_store.write_snapshot(match_id, snap)


def inject_distant_enemy_warrior_on_prototype_play(match_id: str) -> None:
    """P0 warrior id=2 at (1,0); P1 warrior id=3 at (9,5) — non-adjacent on prototype_play."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None, match_id
    for u in snap["scenario"]["units"]:
        if int(u["id"]) == 3:
            u["type_id"] = "warrior"
            u["current_hp"] = 100
            u["remaining_movement"] = 2
    file_store.write_snapshot(match_id, snap)
