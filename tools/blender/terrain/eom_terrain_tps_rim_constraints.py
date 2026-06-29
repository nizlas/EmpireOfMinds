# Empire of Minds — TS-06 TPS with explicit cliff-front rim constraints (experimental).
# Per-cluster scattered-data TPS: tile centers + hard rim samples from connected cliff fronts.

from __future__ import annotations

TS06_MODULE_VERSION = "ts06_rim_constraints_2026_06_28"
print("LOADED TS06 MODULE:", __file__, "VERSION:", TS06_MODULE_VERSION)

from collections import defaultdict
from dataclasses import dataclass
from typing import Any

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    _baseline_neighbor_direction,
    _physical_edge_for_baseline_neighbor,
    canonical_center_world_z,
    corner_xy_local,
    handdrawn_center_world_xy,
    sector_barycentric_xy,
    tile_world_z,
)
from eom_terrain_variational_spline import (
    ComponentSolveReport,
    VariationalSplineSolveReport,
    VariationalSplineTerrainSolver,
    _affine_invariance_tests,
    _audit_representative_cliff_edge,
    _component_centers,
    build_cliff_side_cluster_lookup,
    solve_component_field,
)
from eom_terrain_variational_spline import _NUMPY_AVAILABLE as _VS_NUMPY_AVAILABLE

try:
    from numpy.linalg import LinAlgError
except ImportError:
    LinAlgError = Exception  # type: ignore[misc,assignment]

TS06_RIM_EDGE_T_PARAMS = (0.15, 0.325, 0.5, 0.675, 0.85)
REPRESENTATIVE_CLIFF = ((4, 0), (5, 0))


@dataclass(frozen=True)
class CliffFront:
    front_id: int
    edges: tuple[Any, ...]
    cliff_pairs: frozenset[frozenset[tuple[int, int]]]


@dataclass
class CliffFrontSideSegment:
    """Own-side height profile for one cliff edge (v1: constant per segment)."""

    front_id: int
    cliff: Any
    side_tile: tuple[int, int]
    other_tile: tuple[int, int]
    height: float

    def height_at(self, _t: float) -> float:
        return self.height


@dataclass
class CliffFrontSideProfile:
    """1D height data along a connected cliff front, per side tile."""

    front_id: int
    side_tile: tuple[int, int]
    segments: tuple[CliffFrontSideSegment, ...]

    def height_for_edge(self, cliff: Any) -> float:
        for segment in self.segments:
            if segment.cliff is cliff and segment.side_tile == self.side_tile:
                return segment.height
        raise KeyError(f"no segment for cliff {cliff} on tile {self.side_tile}")


@dataclass
class CliffFrontBuildStats:
    front_id: int
    edge_count: int
    rim_sample_count: int
    clusters_touched: frozenset[frozenset[tuple[int, int]]]


@dataclass
class RimConstraintClusterReport:
    cluster_id: int
    center_count: int
    rim_constraint_count: int
    max_center_interpolation_error: float
    solve_residual: float
    kind: str


@dataclass
class TpsRimConstraintsReport:
    front_count: int
    total_rim_constraints: int
    fronts: list[CliffFrontBuildStats]
    clusters: list[RimConstraintClusterReport]
    max_center_interpolation_error: float
    representative: dict[str, Any] | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "prototype": "ts06_tps_rim_constraints",
            "front_count": self.front_count,
            "total_rim_constraints": self.total_rim_constraints,
            "fronts": [f.__dict__ for f in self.fronts],
            "clusters": [c.__dict__ for c in self.clusters],
            "max_center_interpolation_error": self.max_center_interpolation_error,
            "representative": self.representative,
        }


def _cliff_pair(cliff: Any) -> frozenset[tuple[int, int]]:
    return frozenset((cliff.tile_a, cliff.tile_b))


def build_cliff_fronts(model: Any) -> list[CliffFront]:
    """Connected components of cliff edges sharing a tile (cliff chains/fronts)."""
    edges = list(model.cliff_edge_graph)
    n = len(edges)
    parent = list(range(n))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    tile_to_indices: dict[tuple[int, int], list[int]] = {}
    for idx, cliff in enumerate(edges):
        tile_to_indices.setdefault(cliff.tile_a, []).append(idx)
        tile_to_indices.setdefault(cliff.tile_b, []).append(idx)

    for indices in tile_to_indices.values():
        for i in range(len(indices)):
            for j in range(i + 1, len(indices)):
                union(indices[i], indices[j])

    groups: dict[int, list[int]] = {}
    for idx in range(n):
        root = find(idx)
        groups.setdefault(root, []).append(idx)

    fronts: list[CliffFront] = []
    for front_id, (_, indices) in enumerate(sorted(groups.items(), key=lambda item: item[1])):
        front_edges = tuple(
            sorted((edges[i] for i in indices), key=lambda e: (e.tile_a, e.tile_b))
        )
        pairs = frozenset(_cliff_pair(e) for e in front_edges)
        fronts.append(CliffFront(front_id=front_id, edges=front_edges, cliff_pairs=pairs))
    return fronts


def _cliff_edge_segment_world_for_tile(
    tile: tuple[int, int],
    other_tile: tuple[int, int],
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[float, float]]:
    direction = _baseline_neighbor_direction(tile, other_tile)
    edge_index = _physical_edge_for_baseline_neighbor(direction)
    cx, cy = handdrawn_center_world_xy(tile[0], tile[1], radius)
    c0 = edge_index
    c1 = (edge_index + 1) % 6
    lx0, ly0 = corner_xy_local(c0, radius)
    lx1, ly1 = corner_xy_local(c1, radius)
    return (cx + lx0, cy + ly0), (cx + lx1, cy + ly1)


def _build_front_side_profiles(
    front: CliffFront,
    model: Any,
) -> dict[tuple[int, int], CliffFrontSideProfile]:
    """v1: constant own-side height per edge segment; structure ready for front-wide 1D profiles."""
    by_tile: dict[tuple[int, int], list[CliffFrontSideSegment]] = defaultdict(list)
    for cliff in front.edges:
        for side_tile, other_tile in (
            (cliff.tile_a, cliff.tile_b),
            (cliff.tile_b, cliff.tile_a),
        ):
            height = canonical_center_world_z(model.map, *side_tile)
            by_tile[side_tile].append(
                CliffFrontSideSegment(
                    front_id=front.front_id,
                    cliff=cliff,
                    side_tile=side_tile,
                    other_tile=other_tile,
                    height=height,
                )
            )
    profiles: dict[tuple[int, int], CliffFrontSideProfile] = {}
    for side_tile, segments in by_tile.items():
        profiles[side_tile] = CliffFrontSideProfile(
            front_id=front.front_id,
            side_tile=side_tile,
            segments=tuple(segments),
        )
    return profiles


def build_rim_samples_by_cluster(
    model: Any,
    tile_to_cluster: dict[tuple[int, int], frozenset[tuple[int, int]]],
    *,
    radius: float,
) -> tuple[
    dict[frozenset[tuple[int, int]], list[tuple[float, float, float]]],
    list[CliffFront],
    list[CliffFrontBuildStats],
]:
    cluster_samples: dict[frozenset[tuple[int, int]], list[tuple[float, float, float]]] = (
        defaultdict(list)
    )
    fronts = build_cliff_fronts(model)
    front_stats: list[CliffFrontBuildStats] = []

    for front in fronts:
        front_sample_count = 0
        clusters_touched: set[frozenset[tuple[int, int]]] = set()
        profiles = _build_front_side_profiles(front, model)
        for cliff in front.edges:
            for side_tile, other_tile in (
                (cliff.tile_a, cliff.tile_b),
                (cliff.tile_b, cliff.tile_a),
            ):
                profile = profiles[side_tile]
                z_side = profile.height_for_edge(cliff)
                (ax, ay), (bx, by) = _cliff_edge_segment_world_for_tile(
                    side_tile,
                    other_tile,
                    radius=radius,
                )
                cluster = tile_to_cluster[side_tile]
                clusters_touched.add(cluster)
                for t in TS06_RIM_EDGE_T_PARAMS:
                    wx = ax + t * (bx - ax)
                    wy = ay + t * (by - ay)
                    cluster_samples[cluster].append((wx, wy, z_side))
                    front_sample_count += 1
        front_stats.append(
            CliffFrontBuildStats(
                front_id=front.front_id,
                edge_count=len(front.edges),
                rim_sample_count=front_sample_count,
                clusters_touched=frozenset(clusters_touched),
            )
        )

    return dict(cluster_samples), fronts, front_stats


def _front_id_for_cliff_pair(
    pair: frozenset[tuple[int, int]],
    fronts: list[CliffFront],
) -> int | None:
    for front in fronts:
        if pair in front.cliff_pairs:
            return front.front_id
    return None


def _rim_midpoint_world_xy(
    lower_tile: tuple[int, int],
    upper_tile: tuple[int, int],
    tile: tuple[int, int],
    *,
    radius: float,
    subdiv: int,
) -> tuple[float, float]:
    direction = _baseline_neighbor_direction(tile, upper_tile if tile == lower_tile else lower_tile)
    edge = _physical_edge_for_baseline_neighbor(direction)
    q, r = tile
    cx, cy = handdrawn_center_world_xy(q, r, radius)
    mid = subdiv // 2
    si, sj = mid, subdiv - mid
    if tile == upper_tile:
        si, sj = subdiv - mid, mid
    lx, ly, _, _ = sector_barycentric_xy(edge, si, sj, subdiv, radius=radius)
    return cx + lx, cy + ly


def _rim_midpoint_z(
    solver: Any,
    lower_tile: tuple[int, int],
    upper_tile: tuple[int, int],
    tile: tuple[int, int],
    *,
    radius: float,
    subdiv: int,
) -> float:
    wx, wy = _rim_midpoint_world_xy(
        lower_tile,
        upper_tile,
        tile,
        radius=radius,
        subdiv=subdiv,
    )
    q, r = tile
    direction = _baseline_neighbor_direction(
        tile,
        upper_tile if tile == lower_tile else lower_tile,
    )
    edge = _physical_edge_for_baseline_neighbor(direction)
    return solver.sample_world(
        wx,
        wy,
        q,
        r,
        sector=edge,
        at_sector_outer_edge=True,
    )


def _append_rim_to_cluster_constraints(
    center_xy: list[tuple[float, float]],
    center_zz: list[float],
    rim_samples: list[tuple[float, float, float]],
    *,
    xy_tol: float = 1e-9,
    z_tol: float = 1e-9,
) -> tuple[list[tuple[float, float]], list[float], int]:
    """Append rim samples; skip duplicates of existing center constraints at same xy."""
    xy = list(center_xy)
    zz = list(center_zz)
    appended = 0
    for wx, wy, rz in rim_samples:
        skip = False
        for (cx, cy), cz in zip(center_xy, center_zz, strict=True):
            if abs(wx - cx) <= xy_tol and abs(wy - cy) <= xy_tol:
                if abs(rz - cz) <= z_tol:
                    skip = True
                    break
        if skip:
            continue
        xy.append((wx, wy))
        zz.append(rz)
        appended += 1
    return xy, zz, appended


def _finalize_ts03_solve_report(
    solver: VariationalSplineTerrainSolver,
    *,
    model: Any,
    radius: float,
    unique_clusters: list[frozenset[tuple[int, int]]],
    component_reports: list[ComponentSolveReport],
    max_center_err: float,
    max_residual: float,
    all_input_z: list[float],
) -> None:
    """Mirror VariationalSplineTerrainSolver.prepare report finalization (TS-03 compatible)."""
    probe_xy: list[tuple[float, float]] = []
    for cluster in unique_clusters:
        xy_d, _ = _component_centers(model, cluster, radius=radius)
        if len(xy_d) >= 3:
            probe_xy = xy_d
            break
    if not probe_xy and unique_clusters:
        probe_xy = _component_centers(model, unique_clusters[0], radius=radius)[0]

    const_ok, const_err, planar_ok, planar_err = _affine_invariance_tests(
        probe_xy,
        prefer_numpy=_VS_NUMPY_AVAILABLE,
    )

    input_min = min(all_input_z) if all_input_z else 0.0
    input_max = max(all_input_z) if all_input_z else 0.0
    input_range = input_max - input_min

    z_samples: list[float] = []
    for cluster_id, cluster in enumerate(unique_clusters):
        xy_d, _zz_d = _component_centers(model, cluster, radius=radius)
        field_d = solver._fields_by_cluster_id[cluster_id]
        for x, y in xy_d:
            z_samples.append(field_d.eval_at(x, y))
        if len(xy_d) >= 3:
            cx = sum(p[0] for p in xy_d) / float(len(xy_d))
            cy = sum(p[1] for p in xy_d) / float(len(xy_d))
            z_samples.append(field_d.eval_at(cx, cy))

    z_min = min(z_samples) if z_samples else input_min
    z_max = max(z_samples) if z_samples else input_max
    overshoot = 0.0
    if input_range > 0.0:
        overshoot = max(0.0, z_max - input_max, input_min - z_min)

    warnings: list[str] = []
    if input_range > 0.0 and overshoot > 0.25 * input_range:
        warnings.append(
            f"overshoot {overshoot:.4f} exceeds 25% of input elevation range {input_range:.4f}"
        )
    if not const_ok:
        warnings.append(f"affine constant self-test failed (max error {const_err:.3e})")
    if not planar_ok:
        warnings.append(f"affine planar self-test failed (max error {planar_err:.3e})")

    solver._report = VariationalSplineSolveReport(
        component_count=len(component_reports),
        components=component_reports,
        max_center_interpolation_error=max_center_err,
        max_solve_residual=max_residual,
        z_min=z_min,
        z_max=z_max,
        input_z_min=input_min,
        input_z_max=input_max,
        max_overshoot=overshoot,
        affine_constant_ok=const_ok,
        affine_constant_max_error=const_err,
        affine_planar_ok=planar_ok,
        affine_planar_max_error=planar_err,
        cliff_cut_field_count=len(unique_clusters),
        warnings=warnings,
    )

    cliff_audit = _audit_representative_cliff_edge(solver, model, radius=radius)
    if cliff_audit is not None:
        solver._report.representative_cliff = cliff_audit
        if not cliff_audit.used_distinct_fields:
            solver._report.warnings.append(
                "representative cliff (4,0)<->(5,0) sampled the same solver field on both sides"
            )
        if cliff_audit.expected_canonical_gap > 1e-9:
            gap_ratio = cliff_audit.rim_z_gap / cliff_audit.expected_canonical_gap
            if gap_ratio < 0.5:
                solver._report.warnings.append(
                    f"representative cliff rim gap {cliff_audit.rim_z_gap:.4f} "
                    f"is far below canonical {cliff_audit.expected_canonical_gap:.4f}"
                )


class TpsRimConstraintsTerrainSolver(VariationalSplineTerrainSolver):
    """TS-03 per-cluster TPS with explicit cliff-front rim interpolation constraints only."""

    backend = None  # attached in generator

    def __init__(self) -> None:
        super().__init__()
        self._fronts: list[CliffFront] = []
        self._ts06_rim_report: TpsRimConstraintsReport | None = None

    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        self._model = model
        self._radius = radius
        self._fields_by_cluster_id.clear()
        self._field_id_by_tile.clear()
        self._cluster_by_id.clear()
        self._report = None
        self._ts06_rim_report = None

        tile_to_cluster, unique_clusters = build_cliff_side_cluster_lookup(model)
        cluster_id_for_tiles = {
            cluster: index for index, cluster in enumerate(unique_clusters)
        }
        rim_by_cluster, self._fronts, front_stats = build_rim_samples_by_cluster(
            model,
            tile_to_cluster,
            radius=radius,
        )

        component_reports: list[ComponentSolveReport] = []
        cluster_reports: list[RimConstraintClusterReport] = []
        all_input_z: list[float] = []
        max_center_err = 0.0
        max_residual = 0.0
        total_rim = 0

        for cluster_id, cluster in enumerate(unique_clusters):
            self._cluster_by_id[cluster_id] = cluster
            center_xy, center_zz = _component_centers(model, cluster, radius=radius)
            rim_samples = rim_by_cluster.get(cluster, [])
            xy, zz, rim_used = _append_rim_to_cluster_constraints(
                center_xy,
                center_zz,
                rim_samples,
            )
            total_rim += rim_used
            all_input_z.extend(zz)

            if len(xy) < 1:
                continue

            try:
                field, residual, _ = solve_component_field(
                    xy,
                    zz,
                    prefer_numpy=_VS_NUMPY_AVAILABLE,
                )
            except LinAlgError:
                raise

            center_err = max(
                abs(field.eval_at(x, y) - z)
                for (x, y), z in zip(center_xy, center_zz, strict=True)
            )
            max_center_err = max(max_center_err, center_err)
            max_residual = max(max_residual, residual)
            self._fields_by_cluster_id[cluster_id] = field
            matrix_size = len(xy) + 3 if len(xy) >= 3 else len(xy)
            component_reports.append(
                ComponentSolveReport(
                    domain_id=cluster_id,
                    center_count=len(center_xy),
                    matrix_size=matrix_size,
                    solve_residual=residual,
                    max_center_error=center_err,
                    kind=field.kind,
                )
            )
            cluster_reports.append(
                RimConstraintClusterReport(
                    cluster_id=cluster_id,
                    center_count=len(center_xy),
                    rim_constraint_count=rim_used,
                    max_center_interpolation_error=center_err,
                    solve_residual=residual,
                    kind=field.kind,
                )
            )

        for tile, cluster in tile_to_cluster.items():
            self._field_id_by_tile[tile] = cluster_id_for_tiles[cluster]

        self._ts06_rim_report = TpsRimConstraintsReport(
            front_count=len(self._fronts),
            total_rim_constraints=total_rim,
            fronts=front_stats,
            clusters=cluster_reports,
            max_center_interpolation_error=max_center_err,
        )

        _finalize_ts03_solve_report(
            self,
            model=model,
            radius=radius,
            unique_clusters=unique_clusters,
            component_reports=component_reports,
            max_center_err=max_center_err,
            max_residual=max_residual,
            all_input_z=all_input_z,
        )

    @property
    def stats(self) -> dict[str, Any] | None:
        base = super().stats
        if base is None:
            return None
        merged = dict(base)
        merged["backend"] = "variational_spline"
        merged["prototype"] = "ts06_tps_rim_constraints"
        if self._ts06_rim_report is not None:
            merged["ts06_rim_constraints"] = self._ts06_rim_report.as_dict()
        return merged


def print_ts06_rim_diag(
    model: Any,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    base_solver: VariationalSplineTerrainSolver | None = None,
    ts06_solver: TpsRimConstraintsTerrainSolver | None = None,
) -> None:
    base = base_solver or VariationalSplineTerrainSolver()
    if base_solver is None:
        base.prepare(model, radius=radius)
    ts06 = ts06_solver or TpsRimConstraintsTerrainSolver()
    if ts06_solver is None:
        ts06.prepare(model, radius=radius)

    pair = frozenset(REPRESENTATIVE_CLIFF)
    front_id = _front_id_for_cliff_pair(pair, ts06._fronts)

    record = None
    for cliff in model.cliff_edge_graph:
        if frozenset((cliff.tile_a, cliff.tile_b)) == pair:
            record = cliff
            break

    rep: dict[str, Any] | None = None
    if record is not None:
        elev_a = tile_world_z(model.map, *record.tile_a)
        elev_b = tile_world_z(model.map, *record.tile_b)
        if elev_a <= elev_b:
            lower_tile, upper_tile = record.tile_a, record.tile_b
        else:
            lower_tile, upper_tile = record.tile_b, record.tile_a

        lower_center = canonical_center_world_z(model.map, *lower_tile)
        upper_center = canonical_center_world_z(model.map, *upper_tile)
        lower_base_rim = _rim_midpoint_z(
            base, lower_tile, upper_tile, lower_tile, radius=radius, subdiv=subdiv
        )
        upper_base_rim = _rim_midpoint_z(
            base, lower_tile, upper_tile, upper_tile, radius=radius, subdiv=subdiv
        )
        lower_ts06_rim = _rim_midpoint_z(
            ts06, lower_tile, upper_tile, lower_tile, radius=radius, subdiv=subdiv
        )
        upper_ts06_rim = _rim_midpoint_z(
            ts06, lower_tile, upper_tile, upper_tile, radius=radius, subdiv=subdiv
        )
        expected_gap = abs(elev_a - elev_b)
        rim_gap_before = upper_base_rim - lower_base_rim
        rim_gap_after = upper_ts06_rim - lower_ts06_rim

        lower_cluster = ts06._field_id_by_tile[lower_tile]
        upper_cluster = ts06._field_id_by_tile[upper_tile]
        lower_rim_count = 0
        upper_rim_count = 0
        rim_report = ts06._ts06_rim_report
        if rim_report is not None:
            for cluster_report in rim_report.clusters:
                if cluster_report.cluster_id == lower_cluster:
                    lower_rim_count = cluster_report.rim_constraint_count
                if cluster_report.cluster_id == upper_cluster:
                    upper_rim_count = cluster_report.rim_constraint_count

        rep = {
            "cliff_pair": REPRESENTATIVE_CLIFF,
            "front_id": front_id,
            "lower_tile": lower_tile,
            "upper_tile": upper_tile,
            "lower_center_z": lower_center,
            "upper_center_z": upper_center,
            "lower_base_rim_z": lower_base_rim,
            "upper_base_rim_z": upper_base_rim,
            "lower_ts06_rim_z": lower_ts06_rim,
            "upper_ts06_rim_z": upper_ts06_rim,
            "rim_gap_before": rim_gap_before,
            "rim_gap_after": rim_gap_after,
            "expected_canonical_gap": expected_gap,
            "lower_cluster_rim_constraints": lower_rim_count,
            "upper_cluster_rim_constraints": upper_rim_count,
        }

        print("TS06_RIM_DIAG === representative cliff ===")
        print(f"TS06_RIM_DIAG   cliff_pair={REPRESENTATIVE_CLIFF} front_id={front_id}")
        print(f"TS06_RIM_DIAG   lower_tile={lower_tile} upper_tile={upper_tile}")
        print(f"TS06_RIM_DIAG   lower_center_z={lower_center:.6f} upper_center_z={upper_center:.6f}")
        print(
            f"TS06_RIM_DIAG   lower_base_rim_z={lower_base_rim:.6f} "
            f"upper_base_rim_z={upper_base_rim:.6f}"
        )
        print(
            f"TS06_RIM_DIAG   lower_ts06_rim_z={lower_ts06_rim:.6f} "
            f"upper_ts06_rim_z={upper_ts06_rim:.6f}"
        )
        print(
            f"TS06_RIM_DIAG   rim_gap_before={rim_gap_before:.6f} "
            f"rim_gap_after={rim_gap_after:.6f} "
            f"expected_canonical_gap={expected_gap:.6f}"
        )
        print(
            f"TS06_RIM_DIAG   rim_constraints lower_cluster={lower_rim_count} "
            f"upper_cluster={upper_rim_count}"
        )
    else:
        print("TS06_RIM_DIAG   representative cliff (4,0)<->(5,0) not found in model")

    if ts06._ts06_rim_report is not None:
        report = ts06._ts06_rim_report
        print(
            f"TS06_RIM_DIAG   total_rim_constraints={report.total_rim_constraints} "
            f"max_center_interpolation_error={report.max_center_interpolation_error:.3e}"
        )
        print("TS06_RIM_DIAG === front stats ===")
        for front_stat in report.fronts:
            print(
                f"TS06_RIM_DIAG   front={front_stat.front_id} edges={front_stat.edge_count} "
                f"rim_samples={front_stat.rim_sample_count} "
                f"clusters={len(front_stat.clusters_touched)}"
            )
        clusters_with_samples = sum(1 for c in report.clusters if c.rim_constraint_count > 0)
        print(
            f"TS06_RIM_DIAG   connected_fronts={report.front_count} "
            f"clusters_receiving_rim_samples={clusters_with_samples}"
        )

    if rep is not None and ts06._ts06_rim_report is not None:
        ts06._ts06_rim_report.representative = rep


def print_ts06_representative_mesh_audit(
    model: Any,
    mesh: Any,
    stats: dict[str, Any],
    terrain_solver: Any,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    xy_tol: float = 0.05,
    z_tol: float = 1e-3,
    bottom_z: float = -0.35,
) -> None:
    """Mesh-side audit for representative cliff (4,0)<->(5,0): rim vs wall vertex heights."""
    from math import hypot

    pair = frozenset(REPRESENTATIVE_CLIFF)
    record = None
    for cliff in model.cliff_edge_graph:
        if frozenset((cliff.tile_a, cliff.tile_b)) == pair:
            record = cliff
            break
    if record is None:
        print("TS06_MESH_AUDIT representative cliff (4,0)<->(5,0) not found")
        return

    elev_a = tile_world_z(model.map, *record.tile_a)
    elev_b = tile_world_z(model.map, *record.tile_b)
    if elev_a <= elev_b:
        lower_tile, upper_tile = record.tile_a, record.tile_b
    else:
        lower_tile, upper_tile = record.tile_b, record.tile_a

    lower_rim_z = _rim_midpoint_z(
        terrain_solver, lower_tile, upper_tile, lower_tile, radius=radius, subdiv=subdiv
    )
    upper_rim_z = _rim_midpoint_z(
        terrain_solver, lower_tile, upper_tile, upper_tile, radius=radius, subdiv=subdiv
    )
    lower_rim_xy = _rim_midpoint_world_xy(
        lower_tile, upper_tile, lower_tile, radius=radius, subdiv=subdiv
    )
    upper_rim_xy = _rim_midpoint_world_xy(
        lower_tile, upper_tile, upper_tile, radius=radius, subdiv=subdiv
    )
    shared_rim_xy = lower_rim_xy

    cliff_vert_indices = stats.get("cliff_wall_vertex_indices") or []

    def _verts_near_xy(
        rim_xy: tuple[float, float],
        *,
        vert_indices: list[int] | None = None,
    ) -> list[int]:
        matches: list[int] = []
        for vi in vert_indices or range(len(mesh.vertices)):
            co = mesh.vertices[vi].co
            if hypot(co.x - rim_xy[0], co.y - rim_xy[1]) <= xy_tol:
                matches.append(vi)
        return matches

    def _pick_z_near_target(vert_indices: list[int], target_z: float) -> tuple[float | None, int | None]:
        best_z: float | None = None
        best_vi: int | None = None
        best_delta = float("inf")
        for vi in vert_indices:
            z = mesh.vertices[vi].co.z
            delta = abs(z - target_z)
            if delta < best_delta:
                best_delta = delta
                best_z = z
                best_vi = vi
        return best_z, best_vi

    rim_verts = _verts_near_xy(shared_rim_xy)
    cliff_verts_at_rim = _verts_near_xy(shared_rim_xy, vert_indices=cliff_vert_indices)
    top_rim_verts = [
        vi
        for vi in rim_verts
        if mesh.vertices[vi].co.z > bottom_z + 0.01
    ]

    lower_top_mesh_z, lower_top_vi = _pick_z_near_target(top_rim_verts, lower_rim_z)
    upper_top_mesh_z, upper_top_vi = _pick_z_near_target(top_rim_verts, upper_rim_z)
    lower_wall_top_z, _ = _pick_z_near_target(cliff_verts_at_rim, lower_rim_z)
    upper_wall_top_z, _ = _pick_z_near_target(cliff_verts_at_rim, upper_rim_z)
    _, lower_wall_bottom_vi = _pick_z_near_target(cliff_verts_at_rim, bottom_z)
    _, upper_wall_bottom_vi = _pick_z_near_target(cliff_verts_at_rim, bottom_z)
    lower_wall_bottom_z = (
        mesh.vertices[lower_wall_bottom_vi].co.z if lower_wall_bottom_vi is not None else None
    )
    upper_wall_bottom_z = (
        mesh.vertices[upper_wall_bottom_vi].co.z if upper_wall_bottom_vi is not None else None
    )

    def _z_match(a: float | None, b: float, label: str) -> bool:
        if a is None:
            print(f"TS06_MESH_AUDIT   {label}: missing wall/top vertex")
            return False
        ok = abs(a - b) <= z_tol
        print(
            f"TS06_MESH_AUDIT   {label}: mesh_z={a:.6f} sampled_rim_z={b:.6f} "
            f"delta={abs(a - b):.6f} within_tol={ok}"
        )
        return ok

    print("TS06_MESH_AUDIT === representative cliff mesh ===")
    print(f"TS06_MESH_AUDIT   cliff_pair={REPRESENTATIVE_CLIFF}")
    print(f"TS06_MESH_AUDIT   lower_tile={lower_tile} upper_tile={upper_tile}")
    print(f"TS06_MESH_AUDIT   shared_rim_xy=({shared_rim_xy[0]:.6f},{shared_rim_xy[1]:.6f})")
    print(f"TS06_MESH_AUDIT   lower_rim_z={lower_rim_z:.6f} upper_rim_z={upper_rim_z:.6f}")
    print(
        f"TS06_MESH_AUDIT   lower_top_mesh_z={lower_top_mesh_z} vi={lower_top_vi} "
        f"upper_top_mesh_z={upper_top_mesh_z} vi={upper_top_vi}"
    )
    print(
        f"TS06_MESH_AUDIT   lower_wall_top_z={lower_wall_top_z} "
        f"lower_wall_bottom_z={lower_wall_bottom_z}"
    )
    print(
        f"TS06_MESH_AUDIT   upper_wall_top_z={upper_wall_top_z} "
        f"upper_wall_bottom_z={upper_wall_bottom_z}"
    )
    print(
        f"TS06_MESH_AUDIT   rim_verts_at_shared_xy={len(rim_verts)} "
        f"top_rim_verts={len(top_rim_verts)} cliff_verts_at_rim={len(cliff_verts_at_rim)}"
    )

    _z_match(lower_top_mesh_z, lower_rim_z, "lower_top_surface_vs_rim")
    _z_match(upper_top_mesh_z, upper_rim_z, "upper_top_surface_vs_rim")
    _z_match(lower_wall_top_z, lower_rim_z, "lower_wall_top_vs_rim")
    _z_match(upper_wall_top_z, upper_rim_z, "upper_wall_top_vs_rim")

    lower_top_gap = abs((lower_top_mesh_z or 0.0) - lower_rim_z)
    upper_top_gap = abs((upper_top_mesh_z or 0.0) - upper_rim_z)
    print(
        f"TS06_MESH_AUDIT   top_surface_rim_gap lower={lower_top_gap:.6f} "
        f"upper={upper_top_gap:.6f} xy_tol={xy_tol} z_tol={z_tol}"
    )
    rim_to_wall_lower = (
        abs((lower_wall_top_z or 0.0) - lower_rim_z) if lower_wall_top_z is not None else float("inf")
    )
    rim_to_wall_upper = (
        abs((upper_wall_top_z or 0.0) - upper_rim_z) if upper_wall_top_z is not None else float("inf")
    )
    print(
        f"TS06_MESH_AUDIT   rim_gap_top_to_wall lower={rim_to_wall_lower:.6f} "
        f"upper={rim_to_wall_upper:.6f}"
    )
    distinct_top_rim = (
        lower_top_vi is not None
        and upper_top_vi is not None
        and lower_top_vi != upper_top_vi
    )
    print(f"TS06_MESH_AUDIT   distinct_side_rim_vertices={distinct_top_rim}")


def _run_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model

    json_map = """
    {
      "id": "ts06_small",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":4,"r":0,"elevation":1},
        {"q":5,"r":0,"elevation":3},
        {"q":4,"r":1,"elevation":1},
        {"q":5,"r":1,"elevation":1}
      ]
    }
    """
    model = build_terrain_model(json_map)
    solver = TpsRimConstraintsTerrainSolver()
    solver.prepare(model)
    assert solver._ts06_rim_report is not None
    assert solver._ts06_rim_report.total_rim_constraints > 0
    assert solver._ts06_rim_report.max_center_interpolation_error < 1e-6

    pair = frozenset(((4, 0), (5, 0)))
    record = next(
        c for c in model.cliff_edge_graph if frozenset((c.tile_a, c.tile_b)) == pair
    )
    elev_a = tile_world_z(model.map, *record.tile_a)
    elev_b = tile_world_z(model.map, *record.tile_b)
    lower = record.tile_a if elev_a <= elev_b else record.tile_b
    upper = record.tile_b if elev_a <= elev_b else record.tile_a

    for tile in (lower, upper):
        wx, wy = _rim_midpoint_world_xy(
            lower,
            upper,
            tile,
            radius=DEFAULT_HEX_RADIUS,
            subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
        )
        expected = canonical_center_world_z(model.map, *tile)
        actual = solver.sample_world(
            wx,
            wy,
            tile[0],
            tile[1],
            at_sector_outer_edge=True,
        )
        assert abs(actual - expected) < 1e-5, f"rim midpoint {tile}: {actual} vs {expected}"

    print("eom_terrain_tps_rim_constraints self-test passed")


if __name__ == "__main__":
    _run_self_tests()
