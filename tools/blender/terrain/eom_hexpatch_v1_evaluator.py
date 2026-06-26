# Empire of Minds — HexPatch Mathematics v1.0 pure evaluator (HXP-02a).
# S_patch, beta, S_final per docs/TERRAIN_MODEL.md §15. Not wired to rendering.
# Cliff edges use a linear endpoint placeholder (Cliff Model v1 interior deferred).

from __future__ import annotations

import math
from dataclasses import dataclass

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    corner_xy_local,
    hex_apothem,
    perlin_smootherstep,
)
from eom_hexpatch_v1_graph import (
    HexPatchEdgeSlot,
    HexPatchRecord,
    HexPatchV1Graph,
    QuarticCoeffs,
    QuadraticCoeffs,
    SharedCornerKey,
    SharedRibbonRecord,
)

HEXPATCH_V1_VERTEX_EPSILON_FACTOR = 1e-6


@dataclass(frozen=True)
class HexPatchEvalContext:
    """Evaluation bundle for one tile: patch + lookups + cached center bubble Δz."""

    patch: HexPatchRecord
    corner_c_v: tuple[float, float, float, float, float, float]
    ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord]
    delta_z: float


def build_hexpatch_eval_context(
    graph: HexPatchV1Graph,
    patch: HexPatchRecord,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> HexPatchEvalContext:
    corner_by_key = {record.key: record for record in graph.shared_corners}
    ribbons = {record.edge_key: record for record in graph.shared_ribbons}
    corner_c_v = tuple(
        corner_by_key[key].c_v for key in patch.corner_keys
    )
    s_center = S_patch(0.0, 0.0, patch, corner_c_v, ribbons, radius=radius)
    delta_z = patch.z_center - s_center
    return HexPatchEvalContext(
        patch=patch,
        corner_c_v=corner_c_v,
        ribbons=ribbons,
        delta_z=delta_z,
    )


def patch_for_tile(graph: HexPatchV1Graph, tile: tuple[int, int]) -> HexPatchRecord:
    for patch in graph.hex_patches:
        if patch.tile == tile:
            return patch
    raise KeyError(f"no HexPatchRecord for tile {tile!r}")


def eval_quartic(coeffs: QuarticCoeffs, t: float) -> float:
    return (
        coeffs.c0
        + t
        * (
            coeffs.c1
            + t
            * (
                coeffs.c2
                + t * (coeffs.c3 + t * coeffs.c4)
            )
        )
    )


def eval_quadratic(coeffs: QuadraticCoeffs, t: float) -> float:
    return coeffs.c0 + t * (coeffs.c1 + t * coeffs.c2)


def eval_d_signed(
    coeffs: QuadraticCoeffs,
    s_low: float,
    cross_deriv_sign: int,
    t: float,
) -> float:
    d0 = coeffs.c0
    d1 = coeffs.c0 + coeffs.c1 + coeffs.c2
    d_mid = float(cross_deriv_sign) * s_low
    return (
        2.0 * (t - 0.5) * (t - 1.0) * d0
        + 4.0 * t * (1.0 - t) * d_mid
        + 2.0 * t * (t - 0.5) * d1
    )


def _orient_edge_parameter(t: float, reversed_edge: bool) -> float:
    return 1.0 - t if reversed_edge else t


def _edge_inward_normal(
    v0: tuple[float, float],
    v1: tuple[float, float],
) -> tuple[float, float]:
    ex = v1[0] - v0[0]
    ey = v1[1] - v0[1]
    mx = 0.5 * (v0[0] + v1[0])
    my = 0.5 * (v0[1] + v1[1])
    norm = math.hypot(mx, my)
    if norm <= 1e-18:
        return 0.0, 0.0
    return -mx / norm, -my / norm


def edge_h_and_s(
    lx: float,
    ly: float,
    physical_edge: int,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float]:
    """Return (h_i, s_i) for edge physical_edge; s_i is unclamped orthogonal projection."""
    v0 = corner_xy_local(physical_edge, radius)
    v1 = corner_xy_local((physical_edge + 1) % 6, radius)
    nx, ny = _edge_inward_normal(v0, v1)
    ap = hex_apothem(radius=radius)
    h_i = ap + lx * nx + ly * ny
    ex = v1[0] - v0[0]
    ey = v1[1] - v0[1]
    el2 = ex * ex + ey * ey
    if el2 <= 1e-18:
        return h_i, 0.0
    s_i = ((lx - v0[0]) * ex + (ly - v0[1]) * ey) / el2
    return h_i, s_i


def all_edge_h(
    lx: float,
    ly: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[float, float, float, float, float, float]:
    return tuple(
        edge_h_and_s(lx, ly, pe, radius=radius)[0] for pe in range(6)
    )


def vertex_corner_index(
    lx: float,
    ly: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    epsilon_factor: float = HEXPATCH_V1_VERTEX_EPSILON_FACTOR,
) -> int | None:
    tolerance = epsilon_factor * radius
    for ci in range(6):
        cx, cy = corner_xy_local(ci, radius)
        if math.hypot(lx - cx, ly - cy) <= tolerance:
            return ci
    return None


def vertex_height(
    lx: float,
    ly: float,
    corner_c_v: tuple[float, ...],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float | None:
    ci = vertex_corner_index(lx, ly, radius=radius)
    if ci is None:
        return None
    return corner_c_v[ci]


def _ribbon_field(
    slot: HexPatchEdgeSlot,
    ribbon: SharedRibbonRecord | None,
    s_i: float,
    h_i: float,
    corner_c_v: tuple[float, ...],
) -> float:
    if slot.kind == "ribbon":
        if ribbon is None:
            raise RuntimeError(f"missing ribbon for edge slot {slot.physical_edge!r}")
        t = _orient_edge_parameter(s_i, slot.ribbon_reversed)
        b_val = eval_quartic(ribbon.b_coeffs, t)
        d_val = eval_d_signed(
            ribbon.d_coeffs,
            ribbon.s_low,
            slot.cross_deriv_sign,
            t,
        )
        return b_val + h_i * d_val
    c0 = corner_c_v[slot.physical_edge]
    c1 = corner_c_v[(slot.physical_edge + 1) % 6]
    t = s_i
    b_val = c0 + (c1 - c0) * t
    return b_val


def S_patch(
    lx: float,
    ly: float,
    patch: HexPatchRecord,
    corner_c_v: tuple[float, ...],
    ribbons: dict[tuple[tuple[int, int], tuple[int, int]], SharedRibbonRecord],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    corner_height = vertex_height(lx, ly, corner_c_v, radius=radius)
    if corner_height is not None:
        return corner_height

    h_vals = all_edge_h(lx, ly, radius=radius)
    d_vals: list[float] = []
    for pe in range(6):
        prod = 1.0
        h_pe = h_vals[pe]
        for j in range(6):
            if j == pe:
                continue
            prod *= h_vals[j] * h_vals[j]
        d_vals.append(prod)
    weight_sum = sum(d_vals)
    if weight_sum <= 1e-18:
        return 0.0

    value = 0.0
    for pe in range(6):
        phi = d_vals[pe] / weight_sum
        slot = patch.edge_slots[pe]
        ribbon = ribbons.get(slot.edge_key) if slot.edge_key is not None else None
        _h_i, s_i = edge_h_and_s(lx, ly, pe, radius=radius)
        r_i = _ribbon_field(slot, ribbon, s_i, h_vals[pe], corner_c_v)
        value += phi * r_i
    return value


def beta(
    lx: float,
    ly: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    ap = hex_apothem(radius=radius)
    if ap <= 1e-18:
        return 1.0
    h_vals = all_edge_h(lx, ly, radius=radius)
    result = 1.0
    for h_i in h_vals:
        result *= perlin_smootherstep(h_i / ap)
    return result


def S_final(
    lx: float,
    ly: float,
    ctx: HexPatchEvalContext,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    corner_height = vertex_height(lx, ly, ctx.corner_c_v, radius=radius)
    if corner_height is not None:
        return corner_height
    s_patch = S_patch(
        lx,
        ly,
        ctx.patch,
        ctx.corner_c_v,
        ctx.ribbons,
        radius=radius,
    )
    return s_patch + ctx.delta_z * beta(lx, ly, radius=radius)


def S_final_from_patch(
    lx: float,
    ly: float,
    graph: HexPatchV1Graph,
    patch: HexPatchRecord,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    ctx = build_hexpatch_eval_context(graph, patch, radius=radius)
    return S_final(lx, ly, ctx, radius=radius)


def _rotate_local(lx: float, ly: float, steps: int) -> tuple[float, float]:
    angle = math.radians(60.0 * float(steps))
    c = math.cos(angle)
    s = math.sin(angle)
    return lx * c - ly * s, lx * s + ly * c


def _make_constant_eval_context(
    height: float,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> HexPatchEvalContext:
    key = SharedCornerKey(corner_position=(0.0, 0.0), component_id=((0, 0),))
    coeffs_b = QuarticCoeffs(height, 0.0, 0.0, 0.0, 0.0)
    coeffs_d = QuadraticCoeffs(0.0, 0.0, 0.0)
    edge_key = ((0, 0), (1, 0))
    ribbon = SharedRibbonRecord(
        edge_key=edge_key,
        corner_key_start=key,
        corner_key_end=key,
        b_coeffs=coeffs_b,
        d_coeffs=coeffs_d,
        s_low=0.0,
        h_mid=height,
    )
    ribbons = {edge_key: ribbon}
    slots = tuple(
        HexPatchEdgeSlot(
            physical_edge=pe,
            kind="ribbon",
            edge_key=edge_key,
            ribbon_reversed=False,
            cross_deriv_sign=0,
        )
        for pe in range(6)
    )
    patch = HexPatchRecord(
        tile=(0, 0),
        z_center=height,
        corner_keys=tuple(key for _ in range(6)),
        edge_slots=slots,
    )
    return HexPatchEvalContext(
        patch=patch,
        corner_c_v=(height, height, height, height, height, height),
        ribbons=ribbons,
        delta_z=0.0,
    )


def _run_evaluator_self_tests() -> None:
    radius = DEFAULT_HEX_RADIUS
    ctx_const = _make_constant_eval_context(3.5, radius=radius)
    probe_points = [
        (0.0, 0.0),
        (0.2, 0.1),
        (-0.3, 0.15),
        (0.4, -0.2),
    ]
    for lx, ly in probe_points:
        v1 = S_final(lx, ly, ctx_const, radius=radius)
        v2 = S_final(lx, ly, ctx_const, radius=radius)
        assert v1 == v2, (lx, ly, v1, v2)
        assert abs(v1 - 3.5) < 1e-9, (lx, ly, v1)

    for ci in range(6):
        cx, cy = corner_xy_local(ci, radius)
        v = S_final(cx, cy, ctx_const, radius=radius)
        assert abs(v - 3.5) < 1e-9, (ci, v)

    ctx_bubble = _make_constant_eval_context(2.0, radius=radius)
    target_z = 2.75
    bubble_patch = HexPatchRecord(
        tile=ctx_bubble.patch.tile,
        z_center=target_z,
        corner_keys=ctx_bubble.patch.corner_keys,
        edge_slots=ctx_bubble.patch.edge_slots,
    )
    ctx_bubble = HexPatchEvalContext(
        patch=bubble_patch,
        corner_c_v=ctx_bubble.corner_c_v,
        ribbons=ctx_bubble.ribbons,
        delta_z=target_z - 2.0,
    )
    center_final = S_final(0.0, 0.0, ctx_bubble, radius=radius)
    assert abs(center_final - target_z) < 1e-9, center_final

    for lx, ly in probe_points:
        base = S_patch(
            lx,
            ly,
            ctx_const.patch,
            ctx_const.corner_c_v,
            ctx_const.ribbons,
            radius=radius,
        )
        sym_vals = [
            S_patch(
                *_rotate_local(lx, ly, k),
                ctx_const.patch,
                ctx_const.corner_c_v,
                ctx_const.ribbons,
                radius=radius,
            )
            for k in range(6)
        ]
        for sv in sym_vals:
            assert abs(sv - base) < 1e-9, (lx, ly, base, sv)

    from eom_terrain_math_core import (
        build_terrain_model,
        handdrawn_center_world_xy,
        handdrawn_corner_world_xy,
        _baseline_neighbor_direction,
        _physical_edge_for_baseline_neighbor,
    )

    two_tile = """
    {
      "id": "hxp02a_orientation",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2}
      ]
    }
    """
    model = build_terrain_model(two_tile, radius=radius)
    graph = model.hexpatch_v1_graph
    assert graph is not None
    patch_a = patch_for_tile(graph, (0, 0))
    patch_b = patch_for_tile(graph, (1, 0))
    ctx_a = build_hexpatch_eval_context(graph, patch_a, radius=radius)
    ctx_b = build_hexpatch_eval_context(graph, patch_b, radius=radius)
    dir_a = _baseline_neighbor_direction((0, 0), (1, 0))
    pe_a = _physical_edge_for_baseline_neighbor(dir_a)
    c0 = handdrawn_corner_world_xy(0, 0, pe_a, radius)
    c1 = handdrawn_corner_world_xy(0, 0, (pe_a + 1) % 6, radius)
    cx0, cy0 = handdrawn_center_world_xy(0, 0, radius)
    cx1, cy1 = handdrawn_center_world_xy(1, 0, radius)
    for step in range(1, 8):
        t = float(step) / 8.0
        wx = c0[0] * (1.0 - t) + c1[0] * t
        wy = c0[1] * (1.0 - t) + c1[1] * t
        lx_a = wx - cx0
        ly_a = wy - cy0
        lx_b = wx - cx1
        ly_b = wy - cy1
        za = S_final(lx_a, ly_a, ctx_a, radius=radius)
        zb = S_final(lx_b, ly_b, ctx_b, radius=radius)
        assert abs(za - zb) < 1e-5, (step, t, za, zb)

    print("eom_hexpatch_v1_evaluator self-test passed")


if __name__ == "__main__":
    _run_evaluator_self_tests()
    from eom_hexpatch_v1_audits import run_hexpatch_v1_audit_fixtures

    reports = run_hexpatch_v1_audit_fixtures()
    failed = [r for r in reports if not r["ok"]]
    assert not failed, failed
    print("eom_hexpatch_v1_evaluator contract audits passed")
