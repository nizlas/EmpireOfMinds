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
# docs/TERRAIN_MODEL.md §9: bounded local deformation near SSC corners (fraction of HEX_RADIUS).
DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR = 0.2
# SharedEdgeCurve: endpoint pin correction band as fraction of edge parameter t in [0, 1].
DEFAULT_SHARED_EDGE_ENDPOINT_BAND_FACTOR = 0.25
# World/local tolerance for treating a sample as lying on a shared SSC corner vertex.
SSC_CORNER_VERTEX_EPSILON = 1e-5
# Collinearity tolerance for center→edge-midpoint median detection (fraction of radius).
MID_EDGE_MEDIAN_COLLINEARITY_EPSILON = 1e-6
# §11 sector patch: Hermite lateral basis between side/spine/side (zero deriv at 0, 0.5, 1).
DEFAULT_SECTOR_PATCH_LATERAL_PROFILE = "hermite"


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


@dataclass(frozen=True)
class SscCornerRecord:
    """Single-cliff (SSC) mixed corner: one cliff edge bridged by two smooth edges."""

    corner_world: tuple[float, float]
    cliff_a: tuple[int, int]
    cliff_b: tuple[int, int]
    bridge: tuple[int, int]
    target_z: float
    corner_index_by_tile: tuple[tuple[int, int, int], ...]

    def corner_index_for(self, q: int, r: int) -> int | None:
        for tq, tr, corner_index in self.corner_index_by_tile:
            if (tq, tr) == (q, r):
                return corner_index
        return None


@dataclass(frozen=True)
class SharedEdgeCurve:
    """Canonical Z profile along one resolved smooth edge (shared by both adjacent tiles)."""

    edge_key: tuple[tuple[int, int], tuple[int, int]]
    tile_a: tuple[int, int]
    tile_b: tuple[int, int]
    physical_edge_a: int
    physical_edge_b: int
    corner_z_0: float
    corner_z_1: float
    samples: tuple[tuple[tuple[float, float], float], ...]


@dataclass
class TerrainModel:
    map: TerrainMap
    smooth_edges: list[ResolvedEdge]
    cliff_edges: list[ResolvedEdge]
    domains: list[SmoothingDomain]
    tile_domain: dict[tuple[int, int], int]
    corner_heights: dict[tuple[int, int, int], float]
    cliff_edge_graph: list[CliffEdgeRecord]
    ssc_corners: list[SscCornerRecord] = field(default_factory=list)
    shared_edge_curves: dict[tuple[tuple[int, int], tuple[int, int]], SharedEdgeCurve] = (
        field(default_factory=dict)
    )
    shared_edge_z_lookup: dict[tuple[float, float], float] = field(default_factory=dict)
    hexpatch_bundle: Any | None = None
    hexpatch_v1_graph: Any | None = None


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


def canonical_center_world_z(terrain_map: TerrainMap, q: int, r: int) -> float:
    """
    §11.3 canonical tile-center height: elevation * elevation_step in world coordinates.

    Uses TerrainMap elevation_base so world Z matches the heightfield IR
    (equivalent to tile_world_z).
    """
    return tile_world_z(terrain_map, q, r)


def hex_apothem(*, radius: float = DEFAULT_HEX_RADIUS) -> float:
    """Distance from hex center to midpoint of a shared edge."""
    return radius * math.sqrt(3) / 2.0


def canonical_single_hill_rise_fraction(
    u: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    Approved 7-hex hill *decay* fraction at radial param u in [0, 1].

    u=0 at tile center (decay=0, rise=1), u=1 at edge midpoint (apothem).
    Returns 1 - smootherstep(u * apothem / hill_radius); decreases toward the edge.
    """
    if u <= 0.0:
        return 1.0
    apothem = hex_apothem(radius=radius)
    hill_radius = radius * influence_radius_factor
    if hill_radius <= 0.0:
        return 0.0
    t = max(0.0, min(1.0, u * apothem / hill_radius))
    return 1.0 - perlin_smootherstep(t)


def canonical_rise_at_edge_midpoint(
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Fraction of elevation delta reached at edge midpoint (≈0.69357 for default constants)."""
    return canonical_single_hill_rise_fraction(
        1.0,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )


def canonical_profile_progress_fraction(
    u: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    Monotonic progress 0→1 from tile center to edge midpoint along the approved
    7-hex single-hill cross-section.

    Inverts center-outward hill decay: progress = (rise(0) - rise(u)) / (rise(0) - rise(1)).
    No clamp-to-constant: rise(u) strictly exceeds rise(1) for u in (0, 1).
    """
    if u <= 0.0:
        return 0.0
    if u >= 1.0:
        return 1.0
    rise_at_center = canonical_single_hill_rise_fraction(
        0.0,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    rise_at_mid = canonical_single_hill_rise_fraction(
        1.0,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    rise_u = canonical_single_hill_rise_fraction(
        u,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    denom = rise_at_center - rise_at_mid
    if denom <= 1e-12:
        return u
    return (rise_at_center - rise_u) / denom


def canonical_edge_profile_z(
    z_self: float,
    z_neighbor: float,
    u: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    §11 canonical center→edge-midpoint profile for one tile toward a smooth neighbor.

    z(u=0) = z_self; z(u=1) = z_mid = z_low + delta * rise_at_mid.
    Between endpoints follows the approved 7-hex single-hill cross-section (monotonic,
    no overshoot beyond [z_self, z_mid] on the low side / [z_mid, z_self] on the high side).
    """
    if u <= 0.0:
        return z_self
    z_low = min(z_self, z_neighbor)
    z_high = max(z_self, z_neighbor)
    delta = z_high - z_low
    if delta <= 1e-12:
        return z_self
    rise_at_mid = canonical_rise_at_edge_midpoint(
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    z_mid = z_low + delta * rise_at_mid
    progress = canonical_profile_progress_fraction(
        min(1.0, u),
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    if z_self <= z_neighbor:
        return z_low + (z_mid - z_low) * progress
    return z_high - (z_high - z_mid) * progress


def canonical_smooth_edge_midpoint_z(
    q_a: int,
    r_a: int,
    q_b: int,
    r_b: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Shared edge-midpoint height from the §11 canonical profile (u=1)."""
    z_a = canonical_center_world_z(model.map, q_a, r_a)
    z_b = canonical_center_world_z(model.map, q_b, r_b)
    return canonical_edge_profile_z(
        z_a,
        z_b,
        1.0,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )


def _baseline_direction_for_physical_edge(physical_edge: int) -> int:
    return (5 - physical_edge) % 6


def _smooth_neighbor_across_physical_edge(
    q: int,
    r: int,
    physical_edge: int,
    model: TerrainModel,
) -> tuple[int, int] | None:
    """Neighbor tile across physical_edge when the edge is smooth, else None."""
    direction = _baseline_direction_for_physical_edge(physical_edge)
    dq, dr = NEIGHBOR_DIRS[direction]
    q_b, r_b = handdrawn_to_baseline_axial(q, r)
    nq, nr = baseline_to_handdrawn_axial(q_b + dq, r_b + dr)
    if (nq, nr) not in model.map.tiles:
        return None
    edge_key = sorted_edge_key((q, r), (nq, nr))
    for edge in model.smooth_edges:
        if sorted_edge_key(edge.tile_a, edge.tile_b) == edge_key:
            return (nq, nr)
    return None


def _median_param_center_to_edge_midpoint(
    lx: float,
    ly: float,
    sector: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float | None:
    """
    Return u in [0, 1] when (lx, ly) lies on the center→edge-midpoint median of sector.

    u=0 at tile center, u=1 at the outer-edge midpoint. None if off the median.
    """
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx, cy = corner_xy_local(cj, radius)
    mx = 0.5 * (bx + cx)
    my = 0.5 * (by + cy)
    mm2 = mx * mx + my * my
    if mm2 <= 1e-18:
        return None
    cross = lx * my - ly * mx
    scale = radius * max(math.hypot(lx, ly), math.hypot(mx, my), radius)
    if abs(cross) > MID_EDGE_MEDIAN_COLLINEARITY_EPSILON * scale:
        return None
    u = (lx * mx + ly * my) / mm2
    if u < -1e-9 or u > 1.0 + 1e-9:
        return None
    return max(0.0, min(1.0, u))


def _sector_barycentric_ab_from_local(
    lx: float,
    ly: float,
    sector: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float, float, float] | None:
    """Return (a, b, radial, edge_t) in sector triangle; radial=a+b."""
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx, cy = corner_xy_local(cj, radius)
    det = bx * cy - by * cx
    if abs(det) <= 1e-18:
        return None
    a = (lx * cy - ly * cx) / det
    b = (ly * bx - lx * by) / det
    radial = a + b
    if radial <= 1e-12:
        return 0.0, 0.0, 0.0, 0.5
    if a < -1e-9 or b < -1e-9 or radial > 1.0 + 1e-9:
        return None
    return a, b, radial, b / radial


def _sector_radial_edge_t_from_local(
    lx: float,
    ly: float,
    sector: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float] | None:
    """
    Barycentric coords in sector triangle: radial in [0, 1] to outer edge, edge_t in [0, 1].
    """
    parsed = _sector_barycentric_ab_from_local(lx, ly, sector, radius=radius)
    if parsed is None:
        return None
    _a, _b, radial, edge_t = parsed
    return radial, edge_t


def _sector_u_from_barycentric(a: float, b: float) -> float:
    """Canonical profile parameter: 0 at center, 1 at edge midpoint (a=b=0.5)."""
    return min(1.0, 2.0 * min(a, b))


def _sector_lateral_weight(
    edge_t: float,
    *,
    profile: str = DEFAULT_SECTOR_PATCH_LATERAL_PROFILE,
) -> float:
    """Legacy weight 1 on sector median, 0 on sides (used by shelf diagnostic only)."""
    d = abs(edge_t - 0.5) * 2.0
    if d >= 1.0:
        return 0.0
    if profile == "quadratic":
        return 1.0 - d * d
    if profile == "cubic":
        return 1.0 - d * d * d
    t = 1.0 - d
    if profile in ("smoothstep", "smootherstep"):
        return perlin_smootherstep(t)
    return t


def _sector_lateral_hermite_weights(edge_t: float) -> tuple[float, float, float]:
    """
    Weights for (sideK0, spine, sideK1) with value 1 and zero derivative at
    edge_t = 0, 0.5, and 1.
    """
    if edge_t <= 0.5:
        t = edge_t * 2.0
        h = perlin_smootherstep(t)
        return 1.0 - h, h, 0.0
    t = (edge_t - 0.5) * 2.0
    h = perlin_smootherstep(t)
    return 0.0, 1.0 - h, h


def _shared_corner_height_at_vertex(
    wx: float,
    wy: float,
    q: int,
    r: int,
    corner_index: int,
    model: TerrainModel,
) -> float:
    """Single-valued corner height: SSC target_z when applicable, else component corner height."""
    corner_key = pos_key(wx, wy)
    for ssc in model.ssc_corners:
        if ssc.corner_world == corner_key:
            return ssc.target_z
    return model.corner_heights[(q, r, corner_index)]


def _center_to_corner_side_z(
    z_center: float,
    z_corner: float,
    radial: float,
) -> float:
    """Explicit center→corner side curve (smootherstep, exact at endpoints)."""
    if radial <= 0.0:
        return z_center
    if radial >= 1.0:
        return z_corner
    blend = perlin_smootherstep(radial)
    return z_center + (z_corner - z_center) * blend


def _tile_has_smooth_neighbor(
    q: int,
    r: int,
    model: TerrainModel,
) -> bool:
    for sector in range(6):
        if _smooth_neighbor_across_physical_edge(q, r, sector, model) is not None:
            return True
    return False


def _sample_smooth_sector_transfinite_patch(
    wx: float,
    wy: float,
    lx: float,
    ly: float,
    q: int,
    r: int,
    sector: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    §11 spine-anchored transfinite sector patch for smooth-facing sectors.

    Laterally blends sideK0(r), canonical spine(r), sideK1(r) with Hermite weights.
    Outer-edge samples use SharedEdgeCurve when available. No legacy radial kernel.
    """
    z_center = canonical_center_world_z(model.map, q, r)
    neighbor = _smooth_neighbor_across_physical_edge(q, r, sector, model)
    if neighbor is None:
        return z_center

    parsed = _sector_barycentric_ab_from_local(lx, ly, sector, radius=radius)
    if parsed is None:
        return z_center
    a, b, radial, edge_t = parsed
    if radial <= 1e-12:
        return z_center

    shared_z = shared_edge_z_at(model, pos_key(wx, wy))
    if shared_z is not None and radial >= 1.0 - 1e-9:
        return shared_z

    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx, cy = corner_xy_local(cj, radius)
    tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
    z_k0 = _shared_corner_height_at_vertex(
        tile_cx + bx, tile_cy + by, q, r, ci, model
    )
    z_k1 = _shared_corner_height_at_vertex(
        tile_cx + cx, tile_cy + cy, q, r, cj, model
    )

    side_k0 = _center_to_corner_side_z(z_center, z_k0, radial)
    side_k1 = _center_to_corner_side_z(z_center, z_k1, radial)

    nq, nr = neighbor
    z_neighbor = canonical_center_world_z(model.map, nq, nr)
    u = _sector_u_from_barycentric(a, b)
    z_spine = canonical_edge_profile_z(
        z_center,
        z_neighbor,
        u,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )

    w0, w_mid, w1 = _sector_lateral_hermite_weights(edge_t)
    return w0 * side_k0 + w_mid * z_spine + w1 * side_k1


def _sector_u_from_local(
    lx: float,
    ly: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    """Normalized center→edge-midpoint distance (0 at center, 1 at apothem)."""
    ap = hex_apothem(radius=radius)
    if ap <= 1e-18:
        return 0.0
    return min(1.0, math.hypot(lx, ly) / ap)


def _compute_radial_base_height(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Pre-SSC radial 2.2 kernel height (smooth-domain weighted mean)."""
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
    ssc_corners = detect_ssc_corners(terrain_map, cliff_edges, radius=radius)

    model = TerrainModel(
        map=terrain_map,
        smooth_edges=smooth_edges,
        cliff_edges=cliff_edges,
        domains=domains,
        tile_domain=tile_domain,
        corner_heights=corner_heights,
        cliff_edge_graph=cliff_edge_graph,
        ssc_corners=ssc_corners,
    )
    shared_curves, shared_lookup = build_shared_edge_curves(model, radius=radius)
    model.shared_edge_curves = shared_curves
    model.shared_edge_z_lookup = shared_lookup
    from eom_hexpatch_surface import build_hexpatch_bundle

    model.hexpatch_bundle = build_hexpatch_bundle(
        model,
        radius=radius,
    )
    from eom_hexpatch_v1_graph import build_hexpatch_v1_graph

    model.hexpatch_v1_graph = build_hexpatch_v1_graph(
        model,
        radius=radius,
    )
    return model


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


def _baseline_neighbor_direction(from_tile: tuple[int, int], to_tile: tuple[int, int]) -> int:
    q_b_from, r_b_from = handdrawn_to_baseline_axial(*from_tile)
    q_b_to, r_b_to = handdrawn_to_baseline_axial(*to_tile)
    dq = q_b_to - q_b_from
    dr = r_b_to - r_b_from
    for index, direction in enumerate(NEIGHBOR_DIRS):
        if direction == (dq, dr):
            return index
    raise ValueError(f"{to_tile} is not a baseline neighbor of {from_tile}")


def _physical_edge_for_baseline_neighbor(direction: int) -> int:
    return (5 - direction) % 6


def _corner_index_on_tile(
    q: int,
    r: int,
    corner_world: tuple[float, float],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> int:
    target = pos_key(*corner_world)
    for corner_index in range(6):
        cwx, cwy = handdrawn_corner_world_xy(q, r, corner_index, radius)
        if pos_key(cwx, cwy) == target:
            return corner_index
    raise ValueError(f"tile {(q, r)} does not touch corner {corner_world}")


def detect_ssc_corners(
    terrain_map: TerrainMap,
    cliff_edges: list[ResolvedEdge],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> list[SscCornerRecord]:
    """Find interior corners with exactly one incident cliff edge (SSC topology)."""
    cliff_pairs = _build_cliff_neighbor_pairs(cliff_edges)
    seen_corner_keys: set[tuple[float, float]] = set()
    records: list[SscCornerRecord] = []

    for q, r in sorted(terrain_map.tiles):
        for _corner_index in range(6):
            cwx, cwy = handdrawn_corner_world_xy(q, r, _corner_index, radius)
            corner_key = pos_key(cwx, cwy)
            if corner_key in seen_corner_keys:
                continue
            seen_corner_keys.add(corner_key)

            sharing = _tiles_touching_corner(terrain_map, cwx, cwy, radius=radius)
            if len(sharing) != 3:
                continue

            cliff_pairs_at_corner: list[tuple[tuple[int, int], tuple[int, int]]] = []
            for index_a in range(3):
                for index_b in range(index_a + 1, 3):
                    tile_a = sharing[index_a]
                    tile_b = sharing[index_b]
                    if frozenset((tile_a, tile_b)) in cliff_pairs:
                        cliff_pairs_at_corner.append((tile_a, tile_b))

            if len(cliff_pairs_at_corner) != 1:
                continue

            cliff_a, cliff_b = cliff_pairs_at_corner[0]
            bridge = next(tile for tile in sharing if tile not in (cliff_a, cliff_b))
            elevations = [tile_world_z(terrain_map, tq, tr) for tq, tr in sharing]
            target_z = sum(elevations) / float(len(elevations))
            corner_index_by_tile = tuple(
                sorted(
                    (
                        tq,
                        tr,
                        _corner_index_on_tile(tq, tr, corner_key, radius=radius),
                    )
                    for tq, tr in sharing
                )
            )
            records.append(
                SscCornerRecord(
                    corner_world=corner_key,
                    cliff_a=cliff_a,
                    cliff_b=cliff_b,
                    bridge=bridge,
                    target_z=target_z,
                    corner_index_by_tile=corner_index_by_tile,
                )
            )

    records.sort(key=lambda record: (record.corner_world, record.cliff_a, record.cliff_b))
    return records


_SSC_DEFORMATION_SAMPLE_COUNT = 0


def reset_ssc_deformation_audit() -> None:
    global _SSC_DEFORMATION_SAMPLE_COUNT
    _SSC_DEFORMATION_SAMPLE_COUNT = 0


def ssc_deformation_audit() -> dict[str, Any]:
    return {
        "deformation_radius_factor": DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR,
        "affected_sample_count": _SSC_DEFORMATION_SAMPLE_COUNT,
    }


def _ssc_falloff_weight(
    dist_from_corner: float,
    *,
    radius: float,
    deformation_radius_factor: float,
) -> float:
    """1.0 at the corner vertex, 0.0 at the deformation zone boundary."""
    zone = deformation_radius_factor * radius
    if zone <= 0.0 or dist_from_corner >= zone:
        return 0.0
    t = dist_from_corner / zone
    return 1.0 - perlin_smootherstep(t)


def _sample_at_tile_sector_corner(
    lx: float,
    ly: float,
    sector: int,
    *,
    radius: float,
    epsilon: float = SSC_CORNER_VERTEX_EPSILON,
) -> bool:
    """True when the local sample lies on either corner vertex of the mesh sector."""
    for corner_index in (sector, (sector + 1) % 6):
        bx, by = corner_xy_local(corner_index, radius)
        if math.hypot(lx - bx, ly - by) <= epsilon:
            return True
    return False


def _ssc_participating_smooth_sectors(
    q: int,
    r: int,
    ssc: SscCornerRecord,
) -> tuple[int, ...]:
    corner_index = ssc.corner_index_for(q, r)
    if corner_index is None:
        return ()
    candidates = ((corner_index - 1) % 6, corner_index)
    return tuple(
        sector
        for sector in candidates
        if _ssc_sector_allows_deformation(q, r, sector, ssc)
    )


def _ssc_cliff_sector_at_corner(cliff_physical_edge: int, corner_index: int) -> int:
    if cliff_physical_edge == corner_index:
        return corner_index
    if cliff_physical_edge == (corner_index - 1) % 6:
        return (corner_index - 1) % 6
    raise ValueError(
        f"cliff physical edge {cliff_physical_edge} does not meet corner {corner_index}"
    )


def _ssc_sector_allows_deformation(
    q: int,
    r: int,
    sector: int,
    ssc: SscCornerRecord,
) -> bool:
    corner_index = ssc.corner_index_for(q, r)
    if corner_index is None:
        return False
    if sector not in ((corner_index - 1) % 6, corner_index):
        return False
    if (q, r) == ssc.bridge:
        return True
    if (q, r) == ssc.cliff_a:
        cliff_neighbor = ssc.cliff_b
    elif (q, r) == ssc.cliff_b:
        cliff_neighbor = ssc.cliff_a
    else:
        return False
    cliff_edge = _physical_edge_for_baseline_neighbor(
        _baseline_neighbor_direction((q, r), cliff_neighbor)
    )
    cliff_sector = _ssc_cliff_sector_at_corner(cliff_edge, corner_index)
    return sector != cliff_sector


def _apply_ssc_corner_boundary_deformation(
    wx: float,
    wy: float,
    q: int,
    r: int,
    sector: int,
    base_height: float,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    deformation_radius_factor: float = DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR,
    at_sector_corner: bool = False,
) -> float:
    """
    Apply SSC deformation as an explicit corner boundary condition.

    Participating smooth sectors evaluate to exactly ``target_z`` at the shared
    corner vertex. Away from the corner, height falls off toward the radial
    base height within the bounded deformation zone.
    """
    global _SSC_DEFORMATION_SAMPLE_COUNT
    if not model.ssc_corners:
        return base_height

    best_weight = 0.0
    best_height = base_height
    for ssc in model.ssc_corners:
        if not _ssc_sector_allows_deformation(q, r, sector, ssc):
            continue
        cwx, cwy = ssc.corner_world
        dist = math.hypot(wx - cwx, wy - cwy)
        if pos_key(wx, wy) == ssc.corner_world:
            _SSC_DEFORMATION_SAMPLE_COUNT += 1
            return ssc.target_z

        weight = _ssc_falloff_weight(
            dist,
            radius=radius,
            deformation_radius_factor=deformation_radius_factor,
        )
        if weight <= 0.0:
            continue
        deformed = ssc.target_z + (1.0 - weight) * (base_height - ssc.target_z)
        if weight > best_weight:
            best_weight = weight
            best_height = deformed

    if best_weight > 1e-9:
        _SSC_DEFORMATION_SAMPLE_COUNT += 1
    return best_height


def _audit_ssc_radial_base_height(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Audit-only alias for sample_base_radial_height (pre-SSC radial 2.2 kernel)."""
    return sample_base_radial_height(
        wx,
        wy,
        q,
        r,
        model,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )


def _ssc_corner_topology(
    ssc: SscCornerRecord,
    model: TerrainModel,
) -> dict[str, Any]:
    """Audit-only summary of tile roles and incident edge transitions at an SSC corner."""
    terrain_map = model.map
    cliff_pair = (ssc.cliff_a, ssc.cliff_b)
    sharing = [ssc.cliff_a, ssc.cliff_b, ssc.bridge]
    incident_tiles: list[dict[str, Any]] = []
    for tq, tr in sharing:
        elevation = terrain_map.tiles[(tq, tr)]
        incident_tiles.append(
            {
                "tile": (tq, tr),
                "elevation": elevation,
                "world_z": tile_world_z(terrain_map, tq, tr),
                "role": (
                    "bridge"
                    if (tq, tr) == ssc.bridge
                    else "cliff_endpoint"
                ),
                "corner_index": ssc.corner_index_for(tq, tr),
            }
        )

    smooth_pairs: list[dict[str, Any]] = []
    for index_a in range(3):
        for index_b in range(index_a + 1, 3):
            tile_a = sharing[index_a]
            tile_b = sharing[index_b]
            ordered = sorted((tile_a, tile_b))
            if ordered == sorted(cliff_pair):
                continue
            elevation_a = terrain_map.tiles[tile_a]
            elevation_b = terrain_map.tiles[tile_b]
            smooth_pairs.append(
                {
                    "tile_a": tile_a,
                    "tile_b": tile_b,
                    "elevation_a": elevation_a,
                    "elevation_b": elevation_b,
                    "delta": abs(elevation_a - elevation_b),
                }
            )

    cliff_elevation_a = terrain_map.tiles[ssc.cliff_a]
    cliff_elevation_b = terrain_map.tiles[ssc.cliff_b]
    return {
        "incident_tiles": incident_tiles,
        "cliff_pair": {
            "tile_a": ssc.cliff_a,
            "tile_b": ssc.cliff_b,
            "elevation_a": cliff_elevation_a,
            "elevation_b": cliff_elevation_b,
            "delta": abs(cliff_elevation_a - cliff_elevation_b),
        },
        "smooth_pairs": smooth_pairs,
        "bridge": ssc.bridge,
    }


def _ssc_diagnose_sector_sample(
    ssc: SscCornerRecord,
    q: int,
    r: int,
    sector: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    deformation_radius_factor: float = DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR,
    at_sector_corner_input: bool = False,
) -> dict[str, Any]:
    """Audit-only per-sector diagnostic at the SSC corner world position."""
    cwx, cwy = ssc.corner_world
    corner_index = ssc.corner_index_for(q, r)
    tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
    lx = cwx - tile_cx
    ly = cwy - tile_cy
    computed_corner_xy = (
        handdrawn_corner_world_xy(q, r, corner_index, radius)
        if corner_index is not None
        else (None, None)
    )
    computed_corner_key = (
        pos_key(*computed_corner_xy) if corner_index is not None else None
    )
    at_sector_corner_detected = (
        _sample_at_tile_sector_corner(lx, ly, sector, radius=radius)
        if corner_index is not None
        else False
    )
    wx, wy = cwx, cwy
    dist_to_corner = math.hypot(wx - cwx, wy - cwy)
    deformation_zone = deformation_radius_factor * radius
    falloff_weight = _ssc_falloff_weight(
        dist_to_corner,
        radius=radius,
        deformation_radius_factor=deformation_radius_factor,
    )
    base_height = _audit_ssc_radial_base_height(
        cwx, cwy, q, r, model, radius=radius
    )

    incident_corner_sectors = (
        ((corner_index - 1) % 6, corner_index) if corner_index is not None else ()
    )
    cliff_sector: int | None = None
    tile_role = "unknown"
    participating = False
    deformation_applied = False
    deformation_mode = "skipped"
    skip_reason = ""

    if corner_index is None:
        skip_reason = "tile does not touch this SSC corner"
    elif sector not in incident_corner_sectors:
        skip_reason = (
            f"sector {sector} is not incident at corner_index {corner_index} "
            f"(incident sectors {incident_corner_sectors})"
        )
    elif (q, r) == ssc.bridge:
        tile_role = "bridge"
        participating = True
    elif (q, r) in (ssc.cliff_a, ssc.cliff_b):
        tile_role = "cliff_endpoint"
        cliff_neighbor = ssc.cliff_b if (q, r) == ssc.cliff_a else ssc.cliff_a
        cliff_baseline_dir = _baseline_neighbor_direction((q, r), cliff_neighbor)
        cliff_physical_edge = _physical_edge_for_baseline_neighbor(cliff_baseline_dir)
        cliff_sector = _ssc_cliff_sector_at_corner(cliff_physical_edge, corner_index)
        if sector == cliff_sector:
            skip_reason = (
                f"cliff sector {sector} on cliff edge {cliff_physical_edge} "
                f"(cliff neighbor {cliff_neighbor})"
            )
        else:
            participating = True
    else:
        skip_reason = f"tile ({q},{r}) is not one of the three SSC incident tiles"

    at_this_ssc_corner = pos_key(wx, wy) == ssc.corner_world
    expected_height = base_height
    if participating:
        if at_this_ssc_corner:
            deformation_applied = True
            deformation_mode = "exact_bc"
            expected_height = ssc.target_z
        elif falloff_weight > 0.0:
            deformation_applied = True
            deformation_mode = "falloff"
            expected_height = ssc.target_z + (1.0 - falloff_weight) * (
                base_height - ssc.target_z
            )
        else:
            skip_reason = (
                f"outside deformation zone (dist {dist_to_corner:.6e} >= "
                f"zone {deformation_zone:.6e})"
            )

    sampled_height = sample_smooth_domain_surface_world(
        cwx,
        cwy,
        q,
        r,
        model,
        radius=radius,
        sector=sector,
        at_sector_corner=at_sector_corner_input,
    )

    sector_corner_vertex = (
        sector
        if corner_index is not None and sector == corner_index
        else ((sector + 1) % 6 if corner_index is not None else None)
    )

    return {
        "tile": (q, r),
        "elevation": model.map.tiles[(q, r)],
        "tile_role": tile_role,
        "corner_index": corner_index,
        "sector": sector,
        "sector_corner_vertex": sector_corner_vertex,
        "incident_corner_sectors": incident_corner_sectors,
        "cliff_sector_excluded": cliff_sector,
        "participating_smooth_sector": participating,
        "sample_world_xy": (cwx, cwy),
        "computed_corner_xy": computed_corner_xy,
        "computed_corner_key": computed_corner_key,
        "ssc_corner_key": ssc.corner_world,
        "corner_key_matches": computed_corner_key == ssc.corner_world,
        "local_xy": (lx, ly),
        "dist_to_ssc_corner": dist_to_corner,
        "deformation_zone_radius": deformation_zone,
        "at_sector_corner_input": at_sector_corner_input,
        "at_sector_corner_detected": at_sector_corner_detected,
        "at_this_ssc_corner": at_this_ssc_corner,
        "radial_base_height": base_height,
        "corner_bc_z": ssc.target_z,
        "falloff_weight": falloff_weight,
        "deformation_applied": deformation_applied,
        "deformation_mode": deformation_mode,
        "deformation_skip_reason": skip_reason,
        "expected_height": expected_height,
        "sampled_height": sampled_height,
        "error_from_corner_bc_z": sampled_height - ssc.target_z,
        "error_from_expected": sampled_height - expected_height,
    }


def _ssc_diagnose_excluded_sectors(
    ssc: SscCornerRecord,
    q: int,
    r: int,
    model: TerrainModel,
) -> list[dict[str, Any]]:
    """Audit-only: cliff sectors at the corner that are intentionally excluded."""
    corner_index = ssc.corner_index_for(q, r)
    if corner_index is None:
        return []
    incident = ((corner_index - 1) % 6, corner_index)
    excluded: list[dict[str, Any]] = []
    for sector in incident:
        if _ssc_sector_allows_deformation(q, r, sector, ssc):
            continue
        cliff_sector: int | None = None
        reason = "not a participating smooth sector"
        if (q, r) in (ssc.cliff_a, ssc.cliff_b):
            cliff_neighbor = ssc.cliff_b if (q, r) == ssc.cliff_a else ssc.cliff_a
            cliff_baseline_dir = _baseline_neighbor_direction((q, r), cliff_neighbor)
            cliff_physical_edge = _physical_edge_for_baseline_neighbor(cliff_baseline_dir)
            cliff_sector = _ssc_cliff_sector_at_corner(cliff_physical_edge, corner_index)
            reason = (
                f"cliff sector {sector} excluded (cliff edge {cliff_physical_edge}, "
                f"cliff neighbor {cliff_neighbor})"
            )
        excluded.append(
            {
                "tile": (q, r),
                "sector": sector,
                "corner_index": corner_index,
                "cliff_sector": cliff_sector,
                "reason": reason,
            }
        )
    return excluded


def audit_ssc_corner_continuity(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    height_epsilon: float = 1e-9,
) -> dict[str, Any]:
    """
    Verify surface_1(corner) == surface_2(corner) for every participating
    smooth sector at each SSC corner. Returns rich per-corner diagnostics.
    """
    corner_reports: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []

    for ssc in model.ssc_corners:
        cwx, cwy = ssc.corner_world
        topology = _ssc_corner_topology(ssc, model)
        participating_reports: list[dict[str, Any]] = []
        excluded_reports: list[dict[str, Any]] = []

        for tq, tr, _corner_index in ssc.corner_index_by_tile:
            excluded_reports.extend(_ssc_diagnose_excluded_sectors(ssc, tq, tr, model))
            for sector in _ssc_participating_smooth_sectors(tq, tr, ssc):
                participating_reports.append(
                    _ssc_diagnose_sector_sample(
                        ssc,
                        tq,
                        tr,
                        sector,
                        model,
                        radius=radius,
                        at_sector_corner_input=True,
                    )
                )

        sampled_heights = [
            report["sampled_height"] for report in participating_reports
        ]
        if not sampled_heights:
            spread = 0.0
            continuity_ok = True
        else:
            spread = max(sampled_heights) - min(sampled_heights)
            continuity_ok = spread <= height_epsilon

        corner_report = {
            "corner_world": ssc.corner_world,
            "corner_key": ssc.corner_world,
            "corner_bc_z": ssc.target_z,
            "topology": topology,
            "participating_sample_reports": participating_reports,
            "excluded_sector_reports": excluded_reports,
            "height_spread": spread,
            "continuity_ok": continuity_ok,
        }
        corner_reports.append(corner_report)
        if not continuity_ok:
            failures.append(corner_report)

    passed_count = sum(1 for report in corner_reports if report["continuity_ok"])
    return {
        "corner_count": len(model.ssc_corners),
        "passed_count": passed_count,
        "failure_count": len(failures),
        "continuity_ok": len(failures) == 0,
        "corners": corner_reports,
        "failures": failures,
    }


def _audit_classify_corner_world(
    wx: float,
    wy: float,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    """Audit-only geometric classification of a lattice corner world position."""
    terrain_map = model.map
    touching = _tiles_touching_corner(terrain_map, wx, wy, radius=radius)
    touching_count = len(touching)
    cliff_pairs = _build_cliff_neighbor_pairs(model.cliff_edges)
    cliff_pair_count = 0
    for index_a in range(touching_count):
        for index_b in range(index_a + 1, touching_count):
            if frozenset((touching[index_a], touching[index_b])) in cliff_pairs:
                cliff_pair_count += 1
    corner_key = pos_key(wx, wy)
    is_ssc = touching_count == 3 and cliff_pair_count == 1
    return {
        "corner_world": corner_key,
        "touching_count": touching_count,
        "touching_tiles": touching,
        "cliff_pair_count": cliff_pair_count,
        "is_ssc": is_ssc,
        "is_perimeter": touching_count < 3,
    }


def _audit_classify_smooth_edge_mismatch(
    endpoint_a: dict[str, Any],
    endpoint_b: dict[str, Any],
    max_abs_z_diff: float,
    height_epsilon: float,
) -> str:
    if max_abs_z_diff <= height_epsilon:
        return "merged_no_gap"
    if endpoint_a["is_perimeter"] or endpoint_b["is_perimeter"]:
        return "overlay_skirt_adjacent"
    if endpoint_a["cliff_pair_count"] >= 1 or endpoint_b["cliff_pair_count"] >= 1:
        return "cliff_or_ssc_adjacent"
    return "true_smooth_mismatch"


def audit_smooth_edge_continuity(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = 1e-5,
    worst_count: int = 20,
) -> dict[str, Any]:
    """
    Read-only audit: sample both tiles along each resolved smooth edge and compare Z.

    Uses the same sampler and sector/corner flags as mesh generation. A per-point
    abs(zA - zB) > height_epsilon predicts a split vertex (visible gap) at that edge.
    """
    edge_reports: list[dict[str, Any]] = []
    category_counts: dict[str, int] = {
        "merged_no_gap": 0,
        "overlay_skirt_adjacent": 0,
        "cliff_or_ssc_adjacent": 0,
        "true_smooth_mismatch": 0,
    }
    global_max_abs_z_diff = 0.0
    mismatch_count = 0

    for edge in model.smooth_edges:
        tile_a = edge.tile_a
        tile_b = edge.tile_b
        edge_a = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_a, tile_b)
        )
        edge_b = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_b, tile_a)
        )
        c0x, c0y = handdrawn_corner_world_xy(*tile_a, edge_a, radius)
        c1x, c1y = handdrawn_corner_world_xy(*tile_a, (edge_a + 1) % 6, radius)
        endpoint_a = _audit_classify_corner_world(c0x, c0y, model, radius=radius)
        endpoint_b = _audit_classify_corner_world(c1x, c1y, model, radius=radius)

        max_abs_z_diff = 0.0
        peak_subdiv_index = 0
        peak_world_xy = (c0x, c0y)
        peak_z_a = 0.0
        peak_z_b = 0.0
        endpoint_z_diffs: list[dict[str, Any]] = []
        sample_diffs: list[float] = []

        denom = float(subdiv)
        for step_k in range(subdiv + 1):
            t = float(step_k) / denom
            wx = c0x * (1.0 - t) + c1x * t
            wy = c0y * (1.0 - t) + c1y * t
            at_corner = step_k == 0 or step_k == subdiv
            point_key = pos_key(wx, wy)
            curve_z = shared_edge_z_at(model, point_key)
            if curve_z is not None:
                z_a = curve_z
                z_b = curve_z
            else:
                z_a = sample_smooth_domain_surface_world(
                    wx,
                    wy,
                    tile_a[0],
                    tile_a[1],
                    model,
                    radius=radius,
                    sector=edge_a,
                    at_sector_corner=at_corner,
                )
                z_b = sample_smooth_domain_surface_world(
                    wx,
                    wy,
                    tile_b[0],
                    tile_b[1],
                    model,
                    radius=radius,
                    sector=edge_b,
                    at_sector_corner=at_corner,
                )
            abs_diff = abs(z_a - z_b)
            sample_diffs.append(abs_diff)
            if abs_diff > max_abs_z_diff:
                max_abs_z_diff = abs_diff
                peak_subdiv_index = step_k
                peak_world_xy = (wx, wy)
                peak_z_a = z_a
                peak_z_b = z_b
            if at_corner:
                endpoint_z_diffs.append(
                    {
                        "subdiv_index": step_k,
                        "world_xy": pos_key(wx, wy),
                        "z_a": z_a,
                        "z_b": z_b,
                        "abs_z_diff": abs_diff,
                    }
                )

        category = _audit_classify_smooth_edge_mismatch(
            endpoint_a,
            endpoint_b,
            max_abs_z_diff,
            height_epsilon,
        )
        category_counts[category] += 1
        global_max_abs_z_diff = max(global_max_abs_z_diff, max_abs_z_diff)
        if max_abs_z_diff > height_epsilon:
            mismatch_count += 1

        edge_reports.append(
            {
                "tile_a": tile_a,
                "tile_b": tile_b,
                "elevation_a": edge.elevation_a,
                "elevation_b": edge.elevation_b,
                "delta": edge.delta,
                "physical_edge_a": edge_a,
                "physical_edge_b": edge_b,
                "endpoint_a": endpoint_a,
                "endpoint_b": endpoint_b,
                "touches_ssc": endpoint_a["is_ssc"] or endpoint_b["is_ssc"],
                "max_abs_z_diff": max_abs_z_diff,
                "peak_subdiv_index": peak_subdiv_index,
                "peak_world_xy": pos_key(*peak_world_xy),
                "peak_at_endpoint": peak_subdiv_index == 0 or peak_subdiv_index == subdiv,
                "peak_z_a": peak_z_a,
                "peak_z_b": peak_z_b,
                "endpoint_z_diffs": endpoint_z_diffs,
                "category": category,
            }
        )

    worst_edges = sorted(
        edge_reports,
        key=lambda report: report["max_abs_z_diff"],
        reverse=True,
    )[:worst_count]

    return {
        "smooth_edge_count": len(model.smooth_edges),
        "height_epsilon": height_epsilon,
        "subdiv": subdiv,
        "global_max_abs_z_diff": global_max_abs_z_diff,
        "mismatch_count": mismatch_count,
        "category_counts": category_counts,
        "worst_edges": worst_edges,
        "edges": edge_reports,
    }


def domain_for_tile(model: TerrainModel, q: int, r: int) -> SmoothingDomain:
    domain_id = model.tile_domain[(q, r)]
    for domain in model.domains:
        if domain.domain_id == domain_id:
            return domain
    raise KeyError(f"no smoothing domain {domain_id} for tile {(q, r)}")


def sample_base_radial_height(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Pre-SSC radial 2.2 kernel height for a tile's smooth domain."""
    return _compute_radial_base_height(
        wx,
        wy,
        q,
        r,
        model,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )


def sample_smooth_domain_surface_world(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    ssc_deformation_radius_factor: float = DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR,
    sector: int | None = None,
    at_sector_corner: bool = False,
) -> float:
    """
    Smooth-domain top-surface height sampler.

    Smooth-facing sectors use the §11 spine-anchored transfinite patch (no legacy
    radial kernel on side lines). Cliff-facing sectors keep the radial kernel.
    All-cliff tiles use flat z_center. SSC corner BC unchanged.
    """
    tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
    lx = wx - tile_cx
    ly = wy - tile_cy
    z_center = canonical_center_world_z(model.map, q, r)
    if sector is None:
        if math.hypot(lx, ly) < 1e-12:
            return z_center
        sector = _point_sector(lx, ly)
        at_sector_corner = _sample_at_tile_sector_corner(lx, ly, sector, radius=radius)
    elif not at_sector_corner:
        at_sector_corner = _sample_at_tile_sector_corner(lx, ly, sector, radius=radius)

    if not _tile_has_smooth_neighbor(q, r, model):
        height = z_center
    elif _smooth_neighbor_across_physical_edge(q, r, sector, model) is not None:
        height = _sample_smooth_sector_transfinite_patch(
            wx,
            wy,
            lx,
            ly,
            q,
            r,
            sector,
            model,
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
    else:
        height = _compute_radial_base_height(
            wx,
            wy,
            q,
            r,
            model,
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )

    return _apply_ssc_corner_boundary_deformation(
        wx,
        wy,
        q,
        r,
        sector,
        height,
        model,
        radius=radius,
        deformation_radius_factor=ssc_deformation_radius_factor,
        at_sector_corner=at_sector_corner,
    )


def _pinned_smooth_corner_z(
    wx: float,
    wy: float,
    tile_a: tuple[int, int],
    physical_edge_a: int,
    tile_b: tuple[int, int],
    physical_edge_b: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    """Shared corner Z for smooth-edge endpoints (SSC BC or symmetric average)."""
    corner_key = pos_key(wx, wy)
    for ssc in model.ssc_corners:
        if ssc.corner_world == corner_key:
            return ssc.target_z
    z_a = sample_smooth_domain_surface_world(
        wx,
        wy,
        tile_a[0],
        tile_a[1],
        model,
        radius=radius,
        sector=physical_edge_a,
        at_sector_corner=True,
    )
    z_b = sample_smooth_domain_surface_world(
        wx,
        wy,
        tile_b[0],
        tile_b[1],
        model,
        radius=radius,
        sector=physical_edge_b,
        at_sector_corner=True,
    )
    return (z_a + z_b) * 0.5


def _shared_edge_endpoint_falloff(x: float) -> float:
    """Falloff for endpoint pin correction: 1 - smootherstep(x) on [0, 1], else 0."""
    if x < 0.0 or x > 1.0:
        return 0.0
    return 1.0 - perlin_smootherstep(x)


def build_shared_edge_curves(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    endpoint_band_factor: float = DEFAULT_SHARED_EDGE_ENDPOINT_BAND_FACTOR,
) -> tuple[
    dict[tuple[tuple[int, int], tuple[int, int]], SharedEdgeCurve],
    dict[tuple[float, float], float],
]:
    """
    Build one SharedEdgeCurve per resolved smooth edge.

    Interior samples: symmetric average of both tiles' pre-SSC base radial heights B(t).
    Endpoints: pinned via _pinned_smooth_corner_z, with correction confined to endpoint bands:
      curve(t) = B(t) + f(t/band)*(P0 - B(0)) + f((1-t)/band)*(P1 - B(1))
    where f(x) = 1 - perlin_smootherstep(x) on [0, 1] and 0 otherwise.
    """
    curves: dict[tuple[tuple[int, int], tuple[int, int]], SharedEdgeCurve] = {}
    lookup: dict[tuple[float, float], float] = {}
    denom = float(subdiv)
    band = endpoint_band_factor

    for edge in model.smooth_edges:
        tile_a = edge.tile_a
        tile_b = edge.tile_b
        edge_key = sorted_edge_key(tile_a, tile_b)
        edge_a = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_a, tile_b)
        )
        edge_b = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_b, tile_a)
        )
        c0x, c0y = handdrawn_corner_world_xy(*tile_a, edge_a, radius)
        c1x, c1y = handdrawn_corner_world_xy(*tile_a, (edge_a + 1) % 6, radius)

        base_z_by_step: list[float] = []
        world_xy_by_step: list[tuple[float, float]] = []
        for step_k in range(subdiv + 1):
            t = float(step_k) / denom
            wx = c0x * (1.0 - t) + c1x * t
            wy = c0y * (1.0 - t) + c1y * t
            world_xy_by_step.append((wx, wy))
            z_a_base = sample_base_radial_height(
                wx,
                wy,
                tile_a[0],
                tile_a[1],
                model,
                radius=radius,
            )
            z_b_base = sample_base_radial_height(
                wx,
                wy,
                tile_b[0],
                tile_b[1],
                model,
                radius=radius,
            )
            base_z_by_step.append((z_a_base + z_b_base) * 0.5)

        p0 = _pinned_smooth_corner_z(
            c0x,
            c0y,
            tile_a,
            edge_a,
            tile_b,
            edge_b,
            model,
            radius=radius,
        )
        p1 = _pinned_smooth_corner_z(
            c1x,
            c1y,
            tile_a,
            edge_a,
            tile_b,
            edge_b,
            model,
            radius=radius,
        )
        b0 = base_z_by_step[0]
        b1 = base_z_by_step[subdiv]
        mid_step = subdiv // 2
        canonical_mid_z = canonical_smooth_edge_midpoint_z(
            tile_a[0],
            tile_a[1],
            tile_b[0],
            tile_b[1],
            model,
            radius=radius,
        )

        samples_list: list[tuple[tuple[float, float], float]] = []
        corner_z_0 = p0
        corner_z_1 = p1

        for step_k in range(subdiv + 1):
            t = float(step_k) / denom
            wx, wy = world_xy_by_step[step_k]
            base_z = base_z_by_step[step_k]
            if step_k == 0:
                z = p0
            elif step_k == subdiv:
                z = p1
            elif step_k == mid_step:
                z = canonical_mid_z
            else:
                f0 = _shared_edge_endpoint_falloff(t / band) if band > 0.0 else 0.0
                f1 = _shared_edge_endpoint_falloff((1.0 - t) / band) if band > 0.0 else 0.0
                z = base_z + f0 * (p0 - b0) + f1 * (p1 - b1)

            point_key = pos_key(wx, wy)
            samples_list.append((point_key, z))
            lookup[point_key] = z

        curves[edge_key] = SharedEdgeCurve(
            edge_key=edge_key,
            tile_a=tile_a,
            tile_b=tile_b,
            physical_edge_a=edge_a,
            physical_edge_b=edge_b,
            corner_z_0=corner_z_0,
            corner_z_1=corner_z_1,
            samples=tuple(samples_list),
        )

    return curves, lookup


def shared_edge_z_at(
    model: TerrainModel,
    point_key: tuple[float, float],
) -> float | None:
    """Return canonical shared-edge Z at a pos_key world-XY sample, or None if off smooth edges."""
    return model.shared_edge_z_lookup.get(point_key)


def audit_shared_edge_curve_preservation(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    endpoint_band_factor: float = DEFAULT_SHARED_EDGE_ENDPOINT_BAND_FACTOR,
    height_epsilon: float = 1e-5,
) -> dict[str, Any]:
    """
    Verify SharedEdgeCurve construction invariants:
    - endpoints equal pinned P0/P1 exactly
    - edge midpoint equals §11 canonical mid-edge height within epsilon
    - interior band (band < t < 1-band) equals B(t) exactly
    """
    denom = float(subdiv)
    band = endpoint_band_factor
    midpoint_index = subdiv // 2
    endpoint_failures: list[dict[str, Any]] = []
    midpoint_failures: list[dict[str, Any]] = []
    interior_failures: list[dict[str, Any]] = []
    preserved_midpoints: list[dict[str, Any]] = []

    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        curve = model.shared_edge_curves[edge_key]
        edge_a = curve.physical_edge_a
        edge_b = curve.physical_edge_b
        c0x, c0y = handdrawn_corner_world_xy(*edge.tile_a, edge_a, radius)
        c1x, c1y = handdrawn_corner_world_xy(
            *edge.tile_a, (edge_a + 1) % 6, radius
        )

        p0 = _pinned_smooth_corner_z(
            c0x,
            c0y,
            edge.tile_a,
            edge_a,
            edge.tile_b,
            edge_b,
            model,
            radius=radius,
        )
        p1 = _pinned_smooth_corner_z(
            c1x,
            c1y,
            edge.tile_a,
            edge_a,
            edge.tile_b,
            edge_b,
            model,
            radius=radius,
        )

        endpoint_z_0 = curve.samples[0][1]
        endpoint_z_1 = curve.samples[subdiv][1]
        if endpoint_z_0 != p0 or endpoint_z_1 != p1:
            endpoint_failures.append(
                {
                    "edge_key": edge_key,
                    "p0": p0,
                    "curve_z_0": endpoint_z_0,
                    "p1": p1,
                    "curve_z_1": endpoint_z_1,
                }
            )

        t_mid = float(midpoint_index) / denom
        wx_mid = c0x * (1.0 - t_mid) + c1x * t_mid
        wy_mid = c0y * (1.0 - t_mid) + c1y * t_mid
        canonical_mid = canonical_smooth_edge_midpoint_z(
            edge.tile_a[0],
            edge.tile_a[1],
            edge.tile_b[0],
            edge.tile_b[1],
            model,
            radius=radius,
        )
        curve_mid = curve.samples[midpoint_index][1]
        mid_error = abs(curve_mid - canonical_mid)
        midpoint_report = {
            "edge_key": edge_key,
            "tile_a": edge.tile_a,
            "tile_b": edge.tile_b,
            "delta": edge.delta,
            "world_xy": pos_key(wx_mid, wy_mid),
            "canonical_mid": canonical_mid,
            "curve_mid": curve_mid,
            "abs_error": mid_error,
        }
        preserved_midpoints.append(midpoint_report)
        if mid_error > height_epsilon:
            midpoint_failures.append(midpoint_report)

        for step_k in range(1, subdiv):
            if step_k == midpoint_index:
                continue
            t = float(step_k) / denom
            if band < t < 1.0 - band:
                wx = c0x * (1.0 - t) + c1x * t
                wy = c0y * (1.0 - t) + c1y * t
                base_z = (
                    sample_base_radial_height(
                        wx, wy, edge.tile_a[0], edge.tile_a[1], model, radius=radius
                    )
                    + sample_base_radial_height(
                        wx, wy, edge.tile_b[0], edge.tile_b[1], model, radius=radius
                    )
                ) * 0.5
                curve_z = curve.samples[step_k][1]
                if abs(curve_z - base_z) > height_epsilon:
                    interior_failures.append(
                        {
                            "edge_key": edge_key,
                            "subdiv_index": step_k,
                            "t": t,
                            "base_z": base_z,
                            "curve_z": curve_z,
                            "abs_error": abs(curve_z - base_z),
                        }
                    )

    preserved_midpoints.sort(key=lambda report: report["abs_error"], reverse=True)

    return {
        "smooth_edge_count": len(model.smooth_edges),
        "endpoint_band_factor": endpoint_band_factor,
        "height_epsilon": height_epsilon,
        "endpoint_ok": len(endpoint_failures) == 0,
        "midpoint_ok": len(midpoint_failures) == 0,
        "interior_ok": len(interior_failures) == 0,
        "preservation_ok": (
            len(endpoint_failures) == 0
            and len(midpoint_failures) == 0
            and len(interior_failures) == 0
        ),
        "endpoint_failures": endpoint_failures,
        "midpoint_failures": midpoint_failures,
        "interior_failures": interior_failures,
        "worst_midpoint_preservation": preserved_midpoints[:20],
    }


def audit_mid_edge_canonical_profile(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    height_epsilon: float = 1e-5,
    worst_count: int = 20,
) -> dict[str, Any]:
    """
    §11 slice A audit: center→edge-midpoint median matches the canonical 7-hex profile.

    Compares sample_smooth_domain_surface_world() against the closed-form reference on
    each smooth edge from both tiles; reports maximum deviation and midpoint agreement.
    """
    global_max_deviation = 0.0
    profile_failures: list[dict[str, Any]] = []
    midpoint_tile_mismatches: list[dict[str, Any]] = []
    sample_count = 0
    half = subdiv // 2
    u_steps = half if half > 0 else 1

    for edge in model.smooth_edges:
        tile_a = edge.tile_a
        tile_b = edge.tile_b
        edge_a = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_a, tile_b)
        )
        edge_b = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_b, tile_a)
        )
        c0x, c0y = handdrawn_corner_world_xy(*tile_a, edge_a, radius)
        c1x, c1y = handdrawn_corner_world_xy(*tile_a, (edge_a + 1) % 6, radius)
        wx_mid = 0.5 * (c0x + c1x)
        wy_mid = 0.5 * (c0y + c1y)
        mid_key = pos_key(wx_mid, wy_mid)

        z_mid_a = sample_smooth_domain_surface_world(
            wx_mid,
            wy_mid,
            tile_a[0],
            tile_a[1],
            model,
            radius=radius,
            sector=edge_a,
            at_sector_corner=False,
        )
        z_mid_b = sample_smooth_domain_surface_world(
            wx_mid,
            wy_mid,
            tile_b[0],
            tile_b[1],
            model,
            radius=radius,
            sector=edge_b,
            at_sector_corner=False,
        )
        mid_tile_diff = abs(z_mid_a - z_mid_b)
        global_max_deviation = max(global_max_deviation, mid_tile_diff)
        if mid_tile_diff > height_epsilon:
            midpoint_tile_mismatches.append(
                {
                    "tile_a": tile_a,
                    "tile_b": tile_b,
                    "delta": edge.delta,
                    "world_xy": mid_key,
                    "z_a": z_mid_a,
                    "z_b": z_mid_b,
                    "abs_diff": mid_tile_diff,
                }
            )

        for q, r, sector, neighbor in (
            (tile_a[0], tile_a[1], edge_a, tile_b),
            (tile_b[0], tile_b[1], edge_b, tile_a),
        ):
            tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
            ci = sector
            cj = (sector + 1) % 6
            bx, by = corner_xy_local(ci, radius)
            cx, cy = corner_xy_local(cj, radius)
            mx = 0.5 * (bx + cx)
            my = 0.5 * (by + cy)
            z_self = canonical_center_world_z(model.map, q, r)
            z_neighbor = canonical_center_world_z(model.map, neighbor[0], neighbor[1])

            for step_k in range(u_steps + 1):
                u = float(step_k) / float(u_steps)
                wx = tile_cx + u * mx
                wy = tile_cy + u * my
                expected = _independent_profile_z_at_u(
                    z_self,
                    z_neighbor,
                    u,
                    radius=radius,
                    influence_radius_factor=influence_radius_factor,
                )
                actual = sample_smooth_domain_surface_world(
                    wx,
                    wy,
                    q,
                    r,
                    model,
                    radius=radius,
                    sector=sector,
                    at_sector_corner=False,
                )
                sample_count += 1
                deviation = abs(actual - expected)
                global_max_deviation = max(global_max_deviation, deviation)
                if deviation > height_epsilon:
                    profile_failures.append(
                        {
                            "tile": (q, r),
                            "neighbor": neighbor,
                            "delta": edge.delta,
                            "u": u,
                            "world_xy": pos_key(wx, wy),
                            "expected": expected,
                            "actual": actual,
                            "abs_deviation": deviation,
                        }
                    )

    profile_failures.sort(key=lambda row: row["abs_deviation"], reverse=True)

    return {
        "smooth_edge_count": len(model.smooth_edges),
        "sample_count": sample_count,
        "height_epsilon": height_epsilon,
        "global_max_deviation": global_max_deviation,
        "profile_ok": len(profile_failures) == 0,
        "midpoint_tile_agreement_ok": len(midpoint_tile_mismatches) == 0,
        "invariant_ok": len(profile_failures) == 0 and len(midpoint_tile_mismatches) == 0,
        "profile_failures": profile_failures[:worst_count],
        "midpoint_tile_mismatches": midpoint_tile_mismatches,
        "worst_profile_failures": profile_failures[:worst_count],
    }


def audit_transverse_spike_seams(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    worst_count: int = 20,
) -> dict[str, Any]:
    """
    Measure |Z_median - Z_transverse| at adjacent grid samples in smooth-facing sectors.

    Large values indicate one-vertex-wide lifted seams (needle ridges). Compare
    global_max_spike against a pre-sector-field baseline (~0.07-0.08 on delta-1 edges).
    """
    global_max_spike = 0.0
    spike_reports: list[dict[str, Any]] = []
    sample_pairs = 0

    for q, r in sorted(model.map.tiles):
        for sector in range(6):
            if _smooth_neighbor_across_physical_edge(q, r, sector, model) is None:
                continue
            tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
            ci = sector
            cj = (sector + 1) % 6
            bx, by = corner_xy_local(ci, radius)
            cx, cy = corner_xy_local(cj, radius)

            for step_k in range(1, subdiv // 2 + 1):
                si = step_k
                sj = step_k
                denom = float(subdiv)
                wb = float(si) / denom
                wc = float(sj) / denom
                wx_m = tile_cx + wb * bx + wc * cx
                wy_m = tile_cy + wb * by + wc * cy
                z_m = sample_smooth_domain_surface_world(
                    wx_m,
                    wy_m,
                    q,
                    r,
                    model,
                    radius=radius,
                    sector=sector,
                    at_sector_corner=False,
                )

                for si_t, sj_t in ((si + 1, sj), (si, sj + 1)):
                    if si_t + sj_t > subdiv:
                        continue
                    wb_t = float(si_t) / denom
                    wc_t = float(sj_t) / denom
                    wx_t = tile_cx + wb_t * bx + wc_t * cx
                    wy_t = tile_cy + wb_t * by + wc_t * cy
                    z_t = sample_smooth_domain_surface_world(
                        wx_t,
                        wy_t,
                        q,
                        r,
                        model,
                        radius=radius,
                        sector=sector,
                        at_sector_corner=False,
                    )
                    sample_pairs += 1
                    spike = abs(z_m - z_t)
                    if spike > global_max_spike:
                        global_max_spike = spike
                    if spike > 1e-9:
                        spike_reports.append(
                            {
                                "tile": (q, r),
                                "sector": sector,
                                "median_step": step_k,
                                "transverse": (si_t, sj_t),
                                "world_median": pos_key(wx_m, wy_m),
                                "world_transverse": pos_key(wx_t, wy_t),
                                "z_median": z_m,
                                "z_transverse": z_t,
                                "abs_spike": spike,
                            }
                        )

    spike_reports.sort(key=lambda row: row["abs_spike"], reverse=True)

    return {
        "subdiv": subdiv,
        "sample_pairs": sample_pairs,
        "global_max_spike": global_max_spike,
        "spike_reports": spike_reports[:worst_count],
        "worst_spikes": spike_reports[:worst_count],
    }


def _independent_delta1_profile_z_at_u(
    u: float,
    *,
    elevation_step: float = DEFAULT_ELEVATION_STEP,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """
    Duplicate closed-form delta-1 low-tile profile for audit ground truth.

    Intentionally does not call canonical_edge_profile_z or its helpers so the audit
    cannot pass by comparing the implementation against itself.
    """
    return _independent_profile_z_at_u(
        0.0,
        elevation_step,
        u,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )


def _independent_profile_z_at_u(
    z_self: float,
    z_neighbor: float,
    u: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    """Audit-only duplicate of the §11 profile; does not call production helpers."""
    if u <= 0.0:
        return z_self
    z_low = min(z_self, z_neighbor)
    z_high = max(z_self, z_neighbor)
    delta = z_high - z_low
    if delta <= 1e-12:
        return z_self
    apothem = radius * math.sqrt(3.0) / 2.0
    hill_radius = radius * influence_radius_factor
    if hill_radius <= 0.0:
        return z_self
    t_mid = max(0.0, min(1.0, apothem / hill_radius))
    rise_at_mid = 1.0 - perlin_smootherstep(t_mid)
    z_mid = z_low + delta * rise_at_mid
    if u >= 1.0:
        return z_mid
    t_u = max(0.0, min(1.0, u * apothem / hill_radius))
    rise_u = 1.0 - perlin_smootherstep(t_u)
    rise_at_center = 1.0
    denom = rise_at_center - rise_at_mid
    if denom <= 1e-12:
        progress = u
    else:
        progress = (rise_at_center - rise_u) / denom
    if z_self <= z_neighbor:
        return z_low + (z_mid - z_low) * progress
    return z_high - (z_high - z_mid) * progress


def audit_independent_delta1_profile(
    *,
    elevation_step: float = DEFAULT_ELEVATION_STEP,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    height_epsilon: float = 1e-4,
) -> dict[str, Any]:
    """
    Verify canonical_edge_profile_z against an independent duplicate formula at anchor u.

    Anchor tolerances are absolute; values are computed from first principles, not from
    the production profile helpers.
    """
    z_low = 0.0
    z_high = elevation_step
    anchor_us = (0.0, 0.25, 0.50, 0.75, 1.0)
    samples: list[dict[str, Any]] = []
    max_deviation = 0.0
    failures: list[dict[str, Any]] = []

    for u in anchor_us:
        expected = _independent_delta1_profile_z_at_u(
            u,
            elevation_step=elevation_step,
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
        actual = canonical_edge_profile_z(
            z_low,
            z_high,
            u,
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
        deviation = abs(actual - expected)
        max_deviation = max(max_deviation, deviation)
        row = {
            "u": u,
            "expected": expected,
            "actual": actual,
            "abs_deviation": deviation,
        }
        samples.append(row)
        if deviation > height_epsilon:
            failures.append(row)

    return {
        "height_epsilon": height_epsilon,
        "elevation_step": elevation_step,
        "samples": samples,
        "max_deviation": max_deviation,
        "profile_ok": len(failures) == 0,
        "failures": failures,
    }


def audit_canonical_profile_shape(
    *,
    elevation_step: float = DEFAULT_ELEVATION_STEP,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    subdiv: int = 40,
    height_epsilon: float = 1e-9,
) -> dict[str, Any]:
    """Monotonicity, overshoot, center, and midpoint checks for delta ±1."""
    z_low = 0.0
    z_high = elevation_step
    rise_at_mid = canonical_rise_at_edge_midpoint(
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    z_mid = z_low + elevation_step * rise_at_mid

    center_low = canonical_edge_profile_z(z_low, z_high, 0.0, radius=radius)
    center_high = canonical_edge_profile_z(z_high, z_low, 0.0, radius=radius)
    mid_low = canonical_edge_profile_z(z_low, z_high, 1.0, radius=radius)
    mid_high = canonical_edge_profile_z(z_high, z_low, 1.0, radius=radius)

    monotonic_violations: list[dict[str, Any]] = []
    overshoot_violations: list[dict[str, Any]] = []
    prev_low = center_low
    prev_high = center_high

    for step in range(1, subdiv + 1):
        u = float(step) / float(subdiv)
        z_l = canonical_edge_profile_z(z_low, z_high, u, radius=radius)
        z_h = canonical_edge_profile_z(z_high, z_low, u, radius=radius)

        if z_l + height_epsilon < prev_low:
            monotonic_violations.append({"side": "low", "u": u, "z": z_l, "prev": prev_low})
        if z_h - height_epsilon > prev_high:
            monotonic_violations.append({"side": "high", "u": u, "z": z_h, "prev": prev_high})
        prev_low = z_l
        prev_high = z_h

        if z_l < z_low - height_epsilon or z_l > z_mid + height_epsilon:
            overshoot_violations.append({"side": "low", "u": u, "z": z_l})
        if z_h > z_high + height_epsilon or z_h < z_mid - height_epsilon:
            overshoot_violations.append({"side": "high", "u": u, "z": z_h})

    return {
        "center_low_ok": abs(center_low - z_low) <= height_epsilon,
        "center_high_ok": abs(center_high - z_high) <= height_epsilon,
        "midpoint_low_ok": abs(mid_low - z_mid) <= height_epsilon,
        "midpoint_high_ok": abs(mid_high - z_mid) <= height_epsilon,
        "rise_at_mid": rise_at_mid,
        "z_mid": z_mid,
        "monotonic_ok": len(monotonic_violations) == 0,
        "overshoot_ok": len(overshoot_violations) == 0,
        "shape_ok": (
            abs(center_low - z_low) <= height_epsilon
            and abs(center_high - z_high) <= height_epsilon
            and abs(mid_low - z_mid) <= height_epsilon
            and abs(mid_high - z_mid) <= height_epsilon
            and len(monotonic_violations) == 0
            and len(overshoot_violations) == 0
        ),
        "monotonic_violations": monotonic_violations[:10],
        "overshoot_violations": overshoot_violations[:10],
    }


def audit_sector_shelf_diagnostic(
    model: TerrainModel,
    tile: tuple[int, int],
    sector: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> dict[str, Any]:
    """Report spine, sides, and patch height along the sector median."""
    q, r = tile
    neighbor = _smooth_neighbor_across_physical_edge(q, r, sector, model)
    if neighbor is None:
        return {"tile": tile, "sector": sector, "error": "not a smooth-facing sector"}

    tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, radius)
    cx, cy = corner_xy_local(cj, radius)
    z_self = canonical_center_world_z(model.map, q, r)
    z_neighbor = canonical_center_world_z(model.map, neighbor[0], neighbor[1])
    rows: list[dict[str, Any]] = []

    for step_k in range(subdiv // 2 + 1):
        si = step_k
        sj = step_k
        denom = float(subdiv)
        wb = float(si) / denom
        wc = float(sj) / denom
        wx = tile_cx + wb * bx + wc * cx
        wy = tile_cy + wb * by + wc * cy
        lx = wx - tile_cx
        ly = wy - tile_cy
        parsed = _sector_barycentric_ab_from_local(lx, ly, sector, radius=radius)
        if parsed is None:
            continue
        a, b, radial, edge_t = parsed
        u = _sector_u_from_barycentric(a, b)
        z_spine = canonical_edge_profile_z(
            z_self,
            z_neighbor,
            u,
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
        final = sample_smooth_domain_surface_world(
            wx,
            wy,
            q,
            r,
            model,
            radius=radius,
            sector=sector,
            at_sector_corner=False,
        )
        rows.append(
            {
                "step": step_k,
                "u": u,
                "radial": radial,
                "edge_t": edge_t,
                "spine": z_spine,
                "final": final,
                "spine_delta": final - z_spine,
            }
        )

    return {
        "tile": tile,
        "sector": sector,
        "neighbor": neighbor,
        "delta": abs(z_self - z_neighbor),
        "median_samples": rows,
    }


def audit_center_corner_ray_artifacts(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    height_epsilon: float = 1e-5,
    worst_count: int = 20,
) -> dict[str, Any]:
    """
    Measure star/ray indicators on smooth-facing sectors.

    star_shell_asymmetry: |Z_median - Z_side| at the same radial shell (lower is smoother).
    side_radial_decouple: |Z_side - radial_kernel| on center→corner side lines (should be
    > 0 on sloped edges, confirming side lines no longer follow the legacy radial kernel).
    side_curve_error: |Z_side - explicit_side_curve| (should be ~0).
    """
    global_max_star_shell = 0.0
    global_max_side_radial_decouple = 0.0
    global_max_side_curve_error = 0.0
    sample_pairs = 0
    reports: list[dict[str, Any]] = []

    for q, r in sorted(model.map.tiles):
        z_center = canonical_center_world_z(model.map, q, r)
        tile_cx, tile_cy = handdrawn_center_world_xy(q, r, radius)
        for sector in range(6):
            if _smooth_neighbor_across_physical_edge(q, r, sector, model) is None:
                continue
            ci = sector
            cj = (sector + 1) % 6
            bx, by = corner_xy_local(ci, radius)
            cx, cy = corner_xy_local(cj, radius)
            z_k0 = _shared_corner_height_at_vertex(
                tile_cx + bx, tile_cy + by, q, r, ci, model
            )

            for step_k in range(1, subdiv // 2 + 1):
                denom = float(subdiv)
                wb_m = float(step_k) / denom
                wc_m = float(step_k) / denom
                wx_m = tile_cx + wb_m * bx + wc_m * cx
                wy_m = tile_cy + wb_m * by + wc_m * cy
                wb_s = float(step_k) / denom
                wc_s = 0.0
                wx_s = tile_cx + wb_s * bx + wc_s * cx
                wy_s = tile_cy + wb_s * by + wc_s * cy

                z_m = sample_smooth_domain_surface_world(
                    wx_m,
                    wy_m,
                    q,
                    r,
                    model,
                    radius=radius,
                    sector=sector,
                    at_sector_corner=False,
                )
                z_s = sample_smooth_domain_surface_world(
                    wx_s,
                    wy_s,
                    q,
                    r,
                    model,
                    radius=radius,
                    sector=sector,
                    at_sector_corner=False,
                )
                parsed_s = _sector_barycentric_ab_from_local(
                    wx_s - tile_cx,
                    wy_s - tile_cy,
                    sector,
                    radius=radius,
                )
                if parsed_s is None:
                    continue
                _a, _b, radial_s, _edge_t = parsed_s
                z_radial = _compute_radial_base_height(
                    wx_s,
                    wy_s,
                    q,
                    r,
                    model,
                    radius=radius,
                    influence_radius_factor=influence_radius_factor,
                )
                z_side_expected = _center_to_corner_side_z(z_center, z_k0, radial_s)

                sample_pairs += 1
                star = abs(z_m - z_s)
                decouple = abs(z_s - z_radial)
                side_err = abs(z_s - z_side_expected)
                global_max_star_shell = max(global_max_star_shell, star)
                global_max_side_radial_decouple = max(
                    global_max_side_radial_decouple, decouple
                )
                global_max_side_curve_error = max(global_max_side_curve_error, side_err)
                if star > height_epsilon or decouple > height_epsilon:
                    reports.append(
                        {
                            "tile": (q, r),
                            "sector": sector,
                            "radial_step": step_k,
                            "z_median": z_m,
                            "z_side": z_s,
                            "star_shell_asymmetry": star,
                            "side_radial_decouple": decouple,
                            "side_curve_error": side_err,
                        }
                    )

    reports.sort(key=lambda row: row["star_shell_asymmetry"], reverse=True)

    return {
        "subdiv": subdiv,
        "sample_pairs": sample_pairs,
        "global_max_star_shell": global_max_star_shell,
        "global_max_side_radial_decouple": global_max_side_radial_decouple,
        "global_max_side_curve_error": global_max_side_curve_error,
        "side_curve_ok": global_max_side_curve_error <= height_epsilon,
        "worst_star_shells": reports[:worst_count],
    }


def audit_sector_patch_falsification(
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    height_epsilon: float = 1e-4,
) -> dict[str, Any]:
    """Synthetic-map checks for sector-patch edge cases."""
    cases: list[dict[str, Any]] = []

    def check(name: str, json_text: str, predicate) -> None:
        built = build_terrain_model(json_text, radius=radius)
        ok, detail = predicate(built)
        cases.append({"case": name, "ok": ok, "detail": detail})

    # Flat delta-0 smooth edge
    check(
        "flat_delta_0",
        """
        {"id":"flat","orientation":"pointy_top_custom_axes","elevation_step":0.4,
         "edge_rule":{"cliff_if_abs_delta_greater_than":1},
         "tiles":[{"q":0,"r":0,"elevation":2},{"q":1,"r":0,"elevation":2}]}
        """,
        lambda m: (
            abs(
                sample_smooth_domain_surface_world(
                    *handdrawn_center_world_xy(0, 0, radius),
                    0,
                    0,
                    m,
                    radius=radius,
                    sector=0,
                )
                - 0.4
            )
            <= height_epsilon,
            "center height",
        ),
    )

    # Isolated high tile surrounded by cliffs (flat mesa)
    check(
        "isolated_cliff_mesa",
        """
        {"id":"mesa","orientation":"pointy_top_custom_axes","elevation_step":0.4,
         "edge_rule":{"cliff_if_abs_delta_greater_than":1},
         "tiles":[
           {"q":0,"r":0,"elevation":1},
           {"q":1,"r":0,"elevation":3},
           {"q":0,"r":1,"elevation":1},
           {"q":1,"r":1,"elevation":1}
         ]}
        """,
        lambda m: (
            not _tile_has_smooth_neighbor(1, 0, m)
            and abs(
                sample_smooth_domain_surface_world(
                    *handdrawn_center_world_xy(1, 0, radius),
                    1,
                    0,
                    m,
                    radius=radius,
                    sector=0,
                )
                - 0.8
            )
            <= height_epsilon,
            "all-cliff tile flat at z_center",
        ),
    )

    # SSS corner single-valued corner height
    def _sss_corner_heights_agree(m: TerrainModel) -> tuple[bool, str]:
        for q, r in sorted(m.map.tiles):
            for ci in range(6):
                cwx, cwy = handdrawn_corner_world_xy(q, r, ci, radius)
                corner_key = pos_key(cwx, cwy)
                sharing = _tiles_touching_corner(m.map, cwx, cwy, radius=radius)
                if len(sharing) != 3:
                    continue
                heights = [
                    m.corner_heights[
                        (tq, tr, _corner_index_on_tile(tq, tr, corner_key, radius=radius))
                    ]
                    for tq, tr in sharing
                ]
                spread = max(heights) - min(heights)
                if spread <= height_epsilon:
                    return True, f"corner {corner_key} shared height {heights[0]:.4f}"
        return False, "no 3-tile corner with agreeing heights"

    check(
        "sss_corner_single_valued",
        """
        {"id":"sss","orientation":"pointy_top_custom_axes","elevation_step":0.4,
         "edge_rule":{"cliff_if_abs_delta_greater_than":1},
         "tiles":[
           {"q":0,"r":0,"elevation":1},
           {"q":1,"r":0,"elevation":2},
           {"q":0,"r":1,"elevation":2}
         ]}
        """,
        _sss_corner_heights_agree,
    )

    # SSC continuity on built-in self-test topology
    check(
        "ssc_corner",
        """
        {"id":"ssc","orientation":"pointy_top_custom_axes","elevation_step":0.4,
         "edge_rule":{"cliff_if_abs_delta_greater_than":1},
         "tiles":[
           {"q":0,"r":0,"elevation":1},
           {"q":1,"r":0,"elevation":2},
           {"q":0,"r":1,"elevation":3}
         ]}
        """,
        lambda m: (
            audit_ssc_corner_continuity(m)["continuity_ok"],
            audit_ssc_corner_continuity(m),
        ),
    )

    # Opposite-delta adjacent smooth edges (ridge tile)
    check(
        "opposite_delta_adjacent",
        """
        {"id":"ridge","orientation":"pointy_top_custom_axes","elevation_step":0.4,
         "edge_rule":{"cliff_if_abs_delta_greater_than":1},
         "tiles":[
           {"q":0,"r":0,"elevation":1},
           {"q":1,"r":0,"elevation":2},
           {"q":2,"r":0,"elevation":1}
         ]}
        """,
        lambda m: (
            audit_mid_edge_canonical_profile(m)["invariant_ok"],
            "mid-edge profile on opposite deltas",
        ),
    )

    all_ok = all(row["ok"] for row in cases)
    return {"falsification_ok": all_ok, "cases": cases}


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
        "ssc_corner_count": len(model.ssc_corners),
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
        {"q":1,"r":0,"elevation":2},
        {"q":0,"r":1,"elevation":3}
      ]
    }
    """
    built = build_terrain_model(SAMPLE)
    summary = audit_summary(built)
    assert summary["tile_count"] == 3
    assert summary["cliff_edge_count"] == 1
    assert summary["smooth_edge_count"] == 2
    assert summary["smoothing_domain_count"] == 1
    assert summary["corner_height_count"] == 18
    x10, y10 = handdrawn_center_world_xy(1, 0)
    x01, y01 = handdrawn_center_world_xy(0, 1)
    assert x10 > 0 and abs(y10) < 1e-9
    assert x01 > 0 and y01 < 0
    ssc_audit = audit_ssc_corner_continuity(built)
    assert ssc_audit["corner_count"] == 1
    assert ssc_audit["continuity_ok"]
    smooth_edge_audit = audit_smooth_edge_continuity(built)
    assert smooth_edge_audit["category_counts"]["true_smooth_mismatch"] == 0
    assert smooth_edge_audit["mismatch_count"] == 0
    curve_preservation = audit_shared_edge_curve_preservation(built)
    assert curve_preservation["preservation_ok"]
    mid_edge_audit = audit_mid_edge_canonical_profile(built)
    assert mid_edge_audit["invariant_ok"]
    independent_profile = audit_independent_delta1_profile()
    assert independent_profile["profile_ok"], independent_profile
    shape_audit = audit_canonical_profile_shape()
    assert shape_audit["shape_ok"], shape_audit
    spike_audit = audit_transverse_spike_seams(built)
    assert spike_audit["global_max_spike"] < 0.02
    ray_audit = audit_center_corner_ray_artifacts(built)
    assert ray_audit["side_curve_ok"], ray_audit
    falsification = audit_sector_patch_falsification()
    assert falsification["falsification_ok"], falsification
    from eom_hexpatch_surface import audit_hexpatch_suite

    hexpatch_audit = audit_hexpatch_suite(built)
    assert hexpatch_audit["smooth_edge_height"]["ok"], hexpatch_audit["smooth_edge_height"]
    assert hexpatch_audit["center"]["ok"], hexpatch_audit["center"]
    assert hexpatch_audit["boundary_reproduction"]["ok"], hexpatch_audit["boundary_reproduction"]
    assert hexpatch_audit["g1_ribbons"]["ok"], hexpatch_audit["g1_ribbons"]
    from eom_hexpatch_v1_graph import (
        build_hexpatch_v1_graph,
        graph_fingerprint,
        validate_hexpatch_v1_graph,
    )

    v1_graph = built.hexpatch_v1_graph
    assert v1_graph is not None
    v1_validation = validate_hexpatch_v1_graph(built, v1_graph)
    assert v1_validation["ok"], v1_validation
    v1_rebuild = build_hexpatch_v1_graph(built)
    assert graph_fingerprint(v1_graph) == graph_fingerprint(v1_rebuild)
    shelf_diag = audit_sector_shelf_diagnostic(built, (1, 0), 3)
    print(
        "eom_terrain_math_core self-test passed:",
        summary,
        ssc_audit,
        smooth_edge_audit,
        curve_preservation,
        mid_edge_audit,
        independent_profile,
        shape_audit,
        spike_audit,
        ray_audit,
        falsification,
        hexpatch_audit,
        v1_validation,
        shelf_diag,
    )
