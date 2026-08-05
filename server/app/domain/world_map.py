"""Python logical WorldMap (N5). Parity: game/domain/world/world_map.gd.

Separate from the frozen legacy HexMap (hex_map.py): no adapter, no shared
types. Sole canonical logical map authority for the WorldMap path; terrain
solving and geometry generation stay Godot-only (docs/MAP_MODEL.md).
"""

from __future__ import annotations

from dataclasses import dataclass

EDGE_SMOOTH = "smooth"
EDGE_CLIFF = "cliff"

TileCoord = tuple[int, int]


@dataclass(frozen=True, slots=True)
class MapIdentity:
    """Parity: game/domain/world/map_identity.gd."""

    map_id: str
    schema_version: int
    content_hash: str

    def to_dict(self) -> dict[str, str | int]:
        """Exact key/value parity with map_identity.gd to_dict() (snapshot v3 `map`)."""
        return {
            "map_id": self.map_id,
            "schema_version": self.schema_version,
            "content_hash": self.content_hash,
        }


@dataclass(frozen=True, slots=True)
class WorldTile:
    q: int
    r: int
    elevation: int

    def coord(self) -> TileCoord:
        return (self.q, self.r)


@dataclass(frozen=True, slots=True)
class WorldEdge:
    tile_a: TileCoord
    tile_b: TileCoord
    transition: str


def compare_tile_coords(a: TileCoord, b: TileCoord) -> int:
    """Deterministic tile ordering: q first, then r (world_map.gd parity)."""
    if a[0] < b[0]:
        return -1
    if a[0] > b[0]:
        return 1
    if a[1] < b[1]:
        return -1
    if a[1] > b[1]:
        return 1
    return 0


def normalized_edge_key(a: TileCoord, b: TileCoord) -> str:
    """Canonical undirected edge key "qa,ra|qb,rb", min-lex tile first."""
    min_tile, max_tile = (a, b) if compare_tile_coords(a, b) <= 0 else (b, a)
    return f"{min_tile[0]},{min_tile[1]}|{max_tile[0]},{max_tile[1]}"


def parse_edge_key(key: str) -> tuple[TileCoord, TileCoord]:
    parts = key.split("|")
    if len(parts) != 2:
        raise ValueError(f"invalid edge key: {key}")
    a_parts = parts[0].split(",")
    b_parts = parts[1].split(",")
    if len(a_parts) != 2 or len(b_parts) != 2:
        raise ValueError(f"invalid edge key: {key}")
    return (
        (int(a_parts[0]), int(a_parts[1])),
        (int(b_parts[0]), int(b_parts[1])),
    )


class WorldMap:
    """Immutable-by-convention logical map: tiles, derived edges, identity."""

    def __init__(
        self,
        identity: MapIdentity,
        elevation_step: float,
        elevation_base: int,
        cliff_threshold: int,
        tiles: dict[TileCoord, WorldTile],
        edges: dict[str, WorldEdge],
    ) -> None:
        self.identity = identity
        self.elevation_step = elevation_step
        self.elevation_base = elevation_base
        self.cliff_threshold = cliff_threshold
        self._tiles = dict(tiles)
        self._edges = dict(edges)

    def has_tile(self, q: int, r: int) -> bool:
        return (q, r) in self._tiles

    def has_tile_coord(self, coord: TileCoord) -> bool:
        return coord in self._tiles

    def tile_at(self, q: int, r: int) -> WorldTile:
        coord = (q, r)
        if coord not in self._tiles:
            raise KeyError(f"WorldMap.tile_at: missing tile ({q},{r})")
        return self._tiles[coord]

    def tile_elevation(self, q: int, r: int) -> int:
        return self.tile_at(q, r).elevation

    def tile_count(self) -> int:
        return len(self._tiles)

    def tile_coords(self) -> list[TileCoord]:
        # Tuple comparison is lexicographic q-then-r == compare_tile_coords.
        return sorted(self._tiles.keys())

    def bounds_q(self) -> tuple[int, int]:
        return self._bounds(axis=0)

    def bounds_r(self) -> tuple[int, int]:
        return self._bounds(axis=1)

    def _bounds(self, axis: int) -> tuple[int, int]:
        if not self._tiles:
            return (0, 0)
        values = [coord[axis] for coord in self._tiles]
        return (min(values), max(values))

    def elevation_range(self) -> tuple[int, int]:
        elevations = [tile.elevation for tile in self._tiles.values()]
        return (min(elevations), max(elevations))

    def has_edge_between(self, a: TileCoord, b: TileCoord) -> bool:
        return normalized_edge_key(a, b) in self._edges

    def edge_between(self, a: TileCoord, b: TileCoord) -> WorldEdge:
        key = normalized_edge_key(a, b)
        if key not in self._edges:
            raise KeyError(f"WorldMap.edge_between: missing edge {key}")
        return self._edges[key]

    def edge_at_key(self, edge_key: str) -> WorldEdge:
        if edge_key not in self._edges:
            raise KeyError(f"WorldMap.edge_at_key: missing edge {edge_key}")
        return self._edges[edge_key]

    def edge_count(self) -> int:
        return len(self._edges)

    def cliff_edge_count(self) -> int:
        return sum(1 for edge in self._edges.values() if edge.transition == EDGE_CLIFF)

    def smooth_edge_count(self) -> int:
        return self.edge_count() - self.cliff_edge_count()

    def edges_for_tile(self, q: int, r: int) -> list[WorldEdge]:
        coord = (q, r)
        found = [
            edge
            for edge in self._edges.values()
            if edge.tile_a == coord or edge.tile_b == coord
        ]
        found.sort(key=lambda edge: normalized_edge_key(edge.tile_a, edge.tile_b))
        return found

    def all_edges(self) -> list[WorldEdge]:
        # ASCII string sort of normalized keys == GDScript String "<" order.
        return sorted(
            self._edges.values(),
            key=lambda edge: normalized_edge_key(edge.tile_a, edge.tile_b),
        )
