"""Slice C10: combat_rules parity with game/domain/combat_rules.gd."""

from __future__ import annotations

from app.domain.combat_rules import damage_for_strengths, resolve_attack
from app.domain.hex_map import make_tiny_test_map
from app.domain.hex_coord import HexCoord
from app.domain.scenario import Scenario
from app.domain.unit import Unit


def _two_warrior_scenario(def_hp: int = 100) -> Scenario:
    m = make_tiny_test_map()
    w0 = Unit.make(10, 0, HexCoord(0, 0), "warrior")
    w1 = Unit.make(11, 1, HexCoord(1, 0), "warrior", current_hp=def_hp)
    return Scenario(map=m, _units=(w0, w1), _cities=(), next_unit_id=12, next_city_id=1, lightning_tree_hex=None)


def test_equal_strength_damage_is_30() -> None:
    assert damage_for_strengths(20, 20) == 30


def test_min_damage_clamp() -> None:
    assert damage_for_strengths(0, 200) == 1


def test_max_damage_clamp() -> None:
    assert damage_for_strengths(200, 0) == 100


def test_full_hp_both_retaliate() -> None:
    sc = _two_warrior_scenario()
    act = {"attacker_id": 10, "defender_id": 11}
    r = resolve_attack(sc, act)
    assert r["defender_damage_taken"] == 30
    assert r["attacker_damage_taken"] == 30
    assert r["retaliated"] is True
    assert r["attacker_killed"] is False
    assert r["defender_killed"] is False


def test_lethal_defender_no_retaliation() -> None:
    sc = _two_warrior_scenario(def_hp=20)
    r = resolve_attack(sc, {"attacker_id": 10, "defender_id": 11})
    assert r["defender_killed"] is True
    assert r["retaliated"] is False
    assert r["attacker_damage_taken"] == 0
