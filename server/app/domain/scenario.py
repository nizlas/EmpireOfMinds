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

    def unit_by_id(self, unit_id: int) -> Unit | None:
        for u in self._units:
            if u.id == unit_id:
                return u
        return None

    def units_at(self, coord: HexCoord) -> tuple[Unit, ...]:
        return tuple(u for u in self._units if u.position == coord)

    def with_units(self, units: tuple[Unit, ...]) -> Scenario:
        return Scenario(
            map=self.map,
            _units=units,
            _cities=self._cities,
            next_unit_id=self.next_unit_id,
            next_city_id=self.next_city_id,
            lightning_tree_hex=self.lightning_tree_hex,
        )

    def city_by_id(self, city_id: int) -> City | None:
        for c in self._cities:
            if c.id == city_id:
                return c
        return None

    def cities_at(self, coord: HexCoord) -> tuple[City, ...]:
        return tuple(c for c in self._cities if c.position == coord)

    def cities_owned_by(self, owner_id: int) -> tuple[City, ...]:
        return tuple(c for c in self._cities if c.owner_id == owner_id)

    def tile_is_owned(self, coord: HexCoord) -> bool:
        for c in self._cities:
            for ot in c.owned_tiles:
                if ot == coord:
                    return True
        return False

    def with_cities(self, cities: tuple[City, ...]) -> Scenario:
        return Scenario(
            map=self.map,
            _units=self._units,
            _cities=cities,
            next_unit_id=self.next_unit_id,
            next_city_id=self.next_city_id,
            lightning_tree_hex=self.lightning_tree_hex,
        )


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
