"""City yield vectors. Parity: game/domain/city_yields.gd (production tick input)."""

from __future__ import annotations

from functools import cmp_to_key

from app.domain.city import WORKED_TILES_MODE_MANUAL, City
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap, Landform, Terrain
from app.domain.scenario import Scenario

BUILDING_ID_PALACE = "palace"


def empty() -> dict[str, int]:
    return {"food": 0, "production": 0, "science": 0, "coin": 0}


def get_yield(y: dict[str, int] | None, key: str) -> int:
    if y is None:
        return 0
    return int(y.get(key, 0))


def add(a: dict[str, int], b: dict[str, int]) -> dict[str, int]:
    return {
        "food": get_yield(a, "food") + get_yield(b, "food"),
        "production": get_yield(a, "production") + get_yield(b, "production"),
        "science": get_yield(a, "science") + get_yield(b, "science"),
        "coin": get_yield(a, "coin") + get_yield(b, "coin"),
    }


def raw_terrain_yield(hmap: HexMap, coord: HexCoord) -> dict[str, int]:
    if not hmap.has(coord):
        return empty()
    terr = hmap.terrain_at(coord)
    if terr == Terrain.WATER:
        return empty()
    woods = hmap.has_woods(coord)
    if woods:
        if terr == Terrain.GRASSLAND:
            return {"food": 1, "production": 1, "science": 0, "coin": 0}
        if terr == Terrain.PLAINS:
            return {"food": 1, "production": 2, "science": 0, "coin": 0}
        return empty()
    lf = hmap.landform_at(coord)
    hills = lf == Landform.HILLS
    if terr == Terrain.GRASSLAND:
        if hills:
            return {"food": 1, "production": 1, "science": 0, "coin": 0}
        return {"food": 2, "production": 0, "science": 0, "coin": 0}
    if terr == Terrain.PLAINS:
        if hills:
            return {"food": 0, "production": 2, "science": 0, "coin": 0}
        return {"food": 1, "production": 1, "science": 0, "coin": 0}
    return empty()


def city_center_yield(hmap: HexMap, city: City) -> dict[str, int]:
    raw = raw_terrain_yield(hmap, city.position)
    f = max(get_yield(raw, "food"), 2)
    p = max(get_yield(raw, "production"), 1)
    return {"food": f, "production": p, "science": 0, "coin": 0}


def palace_yield() -> dict[str, int]:
    return {"food": 0, "production": 0, "science": 1, "coin": 1}


def building_yield(building_id: str) -> dict[str, int]:
    if building_id == BUILDING_ID_PALACE:
        return palace_yield()
    return empty()


def _raw_yield_nonzero(raw: dict[str, int]) -> bool:
    return (
        get_yield(raw, "food") != 0
        or get_yield(raw, "production") != 0
        or get_yield(raw, "science") != 0
        or get_yield(raw, "coin") != 0
    )


def _worked_tile_precedes(hmap: HexMap, a: HexCoord, b: HexCoord) -> bool:
    ra = raw_terrain_yield(hmap, a)
    rb = raw_terrain_yield(hmap, b)
    fa, pa = get_yield(ra, "food"), get_yield(ra, "production")
    fb, pb = get_yield(rb, "food"), get_yield(rb, "production")
    sa, sb = fa + pa, fb + pb
    if sa != sb:
        return sa > sb
    if fa != fb:
        return fa > fb
    if pa != pb:
        return pa > pb
    if a.q != b.q:
        return a.q < b.q
    return a.r < b.r


def _city_tile_owned(city: City, q: int, r: int) -> bool:
    for h in city.owned_tiles:
        if h.q == q and h.r == r:
            return True
    return False


def worked_tiles_for_city(scenario: Scenario, city: City) -> list[HexCoord]:
    hmap = scenario.map
    out: list[HexCoord] = []
    lim = int(city.population)
    if lim <= 0:
        return out

    if str(city.worked_tiles_mode) == WORKED_TILES_MODE_MANUAL:
        for mh in city.manual_worked_tiles:
            if len(out) >= lim:
                break
            if mh.q == city.position.q and mh.r == city.position.r:
                continue
            if not _city_tile_owned(city, mh.q, mh.r):
                continue
            rman = raw_terrain_yield(hmap, mh)
            if not _raw_yield_nonzero(rman):
                continue
            dup = any(ex.q == mh.q and ex.r == mh.r for ex in out)
            if dup:
                continue
            out.append(HexCoord(mh.q, mh.r))
        return out

    candidates: list[HexCoord] = []
    for h in city.owned_tiles:
        if h.q == city.position.q and h.r == city.position.r:
            continue
        rw = raw_terrain_yield(hmap, h)
        if not _raw_yield_nonzero(rw):
            continue
        candidates.append(h)
    if candidates:

        def _cmp(a: HexCoord, b: HexCoord) -> int:
            if _worked_tile_precedes(hmap, a, b):
                return -1
            if _worked_tile_precedes(hmap, b, a):
                return 1
            return 0

        candidates.sort(key=cmp_to_key(_cmp))
        take = min(lim, len(candidates))
        for i in range(take):
            ch = candidates[i]
            out.append(HexCoord(ch.q, ch.r))
    return out


def worked_tiles_yield(scenario: Scenario, city: City) -> dict[str, int]:
    acc = empty()
    for hx in worked_tiles_for_city(scenario, city):
        acc = add(acc, raw_terrain_yield(scenario.map, hx))
    return acc


def city_total_yield(scenario: Scenario, city: City) -> dict[str, int]:
    out = city_center_yield(scenario.map, city)
    for bid in city.building_ids:
        out = add(out, building_yield(str(bid)))
    out = add(out, worked_tiles_yield(scenario, city))
    return out


def production_per_turn(scenario: Scenario, city: City) -> int:
    y = city_total_yield(scenario, city)
    p = get_yield(y, "production")
    return max(0, p)


def science_for_player(scenario: Scenario, owner_id: int) -> int:
    """Sum of city_total_yield 'science' for all cities owned by owner_id. Parity: city_yields.gd."""
    total = 0
    for c in scenario.cities_owned_by(owner_id):
        y = city_total_yield(scenario, c)
        total += get_yield(y, "science")
    return total
