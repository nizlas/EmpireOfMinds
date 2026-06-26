# Empire of Minds — HexPatch surface evaluator (TERRAIN_MODEL §§12–13).
# SharedCorner / SharedRibbon / edge-distance Hermite transfinite patch + center bubble.

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    DEFAULT_SURFACE_SUBDIVISIONS,
    TerrainModel,
    canonical_center_world_z,
    canonical_edge_profile_z,
    canonical_rise_at_edge_midpoint,
    corner_xy_local,
    handdrawn_center_world_xy,
    handdrawn_corner_world_xy,
    hex_apothem,
    perlin_smootherstep,
    pos_key,
    sorted_edge_key,
    tile_world_z,
    _baseline_neighbor_direction,
    _build_smooth_adjacency,
    _corner_index_on_tile,
    _physical_edge_for_baseline_neighbor,
    _smooth_component_at_corner,
    _smooth_neighbor_across_physical_edge,
    _tiles_touching_corner,
)

CANONICAL_MIDPOINT_RISE = canonical_rise_at_edge_midpoint()
HEXPATCH_HEIGHT_EPSILON = 1e-5
HEXPATCH_G1_EPSILON = 2e-3
HEXPATCH_CROSS_DERIV_EPSILON = 2e-3
HEXPATCH_CENTER_DRIFT_WARN_FACTOR = 0.1
HEXPATCH_EDGE_DIST_EPSILON = 1e-9


@dataclass(frozen=True)
class SharedCornerKey:
    corner_world: tuple[float, float]
    component_tiles: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class SharedCornerRecord:
    key: SharedCornerKey
    height: float
    gradient: tuple[float, float]


@dataclass(frozen=True)
class SharedRibbonRecord:
    edge_key: tuple[tuple[int, int], tuple[int, int]]
    z_corner_0: float
    z_corner_1: float
    h_mid: float
    d_mid: float
    d_corner_0: float
    d_corner_1: float


@dataclass(frozen=True)
class PrivateLipRecord:
    z_corner_0: float
    z_corner_1: float


@dataclass(frozen=True)
class HexPatchTileEdges:
    smooth_ribbon: tuple[SharedRibbonRecord | None, ...]
    ribbon_reversed: tuple[bool, ...]
    cliff_lip: tuple[PrivateLipRecord | None, ...]


@dataclass
class HexPatchBundle:
    shared_corners: dict[SharedCornerKey, SharedCornerRecord]
    shared_ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord]
    tile_edges: dict[tuple[int, int], HexPatchTileEdges]
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey]


def _corner_component_key(
    model: TerrainModel,
    q: int,
    r: int,
    corner_index: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]] | None = None,
) -> SharedCornerKey:
    wx, wy = handdrawn_corner_world_xy(q, r, corner_index, radius)
    corner_world = pos_key(wx, wy)
    domain_id = model.tile_domain[(q, r)]
    domain_tiles_union: set[tuple[int, int]] = set()
    for domain in model.domains:
        if domain.domain_id == domain_id:
            domain_tiles_union.update(domain.tiles)
    sharing = _tiles_touching_corner(
        model.map,
        wx,
        wy,
        domain_tiles_union,
        radius=radius,
    )
    if not sharing:
        sharing = [(q, r)]
    if smooth_adjacency is None:
        smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    component = tuple(
        sorted(_smooth_component_at_corner((q, r), sharing, smooth_adjacency))
    )
    return SharedCornerKey(corner_world=corner_world, component_tiles=component)


def _ssc_target_at_corner(
    model: TerrainModel,
    corner_world: tuple[float, float],
) -> float | None:
    for ssc in model.ssc_corners:
        if ssc.corner_world == corner_world:
            return ssc.target_z
    return None


def _quadratic_edge_height(z0: float, h_mid: float, z1: float, t: float) -> float:
    if t <= 0.0:
        return z0
    if t >= 1.0:
        return z1
    l0 = 2.0 * (t - 0.5) * (t - 1.0)
    l_mid = 4.0 * t * (1.0 - t)
    l1 = 2.0 * t * (t - 0.5)
    return z0 * l0 + h_mid * l_mid + z1 * l1


def _quadratic_edge_slope_at_start(z0: float, h_mid: float, z1: float) -> float:
    return 4.0 * h_mid - 3.0 * z0 - z1


def _quadratic_edge_slope_at_end(z0: float, h_mid: float, z1: float) -> float:
    return z0 - 4.0 * h_mid + 3.0 * z1


def _orient_t(t: float, reversed_edge: bool) -> float:
    return 1.0 - t if reversed_edge else t


def _ribbon_b_t_oriented(ribbon: SharedRibbonRecord, t: float, reversed_edge: bool) -> float:
    return _ribbon_b_t(ribbon, _orient_t(t, reversed_edge))


def _ribbon_d_t_oriented(ribbon: SharedRibbonRecord, t: float, reversed_edge: bool) -> float:
    return _ribbon_d_t(ribbon, _orient_t(t, reversed_edge))


def _ribbon_b_t(ribbon: SharedRibbonRecord, t: float) -> float:
    return _clamped_smootherstep_half_blend(
        ribbon.z_corner_0,
        ribbon.h_mid,
        ribbon.z_corner_1,
        t,
    )


def _ribbon_d_t(ribbon: SharedRibbonRecord, t: float) -> float:
    return _clamped_smootherstep_half_blend(
        ribbon.d_corner_0,
        ribbon.d_mid,
        ribbon.d_corner_1,
        t,
    )


def _clamped_smootherstep_half_blend(
    v0: float,
    v_mid: float,
    v1: float,
    t: float,
) -> float:
    if t <= 0.0:
        return v0
    if t >= 1.0:
        return v1
    if t <= 0.5:
        u = t * 2.0
        blend = perlin_smootherstep(u)
        return v0 + (v_mid - v0) * blend
    u = (t - 0.5) * 2.0
    blend = perlin_smootherstep(u)
    return v_mid + (v1 - v_mid) * blend


def _ribbon_s_low(
    z_low: float,
    z_high: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> float:
    delta = z_high - z_low
    if delta <= 1e-12:
        return 0.0
    ap = hex_apothem(radius=radius)
    if ap <= 1e-18:
        return 0.0
    eps = 1e-6
    z_before = canonical_edge_profile_z(
        z_low,
        z_high,
        1.0 - eps,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    z_mid = canonical_edge_profile_z(
        z_low,
        z_high,
        1.0,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    return (z_mid - z_before) / (eps * ap)


def _ribbon_h_mid(
    z_a: float,
    z_b: float,
) -> float:
    z_low = min(z_a, z_b)
    z_high = max(z_a, z_b)
    if z_high - z_low <= 1e-12:
        return z_low
    return z_low + CANONICAL_MIDPOINT_RISE * (z_high - z_low)


def _solve_corner_gradient_lsq(
    slopes: list[tuple[tuple[float, float], float]],
) -> tuple[float, float]:
    if not slopes:
        return 0.0, 0.0
    if len(slopes) == 1:
        tx, ty = slopes[0][0]
        s = slopes[0][1]
        norm = math.hypot(tx, ty)
        if norm <= 1e-18:
            return 0.0, 0.0
        return s * tx / norm, s * ty / norm
    a11 = a12 = a22 = 0.0
    b1 = b2 = 0.0
    for (tx, ty), s in slopes:
        a11 += tx * tx
        a12 += tx * ty
        a22 += ty * ty
        b1 += s * tx
        b2 += s * ty
    det = a11 * a22 - a12 * a12
    if abs(det) < 1e-18:
        if abs(a11) + abs(a22) > 1e-18:
            g = b1 / a11 if abs(a11) >= abs(a22) else b2 / a22
            return g, 0.0
        return 0.0, 0.0
    return (
        (b1 * a22 - b2 * a12) / det,
        (a11 * b2 - a12 * b1) / det,
    )


def _edge_inward_normal(v0: tuple[float, float], v1: tuple[float, float]) -> tuple[float, float]:
    ex = v1[0] - v0[0]
    ey = v1[1] - v0[1]
    nx, ny = -ey, ex
    norm = math.hypot(nx, ny)
    if norm <= 1e-18:
        return 0.0, 0.0
    return nx / norm, ny / norm


def _edge_projection(
    px: float,
    py: float,
    v0: tuple[float, float],
    v1: tuple[float, float],
) -> tuple[float, float]:
    ex = v1[0] - v0[0]
    ey = v1[1] - v0[1]
    el2 = ex * ex + ey * ey
    if el2 <= 1e-18:
        return 0.0, 0.0
    t = ((px - v0[0]) * ex + (py - v0[1]) * ey) / el2
    t_clamped = max(0.0, min(1.0, t))
    proj_x = v0[0] + ex * t_clamped
    proj_y = v0[1] + ey * t_clamped
    nx, ny = _edge_inward_normal(v0, v1)
    signed_dist = (px - proj_x) * nx + (py - proj_y) * ny
    return t_clamped, signed_dist


def _collect_incident_smooth_slopes(
    model: TerrainModel,
    corner_key: SharedCornerKey,
    shared_ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord],
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> list[tuple[tuple[float, float], float]]:
    slopes: list[tuple[tuple[float, float], float]] = []
    seen_edges: set[tuple[tuple[int, int], tuple[int, int]]] = set()
    for tq, tr in corner_key.component_tiles:
        for ci in range(6):
            cwx, cwy = handdrawn_corner_world_xy(tq, tr, ci, radius)
            if pos_key(cwx, cwy) != corner_key.corner_world:
                continue
            neighbor = _smooth_neighbor_across_physical_edge(tq, tr, ci, model)
            if neighbor is None:
                continue
            edge_key = sorted_edge_key((tq, tr), neighbor)
            if edge_key in seen_edges:
                continue
            seen_edges.add(edge_key)
            ribbon = shared_ribbons.get(edge_key)
            if ribbon is None:
                continue
            cjx, cjy = handdrawn_corner_world_xy(tq, tr, (ci + 1) % 6, radius)
            if (tq, tr) == edge_key[0]:
                z0, z1 = ribbon.z_corner_0, ribbon.z_corner_1
                at_start = corner_key_by_tile.get((tq, tr, ci)) == corner_key
            else:
                z0, z1 = ribbon.z_corner_1, ribbon.z_corner_0
                at_start = corner_key_by_tile.get((tq, tr, (ci + 1) % 6)) == corner_key
            h_m = ribbon.h_mid
            if at_start:
                tx = cjx - cwx
                ty = cjy - cwy
                slope = _quadratic_edge_slope_at_start(z0, h_m, z1)
            else:
                tx = cwx - cjx
                ty = cwy - cjy
                slope = -_quadratic_edge_slope_at_end(z0, h_m, z1)
            norm = math.hypot(tx, ty)
            if norm <= 1e-18:
                continue
            slopes.append(((tx / norm, ty / norm), slope))
    return slopes


def build_hexpatch_bundle(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> HexPatchBundle:
    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    shared_corners: dict[SharedCornerKey, SharedCornerRecord] = {}
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey] = {}

    for q, r in sorted(model.map.tiles):
        for ci in range(6):
            key = _corner_component_key(
                model,
                q,
                r,
                ci,
                radius=radius,
                smooth_adjacency=smooth_adjacency,
            )
            corner_key_by_tile[(q, r, ci)] = key
            if key in shared_corners:
                continue
            ssc_z = _ssc_target_at_corner(model, key.corner_world)
            if ssc_z is not None:
                height = ssc_z
            else:
                elevations = [
                    tile_world_z(model.map, tq, tr) for tq, tr in key.component_tiles
                ]
                height = sum(elevations) / float(len(elevations))
            shared_corners[key] = SharedCornerRecord(
                key=key,
                height=height,
                gradient=(0.0, 0.0),
            )

    shared_ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord] = {}
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        if edge_key in shared_ribbons:
            continue
        z_a = canonical_center_world_z(model.map, *edge.tile_a)
        z_b = canonical_center_world_z(model.map, *edge.tile_b)
        h_mid = _ribbon_h_mid(z_a, z_b)
        z_low = min(z_a, z_b)
        d_mid = _ribbon_s_low(
            z_low,
            max(z_a, z_b),
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
        dir_a = _baseline_neighbor_direction(edge.tile_a, edge.tile_b)
        pe_a = _physical_edge_for_baseline_neighbor(dir_a)
        k0 = corner_key_by_tile[(edge.tile_a[0], edge.tile_a[1], pe_a)]
        k1 = corner_key_by_tile[(edge.tile_a[0], edge.tile_a[1], (pe_a + 1) % 6)]
        shared_ribbons[edge_key] = SharedRibbonRecord(
            edge_key=edge_key,
            z_corner_0=shared_corners[k0].height,
            z_corner_1=shared_corners[k1].height,
            h_mid=h_mid,
            d_mid=d_mid,
            d_corner_0=0.0,
            d_corner_1=0.0,
        )

    for key in list(shared_corners.keys()):
        slopes = _collect_incident_smooth_slopes(
            model,
            key,
            shared_ribbons,
            corner_key_by_tile,
            radius=radius,
        )
        gx, gy = _solve_corner_gradient_lsq(slopes)
        corner = shared_corners[key]
        shared_corners[key] = SharedCornerRecord(
            key=key,
            height=corner.height,
            gradient=(gx, gy),
        )

    for edge_key, ribbon in list(shared_ribbons.items()):
        tile_a, _tile_b = edge_key
        dir_a = _baseline_neighbor_direction(tile_a, edge_key[1])
        pe_a = _physical_edge_for_baseline_neighbor(dir_a)
        k0 = corner_key_by_tile[(tile_a[0], tile_a[1], pe_a)]
        k1 = corner_key_by_tile[(tile_a[0], tile_a[1], (pe_a + 1) % 6)]
        c0x, c0y = handdrawn_corner_world_xy(tile_a[0], tile_a[1], pe_a, radius)
        c1x, c1y = handdrawn_corner_world_xy(tile_a[0], tile_a[1], (pe_a + 1) % 6, radius)
        nx, ny = _edge_inward_normal((c0x, c0y), (c1x, c1y))
        g0 = shared_corners[k0].gradient
        g1 = shared_corners[k1].gradient
        shared_ribbons[edge_key] = SharedRibbonRecord(
            edge_key=edge_key,
            z_corner_0=ribbon.z_corner_0,
            z_corner_1=ribbon.z_corner_1,
            h_mid=ribbon.h_mid,
            d_mid=ribbon.d_mid,
            d_corner_0=g0[0] * nx + g0[1] * ny,
            d_corner_1=g1[0] * nx + g1[1] * ny,
        )

    tile_edges: dict[tuple[int, int], HexPatchTileEdges] = {}
    for q, r in sorted(model.map.tiles):
        smooth_slots: list[SharedRibbonRecord | None] = []
        reverse_slots: list[bool] = []
        cliff_slots: list[PrivateLipRecord | None] = []
        for pe in range(6):
            neighbor = _smooth_neighbor_across_physical_edge(q, r, pe, model)
            if neighbor is not None:
                edge_key = sorted_edge_key((q, r), neighbor)
                smooth_slots.append(shared_ribbons.get(edge_key))
                reverse_slots.append((q, r) != edge_key[0])
                cliff_slots.append(None)
            else:
                smooth_slots.append(None)
                reverse_slots.append(False)
                k0 = corner_key_by_tile[(q, r, pe)]
                k1 = corner_key_by_tile[(q, r, (pe + 1) % 6)]
                z0 = shared_corners[k0].height
                z1 = shared_corners[k1].height
                cliff_slots.append(PrivateLipRecord(z_corner_0=z0, z_corner_1=z1))
        tile_edges[(q, r)] = HexPatchTileEdges(
            smooth_ribbon=tuple(smooth_slots),
            ribbon_reversed=tuple(reverse_slots),
            cliff_lip=tuple(cliff_slots),
        )

    return HexPatchBundle(
        shared_corners=shared_corners,
        shared_ribbons=shared_ribbons,
        tile_edges=tile_edges,
        corner_key_by_tile=corner_key_by_tile,
    )


def _lip_b_t(lip: PrivateLipRecord, t: float) -> float:
    return lip.z_corner_0 + (lip.z_corner_1 - lip.z_corner_0) * t


def _hex_inward_distance(lx: float, ly: float, *, radius: float) -> tuple[list[tuple[float, float]], list[float]]:
    corners: list[tuple[float, float]] = []
    for ci in range(6):
        corners.append(corner_xy_local(ci, radius))
    dists: list[float] = []
    for ci in range(6):
        v0 = corners[ci]
        v1 = corners[(ci + 1) % 6]
        _t, signed = _edge_projection(lx, ly, v0, v1)
        dists.append(max(0.0, signed))
    return corners, dists


def _bubble_beta(lx: float, ly: float, *, radius: float) -> float:
    ap = hex_apothem(radius=radius)
    if ap <= 1e-18:
        return 1.0
    _corners, dists = _hex_inward_distance(lx, ly, radius=radius)
    beta = 1.0
    for dist in dists:
        t_norm = max(0.0, min(1.0, dist / ap))
        beta *= perlin_smootherstep(t_norm)
    center_beta = 1.0
    for ci in range(6):
        v0 = corner_xy_local(ci, radius)
        v1 = corner_xy_local((ci + 1) % 6, radius)
        _t, signed = _edge_projection(0.0, 0.0, v0, v1)
        t_norm = max(0.0, min(1.0, max(0.0, signed) / ap))
        center_beta *= perlin_smootherstep(t_norm)
    if center_beta <= 1e-18:
        return beta
    return beta / center_beta


def _evaluate_hexpatch_patch_local(
    lx: float,
    ly: float,
    tile_edges: HexPatchTileEdges,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    corners: list[tuple[float, float]] = [corner_xy_local(ci, radius) for ci in range(6)]
    value_sum = 0.0
    deriv_sum = 0.0
    weight_sum = 0.0
    for pe in range(6):
        v0 = corners[pe]
        v1 = corners[(pe + 1) % 6]
        t_edge, signed_dist = _edge_projection(lx, ly, v0, v1)
        dist = max(signed_dist, HEXPATCH_EDGE_DIST_EPSILON)
        weight = 1.0 / (dist * dist)
        ribbon = tile_edges.smooth_ribbon[pe]
        lip = tile_edges.cliff_lip[pe]
        rev = tile_edges.ribbon_reversed[pe]
        if ribbon is not None:
            b_val = _ribbon_b_t_oriented(ribbon, t_edge, rev)
            d_val = _ribbon_d_t_oriented(ribbon, t_edge, rev)
        elif lip is not None:
            b_val = _lip_b_t(lip, t_edge)
            d_val = 0.0
        else:
            continue
        value_sum += weight * b_val
        deriv_sum += weight * d_val * signed_dist
        weight_sum += weight
    if weight_sum <= 1e-18:
        return 0.0
    return value_sum / weight_sum + deriv_sum / weight_sum


def evaluate_hexpatch_patch_local(
    lx: float,
    ly: float,
    tile_edges: HexPatchTileEdges,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float]:
    """Return (S_patch, beta) at tile-local coordinates."""
    s_patch = _evaluate_hexpatch_patch_local(lx, ly, tile_edges, radius=radius)
    beta = _bubble_beta(lx, ly, radius=radius)
    return s_patch, beta


def sample_hexpatch_surface_world(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    apply_center_bubble: bool = True,
) -> float:
    bundle = model.hexpatch_bundle
    if bundle is None:
        raise RuntimeError("hexpatch_bundle not built on TerrainModel")
    tile_edges = bundle.tile_edges[(q, r)]
    cx, cy = handdrawn_center_world_xy(q, r, radius)
    lx = wx - cx
    ly = wy - cy
    s_patch, beta = evaluate_hexpatch_patch_local(lx, ly, tile_edges, radius=radius)
    if not apply_center_bubble:
        return s_patch
    z_center = canonical_center_world_z(model.map, q, r)
    s_patch_center, _beta_c = evaluate_hexpatch_patch_local(0.0, 0.0, tile_edges, radius=radius)
    delta_z = z_center - s_patch_center
    return s_patch + delta_z * beta


def sample_hexpatch_surface_with_drift(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float, float]:
    """Return (height, s_patch_before_bubble, beta)."""
    bundle = model.hexpatch_bundle
    if bundle is None:
        raise RuntimeError("hexpatch_bundle not built on TerrainModel")
    tile_edges = bundle.tile_edges[(q, r)]
    cx, cy = handdrawn_center_world_xy(q, r, radius)
    lx = wx - cx
    ly = wy - cy
    s_patch, beta = evaluate_hexpatch_patch_local(lx, ly, tile_edges, radius=radius)
    z_center = canonical_center_world_z(model.map, q, r)
    s_center, _ = evaluate_hexpatch_patch_local(0.0, 0.0, tile_edges, radius=radius)
    height = s_patch + (z_center - s_center) * beta
    return height, s_patch, beta


def _edge_world_geometry(
    q: int,
    r: int,
    pe: int,
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[float, float], tuple[float, float]]:
    c0 = handdrawn_corner_world_xy(q, r, pe, radius)
    c1 = handdrawn_corner_world_xy(q, r, (pe + 1) % 6, radius)
    mx = 0.5 * (c0[0] + c1[0])
    my = 0.5 * (c0[1] + c1[1])
    return c0, c1, (mx, my)


def audit_hexpatch_g1_ribbons(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = HEXPATCH_G1_EPSILON,
) -> dict[str, Any]:
    bundle = model.hexpatch_bundle
    if bundle is None:
        return {"ok": False, "reason": "no hexpatch_bundle"}
    global_max_slope_diff = 0.0
    failures: list[dict[str, Any]] = []
    delta_h = radius * 1e-4
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        ribbon = bundle.shared_ribbons.get(edge_key)
        if ribbon is None:
            continue
        dir_a = _baseline_neighbor_direction(edge.tile_a, edge.tile_b)
        pe_a = _physical_edge_for_baseline_neighbor(dir_a)
        dir_b = _baseline_neighbor_direction(edge.tile_b, edge.tile_a)
        pe_b = _physical_edge_for_baseline_neighbor(dir_b)
        c0, c1, _mid = _edge_world_geometry(*edge.tile_a, pe_a, radius=radius)
        v0 = (
            c0[0] - handdrawn_center_world_xy(*edge.tile_a, radius)[0],
            c0[1] - handdrawn_center_world_xy(*edge.tile_a, radius)[1],
        )
        v1 = (
            c1[0] - handdrawn_center_world_xy(*edge.tile_a, radius)[0],
            c1[1] - handdrawn_center_world_xy(*edge.tile_a, radius)[1],
        )
        nx, ny = _edge_inward_normal(v0, v1)
        for step in range(1, subdiv):
            t = float(step) / float(subdiv)
            wx = c0[0] * (1.0 - t) + c1[0] * t
            wy = c0[1] * (1.0 - t) + c1[1] * t
            z_a0, _, _ = sample_hexpatch_surface_with_drift(
                wx, wy, edge.tile_a[0], edge.tile_a[1], model, radius=radius
            )
            z_a1, _, _ = sample_hexpatch_surface_with_drift(
                wx + nx * delta_h, wy + ny * delta_h, edge.tile_a[0], edge.tile_a[1], model, radius=radius
            )
            slope_a = (z_a1 - z_a0) / delta_h
            z_b0, _, _ = sample_hexpatch_surface_with_drift(
                wx, wy, edge.tile_b[0], edge.tile_b[1], model, radius=radius
            )
            z_b1, _, _ = sample_hexpatch_surface_with_drift(
                wx - nx * delta_h, wy - ny * delta_h, edge.tile_b[0], edge.tile_b[1], model, radius=radius
            )
            slope_b = (z_b1 - z_b0) / delta_h
            diff = abs(slope_a - slope_b)
            global_max_slope_diff = max(global_max_slope_diff, diff)
            if diff > height_epsilon:
                failures.append(
                    {
                        "edge": edge_key,
                        "t": t,
                        "slope_a": slope_a,
                        "slope_b": slope_b,
                        "diff": diff,
                    }
                )
    return {
        "ok": global_max_slope_diff <= height_epsilon,
        "global_max_slope_diff": global_max_slope_diff,
        "failure_count": len(failures),
        "failures": failures[:20],
    }


def audit_hexpatch_boundary_reproduction(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = HEXPATCH_HEIGHT_EPSILON,
) -> dict[str, Any]:
    bundle = model.hexpatch_bundle
    if bundle is None:
        return {"ok": False, "reason": "no hexpatch_bundle"}
    global_max_err = 0.0
    for q, r in sorted(model.map.tiles):
        tile_edges = bundle.tile_edges[(q, r)]
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        for pe in range(6):
            ribbon = tile_edges.smooth_ribbon[pe]
            if ribbon is None:
                continue
            rev = tile_edges.ribbon_reversed[pe]
            c0 = corner_xy_local(pe, radius)
            c1 = corner_xy_local((pe + 1) % 6, radius)
            for step in range(1, subdiv):
                t = float(step) / float(subdiv)
                lx = c0[0] * (1.0 - t) + c1[0] * t
                ly = c0[1] * (1.0 - t) + c1[1] * t
                expected = _ribbon_b_t_oriented(ribbon, t, rev)
                actual, _ = evaluate_hexpatch_patch_local(lx, ly, tile_edges, radius=radius)
                err = abs(actual - expected)
                global_max_err = max(global_max_err, err)
    return {
        "ok": global_max_err <= height_epsilon,
        "global_max_abs_error": global_max_err,
    }


def audit_hexpatch_cross_derivative(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = HEXPATCH_CROSS_DERIV_EPSILON,
) -> dict[str, Any]:
    bundle = model.hexpatch_bundle
    if bundle is None:
        return {"ok": False, "reason": "no hexpatch_bundle"}
    delta_h = radius * 1e-4
    global_max_err = 0.0
    for q, r in sorted(model.map.tiles):
        tile_edges = bundle.tile_edges[(q, r)]
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        for pe in range(6):
            ribbon = tile_edges.smooth_ribbon[pe]
            if ribbon is None:
                continue
            rev = tile_edges.ribbon_reversed[pe]
            v0 = corner_xy_local(pe, radius)
            v1 = corner_xy_local((pe + 1) % 6, radius)
            nx, ny = _edge_inward_normal(v0, v1)
            for step in range(1, subdiv):
                t = float(step) / float(subdiv)
                lx = v0[0] * (1.0 - t) + v1[0] * t
                ly = v0[1] * (1.0 - t) + v1[1] * t
                z0, _, _ = sample_hexpatch_surface_with_drift(
                    cx + lx, cy + ly, q, r, model, radius=radius
                )
                z1, _, _ = sample_hexpatch_surface_with_drift(
                    cx + lx + nx * delta_h,
                    cy + ly + ny * delta_h,
                    q,
                    r,
                    model,
                    radius=radius,
                )
                fd = (z1 - z0) / delta_h
                expected = _ribbon_d_t_oriented(ribbon, t, rev)
                err = abs(fd - expected)
                global_max_err = max(global_max_err, err)
    return {
        "ok": global_max_err <= height_epsilon,
        "global_max_abs_error": global_max_err,
    }


def audit_hexpatch_center(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    height_epsilon: float = HEXPATCH_HEIGHT_EPSILON,
) -> dict[str, Any]:
    bundle = model.hexpatch_bundle
    if bundle is None:
        return {"ok": False, "reason": "no hexpatch_bundle"}
    drifts: list[float] = []
    warn_threshold = model.map.elevation_step * HEXPATCH_CENTER_DRIFT_WARN_FACTOR
    warnings: list[tuple[int, int]] = []
    for q, r in sorted(model.map.tiles):
        z_canonical = canonical_center_world_z(model.map, q, r)
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        tile_edges = bundle.tile_edges[(q, r)]
        s_center, _ = evaluate_hexpatch_patch_local(0.0, 0.0, tile_edges, radius=radius)
        drift = abs(z_canonical - s_center)
        drifts.append(drift)
        if drift > warn_threshold:
            warnings.append((q, r))
        z_final, _, _ = sample_hexpatch_surface_with_drift(cx, cy, q, r, model, radius=radius)
        if abs(z_final - z_canonical) > height_epsilon:
            return {
                "ok": False,
                "reason": "center not exact after bubble",
                "tile": (q, r),
                "z_canonical": z_canonical,
                "z_final": z_final,
            }
    return {
        "ok": True,
        "drift_max": max(drifts) if drifts else 0.0,
        "drift_mean": sum(drifts) / float(len(drifts)) if drifts else 0.0,
        "drift_warn_threshold": warn_threshold,
        "drift_warn_tiles": warnings[:20],
        "drift_warn_count": len(warnings),
    }


def audit_hexpatch_no_spoke(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = 1e-2,
) -> dict[str, Any]:
    delta = radius / float(subdiv * 4)
    global_max_disc = 0.0
    for q, r in sorted(model.map.tiles):
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        for sector in range(6):
            angle = math.radians(30.0 + 60.0 * float(sector))
            dx = math.cos(angle)
            dy = math.sin(angle)
            z_m, _, _ = sample_hexpatch_surface_with_drift(
                cx + dx * delta, cy + dy * delta, q, r, model, radius=radius
            )
            z_p, _, _ = sample_hexpatch_surface_with_drift(
                cx + dx * delta * 2.0, cy + dy * delta * 2.0, q, r, model, radius=radius
            )
            z_n, _, _ = sample_hexpatch_surface_with_drift(
                cx - dx * delta, cy - dy * delta, q, r, model, radius=radius
            )
            deriv_forward = (z_p - z_m) / delta
            deriv_backward = (z_m - z_n) / delta
            disc = abs(deriv_forward - deriv_backward)
            global_max_disc = max(global_max_disc, disc)
    return {
        "ok": global_max_disc <= height_epsilon,
        "global_max_derivative_discontinuity": global_max_disc,
    }


def audit_hexpatch_smooth_edge_height(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    height_epsilon: float = HEXPATCH_HEIGHT_EPSILON,
) -> dict[str, Any]:
    global_max = 0.0
    for edge in model.smooth_edges:
        dir_a = _baseline_neighbor_direction(edge.tile_a, edge.tile_b)
        pe_a = _physical_edge_for_baseline_neighbor(dir_a)
        dir_b = _baseline_neighbor_direction(edge.tile_b, edge.tile_a)
        pe_b = _physical_edge_for_baseline_neighbor(dir_b)
        c0, c1, _ = _edge_world_geometry(*edge.tile_a, pe_a, radius=radius)
        for step in range(subdiv + 1):
            t = float(step) / float(subdiv)
            wx = c0[0] * (1.0 - t) + c1[0] * t
            wy = c0[1] * (1.0 - t) + c1[1] * t
            za, _, _ = sample_hexpatch_surface_with_drift(
                wx, wy, edge.tile_a[0], edge.tile_a[1], model, radius=radius
            )
            zb, _, _ = sample_hexpatch_surface_with_drift(
                wx, wy, edge.tile_b[0], edge.tile_b[1], model, radius=radius
            )
            global_max = max(global_max, abs(za - zb))
    return {
        "ok": global_max <= height_epsilon,
        "global_max_abs_z_diff": global_max,
        "mismatch_count": 0 if global_max <= height_epsilon else 1,
    }


def audit_hexpatch_suite(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
) -> dict[str, Any]:
    return {
        "smooth_edge_height": audit_hexpatch_smooth_edge_height(
            model, radius=radius, subdiv=subdiv
        ),
        "g1_ribbons": audit_hexpatch_g1_ribbons(model, radius=radius, subdiv=subdiv),
        "boundary_reproduction": audit_hexpatch_boundary_reproduction(
            model, radius=radius, subdiv=subdiv
        ),
        "cross_derivative": audit_hexpatch_cross_derivative(
            model, radius=radius, subdiv=subdiv
        ),
        "center": audit_hexpatch_center(model, radius=radius),
        "no_spoke": audit_hexpatch_no_spoke(model, radius=radius, subdiv=subdiv),
    }
