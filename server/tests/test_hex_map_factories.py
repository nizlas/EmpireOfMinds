"""HexMap factory parity tests (tiny + prototype golden)."""

from __future__ import annotations

import json
from pathlib import Path

from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap, Landform, Terrain, make_tiny_test_map
from app.domain.prototype_maps import make_prototype_play_map

_GOLDEN = Path(__file__).resolve().parent / "golden" / "prototype_play_map.gd_v0.json"


def test_make_tiny_test_map_exact() -> None:
    m = make_tiny_test_map()
    assert m.size() == 7
    o = HexCoord(0, 0)
    assert m.terrain_at(o) == Terrain.PLAINS
    w = HexCoord(-1, 0)
    assert m.terrain_at(w) == Terrain.WATER


def test_proto_anchor_cells() -> None:
    m = make_prototype_play_map()
    assert m.size() == 702
    assert m.terrain_at(HexCoord(0, 0)) == Terrain.PLAINS
    assert m.landform_at(HexCoord(0, 0)) == Landform.FLAT
    assert m.terrain_at(HexCoord(1, 0)) == Terrain.GRASSLAND
    assert m.landform_at(HexCoord(1, 0)) == Landform.FLAT
    assert m.terrain_at(HexCoord(3, 0)) == Terrain.GRASSLAND
    assert m.terrain_at(HexCoord(9, 5)) == Terrain.GRASSLAND
    assert not m.has_woods(HexCoord(1, 0))
    assert any(m.terrain_at(c) == Terrain.WATER for c in m.coords())


def test_hex_map_roundtrip_json_cells() -> None:
    m0 = make_tiny_test_map()
    rows = m0.to_json_cells()
    m1 = HexMap.from_json_cells(rows)
    assert m1.json_cells_dumps() == m0.json_cells_dumps()


def test_prototype_play_map_matches_golden() -> None:
    expected = json.loads(_GOLDEN.read_text(encoding="utf-8"))
    got = make_prototype_play_map().to_json_cells()
    assert got == expected
