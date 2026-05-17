"""Test-only snapshot helpers for multi-owner tick tests (no FoundCity path)."""

from __future__ import annotations

from app.domain.city import WORKED_TILES_MODE_AUTO, City
from app.domain.hex_coord import HexCoord
from app.domain.snapshot import _serialize_city
from app.storage import file_store

# After P0 capital at (0,0), these are in P0's ring — free them before injecting P1 ownership.
# Two plains hexes mirror test_apply_food_growth_godot_fixtures (pair city): center food is floored to 2,
# population 1 works one extra owned tile → +1 food → surplus 3 - 2 > 0 (single-tile city => surplus 0).
P1_TICK_TEST_CITY_CENTER: tuple[int, int] = (1, -1)
P1_TICK_TEST_EXTRA_OWNED: tuple[int, int] = (0, -1)


def inject_p1_city_for_tick_tests(match_id: str) -> None:
    """Add P1 city id=2 on tiny_test without using FoundCity.

    Removes the P1 footprint hexes from P0 city 1's owned_tiles so ownership does not overlap,
    then appends a new city row and bumps next_city_id.
    """
    snap = file_store.read_snapshot(match_id)
    assert snap is not None, match_id
    scenario = snap["scenario"]
    cities = scenario["cities"]
    c0 = next(c for c in cities if int(c["id"]) == 1)

    def _is_freed_tile(t: list[int] | tuple[int, ...]) -> bool:
        pair = (int(t[0]), int(t[1]))
        return pair in {P1_TICK_TEST_CITY_CENTER, P1_TICK_TEST_EXTRA_OWNED}

    c0["owned_tiles"] = [t for t in c0["owned_tiles"] if not _is_freed_tile(t)]

    cq, cr = P1_TICK_TEST_CITY_CENTER
    eq, er = P1_TICK_TEST_EXTRA_OWNED
    p1_city = City(
        id=2,
        owner_id=1,
        position=HexCoord(cq, cr),
        current_project=None,
        city_name="TickTest-P1",
        is_capital=True,
        building_ids=("palace",),
        owned_tiles=(HexCoord(cq, cr), HexCoord(eq, er)),
        population=1,
        manual_worked_tiles=(),
        food_stored=0,
        worked_tiles_mode=WORKED_TILES_MODE_AUTO,
    )
    cities.append(_serialize_city(p1_city))
    cities.sort(key=lambda c: int(c["id"]))
    max_city_id = max(int(c["id"]) for c in cities)
    scenario["next_city_id"] = max_city_id + 1
    file_store.write_snapshot(match_id, snap)
