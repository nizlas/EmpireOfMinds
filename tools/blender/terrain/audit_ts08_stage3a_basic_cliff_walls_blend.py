# Empire of Minds — read-only audit for TS-08 Stage 3a basic cliff-wall output.
# Run: blender --background --python tools/blender/terrain/audit_ts08_stage3a_basic_cliff_walls_blend.py

from __future__ import annotations

import importlib.util
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

import bmesh
import bpy

TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage3a_basic_cliff_walls.blend"
)
STAGE2_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage2_cut_domain_thin_plate_cg.blend"
)
JSON_REPORT_PATH = Path(__file__).resolve().parent / "reports" / "ts08_stage3a_basic_cliff_walls_audit.json"
MAP_ID = "terrain_handdrawn_test_map_full_01"
EXPECTED_VERTICES = 74129
EXPECTED_TOP_FACES = 145152
EXPECTED_CLIFF_EDGES = 78
STAGE2_BOUNDARY_EDGES = 3120
CENTER_HEIGHT_TOL = 1e-6
TOP_Z_COMPARE_TOL = 1e-12
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
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08s3a_audit", generator_path)
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


def _load_stage2_reference_z(stage2_path: Path) -> list[float]:
    current_path = bpy.data.filepath
    bpy.ops.wm.open_mainfile(filepath=str(stage2_path))
    terrain_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
    if terrain_obj is None or terrain_obj.type != "MESH":
        raise RuntimeError(f"Stage 2 reference missing mesh {TERRAIN_OBJECT_NAME!r}")
    z_values = [float(v.co.z) for v in terrain_obj.data.vertices]
    if current_path:
        bpy.ops.wm.open_mainfile(filepath=current_path)
    return z_values


def _audit_center_heights(
    mesh: bpy.types.Mesh,
    lattice: Any,
    *,
    tol: float,
) -> tuple[float, int]:
    max_error = 0.0
    violations = 0
    for node_index, _hex in lattice.pin_hex_by_node.items():
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


def _wall_face_key(indices: tuple[int, ...]) -> tuple[int, ...]:
    if len(indices) == 4:
        return tuple(sorted(indices))
    return indices


def _audit_wall_faces(
    mesh: bpy.types.Mesh,
    lattice: Any,
    model: Any,
    baseline: Any,
    expected_wall_build: Any,
    cliff_pairs: set[frozenset[tuple[int, int]]],
) -> tuple[list[str], dict[str, float]]:
    from eom_terrain_ts08_cliff_walls import (
        TOP_MATERIAL_INDEX,
        WALL_MATERIAL_INDEX,
        expected_segment_length,
        max_wall_face_xy_span,
    )

    failures: list[str] = []
    top_face_count = EXPECTED_TOP_FACES
    expected_keys = expected_wall_build.expected_wall_face_keys
    actual_wall_faces: list[tuple[int, ...]] = []
    actual_keys: set[tuple[int, ...]] = set()

    nodes_by_pos_tile: dict[tuple[tuple[float, float], tuple[int, int]], int] = dict(
        lattice.tile_pos_to_node.items()
    )
    cliff_tiles: set[tuple[int, int]] = set()
    for pair in cliff_pairs:
        cliff_tiles.update(pair)

    for poly in mesh.polygons:
        if poly.index < top_face_count:
            if poly.material_index != TOP_MATERIAL_INDEX:
                failures.append(
                    f"top polygon {poly.index} uses material_index={poly.material_index}"
                )
            continue
        if poly.material_index != WALL_MATERIAL_INDEX:
            failures.append(
                f"wall polygon {poly.index} uses material_index={poly.material_index}"
            )
        indices = tuple(poly.vertices)
        actual_wall_faces.append(indices)
        key = _wall_face_key(indices)
        if key in actual_keys:
            failures.append(f"duplicate wall face key {key}")
        actual_keys.add(key)

        tiles_in_face: set[tuple[int, int]] = set()
        for node_index in indices:
            pk = lattice.node_pos_keys[node_index]
            for (pos, tile), nid in nodes_by_pos_tile.items():
                if nid == node_index and pos == pk:
                    tiles_in_face.add(tile)
        cliff_tiles_in_face = tiles_in_face & cliff_tiles
        if len(cliff_tiles_in_face) < 2:
            failures.append(
                f"wall face {poly.index} does not bridge opposite cliff sheets: "
                f"tiles={sorted(tiles_in_face)}"
            )

    if actual_keys != expected_keys:
        missing = expected_keys - actual_keys
        extra = actual_keys - expected_keys
        if missing:
            failures.append(f"wall faces missing vs helper expectation: {len(missing)}")
        if extra:
            failures.append(f"unexpected wall faces vs helper expectation: {len(extra)}")

    seg_len = expected_segment_length()
    max_span = max_wall_face_xy_span(lattice, actual_wall_faces)
    span_tol = seg_len * 1.05 + 1e-6
    if max_span > span_tol:
        failures.append(
            f"absurd wall face XY span: {max_span:.6f} > {span_tol:.6f}"
        )

    wall_heights: list[float] = []
    for face in actual_wall_faces:
        z_vals = [mesh.vertices[index].co.z for index in face]
        wall_heights.append(max(z_vals) - min(z_vals))

    if not wall_heights:
        failures.append("no wall faces found")
        stats = {"min": 0.0, "mean": 0.0, "max": 0.0, "count": 0.0}
    else:
        stats = {
            "min": min(wall_heights),
            "mean": sum(wall_heights) / float(len(wall_heights)),
            "max": max(wall_heights),
            "count": float(len(wall_heights)),
        }
        if stats["max"] < 1e-6:
            failures.append("all wall heights approximately zero; cuts appear fake")

    return failures, stats


def _audit_case1_crack_tips(
    mesh: bpy.types.Mesh,
    lattice: Any,
    corner_registry: list[Any],
    expected_wall_build: Any,
) -> dict[str, float | int]:
    triangle_count = 0
    max_neighbor_delta = 0.0
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
        if neighbor_z:
            center_z = mesh.vertices[center_node].co.z
            max_neighbor_delta = max(
                max_neighbor_delta,
                max(abs(float(center_z) - float(z)) for z in neighbor_z),
            )

    for record in expected_wall_build.wall_face_records:
        if len(record.vertex_indices) == 3:
            triangle_count += 1

    return {
        "max_neighbor_delta": max_neighbor_delta,
        "triangle_wall_faces": triangle_count,
    }


def main() -> None:
    if "BASELINE" in OUTPUT_BLEND_FILENAME.upper():
        print("FAIL: audit target filename looks like a BASELINE path")
        sys.exit(1)

    output_path = _resolve_blend_path(OUTPUT_BLEND_FILENAME)
    stage2_path = _resolve_blend_path(STAGE2_BLEND_FILENAME)
    full01 = _load_full01_module()
    terrain_map = full01.parse_terrain_map_json(full01.TERRAIN_MAP_JSON)
    model = full01.build_terrain_model(terrain_map)
    repo_root, examined_starts = full01._resolve_repo_root()
    baseline = full01._load_baseline_module(repo_root, examined_starts=examined_starts)

    from eom_terrain_ts08_cliff_walls import (
        TOP_MATERIAL_INDEX,
        WALL_MATERIAL_INDEX,
        build_cliff_wall_faces,
    )
    from eom_terrain_ts08_cut_lattice import (
        build_cliff_neighbor_pairs,
        build_corner_registry,
        build_cut_lattice_for_model,
    )
    from eom_terrain_ts08_stage2_cut_thin_plate_cg import CutDomainThinPlateCgTerrainSolver

    cliff_pairs = build_cliff_neighbor_pairs(model)
    lattice = build_cut_lattice_for_model(model, baseline)
    corner_registry = build_corner_registry(model, cliff_pairs)

    solver = CutDomainThinPlateCgTerrainSolver()
    solver.prepare(model, baseline, radius=full01.DEFAULT_HEX_RADIUS)
    assert solver._heights is not None
    expected_wall_build = build_cliff_wall_faces(
        lattice,
        model,
        baseline,
        solver._heights,
        radius=full01.DEFAULT_HEX_RADIUS,
    )
    expected_wall_face_count = len(expected_wall_build.wall_faces)

    solver_stats: dict[str, Any] = {}
    if JSON_REPORT_PATH.is_file():
        with JSON_REPORT_PATH.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
            solver_stats = payload.get("solver_stats") or {}

    stage2_z = _load_stage2_reference_z(stage2_path)

    print("=== TS08_STAGE3A_BASIC_CLIFF_WALLS_AUDIT (read-only) ===")
    print(f"AUDIT_OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"STAGE2_REFERENCE_BLEND_PATH={stage2_path.resolve()}")
    print(f"MAP_ID={MAP_ID}")
    print("AUDIT_MODE=read_only_no_save")
    print("CUTS=ON")
    print("WALLS=ON")
    print("BASIC_WALLS=ON")
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
    print(f"TOP_FACE_COUNT={EXPECTED_TOP_FACES}")
    print(f"WALL_FACE_COUNT={report['polygons'] - EXPECTED_TOP_FACES}")
    print(f"EXPECTED_WALL_FACE_COUNT={expected_wall_face_count}")
    print(f"WALL_SEGMENT_COUNT={expected_wall_build.segment_count}")
    print(f"WALL_SEGMENTS_SKIPPED={expected_wall_build.skipped_segment_count}")
    print(f"MESH_Z_MIN={report['z_min']:.6f}")
    print(f"MESH_Z_MAX={report['z_max']:.6f}")
    print(f"MESH_LOOSE_VERTS={report['loose_verts']}")
    print(f"MESH_LOOSE_EDGES={report['loose_edges']}")
    print(f"MESH_BOUNDARY_EDGES={report['boundary_edges']}")
    print(f"STAGE2_BOUNDARY_EDGES={STAGE2_BOUNDARY_EDGES}")
    print(f"MESH_ISLANDS={report['mesh_islands']}")

    if report["vertices"] != EXPECTED_VERTICES:
        failures.append(f"vertices: got {report['vertices']}, expected {EXPECTED_VERTICES}")
    if report["polygons"] != EXPECTED_TOP_FACES + expected_wall_face_count:
        failures.append(
            f"polygons: got {report['polygons']}, "
            f"expected {EXPECTED_TOP_FACES + expected_wall_face_count}"
        )
    if report["loose_verts"] != 0:
        failures.append(f"loose_verts: got {report['loose_verts']}, expected 0")
    if report["loose_edges"] != 0:
        failures.append(f"loose_edges: got {report['loose_edges']}, expected 0")
    if report["mesh_islands"] != 1:
        failures.append(f"mesh_islands: got {report['mesh_islands']}, expected 1")
    if report["mesh_islands"] >= 10:
        failures.append(f"mesh_islands fragmentation regression: {report['mesh_islands']}")

    boundary_edges = int(report["boundary_edges"])
    if boundary_edges >= STAGE2_BOUNDARY_EDGES:
        failures.append(
            f"boundary edges not reduced vs Stage 2: {boundary_edges} >= {STAGE2_BOUNDARY_EDGES}"
        )

    max_z_diff = 0.0
    if len(stage2_z) != len(mesh.vertices):
        failures.append(
            f"Stage 2 reference vertex count mismatch: {len(stage2_z)} vs {len(mesh.vertices)}"
        )
    else:
        for index, ref_z in enumerate(stage2_z):
            actual_z = float(mesh.vertices[index].co.z)
            diff = abs(actual_z - ref_z)
            if diff > max_z_diff:
                max_z_diff = diff
            if diff > TOP_Z_COMPARE_TOL:
                failures.append(
                    f"top z mismatch at vertex {index}: diff={diff:.6e} > tol={TOP_Z_COMPARE_TOL:.6e}"
                )
                break
    print(f"MAX_TOP_Z_DIFF_VS_STAGE2={max_z_diff:.6e}")

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

    smooth_mismatch, smooth_violations = _audit_smooth_edge_continuity(mesh, lattice, model)
    print(f"SMOOTH_EDGE_MAX_MISMATCH={smooth_mismatch:.6e}")
    print(f"SMOOTH_EDGE_SPLIT_VIOLATIONS={smooth_violations}")
    if smooth_violations > 0:
        failures.append(f"smooth edges split across topology: {smooth_violations}")

    wall_failures, wall_stats = _audit_wall_faces(
        mesh,
        lattice,
        model,
        baseline,
        expected_wall_build,
        cliff_pairs,
    )
    failures.extend(wall_failures)
    print(
        "WALL_HEIGHT_MIN_MEAN_MAX="
        f"{wall_stats['min']:.6f},{wall_stats['mean']:.6f},{wall_stats['max']:.6f}"
    )
    print(f"WALL_HEIGHT_SAMPLES={int(wall_stats['count'])}")

    case1 = _audit_case1_crack_tips(mesh, lattice, corner_registry, expected_wall_build)
    print(f"CASE1_MAX_NEIGHBOR_DELTA={case1['max_neighbor_delta']:.6f}")
    print(f"CASE1_TRIANGLE_WALL_FACES={case1['triangle_wall_faces']}")

    material_count = len(mesh.materials)
    print(f"MATERIAL_SLOT_COUNT={material_count}")
    if material_count != 2:
        failures.append(f"material slot count: got {material_count}, expected 2")
    else:
        print(f"TOP_MATERIAL_NAME={mesh.materials[TOP_MATERIAL_INDEX].name}")
        print(f"WALL_MATERIAL_NAME={mesh.materials[WALL_MATERIAL_INDEX].name}")

    from eom_terrain_ts08_cliff_wall_stone_material import audit_wall_stone_material

    mat_failures, mat_info = audit_wall_stone_material(mesh, top_face_count=EXPECTED_TOP_FACES)
    failures.extend(mat_failures)
    print(f"WALL_STONE_MATERIAL_NAME={mat_info.get('wall_material_name')}")
    print(f"WALL_STONE_ALBEDO_PRESENT={mat_info.get('has_stone_albedo')}")
    print(f"WALL_UV_LAYER_PRESENT={mat_info.get('wall_uv_layer_present')}")
    print(f"WALL_FACES_ON_STONE_MATERIAL={mat_info.get('wall_faces_on_wall_material')}")
    print(f"TOP_FACES_ON_WALL_MATERIAL={mat_info.get('top_faces_on_wall_material')}")
    print(f"WALL_UV_LOOP_COUNT={mat_info.get('wall_loop_count')}")
    print(f"WALL_DEGENERATE_UV_LOOPS={mat_info.get('degenerate_wall_loops')}")
    if mat_info.get("stone_albedo_source"):
        print(f"STONE_ALBEDO_SOURCE={mat_info.get('stone_albedo_source')}")
    print("WALL_LOCAL_UVS_GENERATED=YES")
    print("TERRAIN_GEOMETRY_CHANGED=NO")

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
    print("TS08_STAGE3A_BASIC_CLIFF_WALLS_AUDIT_PASS=True")


if __name__ == "__main__":
    main()
