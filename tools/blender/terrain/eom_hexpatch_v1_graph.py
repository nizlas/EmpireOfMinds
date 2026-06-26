# Empire of Minds — HexPatch Mathematics v1.0 construction graph (HXP-01).
# Immutable runtime data + Stages 1–3, 5 per docs/TERRAIN_MODEL.md §15–§16.
# No surface evaluation (S_patch / S_final / mesh sampling) in this module.

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Literal

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
    TerrainModel,
    canonical_center_world_z,
    canonical_rise_at_edge_midpoint,
    handdrawn_center_world_xy,
    handdrawn_corner_world_xy,
    hex_apothem,
    perlin_smootherstep,
    pos_key,
    sorted_edge_key,
    _baseline_neighbor_direction,
    _build_smooth_adjacency,
    _physical_edge_for_baseline_neighbor,
    _smooth_component_at_corner,
    _smooth_neighbor_across_physical_edge,
    _tiles_touching_corner,
)

HEXPATCH_V1_PSEUDOINVERSE_SVD_RATIO = 1e-9


@dataclass(frozen=True)
class SharedCornerKey:
    corner_position: tuple[float, float]
    component_id: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class SharedCornerRecord:
    key: SharedCornerKey
    c_v: float
    g_v: tuple[float, float]


@dataclass(frozen=True)
class QuarticCoeffs:
    """b(t) = c0 + c1*t + c2*t^2 + c3*t^3 + c4*t^4."""

    c0: float
    c1: float
    c2: float
    c3: float
    c4: float


@dataclass(frozen=True)
class QuadraticCoeffs:
    """d(t) = c0 + c1*t + c2*t^2 (unsigned midpoint magnitude baked in)."""

    c0: float
    c1: float
    c2: float


@dataclass(frozen=True)
class SharedRibbonRecord:
    edge_key: tuple[tuple[int, int], tuple[int, int]]
    corner_key_start: SharedCornerKey
    corner_key_end: SharedCornerKey
    b_coeffs: QuarticCoeffs
    d_coeffs: QuadraticCoeffs
    s_low: float
    h_mid: float


@dataclass(frozen=True)
class CliffInterfaceStub:
    """Stage 4 interface placeholder — endpoint corners only; interior deferred (Cliff Model v1)."""

    tile: tuple[int, int]
    physical_edge: int
    corner_key_start: SharedCornerKey
    corner_key_end: SharedCornerKey


@dataclass(frozen=True)
class HexPatchEdgeSlot:
    physical_edge: int
    kind: Literal["ribbon", "cliff"]
    edge_key: tuple[tuple[int, int], tuple[int, int]] | None
    ribbon_reversed: bool
    cross_deriv_sign: int


@dataclass(frozen=True)
class HexPatchRecord:
    tile: tuple[int, int]
    z_center: float
    corner_keys: tuple[SharedCornerKey, ...]
    edge_slots: tuple[HexPatchEdgeSlot, ...]


@dataclass(frozen=True)
class HexPatchV1Graph:
    shared_corners: tuple[SharedCornerRecord, ...]
    shared_ribbons: tuple[SharedRibbonRecord, ...]
    cliff_stubs: tuple[CliffInterfaceStub, ...]
    hex_patches: tuple[HexPatchRecord, ...]
    corner_key_by_tile: tuple[tuple[int, int, int, SharedCornerKey], ...]


def _edge_geometry(
    q: int,
    r: int,
    physical_edge: int,
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[float, float], float, tuple[float, float], tuple[float, float]]:
    c0 = handdrawn_corner_world_xy(q, r, physical_edge, radius)
    c1 = handdrawn_corner_world_xy(q, r, (physical_edge + 1) % 6, radius)
    ex = c1[0] - c0[0]
    ey = c1[1] - c0[1]
    length = math.hypot(ex, ey)
    if length <= 1e-18:
        tangent = (0.0, 0.0)
        normal = (0.0, 0.0)
    else:
        tangent = (ex / length, ey / length)
        normal = (-ey / length, ex / length)
    return c0, c1, length, tangent, normal


def _solve_quartic_ribbon(
    b0: float,
    b1: float,
    bp0: float,
    bp1: float,
    b_half: float,
) -> QuarticCoeffs:
    a0 = b0
    a1 = bp0
    rhs_sum = b1 - b0 - bp0
    rhs_slope = bp1 - bp0
    rhs_mid = 16.0 * (b_half - b0 - bp0 * 0.5)
    a4, a3, a2 = _solve_3x3(
        (1.0, 1.0, 1.0),
        (4.0, 3.0, 2.0),
        (1.0, 8.0, 4.0),
        (rhs_sum, rhs_slope, rhs_mid),
    )
    return QuarticCoeffs(c0=a0, c1=a1, c2=a2, c3=a3, c4=a4)


def _solve_3x3(
    row0: tuple[float, float, float],
    row1: tuple[float, float, float],
    row2: tuple[float, float, float],
    rhs: tuple[float, float, float],
) -> tuple[float, float, float]:
    m = [list(row0), list(row1), list(row2)]
    b = list(rhs)
    for col in range(3):
        pivot = col
        for row in range(col + 1, 3):
            if abs(m[row][col]) > abs(m[pivot][col]):
                pivot = row
        if abs(m[pivot][col]) <= 1e-18:
            return 0.0, 0.0, 0.0
        if pivot != col:
            m[col], m[pivot] = m[pivot], m[col]
            b[col], b[pivot] = b[pivot], b[col]
        div = m[col][col]
        for j in range(col, 3):
            m[col][j] /= div
        b[col] /= div
        for row in range(3):
            if row == col:
                continue
            factor = m[row][col]
            if abs(factor) <= 1e-18:
                continue
            for j in range(col, 3):
                m[row][j] -= factor * m[col][j]
            b[row] -= factor * b[col]
    return b[0], b[1], b[2]


def _quadratic_from_nodes(d0: float, d_mid: float, d1: float) -> QuadraticCoeffs:
    c0 = d0
    c2 = 2.0 * d0 - 4.0 * d_mid + 2.0 * d1
    c1 = -3.0 * d0 + 4.0 * d_mid - d1
    return QuadraticCoeffs(c0=c0, c1=c1, c2=c2)


def _canonical_s_low(
    z_low: float,
    z_high: float,
    *,
    radius: float,
    influence_radius_factor: float,
) -> float:
    delta = z_high - z_low
    if delta <= 1e-12:
        return 0.0
    ap = hex_apothem(radius=radius)
    if ap <= 1e-18:
        return 0.0
    hill_radius = radius * influence_radius_factor
    kappa = ap / hill_radius
    rho = 1.0 - perlin_smootherstep(kappa)
    s_prime_kappa = 30.0 * kappa * kappa * (1.0 - kappa) * (1.0 - kappa)
    p_prime = -kappa * s_prime_kappa
    return (rho * delta / ap) * abs(p_prime)


def _canonical_h_mid(z_a: float, z_b: float, *, rho: float | None = None) -> float:
    z_low = min(z_a, z_b)
    z_high = max(z_a, z_b)
    if z_high - z_low <= 1e-12:
        return z_low
    rise = rho if rho is not None else canonical_rise_at_edge_midpoint()
    return z_low + rise * (z_high - z_low)


def _pseudoinverse_gradient(
    centers: list[tuple[float, float]],
    heights: list[float],
    *,
    svd_ratio: float = HEXPATCH_V1_PSEUDOINVERSE_SVD_RATIO,
) -> tuple[float, float]:
    if len(centers) <= 1:
        return 0.0, 0.0
    px = sum(p[0] for p in centers) / float(len(centers))
    py = sum(p[1] for p in centers) / float(len(centers))
    zbar = sum(heights) / float(len(heights))
    m11 = m12 = m22 = 0.0
    b1 = b2 = 0.0
    for (x, y), z in zip(centers, heights):
        qx = x - px
        qy = y - py
        zeta = z - zbar
        m11 += qx * qx
        m12 += qx * qy
        m22 += qy * qy
        b1 += zeta * qx
        b2 += zeta * qy
    return _symmetric_2x2_pseudoinverse(m11, m12, m22, b1, b2, svd_ratio)


def _symmetric_2x2_pseudoinverse(
    m11: float,
    m12: float,
    m22: float,
    b1: float,
    b2: float,
    svd_ratio: float,
) -> tuple[float, float]:
    trace = m11 + m22
    det = m11 * m22 - m12 * m12
    half = trace * 0.5
    rad = max(0.0, half * half - det)
    sqrt_rad = math.sqrt(rad)
    lambda1 = half + sqrt_rad
    lambda2 = half - sqrt_rad
    sigma_max = max(abs(lambda1), abs(lambda2), 1e-18)

    def inv_lambda(value: float) -> float:
        if abs(value) <= svd_ratio * sigma_max:
            return 0.0
        return 1.0 / value

    inv_l1 = inv_lambda(lambda1)
    inv_l2 = inv_lambda(lambda2)
    if inv_l1 == 0.0 and inv_l2 == 0.0:
        return 0.0, 0.0

    def eigenvector(lam: float) -> tuple[float, float]:
        if abs(m12) > 1e-12:
            vx = m12
            vy = lam - m11
        elif abs(lam - m11) >= abs(lam - m22):
            return 1.0, 0.0
        else:
            return 0.0, 1.0
        norm = math.hypot(vx, vy)
        if norm <= 1e-18:
            return 1.0, 0.0
        return vx / norm, vy / norm

    v1 = eigenvector(lambda1)
    v2 = eigenvector(lambda2)
    dot1 = v1[0] * b1 + v1[1] * b2
    dot2 = v2[0] * b1 + v2[1] * b2
    gx = inv_l1 * v1[0] * dot1 + inv_l2 * v2[0] * dot2
    gy = inv_l1 * v1[1] * dot1 + inv_l2 * v2[1] * dot2
    return gx, gy


def _ssc_target_at_corner(model: TerrainModel, corner_world: tuple[float, float]) -> float | None:
    for ssc in model.ssc_corners:
        if ssc.corner_world == corner_world:
            return ssc.target_z
    return None


def _corner_component_key(
    model: TerrainModel,
    q: int,
    r: int,
    corner_index: int,
    *,
    radius: float,
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
) -> SharedCornerKey:
    wx, wy = handdrawn_corner_world_xy(q, r, corner_index, radius)
    corner_world = pos_key(wx, wy)
    domain_id = model.tile_domain[(q, r)]
    domain_tiles: set[tuple[int, int]] = set()
    for domain in model.domains:
        if domain.domain_id == domain_id:
            domain_tiles.update(domain.tiles)
    sharing = _tiles_touching_corner(
        model.map,
        wx,
        wy,
        domain_tiles,
        radius=radius,
    )
    if not sharing:
        sharing = [(q, r)]
    component = tuple(
        sorted(_smooth_component_at_corner((q, r), sharing, smooth_adjacency))
    )
    return SharedCornerKey(corner_position=corner_world, component_id=component)


def _stage1_smooth_components(
    model: TerrainModel,
    *,
    radius: float,
) -> tuple[
    dict[SharedCornerKey, tuple[tuple[int, int], ...]],
    dict[tuple[int, int, int], SharedCornerKey],
]:
    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey] = {}
    components: dict[SharedCornerKey, tuple[tuple[int, int], ...]] = {}
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
            if key not in components:
                components[key] = key.component_id
    return components, corner_key_by_tile


def _stage2_shared_corners(
    model: TerrainModel,
    components: dict[SharedCornerKey, tuple[tuple[int, int], ...]],
    *,
    radius: float,
) -> dict[SharedCornerKey, SharedCornerRecord]:
    records: dict[SharedCornerKey, SharedCornerRecord] = {}
    for key in sorted(components.keys(), key=lambda k: (k.corner_position, k.component_id)):
        ssc_z = _ssc_target_at_corner(model, key.corner_position)
        if ssc_z is not None:
            c_v = ssc_z
        else:
            heights = [
                canonical_center_world_z(model.map, tq, tr)
                for tq, tr in key.component_id
            ]
            c_v = sum(heights) / float(len(heights))
        centers = [
            handdrawn_center_world_xy(tq, tr, radius) for tq, tr in key.component_id
        ]
        heights = [
            canonical_center_world_z(model.map, tq, tr) for tq, tr in key.component_id
        ]
        g_v = _pseudoinverse_gradient(centers, heights)
        records[key] = SharedCornerRecord(key=key, c_v=c_v, g_v=g_v)
    return records


def _stage3_shared_ribbons(
    model: TerrainModel,
    shared_corners: dict[SharedCornerKey, SharedCornerRecord],
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey],
    *,
    radius: float,
    influence_radius_factor: float,
) -> dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord]:
    ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord] = {}
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        if edge_key in ribbons:
            continue
        tile_a = edge_key[0]
        dir_a = _baseline_neighbor_direction(tile_a, edge_key[1])
        pe_a = _physical_edge_for_baseline_neighbor(dir_a)
        k0 = corner_key_by_tile[(tile_a[0], tile_a[1], pe_a)]
        k1 = corner_key_by_tile[(tile_a[0], tile_a[1], (pe_a + 1) % 6)]
        c0 = shared_corners[k0]
        c1 = shared_corners[k1]
        _v0, _v1, length, tangent, normal = _edge_geometry(
            tile_a[0], tile_a[1], pe_a, radius=radius
        )
        z_a = canonical_center_world_z(model.map, *edge.tile_a)
        z_b = canonical_center_world_z(model.map, *edge.tile_b)
        h_mid = _canonical_h_mid(z_a, z_b)
        s_low = _canonical_s_low(
            min(z_a, z_b),
            max(z_a, z_b),
            radius=radius,
            influence_radius_factor=influence_radius_factor,
        )
        bp0 = length * (tangent[0] * c0.g_v[0] + tangent[1] * c0.g_v[1])
        bp1 = length * (tangent[0] * c1.g_v[0] + tangent[1] * c1.g_v[1])
        b_coeffs = _solve_quartic_ribbon(c0.c_v, c1.c_v, bp0, bp1, h_mid)
        d0 = normal[0] * c0.g_v[0] + normal[1] * c0.g_v[1]
        d1 = normal[0] * c1.g_v[0] + normal[1] * c1.g_v[1]
        d_coeffs = _quadratic_from_nodes(d0, s_low, d1)
        ribbons[edge_key] = SharedRibbonRecord(
            edge_key=edge_key,
            corner_key_start=k0,
            corner_key_end=k1,
            b_coeffs=b_coeffs,
            d_coeffs=d_coeffs,
            s_low=s_low,
            h_mid=h_mid,
        )
    return ribbons


def _stage4_cliff_stubs(
    model: TerrainModel,
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey],
) -> tuple[CliffInterfaceStub, ...]:
    stubs: list[CliffInterfaceStub] = []
    for q, r in sorted(model.map.tiles):
        for pe in range(6):
            if _smooth_neighbor_across_physical_edge(q, r, pe, model) is not None:
                continue
            k0 = corner_key_by_tile[(q, r, pe)]
            k1 = corner_key_by_tile[(q, r, (pe + 1) % 6)]
            stubs.append(
                CliffInterfaceStub(
                    tile=(q, r),
                    physical_edge=pe,
                    corner_key_start=k0,
                    corner_key_end=k1,
                )
            )
    return tuple(stubs)


def _cross_deriv_sign(
    model: TerrainModel,
    tile: tuple[int, int],
    neighbor: tuple[int, int],
) -> int:
    z_self = canonical_center_world_z(model.map, *tile)
    z_neighbor = canonical_center_world_z(model.map, *neighbor)
    if z_self > z_neighbor + 1e-12:
        return 1
    if z_self < z_neighbor - 1e-12:
        return -1
    return 0


def _stage5_hexpatch_assembly(
    model: TerrainModel,
    corner_key_by_tile: dict[tuple[int, int, int], SharedCornerKey],
    shared_ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord],
) -> tuple[HexPatchRecord, ...]:
    patches: list[HexPatchRecord] = []
    for q, r in sorted(model.map.tiles):
        corner_keys = tuple(
            corner_key_by_tile[(q, r, pe)] for pe in range(6)
        )
        edge_slots: list[HexPatchEdgeSlot] = []
        for pe in range(6):
            neighbor = _smooth_neighbor_across_physical_edge(q, r, pe, model)
            if neighbor is not None:
                edge_key = sorted_edge_key((q, r), neighbor)
                edge_slots.append(
                    HexPatchEdgeSlot(
                        physical_edge=pe,
                        kind="ribbon",
                        edge_key=edge_key,
                        ribbon_reversed=(q, r) != edge_key[0],
                        cross_deriv_sign=_cross_deriv_sign(model, (q, r), neighbor),
                    )
                )
            else:
                edge_slots.append(
                    HexPatchEdgeSlot(
                        physical_edge=pe,
                        kind="cliff",
                        edge_key=None,
                        ribbon_reversed=False,
                        cross_deriv_sign=0,
                    )
                )
        patches.append(
            HexPatchRecord(
                tile=(q, r),
                z_center=canonical_center_world_z(model.map, q, r),
                corner_keys=corner_keys,
                edge_slots=tuple(edge_slots),
            )
        )
    return tuple(patches)


def build_hexpatch_v1_graph(
    model: TerrainModel,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    influence_radius_factor: float = DEFAULT_HILL_INFLUENCE_RADIUS_FACTOR,
) -> HexPatchV1Graph:
    components, corner_key_by_tile = _stage1_smooth_components(model, radius=radius)
    shared_corners = _stage2_shared_corners(
        model, components, radius=radius
    )
    shared_ribbons = _stage3_shared_ribbons(
        model,
        shared_corners,
        corner_key_by_tile,
        radius=radius,
        influence_radius_factor=influence_radius_factor,
    )
    cliff_stubs = _stage4_cliff_stubs(model, corner_key_by_tile)
    hex_patches = _stage5_hexpatch_assembly(
        model, corner_key_by_tile, shared_ribbons
    )
    return HexPatchV1Graph(
        shared_corners=tuple(
            shared_corners[k]
            for k in sorted(
                shared_corners.keys(),
                key=lambda key: (key.corner_position, key.component_id),
            )
        ),
        shared_ribbons=tuple(
            shared_ribbons[k]
            for k in sorted(shared_ribbons.keys())
        ),
        cliff_stubs=cliff_stubs,
        hex_patches=hex_patches,
        corner_key_by_tile=tuple(
            sorted(
                (
                    (q, r, ci, corner_key_by_tile[(q, r, ci)])
                    for q, r in model.map.tiles
                    for ci in range(6)
                ),
                key=lambda item: (item[0], item[1], item[2]),
            )
        ),
    )


def validate_hexpatch_v1_graph(
    model: TerrainModel,
    graph: HexPatchV1Graph,
) -> dict[str, Any]:
    failures: list[str] = []
    smooth_edge_keys = {
        sorted_edge_key(edge.tile_a, edge.tile_b) for edge in model.smooth_edges
    }
    ribbon_keys = {ribbon.edge_key for ribbon in graph.shared_ribbons}
    if ribbon_keys != smooth_edge_keys:
        missing = smooth_edge_keys - ribbon_keys
        extra = ribbon_keys - smooth_edge_keys
        if missing:
            failures.append(f"smooth edges missing SharedRibbon: {sorted(missing)[:5]}")
        if extra:
            failures.append(f"extra SharedRibbon keys: {sorted(extra)[:5]}")

    expected_components = {
        record.key for record in graph.shared_corners
    }
    if len(expected_components) != len(graph.shared_corners):
        failures.append("duplicate SharedCorner keys in graph output")

    unique_corner_keys_from_tiles = {
        key for _q, _r, _ci, key in graph.corner_key_by_tile
    }
    if unique_corner_keys_from_tiles != expected_components:
        failures.append(
            "SharedCorner set mismatch vs corner_key_by_tile unique keys "
            f"({len(expected_components)} vs {len(unique_corner_keys_from_tiles)})"
        )

    corner_lookup = {
        (q, r, ci): key for q, r, ci, key in graph.corner_key_by_tile
    }
    if len(corner_lookup) != len(graph.corner_key_by_tile):
        failures.append("duplicate corner_key_by_tile entries")

    for patch in graph.hex_patches:
        if len(patch.corner_keys) != 6:
            failures.append(f"tile {patch.tile}: expected 6 corner keys, got {len(patch.corner_keys)}")
        if len(patch.edge_slots) != 6:
            failures.append(f"tile {patch.tile}: expected 6 edge slots, got {len(patch.edge_slots)}")
        for slot in patch.edge_slots:
            if slot.kind == "ribbon":
                if slot.edge_key is None or slot.edge_key not in ribbon_keys:
                    failures.append(
                        f"tile {patch.tile} edge {slot.physical_edge}: ribbon slot missing edge_key"
                    )
            elif slot.kind == "cliff" and slot.edge_key is not None:
                failures.append(
                    f"tile {patch.tile} edge {slot.physical_edge}: cliff slot must not reference ribbon edge_key"
                )
        for pe in range(6):
            if corner_lookup.get((patch.tile[0], patch.tile[1], pe)) != patch.corner_keys[pe]:
                failures.append(
                    f"tile {patch.tile} corner {pe}: corner_keys mismatch vs corner_key_by_tile"
                )

    if len(graph.hex_patches) != len(model.map.tiles):
        failures.append(
            f"expected {len(model.map.tiles)} HexPatch records, got {len(graph.hex_patches)}"
        )

    ordering_ok = _validate_deterministic_ordering(graph)
    if not ordering_ok:
        failures.append("shared_corners or shared_ribbons not in sorted key order")

    return {
        "ok": not failures,
        "failure_count": len(failures),
        "failures": failures,
        "shared_corner_count": len(graph.shared_corners),
        "shared_ribbon_count": len(graph.shared_ribbons),
        "hexpatch_count": len(graph.hex_patches),
        "cliff_stub_count": len(graph.cliff_stubs),
    }


def _validate_deterministic_ordering(graph: HexPatchV1Graph) -> bool:
    corner_keys = [record.key for record in graph.shared_corners]
    sorted_corners = sorted(
        corner_keys, key=lambda key: (key.corner_position, key.component_id)
    )
    if corner_keys != sorted_corners:
        return False
    ribbon_keys = [record.edge_key for record in graph.shared_ribbons]
    return ribbon_keys == sorted(ribbon_keys)


def graph_fingerprint(graph: HexPatchV1Graph) -> tuple[Any, ...]:
    """Deterministic rebuild fingerprint (structure only, no floats beyond rounded scalars)."""
    return (
        tuple(
            (
                record.key.corner_position,
                record.key.component_id,
                round(record.c_v, 9),
                round(record.g_v[0], 9),
                round(record.g_v[1], 9),
            )
            for record in graph.shared_corners
        ),
        tuple(
            (
                record.edge_key,
                round(record.h_mid, 9),
                round(record.s_low, 9),
                tuple(round(c, 9) for c in (
                    record.b_coeffs.c0,
                    record.b_coeffs.c1,
                    record.b_coeffs.c2,
                    record.b_coeffs.c3,
                    record.b_coeffs.c4,
                )),
                tuple(round(c, 9) for c in (
                    record.d_coeffs.c0,
                    record.d_coeffs.c1,
                    record.d_coeffs.c2,
                )),
            )
            for record in graph.shared_ribbons
        ),
        tuple((stub.tile, stub.physical_edge) for stub in graph.cliff_stubs),
        tuple(
            (
                patch.tile,
                round(patch.z_center, 9),
                tuple(slot.kind for slot in patch.edge_slots),
                tuple(slot.cross_deriv_sign for slot in patch.edge_slots),
            )
            for patch in graph.hex_patches
        ),
    )
