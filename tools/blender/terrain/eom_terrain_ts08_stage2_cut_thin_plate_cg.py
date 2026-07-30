# Empire of Minds — TS-08 Stage 2 cut-domain thin-plate CG solver.
# Solves E(z) = Σ_i ((L z)_i)² on the Stage 0 cut lattice (Ω_cut).

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from eom_terrain_math_core import DEFAULT_HEX_RADIUS, DEFAULT_SURFACE_SUBDIVISIONS, pos_key
from eom_terrain_ts08_cut_lattice import (
    EXPECTED_CENTER_PIN_COUNT,
    EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT,
    EXPECTED_HEX_COUNT,
    EXPECTED_TRIANGLE_COUNT,
    CutLatticeBuild,
    build_component_reports,
    build_cut_lattice_for_model,
)
from eom_terrain_ts08_thin_plate_cg import (
    CG_MAX_ITERATIONS,
    CG_REL_TOL,
    _ThinPlateOperator,
    build_flattened_neighbors,
)

MAP_ID = "terrain_handdrawn_test_map_full_01"
PROTOTYPE_ID = "TS-08-STAGE-2-CUT-DOMAIN-THIN-PLATE-CG"


@dataclass
class CutDomainCgSolveReport:
    node_count: int
    triangle_count: int
    pinned_center_count: int
    connected_component_count: int
    deficient_component_count: int
    cg_iterations: int
    cg_final_abs_residual: float
    cg_final_rel_residual: float
    energy_initial: float
    energy_final: float
    z_min: float
    z_max: float
    max_center_interpolation_error: float
    max_tent_pole_delta: float
    converged: bool
    component_reports: list[dict[str, Any]]


def _planar_warm_start(
    lattice: CutLatticeBuild,
    pinned_idx: np.ndarray,
    z_pin: np.ndarray,
) -> np.ndarray:
    pin_xy = np.asarray([lattice.node_xy[int(index)] for index in pinned_idx], dtype=np.float64)
    design = np.column_stack(
        [
            np.ones(len(pinned_idx), dtype=np.float64),
            pin_xy[:, 0],
            pin_xy[:, 1],
        ]
    )
    coeff, _, _, _ = np.linalg.lstsq(design, z_pin, rcond=None)
    all_xy = np.asarray(lattice.node_xy, dtype=np.float64)
    z_full = coeff[0] + coeff[1] * all_xy[:, 0] + coeff[2] * all_xy[:, 1]
    z_full[pinned_idx] = z_pin
    return z_full


def _apply_analytic_constant(
    z_full: np.ndarray,
    component_nodes: np.ndarray,
    z_value: float,
) -> None:
    z_full[component_nodes] = z_value


def _apply_analytic_plane(
    lattice: CutLatticeBuild,
    z_full: np.ndarray,
    component_nodes: np.ndarray,
    pin_indices: list[int],
    pin_z: list[float],
) -> None:
    if len(pin_indices) != 2:
        raise RuntimeError("analytic_plane requires exactly two pins")
    x0, y0 = lattice.node_xy[pin_indices[0]]
    x1, y1 = lattice.node_xy[pin_indices[1]]
    z0, z1 = pin_z
    dx = x1 - x0
    dy = y1 - y0
    dist_sq = dx * dx + dy * dy
    if dist_sq <= 0.0:
        z_full[component_nodes] = z0
        return
    dist = dist_sq ** 0.5
    slope = (z1 - z0) / dist
    for node_index in component_nodes:
        wx, wy = lattice.node_xy[int(node_index)]
        t = ((wx - x0) * dx + (wy - y0) * dy) / dist
        z_full[int(node_index)] = z0 + slope * t


def _solve_cg_plain_global(
    operator: _ThinPlateOperator,
    n: int,
    free_idx: np.ndarray,
    pinned_idx: np.ndarray,
    z_pin: np.ndarray,
    z_warm_full: np.ndarray,
    *,
    rel_tol: float,
    max_iterations: int,
) -> tuple[np.ndarray, int, float, float, float, float, bool]:
    z_pin_embedded = np.zeros(n, dtype=np.float64)
    z_pin_embedded[pinned_idx] = z_pin

    rhs = -operator.apply_B(z_pin_embedded)[free_idx]
    rhs_norm = float(np.linalg.norm(rhs))

    energy_initial = operator.compute_energy(z_warm_full)
    x0 = z_warm_full[free_idx].copy()

    diag_B = operator.jacobi_diagonal()
    precond_inv = 1.0 / diag_B[free_idx]

    def matvec_free(x_free: np.ndarray) -> np.ndarray:
        z_full = np.zeros(n, dtype=np.float64)
        z_full[free_idx] = x_free
        return operator.apply_B(z_full)[free_idx]

    x = x0.copy()
    r = rhs - matvec_free(x)
    abs_residual = float(np.linalg.norm(r))
    rel_residual = abs_residual / rhs_norm if rhs_norm > 0.0 else 0.0

    z = precond_inv * r
    p = z.copy()
    rsold = float(np.dot(r, z))
    iterations = 0
    converged = rel_residual <= rel_tol

    if not converged and rhs_norm > 0.0:
        for iteration in range(max_iterations):
            Ap = matvec_free(p)
            alpha = rsold / float(np.dot(p, Ap))
            x += alpha * p
            r -= alpha * Ap
            abs_residual = float(np.linalg.norm(r))
            rel_residual = abs_residual / rhs_norm
            iterations = iteration + 1
            if rel_residual <= rel_tol:
                converged = True
                break
            z = precond_inv * r
            rsnew = float(np.dot(r, z))
            p = z + (rsnew / rsold) * p
            rsold = rsnew

    z_full = z_pin_embedded.copy()
    z_full[free_idx] = x
    energy_final = operator.compute_energy(z_full)
    return z_full, iterations, abs_residual, rel_residual, energy_initial, energy_final, converged


def solve_cut_domain_thin_plate_cg(
    lattice: CutLatticeBuild,
    model: Any,
    *,
    rel_tol: float = CG_REL_TOL,
    max_iterations: int = CG_MAX_ITERATIONS,
) -> tuple[np.ndarray, CutDomainCgSolveReport]:
    if lattice.node_count != EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT:
        raise RuntimeError(
            f"unexpected cut node count: {lattice.node_count} "
            f"(expected {EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT})"
        )
    if len(lattice.pinned) != EXPECTED_CENTER_PIN_COUNT:
        raise RuntimeError(
            f"unexpected pin count: {len(lattice.pinned)} "
            f"(expected {EXPECTED_CENTER_PIN_COUNT})"
        )
    if len(lattice.triangles) != EXPECTED_TRIANGLE_COUNT:
        raise RuntimeError(
            f"unexpected triangle count: {len(lattice.triangles)} "
            f"(expected {EXPECTED_TRIANGLE_COUNT})"
        )

    component_reports = build_component_reports(lattice, model)
    n = lattice.node_count
    pinned_idx = np.sort(np.fromiter(lattice.pinned.keys(), dtype=np.int64))
    pinned_mask = np.zeros(n, dtype=bool)
    pinned_mask[pinned_idx] = True
    free_idx = np.nonzero(~pinned_mask)[0]
    z_pin = np.asarray([lattice.pinned[int(index)] for index in pinned_idx], dtype=np.float64)

    neighbor_idx, _neighbor_ptr, node_ids_repeat, degrees = build_flattened_neighbors(
        lattice.adjacency
    )
    operator = _ThinPlateOperator(neighbor_idx, node_ids_repeat, degrees, n)

    z_full = np.zeros(n, dtype=np.float64)
    cg_components = [report for report in component_reports if report.gauge_method == "cg_plain"]
    non_cg_components = [report for report in component_reports if report.gauge_method != "cg_plain"]

    for report in non_cg_components:
        if report.gauge_method == "cg_deflated":
            raise RuntimeError(
                f"UNSUPPORTED_GAUGE_CASE: component {report.component_id} "
                f"rank={report.pin_rank} collinear_non_affine={report.collinear_non_affine}"
            )
        component_nodes = np.asarray(
            [index for index, cid in enumerate(lattice.component_ids) if cid == report.component_id],
            dtype=np.int64,
        )
        pin_indices = [
            int(index)
            for index in component_nodes
            if int(index) in lattice.pinned
        ]
        pin_z = [lattice.pinned[index] for index in pin_indices]
        if report.gauge_method == "analytic_constant":
            _apply_analytic_constant(z_full, component_nodes, pin_z[0])
        elif report.gauge_method == "analytic_plane":
            _apply_analytic_plane(lattice, z_full, component_nodes, pin_indices, pin_z)
        else:
            raise RuntimeError(f"unsupported gauge method: {report.gauge_method}")

    total_iterations = 0
    max_abs_residual = 0.0
    max_rel_residual = 0.0
    energy_initial = 0.0
    energy_final = 0.0
    all_converged = True

    if cg_components:
        z_warm_full = _planar_warm_start(lattice, pinned_idx, z_pin)
        (
            z_cg,
            total_iterations,
            max_abs_residual,
            max_rel_residual,
            energy_initial,
            energy_final,
            all_converged,
        ) = _solve_cg_plain_global(
            operator,
            n,
            free_idx,
            pinned_idx,
            z_pin,
            z_warm_full,
            rel_tol=rel_tol,
            max_iterations=max_iterations,
        )
        for report in cg_components:
            component_nodes = np.asarray(
                [index for index, cid in enumerate(lattice.component_ids) if cid == report.component_id],
                dtype=np.int64,
            )
            z_full[component_nodes] = z_cg[component_nodes]

    max_center_error = 0.0
    for node_index, target in lattice.pinned.items():
        error = abs(float(z_full[node_index]) - target)
        if error > max_center_error:
            max_center_error = error

    max_tent_pole = 0.0
    for node_index in lattice.pinned:
        center_z = float(z_full[node_index])
        for neighbor in lattice.adjacency[node_index]:
            delta = abs(center_z - float(z_full[neighbor]))
            if delta > max_tent_pole:
                max_tent_pole = delta

    if energy_final > energy_initial + 1e-9:
        print(
            f"WARNING: energy did not decrease: initial={energy_initial:.6e} "
            f"final={energy_final:.6e}"
        )
    if not all_converged:
        print(
            f"WARNING: CG did not converge within {max_iterations} iterations: "
            f"rel_residual={max_rel_residual:.6e} (tol={rel_tol:.6e})"
        )

    solve_report = CutDomainCgSolveReport(
        node_count=n,
        triangle_count=len(lattice.triangles),
        pinned_center_count=len(pinned_idx),
        connected_component_count=len(component_reports),
        deficient_component_count=sum(1 for item in component_reports if not item.fully_determined),
        cg_iterations=total_iterations,
        cg_final_abs_residual=max_abs_residual,
        cg_final_rel_residual=max_rel_residual,
        energy_initial=energy_initial,
        energy_final=energy_final,
        z_min=float(np.min(z_full)),
        z_max=float(np.max(z_full)),
        max_center_interpolation_error=max_center_error,
        max_tent_pole_delta=max_tent_pole,
        converged=all_converged,
        component_reports=[item.__dict__ for item in component_reports],
    )
    return z_full, solve_report


class CutDomainThinPlateCgTerrainSolver:
    """TS-08 Stage 2: cut-domain thin-plate CG over Ω_cut."""

    backend = None

    def __init__(
        self,
        *,
        rel_tol: float = CG_REL_TOL,
        max_iterations: int = CG_MAX_ITERATIONS,
    ) -> None:
        self._rel_tol = rel_tol
        self._max_iterations = max_iterations
        self._model: Any | None = None
        self._lattice: CutLatticeBuild | None = None
        self._heights: np.ndarray | None = None
        self._report: CutDomainCgSolveReport | None = None

    @property
    def lattice(self) -> CutLatticeBuild | None:
        return self._lattice

    @property
    def stats(self) -> dict[str, Any] | None:
        if self._report is None:
            return None
        return {
            "node_count": self._report.node_count,
            "triangle_count": self._report.triangle_count,
            "pinned_center_count": self._report.pinned_center_count,
            "connected_component_count": self._report.connected_component_count,
            "deficient_component_count": self._report.deficient_component_count,
            "cg_iterations": self._report.cg_iterations,
            "cg_final_abs_residual": self._report.cg_final_abs_residual,
            "cg_final_rel_residual": self._report.cg_final_rel_residual,
            "energy_initial": self._report.energy_initial,
            "energy_final": self._report.energy_final,
            "z_min": self._report.z_min,
            "z_max": self._report.z_max,
            "max_center_interpolation_error": self._report.max_center_interpolation_error,
            "max_tent_pole_delta": self._report.max_tent_pole_delta,
            "converged": self._report.converged,
            "component_reports": self._report.component_reports,
        }

    def prepare(
        self,
        model: Any,
        baseline: Any,
        *,
        radius: float = DEFAULT_HEX_RADIUS,
        subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    ) -> None:
        self._model = model
        if len(model.map.tiles) != EXPECTED_HEX_COUNT:
            raise RuntimeError(
                f"unexpected hex count: {len(model.map.tiles)} (expected {EXPECTED_HEX_COUNT})"
            )
        self._lattice = build_cut_lattice_for_model(
            model,
            baseline,
            subdiv=subdiv,
            radius=radius,
        )
        self._heights, self._report = solve_cut_domain_thin_plate_cg(
            self._lattice,
            model,
            rel_tol=self._rel_tol,
            max_iterations=self._max_iterations,
        )

    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_corner: bool = False,
        at_sector_outer_edge: bool = False,
        **_: Any,
    ) -> float:
        del sector, at_corner, at_sector_outer_edge
        if self._lattice is None or self._heights is None:
            raise RuntimeError("CutDomainThinPlateCgTerrainSolver.prepare not called")
        lookup_key = (pos_key(wx, wy), (q, r))
        node = self._lattice.tile_pos_to_node.get(lookup_key)
        if node is None:
            raise RuntimeError(
                f"TS-08 Stage 2 sample miss at ({wx}, {wy}) tile=({q}, {r})"
            )
        return float(self._heights[node])
