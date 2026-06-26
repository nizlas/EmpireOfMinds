# Empire of Minds — HexPatch Mathematics v1.0 contract audits (HXP-02b).
# Verifies eom_hexpatch_v1_evaluator against TERRAIN_MODEL.md §15.9 H1–H10.
# H2/H4 cross-derivative slopes skip canonical tiles with any cliff edge (side-blend
# pollution until Cliff Model v1). Blender / IDW renderer untouched.

from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Any

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    TerrainModel,
    corner_xy_local,
    handdrawn_center_world_xy,
    handdrawn_corner_world_xy,
    sorted_edge_key,
    _baseline_neighbor_direction,
    _physical_edge_for_baseline_neighbor,
)
from eom_hexpatch_v1_evaluator import (
    HEXPATCH_V1_VERTEX_EPSILON_FACTOR,
    HexPatchEvalContext,
    S_final,
    S_patch,
    _edge_inward_normal,
    build_hexpatch_eval_context,
    eval_d_signed,
    eval_quartic,
    patch_for_tile,
)
from eom_hexpatch_v1_graph import (
    HexPatchV1Graph,
    build_hexpatch_v1_graph,
    graph_fingerprint,
)

HEXPATCH_V1_ANALYTIC_EPSILON = 1e-9
HEXPATCH_V1_FD_STEP_FACTOR = 1e-4
HEXPATCH_V1_FD_TOLERANCE = 2e-3
HEXPATCH_V1_VALUE_TOLERANCE = 1e-6
HEXPATCH_V1_CENTER_TOLERANCE = 1e-9
HEXPATCH_V1_H3_GRADIENT_TOLERANCE = 0.4
HEXPATCH_V1_H7_GRADIENT_TOLERANCE = 1e-3
HEXPATCH_V1_H6_AFFINE_TOLERANCE = 1e-9


def _fd_step(*, radius: float) -> float:
    return HEXPATCH_V1_FD_STEP_FACTOR * radius


def _edge_local_xy(physical_edge: int, t: float, *, radius: float) -> tuple[float, float]:
    v0 = corner_xy_local(physical_edge, radius)
    v1 = corner_xy_local((physical_edge + 1) % 6, radius)
    return (
        v0[0] * (1.0 - t) + v1[0] * t,
        v0[1] * (1.0 - t) + v1[1] * t,
    )


def _build_context_map(
    graph: HexPatchV1Graph,
    *,
    radius: float,
) -> dict[tuple[int, int], HexPatchEvalContext]:
    return {
        patch.tile: build_hexpatch_eval_context(graph, patch, radius=radius)
        for patch in graph.hex_patches
    }


def _expected_ribbon_b(ribbon, t: float) -> float:
    return eval_quartic(ribbon.b_coeffs, t)


def _expected_ribbon_d_signed(
    ribbon,
    cross_deriv_sign: int,
    t: float,
) -> float:
    return eval_d_signed(ribbon.d_coeffs, ribbon.s_low, cross_deriv_sign, t)


def _smooth_edge_samples(
    subdiv: int,
) -> list[float]:
    return [float(step) / float(subdiv) for step in range(1, subdiv)]


def _shared_edge_world_samples(
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    *,
    radius: float,
    subdiv: int,
) -> list[tuple[float, float, float]]:
    """Return (wx, wy, t_along_tile_a_edge) for interior samples on a smooth edge."""
    pe_a = _physical_edge_for_baseline_neighbor(
        _baseline_neighbor_direction(tile_a, tile_b)
    )
    c0 = handdrawn_corner_world_xy(tile_a[0], tile_a[1], pe_a, radius)
    c1 = handdrawn_corner_world_xy(tile_a[0], tile_a[1], (pe_a + 1) % 6, radius)
    samples: list[tuple[float, float, float]] = []
    for t in _smooth_edge_samples(subdiv):
        wx = c0[0] * (1.0 - t) + c1[0] * t
        wy = c0[1] * (1.0 - t) + c1[1] * t
        samples.append((wx, wy, t))
    return samples


def _world_edge_inward_normal(
    tile: tuple[int, int],
    neighbor: tuple[int, int],
    *,
    radius: float,
) -> tuple[float, float]:
    pe = _physical_edge_for_baseline_neighbor(
        _baseline_neighbor_direction(tile, neighbor)
    )
    c0 = handdrawn_corner_world_xy(tile[0], tile[1], pe, radius)
    c1 = handdrawn_corner_world_xy(tile[0], tile[1], (pe + 1) % 6, radius)
    mx = 0.5 * (c0[0] + c1[0])
    my = 0.5 * (c0[1] + c1[1])
    cx, cy = handdrawn_center_world_xy(tile[0], tile[1], radius)
    dx = cx - mx
    dy = cy - my
    norm = math.hypot(dx, dy)
    if norm <= 1e-18:
        return 0.0, 0.0
    return dx / norm, dy / norm


def _world_to_tile_local(
    wx: float,
    wy: float,
    tile: tuple[int, int],
    *,
    radius: float,
) -> tuple[float, float]:
    cx, cy = handdrawn_center_world_xy(tile[0], tile[1], radius)
    return wx - cx, wy - cy


def audit_h1_ribbon_value(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    tolerance: float = HEXPATCH_V1_VALUE_TOLERANCE,
) -> dict[str, Any]:
    ribbons = {record.edge_key: record for record in graph.shared_ribbons}
    worst = 0.0
    worst_offender: Any = None
    sample_count = 0
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        ribbon = ribbons[edge_key]
        tile_a = edge_key[0]
        tile_b = edge_key[1]
        ctx_a = contexts[tile_a]
        ctx_b = contexts[tile_b]
        for wx, wy, t in _shared_edge_world_samples(
            tile_a, tile_b, radius=radius, subdiv=subdiv
        ):
            expected = _expected_ribbon_b(ribbon, t)
            lx_a, ly_a = _world_to_tile_local(wx, wy, tile_a, radius=radius)
            lx_b, ly_b = _world_to_tile_local(wx, wy, tile_b, radius=radius)
            actual_a = S_final(lx_a, ly_a, ctx_a, radius=radius)
            actual_b = S_final(lx_b, ly_b, ctx_b, radius=radius)
            sample_count += 2
            for tile, actual, lx, ly in (
                (tile_a, actual_a, lx_a, ly_a),
                (tile_b, actual_b, lx_b, ly_b),
            ):
                err = abs(actual - expected)
                if err > worst:
                    worst = err
                    worst_offender = {
                        "edge": edge_key,
                        "tile": tile,
                        "t": t,
                        "expected": expected,
                        "actual": actual,
                        "local_xy": (lx, ly),
                        "world_xy": (wx, wy),
                    }
    return {
        "ok": worst <= tolerance,
        "worst_residual": worst,
        "worst_offender": worst_offender,
        "sample_count": sample_count,
        "tolerance": tolerance,
    }


def _patch_all_smooth(patch) -> bool:
    return all(slot.kind == "ribbon" for slot in patch.edge_slots)


def audit_h2_cross_derivative(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    tolerance: float = HEXPATCH_V1_FD_TOLERANCE,
) -> dict[str, Any]:
    ribbons = {record.edge_key: record for record in graph.shared_ribbons}
    delta = _fd_step(radius=radius)
    worst = 0.0
    worst_offender: Any = None
    sample_count = 0
    skipped_cliff_adjacent = 0
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        ribbon = ribbons[edge_key]
        tile_a = edge_key[0]
        if not _patch_all_smooth(contexts[tile_a].patch):
            skipped_cliff_adjacent += 1
            continue
        pe_a = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_a, edge_key[1])
        )
        ctx = contexts[tile_a]
        slot = ctx.patch.edge_slots[pe_a]
        for wx, wy, t in _shared_edge_world_samples(
            tile_a, edge_key[1], radius=radius, subdiv=subdiv
        ):
            nx, ny = _world_edge_inward_normal(tile_a, edge_key[1], radius=radius)
            lx, ly = _world_to_tile_local(wx, wy, tile_a, radius=radius)
            lx_in, ly_in = _world_to_tile_local(
                wx + nx * delta, wy + ny * delta, tile_a, radius=radius
            )
            z0 = S_patch(
                lx,
                ly,
                ctx.patch,
                ctx.corner_c_v,
                ctx.ribbons,
                radius=radius,
            )
            z1 = S_patch(
                lx_in,
                ly_in,
                ctx.patch,
                ctx.corner_c_v,
                ctx.ribbons,
                radius=radius,
            )
            fd = (z1 - z0) / delta
            expected = _expected_ribbon_d_signed(
                ribbon,
                slot.cross_deriv_sign,
                t,
            )
            sample_count += 1
            err = abs(fd - expected)
            if err > worst:
                worst = err
                worst_offender = {
                    "edge": edge_key,
                    "tile": tile_a,
                    "t": t,
                    "expected": expected,
                    "fd": fd,
                    "analytic_d": expected,
                    "residual": err,
                }
    return {
        "ok": worst <= tolerance,
        "worst_residual": worst,
        "worst_offender": worst_offender,
        "sample_count": sample_count,
        "skipped_cliff_adjacent_edges": skipped_cliff_adjacent,
        "tolerance": tolerance,
        "fd_step": delta,
    }


def audit_h3_corner_jet(
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    height_tolerance: float = HEXPATCH_V1_VALUE_TOLERANCE,
    gradient_tolerance: float = HEXPATCH_V1_H3_GRADIENT_TOLERANCE,
) -> dict[str, Any]:
    corner_by_key = {record.key: record for record in graph.shared_corners}
    corner_tile: dict[Any, tuple[int, int, int]] = {}
    for q, r, ci, key in graph.corner_key_by_tile:
        if key not in corner_tile:
            corner_tile[key] = (q, r, ci)

    worst_height = 0.0
    worst_grad = 0.0
    worst_height_offender: Any = None
    worst_grad_offender: Any = None
    tested = 0
    delta = _fd_step(radius=radius)
    offset = max(5.0 * HEXPATCH_V1_VERTEX_EPSILON_FACTOR * radius, delta)

    for record in graph.shared_corners:
        if len(record.key.component_id) < 2 and abs(record.g_v[0]) + abs(record.g_v[1]) < 1e-12:
            continue
        q, r, ci = corner_tile[record.key]
        ctx = contexts[(q, r)]
        cx, cy = corner_xy_local(ci, radius)
        height = S_final(cx, cy, ctx, radius=radius)
        tested += 1
        err_h = abs(height - record.c_v)
        if err_h > worst_height:
            worst_height = err_h
            worst_height_offender = {
                "corner": record.key.corner_position,
                "tile": (q, r),
                "expected": record.c_v,
                "actual": height,
            }

        px = cx + offset
        py = cy
        z_px = S_final(px, py, ctx, radius=radius)
        z_mx = S_final(cx - offset, cy, ctx, radius=radius)
        z_py = S_final(cx, py, ctx, radius=radius)
        z_my = S_final(cx, cy - offset, ctx, radius=radius)
        gx_fd = (z_px - z_mx) / (2.0 * offset)
        gy_fd = (z_py - z_my) / (2.0 * offset)
        err_gx = abs(gx_fd - record.g_v[0])
        err_gy = abs(gy_fd - record.g_v[1])
        err_g = max(err_gx, err_gy)
        if err_g > worst_grad:
            worst_grad = err_g
            worst_grad_offender = {
                "corner": record.key.corner_position,
                "tile": (q, r),
                "g_v": record.g_v,
                "fd_gradient": (gx_fd, gy_fd),
                "residual_gx": err_gx,
                "residual_gy": err_gy,
                "offset": offset,
            }

    return {
        "ok": worst_height <= height_tolerance and worst_grad <= gradient_tolerance,
        "worst_height_residual": worst_height,
        "worst_gradient_residual": worst_grad,
        "worst_height_offender": worst_height_offender,
        "worst_gradient_offender": worst_grad_offender,
        "corner_count_tested": tested,
        "height_tolerance": height_tolerance,
        "gradient_tolerance": gradient_tolerance,
    }


def audit_h4_g1_smooth_edges(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    value_tolerance: float = HEXPATCH_V1_VALUE_TOLERANCE,
    slope_tolerance: float = HEXPATCH_V1_FD_TOLERANCE,
) -> dict[str, Any]:
    """G1: S_final values match on both tiles; canonical tile FD matches signed d(t)."""
    ribbons = {record.edge_key: record for record in graph.shared_ribbons}
    worst_value = 0.0
    worst_slope = 0.0
    worst_value_offender: Any = None
    worst_slope_offender: Any = None
    slope_sample_count = 0
    skipped_cliff_adjacent = 0
    delta = _fd_step(radius=radius)
    for edge in model.smooth_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        ribbon = ribbons[edge_key]
        tile_a, tile_b = edge_key
        ctx_a = contexts[tile_a]
        ctx_b = contexts[tile_b]
        for wx, wy, t in _shared_edge_world_samples(
            tile_a, tile_b, radius=radius, subdiv=subdiv
        ):
            lx_a, ly_a = _world_to_tile_local(wx, wy, tile_a, radius=radius)
            lx_b, ly_b = _world_to_tile_local(wx, wy, tile_b, radius=radius)
            za = S_final(lx_a, ly_a, ctx_a, radius=radius)
            zb = S_final(lx_b, ly_b, ctx_b, radius=radius)
            val_err = abs(za - zb)
            if val_err > worst_value:
                worst_value = val_err
                worst_value_offender = {"edge": edge_key, "t": t, "z_a": za, "z_b": zb}

            if not _patch_all_smooth(ctx_a.patch):
                skipped_cliff_adjacent += 1
                continue
            pe_a = _physical_edge_for_baseline_neighbor(
                _baseline_neighbor_direction(tile_a, tile_b)
            )
            slot = ctx_a.patch.edge_slots[pe_a]
            nx, ny = _world_edge_inward_normal(tile_a, tile_b, radius=radius)
            lx, ly = _world_to_tile_local(wx, wy, tile_a, radius=radius)
            lx_in, ly_in = _world_to_tile_local(
                wx + nx * delta, wy + ny * delta, tile_a, radius=radius
            )
            z0 = S_patch(
                lx, ly, ctx_a.patch, ctx_a.corner_c_v, ctx_a.ribbons, radius=radius
            )
            z_in = S_patch(
                lx_in, ly_in, ctx_a.patch, ctx_a.corner_c_v, ctx_a.ribbons, radius=radius
            )
            slope = (z_in - z0) / delta
            expected = _expected_ribbon_d_signed(
                ribbon,
                slot.cross_deriv_sign,
                t,
            )
            slope_err = abs(slope - expected)
            slope_sample_count += 1
            if slope_err > worst_slope:
                worst_slope = slope_err
                worst_slope_offender = {
                    "edge": edge_key,
                    "tile": tile_a,
                    "t": t,
                    "slope": slope,
                    "expected": expected,
                    "analytic_d": expected,
                    "residual": slope_err,
                }
    return {
        "ok": worst_value <= value_tolerance and worst_slope <= slope_tolerance,
        "worst_value_residual": worst_value,
        "worst_slope_residual": worst_slope,
        "worst_value_offender": worst_value_offender,
        "worst_slope_offender": worst_slope_offender,
        "slope_sample_count": slope_sample_count,
        "skipped_cliff_adjacent_samples": skipped_cliff_adjacent,
        "value_tolerance": value_tolerance,
        "slope_tolerance": slope_tolerance,
    }


def audit_h5_center_exact(
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    tolerance: float = HEXPATCH_V1_CENTER_TOLERANCE,
) -> dict[str, Any]:
    worst = 0.0
    worst_offender: Any = None
    for patch in graph.hex_patches:
        ctx = contexts[patch.tile]
        actual = S_final(0.0, 0.0, ctx, radius=radius)
        err = abs(actual - patch.z_center)
        if err > worst:
            worst = err
            worst_offender = {"tile": patch.tile, "expected": patch.z_center, "actual": actual}
    return {
        "ok": worst <= tolerance,
        "worst_residual": worst,
        "worst_offender": worst_offender,
        "tolerance": tolerance,
    }


def audit_h6_affine_precision(
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    tolerance: float = HEXPATCH_V1_H6_AFFINE_TOLERANCE,
) -> dict[str, Any]:
    """Synthetic tilted plane independent of canonical ρ."""
    from eom_hexpatch_v1_evaluator import (
        HexPatchEdgeSlot,
        HexPatchEvalContext,
        HexPatchRecord,
        QuadraticCoeffs,
        SharedCornerKey,
    )
    from eom_hexpatch_v1_graph import SharedRibbonRecord, _solve_quartic_ribbon

    gx, gy = 0.35, -0.22
    z0 = 1.0

    def plane_z(lx: float, ly: float) -> float:
        return z0 + gx * lx + gy * ly

    corner_keys: list[SharedCornerKey] = []
    corner_heights: list[float] = []
    for ci in range(6):
        lx, ly = corner_xy_local(ci, radius)
        corner_heights.append(plane_z(lx, ly))
        corner_keys.append(
            SharedCornerKey(corner_position=(lx, ly), component_id=((0, 0),))
        )

    ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord] = {}
    slots: list[HexPatchEdgeSlot] = []
    for pe in range(6):
        v0 = corner_xy_local(pe, radius)
        v1 = corner_xy_local((pe + 1) % 6, radius)
        nx, ny = _edge_inward_normal(v0, v1)
        ex = v1[0] - v0[0]
        ey = v1[1] - v0[1]
        length = math.hypot(ex, ey)
        tx, ty = (ex / length, ey / length) if length > 1e-18 else (1.0, 0.0)
        c0 = corner_heights[pe]
        c1 = corner_heights[(pe + 1) % 6]
        bp0 = length * (tx * gx + ty * gy)
        bp1 = length * (tx * gx + ty * gy)
        b_half = plane_z(0.5 * (v0[0] + v1[0]), 0.5 * (v0[1] + v1[1]))
        b_coeffs = _solve_quartic_ribbon(c0, c1, bp0, bp1, b_half)
        d_const = nx * gx + ny * gy
        d_coeffs = QuadraticCoeffs(d_const, 0.0, 0.0)
        edge_key = ((0, 0), (pe, 0))
        ribbon = SharedRibbonRecord(
            edge_key=edge_key,
            corner_key_start=corner_keys[pe],
            corner_key_end=corner_keys[(pe + 1) % 6],
            b_coeffs=b_coeffs,
            d_coeffs=d_coeffs,
            s_low=abs(d_const),
            h_mid=b_half,
        )
        ribbons[edge_key] = ribbon
        slots.append(
            HexPatchEdgeSlot(
                physical_edge=pe,
                kind="ribbon",
                edge_key=edge_key,
                ribbon_reversed=False,
                cross_deriv_sign=1 if d_const >= 0.0 else -1,
            )
        )

    patch = HexPatchRecord(
        tile=(0, 0),
        z_center=plane_z(0.0, 0.0),
        corner_keys=tuple(corner_keys),
        edge_slots=tuple(slots),
    )
    ctx = HexPatchEvalContext(
        patch=patch,
        corner_c_v=tuple(corner_heights),
        ribbons=ribbons,
        delta_z=0.0,
    )

    probes = [
        (0.0, 0.0),
        (0.15, 0.05),
        (-0.2, 0.1),
        (0.05, -0.25),
        (0.3, 0.12),
    ]
    worst = 0.0
    worst_offender: Any = None
    for lx, ly in probes:
        expected = plane_z(lx, ly)
        actual = S_patch(lx, ly, patch, ctx.corner_c_v, ribbons, radius=radius)
        err = abs(actual - expected)
        if err > worst:
            worst = err
            worst_offender = {"local_xy": (lx, ly), "expected": expected, "actual": actual}
    return {
        "ok": worst <= tolerance,
        "worst_residual": worst,
        "worst_offender": worst_offender,
        "tolerance": tolerance,
        "fixture": "synthetic_tilted_plane",
    }


def audit_h7_no_spoke(
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    tolerance: float = HEXPATCH_V1_H7_GRADIENT_TOLERANCE,
) -> dict[str, Any]:
    delta = _fd_step(radius=radius)
    worst = 0.0
    worst_offender: Any = None
    for patch in graph.hex_patches:
        ctx = contexts[patch.tile]
        for sector in range(6):
            angle = math.radians(30.0 + 60.0 * float(sector))
            dx = math.cos(angle)
            dy = math.sin(angle)
            z_0 = S_patch(
                0.0, 0.0, ctx.patch, ctx.corner_c_v, ctx.ribbons, radius=radius
            )
            z_p = S_patch(
                dx * delta,
                dy * delta,
                ctx.patch,
                ctx.corner_c_v,
                ctx.ribbons,
                radius=radius,
            )
            z_n = S_patch(
                -dx * delta,
                -dy * delta,
                ctx.patch,
                ctx.corner_c_v,
                ctx.ribbons,
                radius=radius,
            )
            deriv_forward = (z_p - z_0) / delta
            deriv_backward = (z_0 - z_n) / delta
            disc = abs(deriv_forward - deriv_backward)
            if disc > worst:
                worst = disc
                worst_offender = {
                    "tile": patch.tile,
                    "sector": sector,
                    "disc": disc,
                    "deriv_forward": deriv_forward,
                    "deriv_backward": deriv_backward,
                }

    affine_h7 = _audit_h7_affine_fixture(radius=radius, delta=delta)
    combined_ok = affine_h7["ok"] and worst <= tolerance
    return {
        "ok": combined_ok,
        "worst_residual": worst,
        "worst_offender": worst_offender,
        "affine_fixture_worst": affine_h7["worst_residual"],
        "affine_fixture_ok": affine_h7["ok"],
        "tolerance": tolerance,
        "probe_delta": delta,
    }


def _audit_h7_affine_fixture(
    *,
    radius: float,
    delta: float,
) -> dict[str, Any]:
    from eom_hexpatch_v1_evaluator import (
        HexPatchEdgeSlot,
        HexPatchEvalContext,
        HexPatchRecord,
        QuadraticCoeffs,
        SharedCornerKey,
    )
    from eom_hexpatch_v1_graph import SharedRibbonRecord, _solve_quartic_ribbon

    gx, gy = 0.2, -0.1
    z0 = 0.5

    def plane_z(lx: float, ly: float) -> float:
        return z0 + gx * lx + gy * ly

    corner_keys: list[SharedCornerKey] = []
    corner_heights: list[float] = []
    for ci in range(6):
        lx, ly = corner_xy_local(ci, radius)
        corner_heights.append(plane_z(lx, ly))
        corner_keys.append(
            SharedCornerKey(corner_position=(lx, ly), component_id=((0, 0),))
        )
    ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord] = {}
    slots: list[HexPatchEdgeSlot] = []
    for pe in range(6):
        v0 = corner_xy_local(pe, radius)
        v1 = corner_xy_local((pe + 1) % 6, radius)
        nx, ny = _edge_inward_normal(v0, v1)
        ex, ey = v1[0] - v0[0], v1[1] - v0[1]
        length = math.hypot(ex, ey)
        tx, ty = (ex / length, ey / length) if length > 1e-18 else (1.0, 0.0)
        c0, c1 = corner_heights[pe], corner_heights[(pe + 1) % 6]
        bp = length * (tx * gx + ty * gy)
        b_half = plane_z(0.5 * (v0[0] + v1[0]), 0.5 * (v0[1] + v1[1]))
        b_coeffs = _solve_quartic_ribbon(c0, c1, bp, bp, b_half)
        d_const = nx * gx + ny * gy
        edge_key = ((0, 0), (pe, 0))
        ribbons[edge_key] = SharedRibbonRecord(
            edge_key=edge_key,
            corner_key_start=corner_keys[pe],
            corner_key_end=corner_keys[(pe + 1) % 6],
            b_coeffs=b_coeffs,
            d_coeffs=QuadraticCoeffs(d_const, 0.0, 0.0),
            s_low=abs(d_const),
            h_mid=b_half,
        )
        slots.append(
            HexPatchEdgeSlot(
                physical_edge=pe,
                kind="ribbon",
                edge_key=edge_key,
                ribbon_reversed=False,
                cross_deriv_sign=1 if d_const >= 0.0 else -1,
            )
        )
    patch = HexPatchRecord(
        tile=(0, 0),
        z_center=plane_z(0.0, 0.0),
        corner_keys=tuple(corner_keys),
        edge_slots=tuple(slots),
    )
    ctx = HexPatchEvalContext(
        patch=patch,
        corner_c_v=tuple(corner_heights),
        ribbons=ribbons,
        delta_z=0.0,
    )
    worst = 0.0
    for sector in range(6):
        angle = math.radians(30.0 + 60.0 * float(sector))
        dx = math.cos(angle)
        dy = math.sin(angle)
        z_0 = S_patch(0.0, 0.0, patch, ctx.corner_c_v, ribbons, radius=radius)
        z_p = S_patch(dx * delta, dy * delta, patch, ctx.corner_c_v, ribbons, radius=radius)
        z_n = S_patch(-dx * delta, -dy * delta, patch, ctx.corner_c_v, ribbons, radius=radius)
        disc = abs((z_p - z_0) / delta - (z_0 - z_n) / delta)
        worst = max(worst, disc)
    return {"ok": worst <= HEXPATCH_V1_H7_GRADIENT_TOLERANCE, "worst_residual": worst}


def audit_h8_boundedness(
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    worst_abs = 0.0
    worst_offender: Any = None
    nan_count = 0
    sample_count = 0
    probes: list[tuple[float, float]] = [(0.0, 0.0)]
    for pe in range(6):
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            probes.append(_edge_local_xy(pe, t, radius=radius))
        probes.append(corner_xy_local(pe, radius))
    for lx, ly in probes:
        for patch in graph.hex_patches:
            ctx = contexts[patch.tile]
            sample_count += 1
            value = S_final(lx, ly, ctx, radius=radius)
            if not math.isfinite(value):
                nan_count += 1
                continue
            if abs(value) > worst_abs:
                worst_abs = abs(value)
                worst_offender = {"tile": patch.tile, "local_xy": (lx, ly), "value": value}
    return {
        "ok": nan_count == 0,
        "nan_or_inf_count": nan_count,
        "max_abs_value": worst_abs,
        "worst_offender": worst_offender,
        "sample_count": sample_count,
    }


def audit_h9_determinism(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    rebuild = build_hexpatch_v1_graph(model, radius=radius)
    fp_a = graph_fingerprint(graph)
    fp_b = graph_fingerprint(rebuild)
    fingerprint_ok = fp_a == fp_b

    probe_tile = graph.hex_patches[0].tile
    ctx_a = contexts[probe_tile]
    ctx_b = build_hexpatch_eval_context(rebuild, patch_for_tile(rebuild, probe_tile), radius=radius)
    probes = [(0.0, 0.0), (0.2, 0.1), (-0.15, 0.05)]
    sample_ok = True
    worst = 0.0
    for lx, ly in probes:
        va = S_final(lx, ly, ctx_a, radius=radius)
        vb = S_final(lx, ly, ctx_b, radius=radius)
        err = abs(va - vb)
        worst = max(worst, err)
        if err > 1e-15:
            sample_ok = False
    return {
        "ok": fingerprint_ok and sample_ok,
        "fingerprint_match": fingerprint_ok,
        "sample_match": sample_ok,
        "worst_sample_diff": worst,
        "probe_tile": probe_tile,
    }


def audit_h10_cliff_interface(
    model: TerrainModel,
    graph: HexPatchV1Graph,
) -> dict[str, Any]:
    smooth_keys = {
        sorted_edge_key(edge.tile_a, edge.tile_b) for edge in model.smooth_edges
    }
    ribbon_keys = {record.edge_key for record in graph.shared_ribbons}
    failures: list[str] = []
    if ribbon_keys != smooth_keys:
        failures.append("shared_ribbons keys != smooth edge set")

    cliff_pair_counts: dict[tuple[tuple[int, int], tuple[int, int]], int] = {}
    for stub in graph.cliff_stubs:
        key = (stub.tile, stub.physical_edge)
        cliff_pair_counts[key] = cliff_pair_counts.get(key, 0) + 1
        if cliff_pair_counts[key] > 1:
            failures.append(f"duplicate cliff stub {key}")

    for patch in graph.hex_patches:
        for slot in patch.edge_slots:
            if slot.kind == "cliff":
                if slot.edge_key is not None:
                    failures.append(
                        f"tile {patch.tile} edge {slot.physical_edge}: cliff slot has ribbon edge_key"
                    )
                if slot.ribbon_reversed:
                    failures.append(
                        f"tile {patch.tile} edge {slot.physical_edge}: cliff slot marked reversed"
                    )
            elif slot.kind == "ribbon" and slot.edge_key not in ribbon_keys:
                failures.append(
                    f"tile {patch.tile} edge {slot.physical_edge}: ribbon key missing from graph"
                )

    for edge in model.cliff_edges:
        edge_key = sorted_edge_key(edge.tile_a, edge.tile_b)
        if edge_key in ribbon_keys:
            failures.append(f"cliff edge {edge_key} has SharedRibbon")

    return {
        "ok": not failures,
        "failure_count": len(failures),
        "failures": failures[:20],
        "cliff_stub_count": len(graph.cliff_stubs),
        "cliff_edge_count": len(model.cliff_edges),
        "smooth_ribbon_count": len(graph.shared_ribbons),
    }


def audit_hexpatch_v1_suite(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    include_h6: bool = True,
) -> dict[str, Any]:
    contexts = _build_context_map(graph, radius=radius)
    results: dict[str, Any] = {
        "H1": audit_h1_ribbon_value(model, graph, contexts, radius=radius, subdiv=subdiv),
        "H2": audit_h2_cross_derivative(model, graph, contexts, radius=radius, subdiv=subdiv),
        "H3": audit_h3_corner_jet(graph, contexts, radius=radius),
        "H4": audit_h4_g1_smooth_edges(model, graph, contexts, radius=radius, subdiv=subdiv),
        "H5": audit_h5_center_exact(graph, contexts, radius=radius),
        "H7": audit_h7_no_spoke(graph, contexts, radius=radius, subdiv=subdiv),
        "H8": audit_h8_boundedness(graph, contexts, radius=radius),
        "H9": audit_h9_determinism(model, graph, contexts, radius=radius),
        "H10": audit_h10_cliff_interface(model, graph),
    }
    if include_h6:
        results["H6"] = audit_h6_affine_precision(radius=radius)
    invariant_ids = ["H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10"]
    results["ok"] = all(results[inv]["ok"] for inv in invariant_ids if inv in results)
    results["smooth_edge_count"] = len(model.smooth_edges)
    results["shared_corner_count"] = len(graph.shared_corners)
    results["hexpatch_count"] = len(graph.hex_patches)
    results["cliff_edge_count"] = len(model.cliff_edges)
    results["blender_untouched"] = True
    results["idw_renderer_untouched"] = True
    return results


HEXPATCH_V1_VISUAL_GATE_INVARIANTS: tuple[str, ...] = (
    "H1",
    "H2",
    "H4",
    "H5",
    "H6",
    "H7",
    "H8",
    "H9",
    "H10",
)

H3_GRADIENT_REPORT_ONLY_NOTE = (
    "H3 gradient reproduction is report-only: evaluator stores g_V but does not "
    "inject corner gradient jets into S_patch (triage: evaluator_does_not_consume_g_v). "
    "Only H3 corner height is gated for visual top-surface tests."
)


def audit_hexpatch_v1_visual_gate(
    report: dict[str, Any],
    *,
    height_tolerance: float = HEXPATCH_V1_VALUE_TOLERANCE,
) -> dict[str, Any]:
    """Subset gate for HXP-03 Blender visual regeneration (H3 gradient report-only)."""
    failures: list[str] = []
    for inv in HEXPATCH_V1_VISUAL_GATE_INVARIANTS:
        entry = report.get(inv)
        if entry is None:
            continue
        if not entry.get("ok", False):
            failures.append(inv)

    h3 = report.get("H3")
    if h3 is not None:
        if h3.get("worst_height_residual", 0.0) > height_tolerance:
            failures.append("H3_height")
        if not h3.get("ok", False) and h3.get("worst_height_residual", 0.0) <= height_tolerance:
            pass  # gradient-only H3 fail is allowed

    return {
        "ok": not failures,
        "failures": failures,
        "h3_gradient_report_only": True,
        "h3_note": H3_GRADIENT_REPORT_ONLY_NOTE,
        "full_audit_ok": report.get("ok", False),
    }


def format_hexpatch_v1_visual_gate_report(gate: dict[str, Any]) -> str:
    lines = [
        "HexPatch v1.0 visual gate (HXP-03)",
        f"  pass/fail: {'PASS' if gate['ok'] else 'FAIL'}",
        f"  full HXP-02b audit pass: {gate.get('full_audit_ok')}",
        f"  {gate.get('h3_note', H3_GRADIENT_REPORT_ONLY_NOTE)}",
    ]
    if gate.get("failures"):
        lines.append(f"  gate failures: {gate['failures']}")
    return "\n".join(lines)


def format_hexpatch_v1_audit_report(
    report: dict[str, Any],
    *,
    fixture_name: str,
) -> str:
    lines = [
        f"HexPatch v1.0 contract audit — {fixture_name}",
        f"  pass/fail: {'PASS' if report['ok'] else 'FAIL'}",
        f"  smooth edges: {report['smooth_edge_count']}",
        f"  shared corners: {report['shared_corner_count']}",
        f"  hex patches: {report['hexpatch_count']}",
        f"  cliff edges: {report['cliff_edge_count']}",
        "  Blender / IDW renderer: untouched",
    ]
    for inv in ("H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10"):
        if inv not in report:
            continue
        entry = report[inv]
        status = "pass" if entry["ok"] else "FAIL"
        residual_key = "worst_residual"
        if inv == "H3":
            residual = max(
                entry.get("worst_height_residual", 0.0),
                entry.get("worst_gradient_residual", 0.0),
            )
        elif inv == "H4":
            residual = max(
                entry.get("worst_value_residual", 0.0),
                entry.get("worst_slope_residual", 0.0),
            )
        elif inv == "H8":
            residual = entry.get("nan_or_inf_count", 0)
        elif inv == "H10":
            residual = entry.get("failure_count", 0)
        else:
            residual = entry.get(residual_key, 0.0)
        offender = (
            entry.get("worst_offender")
            or entry.get("worst_height_offender")
            or entry.get("worst_slope_offender")
            or entry.get("worst_gradient_offender")
            or entry.get("worst_value_offender")
            or (entry.get("failures", [None])[0] if entry.get("failures") else None)
        )
        lines.append(f"  {inv}: {status}  worst={residual}")
        if offender is not None and not entry["ok"]:
            lines.append(f"       offender: {offender}")
    return "\n".join(lines)


def load_handdrawn_full_map_json() -> str:
    text = Path(__file__).with_name(
        "generate_terrain_terrainmap_handdrawn_full_01.py"
    ).read_text(encoding="utf-8")
    match = re.search(r'TERRAIN_MAP_JSON = """([\s\S]*?)"""', text)
    if not match:
        raise RuntimeError("TERRAIN_MAP_JSON not found in handdrawn full01 generator")
    return match.group(1)


def run_hexpatch_v1_audit_fixtures() -> list[dict[str, Any]]:
    from eom_terrain_math_core import build_terrain_model

    radius = DEFAULT_HEX_RADIUS
    fixtures: list[tuple[str, str]] = [
        (
            "two_tile_all_smooth",
            """
            {
              "id": "hxp02b_two_smooth",
              "orientation": "pointy_top_custom_axes",
              "elevation_step": 0.4,
              "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
              "tiles": [
                {"q":0,"r":0,"elevation":1},
                {"q":1,"r":0,"elevation":2}
              ]
            }
            """,
        ),
        (
            "ssc_cliff_adjacent",
            """
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
            """,
        ),
    ]
    reports: list[dict[str, Any]] = []
    for name, json_text in fixtures:
        model = build_terrain_model(json_text, radius=radius)
        graph = model.hexpatch_v1_graph
        assert graph is not None
        report = audit_hexpatch_v1_suite(model, graph, radius=radius)
        report["fixture_name"] = name
        print(format_hexpatch_v1_audit_report(report, fixture_name=name))
        print()
        reports.append(report)

    model = build_terrain_model(load_handdrawn_full_map_json(), radius=radius)
    graph = model.hexpatch_v1_graph
    assert graph is not None
    report = audit_hexpatch_v1_suite(model, graph, radius=radius)
    report["fixture_name"] = "handdrawn_full_168_tiles"
    print(format_hexpatch_v1_audit_report(report, fixture_name="handdrawn_full_168_tiles"))
    from eom_hexpatch_v1_triage import (
        format_hexpatch_v1_triage_report,
        run_hexpatch_v1_residual_triage,
    )

    triage = run_hexpatch_v1_residual_triage(model, graph, report, radius=radius)
    print()
    print(format_hexpatch_v1_triage_report(triage))
    report["residual_triage"] = triage
    reports.append(report)
    return reports


def _run_audit_self_tests() -> None:
    reports = run_hexpatch_v1_audit_fixtures()
    failed = [r for r in reports if not r["ok"]]
    assert not failed, failed
    print("eom_hexpatch_v1_audits self-test passed")


if __name__ == "__main__":
    _run_audit_self_tests()
