from __future__ import annotations

from app.domain.hex_coord import HexCoord
from app.domain.scenario import make_prototype_play_scenario, make_tiny_test_scenario


def test_make_tiny_test_scenario_units() -> None:
    s = make_tiny_test_scenario()
    us = sorted(s.units(), key=lambda u: u.id)
    assert [u.id for u in us] == [1, 2, 3]
    assert [u.owner_id for u in us] == [0, 0, 1]
    assert [u.type_id for u in us] == ["settler", "warrior", "settler"]
    assert us[0].position == HexCoord(0, 0)
    assert us[1].position == HexCoord(1, 0)
    assert us[2].position == HexCoord(0, -1)
    assert s.lightning_tree_hex is None
    assert s.peek_next_unit_id() == 4
    assert s.peek_next_city_id() == 1


def test_make_prototype_play_scenario_units() -> None:
    s = make_prototype_play_scenario()
    us = sorted(s.units(), key=lambda u: u.id)
    assert us[2].position == HexCoord(9, 5)
    assert s.lightning_tree_hex == HexCoord(3, 0)
    assert s.peek_next_unit_id() == 4
    assert s.peek_next_city_id() == 1
