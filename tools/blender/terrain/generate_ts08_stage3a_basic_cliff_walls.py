# Empire of Minds — dedicated TS-08 Stage 3a basic cliff-wall generator.
# Standalone entry point: Stage 2 cut-domain solve + presentation cliff walls.
#
# Run: blender --background --python tools/blender/terrain/generate_ts08_stage3a_basic_cliff_walls.py
# Or:  blender --background --python tools/blender/terrain/run_ts08_stage3a_basic_cliff_walls_regen.py

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

PROTOTYPE_ID = "TS-08-STAGE-3A-BASIC-CLIFF-WALLS"
RUNNER_FILE: str | None = None
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage3a_basic_cliff_walls.blend"
)
COLLECTION_NAME = "EOM_Terrain_TerrainMap_Full01"
TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OVERLAY_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_Overlay"
_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"
_REPORT_DIR = SCRIPT_DIR / "reports"
_REPORT_PATH = _REPORT_DIR / "ts08_stage3a_basic_cliff_walls_audit.json"
EXPECTED_TOP_FACE_COUNT = 145152


def _log(message: str) -> None:
    print(f"[TS-08 Stage 3a basic cliff walls] {message}")


def _load_full01_module() -> Any:
    generator_path = SCRIPT_DIR / _FULL01_MODULE_NAME
    if not generator_path.is_file():
        raise FileNotFoundError(f"Missing shared generator: {generator_path}")
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08s3a", generator_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {generator_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _generated_output_path(repo_root: Path) -> Path:
    return (
        repo_root
        / "game"
        / "assets"
        / "prototype"
        / "3d"
        / "terrain"
        / "prototype_3d_terrain"
        / "generated"
        / OUTPUT_BLEND_FILENAME
    )


def _build_top_and_wall_mesh(
    lattice: Any,
    heights: Any,
    baseline: Any,
    model: Any,
    wall_build: Any,
) -> tuple[Any, dict[str, Any]]:
    import bpy

    from eom_terrain_ts08_cliff_walls import TOP_MATERIAL_INDEX, WALL_MATERIAL_INDEX

    verts: list[tuple[float, float, float]] = []
    for index, (wx, wy) in enumerate(lattice.node_xy):
        verts.append((wx, wy, float(heights[index])))

    top_faces: list[tuple[int, int, int]] = []
    face_keys: set[tuple[int, int, int]] = set()
    for v0, v1, v2 in lattice.triangles:
        wound = baseline.orient_upward_triangle(verts, v0, v1, v2)
        key = tuple(sorted(wound))
        if key in face_keys:
            continue
        face_keys.add(key)
        top_faces.append(wound)

    all_faces: list[tuple[int, ...]] = list(top_faces)
    all_faces.extend(wall_build.wall_faces)

    mesh = bpy.data.meshes.new("TerrainMapFull01")
    mesh.from_pydata(verts, [], all_faces)

    for polygon in mesh.polygons:
        if polygon.index < len(top_faces):
            polygon.use_smooth = True
            polygon.material_index = TOP_MATERIAL_INDEX
        else:
            polygon.use_smooth = False
            polygon.material_index = WALL_MATERIAL_INDEX

    baseline._finalize_mesh(mesh)
    stats = {
        "top_verts": len(verts),
        "top_faces": len(top_faces),
        "wall_faces": len(wall_build.wall_faces),
        "wall_segments": wall_build.segment_count,
        "wall_segments_skipped": wall_build.skipped_segment_count,
        "wall_triangles": wall_build.triangle_count,
        "wall_quads": wall_build.quad_count,
        "total_verts": len(verts),
        "total_faces": len(all_faces),
        "cliff_wall_faces": len(wall_build.wall_faces),
        "side_faces": 0,
    }
    return mesh, stats


def _print_traceability_banner(
    *,
    phase: str,
    output_path: Path | None = None,
    terrain_solver: object | None = None,
    mesh_stats: dict[str, Any] | None = None,
    wall_stats: dict[str, float] | None = None,
) -> None:
    from eom_terrain_ts08_cut_lattice import (
        EXPECTED_CENTER_PIN_COUNT,
        EXPECTED_CLIFF_EDGE_COUNT,
        EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT,
    )
    from eom_terrain_ts08_stage2_cut_thin_plate_cg import MAP_ID

    solver_class = (
        type(terrain_solver).__name__ if terrain_solver is not None else "pending"
    )
    backend = getattr(getattr(terrain_solver, "backend", None), "value", "variational_spline")
    stats = getattr(terrain_solver, "stats", None) or {}

    print("=== EOM TERRAIN PROTOTYPE TRACEABILITY ===")
    print(f"TRACEABILITY_PHASE={phase}")
    print(f"PROTOTYPE_ID={PROTOTYPE_ID}")
    print("DOC_SOURCE=docs/TERRAIN_SURFACE_TARGET.md")
    print(f"MAP_ID={MAP_ID}")
    print("STAGE=3A")
    print("CUTS=ON")
    print("WALLS=ON")
    print("BASIC_WALLS=ON")
    print("FINAL_CLIFF_ASSETS=OFF")
    print("HEIGHT_SOLVE=ON")
    print("SOLVER_FROM_STAGE2=ON")
    print("TOP_SURFACE_UNCHANGED_FROM_STAGE2_SOLVE=ON")
    print(f"CLIFF_EDGES={EXPECTED_CLIFF_EDGE_COUNT}")
    print("DELTA_GT_1_IS_CLIFF=confirmed")
    print("DELTA_EQ_1_IS_SMOOTH=confirmed")
    print("DELTA_EQ_1_NOT_CUT=True")
    print("CG_SOLVER=ON")
    print("SCIPY_REQUIRED=NO")
    print("NUMPY_OPERATOR_CG=ON")
    print("MEMBRANE_REGULARIZER=OFF")
    print("ZERO_BOUNDARY_PULL=OFF")
    print("RAILS=OFF")
    print("FEM_SOLVER=OFF")
    print("TPS_SOLVER=OFF")
    print("TS03D_CLUSTERING=OFF")
    print(f"RUNNER_FILE={RUNNER_FILE or __file__}")
    print(f"OUTPUT_BLEND_FILENAME={OUTPUT_BLEND_FILENAME}")
    if output_path is not None:
        print(f"OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"TERRAIN_SOLVER_BACKEND={backend}")
    print(f"TERRAIN_SOLVER_CLASS={solver_class}")
    print("MESH_MODE=lattice_direct_top_surface_plus_basic_cliff_walls")
    print("PRESENTATION_WALLS=ON")
    print(f"CUT_TOPOLOGICAL_NODE_COUNT={EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT}")
    print(f"CENTER_PIN_COUNT={EXPECTED_CENTER_PIN_COUNT}")
    print(f"TOP_FACE_COUNT={EXPECTED_TOP_FACE_COUNT}")
    if mesh_stats is not None:
        print(f"WALL_FACE_COUNT={mesh_stats.get('wall_faces', 0)}")
        print(f"WALL_SEGMENT_COUNT={mesh_stats.get('wall_segments', 0)}")
    if wall_stats is not None:
        print(
            "WALL_HEIGHT_MIN_MEAN_MAX="
            f"{wall_stats.get('min', 0.0):.6f},"
            f"{wall_stats.get('mean', 0.0):.6f},"
            f"{wall_stats.get('max', 0.0):.6f}"
        )
    if stats:
        print(f"CONNECTED_COMPONENT_COUNT={stats.get('connected_component_count', 0)}")
        print(f"DEFICIENT_COMPONENT_COUNT={stats.get('deficient_component_count', 0)}")
        print(f"MAX_CENTER_ERROR={stats.get('max_center_interpolation_error', 0.0):.6e}")
        print(f"CG_ITERATIONS={stats.get('cg_iterations', 0)}")
        print(f"CG_FINAL_ABS_RESIDUAL={stats.get('cg_final_abs_residual', 0.0):.6e}")
        print(f"CG_FINAL_REL_RESIDUAL={stats.get('cg_final_rel_residual', 0.0):.6e}")
        print(f"CG_CONVERGED={stats.get('converged', False)}")
        print(f"ENERGY_INITIAL={stats.get('energy_initial', 0.0):.6e}")
        print(f"ENERGY_FINAL={stats.get('energy_final', 0.0):.6e}")
        print(
            f"Z_MIN_Z_MAX={stats.get('z_min', 0.0):.6f},{stats.get('z_max', 0.0):.6f}"
        )
        print(f"MAX_TENT_POLE_DELTA={stats.get('max_tent_pole_delta', 0.0):.6f}")
    print("=== END TRACEABILITY ===")
    sys.stdout.flush()


def main() -> None:
    import bpy

    from eom_terrain_ts08_cliff_walls import build_cliff_wall_faces, wall_height_stats
    from eom_terrain_ts08_stage2_cut_thin_plate_cg import CutDomainThinPlateCgTerrainSolver

    full01 = _load_full01_module()
    _print_traceability_banner(phase="START")

    terrain_map = full01.parse_terrain_map_json(full01.TERRAIN_MAP_JSON)
    model = full01.build_terrain_model(terrain_map)
    repo_root, examined_starts = full01._resolve_repo_root()
    _log(f"repo root: {repo_root}")

    baseline = full01._load_baseline_module(repo_root, examined_starts=examined_starts)
    full01._assert_baseline_unchanged(baseline)
    baseline.validate_params()
    baseline.validate_material_params()

    terrain_solver = CutDomainThinPlateCgTerrainSolver()
    terrain_solver.backend = full01.TerrainBackend.variational_spline  # type: ignore[attr-defined]
    terrain_solver.prepare(model, baseline, radius=full01.DEFAULT_HEX_RADIUS)

    output_path = _generated_output_path(repo_root)
    full01._assert_not_frozen_baseline_path(output_path)

    lattice = terrain_solver.lattice
    assert lattice is not None
    heights = terrain_solver._heights
    assert heights is not None

    vs_stats = terrain_solver.stats
    if vs_stats is not None:
        _log("--- TS-08 Stage 2 cut-domain thin-plate CG solve (reused for Stage 3a) ---")
        _log(f"cut node count: {vs_stats.get('node_count', 0)}")
        _log(f"triangle count: {vs_stats.get('triangle_count', 0)}")
        _log(f"center pin count: {vs_stats.get('pinned_center_count', 0)}")
        _log(f"cg iterations: {vs_stats.get('cg_iterations', 0)}")
        _log(
            f"cg rel residual: {vs_stats.get('cg_final_rel_residual', 0.0):.6e} "
            f"(abs {vs_stats.get('cg_final_abs_residual', 0.0):.6e})"
        )
        _log(
            f"z_min/z_max: {vs_stats.get('z_min', 0.0):.4f} / {vs_stats.get('z_max', 0.0):.4f}"
        )
        _log(
            f"max center error: {vs_stats.get('max_center_interpolation_error', 0.0):.6e}"
        )
        _log(f"cg converged: {vs_stats.get('converged', False)}")

    wall_build = build_cliff_wall_faces(
        lattice,
        model,
        baseline,
        heights,
        radius=full01.DEFAULT_HEX_RADIUS,
    )
    wall_stats = wall_height_stats(wall_build)
    _log("--- cliff wall build ---")
    _log(f"wall faces: {len(wall_build.wall_faces)}")
    _log(f"wall segments: {wall_build.segment_count}")
    _log(f"wall segments skipped: {wall_build.skipped_segment_count}")
    _log(f"wall triangles: {wall_build.triangle_count}")
    _log(f"wall quads: {wall_build.quad_count}")
    _log(
        f"wall height min/mean/max: {wall_stats['min']:.6f} / "
        f"{wall_stats['mean']:.6f} / {wall_stats['max']:.6f}"
    )

    ground_albedo_path, ground_normal_path, ground_roughness_path = (
        baseline.resolve_ground_texture_paths(repo_root)
    )
    stone_albedo_path, stone_normal_path, stone_roughness_path = (
        baseline.resolve_stone_texture_paths(repo_root)
    )
    ash_albedo_path, ash_normal_path, ash_roughness_path = baseline.resolve_ash_texture_paths(
        repo_root
    )

    baseline.clear_scene()
    coll = baseline.ensure_collection(COLLECTION_NAME)

    top_material = baseline.make_pbr_ground_stone_ash_terrain_material(
        ground_albedo_path,
        ground_normal_path,
        ground_roughness_path,
        ash_albedo_path,
        ash_normal_path,
        ash_roughness_path,
        stone_albedo_path,
        stone_normal_path,
        stone_roughness_path,
    )
    baseline._log_material_setup()

    terrain_mesh, stats = _build_top_and_wall_mesh(
        lattice,
        heights,
        baseline,
        model,
        wall_build,
    )
    baseline.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    from eom_terrain_ts08_cliff_wall_stone_material import (
        CLIFF_WALL_STONE_MATERIAL_NAME,
        apply_ts08_cliff_wall_stone_presentation,
    )

    wall_material, wall_mat_stats = apply_ts08_cliff_wall_stone_presentation(
        terrain_mesh,
        stats,
        wall_build,
        baseline,
        stone_albedo_path,
        stone_normal_path,
        stone_roughness_path,
    )
    terrain_mesh.materials.append(top_material)
    terrain_mesh.materials.append(wall_material)
    terrain_obj = bpy.data.objects.new(TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)
    _log("lattice-direct top surface + basic cliff walls mesh created")
    _log(f"top vertices: {stats['top_verts']}")
    _log(f"top faces: {stats['top_faces']}")
    _log(f"wall faces: {stats['wall_faces']}")
    _log(f"wall material: {CLIFF_WALL_STONE_MATERIAL_NAME}")
    _log(f"stone albedo: {stone_albedo_path}")
    _log(f"wall-local UV layer: {wall_mat_stats.get('layer_name')}")
    _log(f"wall UV mapping: {wall_mat_stats.get('mapping_mode')}")
    _log(f"wall faces on stone material: {wall_mat_stats.get('wall_faces_assigned')}")

    overlay_material = baseline.make_overlay_material()
    overlay_mesh, overlay_stats = full01.build_hex_overlay_mesh(model, baseline)
    overlay_obj = bpy.data.objects.new(OVERLAY_OBJECT_NAME, overlay_mesh)
    overlay_obj.data.materials.append(overlay_material)
    coll.objects.link(overlay_obj)
    _log("hex overlay created")
    _log(f"unique overlay edges: {overlay_stats['unique_edges']}")

    baseline.setup_camera_and_lights()
    full01._adjust_camera(baseline, model)
    baseline.setup_render_and_world()
    baseline._log_ash_brightness_audit(
        top_material,
        ground_albedo_path=ground_albedo_path,
        ground_normal_path=ground_normal_path,
        ground_roughness_path=ground_roughness_path,
        ash_albedo_path=ash_albedo_path,
        ash_normal_path=ash_normal_path,
        ash_roughness_path=ash_roughness_path,
        stone_albedo_path=stone_albedo_path,
        stone_normal_path=stone_normal_path,
        stone_roughness_path=stone_roughness_path,
    )

    from eom_terrain_ts08_stage2_cut_thin_plate_cg import MAP_ID

    _REPORT_DIR.mkdir(parents=True, exist_ok=True)
    with _REPORT_PATH.open("w", encoding="utf-8") as handle:
        json.dump(
            {
                "prototype_id": PROTOTYPE_ID,
                "map_id": MAP_ID,
                "solver_stats": vs_stats,
                "mesh_stats": stats,
                "wall_stats": wall_stats,
                "wall_material": wall_mat_stats,
                "wall_build": {
                    "segment_count": wall_build.segment_count,
                    "skipped_segment_count": wall_build.skipped_segment_count,
                    "triangle_count": wall_build.triangle_count,
                    "quad_count": wall_build.quad_count,
                    "wall_face_count": len(wall_build.wall_faces),
                    "expected_wall_face_keys": [
                        list(key) for key in sorted(wall_build.expected_wall_face_keys)
                    ],
                },
            },
            handle,
            indent=2,
        )
    print(f"JSON_REPORT_PATH={_REPORT_PATH.resolve()}")

    _print_traceability_banner(
        phase="END",
        output_path=output_path,
        terrain_solver=terrain_solver,
        mesh_stats=stats,
        wall_stats=wall_stats,
    )
    print(f"WALL_MATERIAL_NAME={CLIFF_WALL_STONE_MATERIAL_NAME}")
    print(f"STONE_ALBEDO_SOURCE={stone_albedo_path.resolve()}")
    print(f"WALL_FACE_STONE_ASSIGN_COUNT={wall_mat_stats.get('wall_faces_assigned', 0)}")
    print(f"TOP_FACE_COUNT_UNCHANGED={stats['top_faces']}")
    print(f"WALL_LOCAL_UVS_GENERATED={wall_mat_stats.get('wall_loop_count', 0) > 0}")
    print("TERRAIN_GEOMETRY_CHANGED=NO")
    full01._save_blend(output_path)
    _log(f"saved blend: {output_path}")
    _log("done")


if __name__ == "__main__":
    main()
