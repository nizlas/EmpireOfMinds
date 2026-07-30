# Empire of Minds — TS-08 Stage 1 no-cut thin-plate CG solver (Γ = ∅).
# Squared graph Laplacian energy E(z) = Σ_i ((L z)_i)² solved via NumPy operator CG.
# Per docs/TERRAIN_SURFACE_TARGET.md — no scipy, no FEM, no TPS, no relaxation.

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    canonical_center_world_z,
    handdrawn_to_baseline_axial,
    pos_key,
)

MAP_ID = "terrain_handdrawn_test_map_full_01"
MAP_JSON_ID = "handdrawn_test_map_full_01"
PROTOTYPE_ID = "TS-08-STAGE-1-NO-CUT-THIN-PLATE-CG"
EXPECTED_HEX_COUNT = 168
EXPECTED_UNCUT_NODE_COUNT = 73201
EXPECTED_CENTER_PIN_COUNT = 168

CG_REL_TOL = 1e-8
CG_MAX_ITERATIONS = 40000


@dataclass
class ThinPlateCgSolveReport:
    node_count: int
    free_count: int
    pinned_center_count: int
    hex_count: int
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


@dataclass
class UncutThinPlateLattice:
    node_count: int
    node_xy: list[tuple[float, float]]
    adjacency: list[list[int]]
    pinned: dict[int, float]
    sample_lookup: dict[tuple[float, float], int]
    pin_hex_by_node: dict[int, tuple[int, int]]


def _add_undirected_edge(adjacency: list[set[int]], a: int, b: int) -> None:
    if a == b:
        return
    adjacency[a].add(b)
    adjacency[b].add(a)


def build_uncut_solver_lattice(
    model: Any,
    baseline: Any,
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> UncutThinPlateLattice:
    """Uncut top-surface barycentric lattice merged by pos_key only (Γ = ∅)."""
    hex_coords = set(model.map.tiles.keys())
    merge_map: dict[tuple[float, float], int] = {}
    node_xy: list[tuple[float, float]] = []
    pinned: dict[int, float] = {}
    pin_hex_by_node: dict[int, tuple[int, int]] = {}
    adjacency_sets: list[set[int]] = []

    def node_id_for(wx: float, wy: float, q: int, r: int) -> int:
        key = pos_key(wx, wy)
        existing = merge_map.get(key)
        if existing is not None:
            return existing
        index = len(adjacency_sets)
        merge_map[key] = index
        node_xy.append((wx, wy))
        adjacency_sets.append(set())
        return index

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        for sector in range(6):
            grid: dict[tuple[int, int], int] = {}
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = baseline.sector_barycentric_xy(sector, si, sj, subdiv)
                    wx = cx + lx
                    wy = cy + ly
                    nid = node_id_for(wx, wy, q_h, r_h)
                    grid[(si, sj)] = nid
                    if si == 0 and sj == 0:
                        pinned[nid] = canonical_center_world_z(model.map, q_h, r_h)
                        pin_hex_by_node[nid] = (q_h, r_h)
                    sj += 1

            for si in range(subdiv):
                sj = 0
                while sj <= subdiv - si - 1:
                    v00 = grid[(si, sj)]
                    v10 = grid[(si + 1, sj)]
                    v01 = grid[(si, sj + 1)]
                    _add_undirected_edge(adjacency_sets, v00, v10)
                    _add_undirected_edge(adjacency_sets, v10, v01)
                    _add_undirected_edge(adjacency_sets, v00, v01)
                    if sj + 1 <= subdiv - (si + 1):
                        v11 = grid[(si + 1, sj + 1)]
                        _add_undirected_edge(adjacency_sets, v10, v11)
                        _add_undirected_edge(adjacency_sets, v01, v11)
                    sj += 1

    adjacency = [sorted(neighbors) for neighbors in adjacency_sets]
    return UncutThinPlateLattice(
        node_count=len(adjacency),
        node_xy=node_xy,
        adjacency=adjacency,
        pinned=pinned,
        sample_lookup=merge_map,
        pin_hex_by_node=pin_hex_by_node,
    )


def build_flattened_neighbors(
    adjacency: list[list[int]],
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    neighbor_idx_list: list[int] = []
    neighbor_ptr_list: list[int] = [0]
    node_ids_repeat_list: list[int] = []
    for node_index, neighbors in enumerate(adjacency):
        neighbor_idx_list.extend(neighbors)
        neighbor_ptr_list.append(len(neighbor_idx_list))
        node_ids_repeat_list.extend([node_index] * len(neighbors))

    neighbor_idx = np.asarray(neighbor_idx_list, dtype=np.int64)
    neighbor_ptr = np.asarray(neighbor_ptr_list, dtype=np.int64)
    node_ids_repeat = np.asarray(node_ids_repeat_list, dtype=np.int64)
    degrees = np.diff(neighbor_ptr).astype(np.float64)
    degrees_safe = np.maximum(degrees, 1.0)
    return neighbor_idx, neighbor_ptr, node_ids_repeat, degrees_safe


class _ThinPlateOperator:
    """Vectorized normalized umbrella L and B = Lᵀ A L with uniform area weights."""

    def __init__(
        self,
        neighbor_idx: np.ndarray,
        node_ids_repeat: np.ndarray,
        degrees: np.ndarray,
        node_count: int,
    ) -> None:
        self._neighbor_idx = neighbor_idx
        self._node_ids_repeat = node_ids_repeat
        self._degrees = degrees
        self._n = node_count

    def apply_L(self, z: np.ndarray) -> np.ndarray:
        neighbor_sum = np.bincount(
            self._node_ids_repeat,
            weights=z[self._neighbor_idx],
            minlength=self._n,
        )
        return z - neighbor_sum / self._degrees

    def apply_LT(self, w: np.ndarray) -> np.ndarray:
        weights = w[self._node_ids_repeat] / self._degrees[self._node_ids_repeat]
        scatter = np.bincount(self._neighbor_idx, weights=weights, minlength=self._n)
        return w - scatter

    def apply_B(self, z: np.ndarray) -> np.ndarray:
        return self.apply_LT(self.apply_L(z))

    def compute_energy(self, z: np.ndarray) -> float:
        lz = self.apply_L(z)
        return float(np.dot(lz, lz))

    def jacobi_diagonal(self) -> np.ndarray:
        weights = 1.0 / (self._degrees[self._node_ids_repeat] ** 2)
        return 1.0 + np.bincount(self._neighbor_idx, weights=weights, minlength=self._n)


def _planar_warm_start(
    lattice: UncutThinPlateLattice,
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


def _max_center_error_from_pins(
    lattice: UncutThinPlateLattice,
    z_full: np.ndarray,
) -> float:
    max_error = 0.0
    for node_index, target in lattice.pinned.items():
        error = abs(float(z_full[node_index]) - target)
        if error > max_error:
            max_error = error
    return max_error


def _max_tent_pole_delta(
    lattice: UncutThinPlateLattice,
    z_full: np.ndarray,
) -> float:
    max_delta = 0.0
    for node_index in lattice.pinned:
        center_z = float(z_full[node_index])
        for neighbor in lattice.adjacency[node_index]:
            delta = abs(center_z - float(z_full[neighbor]))
            if delta > max_delta:
                max_delta = delta
    return max_delta


def solve_no_cut_thin_plate_cg(
    lattice: UncutThinPlateLattice,
    *,
    rel_tol: float = CG_REL_TOL,
    max_iterations: int = CG_MAX_ITERATIONS,
) -> tuple[np.ndarray, ThinPlateCgSolveReport]:
    if lattice.node_count != EXPECTED_UNCUT_NODE_COUNT:
        raise RuntimeError(
            f"unexpected uncut node count: {lattice.node_count} "
            f"(expected {EXPECTED_UNCUT_NODE_COUNT})"
        )
    if len(lattice.pinned) != EXPECTED_CENTER_PIN_COUNT:
        raise RuntimeError(
            f"unexpected pin count: {len(lattice.pinned)} "
            f"(expected {EXPECTED_CENTER_PIN_COUNT})"
        )

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

    z_pin_embedded = np.zeros(n, dtype=np.float64)
    z_pin_embedded[pinned_idx] = z_pin

    rhs = -operator.apply_B(z_pin_embedded)[free_idx]
    rhs_norm = float(np.linalg.norm(rhs))

    z_warm = _planar_warm_start(lattice, pinned_idx, z_pin)
    energy_initial = operator.compute_energy(z_warm)
    x0 = z_warm[free_idx].copy()

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

    if energy_final > energy_initial + 1e-9:
        print(
            f"WARNING: energy did not decrease: initial={energy_initial:.6e} "
            f"final={energy_final:.6e}"
        )

    if not converged:
        print(
            f"WARNING: CG did not converge within {max_iterations} iterations: "
            f"rel_residual={rel_residual:.6e} (tol={rel_tol:.6e})"
        )

    report = ThinPlateCgSolveReport(
        node_count=n,
        free_count=len(free_idx),
        pinned_center_count=len(pinned_idx),
        hex_count=len(lattice.pin_hex_by_node),
        cg_iterations=iterations,
        cg_final_abs_residual=abs_residual,
        cg_final_rel_residual=rel_residual,
        energy_initial=energy_initial,
        energy_final=energy_final,
        z_min=float(np.min(z_full)),
        z_max=float(np.max(z_full)),
        max_center_interpolation_error=_max_center_error_from_pins(lattice, z_full),
        max_tent_pole_delta=_max_tent_pole_delta(lattice, z_full),
        converged=converged,
    )
    return z_full, report


class GlobalNoCutThinPlateCgTerrainSolver:
    """TS-08 Stage 1: uncut thin-plate CG heightfield over the barycentric lattice."""

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
        self._radius: float = DEFAULT_HEX_RADIUS
        self._lattice: UncutThinPlateLattice | None = None
        self._heights: np.ndarray | None = None
        self._report: ThinPlateCgSolveReport | None = None

    @property
    def stats(self) -> dict[str, Any] | None:
        if self._report is None:
            return None
        return {
            "node_count": self._report.node_count,
            "free_count": self._report.free_count,
            "pinned_center_count": self._report.pinned_center_count,
            "hex_count": self._report.hex_count,
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
        self._radius = radius
        self._lattice = build_uncut_solver_lattice(
            model,
            baseline,
            subdiv=subdiv,
            radius=radius,
        )
        if len(model.map.tiles) != EXPECTED_HEX_COUNT:
            raise RuntimeError(
                f"unexpected hex count: {len(model.map.tiles)} (expected {EXPECTED_HEX_COUNT})"
            )
        self._heights, self._report = solve_no_cut_thin_plate_cg(
            self._lattice,
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
        del q, r, sector, at_corner, at_sector_outer_edge
        if self._lattice is None or self._heights is None:
            raise RuntimeError("GlobalNoCutThinPlateCgTerrainSolver.prepare not called")
        lookup_key = pos_key(wx, wy)
        node = self._lattice.sample_lookup.get(lookup_key)
        if node is None:
            raise RuntimeError(
                f"TS-08 Stage 1 sample miss at ({wx}, {wy}); lattice lookup failed"
            )
        return float(self._heights[node])
