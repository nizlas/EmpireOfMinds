"""Scenario bundle. Parity: game/domain/scenario.gd factories used at session start."""

from __future__ import annotations

from dataclasses import dataclass

from app.domain.city import City
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap, make_tiny_test_map
from app.domain.prototype_maps import make_prototype_play_map
from app.domain.unit import Unit


@dataclass(frozen=True, slots=True)
class Scenario:
    map: HexMap
    _units: tuple[Unit, ...]
    _cities: tuple[City, ...]
    next_unit_id: int
    next_city_id: int
    lightning_tree_hex: HexCoord | None

    def peek_next_unit_id(self) -> int:
        return self.next_unit_id

    def peek_next_city_id(self) -> int:
        return self.next_city_id

    def units(self) -> tuple[Unit, ...]:
        return self._units

    def cities(self) -> tuple[City, ...]:
        return self._cities


def make_tiny_test_scenario() -> Scenario:
    m = make_tiny_test_map()
    us = (
        Unit.make(1, 0, HexCoord(0, 0), "settler"),
        Unit.make(2, 0, HexCoord(1, 0), "warrior"),
        Unit.make(3, 1, HexCoord(0, -1), "settler"),
    )
    return Scenario(
        map=m,
        _units=us,
        _cities=(),
        next_unit_id=4,
        next_city_id=1,
        lightning_tree_hex=None,
    )


def make_prototype_play_scenario() -> Scenario:
    m = make_prototype_play_map()
    us = (
        Unit.make(1, 0, HexCoord(0, 0), "settler"),
        Unit.make(2, 0, HexCoord(1, 0), "warrior"),
        Unit.make(3, 1, HexCoord(9, 5), "settler"),
    )
    return Scenario(
        map=m,
        _units=us,
        _cities=(),
        next_unit_id=4,
        next_city_id=1,
        lightning_tree_hex=HexCoord(3, 0),
    )


def scenario_for_id(scenario_id: str) -> Scenario:
    if scenario_id == "tiny_test":
        return make_tiny_test_scenario()
    if scenario_id == "prototype_play":
        return make_prototype_play_scenario()
    raise ValueError(scenario_id)
