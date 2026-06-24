# Empire of Minds — pure deterministic terrain math core (no bpy).
# Implements docs/TERRAIN_MODEL.md: heightfield + edge constraints, smoothing domains,
# per-domain corner heights, and the authoritative cliff-edge graph.

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Iterable

NEIGHBOR_DIRS: tuple[tuple[int, int], ...] = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)

DEFAULT_ELEVATION_BASE = 1
DEFAULT_CLIFF_THRESHOLD = 1
DEFAULT_ELEVATION_STEP = 0.4
DEFAULT_HEX_RADIUS = 1.0

# Canonical analytic surface kernel (generate_terrain_prototype.py semantics).
DEFAULT_SURFACE_SUBDIVISIONS = 12
DEFAULT_INNER_FLAT_RADIUS_FACTOR = 0.12
DEFAULT_HEIGHT_PROFILE = "smootherstep"
# Approved 7-hex baseline: HILL_RADIUS = HEX_RADIUS * 2.2 (sample_radial_height influence).
DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR = 2.2


class EdgeTransition(str, Enum):
    SMOOTH = "smooth"
    CLIFF = "cliff"


@dataclass(frozen=True)
class TileCoord:
    q: int
    r: int

    def as_tuple(self) -> tuple[int, int]:
        return (self.q, self.r)


@dataclass
class TerrainMap:
    map_id: str
    orientation: str
    elevation_step: float
    cliff_threshold: int
    elevation_base: int
    tiles: dict[tuple[int, int], int]
    edge_overrides: dict[tuple[tuple[int, int], tuple[int, int]], EdgeTransition] = field(
        default_factory=dict
    )


@dataclass(frozen=True)
class ResolvedEdge:
    tile_a: tuple[int, int]
    tile_b: tuple[int, int]
    elevation_a: int
    elevation_b: int
    delta: int
    transition: EdgeTransition


@dataclass
class SmoothingDomain:
    domain_id: int
    tiles: frozenset[tuple[int, int]]


@dataclass(frozen=True)
class CliffEdgeRecord:
    tile_a: tuple[int, int]
    tile_b: tuple[int, int]
    elevation_a: int
    elevation_b: int
    delta: int
    domain_a: int
    domain_b: int


@dataclass
class TerrainModel:
    map: TerrainMap
    smooth_edges: list[ResolvedEdge]
    cliff_edges: list[ResolvedEdge]
    domains: list[SmoothingDomain]
    tile_domain: dict[tuple[int, int], int]
    corner_heights: dict[tuple[int, int, int], float]
    cliff_edge_graph: list[CliffEdgeRecord]


def pos_key(x: float, y: float, precision: int = 6) -> tuple[float, float]:
    return (round(x, precision), round(y, precision))


def sorted_edge_key(
    a: tuple[int, int],
    b: tuple[int, int],
) -> tuple[tuple[int, int], tuple[int, int]]:
    return (a, b) if a <= b else (b, a)


def handdrawn_to_baseline_axial(q: int, r: int) -> tuple[int, int]:
    """PowerPoint handdrawn axes: +q right, +r down-right."""
    return q + r, -r


def baseline_to_handdrawn_axial(q_b: int, r_b: int) -> tuple[int, int]:
    return q_b + r_b, -r_b


def axial_to_world_xy(q: int, r: int, radius: float = DEFAULT_HEX_RADIUS) -> tuple[float, float]:
    x = radius * math.sqrt(3.0) * (float(q) + float(r) * 0.5)
    y = radius * 1.5 * float(r)
    return x, y


def handdrawn_center_world_xy(
    q: int,
    r: int,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float]:
    q_b, r_b = handdrawn_to_baseline_axial(q, r)
    return axial_to_world_xy(q_b, r_b, radius)


def corner_xy_local(corner_index: int, radius: float = DEFAULT_HEX_RADIUS) -> tuple[float, float]:
    angle_deg = 60.0 * float(corner_index) + 30.0
    angle_rad = math.radians(angle_deg)
    return radius * math.cos(angle_rad), radius * math.sin(angle_rad)


def corner_world_xy(
    q_b: int,
    r_b: int,
    corner_index: int,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float]:
    cx, cy = axial_to_world_xy(q_b, r_b, radius)
    lx, ly = corner_xy_local(corner_index, radius)
    return cx + lx, cy + ly


def handdrawn_corner_world_xy(
    q: int,
    r: int,
    corner_index: int,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float]:
    q_b, r_b = handdrawn_to_baseline_axial(q, r)
    return corner_world_xy(q_b, r_b, corner_index, radius)


def _parse_tile_coord(raw: Any) -> tuple[int, int]:
    if isinstance(raw, dict):
        return (int(raw["q"]), int(raw["r"]))
    if isinstance(raw, (list, tuple)) and len(raw) == 2:
        return (int(raw[0]), int(raw[1]))
    raise ValueError(f"invalid tile coordinate: {raw!r}")


def _parse_edge_overrides(raw: Any) -> dict[tuple[tuple[int, int], tuple[int, int]], EdgeTransition]:
    if raw is None:
        return {}
    overrides: dict[tuple[tuple[int, int], tuple[int, int]], EdgeTransition] = {}
    if isinstance(raw, dict):
        for key, value in raw.items():
            if isinstance(key, str):
                parts = key.split(",")
                if len(parts) != 4:
                    raise ValueError(f"invalid edge override key: {key!r}")
                a = (int(parts[0]), int(parts[1]))
                b = (int(parts[2]), int(parts[3]))
            else:
                raise ValueError(f"unsupported edge override key type: {type(key)!r}")
            overrides[sorted_edge_key(a, b)] = EdgeTransition(str(value))
        return overrides
    if isinstance(raw, list):
        for entry in raw:
            edge = entry.get("edge")
            if not isinstance(edge, (list, tuple)) or len(edge) != 2:
                raise ValueError(f"invalid edge override entry: {entry!r}")
            a = _parse_tile_coord(edge[0])
            b = _parse_tile_coord(edge[1])
            overrides[sorted_edge_key(a, b)] = EdgeTransition(str(entry["transition"]))
        return overrides
    raise ValueError(f"unsupported edge_overrides format: {type(raw)!r}")


def parse_terrain_map_ir(data: dict[str, Any]) -> TerrainMap:
    map_id = str(data["id"])
    orientation = str(data.get("orientation", ""))
    elevation_step = float(data.get("elevation_step", DEFAULT_ELEVATION_STEP))
    elevation_base = int(data.get("elevation_base", DEFAULT_ELEVATION_BASE))

    edge_rule = data.get("edge_rule", {})
    cliff_threshold = int(
        edge_rule.get(
            "cliff_if_abs_delta_greater_than",
            data.get("cliff_threshold", DEFAULT_CLIFF_THRESHOLD),
        )
    )

    tiles: dict[tuple[int, int], int] = {}
    for tile in data["tiles"]:
        key = (int(tile["q"]), int(tile["r"]))
        if key in tiles:
            raise ValueError(f"duplicate tile in map: {key}")
        tiles[key] = int(tile["elevation"])

    overrides = _parse_edge_overrides(data.get("edge_overrides"))

    return TerrainMap(
        map_id=map_id,
        orientation=orientation,
        elevation_step=elevation_step,
        cliff_threshold=cliff_threshold,
        elevation_base=elevation_base,
        tiles=tiles,
        edge_overrides=overrides,
    )


def parse_terrain_map_json(json_text: str) -> TerrainMap:
    return parse_terrain_map_ir(json.loads(json_text))


def tile_world_z(terrain_map: TerrainMap, q: int, r: int) -> float:
    elevation = terrain_map.tiles[(q, r)]
    return (elevation - terrain_map.elevation_base) * terrain_map.elevation_step


def resolve_edge_transitions(
    terrain_map: TerrainMap,
) -> tuple[list[ResolvedEdge], list[ResolvedEdge]]:
    smooth_edges: list[ResolvedEdge] = []
    cliff_edges: list[ResolvedEdge] = []
    seen: set[tuple[tuple[int, int], tuple[int, int]]] = set()

    for q, r in sorted(terrain_map.tiles):
        for dq, dr in NEIGHBOR_DIRS:
            nq, nr = q + dq, r + dr
            if (nq, nr) not in terrain_map.tiles:
                continue
            edge_key = sorted_edge_key((q, r), (nq, nr))
            if edge_key in seen:
                continue
            seen.add(edge_key)

            elevation_a = terrain_map.tiles[(q, r)]
            elevation_b = terrain_map.tiles[(nq, nr)]
            delta = abs(elevation_a - elevation_b)

            if edge_key in terrain_map.edge_overrides:
                transition = terrain_map.edge_overrides[edge_key]
            elif delta > terrain_map.cliff_threshold:
                transition = EdgeTransition.CLIFF
            else:
                transition = EdgeTransition.SMOOTH

            record = ResolvedEdge(
                tile_a=edge_key[0],
                tile_b=edge_key[1],
                elevation_a=elevation_a,
                elevation_b=elevation_b,
                delta=delta,
                transition=transition,
            )
            if transition == EdgeTransition.CLIFF:
                cliff_edges.append(record)
            else:
                smooth_edges.append(record)

    cliff_edges.sort(key=lambda e: (e.tile_a, e.tile_b))
    smooth_edges.sort(key=lambda e: (e.tile_a, e.tile_b))
    return smooth_edges, cliff_edges


def partition_smoothing_domains(terrain_map: TerrainMap) -> list[SmoothingDomain]:
    parent: dict[tuple[int, int], tuple[int, int]] = {
        coord: coord for coord in terrain_map.tiles
    }

    def find(coord: tuple[int, int]) -> tuple[int, int]:
        while parent[coord] != coord:
            parent[coord] = parent[parent[coord]]
            coord = parent[coord]
        return coord

    def union(a: tuple[int, int], b: tuple[int, int]) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    smooth_edges, _cliff_edges = resolve_edge_transitions(terrain_map)
    for edge in smooth_edges:
        union(edge.tile_a, edge.tile_b)

    groups: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for coord in terrain_map.tiles:
        root = find(coord)
        groups.setdefault(root, []).append(coord)

    domains: list[SmoothingDomain] = []
    for domain_id, root in enumerate(sorted(groups, key=lambda item: item)):
        tile_set = frozenset(groups[root])
        domains.append(SmoothingDomain(domain_id=domain_id, tiles=tile_set))
    domains.sort(key=lambda d: min(d.tiles))
    for index, domain in enumerate(domains):
        domain.domain_id = index
    return domains


def _tiles_touching_corner(
    terrain_map: TerrainMap,
    wx: float,
    wy: float,
    tile_filter: Iterable[tuple[int, int]] | None = None,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> list[tuple[int, int]]:
    target = pos_key(wx, wy)
    candidates = tile_filter if tile_filter is not None else terrain_map.tiles.keys()
    sharing: list[tuple[int, int]] = []
    for q, r in candidates:
        for corner_index in range(6):
            cwx, cwy = handdrawn_corner_world_xy(q, r, corner_index, radius)
            if pos_key(cwx, cwy) == target:
                sharing.append((q, r))
                break
    return sharing


def _build_smooth_adjacency(
    terrain_map: TerrainMap,
    smooth_edges: list[ResolvedEdge],
) -> dict[tuple[int, int], set[tuple[int, int]]]:
    adjacency: dict[tuple[int, int], set[tuple[int, int]]] = {
        coord: set() for coord in terrain_map.tiles
    }
    for edge in smooth_edges:
        adjacency[edge.tile_a].add(edge.tile_b)
        adjacency[edge.tile_b].add(edge.tile_a)
    return adjacency


def _smooth_component_at_corner(
    start: tuple[int, int],
    corner_tiles: list[tuple[int, int]],
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
) -> list[tuple[int, int]]:
    allowed = set(corner_tiles)
    queue = [start]
    seen = {start}
    while queue:
        current = queue.pop(0)
        for neighbor in smooth_adjacency.get(current, ()):
            if neighbor in allowed and neighbor not in seen:
                seen.add(neighbor)
                queue.append(neighbor)
    return sorted(seen)


def compute_tile_corner_heights(
    terrain_map: TerrainMap,
    domains: list[SmoothingDomain],
    smooth_edges: list[ResolvedEdge],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[tuple[int, int, int], float]:
    """Per-tile corner heights: mean elevation of smooth-connected in-domain tiles at each corner."""
    smooth_adjacency = _build_smooth_adjacency(terrain_map, smooth_edges)
    corner_heights: dict[tuple[int, int, int], float] = {}

    for domain in domains:
        domain_tiles = frozenset(domain.tiles)
        for q, r in domain.tiles:
            for corner_index in range(6):
                wx, wy = handdrawn_corner_world_xy(q, r, corner_index, radius)
                sharing = _tiles_touching_corner(
                    terrain_map,
                    wx,
                    wy,
                    domain_tiles,
                    radius=radius,
                )
                if not sharing:
                    raise RuntimeError(
                        f"no in-domain tiles for corner {(wx, wy)} domain {domain.domain_id}"
                    )
                component = _smooth_component_at_corner((q, r), sharing, smooth_adjacency)
                elevations = [tile_world_z(terrain_map, tq, tr) for tq, tr in component]
                corner_heights[(q, r, corner_index)] = sum(elevations) / float(len(elevations))

    return corner_heights


def build_cliff_edge_graph(
    cliff_edges: list[ResolvedEdge],
    tile_domain: dict[tuple[int, int], int],
) -> list[CliffEdgeRecord]:
    graph: list[CliffEdgeRecord] = []
    for edge in cliff_edges:
        graph.append(
            CliffEdgeRecord(
                tile_a=edge.tile_a,
                tile_b=edge.tile_b,
                elevation_a=edge.elevation_a,
                elevation_b=edge.elevation_b,
                delta=edge.delta,
                domain_a=tile_domain[edge.tile_a],
                domain_b=tile_domain[edge.tile_b],
            )
        )
    graph.sort(key=lambda e: (e.tile_a, e.tile_b))
    return graph


def build_tile_domain_lookup(domains: list[SmoothingDomain]) -> dict[tuple[int, int], int]:
    lookup: dict[tuple[int, int], int] = {}
    for domain in domains:
        for coord in domain.tiles:
            lookup[coord] = domain.domain_id
    return lookup


def build_terrain_model(
    terrain_map: TerrainMap | dict[str, Any] | str,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> TerrainModel:
    if isinstance(terrain_map, str):
        terrain_map = parse_terrain_map_json(terrain_map)
    elif isinstance(terrain_map, dict):
        terrain_map = parse_terrain_map_ir(terrain_map)

    smooth_edges, cliff_edges = resolve_edge_transitions(terrain_map)
    domains = partition_smoothing_domains(terrain_map)
    tile_domain = build_tile_domain_lookup(domains)
    corner_heights = compute_tile_corner_heights(
        terrain_map,
        domains,
        smooth_edges,
        radius=radius,
    )
    cliff_edge_graph = build_cliff_edge_graph(cliff_edges, tile_domain)

    return TerrainModel(
        map=terrain_map,
        smooth_edges=smooth_edges,
        cliff_edges=cliff_edges,
        domains=domains,
        tile_domain=tile_domain,
        corner_heights=corner_heights,
        cliff_edge_graph=cliff_edge_graph,
    )


def height_profile_weight(
    t: float,
    profile: str = DEFAULT_HEIGHT_PROFILE,
) -> float:
    t_clamped = max(0.0, min(1.0, t))
    if profile == "linear":
        return t_clamped
    if profile in ("smoothstep", "smootherstep"):
        return perlin_smootherstep(t_clamped)
    if profile == "ease_in_cubic":
        return t_clamped * t_clamped * (2.0 - t_clamped)
    if profile == "quadratic":
        return t_clamped * t_clamped
    return perlin_smootherstep(t_clamped)


def perlin_smootherstep(t: float) -> float:
    """Same 6th-degree smootherstep as approved baseline hill_falloff_weight."""
    t_clamped = max(0.0, min(1.0, t))
    return t_clamped * t_clamped * t_clamped * (
        t_clamped * (t_clamped * 6.0 - 15.0) + 10.0
    )


def radial_influence_weight(distance: float, influence_radius: float) -> float:
    """1.0 at distance 0, 0.0 at distance >= influence_radius (baseline hill semantics)."""
    if influence_radius <= 0.0:
        return 0.0
    t = max(0.0, min(1.0, distance / influence_radius))
    return 1.0 - perlin_smootherstep(t)


def _build_cliff_neighbor_pairs(
    cliff_edges: list[ResolvedEdge],
) -> set[frozenset[tuple[int, int]]]:
    return {frozenset((edge.tile_a, edge.tile_b)) for edge in cliff_edges}


def _tiles_are_cliff_neighbors(
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    cliff_pairs: set[frozenset[tuple[int, int]]],
) -> bool:
    if tile_a == tile_b:
        return False
    return frozenset((tile_a, tile_b)) in cliff_pairs


def domain_for_tile(model: TerrainModel, q: int, r: int) -> SmoothingDomain:
    domain_id = model.tile_domain[(q, r)]
    for domain in model.domains:
        if domain.domain_id == domain_id:
            return domain
    raise KeyError(f"no smoothing domain {domain_id} for tile {(q, r)}")


def sample_smooth_domain_surface_world(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    Smooth-domain height using approved baseline radial influence (HILL_RADIUS semantics)
    over tile centers that are smooth-connected to the sampling tile.
    Direct cliff neighbors are excluded so height does not bleed across cliffs.
    """
    domain = domain_for_tile(model, q, r)
    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    component = set(
        _smooth_component_at_corner((q, r), list(domain.tiles), smooth_adjacency)
    )
    cliff_pairs = _build_cliff_neighbor_pairs(model.cliff_edges)
    influence_radius = radius * influence_radius_factor
    height_sum = 0.0
    weight_sum = 0.0
    for tq, tr in component:
        if _tiles_are_cliff_neighbors((q, r), (tq, tr), cliff_pairs):
            continue
        cx, cy = handdrawn_center_world_xy(tq, tr, radius)
        dist = math.hypot(wx - cx, wy - cy)
        weight = radial_influence_weight(dist, influence_radius)
        if weight <= 0.0:
            continue
        tile_z = tile_world_z(model.map, tq, tr)
        height_sum += tile_z * weight
        weight_sum += weight
    if weight_sum <= 1e-12:
        return tile_world_z(model.map, q, r)
    return height_sum / weight_sum


def curvature_influence_audit(
    *,
    hex_radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> dict[str, float]:
    """Compare effective influence radii in HEX_RADIUS units."""
    approved_hill_radius = hex_radius * influence_radius_factor
    return {
        "hex_radius_world": hex_radius,
        "approved_hill_influence_radius_hex_units": influence_radius_factor,
        "approved_hill_influence_radius_world": approved_hill_radius,
        "prior_analytic_per_hex_influence_hex_units": 1.0,
        "terrainmap_smooth_domain_influence_hex_units": influence_radius_factor,
    }


def analytic_surface_height(
    center_height: float,
    edge_height: float,
    radial: float,
    *,
    inner_flat_radius_factor: float = DEFAULT_INNER_FLAT_RADIUS_FACTOR,
    profile: str = DEFAULT_HEIGHT_PROFILE,
) -> float:
    if radial <= inner_flat_radius_factor:
        return center_height
    denom = 1.0 - inner_flat_radius_factor
    t = (radial - inner_flat_radius_factor) / denom
    t = max(0.0, min(1.0, t))
    weight = height_profile_weight(t, profile)
    return center_height + (edge_height - center_height) * weight


def sector_barycentric_xy(
    sector: int,
    si: int,
    sj: int,
    subdiv: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float, float, float]:
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx, cy = corner_xy_local(cj, radius)
    denom = float(subdiv)
    wb = float(si) / denom
    wc = float(sj) / denom
    lx = wb * bx + wc * cx
    ly = wb * by + wc * cy
    radial = (float(si) + float(sj)) / denom
    edge_t = (float(sj) / float(si + sj)) if (si + sj) > 0 else 0.0
    return lx, ly, radial, edge_t


def sector_edge_height(
    q: int,
    r: int,
    sector: int,
    edge_t: float,
    domain_id: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    ci = sector
    cj = (sector + 1) % 6
    hi = model.corner_heights[(q, r, ci)]
    hj = model.corner_heights[(q, r, cj)]
    return hi * (1.0 - edge_t) + hj * edge_t


def _point_sector(lx: float, ly: float) -> int:
    angle = math.degrees(math.atan2(ly, lx)) % 360.0
    for sector in range(6):
        a0 = (30.0 + 60.0 * float(sector)) % 360.0
        a1 = (30.0 + 60.0 * float((sector + 1) % 6)) % 360.0
        if a0 < a1:
            if a0 <= angle < a1:
                return sector
        elif angle >= a0 or angle < a1:
            return sector
    return 0


def sample_analytic_surface_at_local(
    q: int,
    r: int,
    lx: float,
    ly: float,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    inner_flat_radius_factor: float = DEFAULT_INNER_FLAT_RADIUS_FACTOR,
    profile: str = DEFAULT_HEIGHT_PROFILE,
) -> float:
    domain_id = model.tile_domain[(q, r)]
    center_height = tile_world_z(model.map, q, r)
    if math.hypot(lx, ly) < 1e-9:
        return center_height

    sector = _point_sector(lx, ly)
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx_l, cy_l = corner_xy_local(cj, radius)
    denom = bx * cy_l - cx_l * by
    if abs(denom) < 1e-12:
        return center_height
    wi = (lx * cy_l - ly * cx_l) / denom
    wj = (ly * bx - lx * by) / denom
    radial = max(0.0, min(1.0, wi + wj))
    edge_t = wj / (wi + wj) if (wi + wj) > 1e-12 else 0.0

    edge_height = sector_edge_height(q, r, sector, edge_t, domain_id, model, radius=radius)
    return analytic_surface_height(
        center_height,
        edge_height,
        radial,
        inner_flat_radius_factor=inner_flat_radius_factor,
        profile=profile,
    )


def handdrawn_tile_at_world(
    wx: float,
    wy: float,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[int, int] | None:
    q_b, r_b = _world_xy_to_baseline_axial_round(wx, wy, radius)
    q, r = baseline_to_handdrawn_axial(q_b, r_b)
    if (q, r) in model.map.tiles:
        return q, r
    return None


def sample_analytic_surface_world(
    wx: float,
    wy: float,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    q_b, r_b = _world_xy_to_baseline_axial_round(wx, wy, radius)
    q, r = baseline_to_handdrawn_axial(q_b, r_b)
    if (q, r) not in model.map.tiles:
        return 0.0
    q_b_tile, r_b_tile = handdrawn_to_baseline_axial(q, r)
    cx, cy = axial_to_world_xy(q_b_tile, r_b_tile, radius)
    return sample_analytic_surface_at_local(q, r, wx - cx, wy - cy, model, radius=radius)


def _cube_round(q: float, r: float, s: float) -> tuple[int, int]:
    rq = round(q)
    rr = round(r)
    rs = round(s)
    q_diff = abs(rq - q)
    r_diff = abs(rr - r)
    s_diff = abs(rs - s)
    if q_diff > r_diff and q_diff > s_diff:
        rq = -rr - rs
    elif r_diff > s_diff:
        rr = -rq - rs
    else:
        rs = -rq - rr
    return int(rq), int(rr)


def _world_xy_to_baseline_axial_round(
    wx: float,
    wy: float,
    radius: float,
) -> tuple[int, int]:
    q = (math.sqrt(3.0) / 3.0 * wx - 1.0 / 3.0 * wy) / radius
    r = (2.0 / 3.0 * wy) / radius
    return _cube_round(q, r, -q - r)


def map_q_bounds(tiles: dict[tuple[int, int], int]) -> tuple[int, int]:
    qs = [q for q, _r in tiles]
    return min(qs), max(qs)


def map_r_bounds(tiles: dict[tuple[int, int], int]) -> tuple[int, int]:
    rs = [r for _q, r in tiles]
    return min(rs), max(rs)


def map_elevation_bounds(tiles: dict[tuple[int, int], int]) -> tuple[int, int]:
    elevations = list(tiles.values())
    return min(elevations), max(elevations)


def audit_summary(model: TerrainModel) -> dict[str, Any]:
    tiles = model.map.tiles
    q_min, q_max = map_q_bounds(tiles)
    r_min, r_max = map_r_bounds(tiles)
    e_min, e_max = map_elevation_bounds(tiles)
    return {
        "map_id": model.map.map_id,
        "tile_count": len(tiles),
        "q_bounds": (q_min, q_max),
        "r_bounds": (r_min, r_max),
        "elevation_min_max": (e_min, e_max),
        "smooth_edge_count": len(model.smooth_edges),
        "cliff_edge_count": len(model.cliff_edges),
        "smoothing_domain_count": len(model.domains),
        "corner_height_count": len(model.corner_heights),
    }


if __name__ == "__main__":
    SAMPLE = """
    {
      "id": "self_test",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":1},
        {"q":0,"r":1,"elevation":3}
      ]
    }
    """
    built = build_terrain_model(SAMPLE)
    summary = audit_summary(built)
    assert summary["tile_count"] == 3
    assert summary["cliff_edge_count"] == 2
    assert summary["smooth_edge_count"] == 1
    assert summary["smoothing_domain_count"] == 2
    assert summary["corner_height_count"] == 18
    x10, y10 = handdrawn_center_world_xy(1, 0)
    x01, y01 = handdrawn_center_world_xy(0, 1)
    assert x10 > 0 and abs(y10) < 1e-9
    assert x01 > 0 and y01 < 0
    print("eom_terrain_math_core self-test passed:", summary)
