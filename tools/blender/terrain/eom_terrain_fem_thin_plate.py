# Empire of Minds — FEM thin-plate terrain backend on cliff-cut mesh (TS-04d).
# Stein et al. 2018 Route B mixed-FEM squared-Hessian energy with hard center pins; direct solve on small patches.

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    canonical_center_world_z,
    handdrawn_center_world_xy,
    handdrawn_to_baseline_axial,
    pos_key,
)
from eom_terrain_math_core import (
    _build_smooth_adjacency,
    _smooth_component_at_corner,
    _tiles_touching_corner,
)

try:
    import numpy as np

    _NUMPY_AVAILABLE = True
except ImportError:
    np = None  # type: ignore[assignment,misc]
    _NUMPY_AVAILABLE = False

# TS-04d: formulation slice uses exact dense elimination only; large canonical solve is out of scope.
DIRECT_SOLVE_MAX_FREE_DOFS = 12000


@dataclass
class CliffCutMesh:
    node_count: int
    node_xy: list[tuple[float, float]]
    triangles: list[tuple[int, int, int]]
    pinned: dict[int, float]
    sample_lookup: dict[tuple[Any, ...], int]
    component_ids: list[int]
    component_count: int
    adjacency: list[list[int]]


@dataclass
class FemThinPlateSolveReport:
    node_count: int
    triangle_count: int
    component_count: int
    pinned_center_count: int
    free_dof_count: int
    laplacian_nnz: int
    cg_iterations: int
    final_residual: float
    relative_residual: float
    cg_solve_blocks: int
    mesh_connected_via_smooth_detour: bool
    no_stencil_across_cliff: bool
    cross_cliff_stencil_count: int
    representative_cliff_rim_gap: float | None
    delete_opposite_side_max_delta: float | None
    max_center_interpolation_error: float
    affine_constant_ok: bool
    affine_constant_max_error: float
    affine_planar_ok: bool
    affine_planar_max_error: float
    z_min: float
    z_max: float
    input_z_min: float
    input_z_max: float
    max_overshoot: float
    cliff_cut_two_tile_ok: bool
    cross_cliff_decoupling_delta: float | None
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "backend": "fem_thin_plate",
            "node_count": self.node_count,
            "triangle_count": self.triangle_count,
            "component_count": self.component_count,
            "pinned_center_count": self.pinned_center_count,
            "free_dof_count": self.free_dof_count,
            "laplacian_nnz": self.laplacian_nnz,
            "cg_iterations": self.cg_iterations,
            "final_residual": self.final_residual,
            "relative_residual": self.relative_residual,
            "cg_solve_blocks": self.cg_solve_blocks,
            "mesh_connected_via_smooth_detour": self.mesh_connected_via_smooth_detour,
            "no_stencil_across_cliff": self.no_stencil_across_cliff,
            "cross_cliff_stencil_count": self.cross_cliff_stencil_count,
            "representative_cliff_rim_gap": self.representative_cliff_rim_gap,
            "delete_opposite_side_max_delta": self.delete_opposite_side_max_delta,
            "max_center_interpolation_error": self.max_center_interpolation_error,
            "affine_constant_ok": self.affine_constant_ok,
            "affine_constant_max_error": self.affine_constant_max_error,
            "affine_planar_ok": self.affine_planar_ok,
            "affine_planar_max_error": self.affine_planar_max_error,
            "z_min": self.z_min,
            "z_max": self.z_max,
            "input_z_min": self.input_z_min,
            "input_z_max": self.input_z_max,
            "max_overshoot": self.max_overshoot,
            "cliff_cut_two_tile_ok": self.cliff_cut_two_tile_ok,
            "cross_cliff_decoupling_delta": self.cross_cliff_decoupling_delta,
            "warnings": list(self.warnings),
        }


def _cluster_key_for_tile(
    wx: float,
    wy: float,
    q: int,
    r: int,
    model: Any,
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[tuple[int, int], ...]]:
    sharing = _tiles_touching_corner(
        model.map,
        wx,
        wy,
        model.map.tiles.keys(),
        radius=radius,
    )
    cluster = _smooth_component_at_corner((q, r), sharing, smooth_adjacency)
    return (pos_key(wx, wy), tuple(sorted(cluster)))


def build_cliff_cut_mesh(
    model: Any,
    baseline: Any,
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> CliffCutMesh:
    """Sector-grid triangulation with merge only within smooth-connected clusters."""
    hex_coords = set(model.map.tiles.keys())
    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    merge_map: dict[tuple[Any, ...], int] = {}
    pinned: dict[int, float] = {}
    node_xy: list[tuple[float, float]] = []
    triangles: list[tuple[int, int, int]] = []

    def node_id_for(
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        is_center: bool,
    ) -> int:
        if is_center:
            key: tuple[Any, ...] = ("center", q, r)
        else:
            cluster_key = _cluster_key_for_tile(
                wx,
                wy,
                q,
                r,
                model,
                smooth_adjacency,
                radius=radius,
            )
            key = ("pos", cluster_key[0], cluster_key[1])
        existing = merge_map.get(key)
        if existing is not None:
            return existing
        index = len(node_xy)
        merge_map[key] = index
        node_xy.append((wx, wy))
        if is_center:
            pinned[index] = canonical_center_world_z(model.map, q, r)
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
                    is_center = si == 0 and sj == 0
                    nid = node_id_for(wx, wy, q_h, r_h, is_center=is_center)
                    grid[(si, sj)] = nid
                    sj += 1

            for si in range(subdiv):
                sj = 0
                while sj <= subdiv - si - 1:
                    v00 = grid[(si, sj)]
                    v10 = grid[(si + 1, sj)]
                    v01 = grid[(si, sj + 1)]
                    triangles.append((v00, v10, v01))
                    if sj + 1 <= subdiv - (si + 1):
                        v11 = grid[(si + 1, sj + 1)]
                        triangles.append((v10, v01, v11))
                    sj += 1

    adjacency_sets: list[set[int]] = [set() for _ in range(len(node_xy))]
    for a, b, c in triangles:
        for i, j in ((a, b), (b, c), (c, a)):
            adjacency_sets[i].add(j)
            adjacency_sets[j].add(i)
    adjacency = [sorted(neighbors) for neighbors in adjacency_sets]
    component_ids, component_count = _connected_components(adjacency)

    sample_lookup: dict[tuple[Any, ...], int] = {}
    for key, nid in merge_map.items():
        sample_lookup[key] = nid
        if key[0] == "pos":
            pk, cluster = key[1], key[2]
            for tq, tr in cluster:
                sample_lookup[(pk, tq, tr)] = nid

    return CliffCutMesh(
        node_count=len(node_xy),
        node_xy=node_xy,
        triangles=triangles,
        pinned=pinned,
        sample_lookup=sample_lookup,
        component_ids=component_ids,
        component_count=component_count,
        adjacency=adjacency,
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


def _triangle_geometry(
    xy: list[tuple[float, float]],
    i: int,
    j: int,
    k: int,
) -> tuple[float, float, float, float, float, float]:
    xi, yi = xy[i]
    xj, yj = xy[j]
    xk, yk = xy[k]
    area2 = abs((xj - xi) * (yk - yi) - (xk - xi) * (yj - yi))
    area = 0.5 * area2
    if area <= 1e-18:
        return 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    cot_i = ((xj - xi) * (xk - xi) + (yj - yi) * (yk - yi)) / area2
    cot_j = ((xi - xj) * (xk - xj) + (yi - yj) * (yk - yj)) / area2
    cot_k = ((xi - xk) * (xj - xk) + (yi - yk) * (yj - yk)) / area2
    return area, cot_i, cot_j, cot_k, area2, area


def assemble_cotan_laplacian_and_mass(
    mesh: CliffCutMesh,
) -> tuple[list[list[tuple[int, float]]], list[float]]:
    n = mesh.node_count
    rows: list[dict[int, float]] = [dict() for _ in range(n)]
    mass = [0.0] * n

    for i, j, k in mesh.triangles:
        area, cot_i, cot_j, cot_k, _area2, _area = _triangle_geometry(mesh.node_xy, i, j, k)
        if area <= 1e-18:
            continue
        third = area / 3.0
        mass[i] += third
        mass[j] += third
        mass[k] += third

        for a, b, cot_opposite in (
            (i, j, cot_k),
            (j, k, cot_i),
            (k, i, cot_j),
        ):
            w = 0.5 * cot_opposite
            rows[a][a] = rows[a].get(a, 0.0) + w
            rows[b][b] = rows[b].get(b, 0.0) + w
            rows[a][b] = rows[a].get(b, 0.0) - w
            rows[b][a] = rows[b].get(a, 0.0) - w

    for idx in range(n):
        if mass[idx] <= 1e-18:
            mass[idx] = 1.0

    laplacian = [sorted(row.items()) for row in rows]
    return laplacian, mass


def _vertex_lumped_area(mesh: CliffCutMesh) -> list[float]:
    """Per-vertex lumped area A_i (area/3 per incident triangle)."""
    mass = [0.0] * mesh.node_count
    for i, j, k in mesh.triangles:
        area, _, _, _, _, _ = _triangle_geometry(mesh.node_xy, i, j, k)
        if area <= 1e-18:
            continue
        third = area / 3.0
        mass[i] += third
        mass[j] += third
        mass[k] += third
    for idx in range(mesh.node_count):
        if mass[idx] <= 1e-18:
            mass[idx] = 1.0
    return mass


def _undirected_edge(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _boundary_vertex_set(mesh: CliffCutMesh) -> set[int]:
    """Vertices on edges incident to exactly one triangle (outer map + cliff rims)."""
    edge_incidence: dict[tuple[int, int], int] = {}
    for i, j, k in mesh.triangles:
        for a, b in ((i, j), (j, k), (k, i)):
            edge = _undirected_edge(a, b)
            edge_incidence[edge] = edge_incidence.get(edge, 0) + 1
    boundary: set[int] = set()
    for (a, b), count in edge_incidence.items():
        if count == 1:
            boundary.add(a)
            boundary.add(b)
    return boundary


def _boundary_outward_normals(
    mesh: CliffCutMesh,
) -> tuple[set[int], dict[int, list[tuple[float, float]]]]:
    """Boundary vertices and unit outward normals per adjacent boundary edge."""
    edge_triangles: dict[tuple[int, int], list[int]] = {}
    for face_idx, (i, j, k) in enumerate(mesh.triangles):
        for a, b in ((i, j), (j, k), (k, i)):
            edge = _undirected_edge(a, b)
            edge_triangles.setdefault(edge, []).append(face_idx)

    boundary_vertices: set[int] = set()
    outward: dict[int, list[tuple[float, float]]] = {}
    for edge, faces in edge_triangles.items():
        if len(faces) != 1:
            continue
        a, b = edge
        boundary_vertices.add(a)
        boundary_vertices.add(b)
        face_idx = faces[0]
        i, j, k = mesh.triangles[face_idx]
        third = next(v for v in (i, j, k) if v not in (a, b))
        xa, ya = mesh.node_xy[a]
        xb, yb = mesh.node_xy[b]
        xt, yt = mesh.node_xy[third]
        mx, my = 0.5 * (xa + xb), 0.5 * (ya + yb)
        ex, ey = xb - xa, yb - ya
        nx, ny = -ey, ex
        if (xt - mx) * nx + (yt - my) * ny > 0.0:
            nx, ny = ey, -ex
        length = math.hypot(nx, ny)
        if length <= 1e-18:
            continue
        unit = (nx / length, ny / length)
        outward.setdefault(a, []).append(unit)
        outward.setdefault(b, []).append(unit)
    return boundary_vertices, outward


def _face_p1_gradients(
    mesh: CliffCutMesh,
    i: int,
    j: int,
    k: int,
) -> tuple[float, tuple[float, float], tuple[float, float], tuple[float, float]] | None:
    """Signed P1 hat gradients on one triangle; area is unsigned."""
    xi, yi = mesh.node_xy[i]
    xj, yj = mesh.node_xy[j]
    xk, yk = mesh.node_xy[k]
    signed_area2 = (xj - xi) * (yk - yi) - (xk - xi) * (yj - yi)
    if abs(signed_area2) <= 1e-18:
        return None
    area = 0.5 * abs(signed_area2)
    inv_signed_area2 = 1.0 / signed_area2
    verts = (i, j, k)
    coords = [mesh.node_xy[v] for v in verts]
    grads: list[tuple[float, float]] = []
    for idx in range(3):
        a = (idx + 1) % 3
        b = (idx + 2) % 3
        xa, ya = coords[a]
        xb, yb = coords[b]
        gx = (ya - yb) * inv_signed_area2
        gy = (xb - xa) * inv_signed_area2
        grads.append((gx, gy))
    return area, grads[0], grads[1], grads[2]


def _mass_inverse_for_mixed_fem(
    mesh: CliffCutMesh,
    *,
    clamp_boundary: bool,
) -> tuple[list[float], set[int]]:
    """Lumped vertex mass and diagonal M_inv (interior-only when clamp_boundary)."""
    mass = _vertex_lumped_area(mesh)
    boundary = _boundary_vertex_set(mesh)
    if clamp_boundary:
        m_inv = [0.0 if idx in boundary else 1.0 / mass[idx] for idx in range(mesh.node_count)]
    else:
        m_inv = [1.0 / mass[idx] for idx in range(mesh.node_count)]
    return m_inv, boundary


def _ring_neighborhood(adjacency: list[list[int]], center: int, ring_depth: int) -> list[int]:
    seen = {center}
    frontier = {center}
    for _ in range(ring_depth):
        next_frontier: set[int] = set()
        for vertex in frontier:
            for neighbor in adjacency[vertex]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    next_frontier.add(neighbor)
        frontier = next_frontier
    return sorted(seen)


def _invert_matrix_cols(cols: list[list[float]]) -> list[list[float]] | None:
    n = len(cols)
    inv = [[0.0] * n for _ in range(n)]
    for col in range(n):
        rhs = [1.0 if row == col else 0.0 for row in range(n)]
        try:
            solution = _gaussian_solve(cols, rhs)
        except (ValueError, ZeroDivisionError):
            return None
        for row in range(n):
            inv[row][col] = solution[row]
    return inv


def _local_quadratic_hessian_map(
    mesh: CliffCutMesh,
    center: int,
    neighbors: list[int],
) -> list[list[float]] | None:
    """Return S_i (3 x len(neighbors)): neighborhood values -> (u_xx, u_xy, u_yy)."""
    xi, yi = mesh.node_xy[center]
    count = len(neighbors)
    if count < 3:
        return None

    bt_wb = [[0.0] * 6 for _ in range(6)]
    btw = [[0.0] * count for _ in range(6)]
    for local_idx, node in enumerate(neighbors):
        xk, yk = mesh.node_xy[node]
        dx = xk - xi
        dy = yk - yi
        row = [1.0, dx, dy, 0.5 * dx * dx, dx * dy, 0.5 * dy * dy]
        weight = 1.0
        for a in range(6):
            btw[a][local_idx] = weight * row[a]
            for b in range(6):
                bt_wb[a][b] += weight * row[a] * row[b]

    inv = _invert_matrix_cols([[bt_wb[r][c] for r in range(6)] for c in range(6)])
    if inv is None:
        return None

    fit = [[0.0] * count for _ in range(6)]
    for a in range(6):
        for local_idx in range(count):
            fit[a][local_idx] = sum(inv[a][b] * btw[b][local_idx] for b in range(6))
    return fit[3:6]


def _local_hessian_map_with_ring_expansion(
    mesh: CliffCutMesh,
    center: int,
    *,
    min_ring: int = 2,
    max_ring: int = 6,
) -> tuple[list[int], list[list[float]]] | None:
    for ring in range(min_ring, max_ring + 1):
        neighbors = _ring_neighborhood(mesh.adjacency, center, ring)
        hess_map = _local_quadratic_hessian_map(mesh, center, neighbors)
        if hess_map is None:
            continue
        if _affine_hessian_map_is_zero(mesh, neighbors, hess_map):
            return neighbors, hess_map
    return None


def _affine_hessian_map_is_zero(
    mesh: CliffCutMesh,
    neighbors: list[int],
    hess_map: list[list[float]],
    *,
    tol: float = 1e-9,
) -> bool:
    """True when S maps the local affine basis to zero second derivatives."""
    for c0 in (0.0, 1.0):
        for c1 in (0.0, 0.5):
            for c2 in (0.0, -0.3):
                values = [
                    c0 + c1 * mesh.node_xy[node][0] + c2 * mesh.node_xy[node][1]
                    for node in neighbors
                ]
                for row in range(3):
                    second = sum(hess_map[row][local] * values[local] for local in range(len(neighbors)))
                    if abs(second) > tol:
                        return False
    return True


def _add_symmetric_k_row(rows: list[dict[int, float]], i: int, j: int, value: float) -> None:
    if abs(value) < 1e-18:
        return
    rows[i][j] = rows[i].get(j, 0.0) + value
    if i != j:
        rows[j][i] = rows[j].get(i, 0.0) + value


def _accumulate_s_ab_from_faces(
    mesh: CliffCutMesh,
) -> tuple[
    list[dict[int, float]],
    list[dict[int, float]],
    list[dict[int, float]],
    list[dict[int, float]],
]:
    """Build S_xx, S_xy, S_yx, S_yy for Stein Eq. (26)/(30): H = D^T A G."""
    n = mesh.node_count
    s_xx: list[dict[int, float]] = [dict() for _ in range(n)]
    s_xy: list[dict[int, float]] = [dict() for _ in range(n)]
    s_yx: list[dict[int, float]] = [dict() for _ in range(n)]
    s_yy: list[dict[int, float]] = [dict() for _ in range(n)]

    for i, j, k in mesh.triangles:
        geom = _face_p1_gradients(mesh, i, j, k)
        if geom is None:
            continue
        area, grad_i, grad_j, grad_k = geom
        verts = (i, j, k)
        grads = (grad_i, grad_j, grad_k)
        for ai, va in enumerate(verts):
            gxa, gya = grads[ai]
            for bi, vb in enumerate(verts):
                gxb, gyb = grads[bi]
                s_xx[va][vb] = s_xx[va].get(vb, 0.0) + area * gxa * gxb
                s_xy[va][vb] = s_xy[va].get(vb, 0.0) + area * gya * gxb
                s_yx[va][vb] = s_yx[va].get(vb, 0.0) + area * gxa * gyb
                s_yy[va][vb] = s_yy[va].get(vb, 0.0) + area * gya * gyb

    return s_xx, s_xy, s_yx, s_yy


def _assemble_k_from_s_ab(
    s_xx: list[dict[int, float]],
    s_xy: list[dict[int, float]],
    s_yx: list[dict[int, float]],
    s_yy: list[dict[int, float]],
    m_inv: list[float],
) -> list[list[tuple[int, float]]]:
    """K = S_xx^T M_inv S_xx + S_xy^T M_inv S_xy + S_yx^T M_inv S_yx + S_yy^T M_inv S_yy."""
    n = len(m_inv)
    rows: list[dict[int, float]] = [dict() for _ in range(n)]
    for s_ab in (s_xx, s_xy, s_yx, s_yy):
        for vertex in range(n):
            mi = m_inv[vertex]
            if mi <= 0.0:
                continue
            row_s = s_ab[vertex]
            if not row_s:
                continue
            for col_j, s_ij in row_s.items():
                for col_k, s_ik in row_s.items():
                    val = mi * s_ij * s_ik
                    if abs(val) < 1e-18:
                        continue
                    rows[col_j][col_k] = rows[col_j].get(col_k, 0.0) + val
    return [sorted(row.items()) for row in rows]


def _dense_symmetric_to_energy_rows(matrix: Any) -> list[list[tuple[int, float]]]:
    assert np is not None
    n = int(matrix.shape[0])
    rows: list[list[tuple[int, float]]] = []
    for i in range(n):
        row_dict: dict[int, float] = {}
        for j in range(i, n):
            value = float(matrix[i, j])
            if abs(value) > 1e-18:
                row_dict[j] = value
        rows.append(sorted(row_dict.items()))
    return rows


def assemble_hessian_energy_mixed_fem(
    mesh: CliffCutMesh,
    *,
    clamp_boundary: bool = True,
) -> list[list[tuple[int, float]]]:
    """Stein et al. 2018 Route B mixed-FEM squared-Hessian energy (Eq. 26/30 condensed)."""
    m_inv, _boundary = _mass_inverse_for_mixed_fem(mesh, clamp_boundary=clamp_boundary)
    if _NUMPY_AVAILABLE:
        assert np is not None
        n = mesh.node_count
        m = len(mesh.triangles)
        gx = np.zeros((m, n), dtype=np.float64)
        gy = np.zeros((m, n), dtype=np.float64)
        areas = np.zeros(m, dtype=np.float64)
        for face_idx, (i, j, k) in enumerate(mesh.triangles):
            geom = _face_p1_gradients(mesh, i, j, k)
            if geom is None:
                continue
            area, grad_i, grad_j, grad_k = geom
            areas[face_idx] = area
            for vertex, (gpx, gpy) in zip((i, j, k), (grad_i, grad_j, grad_k), strict=True):
                gx[face_idx, vertex] = gpx
                gy[face_idx, vertex] = gpy
        weight = np.diag(areas)
        s_xx = gx.T @ weight @ gx
        s_xy = gy.T @ weight @ gx
        s_yx = gx.T @ weight @ gy
        s_yy = gy.T @ weight @ gy
        m_inv_diag = np.diag(np.array(m_inv, dtype=np.float64))
        k_h = (
            s_xx.T @ m_inv_diag @ s_xx
            + s_xy.T @ m_inv_diag @ s_xy
            + s_yx.T @ m_inv_diag @ s_yx
            + s_yy.T @ m_inv_diag @ s_yy
        )
        return _dense_symmetric_to_energy_rows(k_h)

    s_xx, s_xy, s_yx, s_yy = _accumulate_s_ab_from_faces(mesh)
    return _assemble_k_from_s_ab(s_xx, s_xy, s_yx, s_yy, m_inv)


def assemble_hessian_energy_matrix(mesh: CliffCutMesh) -> list[list[tuple[int, float]]]:
    """Assemble K for E = sum_i A_i |H u|^2 via local quadratic-fit Hessian recovery."""
    n = mesh.node_count
    area = _vertex_lumped_area(mesh)
    rows: list[dict[int, float]] = [dict() for _ in range(n)]
    hess_weights = (1.0, 2.0, 1.0)

    for center in range(n):
        fit = _local_hessian_map_with_ring_expansion(mesh, center)
        if fit is None:
            continue
        neighbors, hess_map = fit
        ai = area[center]
        local_count = len(neighbors)
        for la in range(local_count):
            ga = neighbors[la]
            for lb in range(la, local_count):
                gb = neighbors[lb]
                entry = 0.0
                for component, weight in enumerate(hess_weights):
                    entry += ai * weight * hess_map[component][la] * hess_map[component][lb]
                _add_symmetric_k_row(rows, ga, gb, entry)

    return [sorted(row.items()) for row in rows]


def _energy_matrix_nnz(energy: list[list[tuple[int, float]]]) -> int:
    return sum(len(row) for row in energy)


def _spmv_energy(
    energy: list[list[tuple[int, float]]],
    x: list[float],
) -> list[float]:
    y = [0.0] * len(x)
    for row_idx, row in enumerate(energy):
        s = 0.0
        for col, val in row:
            s += val * x[col]
        y[row_idx] = s
    return y


def _solve_constrained_hessian_direct(
    energy: list[list[tuple[int, float]]],
    free_indices: list[int],
    pinned_values: dict[int, float],
    *,
    prefer_numpy: bool = True,
    direct_limit: int = DIRECT_SOLVE_MAX_FREE_DOFS,
) -> tuple[list[float], int, float]:
    """Minimize u^T K u subject to pinned DOFs; direct dense elimination only."""
    n = len(energy)
    z = [pinned_values.get(i, 0.0) for i in range(n)]
    m = len(free_indices)
    if m == 0:
        return z, 0, 0.0
    if m > direct_limit:
        raise RuntimeError(
            "TS-04d Hessian energy supports direct solve only on small patches; "
            f"free DOFs={m} exceeds limit={direct_limit}. "
            "Large canonical map solve is out of scope for this slice."
        )

    pin_vals = list(pinned_values.values())
    if pin_vals and max(pin_vals) - min(pin_vals) < 1e-12:
        fill = pin_vals[0]
        z = [fill if i in pinned_values else fill for i in range(n)]
        return z, 0, 0.0

    kz = _spmv_energy(energy, z)
    b = [-kz[node] for node in free_indices]

    if prefer_numpy and _NUMPY_AVAILABLE:
        assert np is not None
        kff = np.zeros((m, m), dtype=np.float64)
        for j, free_col in enumerate(free_indices):
            ej = np.zeros(n, dtype=np.float64)
            ej[free_col] = 1.0
            kff[:, j] = np.array(_spmv_energy(energy, ej.tolist()), dtype=np.float64)[free_indices]
        x = np.linalg.solve(kff, np.array(b, dtype=np.float64))
        residual = float(np.linalg.norm(kff @ x - np.array(b, dtype=np.float64)))
        for node, val in zip(free_indices, x.tolist(), strict=True):
            z[node] = val
        return z, 0, residual

    kff_cols: list[list[float]] = []
    for free_col in free_indices:
        ej = [0.0] * n
        ej[free_col] = 1.0
        kff_cols.append([_spmv_energy(energy, ej)[node] for node in free_indices])
    x = _gaussian_solve(kff_cols, b)
    residual = math.sqrt(
        sum(
            (sum(kff_cols[j][i] * x[j] for j in range(m)) - b[i]) ** 2
            for i in range(m)
        )
    )
    for node, val in zip(free_indices, x, strict=True):
        z[node] = val
    return z, 0, residual


def _energy_affine_precision_tests(
    mesh: CliffCutMesh,
    energy: list[list[tuple[int, float]]],
) -> tuple[bool, float, bool, float]:
    if mesh.node_count < 3:
        return True, 0.0, True, 0.0
    z_const = [2.5] * mesh.node_count
    k_const = _spmv_energy(energy, z_const)
    const_err = max(abs(v) for v in k_const)

    z_planar = [0.3 * x - 0.2 * y + 1.0 for x, y in mesh.node_xy]
    k_planar = _spmv_energy(energy, z_planar)
    planar_err = max(abs(v) for v in k_planar)
    return const_err < 1e-9, const_err, planar_err < 1e-9, planar_err


def _verify_no_energy_across_cliff(
    energy: list[list[tuple[int, float]]],
    mesh: CliffCutMesh,
    model: Any | None,
) -> tuple[bool, int]:
    if model is None:
        return True, 0
    pairs = _collect_opposite_cliff_rim_pairs(mesh, model)
    if not pairs:
        return True, 0
    energy_lookup: dict[tuple[int, int], float] = {}
    for i, row in enumerate(energy):
        for j, val in row:
            if i != j and abs(val) > 1e-18:
                energy_lookup[(i, j)] = val
    cross_count = 0
    for a, b in pairs:
        if (a, b) in energy_lookup or (b, a) in energy_lookup:
            cross_count += 1
    return cross_count == 0, cross_count


def _nullspace_dimension_per_component(
    energy: list[list[tuple[int, float]]],
    mesh: CliffCutMesh,
    *,
    tol: float = 1e-7,
) -> dict[int, int]:
    """Estimate nullspace dimension per mesh component via |K v| for affine probes."""
    dims: dict[int, int] = {}
    for cid in range(mesh.component_count):
        nodes = [i for i in range(mesh.node_count) if mesh.component_ids[i] == cid]
        if len(nodes) < 3:
            dims[cid] = len(nodes)
            continue
        cx = sum(mesh.node_xy[i][0] for i in nodes) / len(nodes)
        cy = sum(mesh.node_xy[i][1] for i in nodes) / len(nodes)
        probes: list[list[float]] = [
            [1.0 if i in nodes else 0.0 for i in range(mesh.node_count)],
            [
                (mesh.node_xy[i][0] - cx if i in nodes else 0.0)
                for i in range(mesh.node_count)
            ],
            [
                (mesh.node_xy[i][1] - cy if i in nodes else 0.0)
                for i in range(mesh.node_count)
            ],
        ]
        null_count = 0
        for probe in probes:
            kv = _spmv_energy(energy, probe)
            norm = math.sqrt(sum(kv[i] * kv[i] for i in nodes))
            if norm <= tol:
                null_count += 1
        dims[cid] = null_count
    return dims


def _tps_height_at(
    x: float,
    y: float,
    centers_xy: list[tuple[float, float]],
    center_z: list[float],
    weights: list[float],
    affine: tuple[float, float, float],
) -> float:
    c0, c1, c2 = affine
    height = c0 + c1 * x + c2 * y
    for (cx, cy), w in zip(centers_xy, weights, strict=True):
        dx = x - cx
        dy = y - cy
        r2 = dx * dx + dy * dy
        if r2 <= 1e-18:
            continue
        height += w * 0.5 * r2 * math.log(r2)
    return height


def _fit_tps_at_centers(
    centers_xy: list[tuple[float, float]],
    center_z: list[float],
) -> tuple[list[float], tuple[float, float, float]]:
    count = len(centers_xy)
    dim = count + 3
    cols = [[0.0] * dim for _ in range(dim)]
    rhs = [0.0] * dim
    for i in range(count):
        rhs[i] = center_z[i]
        for j in range(count):
            dx = centers_xy[i][0] - centers_xy[j][0]
            dy = centers_xy[i][1] - centers_xy[j][1]
            r2 = dx * dx + dy * dy
            phi = 0.0 if r2 <= 1e-18 else 0.5 * r2 * math.log(r2)
            cols[j][i] = phi
        cols[count][i] = 1.0
        cols[count + 1][i] = centers_xy[i][0]
        cols[count + 2][i] = centers_xy[i][1]
    for j in range(count):
        cols[j][count] = 1.0
        cols[j][count + 1] = centers_xy[j][0]
        cols[j][count + 2] = centers_xy[j][1]
    sol = _gaussian_solve(cols, rhs)
    return sol[:count], (sol[count], sol[count + 1], sol[count + 2])


def _profile_along_segment(
    mesh: CliffCutMesh,
    heights: list[float],
    start: tuple[float, float],
    end: tuple[float, float],
    *,
    perp_tol: float = 0.08,
) -> list[tuple[float, float]]:
    cx, cy = start
    nx, ny = end
    dx, dy = nx - cx, ny - cy
    length_sq = dx * dx + dy * dy
    profile: list[tuple[float, float]] = []
    for nid, (x, y) in enumerate(mesh.node_xy):
        t = ((x - cx) * dx + (y - cy) * dy) / length_sq
        px = cx + t * dx
        py = cy + t * dy
        if -0.02 <= t <= 1.02 and math.hypot(x - px, y - py) <= perp_tol:
            profile.append((t, heights[nid]))
    profile.sort()
    return profile


def _sample_profile_at(profile: list[tuple[float, float]], t_query: float) -> float:
    if not profile:
        raise RuntimeError("empty profile")
    best = min(profile, key=lambda item: abs(item[0] - t_query))
    return best[1]


def _estimate_vertex_gradient(
    mesh: CliffCutMesh,
    heights: list[float],
    vertex: int,
) -> tuple[float, float]:
    xi, yi = mesh.node_xy[vertex]
    gx = 0.0
    gy = 0.0
    weight_sum = 0.0
    for neighbor in mesh.adjacency[vertex]:
        xj, yj = mesh.node_xy[neighbor]
        dx = xj - xi
        dy = yj - yi
        length_sq = dx * dx + dy * dy
        if length_sq <= 1e-18:
            continue
        du = heights[neighbor] - heights[vertex]
        gx += du * dx / length_sq
        gy += du * dy / length_sq
        weight_sum += 1.0
    if weight_sum <= 0.0:
        return 0.0, 0.0
    return gx / weight_sum, gy / weight_sum


def _free_boundary_tangent_normal_ratio(
    mesh: CliffCutMesh,
    heights: list[float],
) -> float:
    """Max |grad·t| / |grad·n| over boundary edges (natural BC should not force grad ⊥ boundary)."""
    boundary_vertices, outward = _boundary_outward_normals(mesh)
    best_ratio = 0.0
    for vertex in boundary_vertices:
        gx, gy = _estimate_vertex_gradient(mesh, heights, vertex)
        grad_mag = math.hypot(gx, gy)
        if grad_mag <= 1e-9:
            continue
        for nx, ny in outward.get(vertex, ()):
            tx, ty = -ny, nx
            normal = abs(gx * nx + gy * ny) / grad_mag
            tangent = abs(gx * tx + gy * ty) / grad_mag
            if normal > 1e-6:
                best_ratio = max(best_ratio, tangent / normal)
    return best_ratio


def _nearest_mesh_height(
    mesh: CliffCutMesh,
    heights: list[float],
    wx: float,
    wy: float,
) -> float:
    best_dist = float("inf")
    best_height = 0.0
    for nid, (x, y) in enumerate(mesh.node_xy):
        dist = math.hypot(x - wx, y - wy)
        if dist < best_dist:
            best_dist = dist
            best_height = heights[nid]
    return best_height


def _spmv(laplacian: list[list[tuple[int, float]]], x: list[float]) -> list[float]:
    y = [0.0] * len(x)
    for row_idx, row in enumerate(laplacian):
        s = 0.0
        for col, val in row:
            s += val * x[col]
        y[row_idx] = s
    return y


def _laplacian_to_coo(
    laplacian: list[list[tuple[int, float]]],
) -> tuple[list[int], list[int], list[float], int]:
    rows: list[int] = []
    cols: list[int] = []
    vals: list[float] = []
    for row_idx, row in enumerate(laplacian):
        for col_idx, val in row:
            rows.append(row_idx)
            cols.append(col_idx)
            vals.append(val)
    return rows, cols, vals, len(laplacian)


def _spmv_coo(
    rows: list[int],
    cols: list[int],
    vals: list[float],
    n: int,
    x: list[float],
) -> list[float]:
    y = [0.0] * n
    for r, c, v in zip(rows, cols, vals, strict=True):
        y[r] += v * x[c]
    return y


def _apply_bilaplacian(
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    x: list[float],
) -> list[float]:
    lx = _spmv(laplacian, x)
    mlx = [lx[i] * mass_inv[i] for i in range(len(x))]
    return _spmv(laplacian, mlx)


def _apply_bilaplacian_coo(
    rows: list[int],
    cols: list[int],
    vals: list[float],
    n: int,
    mass_inv: list[float],
    x: list[float],
) -> list[float]:
    tmp = _spmv_coo(rows, cols, vals, n, x)
    mlx = [tmp[i] * mass_inv[i] for i in range(n)]
    return _spmv_coo(rows, cols, vals, n, mlx)


def _bilaplacian_diagonal(
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    free_indices: list[int],
) -> list[float]:
    """Diagonal of K = L M^-1 L: K_ii = sum_j L_ij M_jj^-1 L_ji."""
    lap_dict = [dict(row) for row in laplacian]
    full_diag = [0.0] * len(laplacian)
    for i, row in enumerate(laplacian):
        s = 0.0
        for j, lij in row:
            s += lij * mass_inv[j] * lap_dict[j].get(i, 0.0)
        full_diag[i] = max(abs(s), 1e-18)
    return [full_diag[node] for node in free_indices]


def _laplacian_nnz(laplacian: list[list[tuple[int, float]]]) -> int:
    return sum(len(row) for row in laplacian)


def _group_free_by_component(
    free_indices: list[int],
    component_ids: list[int],
) -> dict[int, list[int]]:
    groups: dict[int, list[int]] = {}
    for node in free_indices:
        cid = component_ids[node]
        groups.setdefault(cid, []).append(node)
    return groups


def _solve_constrained_bilaplacian(
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    free_indices: list[int],
    pinned_values: dict[int, float],
    *,
    max_iterations: int = 5000,
    tolerance: float = 1e-8,
    prefer_numpy: bool = True,
    direct_limit: int = 2500,
    component_ids: list[int] | None = None,
) -> tuple[list[float], int, float, int]:
    """Solve K z = 0 on free DOFs with pinned values fixed. Returns (z, iters, residual, blocks)."""
    n = len(laplacian)
    z = [pinned_values.get(i, 0.0) for i in range(n)]
    m = len(free_indices)
    if m == 0:
        return z, 0, 0.0, 0

    rows, cols, vals, _n = _laplacian_to_coo(laplacian)

    def matvec_free(v: list[float]) -> list[float]:
        z_full = z[:]
        for node, val in zip(free_indices, v, strict=True):
            z_full[node] = val
        kz = _apply_bilaplacian_coo(rows, cols, vals, n, mass_inv, z_full)
        return [kz[node] for node in free_indices]

    kz = _apply_bilaplacian_coo(rows, cols, vals, n, mass_inv, z)
    b = [-kz[node] for node in free_indices]
    b_norm = math.sqrt(sum(bi * bi for bi in b))
    rel_stop = max(b_norm * tolerance, tolerance * 1e-6)

    if m <= direct_limit:
        if prefer_numpy and _NUMPY_AVAILABLE:
            assert np is not None
            kff = np.zeros((m, m), dtype=np.float64)
            for j in range(m):
                ej = np.zeros(m, dtype=np.float64)
                ej[j] = 1.0
                kff[:, j] = np.array(matvec_free(ej.tolist()), dtype=np.float64)
            x = np.linalg.solve(kff, np.array(b, dtype=np.float64))
            residual = float(np.linalg.norm(kff @ x - np.array(b, dtype=np.float64)))
            for node, val in zip(free_indices, x.tolist(), strict=True):
                z[node] = val
            return z, 0, residual, 1
        kff_cols: list[list[float]] = []
        for j in range(m):
            ej = [0.0] * m
            ej[j] = 1.0
            kff_cols.append(matvec_free(ej))
        x = _gaussian_solve(kff_cols, b)
        residual = math.sqrt(
            sum(
                (
                    sum(kff_cols[j][i] * x[j] for j in range(m)) - b[i]
                )
                ** 2
                for i in range(m)
            )
        )
        for node, val in zip(free_indices, x, strict=True):
            z[node] = val
        return z, 0, residual, 1

    free_groups: list[list[int]]
    if component_ids is not None:
        grouped = _group_free_by_component(free_indices, component_ids)
        free_groups = list(grouped.values())
    else:
        free_groups = [free_indices]

    total_iters = 0
    max_residual = 0.0
    for comp_free in free_groups:
        comp_z, comp_iters, comp_res = _solve_constrained_bilaplacian_block(
            rows,
            cols,
            vals,
            n,
            mass_inv,
            laplacian,
            comp_free,
            z,
            max_iterations=max_iterations,
            tolerance=tolerance,
            prefer_numpy=prefer_numpy,
        )
        for node, val in comp_z.items():
            z[node] = val
        total_iters += comp_iters
        max_residual = max(max_residual, comp_res)

    return z, total_iters, max_residual, len(free_groups)


def _solve_constrained_bilaplacian_block(
    rows: list[int],
    cols: list[int],
    vals: list[float],
    n: int,
    mass_inv: list[float],
    laplacian: list[list[tuple[int, float]]],
    free_indices: list[int],
    z_pinned: list[float],
    *,
    max_iterations: int,
    tolerance: float,
    prefer_numpy: bool,
) -> tuple[dict[int, float], int, float]:
    z = z_pinned[:]
    kz = _apply_bilaplacian_coo(rows, cols, vals, n, mass_inv, z)
    b = [-kz[node] for node in free_indices]
    b_norm = math.sqrt(sum(bi * bi for bi in b))
    rel_stop = max(b_norm * tolerance, tolerance * 1e-6)

    diag = _bilaplacian_diagonal(laplacian, mass_inv, free_indices)
    inv_diag = [1.0 / d for d in diag]

    if prefer_numpy and _NUMPY_AVAILABLE:
        z_out, iterations, residual = _pcg_numpy_fast(
            rows,
            cols,
            vals,
            n,
            mass_inv,
            free_indices,
            z,
            b,
            inv_diag,
            max_iterations,
            rel_stop,
        )
        return {node: z_out[node] for node in free_indices}, iterations, residual
    return _pcg_pure_python_block(
        rows,
        cols,
        vals,
        n,
        mass_inv,
        free_indices,
        z,
        b,
        inv_diag,
        max_iterations,
        rel_stop,
    )


def _pcg_pure_python_block(
    rows: list[int],
    cols: list[int],
    vals: list[float],
    n: int,
    mass_inv: list[float],
    free_indices: list[int],
    z_pinned: list[float],
    b: list[float],
    inv_diag: list[float],
    max_iterations: int,
    tolerance: float,
) -> tuple[dict[int, float], int, float]:
    z = z_pinned[:]

    def matvec(v: list[float]) -> list[float]:
        z_full = z[:]
        for node, val in zip(free_indices, v, strict=True):
            z_full[node] = val
        kz = _apply_bilaplacian_coo(rows, cols, vals, n, mass_inv, z_full)
        return [kz[node] for node in free_indices]

    z_out, iterations, residual = _pcg_pure_python(
        matvec, b, inv_diag, free_indices, z, max_iterations, tolerance
    )
    return {node: z_out[node] for node in free_indices}, iterations, residual


def _collect_opposite_cliff_rim_pairs(
    mesh: CliffCutMesh,
    model: Any,
) -> list[tuple[int, int]]:
    """Node pairs on opposite cliff sides at the same world pos_key."""
    from eom_terrain_math_core import _build_cliff_neighbor_pairs

    cliff_pairs = _build_cliff_neighbor_pairs(model.cliff_edges)
    pk_by_tile: dict[tuple[int, int], dict[Any, int]] = {}
    for key, nid in mesh.sample_lookup.items():
        if len(key) != 3 or not isinstance(key[0], tuple):
            continue
        pk, q, r = key
        pk_by_tile.setdefault((q, r), {})[pk] = nid

    pairs: list[tuple[int, int]] = []
    seen: set[tuple[int, int]] = set()
    for edge in model.cliff_edges:
        ta, tb = edge.tile_a, edge.tile_b
        if frozenset((ta, tb)) not in cliff_pairs:
            continue
        rim_a = pk_by_tile.get(ta, {})
        rim_b = pk_by_tile.get(tb, {})
        for pk, nid_a in rim_a.items():
            nid_b = rim_b.get(pk)
            if nid_b is None or nid_a == nid_b:
                continue
            pair = (min(nid_a, nid_b), max(nid_a, nid_b))
            if pair not in seen:
                seen.add(pair)
                pairs.append(pair)
    return pairs


def _verify_no_stencil_across_cliff(
    laplacian: list[list[tuple[int, float]]],
    mesh: CliffCutMesh,
    model: Any | None,
) -> tuple[bool, int]:
    """True when no Laplacian off-diagonal links opposite cliff-rim nodes."""
    if model is None:
        return True, 0
    pairs = _collect_opposite_cliff_rim_pairs(mesh, model)
    if not pairs:
        return True, 0
    lap_lookup: dict[tuple[int, int], float] = {}
    for i, row in enumerate(laplacian):
        for j, val in row:
            if i != j and abs(val) > 1e-18:
                lap_lookup[(i, j)] = val
    cross_count = 0
    for a, b in pairs:
        if (a, b) in lap_lookup or (b, a) in lap_lookup:
            cross_count += 1
    return cross_count == 0, cross_count


def _representative_cliff_rim_gap(
    mesh: CliffCutMesh,
    heights: list[float],
    tile_a: tuple[int, int] = (4, 0),
    tile_b: tuple[int, int] = (5, 0),
) -> float | None:
    pk_nodes_a: dict[Any, int] = {}
    pk_nodes_b: dict[Any, int] = {}
    for key, nid in mesh.sample_lookup.items():
        if len(key) != 3 or not isinstance(key[0], tuple):
            continue
        pk, q, r = key
        if (q, r) == tile_a:
            pk_nodes_a[pk] = nid
        elif (q, r) == tile_b:
            pk_nodes_b[pk] = nid
    best_gap: float | None = None
    for pk, nid_a in pk_nodes_a.items():
        nid_b = pk_nodes_b.get(pk)
        if nid_b is None or nid_a == nid_b:
            continue
        gap = abs(heights[nid_a] - heights[nid_b])
        if best_gap is None or gap > best_gap:
            best_gap = gap
    return best_gap


def _tiles_on_cliff_side(
    start: tuple[int, int],
    cliff_edge: tuple[tuple[int, int], tuple[int, int]],
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
) -> set[tuple[int, int]]:
    """Tiles reachable from start without crossing the given cliff edge."""
    blocked = frozenset(cliff_edge)
    visited = {start}
    queue = [start]
    head = 0
    while head < len(queue):
        current = queue[head]
        head += 1
        for neighbor in smooth_adjacency.get(current, ()):
            if frozenset((current, neighbor)) == blocked:
                continue
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    return visited


def _model_with_tile_subset(model: Any, keep: set[tuple[int, int]]) -> Any:
    from eom_terrain_math_core import build_terrain_model

    tiles = [
        {"q": q, "r": r, "elevation": model.map.tiles[(q, r)]}
        for q, r in sorted(keep)
        if (q, r) in model.map.tiles
    ]
    payload = {
        "id": f"{model.map.map_id}_subset",
        "orientation": model.map.orientation,
        "elevation_step": model.map.elevation_step,
        "edge_rule": {"cliff_if_abs_delta_greater_than": model.map.cliff_threshold},
        "tiles": tiles,
    }
    return build_terrain_model(payload)


def _delete_opposite_side_invariance(
    model: Any,
    baseline: Any,
    mesh: CliffCutMesh,
    heights: list[float],
    *,
    cliff_a: tuple[int, int] = (4, 0),
    cliff_b: tuple[int, int] = (5, 0),
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
    prefer_numpy: bool,
    direct_limit: int = DIRECT_SOLVE_MAX_FREE_DOFS,
) -> float | None:
    """Max |delta z| on cliff_a samples after removing all tiles on cliff_b side."""
    if cliff_a not in model.map.tiles or cliff_b not in model.map.tiles:
        return None
    smooth_adjacency = _build_smooth_adjacency(model.map, model.smooth_edges)
    side_b = _tiles_on_cliff_side(cliff_b, (cliff_a, cliff_b), smooth_adjacency)
    if cliff_a in side_b:
        return None
    keep = set(model.map.tiles.keys()) - side_b
    if cliff_a not in keep:
        return None
    reduced = _model_with_tile_subset(model, keep)
    reduced_mesh = build_cliff_cut_mesh(reduced, baseline, subdiv=subdiv, radius=radius)
    reduced_heights, _ = solve_fem_thin_plate(
        reduced_mesh,
        prefer_numpy=prefer_numpy,
        model=reduced,
        baseline=None,
        skip_extended_diagnostics=True,
        direct_limit=direct_limit,
    )
    max_delta = 0.0
    found = False
    for key, nid in mesh.sample_lookup.items():
        if len(key) == 3 and key[1:] == cliff_a:
            reduced_nid = reduced_mesh.sample_lookup.get(key)
            if reduced_nid is None:
                continue
            max_delta = max(max_delta, abs(heights[nid] - reduced_heights[reduced_nid]))
            found = True
    return max_delta if found else None


def _pcg_numpy_fast(
    rows: list[int],
    cols: list[int],
    vals: list[float],
    n: int,
    mass_inv: list[float],
    free_indices: list[int],
    z_pinned: list[float],
    b: list[float],
    inv_diag: list[float],
    max_iterations: int,
    tolerance: float,
) -> tuple[list[float], int, float]:
    """Preconditioned CG on reduced K_ff with K = L M^-1 L."""
    assert np is not None
    free_idx = np.array(free_indices, dtype=np.int64)
    row_arr = np.array(rows, dtype=np.int64)
    col_arr = np.array(cols, dtype=np.int64)
    val_arr = np.array(vals, dtype=np.float64)
    mass_arr = np.array(mass_inv, dtype=np.float64)
    z = np.array(z_pinned, dtype=np.float64)
    b_arr = np.array(b, dtype=np.float64)
    inv_d = np.array(inv_diag, dtype=np.float64)
    m = len(free_indices)

    def spmv(x: np.ndarray) -> np.ndarray:
        y = np.zeros(n, dtype=np.float64)
        np.add.at(y, row_arr, val_arr * x[col_arr])
        return y

    def matvec(v: np.ndarray) -> np.ndarray:
        z[free_idx] = v
        lx = spmv(z)
        mlx = mass_arr * lx
        kz = spmv(mlx)
        return kz[free_idx]

    x = np.zeros(m, dtype=np.float64)
    r = b_arr - matvec(x)
    z_prec = inv_d * r
    p = z_prec.copy()
    rs_old = float(r @ z_prec)
    if rs_old <= tolerance * tolerance:
        z[free_idx] = x
        return z.tolist(), 0, math.sqrt(float(r @ r))

    iterations = 0
    final_residual = math.sqrt(float(r @ r))
    for _ in range(max_iterations):
        iterations += 1
        Ap = matvec(p)
        denom = float(p @ Ap)
        if abs(denom) < 1e-30:
            break
        alpha = rs_old / denom
        x = x + alpha * p
        r = r - alpha * Ap
        final_residual = math.sqrt(float(r @ r))
        if iterations % 500 == 0:
            print(f"[fem_thin_plate] CG iter {iterations} residual {final_residual:.3e}")
        if final_residual <= tolerance:
            break
        z_prec = inv_d * r
        rs_new = float(r @ z_prec)
        beta = rs_new / rs_old if rs_old > 0.0 else 0.0
        p = z_prec + beta * p
        rs_old = rs_new

    z[free_idx] = x
    return z.tolist(), iterations, final_residual


def _gaussian_solve(cols: list[list[float]], b: list[float]) -> list[float]:
    m = len(b)
    aug = [[cols[j][i] for j in range(m)] + [b[i]] for i in range(m)]
    for col in range(m):
        pivot = col
        for row in range(col + 1, m):
            if abs(aug[row][col]) > abs(aug[pivot][col]):
                pivot = row
        if abs(aug[pivot][col]) < 1e-14:
            continue
        aug[col], aug[pivot] = aug[pivot], aug[col]
        div = aug[col][col]
        for j in range(col, m + 1):
            aug[col][j] /= div
        for row in range(m):
            if row == col:
                continue
            factor = aug[row][col]
            if factor == 0.0:
                continue
            for j in range(col, m + 1):
                aug[row][j] -= factor * aug[col][j]
    return [aug[i][m] for i in range(m)]


def _pcg_pure_python(
    matvec: Any,
    b: list[float],
    inv_diag: list[float],
    free_indices: list[int],
    z: list[float],
    max_iterations: int,
    tolerance: float,
) -> tuple[list[float], int, float]:
    m = len(b)
    x = [0.0] * m
    r = [b[i] - matvec(x)[i] for i in range(m)]
    z_prec = [inv_diag[i] * r[i] for i in range(m)]
    p = z_prec[:]
    rs_old = sum(r[i] * z_prec[i] for i in range(m))
    if rs_old <= tolerance * tolerance:
        for node, val in zip(free_indices, x, strict=True):
            z[node] = val
        return z, 0, math.sqrt(rs_old)

    iterations = 0
    final_residual = math.sqrt(sum(ri * ri for ri in r))
    for _ in range(max_iterations):
        iterations += 1
        Ap = matvec(p)
        denom = sum(p[i] * Ap[i] for i in range(m))
        if abs(denom) < 1e-30:
            break
        alpha = rs_old / denom
        x = [x[i] + alpha * p[i] for i in range(m)]
        r = [r[i] - alpha * Ap[i] for i in range(m)]
        final_residual = math.sqrt(sum(ri * ri for ri in r))
        if final_residual <= tolerance:
            break
        z_prec = [inv_diag[i] * r[i] for i in range(m)]
        rs_new = sum(r[i] * z_prec[i] for i in range(m))
        beta = rs_new / rs_old if rs_old > 0.0 else 0.0
        p = [z_prec[i] + beta * p[i] for i in range(m)]
        rs_old = rs_new

    for node, val in zip(free_indices, x, strict=True):
        z[node] = val
    return z, iterations, final_residual


def _pcg_numpy(
    matvec: Any,
    b: list[float],
    inv_diag: list[float],
    free_indices: list[int],
    z: list[float],
    max_iterations: int,
    tolerance: float,
) -> tuple[list[float], int, float]:
    assert np is not None
    m = len(b)
    b_arr = np.array(b, dtype=np.float64)
    inv_d = np.array(inv_diag, dtype=np.float64)
    x = np.zeros(m, dtype=np.float64)
    r = b_arr - np.array(matvec(x.tolist()), dtype=np.float64)
    z_prec = inv_d * r
    p = z_prec.copy()
    rs_old = float(r @ z_prec)
    if rs_old <= tolerance * tolerance:
        for node, val in zip(free_indices, x.tolist(), strict=True):
            z[node] = val
        return z, 0, math.sqrt(float(r @ r))

    iterations = 0
    final_residual = math.sqrt(float(r @ r))
    for _ in range(max_iterations):
        iterations += 1
        Ap = np.array(matvec(p.tolist()), dtype=np.float64)
        denom = float(p @ Ap)
        if abs(denom) < 1e-30:
            break
        alpha = rs_old / denom
        x = x + alpha * p
        r = r - alpha * Ap
        final_residual = math.sqrt(float(r @ r))
        if final_residual <= tolerance:
            break
        z_prec = inv_d * r
        rs_new = float(r @ z_prec)
        beta = rs_new / rs_old if rs_old > 0.0 else 0.0
        p = z_prec + beta * p
        rs_old = rs_new

    for node, val in zip(free_indices, x.tolist(), strict=True):
        z[node] = val
    return z, iterations, final_residual


def _solve_cg_pure_python(
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    free_indices: list[int],
    pinned_values: dict[int, float],
    *,
    max_iterations: int = 5000,
    tolerance: float = 1e-8,
) -> tuple[list[float], int, float]:
    n = len(laplacian)
    z = [pinned_values.get(i, 0.0) for i in range(n)]
    free_set = set(free_indices)
    index_map = {node: idx for idx, node in enumerate(free_indices)}
    m = len(free_indices)

    def matvec(v: list[float]) -> list[float]:
        z_full = z[:]
        for node, val in zip(free_indices, v, strict=True):
            z_full[node] = val
        kz = _apply_bilaplacian(laplacian, mass_inv, z_full)
        return [kz[node] for node in free_indices]

    b = [0.0] * m
    z_full = z[:]
    kz = _apply_bilaplacian(laplacian, mass_inv, z_full)
    for node in free_indices:
        b[index_map[node]] = -kz[node]

    x = [0.0] * m
    r = [b[i] - matvec(x)[i] for i in range(m)]
    p = r[:]
    rs_old = sum(ri * ri for ri in r)
    if rs_old <= tolerance * tolerance:
        for node, val in zip(free_indices, x, strict=True):
            z[node] = val
        return z, 0, math.sqrt(rs_old)

    iterations = 0
    final_residual = math.sqrt(rs_old)
    for _ in range(max_iterations):
        iterations += 1
        Ap = matvec(p)
        denom = sum(p[i] * Ap[i] for i in range(m))
        if abs(denom) < 1e-30:
            break
        alpha = rs_old / denom
        x = [x[i] + alpha * p[i] for i in range(m)]
        r = [r[i] - alpha * Ap[i] for i in range(m)]
        rs_new = sum(ri * ri for ri in r)
        final_residual = math.sqrt(rs_new)
        if final_residual <= tolerance:
            break
        beta = rs_new / rs_old if rs_old > 0.0 else 0.0
        p = [r[i] + beta * p[i] for i in range(m)]
        rs_old = rs_new

    for node, val in zip(free_indices, x, strict=True):
        z[node] = val
    return z, iterations, final_residual


def _solve_cg_numpy(
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    free_indices: list[int],
    pinned_values: dict[int, float],
    *,
    max_iterations: int = 5000,
    tolerance: float = 1e-8,
) -> tuple[list[float], int, float]:
    assert np is not None
    n = len(laplacian)
    z = np.array([pinned_values.get(i, 0.0) for i in range(n)], dtype=np.float64)
    free_idx = np.array(free_indices, dtype=np.int64)
    m = len(free_indices)

    def matvec(v: np.ndarray) -> np.ndarray:
        z_full = z.copy()
        z_full[free_idx] = v
        tmp = _spmv(laplacian, z_full.tolist())
        tmp = np.array(tmp, dtype=np.float64) * np.array(mass_inv, dtype=np.float64)
        kz = _spmv(laplacian, tmp.tolist())
        return np.array([kz[i] for i in free_indices], dtype=np.float64)

    z_full_list = z.tolist()
    kz = _apply_bilaplacian(laplacian, mass_inv, z_full_list)
    b = -np.array([kz[i] for i in free_indices], dtype=np.float64)

    x = np.zeros(m, dtype=np.float64)
    r = b - matvec(x)
    p = r.copy()
    rs_old = float(r @ r)
    if rs_old <= tolerance * tolerance:
        z[free_idx] = x
        return z.tolist(), 0, math.sqrt(rs_old)

    iterations = 0
    final_residual = math.sqrt(rs_old)
    for _ in range(max_iterations):
        iterations += 1
        Ap = matvec(p)
        denom = float(p @ Ap)
        if abs(denom) < 1e-30:
            break
        alpha = rs_old / denom
        x = x + alpha * p
        r = r - alpha * Ap
        rs_new = float(r @ r)
        final_residual = math.sqrt(rs_new)
        if final_residual <= tolerance:
            break
        beta = rs_new / rs_old if rs_old > 0.0 else 0.0
        p = r + beta * p
        rs_old = rs_new

    z[free_idx] = x
    return z.tolist(), iterations, final_residual


def solve_fem_thin_plate(
    mesh: CliffCutMesh,
    *,
    max_iterations: int = 5000,
    tolerance: float = 1e-8,
    prefer_numpy: bool = True,
    model: Any | None = None,
    baseline: Any | None = None,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
    skip_extended_diagnostics: bool = False,
    direct_limit: int = DIRECT_SOLVE_MAX_FREE_DOFS,
    energy_method: str = "mixed_fem",
    clamp_boundary: bool = True,
) -> tuple[list[float], FemThinPlateSolveReport]:
    del max_iterations, tolerance
    if energy_method == "mixed_fem":
        energy = assemble_hessian_energy_mixed_fem(mesh, clamp_boundary=clamp_boundary)
    elif energy_method == "quadratic_fit":
        energy = assemble_hessian_energy_matrix(mesh)
    else:
        raise ValueError(
            f"unknown energy_method={energy_method!r}; expected 'mixed_fem' or 'quadratic_fit'"
        )
    nnz = _energy_matrix_nnz(energy)

    pinned = mesh.pinned
    free_indices = [i for i in range(mesh.node_count) if i not in pinned]

    z_init = [pinned.get(i, 0.0) for i in range(mesh.node_count)]
    kz_init = _spmv_energy(energy, z_init)
    b_norm = max(
        math.sqrt(sum(kz_init[node] * kz_init[node] for node in free_indices)),
        1e-18,
    )

    heights, solve_iters, residual = _solve_constrained_hessian_direct(
        energy,
        free_indices,
        pinned,
        prefer_numpy=prefer_numpy,
        direct_limit=direct_limit,
    )
    relative_residual = residual / b_norm

    max_center_err = max(
        (abs(heights[node] - pin_z) for node, pin_z in pinned.items()),
        default=0.0,
    )
    input_z = list(pinned.values())
    input_min = min(input_z) if input_z else 0.0
    input_max = max(input_z) if input_z else 0.0
    z_min = min(heights) if heights else 0.0
    z_max = max(heights) if heights else 0.0
    overshoot = max(
        max(0.0, z_max - input_max),
        max(0.0, input_min - z_min),
    )

    const_ok, const_err, planar_ok, planar_err = _energy_affine_precision_tests(mesh, energy)

    cliff_ok, decouple_delta = _cliff_cut_diagnostics(mesh, prefer_numpy=prefer_numpy)

    mesh_connected = mesh.component_count == 1
    no_stencil, cross_stencil = _verify_no_energy_across_cliff(energy, mesh, model)
    rim_gap = _representative_cliff_rim_gap(mesh, heights) if model is not None else None
    delete_delta: float | None = None
    if (
        not skip_extended_diagnostics
        and model is not None
        and baseline is not None
    ):
        delete_delta = _delete_opposite_side_invariance(
            model,
            baseline,
            mesh,
            heights,
            subdiv=subdiv,
            radius=radius,
            prefer_numpy=prefer_numpy,
            direct_limit=direct_limit,
        )

    warnings: list[str] = []
    if mesh_connected and model is not None and model.cliff_edges:
        warnings.append(
            "cut mesh is one connected component via smooth detours (allowed); "
            "cliff independence is verified by energy stencil audit, not component count"
        )
    if not no_stencil:
        warnings.append(
            f"Hessian energy has {cross_stencil} coupling edge(s) across opposite cliff rims"
        )
    if overshoot > 0.25 * max(input_max - input_min, 1e-9):
        warnings.append(
            f"max overshoot {overshoot:.4f} exceeds 25% of input elevation range"
        )
    if max_center_err > 1e-6:
        warnings.append(f"center interpolation error {max_center_err:.3e} is large")
    if relative_residual > 1e-8:
        warnings.append(f"direct solve residual {relative_residual:.3e} is not near zero")

    report = FemThinPlateSolveReport(
        node_count=mesh.node_count,
        triangle_count=len(mesh.triangles),
        component_count=mesh.component_count,
        pinned_center_count=len(pinned),
        free_dof_count=len(free_indices),
        laplacian_nnz=nnz,
        cg_iterations=solve_iters,
        final_residual=residual,
        relative_residual=relative_residual,
        cg_solve_blocks=1,
        mesh_connected_via_smooth_detour=mesh_connected,
        no_stencil_across_cliff=no_stencil,
        cross_cliff_stencil_count=cross_stencil,
        representative_cliff_rim_gap=rim_gap,
        delete_opposite_side_max_delta=delete_delta,
        max_center_interpolation_error=max_center_err,
        affine_constant_ok=const_ok,
        affine_constant_max_error=const_err,
        affine_planar_ok=planar_ok,
        affine_planar_max_error=planar_err,
        z_min=z_min,
        z_max=z_max,
        input_z_min=input_min,
        input_z_max=input_max,
        max_overshoot=overshoot,
        cliff_cut_two_tile_ok=cliff_ok,
        cross_cliff_decoupling_delta=decouple_delta,
        warnings=warnings,
    )
    return heights, report


def _affine_precision_tests(
    mesh: CliffCutMesh,
    laplacian: list[list[tuple[int, float]]],
    mass_inv: list[float],
    *,
    prefer_numpy: bool,
) -> tuple[bool, float, bool, float]:
    if mesh.node_count < 3:
        return True, 0.0, True, 0.0

    rows, cols, vals, n = _laplacian_to_coo(laplacian)
    z_const = [2.5] * n
    k_const = _apply_bilaplacian_coo(rows, cols, vals, n, mass_inv, z_const)
    const_err = max(abs(v) for v in k_const)

    z_planar = [0.3 * x - 0.2 * y + 1.0 for x, y in mesh.node_xy]
    l_planar = _spmv_coo(rows, cols, vals, n, z_planar)
    planar_err = max(abs(v) for v in l_planar)

    return const_err < 1e-9, const_err, planar_err < 0.1, planar_err


def _cliff_cut_diagnostics(
    mesh: CliffCutMesh,
    *,
    prefer_numpy: bool,
) -> tuple[bool, float | None]:
    from eom_terrain_math_core import build_terrain_model

    json_cliff = """
    {
      "id": "ts04_cliff_two",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":5}
      ]
    }
    """
    model = build_terrain_model(json_cliff)
    baseline = _minimal_baseline_stub()
    cliff_mesh = build_cliff_cut_mesh(model, baseline, subdiv=4)
    if cliff_mesh.component_count < 2:
        return False, None

    lookup_00 = cliff_mesh.sample_lookup.get(("center", 0, 0))
    lookup_10 = cliff_mesh.sample_lookup.get(("center", 1, 0))
    if lookup_00 is None or lookup_10 is None:
        return False, None

    shared_distinct = False
    for key, nid in cliff_mesh.sample_lookup.items():
        if key[0] != "pos":
            continue
        pk, cluster = key[1], key[2]
        if (0, 0) in cluster and len(cluster) == 1:
            for key2, nid2 in cliff_mesh.sample_lookup.items():
                if key2[0] != "pos":
                    continue
                pk2, cluster2 = key2[1], key2[2]
                if pk2 == pk and (1, 0) in cluster2 and len(cluster2) == 1 and nid != nid2:
                    shared_distinct = True
                    break
        if shared_distinct:
            break

    if not shared_distinct:
        return False, None

    energy = assemble_hessian_energy_mixed_fem(cliff_mesh, clamp_boundary=True)
    pins_a = {lookup_00: 0.0, lookup_10: 2.0}
    free = [i for i in range(cliff_mesh.node_count) if i not in pins_a]
    z_a, _, _ = _solve_constrained_hessian_direct(
        energy, free, pins_a, prefer_numpy=prefer_numpy, direct_limit=DIRECT_SOLVE_MAX_FREE_DOFS
    )
    h10_a = z_a[lookup_10]

    pins_b = {lookup_00: 1.0, lookup_10: 2.0}
    z_b, _, _ = _solve_constrained_hessian_direct(
        energy, free, pins_b, prefer_numpy=prefer_numpy, direct_limit=DIRECT_SOLVE_MAX_FREE_DOFS
    )
    h10_b = z_b[lookup_10]

    return True, abs(h10_b - h10_a)


class FemThinPlateTerrainSolver:
    """Stein Route B mixed-FEM squared-Hessian on cliff-cut mesh; backend enum attached in eom_terrain_solver."""

    backend = None  # type: ignore

    def __init__(
        self,
        *,
        max_iterations: int = 8000,
        tolerance: float = 1e-4,
    ) -> None:
        self._max_iterations = max_iterations
        self._tolerance = tolerance
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS
        self._mesh: CliffCutMesh | None = None
        self._heights: list[float] | None = None
        self._report: FemThinPlateSolveReport | None = None

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
                "FemThinPlateTerrainSolver.prepare requires baseline module "
                "(sector_barycentric_xy, axial_to_world_xy)"
            )
        self._model = model
        self._radius = radius
        print("[fem_thin_plate] building cliff-cut mesh...")
        self._mesh = build_cliff_cut_mesh(
            model,
            baseline,
            subdiv=subdiv,
            radius=radius,
        )
        print(
            f"[fem_thin_plate] mesh: nodes={self._mesh.node_count} "
            f"triangles={len(self._mesh.triangles)} "
            f"components={self._mesh.component_count}"
            + (
                " (connected via smooth detours — expected on canonical map)"
                if self._mesh.component_count == 1
                else ""
            )
        )
        print("[fem_thin_plate] solving Hessian energy system (direct)...")
        self._heights, self._report = solve_fem_thin_plate(
            self._mesh,
            max_iterations=self._max_iterations,
            tolerance=self._tolerance,
            prefer_numpy=_NUMPY_AVAILABLE,
            model=model,
            baseline=baseline,
            subdiv=subdiv,
            radius=radius,
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
        assert self._mesh is not None
        assert self._heights is not None

        pk = pos_key(wx, wy)
        cx, cy = handdrawn_center_world_xy(q, r, self._radius)
        if abs(wx - cx) < 1e-9 and abs(wy - cy) < 1e-9:
            node = self._mesh.sample_lookup.get(("center", q, r))
        else:
            node = self._mesh.sample_lookup.get((pk, q, r))

        if node is None:
            raise RuntimeError(
                "fem_thin_plate sample not on cliff-cut mesh: "
                f"tile=({q}, {r}) world=({wx:.6f}, {wy:.6f}) pos_key={pk!r}"
            )
        return self._heights[node]

    @property
    def stats(self) -> dict[str, Any] | None:
        if self._report is None:
            return None
        return self._report.as_dict()


def _minimal_baseline_stub(radius: float = DEFAULT_HEX_RADIUS) -> Any:
    from eom_terrain_math_core import corner_xy_local

    class _Stub:
        HEX_RADIUS = radius

        @staticmethod
        def axial_to_world_xy(q_b: int, r_b: int, rad: float) -> tuple[float, float]:
            x = rad * math.sqrt(3.0) * (float(q_b) + float(r_b) * 0.5)
            y = rad * 1.5 * float(r_b)
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


def _quadratic_form_energy(
    energy: list[list[tuple[int, float]]],
    values: list[float],
) -> float:
    kv = _spmv_energy(energy, values)
    return sum(v * kv_i for v, kv_i in zip(values, kv, strict=True))


def _assemble_laplacian_squared_natural_bc(
    mesh: CliffCutMesh,
    *,
    interior_only_mass: bool = True,
) -> list[list[tuple[int, float]]]:
    """Stein Eq. (23) analog: L(i,a)^T M(i,i)^{-1} L(i,a) when interior_only_mass."""
    laplacian, mass = assemble_cotan_laplacian_and_mass(mesh)
    boundary = _boundary_vertex_set(mesh)
    n = mesh.node_count
    rows: list[dict[int, float]] = [dict() for _ in range(n)]
    for vertex in range(n):
        if interior_only_mass and vertex in boundary:
            continue
        mi = 1.0 / mass[vertex]
        row_l = dict(laplacian[vertex])
        for col_j, l_ij in row_l.items():
            for col_k, l_ik in row_l.items():
                val = mi * l_ij * l_ik
                if abs(val) < 1e-18:
                    continue
                rows[col_j][col_k] = rows[col_j].get(col_k, 0.0) + val
    return [sorted(row.items()) for row in rows]


def _harmonic_extension_with_boundary_values(
    mesh: CliffCutMesh,
    boundary_values: dict[int, float],
    *,
    prefer_numpy: bool = False,
) -> list[float]:
    """Discrete harmonic field: min h^T L h with Dirichlet data on boundary vertices."""
    laplacian, _mass = assemble_cotan_laplacian_and_mass(mesh)
    free = [i for i in range(mesh.node_count) if i not in boundary_values]
    heights, _, _ = _solve_constrained_hessian_direct(
        laplacian,
        free,
        boundary_values,
        prefer_numpy=prefer_numpy,
    )
    return heights


def _run_route_b_diagnostics(*, subdiv: int = 4, time_limit_s: float = 180.0) -> None:
    """Print-only Route B stop-point diagnostics (TS-04d); no pass/fail assertions."""
    import sys
    import time

    from eom_terrain_math_core import build_terrain_model, canonical_center_world_z, handdrawn_center_world_xy

    def _timed(label: str, started: float) -> float:
        elapsed = time.perf_counter() - started
        print(f"[route_b_diag] {label}: {elapsed:.2f}s")
        if elapsed > time_limit_s:
            print(
                f"[route_b_diag] STOP — {label} exceeded {time_limit_s:.0f}s budget; "
                "not expanding experiment."
            )
            sys.exit(2)
        return elapsed

    print(f"[route_b_diag] subdiv={subdiv} time_limit={time_limit_s:.0f}s per step")
    baseline = _minimal_baseline_stub()
    prefer_numpy = _NUMPY_AVAILABLE
    print(f"[route_b_diag] prefer_numpy={prefer_numpy}")

    # --- Diagnostic 1: asymmetric patch, off-axis vs on-axis ---
    print("\n[route_b_diag] === Diagnostic 1: asymmetric 4-tile off-axis sample ===")
    t0 = time.perf_counter()
    json_asym = """
    {
      "id": "ts04d_diag_asym",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 1.0,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":0},
        {"q":0,"r":1,"elevation":0},
        {"q":1,"r":1,"elevation":0}
      ]
    }
    """
    model_asym = build_terrain_model(json_asym)
    mesh_asym = build_cliff_cut_mesh(model_asym, baseline, subdiv=subdiv)
    _timed(f"D1 mesh build (nodes={mesh_asym.node_count})", t0)

    t0 = time.perf_counter()
    energy_asym = assemble_hessian_energy_mixed_fem(mesh_asym, clamp_boundary=True)
    _timed(f"D1 energy assemble (nnz={_energy_matrix_nnz(energy_asym)})", t0)

    t0 = time.perf_counter()
    free_asym = [i for i in range(mesh_asym.node_count) if i not in mesh_asym.pinned]
    heights_asym, _, _ = _solve_constrained_hessian_direct(
        energy_asym,
        free_asym,
        mesh_asym.pinned,
        prefer_numpy=prefer_numpy,
    )
    _timed(f"D1 direct solve (free={len(free_asym)})", t0)

    asym_tiles = [(0, 0), (1, 0), (0, 1), (1, 1)]
    asym_xy = [handdrawn_center_world_xy(q, r) for q, r in asym_tiles]
    asym_z = [canonical_center_world_z(model_asym.map, q, r) for q, r in asym_tiles]
    weights, affine = _fit_tps_at_centers(asym_xy, asym_z)
    wx0, wy0 = asym_xy[0]
    wx1, wy1 = asym_xy[1]
    mx = 0.5 * (wx0 + wx1)
    my = 0.5 * (wy0 + wy1)
    px, py = -(wy1 - wy0), (wx1 - wx0)
    plen = math.hypot(px, py)
    off = 0.15 * DEFAULT_HEX_RADIUS
    sx_off = mx + off * px / plen
    sy_off = my + off * py / plen

    tps_on = _tps_height_at(mx, my, asym_xy, asym_z, weights, affine)
    fem_on = _nearest_mesh_height(mesh_asym, heights_asym, mx, my)
    tps_off = _tps_height_at(sx_off, sy_off, asym_xy, asym_z, weights, affine)
    fem_off = _nearest_mesh_height(mesh_asym, heights_asym, sx_off, sy_off)
    print(
        f"[route_b_diag] D1 on-axis  sample=({mx:.4f},{my:.4f}) "
        f"TPS={tps_on:.4f} FEM={fem_on:.4f} delta={fem_on - tps_on:.4f}"
    )
    print(
        f"[route_b_diag] D1 off-axis sample=({sx_off:.4f},{sy_off:.4f}) "
        f"TPS={tps_off:.4f} FEM={fem_off:.4f} delta={fem_off - tps_off:.4f}"
    )

    # --- Diagnostic 2: harmonic-energy discriminator on 7-tile hill ---
    print("\n[route_b_diag] === Diagnostic 2: harmonic-energy discriminator (7-tile) ===")
    t0 = time.perf_counter()
    json_hill = {
        "id": "ts04d_diag_hill",
        "orientation": "pointy_top_custom_axes",
        "elevation_step": 1.0,
        "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
        "tiles": [
            {"q": 0, "r": 0, "elevation": 1},
            {"q": 1, "r": 0, "elevation": 0},
            {"q": -1, "r": 0, "elevation": 0},
            {"q": 0, "r": 1, "elevation": 0},
            {"q": 0, "r": -1, "elevation": 0},
            {"q": 1, "r": -1, "elevation": 0},
            {"q": -1, "r": 1, "elevation": 0},
        ],
    }
    model_hill = build_terrain_model(json_hill)
    mesh_hill = build_cliff_cut_mesh(model_hill, baseline, subdiv=subdiv)
    _timed(f"D2 mesh build (nodes={mesh_hill.node_count})", t0)

    t0 = time.perf_counter()
    boundary = _boundary_vertex_set(mesh_hill)
    boundary_values = {
        vertex: math.sin(0.25 * mesh_hill.node_xy[vertex][0])
        + math.cos(0.2 * mesh_hill.node_xy[vertex][1])
        for vertex in boundary
    }
    h_harmonic = _harmonic_extension_with_boundary_values(
        mesh_hill,
        boundary_values,
        prefer_numpy=prefer_numpy,
    )
    _timed(f"D2 harmonic extension (boundary={len(boundary)})", t0)

    interior = [i for i in range(mesh_hill.node_count) if i not in boundary]
    fit_num = [0.0, 0.0, 0.0]
    fit_den = [[0.0] * 3 for _ in range(3)]
    for vertex in interior:
        x, y = mesh_hill.node_xy[vertex]
        row = [1.0, x, y]
        val = h_harmonic[vertex]
        for a in range(3):
            for b in range(3):
                fit_den[a][b] += row[a] * row[b]
            fit_num[a] += row[a] * val
    try:
        abc = _gaussian_solve([[fit_den[r][c] for r in range(3)] for c in range(3)], fit_num)
        fit_err = max(
            abs(
                h_harmonic[vertex]
                - (abc[0] + abc[1] * mesh_hill.node_xy[vertex][0] + abc[2] * mesh_hill.node_xy[vertex][1])
            )
            for vertex in interior
        )
    except (ValueError, ZeroDivisionError):
        fit_err = float("nan")
    print(f"[route_b_diag] D2 harmonic interior max affine-fit error={fit_err:.4f}")

    t0 = time.perf_counter()
    energy_h2 = assemble_hessian_energy_mixed_fem(mesh_hill, clamp_boundary=True)
    _timed(f"D2 Hessian energy assemble (nnz={_energy_matrix_nnz(energy_h2)})", t0)

    t0 = time.perf_counter()
    energy_lap2 = _assemble_laplacian_squared_natural_bc(mesh_hill, interior_only_mass=True)
    _timed(f"D2 Laplacian^2 natural assemble (nnz={_energy_matrix_nnz(energy_lap2)})", t0)

    t0 = time.perf_counter()
    e_h2 = _quadratic_form_energy(energy_h2, h_harmonic)
    e_lap2 = _quadratic_form_energy(energy_lap2, h_harmonic)
    _timed("D2 quadratic forms", t0)
    print(f"[route_b_diag] D2 E_H2(h_harmonic)={e_h2:.6e}")
    print(f"[route_b_diag] D2 E_Lap2_natural(h_harmonic)={e_lap2:.6e}")
    print(f"[route_b_diag] D2 ratio E_H2/E_Lap2={e_h2 / e_lap2 if e_lap2 > 1e-30 else float('inf'):.6e}")

    print("\n[route_b_diag] === Interpretation guide ===")
    print(
        "[route_b_diag] D1: if off-axis delta << on-axis delta vs TPS, symmetric midpoint is misleading."
    )
    print(
        "[route_b_diag] D2: if E_H2 >> 0 while E_Lap2 ~= 0, operator is genuinely Hessian (no collapse)."
    )
    print("[route_b_diag] done")


def _run_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model, handdrawn_center_world_xy

    baseline = _minimal_baseline_stub()
    subdiv = 4

    json_two = """
    {
      "id": "ts04_two_smooth",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2}
      ]
    }
    """
    model_two = build_terrain_model(json_two)
    mesh_two = build_cliff_cut_mesh(model_two, baseline, subdiv=subdiv)
    assert mesh_two.node_count > 0
    assert len(mesh_two.pinned) == 2

    heights_two, report_two = solve_fem_thin_plate(
        mesh_two,
        prefer_numpy=False,
        model=model_two,
        energy_method="mixed_fem",
    )
    assert report_two.max_center_interpolation_error < 1e-6
    assert report_two.relative_residual < 1e-6
    assert report_two.affine_constant_ok
    assert report_two.affine_planar_ok
    assert report_two.cliff_cut_two_tile_ok
    assert report_two.no_stencil_across_cliff

    energy_two = assemble_hessian_energy_mixed_fem(mesh_two, clamp_boundary=True)
    null_dims = _nullspace_dimension_per_component(energy_two, mesh_two)
    assert all(dim == 3 for dim in null_dims.values()), f"gate1 nullspace dims={null_dims}"

    json_constant = """
    {
      "id": "ts04d_constant",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":2},
        {"q":1,"r":0,"elevation":2},
        {"q":0,"r":1,"elevation":2}
      ]
    }
    """
    model_const = build_terrain_model(json_constant)
    mesh_const = build_cliff_cut_mesh(model_const, baseline, subdiv=subdiv)
    heights_const, report_const = solve_fem_thin_plate(
        mesh_const,
        prefer_numpy=False,
        model=model_const,
        energy_method="mixed_fem",
    )
    assert report_const.max_center_interpolation_error < 1e-6
    assert report_const.affine_constant_ok and report_const.affine_planar_ok
    target = canonical_center_world_z(model_const.map, 0, 0)
    assert max(abs(h - target) for h in heights_const) < 1e-5

    json_hill = {
        "id": "ts04d_hill",
        "orientation": "pointy_top_custom_axes",
        "elevation_step": 1.0,
        "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
        "tiles": [
            {"q": 0, "r": 0, "elevation": 1},
            {"q": 1, "r": 0, "elevation": 0},
            {"q": -1, "r": 0, "elevation": 0},
            {"q": 0, "r": 1, "elevation": 0},
            {"q": 0, "r": -1, "elevation": 0},
            {"q": 1, "r": -1, "elevation": 0},
            {"q": -1, "r": 1, "elevation": 0},
        ],
    }
    model_hill = build_terrain_model(json_hill)
    mesh_hill = build_cliff_cut_mesh(model_hill, baseline, subdiv=subdiv)
    heights_hill, report_hill = solve_fem_thin_plate(
        mesh_hill,
        prefer_numpy=False,
        model=model_hill,
        energy_method="mixed_fem",
        clamp_boundary=True,
    )
    assert report_hill.max_center_interpolation_error < 1e-6
    assert report_hill.no_stencil_across_cliff

    tiles = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)]
    centers_xy = [handdrawn_center_world_xy(q, r) for q, r in tiles]
    center_z = [canonical_center_world_z(model_hill.map, q, r) for q, r in tiles]
    weights, affine = _fit_tps_at_centers(centers_xy, center_z)
    start = centers_xy[0]
    end = centers_xy[1]
    profile = _profile_along_segment(mesh_hill, heights_hill, start, end)
    samples = [0.0, 0.25, 0.5, 0.75, 1.0]
    fem_vals = [_sample_profile_at(profile, t) for t in samples]
    tps_vals = [
        _tps_height_at(
            start[0] + t * (end[0] - start[0]),
            start[1] + t * (end[1] - start[1]),
            centers_xy,
            center_z,
            weights,
            affine,
        )
        for t in samples
    ]
    print("[fem_thin_plate] gate3 7-tile profile center->neighbor (TPS vs mixed-FEM):")
    for t, tps_h, fem_h in zip(samples, tps_vals, fem_vals, strict=True):
        print(f"  t={t:4.2f}  TPS={tps_h:8.4f}  FEM={fem_h:8.4f}  delta={fem_h - tps_h:8.4f}")
    mid_delta = fem_vals[2] - tps_vals[2]
    assert abs(mid_delta) <= 0.08, (
        f"gate3 midpoint FEM {fem_vals[2]:.4f} not within 0.08 of TPS {tps_vals[2]:.4f}"
    )
    for idx in range(len(samples) - 1):
        assert fem_vals[idx] >= fem_vals[idx + 1] - 1e-3, "gate3 profile should descend monotonically"
    assert fem_vals[0] >= fem_vals[-1] - 1e-3
    assert min(fem_vals) >= center_z[1] - 0.05

    json_asym = """
    {
      "id": "ts04d_asym",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 1.0,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":0},
        {"q":0,"r":1,"elevation":0},
        {"q":1,"r":1,"elevation":0}
      ]
    }
    """
    model_asym = build_terrain_model(json_asym)
    mesh_asym = build_cliff_cut_mesh(model_asym, baseline, subdiv=subdiv)
    heights_asym, _ = solve_fem_thin_plate(
        mesh_asym,
        prefer_numpy=False,
        model=model_asym,
        energy_method="mixed_fem",
    )
    asym_tiles = [(0, 0), (1, 0), (0, 1), (1, 1)]
    asym_xy = [handdrawn_center_world_xy(q, r) for q, r in asym_tiles]
    asym_z = [canonical_center_world_z(model_asym.map, q, r) for q, r in asym_tiles]
    asym_weights, asym_affine = _fit_tps_at_centers(asym_xy, asym_z)
    wx0, wy0 = asym_xy[0]
    wx1, wy1 = asym_xy[1]
    mx = 0.5 * (wx0 + wx1)
    my = 0.5 * (wy0 + wy1)
    px, py = -(wy1 - wy0), (wx1 - wx0)
    plen = math.hypot(px, py)
    off = 0.15 * DEFAULT_HEX_RADIUS
    sx = mx + off * px / plen
    sy = my + off * py / plen
    tps_off = _tps_height_at(sx, sy, asym_xy, asym_z, asym_weights, asym_affine)
    fem_off = _nearest_mesh_height(mesh_asym, heights_asym, sx, sy)
    off_delta = fem_off - tps_off
    print(
        f"[fem_thin_plate] gate2 off-axis sample delta={off_delta:.4f} "
        f"(TPS={tps_off:.4f} FEM={fem_off:.4f})"
    )
    assert abs(off_delta) <= 0.08, (
        f"gate2 off-axis FEM {fem_off:.4f} not within 0.08 of TPS {tps_off:.4f}"
    )

    boundary_ratio = _free_boundary_tangent_normal_ratio(mesh_hill, heights_hill)
    print(f"[fem_thin_plate] gate5 boundary tangent/normal ratio={boundary_ratio:.4f}")
    assert boundary_ratio > 0.03, (
        f"gate5 natural BC appears collapsed toward zero-Neumann (ratio={boundary_ratio:.4f})"
    )

    energy_ablation = assemble_hessian_energy_mixed_fem(mesh_hill, clamp_boundary=False)
    free_hill = [i for i in range(mesh_hill.node_count) if i not in mesh_hill.pinned]
    heights_ablation, _, _ = _solve_constrained_hessian_direct(
        energy_ablation,
        free_hill,
        mesh_hill.pinned,
        prefer_numpy=False,
    )
    profile_ablation = _profile_along_segment(mesh_hill, heights_ablation, start, end)
    fem_ablation_mid = _sample_profile_at(profile_ablation, 0.5)
    ablation_mid_delta = fem_ablation_mid - tps_vals[2]
    ablation_ratio = _free_boundary_tangent_normal_ratio(mesh_hill, heights_ablation)
    print(
        f"[fem_thin_plate] gate6 ablation midpoint delta={ablation_mid_delta:.4f} "
        f"ratio={ablation_ratio:.4f} (clamped delta={mid_delta:.4f} ratio={boundary_ratio:.4f})"
    )
    ablation_fails = abs(ablation_mid_delta) > abs(mid_delta) + 0.03 or (
        ablation_ratio < boundary_ratio * 0.5
    )
    assert ablation_fails, (
        "gate6 boundary-clamp ablation must fail gate2/5 while clamped formulation passes"
    )

    solver = FemThinPlateTerrainSolver()
    solver.prepare(model_two, baseline=baseline, subdiv=subdiv)
    cx, cy = handdrawn_center_world_xy(0, 0)
    assert abs(solver.sample_world(cx, cy, 0, 0) - 0.0) < 1e-6
    cx1, cy1 = handdrawn_center_world_xy(1, 0)
    assert abs(solver.sample_world(cx1, cy1, 1, 0) - 0.4) < 1e-6

    print("eom_terrain_fem_thin_plate self-test passed (TS-04d mixed-FEM gates 1-6)")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "route_b_diagnostics":
        _run_route_b_diagnostics()
    else:
        _run_self_tests()
