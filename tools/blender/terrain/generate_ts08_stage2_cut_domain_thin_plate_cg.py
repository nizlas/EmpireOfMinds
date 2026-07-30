# Empire of Minds — dedicated TS-08 Stage 2 cut-domain thin-plate CG generator.
# Standalone entry point: first real cut-domain solve over Ω_cut.
#
# Run: blender --background --python tools/blender/terrain/generate_ts08_stage2_cut_domain_thin_plate_cg.py
# Or:  blender --background --python tools/blender/terrain/run_ts08_stage2_cut_domain_thin_plate_cg_regen.py

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

PROTOTYPE_ID = "TS-08-STAGE-2-CUT-DOMAIN-THIN-PLATE-CG"
RUNNER_FILE: str | None = None
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage2_cut_domain_thin_plate_cg.blend"
)
COLLECTION_NAME = "EOM_Terrain_TerrainMap_Full01"
TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OVERLAY_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_Overlay"
_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"
_REPORT_DIR = SCRIPT_DIR / "reports"
_REPORT_PATH = _REPORT_DIR / "ts08_stage2_cut_domain_thin_plate_cg_audit.json"


def _log(message: str) -> None:
    print(f"[TS-08 Stage 2 cut-domain thin-plate CG] {message}")


def _load_full01_module() -> Any:
    generator_path = SCRIPT_DIR / _FULL01_MODULE_NAME
    if not generator_path.is_file():
        raise FileNotFoundError(f"Missing shared generator: {generator_path}")
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08s2", generator_path)
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


def _build_lattice_direct_top_mesh(
    lattice: Any,
    heights: Any,
    baseline: Any,
) -> tuple[Any, dict[str, Any]]:
    import bpy

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

    mesh = bpy.data.meshes.new("TerrainMapFull01")
    mesh.from_pydata(verts, [], top_faces)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    baseline._finalize_mesh(mesh)
    stats = {
        "top_verts": len(verts),
        "top_faces": len(top_faces),
        "total_verts": len(verts),
        "total_faces": len(top_faces),
        "cliff_wall_faces": 0,
        "side_faces": 0,
    }
    return mesh, stats


def _print_traceability_banner(
    *,
    phase: str,
    output_path: Path | None = None,
    terrain_solver: object | None = None,
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
    print("STAGE=2")
    print("CUTS=ON")
    print("GAMMA_EMPTY=OFF")
    print(f"CLIFF_EDGES={EXPECTED_CLIFF_EDGE_COUNT}")
    print("DELTA_GT_1_IS_CLIFF=confirmed")
    print("DELTA_EQ_1_IS_SMOOTH=confirmed")
    print("DELTA_EQ_1_NOT_CUT=True")
    print("HEIGHT_SOLVE=ON")
    print("CG_SOLVER=ON")
    print("SCIPY_REQUIRED=NO")
    print("NUMPY_OPERATOR_CG=ON")
    print("MEMBRANE_REGULARIZER=OFF")
    print("ZERO_BOUNDARY_PULL=OFF")
    print("WALLS=OFF")
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
    print("MESH_MODE=lattice_direct_top_surface")
    print("PRESENTATION_WALLS=OFF")
    print(f"CUT_TOPOLOGICAL_NODE_COUNT={EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT}")
    print(f"CENTER_PIN_COUNT={EXPECTED_CENTER_PIN_COUNT}")
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
        _log("--- TS-08 Stage 2 cut-domain thin-plate CG pre-mesh solve ---")
        _log(f"cut node count: {vs_stats.get('node_count', 0)}")
        _log(f"triangle count: {vs_stats.get('triangle_count', 0)}")
        _log(f"center pin count: {vs_stats.get('pinned_center_count', 0)}")
        _log(f"component count: {vs_stats.get('connected_component_count', 0)}")
        _log(f"cg iterations: {vs_stats.get('cg_iterations', 0)}")
        _log(
            f"cg rel residual: {vs_stats.get('cg_final_rel_residual', 0.0):.6e} "
            f"(abs {vs_stats.get('cg_final_abs_residual', 0.0):.6e})"
        )
        _log(
            f"energy initial/final: {vs_stats.get('energy_initial', 0.0):.6e} / "
            f"{vs_stats.get('energy_final', 0.0):.6e}"
        )
        _log(
            f"z_min/z_max: {vs_stats.get('z_min', 0.0):.4f} / {vs_stats.get('z_max', 0.0):.4f}"
        )
        _log(
            f"max center error: {vs_stats.get('max_center_interpolation_error', 0.0):.6e}"
        )
        _log(f"max tent-pole delta: {vs_stats.get('max_tent_pole_delta', 0.0):.6f}")
        _log(f"cg converged: {vs_stats.get('converged', False)}")

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

    procedural_material = baseline.make_pbr_ground_stone_ash_terrain_material(
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

    terrain_mesh, stats = _build_lattice_direct_top_mesh(lattice, heights, baseline)
    baseline.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    terrain_mesh.materials.append(procedural_material)
    terrain_obj = bpy.data.objects.new(TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)
    _log("lattice-direct top surface mesh created")
    _log(f"top vertices: {stats['top_verts']}")
    _log(f"top faces: {stats['top_faces']}")
    _log(f"cliff wall faces: {stats['cliff_wall_faces']}")

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
        procedural_material,
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
            },
            handle,
            indent=2,
        )
    print(f"JSON_REPORT_PATH={_REPORT_PATH.resolve()}")

    _print_traceability_banner(
        phase="END",
        output_path=output_path,
        terrain_solver=terrain_solver,
    )
    full01._save_blend(output_path)
    _log(f"saved blend: {output_path}")
    _log("done")


if __name__ == "__main__":
    main()
