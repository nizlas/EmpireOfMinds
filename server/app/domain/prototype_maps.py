"""Prototype play map factory. Parity: game/domain/hex_map.gd make_prototype_play_map + helpers."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from app.domain.hex_map import HexMap, Landform, Terrain

# Must match HexLayout.SIZE in `game/presentation/hex_layout.gd` (128.0): world-space padding for the prototype sea shell.
_PROTO_LAYOUT_HEX_SIZE: float = 128.0
_PROTO_VIS_WATER_SHELL_PAD_STEPS: int = 3

_PROTO_AX_NEI: tuple[tuple[int, int], ...] = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)

# Parity: game/domain/prototype_terrain_features.gd PROTOTYPE_WOODS_HEXES
PROTOTYPE_WOODS_HEXES: tuple[tuple[int, int], ...] = (
    (-6, 0),
    (-5, -1),
    (-5, 1),
    (-4, -2),
    (-4, 0),
    (-4, 1),
    (-3, 1),
    (-2, 2),
    (0, -3),
    (1, -1),
    (1, -2),
    (1, -3),
    (2, -3),
    (2, 3),
    (3, -3),
    (3, 2),
    (4, -3),
    (2, -2),
    (5, -3),
    (5, 4),
    (0, 4),
    (6, 4),
    (7, -2),
    (7, 0),
    (7, 1),
    (7, 5),
    (8, -1),
    (8, 1),
    (8, 4),
    (4, 1),
    (10, 2),
    (10, 5),
    (10, 6),
    (11, 2),
    (11, 4),
    (11, 6),
    (12, 6),
    (12, 8),
    (13, 6),
    (13, 7),
)


def prototype_woods_set() -> dict[tuple[int, int], bool]:
    return {v: True for v in PROTOTYPE_WOODS_HEXES}


# Parity: game/domain/prototype_plains_clusters.gd cluster_groups -> all_cluster_hexes_sorted
_CLUSTER_GROUPS: tuple[tuple[tuple[int, int], ...], ...] = (
    ((0, -1),),
    ((2, -2), (3, -2)),
    ((5, 0), (6, 0), (5, 1)),
    ((-1, 2), (0, 2), (1, 2), (0, 3), (1, 3)),
    (
        (6, 2),
        (6, 3),
        (7, 3),
        (8, 2),
        (8, 3),
        (9, 2),
        (9, 3),
        (9, 4),
        (10, 3),
        (10, 4),
    ),
)


def _all_cluster_hexes_sorted() -> list[tuple[int, int]]:
    seen: set[tuple[int, int]] = set()
    out: list[tuple[int, int]] = []
    for group in _CLUSTER_GROUPS:
        for q, r in group:
            k = (q, r)
            if k not in seen:
                seen.add(k)
                out.append(k)
    out.sort(key=lambda t: (t[0], t[1]))
    return out


def _proto_axial_dist(q: int, r: int, aq: int, ar: int) -> int:
    return int(abs(q - aq) + abs(r - ar) + abs(q + r - aq - ar)) / 2


@dataclass(frozen=True, slots=True)
class _Rect2:
    x: float
    y: float
    w: float
    h: float

    def merge(self, other: _Rect2) -> _Rect2:
        x0 = min(self.x, other.x)
        y0 = min(self.y, other.y)
        x1 = max(self.x + self.w, other.x + other.w)
        y1 = max(self.y + self.h, other.y + other.h)
        return _Rect2(x0, y0, x1 - x0, y1 - y0)

    def intersects(self, other: _Rect2) -> bool:
        return not (
            other.x >= self.x + self.w
            or other.x + other.w <= self.x
            or other.y >= self.y + self.h
            or other.y + other.h <= self.y
        )


def _proto_hex_center_world(q: int, r: int) -> tuple[float, float]:
    s = _PROTO_LAYOUT_HEX_SIZE
    x = s * math.sqrt(3.0) * (float(q) + float(r) / 2.0)
    y = s * 1.5 * float(r)
    return (x, y)


def _proto_hex_world_aabb_xy(q: int, r: int) -> _Rect2:
    cx, cy = _proto_hex_center_world(q, r)
    min_x = math.inf
    max_x = -math.inf
    min_y = math.inf
    max_y = -math.inf
    for deg in (30, 90, 150, 210, 270, 330):
        rad = math.radians(float(deg))
        px = cx + math.cos(rad) * _PROTO_LAYOUT_HEX_SIZE
        py = cy + math.sin(rad) * _PROTO_LAYOUT_HEX_SIZE
        min_x = min(min_x, px)
        max_x = max(max_x, px)
        min_y = min(min_y, py)
        max_y = max(max_y, py)
    return _Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


def _proto_land_world_rect(land: dict[tuple[int, int], Any]) -> _Rect2:
    first = True
    acc = _Rect2(0, 0, 0, 0)
    for q, r in land.keys():
        hb = _proto_hex_world_aabb_xy(q, r)
        if first:
            acc = hb
            first = False
        else:
            acc = acc.merge(hb)
    return acc


def _proto_expand_world_rect_pad_hex_steps(r: _Rect2, steps: int) -> _Rect2:
    pad_x = float(steps) * math.sqrt(3.0) * _PROTO_LAYOUT_HEX_SIZE
    pad_y = float(steps) * 1.5 * _PROTO_LAYOUT_HEX_SIZE
    return _Rect2(r.x - pad_x, r.y - pad_y, r.w + 2.0 * pad_x, r.h + 2.0 * pad_y)


def _proto_add_world_axis_rect_water_shell(
    land: dict[tuple[int, int], Any], c: dict[tuple[int, int], Terrain]
) -> None:
    inner = _proto_land_world_rect(land)
    outer = _proto_expand_world_rect_pad_hex_steps(inner, _PROTO_VIS_WATER_SHELL_PAD_STEPS)
    q_lo = 2147483647
    q_hi = -2147483648
    r_lo = 2147483647
    r_hi = -2147483648
    for q, r in land.keys():
        q_lo = min(q_lo, q)
        q_hi = max(q_hi, q)
        r_lo = min(r_lo, r)
        r_hi = max(r_hi, r)
    span = 12 + _PROTO_VIS_WATER_SHELL_PAD_STEPS * 4
    q = q_lo - span
    while q <= q_hi + span:
        r = r_lo - span
        while r <= r_hi + span:
            kk = (q, r)
            if kk in land:
                r += 1
                continue
            hb = _proto_hex_world_aabb_xy(q, r)
            if outer.intersects(hb):
                c[kk] = Terrain.WATER
            r += 1
        q += 1


def _proto_lake_strait_dict() -> dict[tuple[int, int], bool]:
    d: dict[tuple[int, int], bool] = {}
    for v in [(-1, 0), (-2, 0), (-2, 1), (-1, -1), (-3, 0)]:
        d[v] = True
    return d


def _proto_nw_bay_dict() -> dict[tuple[int, int], bool]:
    d: dict[tuple[int, int], bool] = {}
    for v in [
        (-4, 3),
        (-3, 3),
        (-2, 3),
        (-4, 2),
        (-5, 4),
        (-4, 4),
        (-6, 4),
        (-4, 5),
        (-5, 3),
        (-3, 4),
        (-5, 2),
    ]:
        d[v] = True
    return d


def _proto_coastal_chop_dict() -> dict[tuple[int, int], bool]:
    return {}


def _proto_island_extension_hexes() -> list[tuple[int, int]]:
    return [
        (5, -2),
        (5, -1),
        (6, -2),
        (6, -1),
        (7, -2),
        (7, -1),
        (8, -2),
        (8, -1),
        (4, -2),
        (5, -3),
        (6, -3),
        (7, -3),
        (5, 1),
        (5, 2),
        (6, 0),
        (6, 1),
        (6, 2),
        (7, 0),
        (7, 1),
        (7, 2),
        (7, 3),
        (8, 1),
        (8, 0),
        (9, 0),
        (9, 1),
        (10, 1),
        (10, 2),
        (11, 2),
        (11, 3),
        (8, 2),
        (8, 3),
        (8, 4),
        (8, 5),
        (8, 6),
        (9, 2),
        (9, 3),
        (9, 4),
        (9, 5),
        (9, 6),
        (9, 7),
        (10, 3),
        (10, 4),
        (10, 5),
        (10, 6),
        (10, 7),
        (11, 4),
        (11, 5),
        (11, 6),
        (11, 7),
        (11, 8),
        (12, 5),
        (12, 6),
        (12, 7),
        (12, 8),
        (13, 6),
        (13, 7),
        (6, 5),
        (6, 6),
        (6, 7),
        (7, 5),
        (7, 6),
        (7, 7),
        (8, 7),
        (10, 8),
        (9, 8),
        (4, 2),
        (4, 3),
        (3, 3),
        (3, 4),
        (2, 4),
        (2, 5),
        (1, 4),
        (0, 4),
        (5, 3),
        (5, 4),
        (6, 3),
        (6, 4),
    ]


def _proto_g1_core_candidates(
    lake: dict[tuple[int, int], bool], bay: dict[tuple[int, int], bool], chop: dict[tuple[int, int], bool]
) -> dict[tuple[int, int], bool]:
    cand: dict[tuple[int, int], bool] = {}
    q = -6
    while q <= 6:
        r = -6
        while r <= 6:
            k = (q, r)
            if _proto_axial_dist(q, r, 0, 0) <= 6:
                if q <= -5 and r >= 5:
                    r += 1
                    continue
                if q >= 7 and r <= -5:
                    r += 1
                    continue
                if k not in lake and k not in bay and k not in chop:
                    cand[k] = True
            r += 1
        q += 1
    return cand


def _proto_merge_candidates(
    core: dict[tuple[int, int], bool],
    ext: list[tuple[int, int]],
    chop: dict[tuple[int, int], bool],
) -> dict[tuple[int, int], bool]:
    cand = dict(core)
    for k in ext:
        if k not in chop:
            cand[k] = True
    return cand


def _proto_flood_component(candidates: dict[tuple[int, int], bool]) -> dict[tuple[int, int], bool]:
    land: dict[tuple[int, int], bool] = {}
    stack: list[tuple[int, int]] = [(0, 0)]
    if (0, 0) not in candidates:
        return land
    while stack:
        cur = stack.pop()
        if cur in land:
            continue
        if cur not in candidates:
            continue
        land[cur] = True
        cq, cr = cur
        for dq, dr in _PROTO_AX_NEI:
            stack.append((cq + dq, cr + dr))
    return land


def _proto_collect_land_keys() -> dict[tuple[int, int], bool]:
    lake = _proto_lake_strait_dict()
    bay = _proto_nw_bay_dict()
    chop = _proto_coastal_chop_dict()
    core = _proto_g1_core_candidates(lake, bay, chop)
    ext = _proto_island_extension_hexes()
    cand = _proto_merge_candidates(core, ext, chop)
    return _proto_flood_component(cand)


def _paint_grass_flat(
    land: dict[tuple[int, int], bool],
    c: dict[tuple[int, int], Terrain],
    lf: dict[tuple[int, int], Landform],
    cells: list[tuple[int, int]],
) -> None:
    for v in cells:
        if v in land:
            c[v] = Terrain.GRASSLAND
            lf.pop(v, None)


def _paint_grass_hill(
    land: dict[tuple[int, int], bool],
    c: dict[tuple[int, int], Terrain],
    lf: dict[tuple[int, int], Landform],
    cells: list[tuple[int, int]],
) -> None:
    for v in cells:
        if v in land:
            c[v] = Terrain.GRASSLAND
            lf[v] = Landform.HILLS


def _paint_plains_flat(
    land: dict[tuple[int, int], bool],
    c: dict[tuple[int, int], Terrain],
    lf: dict[tuple[int, int], Landform],
    cells: list[tuple[int, int]],
) -> None:
    for v in cells:
        if v in land:
            c[v] = Terrain.PLAINS
            lf.pop(v, None)


def _paint_plains_hill(
    land: dict[tuple[int, int], bool],
    c: dict[tuple[int, int], Terrain],
    lf: dict[tuple[int, int], Landform],
    cells: list[tuple[int, int]],
) -> None:
    for v in cells:
        if v in land:
            c[v] = Terrain.PLAINS
            lf[v] = Landform.HILLS


def _proto_paint_land_terrain(
    land: dict[tuple[int, int], bool],
    c: dict[tuple[int, int], Terrain],
    lf: dict[tuple[int, int], Landform],
) -> None:
    for k in land.keys():
        c[k] = Terrain.GRASSLAND
        lf.pop(k, None)

    _paint_grass_hill(
        land,
        c,
        lf,
        [
            (-4, -1),
            (-4, 0),
            (-3, -1),
            (-3, 0),
            (-2, -1),
            (-2, 0),
            (-1, 1),
            (0, 2),
            (-1, 2),
            (-2, 2),
            (-3, 2),
            (1, 1),
            (1, 2),
            (0, 3),
        ],
    )

    _paint_plains_flat(
        land,
        c,
        lf,
        [
            (-6, 0),
            (-5, -1),
            (-4, -2),
            (-4, 0),
            (-5, 1),
            (-4, 1),
            (-3, -1),
            (-3, 1),
            (-2, 2),
            (0, -3),
            (1, -1),
            (1, -3),
            (1, -2),
            (2, -3),
            (2, 0),
            (3, -1),
            (2, 3),
            (3, -3),
            (3, 2),
            (4, -3),
            (4, -1),
            (2, -2),
            (4, -4),
            (5, -3),
            (5, 3),
            (5, 4),
            (6, 5),
            (0, 4),
            (6, 4),
            (7, 0),
            (7, 1),
            (7, 5),
            (8, 0),
            (8, 1),
            (8, 4),
            (9, 4),
            (4, 1),
            (10, 2),
            (10, 5),
            (10, 6),
            (11, 2),
            (11, 4),
            (11, 5),
            (11, 6),
            (12, 6),
            (12, 8),
            (13, 6),
            (13, 7),
            (0, 5),
            (1, 4),
        ],
    )

    _paint_plains_hill(
        land,
        c,
        lf,
        [
            (-4, -1),
            (4, -2),
            (5, -2),
            (6, -2),
            (6, -3),
            (7, -3),
            (7, -2),
            (5, -1),
            (6, -1),
            (7, -1),
            (8, -1),
            (8, -2),
            (10, 3),
            (11, 3),
            (9, 6),
            (9, 7),
            (10, 4),
        ],
    )

    _paint_grass_hill(
        land,
        c,
        lf,
        [
            (4, 2),
            (4, 3),
            (3, 4),
            (2, 5),
            (5, 3),
            (5, 2),
            (6, 3),
            (7, 3),
            (7, 4),
            (8, 5),
            (8, 6),
            (9, 7),
            (10, 7),
            (11, 7),
            (11, 8),
            (1, 3),
            (2, 2),
            (3, 5),
            (8, 3),
            (9, 3),
            (-1, -3),
            (2, 1),
            (1, 5),
            (-1, -2),
        ],
    )

    _paint_plains_flat(land, c, lf, [(0, 0)])
    _paint_grass_flat(land, c, lf, [(1, 0)])
    _paint_grass_flat(land, c, lf, [(3, 0)])
    _paint_grass_flat(land, c, lf, [(9, 5)])
    _paint_grass_flat(land, c, lf, [(-1, 3), (-2, 4)])

    for dv in _all_cluster_hexes_sorted():
        if dv in land:
            _paint_plains_flat(land, c, lf, [dv])


def make_prototype_play_map() -> HexMap:
    land = _proto_collect_land_keys()
    c: dict[tuple[int, int], Terrain] = {}
    lf: dict[tuple[int, int], Landform] = {}
    _proto_paint_land_terrain(land, c, lf)
    _proto_add_world_axis_rect_water_shell(land, c)
    woods_raw = prototype_woods_set()
    return HexMap(c, lf, woods_raw)


def prototype_play_land_key_set() -> dict[tuple[int, int], bool]:
    return _proto_collect_land_keys()
