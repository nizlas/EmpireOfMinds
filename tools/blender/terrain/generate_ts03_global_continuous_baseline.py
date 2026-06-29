# Empire of Minds — dedicated TS-03 global continuous baseline generator.
# Standalone entry point: one global TPS over all tile-center interpolation points.
# Does not read or set shared experiment USE_* flags.
#
# Run: blender --background --python tools/blender/terrain/generate_ts03_global_continuous_baseline.py
# Or:  blender --background --python tools/blender/terrain/run_ts03_global_continuous_baseline_regen.py

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any

try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

PROTOTYPE_ID = "TS-03-GLOBAL-CONTINUOUS-BASELINE"
RUNNER_FILE: str | None = None
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts03_global_continuous_baseline.blend"
)
COLLECTION_NAME = "EOM_Terrain_TerrainMap_Full01"
TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OVERLAY_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_Overlay"
_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"


def _log(message: str) -> None:
    print(f"[TS-03 global continuous baseline] {message}")


def _load_full01_module() -> Any:
    generator_path = SCRIPT_DIR / _FULL01_MODULE_NAME
    if not generator_path.is_file():
        raise FileNotFoundError(f"Missing shared generator: {generator_path}")
    spec = importlib.util.spec_from_file_location("eom_gen_full01_baseline", generator_path)
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


def _print_traceability_banner(
    *,
    phase: str,
    output_path: Path | None = None,
    terrain_solver: object | None = None,
) -> None:
    solver_class = (
        type(terrain_solver).__name__ if terrain_solver is not None else "pending"
    )
    backend = getattr(getattr(terrain_solver, "backend", None), "value", "variational_spline")
    print("=== EOM TERRAIN PROTOTYPE TRACEABILITY ===")
    print(f"TRACEABILITY_PHASE={phase}")
    print(f"PROTOTYPE_ID={PROTOTYPE_ID}")
    print(f"RUNNER_FILE={RUNNER_FILE or __file__}")
    print(f"OUTPUT_BLEND_FILENAME={OUTPUT_BLEND_FILENAME}")
    if output_path is not None:
        print(f"OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"TERRAIN_SOLVER_BACKEND={backend}")
    print(f"TERRAIN_SOLVER_CLASS={solver_class}")
    print("TS03_BASELINE_MODE=global_continuous")
    print("PER_CLIFF_SIDE_CLUSTERING=False")
    print("SPLIT_TOP_AT_CLIFF_EDGES=False")
    print("CLIFF_EDGE_CONSTRAINTS=False")
    print("RIM_CONSTRAINTS=False")
    print("RELEASE_BANDS=False")
    print("LOCAL_POST_SOLVE_CORRECTIONS=False")
    print("USE_VARIATIONAL_SPLINE_SURFACE=True")
    print("USE_TPS_CLIFF_RELEASE=False")
    print("USE_TPS_RIM_CONSTRAINTS=False")
    print("USE_TS07A_TS03_CLONE=False")
    print("USE_TS05_DEBUG_OVERLAY=False")
    print("CLIFF_WALL_DEBUG_ENABLED=False")
    print("=== END TRACEABILITY ===")
    sys.stdout.flush()


def main() -> None:
    import bpy

    from eom_terrain_variational_spline import GlobalContinuousVariationalSplineTerrainSolver

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

    terrain_solver = GlobalContinuousVariationalSplineTerrainSolver()
    terrain_solver.backend = full01.TerrainBackend.variational_spline  # type: ignore[attr-defined]
    terrain_solver.prepare(model, radius=full01.DEFAULT_HEX_RADIUS)

    output_path = _generated_output_path(repo_root)
    full01._assert_not_frozen_baseline_path(output_path)

    vs_stats = terrain_solver.stats
    if vs_stats is not None:
        _log("--- global continuous TPS pre-mesh solve ---")
        _log(f"pre-mesh component_count: {vs_stats.get('component_count', 0)}")
        _log(
            "pre-mesh max_center_interpolation_error: "
            f"{vs_stats.get('max_center_interpolation_error', 0.0)}"
        )
        _log(
            "pre-mesh affine_constant_ok: "
            f"{vs_stats.get('affine_constant_ok')} "
            f"affine_planar_ok: {vs_stats.get('affine_planar_ok')}"
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
    side_material = baseline.make_side_terrain_material()
    baseline._log_material_setup()

    terrain_mesh, stats = full01.build_analytic_terrain_mesh(
        model,
        baseline,
        terrain_solver=terrain_solver,
        split_top_at_cliff_edges=False,
    )
    baseline.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    baseline.assign_patch_materials(
        terrain_mesh,
        stats["top_faces"],
        procedural_material,
        side_material,
    )
    terrain_obj = bpy.data.objects.new(TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)
    _log("terrain mesh created")
    _log(f"top vertices: {stats['top_verts']}")
    _log(f"top faces: {stats['top_faces']}")
    _log(f"cliff placeholder wall faces: {stats['cliff_wall_faces']}")
    _log(f"total vertices: {stats['total_verts']}")
    _log(f"total faces: {stats['total_faces']}")

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

    full01._print_mesh_geometry_integrity(
        terrain_mesh,
        stats,
        bottom_z=-baseline.BASE_THICKNESS,
    )

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
