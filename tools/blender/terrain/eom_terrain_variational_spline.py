# Empire of Minds — Thin-plate variational spline terrain backend (TS-03 / TS-03d cliff-cut).

# Affine-precision TPS per cliff-side cluster; numpy in Blender, pure-python for tiny tests.



from __future__ import annotations



import math

from dataclasses import dataclass, field

from typing import Any, Literal



from eom_terrain_math_core import (

    DEFAULT_HEX_RADIUS,

    DEFAULT_SURFACE_SUBDIVISIONS,

    NEIGHBOR_DIRS,

    _build_smooth_adjacency,

    canonical_center_world_z,

    handdrawn_center_world_xy,

    handdrawn_to_baseline_axial,

    sector_barycentric_xy,

    tile_world_z,

)



try:

    import numpy as np



    _NUMPY_AVAILABLE = True

except ImportError:

    np = None  # type: ignore[assignment,misc]

    _NUMPY_AVAILABLE = False





def thin_plate_phi(r: float) -> float:

    if r <= 0.0:

        return 0.0

    return r * r * math.log(r)





def _dist2(ax: float, ay: float, bx: float, by: float) -> float:

    dx = ax - bx

    dy = ay - by

    return math.hypot(dx, dy)





@dataclass

class _ConstantField:

    kind: Literal["constant"] = "constant"

    height: float = 0.0



    def eval_at(self, wx: float, wy: float) -> float:

        return self.height





@dataclass

class _LinearPlaneField:

    kind: Literal["linear"] = "linear"

    z0: float = 0.0

    gx: float = 0.0

    gy: float = 0.0

    x0: float = 0.0

    y0: float = 0.0



    def eval_at(self, wx: float, wy: float) -> float:

        return self.z0 + self.gx * (wx - self.x0) + self.gy * (wy - self.y0)





@dataclass

class _TpsField:

    kind: Literal["tps"] = "tps"

    xy: list[tuple[float, float]] = field(default_factory=list)

    weights: list[float] = field(default_factory=list)

    a: float = 0.0

    b: float = 0.0

    c: float = 0.0



    def eval_at(self, wx: float, wy: float) -> float:

        total = self.a * wx + self.b * wy + self.c

        for (px, py), w in zip(self.xy, self.weights, strict=True):

            total += w * thin_plate_phi(_dist2(wx, wy, px, py))

        return total





ComponentField = _ConstantField | _LinearPlaneField | _TpsField





@dataclass

class ComponentSolveReport:

    domain_id: int

    center_count: int

    matrix_size: int

    solve_residual: float

    max_center_error: float

    kind: str





@dataclass

class CliffEdgeSamplingAudit:

    tile_a: tuple[int, int]

    tile_b: tuple[int, int]

    lower_tile: tuple[int, int]

    upper_tile: tuple[int, int]

    lower_center_z: float

    upper_center_z: float

    lower_rim_mid_z: float

    upper_rim_mid_z: float

    rim_z_gap: float

    expected_canonical_gap: float

    used_distinct_fields: bool

    lower_field_id: int

    upper_field_id: int





@dataclass

class VariationalSplineSolveReport:

    component_count: int

    components: list[ComponentSolveReport]

    max_center_interpolation_error: float

    max_solve_residual: float

    z_min: float

    z_max: float

    input_z_min: float

    input_z_max: float

    max_overshoot: float

    affine_constant_ok: bool

    affine_constant_max_error: float

    affine_planar_ok: bool

    affine_planar_max_error: float

    cliff_cut_field_count: int

    representative_cliff: CliffEdgeSamplingAudit | None = None

    warnings: list[str] = field(default_factory=list)



    def as_dict(self) -> dict[str, Any]:

        cliff_dict: dict[str, Any] | None = None

        if self.representative_cliff is not None:

            c = self.representative_cliff

            cliff_dict = {

                "tile_a": c.tile_a,

                "tile_b": c.tile_b,

                "lower_tile": c.lower_tile,

                "upper_tile": c.upper_tile,

                "lower_center_z": c.lower_center_z,

                "upper_center_z": c.upper_center_z,

                "lower_rim_mid_z": c.lower_rim_mid_z,

                "upper_rim_mid_z": c.upper_rim_mid_z,

                "rim_z_gap": c.rim_z_gap,

                "expected_canonical_gap": c.expected_canonical_gap,

                "used_distinct_fields": c.used_distinct_fields,

                "lower_field_id": c.lower_field_id,

                "upper_field_id": c.upper_field_id,

            }

        return {

            "backend": "variational_spline",

            "component_count": self.component_count,

            "cliff_cut_field_count": self.cliff_cut_field_count,

            "components": [

                {

                    "domain_id": c.domain_id,

                    "center_count": c.center_count,

                    "matrix_size": c.matrix_size,

                    "solve_residual": c.solve_residual,

                    "max_center_error": c.max_center_error,

                    "kind": c.kind,

                }

                for c in self.components

            ],

            "max_center_interpolation_error": self.max_center_interpolation_error,

            "max_solve_residual": self.max_solve_residual,

            "z_min": self.z_min,

            "z_max": self.z_max,

            "input_z_min": self.input_z_min,

            "input_z_max": self.input_z_max,

            "max_overshoot": self.max_overshoot,

            "affine_constant_ok": self.affine_constant_ok,

            "affine_constant_max_error": self.affine_constant_max_error,

            "affine_planar_ok": self.affine_planar_ok,

            "affine_planar_max_error": self.affine_planar_max_error,

            "representative_cliff": cliff_dict,

            "warnings": list(self.warnings),

        }





def _solve_constant(z: float) -> _ConstantField:

    return _ConstantField(height=z)





def _solve_linear_plane(

    xy: list[tuple[float, float]],

    z: list[float],

) -> _LinearPlaneField:

    (x0, y0), (x1, y1) = xy[0], xy[1]

    z0, z1 = z[0], z[1]

    dx = x1 - x0

    dy = y1 - y0

    denom = dx * dx + dy * dy

    if denom <= 1e-18:

        return _ConstantField(height=0.5 * (z0 + z1))

    t = (z1 - z0) / denom

    return _LinearPlaneField(z0=z0, gx=t * dx, gy=t * dy, x0=x0, y0=y0)





def _solve_tps_pure_python(

    xy: list[tuple[float, float]],

    z: list[float],

) -> tuple[_TpsField, float, float]:

    n = len(xy)

    size = n + 3

    a_mat = [[0.0] * size for _ in range(size)]

    rhs = [0.0] * size



    for i in range(n):

        rhs[i] = z[i]

        xi, yi = xy[i]

        for j in range(n):

            a_mat[i][j] = thin_plate_phi(_dist2(xi, yi, xy[j][0], xy[j][1]))

        a_mat[i][n] = 1.0

        a_mat[i][n + 1] = xi

        a_mat[i][n + 2] = yi

        a_mat[n][i] = 1.0

        a_mat[n + 1][i] = xi

        a_mat[n + 2][i] = yi



    sol = _gaussian_elimination(a_mat, rhs)

    weights = sol[:n]

    field = _TpsField(xy=list(xy), weights=weights, a=sol[n + 1], b=sol[n + 2], c=sol[n])



    residual = _matrix_residual(a_mat, sol, rhs)

    center_err = max(abs(field.eval_at(xy[i][0], xy[i][1]) - z[i]) for i in range(n))

    return field, residual, center_err





def _gaussian_elimination(a: list[list[float]], b: list[float]) -> list[float]:

    n = len(b)

    aug = [row[:] + [b[i]] for i, row in enumerate(a)]

    for col in range(n):

        pivot = col

        for row in range(col + 1, n):

            if abs(aug[row][col]) > abs(aug[pivot][col]):

                pivot = row

        if abs(aug[pivot][col]) < 1e-14:

            continue

        aug[col], aug[pivot] = aug[pivot], aug[col]

        div = aug[col][col]

        for j in range(col, n + 1):

            aug[col][j] /= div

        for row in range(n):

            if row == col:

                continue

            factor = aug[row][col]

            if factor == 0.0:

                continue

            for j in range(col, n + 1):

                aug[row][j] -= factor * aug[col][j]

    return [aug[i][n] for i in range(n)]





def _matrix_residual(a: list[list[float]], x: list[float], b: list[float]) -> float:

    n = len(b)

    max_r = 0.0

    for i in range(n):

        s = sum(a[i][j] * x[j] for j in range(n))

        max_r = max(max_r, abs(s - b[i]))

    return max_r





def _solve_tps_numpy(

    xy: list[tuple[float, float]],

    z: list[float],

) -> tuple[_TpsField, float, float]:

    assert np is not None

    n = len(xy)

    xs = np.array([p[0] for p in xy], dtype=np.float64)

    ys = np.array([p[1] for p in xy], dtype=np.float64)

    zz = np.array(z, dtype=np.float64)



    dx = xs[:, None] - xs[None, :]

    dy = ys[:, None] - ys[None, :]

    r = np.hypot(dx, dy)

    k = np.zeros((n, n), dtype=np.float64)

    mask = r > 0.0

    k[mask] = (r[mask] ** 2) * np.log(r[mask])



    p = np.ones((n, 3), dtype=np.float64)

    p[:, 1] = xs

    p[:, 2] = ys



    top = np.hstack([k, p])

    bottom = np.hstack([p.T, np.zeros((3, 3), dtype=np.float64)])

    a_mat = np.vstack([top, bottom])

    rhs = np.concatenate([zz, np.zeros(3, dtype=np.float64)])

    sol = np.linalg.solve(a_mat, rhs)



    weights = sol[:n].tolist()

    field = _TpsField(

        xy=list(xy),

        weights=weights,

        a=float(sol[n + 1]),

        b=float(sol[n + 2]),

        c=float(sol[n]),

    )

    residual = float(np.max(np.abs(a_mat @ sol - rhs)))

    center_err = max(abs(field.eval_at(xy[i][0], xy[i][1]) - z[i]) for i in range(n))

    return field, residual, center_err





def solve_component_field(

    xy: list[tuple[float, float]],

    z: list[float],

    *,

    prefer_numpy: bool = True,

) -> tuple[ComponentField, float, float]:

    n = len(xy)

    if n == 0:

        raise ValueError("empty component")

    if n == 1:

        return _solve_constant(z[0]), 0.0, 0.0

    if n == 2:

        field = _solve_linear_plane(xy, z)

        err = max(abs(field.eval_at(xy[i][0], xy[i][1]) - z[i]) for i in range(2))

        return field, 0.0, err

    if prefer_numpy and _NUMPY_AVAILABLE:

        return _solve_tps_numpy(xy, z)

    return _solve_tps_pure_python(xy, z)





def _component_centers(

    model: Any,

    tiles: frozenset[tuple[int, int]],

    *,

    radius: float,

) -> tuple[list[tuple[float, float]], list[float]]:

    xy: list[tuple[float, float]] = []

    zz: list[float] = []

    for q, r in sorted(tiles):

        cx, cy = handdrawn_center_world_xy(q, r, radius)

        xy.append((cx, cy))

        zz.append(canonical_center_world_z(model.map, q, r))

    return xy, zz





def _build_cliff_neighbor_map(model: Any) -> dict[tuple[int, int], frozenset[tuple[int, int]]]:

    by_tile: dict[tuple[int, int], set[tuple[int, int]]] = {}

    for cliff in model.cliff_edges:

        by_tile.setdefault(cliff.tile_a, set()).add(cliff.tile_b)

        by_tile.setdefault(cliff.tile_b, set()).add(cliff.tile_a)

    return {tile: frozenset(neighbors) for tile, neighbors in by_tile.items()}





def _side_cluster_for_tile(

    q: int,

    r: int,

    *,

    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],

    cliff_neighbors: dict[tuple[int, int], frozenset[tuple[int, int]]],

    all_tiles: set[tuple[int, int]],

) -> frozenset[tuple[int, int]]:

    """Smooth-connected tiles reachable without entering any direct cliff neighbor."""

    start = (q, r)

    blocked = cliff_neighbors.get(start, frozenset())

    seen: set[tuple[int, int]] = set()

    queue = [start]

    while queue:

        current = queue.pop(0)

        if current in seen or current in blocked:

            continue

        if current not in all_tiles:

            continue

        seen.add(current)

        for neighbor in smooth_adjacency.get(current, ()):

            if neighbor in seen or neighbor in blocked:

                continue

            queue.append(neighbor)

    return frozenset(seen)





def build_cliff_side_cluster_lookup(

    model: Any,

) -> tuple[dict[tuple[int, int], frozenset[tuple[int, int]]], list[frozenset[tuple[int, int]]]]:

    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)

    cliff_neighbors = _build_cliff_neighbor_map(model)

    all_tiles = set(model.map.tiles.keys())

    tile_to_cluster: dict[tuple[int, int], frozenset[tuple[int, int]]] = {}

    for coord in sorted(all_tiles):

        tile_to_cluster[coord] = _side_cluster_for_tile(

            coord[0],

            coord[1],

            smooth_adjacency=smooth_adjacency,

            cliff_neighbors=cliff_neighbors,

            all_tiles=all_tiles,

        )

    unique_clusters = sorted(set(tile_to_cluster.values()), key=lambda cluster: sorted(cluster))

    return tile_to_cluster, unique_clusters





def _baseline_neighbor_direction(

    from_tile: tuple[int, int],

    to_tile: tuple[int, int],

) -> int:

    q_b_from, r_b_from = handdrawn_to_baseline_axial(*from_tile)

    q_b_to, r_b_to = handdrawn_to_baseline_axial(*to_tile)

    dq = q_b_to - q_b_from

    dr = r_b_to - r_b_from

    for index, direction in enumerate(NEIGHBOR_DIRS):

        if direction == (dq, dr):

            return index

    raise ValueError(f"{to_tile} is not a baseline neighbor of {from_tile}")





def _physical_edge_for_baseline_neighbor(direction: int) -> int:

    return (5 - direction) % 6





def _affine_invariance_tests(

    xy: list[tuple[float, float]],

    *,

    prefer_numpy: bool,

) -> tuple[bool, float, bool, float]:

    if len(xy) < 3:

        return True, 0.0, True, 0.0



    z_const = [2.5] * len(xy)

    field_c, _, _ = solve_component_field(xy, z_const, prefer_numpy=prefer_numpy)

    const_err = max(abs(field_c.eval_at(x, y) - 2.5) for x, y in xy)



    z_planar = [0.3 * x - 0.2 * y + 1.0 for x, y in xy]

    field_p, _, _ = solve_component_field(xy, z_planar, prefer_numpy=prefer_numpy)

    planar_err = max(abs(field_p.eval_at(x, y) - z_planar[i]) for i, (x, y) in enumerate(xy))



    return (

        const_err < 1e-9,

        const_err,

        planar_err < 1e-6,

        planar_err,

    )





def _audit_representative_cliff_edge(

    solver: Any,

    model: Any,

    *,

    radius: float,

    tile_a: tuple[int, int] = (4, 0),

    tile_b: tuple[int, int] = (5, 0),

    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,

) -> CliffEdgeSamplingAudit | None:

    record = None

    for cliff in model.cliff_edge_graph:

        if frozenset((cliff.tile_a, cliff.tile_b)) == frozenset((tile_a, tile_b)):

            record = cliff

            break

    if record is None:

        return None



    elev_a = tile_world_z(model.map, *record.tile_a)

    elev_b = tile_world_z(model.map, *record.tile_b)

    if elev_a <= elev_b:

        lower_tile, upper_tile = record.tile_a, record.tile_b

    else:

        lower_tile, upper_tile = record.tile_b, record.tile_a



    edge_lower = _physical_edge_for_baseline_neighbor(

        _baseline_neighbor_direction(lower_tile, upper_tile)

    )

    edge_upper = _physical_edge_for_baseline_neighbor(

        _baseline_neighbor_direction(upper_tile, lower_tile)

    )

    mid = subdiv // 2



    def rim_mid_z(tile: tuple[int, int], edge: int) -> float:

        q, r = tile

        cx, cy = handdrawn_center_world_xy(q, r, radius)

        si, sj = mid, subdiv - mid

        if tile == upper_tile:

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



    lower_center_z = solver.sample_world(

        *handdrawn_center_world_xy(*lower_tile, radius),

        lower_tile[0],

        lower_tile[1],

    )

    upper_center_z = solver.sample_world(

        *handdrawn_center_world_xy(*upper_tile, radius),

        upper_tile[0],

        upper_tile[1],

    )

    lower_rim_mid_z = rim_mid_z(lower_tile, edge_lower)

    upper_rim_mid_z = rim_mid_z(upper_tile, edge_upper)

    rim_z_gap = upper_rim_mid_z - lower_rim_mid_z

    expected_gap = abs(

        tile_world_z(model.map, *record.tile_a) - tile_world_z(model.map, *record.tile_b)

    )

    lower_field_id = solver._field_id_for_tile(lower_tile)

    upper_field_id = solver._field_id_for_tile(upper_tile)



    return CliffEdgeSamplingAudit(

        tile_a=record.tile_a,

        tile_b=record.tile_b,

        lower_tile=lower_tile,

        upper_tile=upper_tile,

        lower_center_z=lower_center_z,

        upper_center_z=upper_center_z,

        lower_rim_mid_z=lower_rim_mid_z,

        upper_rim_mid_z=upper_rim_mid_z,

        rim_z_gap=rim_z_gap,

        expected_canonical_gap=expected_gap,

        used_distinct_fields=lower_field_id != upper_field_id,

        lower_field_id=lower_field_id,

        upper_field_id=upper_field_id,

    )





class VariationalSplineTerrainSolver:

    """Thin-plate spline per cliff-side cluster (TS-03d cliff-cut fields)."""



    backend = None  # attached in eom_terrain_solver



    def __init__(self) -> None:

        self._model: Any | None = None

        self._radius: float = DEFAULT_HEX_RADIUS

        self._fields_by_cluster_id: dict[int, ComponentField] = {}

        self._field_id_by_tile: dict[tuple[int, int], int] = {}

        self._cluster_by_id: dict[int, frozenset[tuple[int, int]]] = {}

        self._report: VariationalSplineSolveReport | None = None



    def _field_id_for_tile(self, tile: tuple[int, int]) -> int:

        return self._field_id_by_tile[tile]



    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:

        self._model = model

        self._radius = radius

        self._fields_by_cluster_id.clear()

        self._field_id_by_tile.clear()

        self._cluster_by_id.clear()



        tile_to_cluster, unique_clusters = build_cliff_side_cluster_lookup(model)

        cluster_id_for_tiles: dict[frozenset[tuple[int, int]], int] = {

            cluster: index for index, cluster in enumerate(unique_clusters)

        }



        component_reports: list[ComponentSolveReport] = []

        all_input_z: list[float] = []

        max_center_err = 0.0

        max_residual = 0.0



        for cluster_id, cluster in enumerate(unique_clusters):

            self._cluster_by_id[cluster_id] = cluster

            xy, zz = _component_centers(model, cluster, radius=radius)

            all_input_z.extend(zz)

            field, residual, center_err = solve_component_field(

                xy,

                zz,

                prefer_numpy=_NUMPY_AVAILABLE,

            )

            self._fields_by_cluster_id[cluster_id] = field

            max_center_err = max(max_center_err, center_err)

            max_residual = max(max_residual, residual)

            matrix_size = len(xy) + 3 if len(xy) >= 3 else len(xy)

            component_reports.append(

                ComponentSolveReport(

                    domain_id=cluster_id,

                    center_count=len(xy),

                    matrix_size=matrix_size,

                    solve_residual=residual,

                    max_center_error=center_err,

                    kind=field.kind,

                )

            )



        for tile, cluster in tile_to_cluster.items():

            field_id = cluster_id_for_tiles[cluster]

            self._field_id_by_tile[tile] = field_id



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

            prefer_numpy=_NUMPY_AVAILABLE,

        )



        input_min = min(all_input_z) if all_input_z else 0.0

        input_max = max(all_input_z) if all_input_z else 0.0

        input_range = input_max - input_min



        z_samples: list[float] = []

        for cluster_id, cluster in enumerate(unique_clusters):

            xy_d, _zz_d = _component_centers(model, cluster, radius=radius)

            field_d = self._fields_by_cluster_id[cluster_id]

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



        self._report = VariationalSplineSolveReport(

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



        cliff_audit = _audit_representative_cliff_edge(self, model, radius=radius)

        if cliff_audit is not None:

            self._report.representative_cliff = cliff_audit

            if not cliff_audit.used_distinct_fields:

                self._report.warnings.append(

                    "representative cliff (4,0)<->(5,0) sampled the same solver field on both sides"

                )

            if cliff_audit.expected_canonical_gap > 1e-9:

                gap_ratio = cliff_audit.rim_z_gap / cliff_audit.expected_canonical_gap

                if gap_ratio < 0.5:

                    self._report.warnings.append(

                        f"representative cliff rim gap {cliff_audit.rim_z_gap:.4f} "

                        f"is far below canonical {cliff_audit.expected_canonical_gap:.4f}"

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

        del sector, at_corner, at_sector_outer_edge, idw_fallback, legacy_fallback

        assert self._model is not None

        tile = (q, r)

        if tile not in self._field_id_by_tile:

            raise RuntimeError(f"variational_spline sample outside map: tile ({q}, {r})")

        field_id = self._field_id_by_tile[tile]

        field = self._fields_by_cluster_id.get(field_id)

        if field is None:

            raise RuntimeError(f"variational_spline missing cliff-side field {field_id} for tile ({q}, {r})")

        return field.eval_at(wx, wy)



    @property

    def stats(self) -> dict[str, Any] | None:

        if self._report is None:

            return None

        return self._report.as_dict()





def _run_self_tests() -> None:

    from eom_terrain_math_core import build_terrain_model



    json_two = """

    {

      "id": "ts03_two_smooth",

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

    solver = VariationalSplineTerrainSolver()

    solver.prepare(model)

    cx, cy = handdrawn_center_world_xy(0, 0)

    assert abs(solver.sample_world(cx, cy, 0, 0) - 0.0) < 1e-9

    cx1, cy1 = handdrawn_center_world_xy(1, 0)

    assert abs(solver.sample_world(cx1, cy1, 1, 0) - 0.4) < 1e-9



    json_one = """

    {

      "id": "ts03_one",

      "orientation": "pointy_top_custom_axes",

      "elevation_step": 0.4,

      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},

      "tiles": [{"q":0,"r":0,"elevation":3}]

    }

    """

    model_one = build_terrain_model(json_one)

    solver_one = VariationalSplineTerrainSolver()

    solver_one.prepare(model_one)

    h = solver_one.sample_world(cx, cy, 0, 0)

    assert abs(h - 0.8) < 1e-9



    json_cliff = """

    {

      "id": "ts03d_cliff_two",

      "orientation": "pointy_top_custom_axes",

      "elevation_step": 0.4,

      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},

      "tiles": [

        {"q":0,"r":0,"elevation":1},

        {"q":1,"r":0,"elevation":5}

      ]

    }

    """

    model_cliff = build_terrain_model(json_cliff)

    solver_cliff = VariationalSplineTerrainSolver()

    solver_cliff.prepare(model_cliff)

    assert solver_cliff.stats["cliff_cut_field_count"] == 2

    assert (

        solver_cliff._field_id_for_tile((0, 0))

        != solver_cliff._field_id_for_tile((1, 0))

    )

    h0 = solver_cliff.sample_world(*handdrawn_center_world_xy(0, 0), 0, 0)

    h1 = solver_cliff.sample_world(*handdrawn_center_world_xy(1, 0), 1, 0)

    assert abs(h0 - 0.0) < 1e-9

    assert abs(h1 - 1.6) < 1e-9



    xy = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]

    z_planar = [0.5 * x + 0.25 * y + 1.0 for x, y in xy]

    field, _, err = solve_component_field(xy, z_planar, prefer_numpy=False)

    for i, (x, y) in enumerate(xy):

        assert abs(field.eval_at(x, y) - z_planar[i]) < 1e-6

    assert abs(field.eval_at(0.5, 0.5) - 1.375) < 1e-6



    print("eom_terrain_variational_spline self-test passed")





if __name__ == "__main__":

    _run_self_tests()


