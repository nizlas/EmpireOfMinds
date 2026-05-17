from __future__ import annotations

from app.domain.hex_coord import HexCoord


def test_neighbors_order_e_to_se() -> None:
    o = HexCoord(0, 0)
    n = o.neighbors()
    assert n[0] == HexCoord(1, 0)
    assert n[1] == HexCoord(1, -1)
    assert n[2] == HexCoord(0, -1)
    assert n[3] == HexCoord(-1, 0)
    assert n[4] == HexCoord(-1, 1)
    assert n[5] == HexCoord(0, 1)


def test_axial_distance_fixtures() -> None:
    fixtures: list[tuple[HexCoord, HexCoord, int]] = [
        (HexCoord(0, 0), HexCoord(0, 0), 0),
        (HexCoord(0, 0), HexCoord(1, 0), 1),
        (HexCoord(0, 0), HexCoord(-1, 0), 1),
        (HexCoord(0, 0), HexCoord(0, 2), 2),
        (HexCoord(0, 0), HexCoord(2, -2), 2),
        (HexCoord(0, 0), HexCoord(9, 5), 14),
        (HexCoord(1, -3), HexCoord(-2, 4), 7),
        (HexCoord(-6, 0), HexCoord(13, 7), 26),
    ]
    for a, b, d in fixtures:
        assert HexCoord.axial_distance(a, b) == d
        assert HexCoord.axial_distance(b, a) == d
