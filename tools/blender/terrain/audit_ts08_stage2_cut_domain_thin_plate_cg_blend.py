# Empire of Minds — read-only audit for TS-08 Stage 2 cut-domain thin-plate CG output.
# Run: blender --background --python tools/blender/terrain/audit_ts08_stage2_cut_domain_thin_plate_cg_blend.py

from __future__ import annotations

import importlib.util
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import bmesh
import bpy

TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage2_cut_domain_thin_plate_cg.blend"
)
JSON_REPORT_PATH = Path(__file__).resolve().parent / "reports" / "ts08_stage2_cut_domain_thin_plate_cg_audit.json"
MAP_ID = "terrain_handdrawn_test_map_full_01"
EXPECTED_VERTICES = 74129
EXPECTED_FACES = 145152
EXPECTED_CLIFF_EDGES = 78
CENTER_HEIGHT_TOL = 1e-6
Z_MIN_WARN = -0.90
Z_MAX_WARN = 2.60
Z_MIN_HARD_FAIL = -2.0
Z_MAX_HARD_FAIL = 4.0
TENT_POLE_WARN = 0.25
_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"


def _resolve_blend_path(filename: str) -> Path:
    starts: list[Path] = []
    try:
        script_path = bpy.path.abspath(__file__)
        if script_path:
            starts.append(Path(script_path).resolve().parent)
    except (NameError, TypeError):
        pass
    try:
        starts.append(Path(__file__).resolve().parent)
    except NameError:
        pass

    seen: set[str] = set()
    for start in starts:
        key = str(start.resolve())
        if key in seen:
            continue
        seen.add(key)
        for root in (start, *start.parents):
            candidate = (
                root
                / "game"
                / "assets"
                / "prototype"
                / "3d"
                / "terrain"
                / "prototype_3d_terrain"
                / "generated"
                / filename
            )
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(f"Blend not found: {filename}")


def _load_full01_module() -> Any:
    script_dir = Path(__file__).resolve().parent
    generator_path = script_dir / _FULL01_MODULE_NAME
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08s2_audit", generator_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {generator_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _count_mesh_islands(mesh: bpy.types.Mesh) -> int:
    parent: dict[int, int] = {}

    def find(x: int) -> int:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for poly in mesh.polygons:
        verts = poly.vertices
        root = find(verts[0])
        for index in verts[1:]:
            ri = find(index)
            if ri != root:
                parent[ri] = root
    all_verts = {v for poly in mesh.polygons for v in poly.vertices}
    return len({find(v) for v in all_verts})


def _audit_mesh_topology(mesh: bpy.types.Mesh) -> dict[str, object]:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    loose_verts = sum(1 for vert in bm.verts if not vert.link_edges)
    loose_edges = sum(1 for edge in bm.edges if not edge.link_faces)
    boundary_edges = sum(1 for edge in bm.edges if len(edge.link_faces) == 1)
    zs = [v.co.z for v in mesh.vertices]
    bm.free()
    return {
        "vertices": len(mesh.vertices),
        "polygons": len(mesh.polygons),
        "loose_verts": loose_verts,
        "loose_edges": loose_edges,
        "boundary_edges": boundary_edges,
        "z_min": min(zs) if zs else 0.0,
        "z_max": max(zs) if zs else 0.0,
        "mesh_islands": _count_mesh_islands(mesh),
    }


def _audit_center_heights(
    mesh: bpy.types.Mesh,
    lattice: Any,
    *,
    tol: float,
) -> tuple[float, int]:
    max_error = 0.0
    violations = 0
    for node_index, (q, r) in lattice.pin_hex_by_node.items():
        del q, r
        expected = lattice.pinned[node_index]
        actual = mesh.vertices[node_index].co.z
        error = abs(float(actual) - expected)
        max_error = max(max_error, error)
        if error > tol:
            violations += 1
    return max_error, violations


def _audit_tent_poles(mesh: bpy.types.Mesh, lattice: Any) -> float:
    max_delta = 0.0
    for node_index in lattice.pinned:
        center_z = mesh.vertices[node_index].co.z
        for neighbor in lattice.adjacency[node_index]:
            delta = abs(float(center_z) - float(mesh.vertices[neighbor].co.z))
            if delta > max_delta:
                max_delta = delta
    return max_delta


def _cliff_neighbor_set(model: Any) -> set[frozenset[tuple[int, int]]]:
    from eom_terrain_ts08_cut_lattice import build_cliff_neighbor_pairs

    return build_cliff_neighbor_pairs(model)


def _audit_cliff_jumps(
    mesh: bpy.types.Mesh,
    lattice: Any,
    cliff_pairs: set[frozenset[tuple[int, int]]],
) -> dict[str, float]:
    from eom_terrain_math_core import pos_key

    nodes_by_pos: dict[tuple[float, float], list[tuple[int, tuple[int, int]]]] = defaultdict(list)
    for (pk, tile), node_index in lattice.tile_pos_to_node.items():
        nodes_by_pos[pk].append((node_index, tile))

    jumps: list[float] = []
    for pk, entries in nodes_by_pos.items():
        if len(entries) < 2:
            continue
        for i in range(len(entries)):
            for j in range(i + 1, len(entries)):
                node_a, tile_a = entries[i]
                node_b, tile_b = entries[j]
                if tile_a == tile_b:
                    continue
                if frozenset((tile_a, tile_b)) not in cliff_pairs:
                    continue
                jump = abs(float(mesh.vertices[node_a].co.z) - float(mesh.vertices[node_b].co.z))
                jumps.append(jump)

    if not jumps:
        return {"min": 0.0, "mean": 0.0, "max": 0.0, "count": 0.0}
    return {
        "min": min(jumps),
        "mean": sum(jumps) / float(len(jumps)),
        "max": max(jumps),
        "count": float(len(jumps)),
    }


def _audit_smooth_edge_continuity(
    mesh: bpy.types.Mesh,
    lattice: Any,
    model: Any,
) -> tuple[float, int]:
    from eom_terrain_math_core import pos_key
    from eom_terrain_ts08_cut_lattice import shared_hex_edge_endpoints

    max_mismatch = 0.0
    violations = 0
    radius = 1.0
    for edge in model.smooth_edges:
        if edge.delta > 1:
            continue
        p0, p1 = shared_hex_edge_endpoints(edge.tile_a, edge.tile_b, radius=radius)
        mid_x = (p0[0] + p1[0]) * 0.5
        mid_y = (p0[1] + p1[1]) * 0.5
        pk = pos_key(mid_x, mid_y)
        node_a = lattice.tile_pos_to_node.get((pk, edge.tile_a))
        node_b = lattice.tile_pos_to_node.get((pk, edge.tile_b))
        if node_a is None or node_b is None:
            continue
        if node_a != node_b:
            violations += 1
            z_a = mesh.vertices[node_a].co.z
            z_b = mesh.vertices[node_b].co.z
            max_mismatch = max(max_mismatch, abs(float(z_a) - float(z_b)))
    return max_mismatch, violations


def _count_duplicated_seam_vertices(lattice: Any) -> int:
    from collections import Counter

    counts = Counter(lattice.node_pos_keys)
    duplicated = sum(count - 1 for count in counts.values() if count > 1)
    return duplicated


def _audit_case1_crack_tips(
    mesh: bpy.types.Mesh,
    lattice: Any,
    corner_registry: list[Any],
) -> dict[str, float]:
    jumps: list[float] = []
    for corner in corner_registry:
        if not corner.is_interior or corner.case != 1:
            continue
        pk = corner.world_xy_key
        nodes = [index for index, pos in enumerate(lattice.node_pos_keys) if pos == pk]
        if len(nodes) != 1:
            continue
        center_node = nodes[0]
        neighbor_z = [
            mesh.vertices[neighbor].co.z for neighbor in lattice.adjacency[center_node]
        ]
        if not neighbor_z:
            continue
        center_z = mesh.vertices[center_node].co.z
        jumps.extend(abs(float(center_z) - float(z)) for z in neighbor_z)
    if not jumps:
        return {"max_neighbor_delta": 0.0}
    return {"max_neighbor_delta": max(jumps)}


def main() -> None:
    if "BASELINE" in OUTPUT_BLEND_FILENAME.upper():
        print("FAIL: audit target filename looks like a BASELINE path")
        sys.exit(1)

    output_path = _resolve_blend_path(OUTPUT_BLEND_FILENAME)
    full01 = _load_full01_module()
    terrain_map = full01.parse_terrain_map_json(full01.TERRAIN_MAP_JSON)
    model = full01.build_terrain_model(terrain_map)
    repo_root, examined_starts = full01._resolve_repo_root()
    baseline = full01._load_baseline_module(repo_root, examined_starts=examined_starts)

    from eom_terrain_ts08_cut_lattice import (
        build_corner_registry,
        build_cut_lattice_for_model,
    )

    cliff_pairs = _cliff_neighbor_set(model)
    lattice = build_cut_lattice_for_model(model, baseline)
    corner_registry = build_corner_registry(model, cliff_pairs)

    solver_stats: dict[str, Any] = {}
    if JSON_REPORT_PATH.is_file():
        with JSON_REPORT_PATH.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
            solver_stats = payload.get("solver_stats") or {}

    print("=== TS08_STAGE2_CUT_DOMAIN_THIN_PLATE_CG_AUDIT (read-only) ===")
    print(f"AUDIT_OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"MAP_ID={MAP_ID}")
    print("AUDIT_MODE=read_only_no_save")
    print("CUTS=ON")
    print("GAMMA_EMPTY=OFF")
    print(f"CLIFF_EDGES={len(cliff_pairs)}")
    print("DELTA_EQ_1_NOT_CUT=True")

    bpy.ops.wm.open_mainfile(filepath=str(output_path))
    terrain_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
    failures: list[str] = []
    warnings: list[str] = []

    if terrain_obj is None or terrain_obj.type != "MESH":
        failures.append(f"missing terrain mesh object {TERRAIN_OBJECT_NAME!r}")
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    mesh = terrain_obj.data
    report = _audit_mesh_topology(mesh)
    print(f"MESH_VERTICES={report['vertices']}")
    print(f"MESH_POLYGONS={report['polygons']}")
    print(f"MESH_Z_MIN={report['z_min']:.6f}")
    print(f"MESH_Z_MAX={report['z_max']:.6f}")
    print(f"MESH_LOOSE_VERTS={report['loose_verts']}")
    print(f"MESH_LOOSE_EDGES={report['loose_edges']}")
    print(f"MESH_BOUNDARY_EDGES={report['boundary_edges']}")
    print(f"MESH_ISLANDS={report['mesh_islands']}")

    if report["vertices"] != EXPECTED_VERTICES:
        failures.append(f"vertices: got {report['vertices']}, expected {EXPECTED_VERTICES}")
    if report["polygons"] != EXPECTED_FACES:
        failures.append(f"polygons: got {report['polygons']}, expected {EXPECTED_FACES}")
    if report["loose_verts"] != 0:
        failures.append(f"loose_verts: got {report['loose_verts']}, expected 0")
    if report["loose_edges"] != 0:
        failures.append(f"loose_edges: got {report['loose_edges']}, expected 0")
    if report["mesh_islands"] != 1:
        failures.append(f"mesh_islands: got {report['mesh_islands']}, expected 1")
    if report["mesh_islands"] >= 10:
        failures.append(f"mesh_islands fragmentation regression: {report['mesh_islands']}")

    duplicated_seams = _count_duplicated_seam_vertices(lattice)
    print(f"DUPLICATED_SEAM_VERTICES={duplicated_seams}")
    if duplicated_seams <= 0:
        failures.append("duplicated seam vertices: expected > 0 for cut-domain mesh")

    z_min = float(report["z_min"])
    z_max = float(report["z_max"])
    if z_min <= Z_MIN_HARD_FAIL or z_max >= Z_MAX_HARD_FAIL:
        failures.append(f"z-range catastrophic: [{z_min:.4f}, {z_max:.4f}]")
    if z_min < Z_MIN_WARN:
        warnings.append(f"z_min below warn gate: {z_min:.6f} < {Z_MIN_WARN}")
    if z_max > Z_MAX_WARN:
        warnings.append(f"z_max above warn gate: {z_max:.6f} > {Z_MAX_WARN}")

    max_center_error, center_violations = _audit_center_heights(
        mesh,
        lattice,
        tol=CENTER_HEIGHT_TOL,
    )
    print(f"MAX_CENTER_INTERPOLATION_ERROR={max_center_error:.6e}")
    print(f"CENTER_HEIGHT_VIOLATIONS={center_violations}")
    if center_violations > 0:
        failures.append(
            f"center height violations: {center_violations} "
            f"(max error {max_center_error:.6e})"
        )

    max_tent_pole = _audit_tent_poles(mesh, lattice)
    print(f"MAX_TENT_POLE_DELTA={max_tent_pole:.6f}")
    if max_tent_pole > TENT_POLE_WARN:
        warnings.append(
            f"tent-pole delta high ({max_tent_pole:.6f}); review visually"
        )

    cliff_jumps = _audit_cliff_jumps(mesh, lattice, cliff_pairs)
    print(
        "CLIFF_JUMP_MIN_MEAN_MAX="
        f"{cliff_jumps['min']:.6f},{cliff_jumps['mean']:.6f},{cliff_jumps['max']:.6f}"
    )
    print(f"CLIFF_JUMP_SAMPLES={int(cliff_jumps['count'])}")
    if cliff_jumps["count"] <= 0:
        failures.append("no cliff jump samples found")
    elif cliff_jumps["max"] < 1e-6:
        failures.append("all cliff jumps approximately zero; cuts appear fake")

    smooth_mismatch, smooth_violations = _audit_smooth_edge_continuity(mesh, lattice, model)
    print(f"SMOOTH_EDGE_MAX_MISMATCH={smooth_mismatch:.6e}")
    print(f"SMOOTH_EDGE_SPLIT_VIOLATIONS={smooth_violations}")
    if smooth_violations > 0:
        failures.append(f"smooth edges split across topology: {smooth_violations}")

    case1 = _audit_case1_crack_tips(mesh, lattice, corner_registry)
    print(f"CASE1_MAX_NEIGHBOR_DELTA={case1['max_neighbor_delta']:.6f}")

    if solver_stats:
        print(f"CG_ITERATIONS={solver_stats.get('cg_iterations', 0)}")
        print(f"CG_FINAL_REL_RESIDUAL={solver_stats.get('cg_final_rel_residual', 0.0):.6e}")
        print(f"CG_CONVERGED={solver_stats.get('converged', False)}")
        print(f"ENERGY_INITIAL={solver_stats.get('energy_initial', 0.0):.6e}")
        print(f"ENERGY_FINAL={solver_stats.get('energy_final', 0.0):.6e}")
        if not solver_stats.get("converged", False):
            failures.append("CG did not converge per solver JSON report")
    else:
        warnings.append("solver JSON report not found; CG metrics not verified from file")

    if len(cliff_pairs) != EXPECTED_CLIFF_EDGES:
        failures.append(f"cliff edge count: got {len(cliff_pairs)}, expected {EXPECTED_CLIFF_EDGES}")

    if warnings:
        print("--- warnings ---")
        for warning in warnings:
            print(f"WARNING: {warning}")

    if failures:
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    print("=== RESULT: PASS ===")
    print("TS08_STAGE2_CUT_DOMAIN_THIN_PLATE_CG_AUDIT_PASS=True")


if __name__ == "__main__":
    main()
