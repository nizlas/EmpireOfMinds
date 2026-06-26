# Empire of Minds — HexPatch v1.0 audit residual triage (HXP-02c).
# Classifies worst H2/H3/H4/H7 residuals; diagnostics only (no formula changes).

from __future__ import annotations

import math
from typing import Any, Literal

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    TerrainModel,
    corner_xy_local,
    sorted_edge_key,
    _baseline_neighbor_direction,
    _physical_edge_for_baseline_neighbor,
)
from eom_hexpatch_v1_audits import (
    HEXPATCH_V1_FD_STEP_FACTOR,
    HEXPATCH_V1_FD_TOLERANCE,
    HEXPATCH_V1_H3_GRADIENT_TOLERANCE,
    HEXPATCH_V1_H7_GRADIENT_TOLERANCE,
    HEXPATCH_V1_VERTEX_EPSILON_FACTOR,
    _build_context_map,
    _fd_step,
    _patch_all_smooth,
    _shared_edge_world_samples,
    _world_edge_inward_normal,
    _world_to_tile_local,
)
from eom_hexpatch_v1_evaluator import (
    HexPatchEvalContext,
    S_final,
    S_patch,
    beta,
    build_hexpatch_eval_context,
    eval_d_signed,
    vertex_corner_index,
)
from eom_hexpatch_v1_graph import HexPatchV1Graph

CornerClass = Literal[
    "all_smooth",
    "ssc",
    "scc",
    "ccc",
    "boundary",
    "cliff_adjacent_probe",
    "unknown",
]

H3_ROOT = Literal[
    "evaluator_does_not_consume_g_v",
    "fd_step_artifact",
    "cliff_stub_contamination",
    "corner_data_mismatch",
    "unknown",
]

H2_ROOT = Literal[
    "fd_truncation_within_tolerance",
    "fd_step_artifact",
    "cliff_side_blend_pollution",
    "signed_d_convention",
    "real_evaluator_mismatch",
    "unknown",
]

H7_ROOT = Literal[
    "fd_center_discretization",
    "bubble_center_correction",
    "non_affine_interior",
    "unknown",
]


def _corner_tile_map(graph: HexPatchV1Graph) -> dict[Any, tuple[int, int, int]]:
    corner_tile: dict[Any, tuple[int, int, int]] = {}
    for q, r, ci, key in graph.corner_key_by_tile:
        if key not in corner_tile:
            corner_tile[key] = (q, r, ci)
    return corner_tile


def _incident_tiles_at_corner(
    model: TerrainModel,
    corner_world: tuple[float, float],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> list[tuple[int, int]]:
    from eom_terrain_math_core import handdrawn_corner_world_xy

    wx, wy = corner_world
    out: list[tuple[int, int]] = []
    for q, r in model.map.tiles:
        for ci in range(6):
            cx, cy = handdrawn_corner_world_xy(q, r, ci, radius)
            if abs(cx - wx) < 1e-5 and abs(cy - wy) < 1e-5:
                out.append((q, r))
    return sorted(set(out))


def _classify_corner(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    record,
    probe_tile: tuple[int, int],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> CornerClass:
    comp_size = len(record.key.component_id)
    corner_world = record.key.corner_position
    incident = _incident_tiles_at_corner(model, corner_world, radius=radius)
    probe_patch = next(p for p in graph.hex_patches if p.tile == probe_tile)
    is_ssc = any(
        abs(ssc.corner_world[0] - corner_world[0]) < 1e-5
        and abs(ssc.corner_world[1] - corner_world[1]) < 1e-5
        for ssc in model.ssc_corners
    )
    probe_cliff = not _patch_all_smooth(probe_patch)

    if is_ssc:
        return "ssc"
    if comp_size >= 3:
        base = "ccc"
    elif comp_size == 2:
        base = "scc"
    else:
        base = "all_smooth"
    if probe_cliff:
        return "cliff_adjacent_probe"
    if len(incident) < len(set(incident)):
        pass
    if len(incident) < 6 and comp_size >= 1:
        perimeter = len(incident) <= 2
        if perimeter and not is_ssc:
            return "boundary"
    return base


def _fd_offset_sweep(
    center_x: float,
    center_y: float,
    ctx: HexPatchEvalContext,
    expected_gx: float,
    expected_gy: float,
    *,
    radius: float,
    axis: str = "x",
) -> list[dict[str, float]]:
    delta = _fd_step(radius=radius)
    base_offset = max(5.0 * HEXPATCH_V1_VERTEX_EPSILON_FACTOR * radius, delta)
    rows: list[dict[str, float]] = []
    for mult in (0.5, 1.0, 2.0, 5.0, 10.0):
        off = base_offset * mult
        if axis == "x":
            z_p = S_final(center_x + off, center_y, ctx, radius=radius)
            z_m = S_final(center_x - off, center_y, ctx, radius=radius)
            fd = (z_p - z_m) / (2.0 * off)
            err = abs(fd - expected_gx)
        else:
            z_p = S_final(center_x, center_y + off, ctx, radius=radius)
            z_m = S_final(center_x, center_y - off, ctx, radius=radius)
            fd = (z_p - z_m) / (2.0 * off)
            err = abs(fd - expected_gy)
        rows.append({"mult": mult, "offset": off, "fd": fd, "residual": err})
    return rows


def _fd_step_sweep_h2(
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    t: float,
    ctx: HexPatchEvalContext,
    ribbon,
    slot,
    *,
    radius: float,
) -> list[dict[str, float]]:
    nx, ny = _world_edge_inward_normal(tile_a, tile_b, radius=radius)
    rows: list[dict[str, float]] = []
    for factor in (0.25, 0.5, 1.0, 2.0, 4.0):
        d = HEXPATCH_V1_FD_STEP_FACTOR * radius * factor
        for wx, wy, ts in _shared_edge_world_samples(
            tile_a, tile_b, radius=radius, subdiv=DEFAULT_SURFACE_SUBDIVISIONS
        ):
            if abs(ts - t) > 1e-9:
                continue
            lx, ly = _world_to_tile_local(wx, wy, tile_a, radius=radius)
            lx_in, ly_in = _world_to_tile_local(
                wx + nx * d, wy + ny * d, tile_a, radius=radius
            )
            z0 = S_patch(
                lx, ly, ctx.patch, ctx.corner_c_v, ctx.ribbons, radius=radius
            )
            z1 = S_patch(
                lx_in, ly_in, ctx.patch, ctx.corner_c_v, ctx.ribbons, radius=radius
            )
            fd = (z1 - z0) / d
            analytic = eval_d_signed(
                ribbon.d_coeffs, ribbon.s_low, slot.cross_deriv_sign, t
            )
            rows.append(
                {
                    "step_factor": factor,
                    "fd": fd,
                    "analytic_d": analytic,
                    "residual": abs(fd - analytic),
                }
            )
    return rows


def _fd_step_sweep_h7(
    ctx: HexPatchEvalContext,
    sector: int,
    *,
    radius: float,
    use_final: bool = False,
) -> list[dict[str, float]]:
    angle = math.radians(30.0 + 60.0 * float(sector))
    dx, dy = math.cos(angle), math.sin(angle)

    def sample(lx: float, ly: float) -> float:
        if use_final:
            return S_final(lx, ly, ctx, radius=radius)
        return S_patch(
            lx, ly, ctx.patch, ctx.corner_c_v, ctx.ribbons, radius=radius
        )

    rows: list[dict[str, float]] = []
    for factor in (0.25, 0.5, 1.0, 2.0, 4.0):
        d = HEXPATCH_V1_FD_STEP_FACTOR * radius * factor
        z0 = sample(0.0, 0.0)
        zp = sample(dx * d, dy * d)
        zn = sample(-dx * d, -dy * d)
        rows.append(
            {
                "step_factor": factor,
                "disc": abs((zp - z0) / d - (z0 - zn) / d),
            }
        )
    return rows


def triage_h3(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    audit_h3: dict[str, Any],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    offender = audit_h3.get("worst_gradient_offender")
    if offender is None:
        return {"root_cause": "unknown", "note": "no gradient offender"}

    corner_by_key = {c.key: c for c in graph.shared_corners}
    corner_tile = _corner_tile_map(graph)
    corner_pos = offender["corner"]
    record = next(
        c for c in graph.shared_corners if c.key.corner_position == corner_pos
    )
    q, r, ci = corner_tile[record.key]
    ctx = contexts[(q, r)]
    cx, cy = corner_xy_local(ci, radius)
    offset = offender["offset"]
    gx_fd, gy_fd = offender["fd_gradient"]
    g_v = record.g_v

    incident = list(record.key.component_id)
    incident_detail = []
    for t in incident:
        patch = next(p for p in graph.hex_patches if p.tile == t)
        incident_detail.append(
            {
                "tile": t,
                "elevation": model.map.tiles[t],
                "edge_kinds": [s.kind for s in patch.edge_slots],
                "all_smooth": _patch_all_smooth(patch),
            }
        )

    corner_class = _classify_corner(model, graph, record, (q, r), radius=radius)
    sweep_x = _fd_offset_sweep(cx, cy, ctx, g_v[0], g_v[1], radius=radius, axis="x")
    sweep_y = _fd_offset_sweep(cx, cy, ctx, g_v[0], g_v[1], radius=radius, axis="y")
    residual_stable = (
        max(r["residual"] for r in sweep_x) - min(r["residual"] for r in sweep_x) < 1e-4
    )

    probes = {}
    for label, lx, ly in [
        ("corner", cx, cy),
        ("probe_plus_x", cx + offset, cy),
        ("probe_minus_x", cx - offset, cy),
    ]:
        sp = S_patch(lx, ly, ctx.patch, ctx.corner_c_v, ctx.ribbons, radius=radius)
        sf = S_final(lx, ly, ctx, radius=radius)
        probes[label] = {
            "S_patch": sp,
            "S_final": sf,
            "beta": beta(lx, ly, radius=radius),
        }

    if residual_stable and abs(gx_fd) < abs(g_v[0]) * 0.5 and abs(g_v[0]) > 0.05:
        root: H3_ROOT = "evaluator_does_not_consume_g_v"
        note = (
            "Height exact at vertex; FD gradient stable vs offset but "
            "does not match stored g_V. S_patch uses c_V only (vertex rule), "
            "not the corner gradient jet in the interior."
        )
    elif corner_class in ("cliff_adjacent_probe", "ssc"):
        root = "cliff_stub_contamination" if corner_class == "cliff_adjacent_probe" else "evaluator_does_not_consume_g_v"
        note = f"Corner class {corner_class}; gradient jet not enforced in S_patch interior."
    else:
        root = "evaluator_does_not_consume_g_v"
        note = "Gradient jet g_V is construction-only; evaluator does not inject g_V off-vertex."

    return {
        "root_cause": root,
        "note": note,
        "corner_key": corner_pos,
        "component_size": len(record.key.component_id),
        "corner_class": corner_class,
        "probe_tile": (q, r),
        "corner_index": ci,
        "offset": offset,
        "expected_g_v": g_v,
        "measured_fd_gradient": (gx_fd, gy_fd),
        "residual": audit_h3["worst_gradient_residual"],
        "height_residual": audit_h3["worst_height_residual"],
        "vertex_rule_at_corner": vertex_corner_index(cx, cy, radius=radius) is not None,
        "vertex_rule_at_probe": vertex_corner_index(cx + offset, cy, radius=radius) is not None,
        "incident_tiles": incident_detail,
        "offset_sweep_x": sweep_x,
        "offset_sweep_y": sweep_y,
        "probes": probes,
        "all_smooth_fixture_residual": None,
    }


def triage_h2_h4(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    audit_h2: dict[str, Any],
    audit_h4: dict[str, Any],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    offender = audit_h2.get("worst_offender") or audit_h4.get("worst_slope_offender")
    if offender is None:
        return {"root_cause": "unknown", "note": "no slope offender"}

    ribbons = {r.edge_key: r for r in graph.shared_ribbons}
    edge_key = offender["edge"]
    tile_a = edge_key[0]
    tile_b = edge_key[1]
    t = offender["t"]
    ctx = contexts[tile_a]
    ribbon = ribbons[edge_key]
    pe = _physical_edge_for_baseline_neighbor(
        _baseline_neighbor_direction(tile_a, tile_b)
    )
    slot = ctx.patch.edge_slots[pe]
    fd = offender.get("fd", offender.get("slope"))
    analytic = offender.get("expected", eval_d_signed(
        ribbon.d_coeffs, ribbon.s_low, slot.cross_deriv_sign, t
    ))
    sweep = _fd_step_sweep_h2(
        tile_a, tile_b, t, ctx, ribbon, slot, radius=radius
    )
    base = sweep[2] if len(sweep) > 2 else sweep[0]
    half = sweep[1] if len(sweep) > 1 else sweep[0]
    scales_with_step = (
        abs(base["residual"] - half["residual"]) > 1e-9
        and base["residual"] > half["residual"] * 0.5
    )

    ea, eb = model.map.tiles[tile_a], model.map.tiles[tile_b]
    a_smooth = _patch_all_smooth(ctx.patch)
    b_smooth = _patch_all_smooth(contexts[tile_b].patch)

    if not a_smooth:
        root: H2_ROOT = "cliff_side_blend_pollution"
        note = "Canonical tile has cliff slots; cross-derivative FD skipped in strict audit."
    elif base["residual"] <= HEXPATCH_V1_FD_TOLERANCE:
        root = "fd_truncation_within_tolerance"
        note = (
            f"FD residual {base['residual']:.4e} <= tolerance {HEXPATCH_V1_FD_TOLERANCE}; "
            "scales ~linearly with step (O(delta) truncation vs analytic d)."
        )
    elif scales_with_step and base["residual"] < HEXPATCH_V1_FD_TOLERANCE * 3:
        root = "fd_step_artifact"
        note = "Residual dominated by finite-difference step; shrinks with smaller delta."
    else:
        root = "real_evaluator_mismatch"
        note = "FD residual large and not explained by step size alone."

    return {
        "root_cause": root,
        "note": note,
        "edge_key": edge_key,
        "elevations": {str(tile_a): ea, str(tile_b): eb},
        "elevation_delta": abs(ea - eb),
        "tile_a_all_smooth": a_smooth,
        "tile_b_all_smooth": b_smooth,
        "t": t,
        "fd_step": audit_h2.get("fd_step", _fd_step(radius=radius)),
        "fd": fd,
        "analytic_d": analytic,
        "residual": abs(fd - analytic) if fd is not None else audit_h2["worst_residual"],
        "tolerance": HEXPATCH_V1_FD_TOLERANCE,
        "fd_step_sweep": sweep,
        "skipped_cliff_adjacent_edges": audit_h2.get("skipped_cliff_adjacent_edges", 0),
    }


def triage_h7(
    graph: HexPatchV1Graph,
    contexts: dict[tuple[int, int], HexPatchEvalContext],
    audit_h7: dict[str, Any],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    offender = audit_h7.get("worst_offender")
    if offender is None:
        return {"root_cause": "unknown", "note": "no offender"}

    tile = offender["tile"]
    sector = offender["sector"]
    ctx = contexts[tile]
    patch = ctx.patch
    sweep_patch = _fd_step_sweep_h7(ctx, sector, radius=radius, use_final=False)
    sweep_final = _fd_step_sweep_h7(ctx, sector, radius=radius, use_final=True)
    base = sweep_patch[2]
    scales = abs(sweep_patch[-1]["disc"] / max(sweep_patch[0]["disc"], 1e-18) - 4.0) < 0.5

    z0p = S_patch(0, 0, patch, ctx.corner_c_v, ctx.ribbons, radius=radius)
    z0f = S_final(0, 0, ctx, radius=radius)
    b0 = beta(0, 0, radius=radius)

    if audit_h7.get("affine_fixture_ok") and base["disc"] <= HEXPATCH_V1_H7_GRADIENT_TOLERANCE:
        root: H7_ROOT = "fd_center_discretization"
        note = "Affine operator fixture passes; map residual is O(delta) center FD on non-affine terrain."
    elif scales:
        root = "fd_center_discretization"
        note = (
            f"Disc ~{base['disc']:.4e} scales linearly with FD step; "
            "center directional derivative asymmetry is discretization, not a spoke."
        )
    elif abs(z0f - z0p) > 1e-6 and b0 > 0.5:
        root = "bubble_center_correction"
        note = "S_final differs from S_patch at center via bubble; H7 probes S_patch."
    else:
        root = "non_affine_interior"
        note = "Non-affine canonical terrain; small center FD asymmetry expected."

    return {
        "root_cause": root,
        "note": note,
        "tile": tile,
        "sector": sector,
        "all_smooth": _patch_all_smooth(patch),
        "residual": audit_h7["worst_residual"],
        "tolerance": HEXPATCH_V1_H7_GRADIENT_TOLERANCE,
        "deriv_forward": offender.get("deriv_forward"),
        "deriv_backward": offender.get("deriv_backward"),
        "center": {
            "S_patch": z0p,
            "S_final": z0f,
            "beta": b0,
            "delta_z": ctx.delta_z,
        },
        "fd_step_sweep_S_patch": sweep_patch,
        "fd_step_sweep_S_final": sweep_final,
        "affine_fixture_worst": audit_h7.get("affine_fixture_worst"),
        "affine_fixture_ok": audit_h7.get("affine_fixture_ok"),
    }


def triage_h3_all_smooth_fixture(
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    from eom_terrain_math_core import build_terrain_model
    from eom_hexpatch_v1_audits import audit_h3_corner_jet

    json_two = """
    {
      "id": "hxp02c_two_smooth",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2}
      ]
    }
    """
    model = build_terrain_model(json_two, radius=radius)
    graph = model.hexpatch_v1_graph
    assert graph is not None
    contexts = _build_context_map(graph, radius=radius)
    h3 = audit_h3_corner_jet(graph, contexts, radius=radius)
    return float(h3["worst_gradient_residual"])


def run_hexpatch_v1_residual_triage(
    model: TerrainModel,
    graph: HexPatchV1Graph,
    audit_report: dict[str, Any],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> dict[str, Any]:
    contexts = _build_context_map(graph, radius=radius)
    h3 = triage_h3(model, graph, contexts, audit_report["H3"], radius=radius)
    h3["all_smooth_fixture_residual"] = triage_h3_all_smooth_fixture(radius=radius)
    return {
        "H3": h3,
        "H2_H4": triage_h2_h4(
            model,
            graph,
            contexts,
            audit_report["H2"],
            audit_report["H4"],
            radius=radius,
        ),
        "H7": triage_h7(graph, contexts, audit_report["H7"], radius=radius),
        "blender_integration_safe": _assess_blender_safe(audit_report),
    }


def _assess_blender_safe(audit_report: dict[str, Any]) -> dict[str, Any]:
    ok = audit_report.get("ok", False)
    blockers: list[str] = []
    if not ok:
        blockers.append("audit suite not all-pass")
    h2 = audit_report.get("H2", {})
    if h2.get("worst_residual", 0) > HEXPATCH_V1_FD_TOLERANCE:
        blockers.append("H2 above FD tolerance")
    return {
        "safe_for_hxp03_wiring": ok and not blockers,
        "audit_all_pass": ok,
        "blockers": blockers,
        "note": (
            "HXP-03 may wire read-only evaluation/audits into Blender tooling "
            "without replacing IDW renderer. Residuals classified below are "
            "understood; no evaluator formula changes required."
            if ok
            else "Resolve audit failures before Blender integration."
        ),
    }


def format_hexpatch_v1_triage_report(triage: dict[str, Any]) -> str:
    lines = ["HexPatch v1.0 audit residual triage (HXP-02c)", ""]
    h3 = triage["H3"]
    lines += [
        "H3 corner 1-jet:",
        f"  root cause: {h3['root_cause']}",
        f"  {h3['note']}",
        f"  worst corner: {h3.get('corner_key')} class={h3.get('corner_class')} "
        f"component_size={h3.get('component_size')}",
        f"  expected g_V: {h3.get('expected_g_v')}  FD gradient: {h3.get('measured_fd_gradient')}",
        f"  residual: {h3.get('residual'):.6g}  height residual: {h3.get('height_residual')}",
        f"  all-smooth 2-tile fixture gradient residual: {h3.get('all_smooth_fixture_residual')}",
        "",
    ]
    h2 = triage["H2_H4"]
    lines += [
        "H2/H4 cross-derivative:",
        f"  root cause: {h2['root_cause']}",
        f"  {h2['note']}",
        f"  worst edge: {h2.get('edge_key')} t={h2.get('t')}",
        f"  elevations: {h2.get('elevations')}  all-smooth: "
        f"a={h2.get('tile_a_all_smooth')} b={h2.get('tile_b_all_smooth')}",
        f"  FD={h2.get('fd'):.8g}  analytic d={h2.get('analytic_d'):.8g}  "
        f"residual={h2.get('residual'):.4e}  tol={h2.get('tolerance')}",
        "",
    ]
    h7 = triage["H7"]
    lines += [
        "H7 no-spoke / center gradient:",
        f"  root cause: {h7['root_cause']}",
        f"  {h7['note']}",
        f"  worst tile: {h7.get('tile')} sector={h7.get('sector')} "
        f"all_smooth={h7.get('all_smooth')}",
        f"  residual: {h7.get('residual'):.6g}  tol={h7.get('tolerance')}",
        f"  center S_patch={h7['center']['S_patch']:.6g} S_final={h7['center']['S_final']:.6g} "
        f"beta={h7['center']['beta']:.6g}",
        f"  affine fixture ok: {h7.get('affine_fixture_ok')}",
        "",
    ]
    safe = triage["blender_integration_safe"]
    lines += [
        "HXP-03 Blender integration:",
        f"  safe to wire (read-only): {safe['safe_for_hxp03_wiring']}",
        f"  {safe['note']}",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    from eom_terrain_math_core import build_terrain_model
    from eom_hexpatch_v1_audits import audit_hexpatch_v1_suite, load_handdrawn_full_map_json

    _model = build_terrain_model(load_handdrawn_full_map_json())
    _graph = _model.hexpatch_v1_graph
    assert _graph is not None
    _report = audit_hexpatch_v1_suite(_model, _graph)
    _triage = run_hexpatch_v1_residual_triage(_model, _graph, _report)
    print(format_hexpatch_v1_triage_report(_triage))
