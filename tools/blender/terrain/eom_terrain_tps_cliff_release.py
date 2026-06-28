# Empire of Minds — TS-05 TPS cliff-band release prototype (experimental).
# Wraps TS-03 VariationalSpline: global TPS unchanged away from cliffs; per-front band
# re-fit releases rim from opposite-side TPS pull.

from __future__ import annotations

TS05_MODULE_VERSION = "ts05_guarded_2026_06_27"
print("LOADED TS05 MODULE:", __file__, "VERSION:", TS05_MODULE_VERSION)

import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    _baseline_neighbor_direction,
    _build_smooth_adjacency,
    _physical_edge_for_baseline_neighbor,
    canonical_center_world_z,
    corner_xy_local,
    handdrawn_center_world_xy,
    sector_barycentric_xy,
    tile_world_z,
)
from eom_terrain_variational_spline import (
    ComponentField,
    VariationalSplineTerrainSolver,
    _LinearPlaneField,
)


def _build_cliff_neighbor_map(model: Any) -> dict[tuple[int, int], frozenset[tuple[int, int]]]:
    by_tile: dict[tuple[int, int], set[tuple[int, int]]] = {}
    for cliff in model.cliff_edges:
        by_tile.setdefault(cliff.tile_a, set()).add(cliff.tile_b)
        by_tile.setdefault(cliff.tile_b, set()).add(cliff.tile_a)
    return {tile: frozenset(neighbors) for tile, neighbors in by_tile.items()}

try:
    import numpy as np
    from numpy.linalg import LinAlgError

    _NUMPY_AVAILABLE = True
except ImportError:
    np = None  # type: ignore[assignment,misc]
    LinAlgError = Exception  # type: ignore[misc,assignment]
    _NUMPY_AVAILABLE = False


def _is_singular_linalg_error(exc: BaseException) -> bool:
    """True for LinAlgError even when Blender loads a second numpy copy."""
    if type(exc).__name__ == "LinAlgError":
        return True
    if "singular matrix" in str(exc).lower():
        return True
    try:
        if isinstance(exc, LinAlgError):
            return True
    except TypeError:
        pass
    if np is not None:
        try:
            if isinstance(exc, np.linalg.LinAlgError):
                return True
        except AttributeError:
            pass
    module = getattr(type(exc), "__module__", "")
    return "linalg" in module and "singular" in str(exc).lower()

# Prototype defaults (not tuned for production).
BAND_DEPTH = 2
INTERIOR_MIN_DIST_FACTOR = 0.35
DIRECT_TILE_MIN_RELEASE_WEIGHT = 0.92
REPRESENTATIVE_CLIFF = ((4, 0), (5, 0))
XY_ANCHOR_TOL_FACTOR = 1e-8
Z_ANCHOR_TOL = 1e-9
TS05_MAX_BAND_TPS_ANCHORS = 500
TS05_MAX_FRONTS_FOR_VISUAL_TEST: int | None = None
TS05_FORCE_BASE_TS03_ON_OVERSIZE = False
BandFallbackKind = Literal["tps", "downsampled_tps", "affine_plane", "base_ts03", "skipped"]
BandAnchorMode = Literal["tps", "downsampled_tps", "affine_plane", "base_ts03", "skipped"]
BandFallbackReason = Literal["singular", "precheck", "anchor_budget"]


@dataclass(frozen=True)
class CliffFront:
    front_id: int
    edges: tuple[Any, ...]
    cliff_pairs: frozenset[frozenset[tuple[int, int]]]


@dataclass
class SideBandRelease:
    front_id: int
    side: Literal["upper", "lower"]
    tiles: frozenset[tuple[int, int]]
    direct_cliff_tiles: frozenset[tuple[int, int]]
    direct_tile_max_inward: dict[tuple[int, int], float]
    field: ComponentField
    center_count: int
    anchor_count: int
    fallback: BandFallbackKind = "tps"


@dataclass
class SideApplicationDiagnostics:
    front_id: int
    side: Literal["upper", "lower"]
    direct_cliff_tile_count: int
    support_band_tile_count: int
    release_sample_count: int
    base_sample_count: int
    direct_cliff_base_fallback_count: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "front_id": self.front_id,
            "side": self.side,
            "direct_cliff_tile_count": self.direct_cliff_tile_count,
            "support_band_tile_count": self.support_band_tile_count,
            "release_sample_count": self.release_sample_count,
            "base_sample_count": self.base_sample_count,
            "direct_cliff_base_fallback_count": self.direct_cliff_base_fallback_count,
        }


@dataclass
class BandSolveDiagnostics:
    front_id: int
    side: Literal["upper", "lower"]
    anchor_count_before_dedupe: int
    unique_anchor_count_after_dedupe: int
    affine_rank: int
    duplicate_xy_anchors: int
    fallback: BandFallbackKind
    solvable_precheck: bool
    tps_attempted: bool
    lin_alg_error: bool
    conflict_messages: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "front_id": self.front_id,
            "side": self.side,
            "anchor_count_before_dedupe": self.anchor_count_before_dedupe,
            "unique_anchor_count_after_dedupe": self.unique_anchor_count_after_dedupe,
            "affine_rank": self.affine_rank,
            "duplicate_xy_anchors": self.duplicate_xy_anchors,
            "fallback": self.fallback,
            "solvable_precheck": self.solvable_precheck,
            "tps_attempted": self.tps_attempted,
            "lin_alg_error": self.lin_alg_error,
            "conflict_messages": list(self.conflict_messages),
        }


@dataclass
class CliffReleaseFrontAudit:
    front_id: int
    edge_count: int
    upper_band_tiles: int
    lower_band_tiles: int
    upper_anchor_count: int
    lower_anchor_count: int


@dataclass
class CliffReleaseRimAudit:
    tile_a: tuple[int, int]
    tile_b: tuple[int, int]
    lower_tile: tuple[int, int]
    upper_tile: tuple[int, int]
    lower_rim_before: float
    upper_rim_before: float
    lower_rim_after: float
    upper_rim_after: float
    rim_gap_before: float
    rim_gap_after: float
    expected_canonical_gap: float


@dataclass
class TpsCliffReleaseReport:
    front_count: int
    band_release_count: int
    fronts: list[CliffReleaseFrontAudit]
    representative: CliffReleaseRimAudit | None = None
    warnings: list[str] = field(default_factory=list)
    band_solve_diagnostics: list[BandSolveDiagnostics] = field(default_factory=list)
    application_diagnostics: list[SideApplicationDiagnostics] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        rep: dict[str, Any] | None = None
        if self.representative is not None:
            r = self.representative
            rep = {
                "tile_a": r.tile_a,
                "tile_b": r.tile_b,
                "lower_tile": r.lower_tile,
                "upper_tile": r.upper_tile,
                "lower_rim_before": r.lower_rim_before,
                "upper_rim_before": r.upper_rim_before,
                "lower_rim_after": r.lower_rim_after,
                "upper_rim_after": r.upper_rim_after,
                "rim_gap_before": r.rim_gap_before,
                "rim_gap_after": r.rim_gap_after,
                "expected_canonical_gap": r.expected_canonical_gap,
            }
        return {
            "prototype": "ts05_tps_cliff_release",
            "front_count": self.front_count,
            "band_release_count": self.band_release_count,
            "fronts": [f.__dict__ for f in self.fronts],
            "representative_cliff_release": rep,
            "warnings": list(self.warnings),
            "band_solve_diagnostics": [d.as_dict() for d in self.band_solve_diagnostics],
            "application_diagnostics": [d.as_dict() for d in self.application_diagnostics],
        }


def _dist_point_segment(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> float:
    abx = bx - ax
    aby = by - ay
    len_sq = abx * abx + aby * aby
    if len_sq <= 1e-18:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * abx + (py - ay) * aby) / len_sq))
    qx = ax + t * abx
    qy = ay + t * aby
    return math.hypot(px - qx, py - qy)


def _upper_lower_tiles(cliff: Any) -> tuple[tuple[int, int], tuple[int, int]]:
    if cliff.elevation_a <= cliff.elevation_b:
        lower, upper = cliff.tile_a, cliff.tile_b
    else:
        lower, upper = cliff.tile_b, cliff.tile_a
    return upper, lower


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
        front_edges = tuple(edges[i] for i in indices)
        pairs = frozenset(_cliff_pair(e) for e in front_edges)
        fronts.append(CliffFront(front_id=front_id, edges=front_edges, cliff_pairs=pairs))
    return fronts


def _expand_side_band(
    seed_tiles: set[tuple[int, int]],
    model: Any,
    *,
    depth: int,
) -> frozenset[tuple[int, int]]:
    smooth_adj = _build_smooth_adjacency(model.map, model.smooth_edges)
    cliff_neighbors = _build_cliff_neighbor_map(model)
    band: set[tuple[int, int]] = set(seed_tiles)
    frontier = list(seed_tiles)
    all_tiles = set(model.map.tiles.keys())
    for _ in range(depth):
        next_frontier: list[tuple[int, int]] = []
        for tile in frontier:
            for neighbor in smooth_adj.get(tile, ()):
                if neighbor in band or neighbor not in all_tiles:
                    continue
                if neighbor in cliff_neighbors.get(tile, frozenset()):
                    continue
                band.add(neighbor)
                next_frontier.append(neighbor)
        frontier = next_frontier
    return frozenset(band)


def _cliff_edge_segment_world(
    cliff: Any,
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[float, float]]:
    tile_a = cliff.tile_a
    direction = _baseline_neighbor_direction(tile_a, cliff.tile_b)
    edge_index = _physical_edge_for_baseline_neighbor(direction)
    cx, cy = handdrawn_center_world_xy(tile_a[0], tile_a[1], radius)
    c0 = edge_index
    c1 = (edge_index + 1) % 6
    lx0, ly0 = corner_xy_local(c0, radius)
    lx1, ly1 = corner_xy_local(c1, radius)
    return (cx + lx0, cy + ly0), (cx + lx1, cy + ly1)


def _min_dist_to_front(
    wx: float,
    wy: float,
    front: CliffFront,
    *,
    radius: float,
) -> float:
    best = float("inf")
    for cliff in front.edges:
        (ax, ay), (bx, by) = _cliff_edge_segment_world(cliff, radius=radius)
        best = min(best, _dist_point_segment(wx, wy, ax, ay, bx, by))
    return best


def _build_cliff_physical_edges_by_tile(model: Any) -> dict[tuple[int, int], frozenset[int]]:
    by_tile: dict[tuple[int, int], set[int]] = {}
    for cliff in model.cliff_edge_graph:
        tile_a = cliff.tile_a
        tile_b = cliff.tile_b
        edge_a = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_a, tile_b)
        )
        edge_b = _physical_edge_for_baseline_neighbor(
            _baseline_neighbor_direction(tile_b, tile_a)
        )
        by_tile.setdefault(tile_a, set()).add(edge_a)
        by_tile.setdefault(tile_b, set()).add(edge_b)
    return {tile: frozenset(edges) for tile, edges in by_tile.items()}


def _tile_side_on_front(
    tile: tuple[int, int],
    cliff: Any,
) -> Literal["upper", "lower"] | None:
    upper, lower = _upper_lower_tiles(cliff)
    if tile == upper:
        return "upper"
    if tile == lower:
        return "lower"
    return None


def _collect_band_constraints(
    band_tiles: frozenset[tuple[int, int]],
    front: CliffFront,
    model: Any,
    base: VariationalSplineTerrainSolver,
    *,
    radius: float,
    subdiv: int,
) -> tuple[list[tuple[float, float]], list[float], list[bool], list[float], int, int]:
    xy: list[tuple[float, float]] = []
    zz: list[float] = []
    is_center: list[bool] = []
    front_dist: list[float] = []
    cliff_phys = _build_cliff_physical_edges_by_tile(model)
    interior_min = INTERIOR_MIN_DIST_FACTOR * radius
    center_count = 0
    anchor_count = 0

    for q, r in sorted(band_tiles):
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        dist_center = _min_dist_to_front(cx, cy, front, radius=radius)
        xy.append((cx, cy))
        zz.append(canonical_center_world_z(model.map, q, r))
        is_center.append(True)
        front_dist.append(dist_center)
        center_count += 1

        tile_cliff_edges = cliff_phys.get((q, r), frozenset())
        for sector in range(6):
            si = 0
            while si <= subdiv:
                sj = 0
                while sj <= subdiv - si:
                    at_outer = si + sj == subdiv
                    if at_outer and sector in tile_cliff_edges:
                        sj += 1
                        continue
                    lx, ly, _, _ = sector_barycentric_xy(sector, si, sj, subdiv, radius=radius)
                    wx = cx + lx
                    wy = cy + ly
                    dist_sample = _min_dist_to_front(wx, wy, front, radius=radius)
                    if dist_sample < interior_min:
                        sj += 1
                        continue
                    z_base = base.sample_world(
                        wx,
                        wy,
                        q,
                        r,
                        sector=sector,
                        at_sector_outer_edge=at_outer,
                    )
                    xy.append((wx, wy))
                    zz.append(z_base)
                    is_center.append(False)
                    front_dist.append(dist_sample)
                    anchor_count += 1
                    sj += 1
                si += 1

    return xy, zz, is_center, front_dist, center_count, anchor_count


def _xy_anchor_tol(radius: float) -> float:
    return max(1e-12, XY_ANCHOR_TOL_FACTOR * radius)


def _dedupe_band_anchors(
    xy: list[tuple[float, float]],
    zz: list[float],
    *,
    xy_tol: float,
    z_tol: float,
) -> tuple[list[tuple[float, float]], list[float], int, list[str]]:
    deduped_xy: list[tuple[float, float]] = []
    deduped_zz: list[float] = []
    duplicate_xy = 0
    conflicts: list[str] = []

    for (x, y), z in zip(xy, zz, strict=True):
        merged = False
        for index, (rx, ry) in enumerate(deduped_xy):
            if math.hypot(x - rx, y - ry) > xy_tol:
                continue
            merged = True
            duplicate_xy += 1
            existing_z = deduped_zz[index]
            if abs(z - existing_z) <= z_tol:
                continue
            mean_z = 0.5 * (z + existing_z)
            conflicts.append(
                f"duplicate xy ({x:.6f}, {y:.6f}) conflicting z "
                f"{existing_z:.6f} vs {z:.6f}; using mean {mean_z:.6f}"
            )
            deduped_zz[index] = mean_z
            break
        if not merged:
            deduped_xy.append((x, y))
            deduped_zz.append(z)

    return deduped_xy, deduped_zz, duplicate_xy, conflicts


def _dedupe_band_anchors_with_meta(
    xy: list[tuple[float, float]],
    zz: list[float],
    is_center: list[bool],
    front_dist: list[float],
    *,
    xy_tol: float,
    z_tol: float,
) -> tuple[
    list[tuple[float, float]],
    list[float],
    list[bool],
    list[float],
    int,
    list[str],
]:
    deduped_xy: list[tuple[float, float]] = []
    deduped_zz: list[float] = []
    deduped_center: list[bool] = []
    deduped_front_dist: list[float] = []
    duplicate_xy = 0
    conflicts: list[str] = []

    for (x, y), z, center_flag, dist in zip(xy, zz, is_center, front_dist, strict=True):
        merged = False
        for index, (rx, ry) in enumerate(deduped_xy):
            if math.hypot(x - rx, y - ry) > xy_tol:
                continue
            merged = True
            duplicate_xy += 1
            existing_z = deduped_zz[index]
            if abs(z - existing_z) <= z_tol:
                pass
            else:
                mean_z = 0.5 * (z + existing_z)
                conflicts.append(
                    f"duplicate xy ({x:.6f}, {y:.6f}) conflicting z "
                    f"{existing_z:.6f} vs {z:.6f}; using mean {mean_z:.6f}"
                )
                deduped_zz[index] = mean_z
            deduped_center[index] = deduped_center[index] or center_flag
            deduped_front_dist[index] = max(deduped_front_dist[index], dist)
            break
        if not merged:
            deduped_xy.append((x, y))
            deduped_zz.append(z)
            deduped_center.append(center_flag)
            deduped_front_dist.append(dist)

    return deduped_xy, deduped_zz, deduped_center, deduped_front_dist, duplicate_xy, conflicts


def _downsample_tps_anchors(
    xy: list[tuple[float, float]],
    zz: list[float],
    is_center: list[bool],
    front_dist: list[float],
    cap: int,
) -> tuple[list[tuple[float, float]], list[float], bool]:
    if len(xy) <= cap:
        return xy, zz, False

    center_idx = sorted(i for i, center in enumerate(is_center) if center)
    interior_idx = sorted(
        (i for i, center in enumerate(is_center) if not center),
        key=lambda i: (-front_dist[i], i),
    )

    selected: list[int] = []
    for index in center_idx:
        if len(selected) >= cap:
            break
        selected.append(index)

    remaining = cap - len(selected)
    if remaining > 0 and interior_idx:
        if len(interior_idx) <= remaining:
            selected.extend(interior_idx)
        else:
            stride = max(1, len(interior_idx) // remaining)
            picked: list[int] = []
            for index in interior_idx[::stride]:
                if index not in picked:
                    picked.append(index)
                if len(picked) >= remaining:
                    break
            if len(picked) < remaining:
                for index in interior_idx:
                    if index in picked:
                        continue
                    picked.append(index)
                    if len(picked) >= remaining:
                        break
            selected.extend(picked[:remaining])

    selected.sort()
    return (
        [xy[i] for i in selected],
        [zz[i] for i in selected],
        True,
    )


def _prepare_tps_solve_anchors(
    xy: list[tuple[float, float]],
    zz: list[float],
    is_center: list[bool],
    front_dist: list[float],
    *,
    xy_tol: float,
    z_tol: float,
    cap: int,
) -> tuple[
    list[tuple[float, float]],
    list[float],
    int,
    int,
    bool,
    bool,
    int,
    int,
    list[str],
]:
    (
        deduped_xy,
        deduped_zz,
        deduped_center,
        deduped_front_dist,
        duplicate_xy,
        conflicts,
    ) = _dedupe_band_anchors_with_meta(
        xy,
        zz,
        is_center,
        front_dist,
        xy_tol=xy_tol,
        z_tol=z_tol,
    )
    unique_count = len(deduped_xy)
    force_base = TS05_FORCE_BASE_TS03_ON_OVERSIZE and unique_count > cap
    solve_xy, solve_zz, was_downsampled = _downsample_tps_anchors(
        deduped_xy,
        deduped_zz,
        deduped_center,
        deduped_front_dist,
        cap,
    )
    used_count = len(solve_xy)
    affine_rank = _affine_design_rank(solve_xy)
    solvable = used_count >= 3 and affine_rank >= 3 and used_count <= cap
    return (
        solve_xy,
        solve_zz,
        unique_count,
        used_count,
        was_downsampled,
        force_base,
        affine_rank,
        duplicate_xy,
        conflicts,
    )


def _affine_design_rank(xy: list[tuple[float, float]]) -> int:
    if not xy:
        return 0
    if _NUMPY_AVAILABLE:
        assert np is not None
        xs = np.array([p[0] for p in xy], dtype=np.float64)
        ys = np.array([p[1] for p in xy], dtype=np.float64)
        design = np.column_stack([np.ones(len(xy), dtype=np.float64), xs, ys])
        return int(np.linalg.matrix_rank(design))
    rows = [[1.0, x, y] for x, y in xy]
    rank = 0
    pivot_cols: list[int] = []
    for col in range(3):
        pivot_row = None
        for row_index, row in enumerate(rows):
            if row_index in pivot_cols:
                continue
            if abs(row[col]) <= 1e-14:
                continue
            pivot_row = row_index
            break
        if pivot_row is None:
            continue
        pivot_cols.append(pivot_row)
        pivot_val = rows[pivot_row][col]
        for row_index, row in enumerate(rows):
            if row_index == pivot_row or row_index in pivot_cols[:-1]:
                continue
            factor = row[col] / pivot_val
            if factor == 0.0:
                continue
            for k in range(col, 3):
                row[k] -= factor * rows[pivot_row][k]
        rank += 1
    return rank


def _band_tps_solvable(
    xy: list[tuple[float, float]],
    zz: list[float],
    *,
    xy_tol: float,
    z_tol: float,
) -> tuple[bool, list[tuple[float, float]], list[float], int, int, list[str]]:
    deduped_xy, deduped_zz, duplicate_xy, conflicts = _dedupe_band_anchors(
        xy,
        zz,
        xy_tol=xy_tol,
        z_tol=z_tol,
    )
    unique_count = len(deduped_xy)
    affine_rank = _affine_design_rank(deduped_xy)
    solvable = unique_count >= 3 and affine_rank >= 3
    return solvable, deduped_xy, deduped_zz, duplicate_xy, affine_rank, conflicts


def _fit_affine_plane_field(
    xy: list[tuple[float, float]],
    zz: list[float],
) -> ComponentField | None:
    if len(xy) < 3 or _affine_design_rank(xy) < 3:
        return None
    if _NUMPY_AVAILABLE:
        assert np is not None
        xs = np.array([p[0] for p in xy], dtype=np.float64)
        ys = np.array([p[1] for p in xy], dtype=np.float64)
        zz_arr = np.array(zz, dtype=np.float64)
        design = np.column_stack([np.ones(len(xy), dtype=np.float64), xs, ys])
        coef, _, _, _ = np.linalg.lstsq(design, zz_arr, rcond=None)
        x0, y0 = xy[0]
        z0 = float(coef[0] + coef[1] * x0 + coef[2] * y0)
        return _LinearPlaneField(
            z0=z0,
            gx=float(coef[1]),
            gy=float(coef[2]),
            x0=x0,
            y0=y0,
        )
    return None


def _base_cluster_field_for_band(
    base: VariationalSplineTerrainSolver,
    band_tiles: frozenset[tuple[int, int]],
) -> ComponentField | None:
    if not band_tiles:
        return None
    tile = min(band_tiles)
    field_id = base._field_id_for_tile(tile)
    return base._fields_by_cluster_id.get(field_id)


def _format_band_diag(diag: BandSolveDiagnostics) -> str:
    return (
        f"TS-05 band front={diag.front_id} side={diag.side}: "
        f"anchors={diag.anchor_count_before_dedupe} "
        f"unique={diag.unique_anchor_count_after_dedupe} "
        f"affine_rank={diag.affine_rank} "
        f"duplicate_xy={diag.duplicate_xy_anchors} "
        f"fallback={diag.fallback}"
        + (" LinAlgError" if diag.lin_alg_error else "")
    )


def _print_ts05_fallback(
    *,
    front_id: int,
    side: Literal["upper", "lower"],
    reason: BandFallbackReason,
    mode: BandFallbackKind,
    unique: int | None = None,
    cap: int | None = None,
) -> None:
    if reason == "anchor_budget":
        print(
            f"TS05_FALLBACK front={front_id} side={side} "
            f"reason=anchor_budget unique={unique} cap={cap} mode={mode}"
        )
    else:
        print(
            f"TS05_FALLBACK front={front_id} side={side} "
            f"reason={reason} mode={mode}"
        )


def _print_ts05_band_anchors(
    *,
    front_id: int,
    side: Literal["upper", "lower"],
    raw: int,
    unique: int,
    used: int,
    mode: BandAnchorMode,
) -> None:
    print(
        f"TS05_BAND_ANCHORS front={front_id} side={side} "
        f"raw={raw} unique={unique} used={used} mode={mode}"
    )


def _guarded_solve_component_field(
    *,
    front_id: int,
    side: Literal["upper", "lower"],
    xy: list[tuple[float, float]],
    zz: list[float],
    raw_anchor_count: int,
    unique_anchor_count: int,
    used_anchor_count: int,
    affine_rank: int,
) -> tuple[ComponentField | None, bool]:
    """The only function in this module that may call solve_component_field."""
    if len(xy) > TS05_MAX_BAND_TPS_ANCHORS:
        raise RuntimeError(
            f"TS-05 internal error: guarded TPS solve requested with "
            f"{len(xy)} anchors (cap={TS05_MAX_BAND_TPS_ANCHORS})"
        )
    from eom_terrain_variational_spline import solve_component_field

    print(
        f"GUARDED_TS05_SOLVE front={front_id} side={side} "
        f"raw={raw_anchor_count} unique={unique_anchor_count} "
        f"used={used_anchor_count} rank={affine_rank}"
    )
    try:
        field, _, _ = solve_component_field(
            xy,
            zz,
            prefer_numpy=_NUMPY_AVAILABLE,
        )
        return field, False
    except BaseException as exc:
        if not _is_singular_linalg_error(exc):
            raise
        return None, True


def _resolve_band_fallback(
    deduped_xy: list[tuple[float, float]],
    deduped_zz: list[float],
    base: VariationalSplineTerrainSolver,
    band_tiles: frozenset[tuple[int, int]],
    *,
    prefer_base_ts03: bool = False,
) -> tuple[ComponentField | None, BandFallbackKind]:
    if prefer_base_ts03:
        base_field = _base_cluster_field_for_band(base, band_tiles)
        if base_field is not None:
            return base_field, "base_ts03"

    plane = _fit_affine_plane_field(deduped_xy, deduped_zz)
    if plane is not None:
        return plane, "affine_plane"

    base_field = _base_cluster_field_for_band(base, band_tiles)
    if base_field is not None:
        return base_field, "base_ts03"

    return None, "skipped"


def _try_solve_band_field(
    front: CliffFront,
    side: Literal["upper", "lower"],
    xy: list[tuple[float, float]],
    zz: list[float],
    is_center: list[bool],
    front_dist: list[float],
    base: VariationalSplineTerrainSolver,
    band_tiles: frozenset[tuple[int, int]],
    *,
    radius: float,
    force_fallback_only: bool = False,
) -> tuple[ComponentField | None, BandSolveDiagnostics]:
    xy_tol = _xy_anchor_tol(radius)
    before_count = len(xy)
    cap = TS05_MAX_BAND_TPS_ANCHORS
    (
        solve_xy,
        solve_zz,
        unique_count,
        used_count,
        was_downsampled,
        force_base,
        affine_rank,
        duplicate_xy,
        conflicts,
    ) = _prepare_tps_solve_anchors(
        xy,
        zz,
        is_center,
        front_dist,
        xy_tol=xy_tol,
        z_tol=Z_ANCHOR_TOL,
        cap=cap,
    )
    solvable = used_count >= 3 and affine_rank >= 3 and used_count <= cap
    diag = BandSolveDiagnostics(
        front_id=front.front_id,
        side=side,
        anchor_count_before_dedupe=before_count,
        unique_anchor_count_after_dedupe=unique_count,
        affine_rank=affine_rank,
        duplicate_xy_anchors=duplicate_xy,
        fallback="skipped",
        solvable_precheck=solvable,
        tps_attempted=False,
        lin_alg_error=False,
        conflict_messages=conflicts,
    )
    anchor_mode: BandAnchorMode = "skipped"

    if used_count < 2:
        _print_ts05_band_anchors(
            front_id=front.front_id,
            side=side,
            raw=before_count,
            unique=unique_count,
            used=used_count,
            mode="skipped",
        )
        _print_ts05_fallback(
            front_id=front.front_id,
            side=side,
            reason="precheck",
            mode="skipped",
        )
        return None, diag

    if force_base or force_fallback_only:
        fallback_reason: BandFallbackReason = (
            "anchor_budget" if force_base else "precheck"
        )
        fallback_field, fallback_kind = _resolve_band_fallback(
            solve_xy,
            solve_zz,
            base,
            band_tiles,
            prefer_base_ts03=force_base,
        )
        diag.fallback = fallback_kind
        anchor_mode = fallback_kind if fallback_kind != "skipped" else "skipped"
        _print_ts05_band_anchors(
            front_id=front.front_id,
            side=side,
            raw=before_count,
            unique=unique_count,
            used=used_count,
            mode=anchor_mode,
        )
        if fallback_kind != "tps":
            _print_ts05_fallback(
                front_id=front.front_id,
                side=side,
                reason=fallback_reason,
                mode=fallback_kind,
                unique=unique_count if fallback_reason == "anchor_budget" else None,
                cap=cap if fallback_reason == "anchor_budget" else None,
            )
        return fallback_field, diag

    if solvable:
        diag.tps_attempted = True
        try:
            field, lin_alg_error = _guarded_solve_component_field(
                front_id=front.front_id,
                side=side,
                xy=solve_xy,
                zz=solve_zz,
                raw_anchor_count=before_count,
                unique_anchor_count=unique_count,
                used_anchor_count=used_count,
                affine_rank=affine_rank,
            )
        except BaseException as exc:
            if not _is_singular_linalg_error(exc):
                raise
            lin_alg_error = True
            field = None
        if field is not None:
            diag.fallback = "downsampled_tps" if was_downsampled else "tps"
            anchor_mode = "downsampled_tps" if was_downsampled else "tps"
            _print_ts05_band_anchors(
                front_id=front.front_id,
                side=side,
                raw=before_count,
                unique=unique_count,
                used=used_count,
                mode=anchor_mode,
            )
            return field, diag
        diag.lin_alg_error = lin_alg_error

    fallback_reason = "singular" if diag.lin_alg_error else "anchor_budget"
    prefer_base = unique_count > cap and not solvable
    fallback_field, fallback_kind = _resolve_band_fallback(
        solve_xy,
        solve_zz,
        base,
        band_tiles,
        prefer_base_ts03=prefer_base,
    )
    diag.fallback = fallback_kind
    anchor_mode = fallback_kind if fallback_kind != "skipped" else "skipped"
    _print_ts05_band_anchors(
        front_id=front.front_id,
        side=side,
        raw=before_count,
        unique=unique_count,
        used=used_count,
        mode=anchor_mode,
    )
    if fallback_kind != "tps":
        _print_ts05_fallback(
            front_id=front.front_id,
            side=side,
            reason=fallback_reason,
            mode=fallback_kind,
            unique=unique_count if fallback_reason == "anchor_budget" else None,
            cap=cap if fallback_reason == "anchor_budget" else None,
        )
    return fallback_field, diag


def _cliff_physical_edges_on_tile_for_front_side(
    tile: tuple[int, int],
    front: CliffFront,
    side: Literal["upper", "lower"],
) -> frozenset[int]:
    edges: set[int] = set()
    for cliff in front.edges:
        if _tile_side_on_front(tile, cliff) != side:
            continue
        if tile == cliff.tile_a:
            direction = _baseline_neighbor_direction(cliff.tile_a, cliff.tile_b)
        elif tile == cliff.tile_b:
            direction = _baseline_neighbor_direction(cliff.tile_b, cliff.tile_a)
        else:
            continue
        edges.add(_physical_edge_for_baseline_neighbor(direction))
    return frozenset(edges)


def _min_dist_to_front_on_tile_side(
    wx: float,
    wy: float,
    tile: tuple[int, int],
    front: CliffFront,
    side: Literal["upper", "lower"],
    *,
    radius: float,
) -> float:
    best = float("inf")
    for cliff in front.edges:
        if _tile_side_on_front(tile, cliff) != side:
            continue
        (ax, ay), (bx, by) = _cliff_edge_segment_world(cliff, radius=radius)
        best = min(best, _dist_point_segment(wx, wy, ax, ay, bx, by))
    return best


def _compute_direct_tile_max_inward_dist(
    tile: tuple[int, int],
    front: CliffFront,
    side: Literal["upper", "lower"],
    *,
    radius: float,
    subdiv: int,
) -> float:
    cliff_edges = _cliff_physical_edges_on_tile_for_front_side(tile, front, side)
    q, r = tile
    cx, cy = handdrawn_center_world_xy(q, r, radius)
    max_inward = 0.0
    for sector in range(6):
        si = 0
        while si <= subdiv:
            sj = 0
            while sj <= subdiv - si:
                at_outer = si + sj == subdiv
                if at_outer and sector in cliff_edges:
                    sj += 1
                    continue
                lx, ly, _, _ = sector_barycentric_xy(sector, si, sj, subdiv, radius=radius)
                wx = cx + lx
                wy = cy + ly
                inward = _min_dist_to_front_on_tile_side(
                    wx,
                    wy,
                    tile,
                    front,
                    side,
                    radius=radius,
                )
                if math.isfinite(inward):
                    max_inward = max(max_inward, inward)
                sj += 1
            si += 1
    return max(max_inward, radius * 0.1)


def _build_direct_tile_max_inward_map(
    direct_tiles: frozenset[tuple[int, int]],
    front: CliffFront,
    side: Literal["upper", "lower"],
    *,
    radius: float,
    subdiv: int,
) -> dict[tuple[int, int], float]:
    return {
        tile: _compute_direct_tile_max_inward_dist(
            tile,
            front,
            side,
            radius=radius,
            subdiv=subdiv,
        )
        for tile in direct_tiles
    }


def _direct_tile_release_weight(
    wx: float,
    wy: float,
    tile: tuple[int, int],
    front: CliffFront,
    side: Literal["upper", "lower"],
    max_inward: float,
    *,
    radius: float,
) -> float:
    dist = _min_dist_to_front_on_tile_side(
        wx,
        wy,
        tile,
        front,
        side,
        radius=radius,
    )
    if not math.isfinite(dist):
        return 1.0
    if max_inward <= 1e-12:
        return 1.0
    t = min(1.0, max(0.0, dist / max_inward))
    return 1.0 - (1.0 - DIRECT_TILE_MIN_RELEASE_WEIGHT) * t


def _classify_sample_application(
    wx: float,
    wy: float,
    tile: tuple[int, int],
    releases: list[SideBandRelease],
    fronts: list[CliffFront],
    *,
    radius: float,
) -> tuple[SideBandRelease | None, float, bool]:
    """Return (release, weight, is_direct_cliff_tile). weight=0 means base-only."""
    best_release: SideBandRelease | None = None
    best_dist = float("inf")
    best_weight = 0.0
    is_direct = _tile_in_any_direct_cliff_set(tile, releases)

    for release in releases:
        if tile not in release.direct_cliff_tiles:
            continue
        front = fronts[release.front_id]
        if not any(_tile_side_on_front(tile, edge) == release.side for edge in front.edges):
            continue
        dist = _min_dist_to_front(wx, wy, front, radius=radius)
        max_inward = release.direct_tile_max_inward.get(tile, radius)
        weight = _direct_tile_release_weight(
            wx,
            wy,
            tile,
            front,
            release.side,
            max_inward,
            radius=radius,
        )
        if weight <= 0.0:
            continue
        if dist < best_dist:
            best_dist = dist
            best_release = release
            best_weight = weight

    return best_release, best_weight, is_direct


def _tile_in_any_direct_cliff_set(
    tile: tuple[int, int],
    releases: list[SideBandRelease],
) -> bool:
    return any(tile in release.direct_cliff_tiles for release in releases)


def _explain_direct_cliff_fallback(
    wx: float,
    wy: float,
    tile: tuple[int, int],
    releases: list[SideBandRelease],
    fronts: list[CliffFront],
    *,
    radius: float,
) -> str:
    if not _tile_in_any_direct_cliff_set(tile, releases):
        return "tile_not_in_any_direct_cliff_tiles"

    details: list[str] = []
    for release in releases:
        if tile not in release.direct_cliff_tiles:
            continue
        front = fronts[release.front_id]
        if not any(_tile_side_on_front(tile, edge) == release.side for edge in front.edges):
            details.append(
                f"front={release.front_id} side={release.side}: "
                "tile_in_direct_set_but_side_not_on_front_edge"
            )
            continue
        max_inward = release.direct_tile_max_inward.get(tile, radius)
        weight = _direct_tile_release_weight(
            wx,
            wy,
            tile,
            front,
            release.side,
            max_inward,
            radius=radius,
        )
        if weight <= 0.0:
            details.append(
                f"front={release.front_id} side={release.side}: release_weight_zero"
            )
            continue
        dist = _min_dist_to_front(wx, wy, front, radius=radius)
        details.append(
            f"front={release.front_id} side={release.side}: "
            f"candidate_ok weight={weight:.6f} dist={dist:.6f}"
        )
    if not details:
        return "direct_cliff_tile_no_release_match_unknown"
    return "; ".join(details)


def _release_for_direct_tile(
    tile: tuple[int, int],
    side: Literal["upper", "lower"],
    releases: list[SideBandRelease],
    fronts: list[CliffFront],
) -> SideBandRelease | None:
    for release in releases:
        if release.side != side:
            continue
        if tile not in release.direct_cliff_tiles:
            continue
        front = fronts[release.front_id]
        if any(_tile_side_on_front(tile, edge) == side for edge in front.edges):
            return release
    return None


def _front_id_for_cliff_pair(
    pair: frozenset[tuple[int, int]],
    fronts: list[CliffFront],
) -> int | None:
    for front in fronts:
        if pair in front.cliff_pairs:
            return front.front_id
    return None


MESH_AUDIT_TILES = (REPRESENTATIVE_CLIFF[0], REPRESENTATIVE_CLIFF[1])


@dataclass
class Ts05MeshTileSampleStats:
    tile: tuple[int, int]
    release_samples: int = 0
    base_samples: int = 0
    cliff_sector_release: int = 0
    cliff_sector_base: int = 0
    direct_fallback_samples: int = 0
    max_release_minus_base: float = 0.0
    max_final_minus_base: float = 0.0


@dataclass
class Ts05MeshRimSampleRecord:
    tile: tuple[int, int]
    role: Literal["upper", "lower"]
    wx: float
    wy: float
    base_z: float
    release_z: float | None
    final_z: float
    weight: float
    used_release: bool
    vertex_id: int | None = None


class Ts05MeshSamplingAudit:
    """Instrument build_analytic_terrain_mesh sample_world calls for TS-05."""

    def __init__(
        self,
        solver: TpsCliffReleaseTerrainSolver,
        model: Any,
        *,
        radius: float,
        subdiv: int,
    ) -> None:
        self._solver = solver
        self._model = model
        self._radius = radius
        self._subdiv = subdiv
        self._tile_stats: dict[tuple[int, int], Ts05MeshTileSampleStats] = {
            tile: Ts05MeshTileSampleStats(tile=tile) for tile in MESH_AUDIT_TILES
        }
        self._cliff_phys = _build_cliff_physical_edges_by_tile(model)
        self._rep_cliff: Any | None = None
        for cliff in model.cliff_edge_graph:
            if frozenset((cliff.tile_a, cliff.tile_b)) == frozenset(REPRESENTATIVE_CLIFF):
                self._rep_cliff = cliff
                break
        self._pending_rim: dict[tuple[int, int], Ts05MeshRimSampleRecord] = {}

    def print_representative_cliff_ownership(self) -> None:
        print("TS05_MESH === TS05_MESH_REP_CLIFF ===")
        pair = frozenset(REPRESENTATIVE_CLIFF)
        front_id = _front_id_for_cliff_pair(pair, self._solver._fronts)
        print(f"TS05_MESH   cliff_pair={REPRESENTATIVE_CLIFF} front_id={front_id}")
        if self._rep_cliff is None:
            print("TS05_MESH   representative cliff edge not found in model.cliff_edge_graph")
            return

        upper, lower = _upper_lower_tiles(self._rep_cliff)
        for tile, role in ((lower, "lower"), (upper, "upper")):
            release = _release_for_direct_tile(
                tile,
                role,
                self._solver._releases,
                self._solver._fronts,
            )
            in_direct = _tile_in_any_direct_cliff_set(tile, self._solver._releases)
            side_release = (
                f"front={release.front_id} side={release.side} fallback={release.fallback}"
                if release is not None
                else "none"
            )
            in_map = tile in self._model.map.tiles
            print(
                f"TS05_MESH   tile={tile!r} role={role} side_release={side_release} "
                f"in_direct_cliff_tiles={in_direct} "
                f"tile_key_type={type(tile[0]).__name__},{type(tile[1]).__name__} "
                f"handdrawn_in_map={in_map}"
            )
            if release is not None:
                print(
                    f"TS05_MESH     direct_set_match={tile in release.direct_cliff_tiles} "
                    f"band_set_match={tile in release.tiles}"
                )

    def _is_cliff_facing_sector(
        self,
        tile: tuple[int, int],
        sector: int | None,
        at_outer: bool,
    ) -> bool:
        if sector is None or not at_outer:
            return False
        return sector in self._cliff_phys.get(tile, frozenset())

    def record_sample(
        self,
        *,
        q: int,
        r: int,
        sector: int | None,
        at_outer: bool,
        si: int,
        sj: int,
        wx: float,
        wy: float,
        used_release: bool,
        base_z: float,
        release_z: float | None,
        final_z: float,
        weight: float,
        fallback_reason: str | None,
    ) -> None:
        tile = (q, r)
        if tile not in self._tile_stats:
            return

        stats = self._tile_stats[tile]
        cliff_facing = self._is_cliff_facing_sector(tile, sector, at_outer)
        if used_release:
            stats.release_samples += 1
            if cliff_facing:
                stats.cliff_sector_release += 1
            if release_z is not None:
                stats.max_release_minus_base = max(
                    stats.max_release_minus_base,
                    abs(release_z - base_z),
                )
            stats.max_final_minus_base = max(
                stats.max_final_minus_base,
                abs(final_z - base_z),
            )
        else:
            stats.base_samples += 1
            if cliff_facing:
                stats.cliff_sector_base += 1
            if _tile_in_any_direct_cliff_set(tile, self._solver._releases):
                stats.direct_fallback_samples += 1
                print(
                    f"TS05_MESH_FALLBACK tile={tile!r} q={q} r={r} sector={sector} "
                    f"si={si} sj={sj} at_outer={at_outer} wx={wx:.6f} wy={wy:.6f} "
                    f"reason={fallback_reason}"
                )

        rim_role = self._representative_rim_role_at_sample(q, r, sector, si, sj, at_outer)
        if rim_role is not None:
            self._pending_rim[tile] = Ts05MeshRimSampleRecord(
                tile=tile,
                role=rim_role,
                wx=wx,
                wy=wy,
                base_z=base_z,
                release_z=release_z,
                final_z=final_z,
                weight=weight,
                used_release=used_release,
            )

    def _representative_rim_role_at_sample(
        self,
        q: int,
        r: int,
        sector: int | None,
        si: int,
        sj: int,
        at_outer: bool,
    ) -> Literal["upper", "lower"] | None:
        if self._rep_cliff is None or sector is None or not at_outer:
            return None
        upper, lower = _upper_lower_tiles(self._rep_cliff)
        tile = (q, r)
        if tile == upper:
            neighbor = lower
            role: Literal["upper", "lower"] = "upper"
        elif tile == lower:
            neighbor = upper
            role = "lower"
        else:
            return None
        direction = _baseline_neighbor_direction(tile, neighbor)
        edge = _physical_edge_for_baseline_neighbor(direction)
        if sector != edge:
            return None
        mid = self._subdiv // 2
        if role == "upper":
            expect_si, expect_sj = self._subdiv - mid, mid
        else:
            expect_si, expect_sj = mid, self._subdiv - mid
        if si != expect_si or sj != expect_sj:
            return None
        return role

    def attach_rim_vertex_id(
        self,
        q: int,
        r: int,
        sector: int | None,
        si: int,
        sj: int,
        at_outer: bool,
        vertex_id: int,
    ) -> None:
        tile = (q, r)
        record = self._pending_rim.get(tile)
        if record is None:
            return
        if self._representative_rim_role_at_sample(q, r, sector, si, sj, at_outer) is None:
            return
        record.vertex_id = vertex_id

    def finish(self) -> None:
        print("TS05_MESH === TS05_MESH_SAMPLE_COUNTS ===")
        for tile in MESH_AUDIT_TILES:
            stats = self._tile_stats[tile]
            print(
                f"TS05_MESH   tile={tile!r} release={stats.release_samples} "
                f"base={stats.base_samples} "
                f"cliff_sector_release={stats.cliff_sector_release} "
                f"cliff_sector_base={stats.cliff_sector_base} "
                f"direct_fallback={stats.direct_fallback_samples} "
                f"max_release_minus_base={stats.max_release_minus_base:.6f} "
                f"max_final_minus_base={stats.max_final_minus_base:.6f}"
            )
        print("TS05_MESH === TS05_MESH_RIM_VERTICES ===")
        if not self._pending_rim:
            print("TS05_MESH   no representative rim samples captured during mesh build")
            return
        for tile in MESH_AUDIT_TILES:
            record = self._pending_rim.get(tile)
            if record is None:
                print(f"TS05_MESH   tile={tile!r} role=? vertex_id=None (rim sample not captured)")
                continue
            release_z_text = (
                f"{record.release_z:.6f}" if record.release_z is not None else "None"
            )
            delta = record.release_z - record.base_z if record.release_z is not None else 0.0
            print(
                f"TS05_MESH   tile={record.tile!r} role={record.role} "
                f"vertex_id={record.vertex_id} "
                f"base_z={record.base_z:.6f} release_z={release_z_text} "
                f"final_z={record.final_z:.6f} weight={record.weight:.6f} "
                f"release_minus_base={delta:.6f} "
                f"used_release={record.used_release}"
            )


def _print_side_application_diagnostics(diag: SideApplicationDiagnostics) -> None:
    print(
        f"TS05_APPLY front={diag.front_id} side={diag.side} "
        f"direct_tiles={diag.direct_cliff_tile_count} "
        f"support_tiles={diag.support_band_tile_count} "
        f"release_samples={diag.release_sample_count} "
        f"base_samples={diag.base_sample_count} "
        f"direct_fallback={diag.direct_cliff_base_fallback_count}"
    )


def _audit_side_application(
    release: SideBandRelease,
    fronts: list[CliffFront],
    *,
    radius: float,
    subdiv: int,
) -> SideApplicationDiagnostics:
    support_tiles = release.tiles - release.direct_cliff_tiles
    release_samples = 0
    base_samples = 0
    direct_fallback = 0

    for tile in sorted(release.tiles):
        q, r = tile
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        for sector in range(6):
            si = 0
            while si <= subdiv:
                sj = 0
                while sj <= subdiv - si:
                    lx, ly, _, _ = sector_barycentric_xy(
                        sector,
                        si,
                        sj,
                        subdiv,
                        radius=radius,
                    )
                    wx = cx + lx
                    wy = cy + ly
                    match, weight, is_direct = _classify_sample_application(
                        wx,
                        wy,
                        tile,
                        [release],
                        fronts,
                        radius=radius,
                    )
                    if match is not None and weight > 0.0:
                        release_samples += 1
                    else:
                        base_samples += 1
                        if is_direct:
                            direct_fallback += 1
                    sj += 1
                si += 1

    return SideApplicationDiagnostics(
        front_id=release.front_id,
        side=release.side,
        direct_cliff_tile_count=len(release.direct_cliff_tiles),
        support_band_tile_count=len(support_tiles),
        release_sample_count=release_samples,
        base_sample_count=base_samples,
        direct_cliff_base_fallback_count=direct_fallback,
    )


def _solve_side_band(
    front: CliffFront,
    side: Literal["upper", "lower"],
    model: Any,
    base: VariationalSplineTerrainSolver,
    *,
    radius: float,
    subdiv: int,
) -> tuple[SideBandRelease | None, BandSolveDiagnostics | None]:
    seeds: set[tuple[int, int]] = set()
    for cliff in front.edges:
        upper, lower = _upper_lower_tiles(cliff)
        seeds.add(upper if side == "upper" else lower)
    direct_cliff_tiles = frozenset(seeds)
    band = _expand_side_band(seeds, model, depth=BAND_DEPTH)
    if len(band) < 2:
        return None, None
    xy, zz, is_center, front_dist, center_count, anchor_count = _collect_band_constraints(
        band,
        front,
        model,
        base,
        radius=radius,
        subdiv=subdiv,
    )
    if len(xy) < 3:
        return None, None
    try:
        field, diag = _try_solve_band_field(
            front,
            side,
            xy,
            zz,
            is_center,
            front_dist,
            base,
            band,
            radius=radius,
        )
    except BaseException as exc:
        if not _is_singular_linalg_error(exc):
            raise
        field, diag = _try_solve_band_field(
            front,
            side,
            xy,
            zz,
            is_center,
            front_dist,
            base,
            band,
            radius=radius,
            force_fallback_only=True,
        )
        if diag is not None:
            diag.lin_alg_error = True
    if field is None:
        return None, diag
    direct_tile_max_inward = _build_direct_tile_max_inward_map(
        direct_cliff_tiles,
        front,
        side,
        radius=radius,
        subdiv=subdiv,
    )
    return SideBandRelease(
        front_id=front.front_id,
        side=side,
        tiles=band,
        direct_cliff_tiles=direct_cliff_tiles,
        direct_tile_max_inward=direct_tile_max_inward,
        field=field,
        center_count=center_count,
        anchor_count=anchor_count,
        fallback=diag.fallback,
    ), diag


def _rim_midpoint_z(
    solver: Any,
    cliff: Any,
    tile: tuple[int, int],
    *,
    radius: float,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
) -> float:
    upper, lower = _upper_lower_tiles(cliff)
    if tile == upper:
        neighbor = lower
    else:
        neighbor = upper
    direction = _baseline_neighbor_direction(tile, neighbor)
    edge = _physical_edge_for_baseline_neighbor(direction)
    q, r = tile
    cx, cy = handdrawn_center_world_xy(q, r, radius)
    mid = subdiv // 2
    si, sj = mid, subdiv - mid
    if tile == upper:
        si, sj = subdiv - mid, mid
    lx, ly, _, _ = sector_barycentric_xy(edge, si, sj, subdiv, radius=radius)
    return solver.sample_world(
        cx + lx,
        cy + ly,
        q,
        r,
        sector=edge,
        at_sector_outer_edge=True,
    )


class TpsCliffReleaseTerrainSolver:
    """TS-03 base field + connected cliff-front band release (prototype)."""

    backend = None  # attached to variational_spline in generator

    def __init__(self) -> None:
        self._base = VariationalSplineTerrainSolver()
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS
        self._releases: list[SideBandRelease] = []
        self._fronts: list[CliffFront] = []
        self._release_report: TpsCliffReleaseReport | None = None
        self._mesh_audit: Ts05MeshSamplingAudit | None = None

    def begin_mesh_sampling_audit(self, audit: Ts05MeshSamplingAudit) -> None:
        self._mesh_audit = audit

    def finish_mesh_sampling_audit(self) -> None:
        if self._mesh_audit is not None:
            self._mesh_audit.finish()
            self._mesh_audit = None

    def _record_mesh_sample(
        self,
        *,
        q: int,
        r: int,
        sector: int | None,
        at_outer: bool,
        si: int,
        sj: int,
        wx: float,
        wy: float,
        used_release: bool,
        base_z: float,
        release_z: float | None,
        final_z: float,
        weight: float,
        fallback_reason: str | None,
    ) -> None:
        if self._mesh_audit is None:
            return
        self._mesh_audit.record_sample(
            q=q,
            r=r,
            sector=sector,
            at_outer=at_outer,
            si=si,
            sj=sj,
            wx=wx,
            wy=wy,
            used_release=used_release,
            base_z=base_z,
            release_z=release_z,
            final_z=final_z,
            weight=weight,
            fallback_reason=fallback_reason,
        )

    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        self._model = model
        self._radius = radius
        self._releases.clear()
        self._fronts = build_cliff_fronts(model)
        if TS05_MAX_FRONTS_FOR_VISUAL_TEST is not None:
            self._fronts = self._fronts[:TS05_MAX_FRONTS_FOR_VISUAL_TEST]

        self._base.prepare(model, radius=radius)
        subdiv = DEFAULT_SURFACE_SUBDIVISIONS

        front_audits: list[CliffReleaseFrontAudit] = []
        band_diags: list[BandSolveDiagnostics] = []
        application_diags: list[SideApplicationDiagnostics] = []
        warnings: list[str] = []
        for front in self._fronts:
            upper_release, upper_diag = _solve_side_band(
                front, "upper", model, self._base, radius=radius, subdiv=subdiv
            )
            lower_release, lower_diag = _solve_side_band(
                front, "lower", model, self._base, radius=radius, subdiv=subdiv
            )
            for diag in (upper_diag, lower_diag):
                if diag is None:
                    continue
                band_diags.append(diag)
                if diag.fallback != "tps" or diag.conflict_messages:
                    warnings.append(_format_band_diag(diag))
                for msg in diag.conflict_messages:
                    warnings.append(
                        f"TS-05 band front={diag.front_id} side={diag.side}: {msg}"
                    )
            for release in (upper_release, lower_release):
                if release is not None:
                    self._releases.append(release)
                    app_diag = _audit_side_application(
                        release,
                        self._fronts,
                        radius=radius,
                        subdiv=subdiv,
                    )
                    application_diags.append(app_diag)
                    _print_side_application_diagnostics(app_diag)
                    if app_diag.direct_cliff_base_fallback_count > 0:
                        warnings.append(
                            f"TS-05 apply front={app_diag.front_id} side={app_diag.side}: "
                            f"{app_diag.direct_cliff_base_fallback_count} direct-cliff samples "
                            "fell back to base"
                        )
            front_audits.append(
                CliffReleaseFrontAudit(
                    front_id=front.front_id,
                    edge_count=len(front.edges),
                    upper_band_tiles=len(upper_release.tiles) if upper_release else 0,
                    lower_band_tiles=len(lower_release.tiles) if lower_release else 0,
                    upper_anchor_count=upper_release.anchor_count if upper_release else 0,
                    lower_anchor_count=lower_release.anchor_count if lower_release else 0,
                )
            )

        rep = _audit_representative_rim(self, model, radius=radius, subdiv=subdiv)
        if rep is not None and rep.expected_canonical_gap > 1e-9:
            if rep.rim_gap_after < rep.expected_canonical_gap * 0.5:
                warnings.append(
                    f"representative rim gap after release {rep.rim_gap_after:.4f} "
                    f"still below half of canonical {rep.expected_canonical_gap:.4f}"
                )
        self._release_report = TpsCliffReleaseReport(
            front_count=len(self._fronts),
            band_release_count=len(self._releases),
            fronts=front_audits,
            representative=rep,
            warnings=warnings,
            band_solve_diagnostics=band_diags,
            application_diagnostics=application_diags,
        )

    def _release_match_for_sample(
        self,
        wx: float,
        wy: float,
        tile: tuple[int, int],
    ) -> tuple[SideBandRelease, float] | None:
        release, weight, _ = _classify_sample_application(
            wx,
            wy,
            tile,
            self._releases,
            self._fronts,
            radius=self._radius,
        )
        if release is None or weight <= 0.0:
            return None
        return release, weight

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
        mesh_si: int = -1,
        mesh_sj: int = -1,
    ) -> float:
        del idw_fallback, legacy_fallback, at_corner
        tile = (q, r)
        at_outer = at_sector_outer_edge
        match = self._release_match_for_sample(wx, wy, tile)
        if match is None:
            base_z = self._base.sample_world(
                wx,
                wy,
                q,
                r,
                sector=sector,
                at_sector_outer_edge=at_sector_outer_edge,
            )
            fallback_reason: str | None = None
            if _tile_in_any_direct_cliff_set(tile, self._releases):
                fallback_reason = _explain_direct_cliff_fallback(
                    wx,
                    wy,
                    tile,
                    self._releases,
                    self._fronts,
                    radius=self._radius,
                )
            self._record_mesh_sample(
                q=q,
                r=r,
                sector=sector,
                at_outer=at_outer,
                si=mesh_si,
                sj=mesh_sj,
                wx=wx,
                wy=wy,
                used_release=False,
                base_z=base_z,
                release_z=None,
                final_z=base_z,
                weight=0.0,
                fallback_reason=fallback_reason,
            )
            return base_z
        release, weight = match
        release_z = release.field.eval_at(wx, wy)
        base_z = self._base.sample_world(
            wx,
            wy,
            q,
            r,
            sector=sector,
            at_sector_outer_edge=at_sector_outer_edge,
        )
        if weight >= 1.0 - 1e-12:
            final_z = release_z
        else:
            final_z = weight * release_z + (1.0 - weight) * base_z
        self._record_mesh_sample(
            q=q,
            r=r,
            sector=sector,
            at_outer=at_outer,
            si=mesh_si,
            sj=mesh_sj,
            wx=wx,
            wy=wy,
            used_release=True,
            base_z=base_z,
            release_z=release_z,
            final_z=final_z,
            weight=weight,
            fallback_reason=None,
        )
        return final_z

    @property
    def stats(self) -> dict[str, Any] | None:
        base_stats = self._base.stats
        if base_stats is None:
            return None
        merged = dict(base_stats)
        merged["ts05_cliff_release"] = (
            self._release_report.as_dict() if self._release_report else None
        )
        return merged


def _audit_representative_rim(
    solver: TpsCliffReleaseTerrainSolver,
    model: Any,
    *,
    radius: float,
    subdiv: int,
) -> CliffReleaseRimAudit | None:
    tile_a, tile_b = REPRESENTATIVE_CLIFF
    record = None
    for cliff in model.cliff_edge_graph:
        if frozenset((cliff.tile_a, cliff.tile_b)) == frozenset((tile_a, tile_b)):
            record = cliff
            break
    if record is None:
        return None

    upper, lower = _upper_lower_tiles(record)
    lower_before = _rim_midpoint_z(solver._base, record, lower, radius=radius, subdiv=subdiv)
    upper_before = _rim_midpoint_z(solver._base, record, upper, radius=radius, subdiv=subdiv)
    lower_after = _rim_midpoint_z(solver, record, lower, radius=radius, subdiv=subdiv)
    upper_after = _rim_midpoint_z(solver, record, upper, radius=radius, subdiv=subdiv)
    expected = abs(tile_world_z(model.map, *record.tile_a) - tile_world_z(model.map, *record.tile_b))

    return CliffReleaseRimAudit(
        tile_a=record.tile_a,
        tile_b=record.tile_b,
        lower_tile=lower,
        upper_tile=upper,
        lower_rim_before=lower_before,
        upper_rim_before=upper_before,
        lower_rim_after=lower_after,
        upper_rim_after=upper_after,
        rim_gap_before=upper_before - lower_before,
        rim_gap_after=upper_after - lower_after,
        expected_canonical_gap=expected,
    )


def _assert_ts05_single_solve_component_field_call_site() -> None:
    text = Path(__file__).read_text(encoding="utf-8")
    calls = re.findall(r"(?<!_)solve_component_field\(", text)
    if len(calls) != 1:
        raise RuntimeError(
            f"{Path(__file__).name}: expected exactly 1 direct "
            f"variational-spline band solve call site, found {len(calls)}"
        )


_assert_ts05_single_solve_component_field_call_site()


def _run_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model

    json_map = """
    {
      "id": "ts05_small",
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
    fronts = build_cliff_fronts(model)
    assert len(fronts) >= 1
    solver = TpsCliffReleaseTerrainSolver()
    solver.prepare(model)
    stats = solver.stats
    assert stats is not None
    report = stats.get("ts05_cliff_release")
    assert report is not None
    for app in report.get("application_diagnostics", []):
        assert app["direct_cliff_base_fallback_count"] == 0
    cx, cy = handdrawn_center_world_xy(4, 0)
    match = solver._release_match_for_sample(cx, cy, (4, 0))
    assert match is not None
    print("eom_terrain_tps_cliff_release self-test passed")


if __name__ == "__main__":
    _run_self_tests()
