"""Axial hex coordinates. Parity: game/domain/hex_coord.gd (cube distance, neighbor order)."""

from __future__ import annotations

from dataclasses import dataclass

# E, NE, NW, W, SW, SE — same deltas as HexCoord.DIRECTIONS in GDScript.
_DIRECTIONS: tuple[tuple[int, int], ...] = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)


@dataclass(frozen=True, slots=True)
class HexCoord:
    q: int
    r: int

    def neighbors(self) -> tuple[HexCoord, ...]:
        return tuple(HexCoord(self.q + dq, self.r + dr) for dq, dr in _DIRECTIONS)

    @staticmethod
    def axial_distance(a: HexCoord, b: HexCoord) -> int:
        aq, ar = a.q, a.r
        bq, br = b.q, b.r
        ac, ay, az = aq, ar, -aq - ar
        bc, by_, bz = bq, br, -bq - br
        dx, dy, dz = ac - bc, ay - by_, az - bz
        return max(abs(dx), abs(dy), abs(dz))
