"""Finite hex map: cells, landforms, woods. Parity: game/domain/hex_map.gd (subset for Slice B)."""

from __future__ import annotations

import json
from enum import IntEnum
from typing import Any

from app.domain.hex_coord import HexCoord


class Terrain(IntEnum):
    """Order matches game/domain/hex_map.gd Terrain enum (PLAINS=0, WATER=1, GRASSLAND=2)."""

    PLAINS = 0
    WATER = 1
    GRASSLAND = 2


class Landform(IntEnum):
    FLAT = 0
    HILLS = 1


def _terrain_json(t: Terrain) -> str:
    return t.name.lower()


def _landform_json(lf: Landform) -> str:
    return lf.name.lower()


class HexMap:
    __slots__ = ("_cells", "_landforms", "_woods")

    def __init__(
        self,
        cells: dict[tuple[int, int], Terrain],
        landforms: dict[tuple[int, int], Landform] | None = None,
        woods: dict[tuple[int, int], bool] | None = None,
    ) -> None:
        self._cells = dict(cells)
        self._landforms = dict(landforms) if landforms else {}
        self._woods = dict(woods) if woods else {}

    def has(self, coord: HexCoord) -> bool:
        return (coord.q, coord.r) in self._cells

    def terrain_at(self, coord: HexCoord) -> Terrain:
        if not self.has(coord):
            raise AssertionError("terrain_at called for missing coordinate")
        return self._cells[(coord.q, coord.r)]

    def landform_at(self, coord: HexCoord) -> Landform:
        if not self.has(coord):
            raise AssertionError("landform_at called for missing coordinate")
        return self._landforms.get((coord.q, coord.r), Landform.FLAT)

    def has_woods(self, coord: HexCoord) -> bool:
        if not self.has(coord):
            raise AssertionError("has_woods called for missing coordinate")
        return (coord.q, coord.r) in self._woods

    def size(self) -> int:
        return len(self._cells)

    def coords(self) -> list[HexCoord]:
        return [HexCoord(q, r) for (q, r) in self._cells.keys()]

    def to_json_cells(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for q, r in sorted(self._cells.keys(), key=lambda t: (t[0], t[1])):
            coord = HexCoord(q, r)
            out.append(
                {
                    "q": q,
                    "r": r,
                    "terrain": _terrain_json(self._cells[(q, r)]),
                    "landform": _landform_json(self.landform_at(coord)),
                    "woods": self.has_woods(coord),
                }
            )
        return out

    @staticmethod
    def from_json_cells(rows: list[dict[str, Any]]) -> HexMap:
        cells: dict[tuple[int, int], Terrain] = {}
        landforms: dict[tuple[int, int], Landform] = {}
        woods: dict[tuple[int, int], bool] = {}
        for row in rows:
            q = int(row["q"])
            r = int(row["r"])
            terr = Terrain[row["terrain"].upper()]
            cells[(q, r)] = terr
            lf = Landform[row["landform"].upper()]
            if lf != Landform.FLAT:
                landforms[(q, r)] = lf
            if bool(row.get("woods", False)):
                woods[(q, r)] = True
        return HexMap(cells, landforms, woods)

    def json_cells_dumps(self) -> str:
        return json.dumps(self.to_json_cells(), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def make_tiny_test_map() -> HexMap:
    c: dict[tuple[int, int], Terrain] = {
        (0, 0): Terrain.PLAINS,
        (1, 0): Terrain.PLAINS,
        (1, -1): Terrain.PLAINS,
        (0, -1): Terrain.PLAINS,
        (-1, 0): Terrain.WATER,
        (-1, 1): Terrain.PLAINS,
        (0, 1): Terrain.PLAINS,
    }
    return HexMap(c)
