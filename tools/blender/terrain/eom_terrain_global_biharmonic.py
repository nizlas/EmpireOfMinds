# Empire of Minds — Global fair-surface (biharmonic-with-tension) terrain solver (TS-02).
# Iterative relaxation on the cliff-cut top-surface triangulation lattice.

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    canonical_center_world_z,
    handdrawn_to_baseline_axial,
    pos_key,
)

try:
    import numpy as np

    _NUMPY_AVAILABLE = True
except ImportError:
    np = None  # type: ignore[assignment,misc]
    _NUMPY_AVAILABLE = False


@dataclass
class GlobalBiharmonicLattice:
    node_count: int
    adjacency: list[list[int]]
    pinned: dict[int, float]
    sample_lookup: dict[tuple[tuple[float, float], int], int]
    component_ids: list[int]
    component_count: int
    free_boundary_nodes: frozenset[int] = field(default_factory=frozenset)


@dataclass
class GlobalBiharmonicSolveReport:
    node_count: int
    component_count: int
    pinned_center_count: int
    free_boundary_count: int
    iteration_count: int
    final_max_update: float
    max_center_constraint_error: float
    z_min: float
    z_max: float
    tension: float
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "node_count": self.node_count,
            "component_count": self.component_count,
            "pinned_center_count": self.pinned_center_count,
            "free_boundary_count": self.free_boundary_count,
            "iteration_count": self.iteration_count,
            "final_max_update": self.final_max_update,
            "max_center_constraint_error": self.max_center_constraint_error,
            "z_min": self.z_min,
            "z_max": self.z_max,
            "tension": self.tension,
            "warnings": list(self.warnings),
        }


def _add_undirected_edge(adjacency: list[set[int]], a: int, b: int) -> None:
    if a == b:
        return
    adjacency[a].add(b)
    adjacency[b].add(a)


def build_global_biharmonic_lattice(
    model: Any,
    baseline: Any,
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> GlobalBiharmonicLattice:
    """Enumerate mesh sample positions and build cliff-cut merge graph + tri adjacency."""
    hex_coords = set(model.map.tiles.keys())
    merge_map: dict[tuple[tuple[float, float], int], int] = {}
    pinned: dict[int, float] = {}
    adjacency_sets: list[set[int]] = []

    def node_id_for(wx: float, wy: float, domain_id: int, q: int, r: int) -> int:
        key = (pos_key(wx, wy), domain_id)
        existing = merge_map.get(key)
        if existing is not None:
            return existing
        index = len(adjacency_sets)
        merge_map[key] = index
        adjacency_sets.append(set())
        return index

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        domain_id = model.tile_domain[(q_h, r_h)]
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)

        for sector in range(6):
            grid: dict[tuple[int, int], int] = {}
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = baseline.sector_barycentric_xy(sector, si, sj, subdiv)
                    wx = cx + lx
                    wy = cy + ly
                    nid = node_id_for(wx, wy, domain_id, q_h, r_h)
                    grid[(si, sj)] = nid
                    if si == 0 and sj == 0:
                        pinned[nid] = canonical_center_world_z(model.map, q_h, r_h)
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
    component_ids, component_count = _connected_components(adjacency)
    free_boundary = _identify_free_boundary_nodes(adjacency, pinned)

    return GlobalBiharmonicLattice(
        node_count=len(adjacency),
        adjacency=adjacency,
        pinned=pinned,
        sample_lookup=merge_map,
        component_ids=component_ids,
        component_count=component_count,
        free_boundary_nodes=free_boundary,
    )


def _connected_components(adjacency: list[list[int]]) -> tuple[list[int], int]:
    node_count = len(adjacency)
    component_ids = [-1] * node_count
    component_index = 0
    for start in range(node_count):
        if component_ids[start] >= 0:
            continue
        queue = [start]
        component_ids[start] = component_index
        head = 0
        while head < len(queue):
            current = queue[head]
            head += 1
            for neighbor in adjacency[current]:
                if component_ids[neighbor] >= 0:
                    continue
                component_ids[neighbor] = component_index
                queue.append(neighbor)
        component_index += 1
    return component_ids, component_index


def _identify_free_boundary_nodes(
    adjacency: list[list[int]],
    pinned: dict[int, float],
) -> frozenset[int]:
    boundary: set[int] = set()
    for node, neighbors in enumerate(adjacency):
        if node in pinned:
            continue
        if len(neighbors) < 6:
            boundary.add(node)
    return frozenset(boundary)


def _component_pin_counts(
    lattice: GlobalBiharmonicLattice,
) -> dict[int, int]:
    counts: dict[int, int] = {}
    for node, _z in lattice.pinned.items():
        comp = lattice.component_ids[node]
        counts[comp] = counts.get(comp, 0) + 1
    return counts


def _solve_fair_surface_pure_python(
    lattice: GlobalBiharmonicLattice,
    *,
    tension: float = 0.5,
    max_iterations: int = 200,
    tolerance: float = 1e-6,
    relaxation_omega: float = 0.4,
) -> tuple[list[float], GlobalBiharmonicSolveReport]:
    node_count = lattice.node_count
    z = [0.0] * node_count
    pinned = lattice.pinned

    pin_by_component: dict[int, list[float]] = {}
    for node, pin_z in pinned.items():
        comp = lattice.component_ids[node]
        pin_by_component.setdefault(comp, []).append(pin_z)

    for node in range(node_count):
        comp = lattice.component_ids[node]
        comp_pins = pin_by_component.get(comp, [])
        z[node] = sum(comp_pins) / float(len(comp_pins)) if comp_pins else 0.0
    for node, pin_z in pinned.items():
        z[node] = pin_z

    final_max_update = 0.0
    iteration_count = 0
    for iteration in range(max_iterations):
        z_next = z[:]
        max_update = 0.0
        for node in range(node_count):
            if node in pinned:
                z_next[node] = pinned[node]
                continue
            neighbors = lattice.adjacency[node]
            if not neighbors:
                continue
            membrane = sum(z[nbr] for nbr in neighbors) / float(len(neighbors))
            if tension >= 1.0 - 1e-12:
                target = membrane
            else:
                second_ring: list[float] = []
                for nbr in neighbors:
                    nbr_neighbors = lattice.adjacency[nbr]
                    if nbr_neighbors:
                        second_ring.append(
                            sum(z[nn] for nn in nbr_neighbors) / float(len(nbr_neighbors))
                        )
                if second_ring:
                    plate = 2.0 * membrane - sum(second_ring) / float(len(second_ring))
                else:
                    plate = membrane
                target = tension * membrane + (1.0 - tension) * plate
            z_next[node] = (1.0 - relaxation_omega) * z[node] + relaxation_omega * target
            max_update = max(max_update, abs(z_next[node] - z[node]))
        z = z_next
        for node, pin_z in pinned.items():
            z[node] = pin_z
        iteration_count = iteration + 1
        final_max_update = max_update
        if max_update <= tolerance:
            break

    max_center_error = max(
        (abs(z[node] - pin_z) for node, pin_z in pinned.items()),
        default=0.0,
    )
    warnings: list[str] = []
    for comp, pin_count in _component_pin_counts(lattice).items():
        if pin_count == 0:
            warnings.append(f"component {comp} has no pinned tile centers")
        elif pin_count < 3:
            warnings.append(
                f"component {comp} has only {pin_count} pinned centers (underdetermined plate)"
            )
    if max(z) > 1e3 or min(z) < -1e3:
        warnings.append("solve produced extreme z magnitudes; reduce plate weight or iterations")

    report = GlobalBiharmonicSolveReport(
        node_count=node_count,
        component_count=lattice.component_count,
        pinned_center_count=len(pinned),
        free_boundary_count=len(lattice.free_boundary_nodes),
        iteration_count=iteration_count,
        final_max_update=final_max_update,
        max_center_constraint_error=max_center_error,
        z_min=min(z) if z else 0.0,
        z_max=max(z) if z else 0.0,
        tension=tension,
        warnings=warnings,
    )
    return z, report


def _solve_fair_surface_numpy(
    lattice: GlobalBiharmonicLattice,
    *,
    tension: float = 0.5,
    max_iterations: int = 200,
    tolerance: float = 1e-6,
    relaxation_omega: float = 0.4,
) -> tuple[list[float], GlobalBiharmonicSolveReport]:
    assert np is not None
    node_count = lattice.node_count
    z = np.zeros(node_count, dtype=np.float64)
    pinned_mask = np.zeros(node_count, dtype=bool)
    pinned_values = np.zeros(node_count, dtype=np.float64)

    for node, pin_z in lattice.pinned.items():
        pinned_mask[node] = True
        pinned_values[node] = pin_z

    pin_by_component: dict[int, list[float]] = {}
    for node, pin_z in lattice.pinned.items():
        comp = lattice.component_ids[node]
        pin_by_component.setdefault(comp, []).append(pin_z)

    for node in range(node_count):
        if pinned_mask[node]:
            z[node] = pinned_values[node]
            continue
        comp_pins = pin_by_component.get(lattice.component_ids[node], [])
        z[node] = float(sum(comp_pins) / len(comp_pins)) if comp_pins else 0.0

    final_max_update = 0.0
    iteration_count = 0
    for iteration in range(max_iterations):
        z_next = z.copy()
        max_update = 0.0
        for node in range(node_count):
            if pinned_mask[node]:
                continue
            neighbors = lattice.adjacency[node]
            if not neighbors:
                continue
            neighbor_vals = z[np.array(neighbors, dtype=np.int64)]
            membrane = float(np.mean(neighbor_vals))
            if tension >= 1.0 - 1e-12:
                target = membrane
            else:
                second_ring: list[float] = []
                for nbr in neighbors:
                    nbr_neighbors = lattice.adjacency[nbr]
                    if nbr_neighbors:
                        second_ring.append(float(np.mean(z[np.array(nbr_neighbors, dtype=np.int64)])))
                if second_ring:
                    plate = 2.0 * membrane - float(sum(second_ring) / len(second_ring))
                else:
                    plate = membrane
                target = tension * membrane + (1.0 - tension) * plate
            blended = (1.0 - relaxation_omega) * float(z[node]) + relaxation_omega * target
            z_next[node] = blended
            max_update = max(max_update, abs(blended - float(z[node])))
        z = z_next
        z[pinned_mask] = pinned_values[pinned_mask]
        iteration_count = iteration + 1
        final_max_update = max_update
        if max_update <= tolerance:
            break

    max_center_error = float(
        max(
            (abs(float(z[node]) - pin_z) for node, pin_z in lattice.pinned.items()),
            default=0.0,
        )
    )
    warnings: list[str] = []
    for comp, pin_count in _component_pin_counts(lattice).items():
        if pin_count == 0:
            warnings.append(f"component {comp} has no pinned tile centers")
        elif pin_count < 3:
            warnings.append(
                f"component {comp} has only {pin_count} pinned centers (underdetermined plate)"
            )
    if node_count and (float(np.max(z)) > 1e3 or float(np.min(z)) < -1e3):
        warnings.append("solve produced extreme z magnitudes; reduce plate weight or iterations")

    report = GlobalBiharmonicSolveReport(
        node_count=node_count,
        component_count=lattice.component_count,
        pinned_center_count=len(lattice.pinned),
        free_boundary_count=len(lattice.free_boundary_nodes),
        iteration_count=iteration_count,
        final_max_update=final_max_update,
        max_center_constraint_error=max_center_error,
        z_min=float(np.min(z)) if node_count else 0.0,
        z_max=float(np.max(z)) if node_count else 0.0,
        tension=tension,
        warnings=warnings,
    )
    return z.tolist(), report


def solve_global_fair_surface(
    lattice: GlobalBiharmonicLattice,
    *,
    tension: float = 0.5,
    max_iterations: int = 200,
    tolerance: float = 1e-6,
    relaxation_omega: float = 0.4,
    prefer_numpy: bool = True,
) -> tuple[list[float], GlobalBiharmonicSolveReport]:
    if prefer_numpy and _NUMPY_AVAILABLE:
        return _solve_fair_surface_numpy(
            lattice,
            tension=tension,
            max_iterations=max_iterations,
            tolerance=tolerance,
            relaxation_omega=relaxation_omega,
        )
    return _solve_fair_surface_pure_python(
        lattice,
        tension=tension,
        max_iterations=max_iterations,
        tolerance=tolerance,
        relaxation_omega=relaxation_omega,
    )


class GlobalBiharmonicTerrainSolver:
    """Global fair-surface solver; backend enum attached in eom_terrain_solver."""

    def __init__(
        self,
        *,
        tension: float = 0.5,
        max_iterations: int = 250,
        tolerance: float = 1e-6,
        relaxation_omega: float = 0.4,
    ) -> None:
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS
        self._tension = tension
        self._max_iterations = max_iterations
        self._tolerance = tolerance
        self._relaxation_omega = relaxation_omega
        self._lattice: GlobalBiharmonicLattice | None = None
        self._heights: list[float] | None = None
        self._report: GlobalBiharmonicSolveReport | None = None

    def prepare(
        self,
        model: Any,
        *,
        radius: float = DEFAULT_HEX_RADIUS,
        baseline: Any | None = None,
        subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    ) -> None:
        if baseline is None:
            raise RuntimeError(
                "GlobalBiharmonicTerrainSolver.prepare requires baseline module "
                "(sector_barycentric_xy, axial_to_world_xy)"
            )
        self._model = model
        self._radius = radius
        self._lattice = build_global_biharmonic_lattice(
            model,
            baseline,
            subdiv=subdiv,
            radius=radius,
        )
        self._heights, self._report = solve_global_fair_surface(
            self._lattice,
            tension=self._tension,
            max_iterations=self._max_iterations,
            tolerance=self._tolerance,
            relaxation_omega=self._relaxation_omega,
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
        idw_fallback: Any = None,
        legacy_fallback: Any = None,
    ) -> float:
        assert self._model is not None
        assert self._lattice is not None
        assert self._heights is not None

        domain_id = self._model.tile_domain.get((q, r))
        if domain_id is None:
            raise RuntimeError(
                f"global_biharmonic sample outside map: tile ({q}, {r}) "
                f"world=({wx:.6f}, {wy:.6f})"
            )
        lookup_key = (pos_key(wx, wy), domain_id)
        node = self._lattice.sample_lookup.get(lookup_key)
        if node is None:
            raise RuntimeError(
                "global_biharmonic sample not on solve lattice: "
                f"tile=({q}, {r}) domain={domain_id} world=({wx:.6f}, {wy:.6f}) "
                f"pos_key={lookup_key[0]!r} sector={sector} at_corner={at_corner} "
                f"at_sector_outer_edge={at_sector_outer_edge}"
            )
        return self._heights[node]

    @property
    def stats(self) -> dict[str, Any] | None:
        if self._report is None:
            return None
        return self._report.as_dict()

    @property
    def solve_report(self) -> GlobalBiharmonicSolveReport | None:
        return self._report


def format_global_biharmonic_report(report: GlobalBiharmonicSolveReport) -> str:
    lines = [
        f"backend: global_biharmonic (tension={report.tension})",
        f"node_count: {report.node_count}",
        f"component_count: {report.component_count}",
        f"pinned_center_count: {report.pinned_center_count}",
        f"free_boundary_count: {report.free_boundary_count}",
        f"iteration_count: {report.iteration_count}",
        f"final_max_update: {report.final_max_update:.6e}",
        f"max_center_constraint_error: {report.max_center_constraint_error:.6e}",
        f"z_min: {report.z_min:.6f}",
        f"z_max: {report.z_max:.6f}",
    ]
    if report.warnings:
        lines.append(f"warnings: {'; '.join(report.warnings)}")
    return "\n".join(lines)


def _minimal_baseline_stub(radius: float = DEFAULT_HEX_RADIUS) -> Any:
    """Pure-python baseline stub for lattice self-tests (mirrors single-patch sector grid)."""
    from eom_terrain_math_core import corner_xy_local

    class _Stub:
        HEX_RADIUS = radius

        @staticmethod
        def axial_to_world_xy(q_b: int, r_b: int, radius: float) -> tuple[float, float]:
            import math

            x = radius * math.sqrt(3.0) * (float(q_b) + float(r_b) * 0.5)
            y = radius * 1.5 * float(r_b)
            return x, y

        @staticmethod
        def sector_barycentric_xy(
            sector: int,
            si: int,
            sj: int,
            subdiv: int,
        ) -> tuple[float, float]:
            if subdiv <= 0:
                return 0.0, 0.0
            ci = sector
            cj = (sector + 1) % 6
            bx, by = corner_xy_local(ci, radius)
            cx, cy = corner_xy_local(cj, radius)
            denom = float(subdiv)
            wb = float(si) / denom
            wc = float(sj) / denom
            return wb * bx + wc * cx, wb * by + wc * cy

    return _Stub()


def _run_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model, handdrawn_center_world_xy

    json_two = """
    {
      "id": "ts02_two_smooth",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2}
      ]
    }
    """
    model = build_terrain_model(json_two)
    baseline = _minimal_baseline_stub()
    subdiv = 4
    lattice = build_global_biharmonic_lattice(model, baseline, subdiv=subdiv)
    assert lattice.node_count > 0
    assert len(lattice.pinned) == 2

    heights, report = solve_global_fair_surface(
        lattice,
        tension=0.5,
        max_iterations=50,
        prefer_numpy=False,
    )
    assert report.max_center_constraint_error < 1e-9
    assert report.pinned_center_count == 2

    solver = GlobalBiharmonicTerrainSolver(tension=0.5, max_iterations=50)
    solver.prepare(model, baseline=baseline, subdiv=subdiv)
    cx, cy = handdrawn_center_world_xy(0, 0)
    h0 = solver.sample_world(cx, cy, 0, 0)
    assert abs(h0 - 0.0) < 1e-9
    cx1, cy1 = handdrawn_center_world_xy(1, 0)
    h1 = solver.sample_world(cx1, cy1, 1, 0)
    assert abs(h1 - 0.4) < 1e-9

    try:
        solver.sample_world(999.0, 999.0, 0, 0)
        raise AssertionError("expected lookup failure for off-lattice sample")
    except RuntimeError:
        pass

    print("eom_terrain_global_biharmonic self-test passed")


if __name__ == "__main__":
    _run_self_tests()
