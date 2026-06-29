# Empire of Minds — TerrainMap IR → math core → Blender analytic terrain backend.
# Run from Blender Scripting workspace: Open → Run Script.
# Requires bpy (not available outside Blender).
#
# First narrow slice of docs/TERRAIN_MODEL.md. Does not modify the approved
# PBR baseline script, Niclas demo, materials, Godot, or gameplay.

from __future__ import annotations

from pathlib import Path
import sys

try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = None

if SCRIPT_DIR is None or not (SCRIPT_DIR / "eom_terrain_math_core.py").is_file():
    try:
        import bpy

        _script_name = "generate_terrain_terrainmap_handdrawn_full_01.py"
        _resolved: Path | None = None
        try:
            space = bpy.context.space_data
            if space is not None and getattr(space, "text", None) is not None:
                text = space.text
                if text is not None and text.filepath and Path(text.filepath).name == _script_name:
                    _resolved = Path(bpy.path.abspath(text.filepath)).resolve().parent
        except Exception:
            pass
        if _resolved is None:
            for text in bpy.data.texts:
                if text.filepath and Path(text.filepath).name == _script_name:
                    _resolved = Path(bpy.path.abspath(text.filepath)).resolve().parent
                    break
        if _resolved is not None and (_resolved / "eom_terrain_math_core.py").is_file():
            SCRIPT_DIR = _resolved
    except ImportError:
        pass

if SCRIPT_DIR is None:
    SCRIPT_DIR = Path.cwd()

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import importlib.util
import json
import math
from typing import Any

import bpy
from mathutils import Vector

# Terrain math symbols are bound after repo/path helpers via _load_terrain_math_core().

# ---------------------------------------------------------------------------
# Inline full experiment map (TerrainMap IR)
# ---------------------------------------------------------------------------

TERRAIN_MAP_JSON = """
{
  "id": "handdrawn_test_map_full_01",
  "orientation": "pointy_top_custom_axes",
  "elevation_step": 0.4,
  "edge_rule": {
    "default": "smooth",
    "cliff_if_abs_delta_greater_than": 1
  },
  "edge_overrides": [],
  "tiles": [
    {"q":0,"r":0,"elevation":1},
    {"q":1,"r":0,"elevation":1},
    {"q":2,"r":0,"elevation":1},
    {"q":3,"r":0,"elevation":1},
    {"q":4,"r":0,"elevation":1},
    {"q":5,"r":0,"elevation":3},
    {"q":6,"r":0,"elevation":3},
    {"q":7,"r":0,"elevation":4},
    {"q":8,"r":0,"elevation":1},
    {"q":9,"r":0,"elevation":1},
    {"q":10,"r":0,"elevation":1},

    {"q":0,"r":1,"elevation":1},
    {"q":1,"r":1,"elevation":1},
    {"q":2,"r":1,"elevation":2},
    {"q":3,"r":1,"elevation":1},
    {"q":4,"r":1,"elevation":3},
    {"q":5,"r":1,"elevation":2},
    {"q":6,"r":1,"elevation":2},
    {"q":7,"r":1,"elevation":4},
    {"q":8,"r":1,"elevation":1},
    {"q":9,"r":1,"elevation":1},

    {"q":-1,"r":2,"elevation":1},
    {"q":0,"r":2,"elevation":1},
    {"q":1,"r":2,"elevation":2},
    {"q":2,"r":2,"elevation":1},
    {"q":3,"r":2,"elevation":2},
    {"q":4,"r":2,"elevation":3},
    {"q":5,"r":2,"elevation":3},
    {"q":6,"r":2,"elevation":3},
    {"q":7,"r":2,"elevation":2},
    {"q":8,"r":2,"elevation":1},
    {"q":9,"r":2,"elevation":1},

    {"q":-1,"r":3,"elevation":1},
    {"q":0,"r":3,"elevation":3},
    {"q":1,"r":3,"elevation":1},
    {"q":2,"r":3,"elevation":2},
    {"q":3,"r":3,"elevation":2},
    {"q":4,"r":3,"elevation":3},
    {"q":5,"r":3,"elevation":3},
    {"q":6,"r":3,"elevation":1},
    {"q":7,"r":3,"elevation":1},
    {"q":8,"r":3,"elevation":1},

    {"q":-2,"r":4,"elevation":1},
    {"q":-1,"r":4,"elevation":3},
    {"q":0,"r":4,"elevation":3},
    {"q":1,"r":4,"elevation":1},
    {"q":2,"r":4,"elevation":1},
    {"q":3,"r":4,"elevation":1},
    {"q":4,"r":4,"elevation":2},
    {"q":5,"r":4,"elevation":1},
    {"q":6,"r":4,"elevation":1},
    {"q":7,"r":4,"elevation":1},
    {"q":8,"r":4,"elevation":1},

    {"q":-2,"r":5,"elevation":1},
    {"q":-1,"r":5,"elevation":1},
    {"q":0,"r":5,"elevation":1},
    {"q":1,"r":5,"elevation":1},
    {"q":2,"r":5,"elevation":1},
    {"q":3,"r":5,"elevation":1},
    {"q":4,"r":5,"elevation":1},
    {"q":5,"r":5,"elevation":1},
    {"q":6,"r":5,"elevation":2},
    {"q":7,"r":5,"elevation":1},

    {"q":-3,"r":6,"elevation":1},
    {"q":-2,"r":6,"elevation":2},
    {"q":-1,"r":6,"elevation":1},
    {"q":0,"r":6,"elevation":1},
    {"q":1,"r":6,"elevation":6},
    {"q":2,"r":6,"elevation":6},
    {"q":3,"r":6,"elevation":3},
    {"q":4,"r":6,"elevation":1},
    {"q":5,"r":6,"elevation":3},
    {"q":6,"r":6,"elevation":2},
    {"q":7,"r":6,"elevation":1},

    {"q":-3,"r":7,"elevation":1},
    {"q":-2,"r":7,"elevation":1},
    {"q":-1,"r":7,"elevation":1},
    {"q":0,"r":7,"elevation":6},
    {"q":1,"r":7,"elevation":5},
    {"q":2,"r":7,"elevation":5},
    {"q":3,"r":7,"elevation":4},
    {"q":4,"r":7,"elevation":1},
    {"q":5,"r":7,"elevation":3},
    {"q":6,"r":7,"elevation":2},

    {"q":-4,"r":8,"elevation":3},
    {"q":-3,"r":8,"elevation":2},
    {"q":-2,"r":8,"elevation":1},
    {"q":-1,"r":8,"elevation":6},
    {"q":0,"r":8,"elevation":6},
    {"q":1,"r":8,"elevation":5},
    {"q":2,"r":8,"elevation":3},
    {"q":3,"r":8,"elevation":3},
    {"q":4,"r":8,"elevation":1},
    {"q":5,"r":8,"elevation":2},
    {"q":6,"r":8,"elevation":1},

    {"q":-4,"r":9,"elevation":2},
    {"q":-3,"r":9,"elevation":2},
    {"q":-2,"r":9,"elevation":1},
    {"q":-1,"r":9,"elevation":6},
    {"q":0,"r":9,"elevation":5},
    {"q":1,"r":9,"elevation":4},
    {"q":2,"r":9,"elevation":2},
    {"q":3,"r":9,"elevation":2},
    {"q":4,"r":9,"elevation":1},
    {"q":5,"r":9,"elevation":1},

    {"q":-5,"r":10,"elevation":1},
    {"q":-4,"r":10,"elevation":2},
    {"q":-3,"r":10,"elevation":1},
    {"q":-2,"r":10,"elevation":5},
    {"q":-1,"r":10,"elevation":5},
    {"q":0,"r":10,"elevation":4},
    {"q":1,"r":10,"elevation":1},
    {"q":2,"r":10,"elevation":1},
    {"q":3,"r":10,"elevation":1},
    {"q":4,"r":10,"elevation":1},
    {"q":5,"r":10,"elevation":1},

    {"q":-5,"r":11,"elevation":1},
    {"q":-4,"r":11,"elevation":1},
    {"q":-3,"r":11,"elevation":1},
    {"q":-2,"r":11,"elevation":1},
    {"q":-1,"r":11,"elevation":4},
    {"q":0,"r":11,"elevation":1},
    {"q":1,"r":11,"elevation":1},
    {"q":2,"r":11,"elevation":1},
    {"q":3,"r":11,"elevation":2},
    {"q":4,"r":11,"elevation":1},

    {"q":-6,"r":12,"elevation":2},
    {"q":-5,"r":12,"elevation":3},
    {"q":-4,"r":12,"elevation":1},
    {"q":-3,"r":12,"elevation":1},
    {"q":-2,"r":12,"elevation":1},
    {"q":-1,"r":12,"elevation":1},
    {"q":0,"r":12,"elevation":1},
    {"q":1,"r":12,"elevation":1},
    {"q":2,"r":12,"elevation":1},
    {"q":3,"r":12,"elevation":2},
    {"q":4,"r":12,"elevation":1},

    {"q":-6,"r":13,"elevation":2},
    {"q":-5,"r":13,"elevation":3},
    {"q":-4,"r":13,"elevation":1},
    {"q":-3,"r":13,"elevation":2},
    {"q":-2,"r":13,"elevation":2},
    {"q":-1,"r":13,"elevation":1},
    {"q":0,"r":13,"elevation":1},
    {"q":1,"r":13,"elevation":1},
    {"q":2,"r":13,"elevation":1},
    {"q":3,"r":13,"elevation":1},

    {"q":-7,"r":14,"elevation":1},
    {"q":-6,"r":14,"elevation":4},
    {"q":-5,"r":14,"elevation":4},
    {"q":-4,"r":14,"elevation":1},
    {"q":-3,"r":14,"elevation":2},
    {"q":-2,"r":14,"elevation":1},
    {"q":-1,"r":14,"elevation":1},
    {"q":0,"r":14,"elevation":1},
    {"q":1,"r":14,"elevation":1},
    {"q":2,"r":14,"elevation":1},
    {"q":3,"r":14,"elevation":1},

    {"q":-7,"r":15,"elevation":1},
    {"q":-6,"r":15,"elevation":1},
    {"q":-5,"r":15,"elevation":1},
    {"q":-4,"r":15,"elevation":1},
    {"q":-3,"r":15,"elevation":1},
    {"q":-2,"r":15,"elevation":1},
    {"q":-1,"r":15,"elevation":1},
    {"q":0,"r":15,"elevation":1},
    {"q":1,"r":15,"elevation":1},
    {"q":2,"r":15,"elevation":1}
  ]
}
"""

TERRAIN_BASELINE_SCRIPT = "generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py"

COLLECTION_NAME = "EOM_Terrain_TerrainMap_Full01"
TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OVERLAY_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_Overlay"
CLIFF_WALL_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_CliffPlaceholder"

OUTPUT_BLEND_FILENAME = "terrain_handdrawn_test_map_full_01.blend"
OUTPUT_BLEND_FILENAME_HEXPATCH_V1 = "terrain_handdrawn_test_map_full_01_hexpatch_v1.blend"
OUTPUT_BLEND_FILENAME_GLOBAL_BIHARMONIC = (
    "terrain_handdrawn_test_map_full_01_global_biharmonic.blend"
)
OUTPUT_BLEND_FILENAME_VARIATIONAL_SPLINE = (
    "terrain_handdrawn_test_map_full_01_variational_spline.blend"
)
OUTPUT_BLEND_FILENAME_FEM_THIN_PLATE = (
    "terrain_handdrawn_test_map_full_01_fem_thin_plate.blend"
)
OUTPUT_BLEND_FILENAME_TPS_CLIFF_RELEASE = (
    "terrain_handdrawn_test_map_full_01_tps_cliff_release.blend"
)
OUTPUT_BLEND_FILENAME_TPS_RIM_CONSTRAINTS = (
    "terrain_handdrawn_test_map_full_01_tps_rim_constraints.blend"
)
OUTPUT_BLEND_FILENAME_TS07A_TS03_CLONE = (
    "terrain_handdrawn_test_map_full_01_ts07a_ts03_clone.blend"
)
SAVE_BLEND = True
# §§12–13 HexPatch IDW evaluator (SharedCorner/Ribbon + center bubble). Legacy sector path when False.
USE_HEXPATCH_SURFACE = True
# HXP-03: side-blend v1.0 S_final diagnostic path. Default off; does not replace IDW unless True.
USE_HEXPATCH_V1_SURFACE = False
# TS-02: global fair-surface / biharmonic-with-tension diagnostic path. Default off.
USE_GLOBAL_BIHARMONIC_SURFACE = False
# TS-03: thin-plate variational spline (affine-precision) path. Default off.
USE_VARIATIONAL_SPLINE_SURFACE = False
# TS-05: experimental TPS cliff-band release wrapper over variational spline. Default off.
USE_TPS_CLIFF_RELEASE = False
# TS-06: explicit cliff-front rim constraints in per-cluster TPS. Default off.
USE_TPS_RIM_CONSTRAINTS = False
# TS-07a: control clone of TS-03 variational spline (alternate output filename only). Default off.
USE_TS07A_TS03_CLONE = False
# TS-05 debug: release-region overlay collection (visualization only; does not change terrain mesh).
USE_TS05_DEBUG_OVERLAY = True
# TS-04: FEM cotan thin-plate on cliff-cut mesh. Default off.
USE_FEM_THIN_PLATE_SURFACE = False
# TS-03e: cliff wall visibility debug (rendering verification only; does not change mesh topology).
DEBUG_SHOW_CLIFF_WALLS = False
DEBUG_HIDE_TOP_SURFACE = False
CLIFF_WALL_DEBUG_MATERIAL_NAME = "EOM_Terrain_CliffWall_Debug_MidGrey"
# TS-01: optional explicit backend override; None = derive from USE_* flags at runtime.
TERRAIN_SOLVER_BACKEND: str | None = None

OUTPUT_BLEND_PATH: Path | None = None
FROZEN_BASELINE_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend"
)
# Set by run_*_blend_regen.py wrappers before main(); None when generator runs directly.
PROTOTYPE_ID: str | None = None
RUNNER_FILE: str | None = None


def _log(message: str) -> None:
    print(f"[EOM terrainmap full01] {message}")


def _candidate_start_paths() -> list[Path]:
    candidates: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        resolved = path.resolve()
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        candidates.append(resolved)

    try:
        space = bpy.context.space_data
        if space is not None and getattr(space, "text", None) is not None:
            text = space.text
            if text is not None and text.filepath:
                add(Path(bpy.path.abspath(text.filepath)))
    except Exception:
        pass

    for text in bpy.data.texts:
        if text.filepath:
            add(Path(bpy.path.abspath(text.filepath)))

    try:
        script_file = Path(__file__)
        if script_file.suffix == ".py" and script_file.exists():
            add(script_file)
    except Exception:
        pass

    if bpy.data.filepath:
        add(Path(bpy.path.abspath(bpy.data.filepath)).parent)

    add(Path.cwd())
    return candidates


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    for candidate in [start, *start.parents]:
        if (candidate / "game").is_dir() and (candidate / "tools").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate Empire of Minds repo root from: {start}")


def _resolve_repo_root() -> tuple[Path, list[Path]]:
    examined_starts = _candidate_start_paths()
    if not examined_starts:
        raise RuntimeError("No start path candidates for repo root resolution.")

    last_error: RuntimeError | None = None
    repo_root: Path | None = None
    for start in examined_starts:
        try:
            repo_root = find_repo_root(start)
            break
        except RuntimeError as exc:
            last_error = exc

    if repo_root is None:
        raise RuntimeError(f"Could not locate repo root. Last error: {last_error}")
    return repo_root, examined_starts


_TERRAIN_MATH_REQUIRED_NAMES: tuple[str, ...] = (
    "DEFAULT_HEX_RADIUS",
    "DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR",
    "DEFAULT_SURFACE_SUBDIVISIONS",
    "NEIGHBOR_DIRS",
    "shared_edge_z_at",
    "audit_smooth_edge_continuity",
    "audit_mid_edge_canonical_profile",
    "audit_transverse_spike_seams",
    "audit_center_corner_ray_artifacts",
    "audit_ssc_corner_continuity",
    "audit_summary",
    "baseline_to_handdrawn_axial",
    "build_terrain_model",
    "handdrawn_center_world_xy",
    "handdrawn_tile_at_world",
    "handdrawn_to_baseline_axial",
    "parse_terrain_map_json",
    "pos_key",
    "reset_ssc_deformation_audit",
    "sample_smooth_domain_surface_world",
    "ssc_deformation_audit",
)


_HEXPATCH_REQUIRED_NAMES: tuple[str, ...] = (
    "sample_hexpatch_surface_world",
    "audit_hexpatch_suite",
)


def _terrain_math_core_path_candidates() -> list[Path]:
    candidates: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        resolved = path.resolve()
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        candidates.append(resolved)

    if SCRIPT_DIR is not None:
        add(SCRIPT_DIR / "eom_terrain_math_core.py")

    for start in _candidate_start_paths():
        try:
            repo_root = find_repo_root(start)
            add(repo_root / "tools" / "blender" / "terrain" / "eom_terrain_math_core.py")
        except RuntimeError:
            continue

    return candidates


def _load_terrain_math_core() -> object:
    core_path: Path | None = None
    searched = _terrain_math_core_path_candidates()
    for candidate in searched:
        if candidate.is_file():
            core_path = candidate
            break

    if core_path is None:
        raise RuntimeError(
            "eom_terrain_math_core.py not found. Searched: "
            f"{', '.join(str(path) for path in searched)}. "
            "Open this script from tools/blender/terrain/ on disk."
        )

    sys.modules.pop("eom_terrain_math_core", None)
    spec = importlib.util.spec_from_file_location("eom_terrain_math_core", core_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load terrain math core from {core_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["eom_terrain_math_core"] = module
    spec.loader.exec_module(module)

    missing = [name for name in _TERRAIN_MATH_REQUIRED_NAMES if not hasattr(module, name)]
    if missing:
        raise RuntimeError(
            f"eom_terrain_math_core at {core_path} is outdated or incomplete. "
            f"Missing: {', '.join(missing)}. "
            "Use the repo copy under tools/blender/terrain/."
        )

    _log(f"terrain math core: {core_path}")
    return module


def _load_hexpatch_v1_surface(core_path: Path) -> object:
    v1_path = core_path.parent / "eom_hexpatch_v1_surface.py"
    if not v1_path.is_file():
        raise RuntimeError(f"eom_hexpatch_v1_surface.py not found beside {core_path}")

    sys.modules.pop("eom_hexpatch_v1_surface", None)
    spec = importlib.util.spec_from_file_location("eom_hexpatch_v1_surface", v1_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load hexpatch v1 surface from {v1_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["eom_hexpatch_v1_surface"] = module
    spec.loader.exec_module(module)

    for name in ("HexPatchV1SurfaceSampler",):
        if not hasattr(module, name):
            raise RuntimeError(f"eom_hexpatch_v1_surface missing {name}")
    _log(f"hexpatch v1 surface: {v1_path}")
    return module


def _load_hexpatch_v1_audits(core_path: Path) -> object:
    audits_path = core_path.parent / "eom_hexpatch_v1_audits.py"
    if not audits_path.is_file():
        raise RuntimeError(f"eom_hexpatch_v1_audits.py not found beside {core_path}")

    sys.modules.pop("eom_hexpatch_v1_audits", None)
    spec = importlib.util.spec_from_file_location("eom_hexpatch_v1_audits", audits_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load hexpatch v1 audits from {audits_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["eom_hexpatch_v1_audits"] = module
    spec.loader.exec_module(module)
    return module


def _load_hexpatch_surface(core_path: Path) -> object:
    hexpatch_path = core_path.parent / "eom_hexpatch_surface.py"
    if not hexpatch_path.is_file():
        raise RuntimeError(f"eom_hexpatch_surface.py not found beside {core_path}")

    sys.modules.pop("eom_hexpatch_surface", None)
    spec = importlib.util.spec_from_file_location("eom_hexpatch_surface", hexpatch_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load hexpatch surface from {hexpatch_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["eom_hexpatch_surface"] = module
    spec.loader.exec_module(module)

    missing = [name for name in _HEXPATCH_REQUIRED_NAMES if not hasattr(module, name)]
    if missing:
        raise RuntimeError(
            f"eom_hexpatch_surface at {hexpatch_path} is outdated or incomplete. "
            f"Missing: {', '.join(missing)}."
        )

    _log(f"hexpatch surface: {hexpatch_path}")
    return module


def _load_terrain_solver(core_path: Path) -> object:
    solver_path = core_path.parent / "eom_terrain_solver.py"
    if not solver_path.is_file():
        raise RuntimeError(f"eom_terrain_solver.py not found beside {core_path}")

    sys.modules.pop("eom_terrain_solver", None)
    spec = importlib.util.spec_from_file_location("eom_terrain_solver", solver_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load terrain solver from {solver_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["eom_terrain_solver"] = module
    spec.loader.exec_module(module)

    for name in (
        "TerrainBackend",
        "make_terrain_solver",
        "resolve_terrain_solver_backend",
        "sampler_label_for_backend",
    ):
        if not hasattr(module, name):
            raise RuntimeError(f"eom_terrain_solver missing {name}")
    _log(f"terrain solver: {solver_path}")
    return module


_terrain_math = _load_terrain_math_core()
_hexpatch_surface = _load_hexpatch_surface(
    Path(getattr(_terrain_math, "__file__", SCRIPT_DIR / "eom_terrain_math_core.py"))
)
_terrain_solver = _load_terrain_solver(
    Path(getattr(_terrain_math, "__file__", SCRIPT_DIR / "eom_terrain_math_core.py"))
)
TerrainBackend = _terrain_solver.TerrainBackend
make_terrain_solver = _terrain_solver.make_terrain_solver
resolve_terrain_solver_backend = _terrain_solver.resolve_terrain_solver_backend
sampler_label_for_backend = _terrain_solver.sampler_label_for_backend
DEFAULT_HEX_RADIUS = _terrain_math.DEFAULT_HEX_RADIUS
DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR = _terrain_math.DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR
DEFAULT_SURFACE_SUBDIVISIONS = _terrain_math.DEFAULT_SURFACE_SUBDIVISIONS
NEIGHBOR_DIRS = _terrain_math.NEIGHBOR_DIRS
shared_edge_z_at = _terrain_math.shared_edge_z_at
audit_smooth_edge_continuity = _terrain_math.audit_smooth_edge_continuity
audit_mid_edge_canonical_profile = _terrain_math.audit_mid_edge_canonical_profile
audit_transverse_spike_seams = _terrain_math.audit_transverse_spike_seams
audit_center_corner_ray_artifacts = _terrain_math.audit_center_corner_ray_artifacts
audit_ssc_corner_continuity = _terrain_math.audit_ssc_corner_continuity
audit_summary = _terrain_math.audit_summary
baseline_to_handdrawn_axial = _terrain_math.baseline_to_handdrawn_axial
build_terrain_model = _terrain_math.build_terrain_model
handdrawn_center_world_xy = _terrain_math.handdrawn_center_world_xy
handdrawn_tile_at_world = _terrain_math.handdrawn_tile_at_world
handdrawn_to_baseline_axial = _terrain_math.handdrawn_to_baseline_axial
parse_terrain_map_json = _terrain_math.parse_terrain_map_json
pos_key = _terrain_math.pos_key
reset_ssc_deformation_audit = _terrain_math.reset_ssc_deformation_audit
sample_smooth_domain_surface_world = _terrain_math.sample_smooth_domain_surface_world
sample_hexpatch_surface_world = _hexpatch_surface.sample_hexpatch_surface_world
audit_hexpatch_suite = _hexpatch_surface.audit_hexpatch_suite
ssc_deformation_audit = _terrain_math.ssc_deformation_audit


def _load_baseline_module(repo_root: Path, *, examined_starts: list[Path]) -> object:
    terrain_path = repo_root / "tools" / "blender" / "terrain" / TERRAIN_BASELINE_SCRIPT
    if not terrain_path.is_file():
        raise RuntimeError(f"Terrain baseline script not found: {terrain_path}")

    module_name = "eom_terrain_pbr_baseline_terrainmap_full01"
    spec = importlib.util.spec_from_file_location(module_name, terrain_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load baseline module from {terrain_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _assert_baseline_unchanged(baseline: object) -> None:
    if getattr(baseline, "ALLOW_BLENDER_PORTING_BASELINE_RETUNE", True):
        raise RuntimeError("Baseline retune flag must remain False")


def _baseline_neighbor_direction(from_tile: tuple[int, int], to_tile: tuple[int, int]) -> int:
    """Baseline flat-top neighbor direction between handdrawn tiles (same convention as outer-edge check)."""
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


def _build_cliff_physical_edges_by_tile(model) -> dict[tuple[int, int], frozenset[int]]:
    """Physical edge indices per tile where the neighbor across that edge is a cliff."""
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


def _is_map_outer_edge(
    q: int,
    r: int,
    edge_index: int,
    hex_coords: set[tuple[int, int]],
    baseline: object,
) -> bool:
    q_b, r_b = handdrawn_to_baseline_axial(q, r)
    direction = baseline.neighbor_direction_for_physical_edge(edge_index)
    dq, dr = NEIGHBOR_DIRS[direction]
    q_neighbor, r_neighbor = baseline_to_handdrawn_axial(q_b + dq, r_b + dr)
    return (q_neighbor, r_neighbor) not in hex_coords


def _print_curvature_influence_audit(baseline: object) -> None:
    radius = baseline.HEX_RADIUS
    baseline_hill_radius = getattr(baseline, "HILL_RADIUS", None)
    if baseline_hill_radius is not None and radius > 0.0:
        influence_radius_factor = baseline_hill_radius / radius
        approved_hill_influence_radius_world = baseline_hill_radius
    else:
        influence_radius_factor = 2.2
        approved_hill_influence_radius_world = radius * influence_radius_factor
    _log("--- curvature influence audit ---")
    _log(
        "approved 7-hex baseline hill influence: "
        f"{influence_radius_factor:.4f} * HEX_RADIUS "
        f"({approved_hill_influence_radius_world:.4f} world)"
    )
    _log(
        "prior TerrainMap analytic per-hex kernel: "
        f"{1.0:.4f} * HEX_RADIUS "
        "(center→edge within one tile)"
    )
    _log(
        "TerrainMap smooth-domain radial sampler: "
        f"{influence_radius_factor:.4f} * HEX_RADIUS "
        "(matches approved HILL_RADIUS / HEX_RADIUS)"
    )
    if baseline_hill_radius is not None and radius > 0.0:
        _log(f"baseline module HILL_RADIUS / HEX_RADIUS: {influence_radius_factor:.4f}")


def build_analytic_terrain_mesh(
    model,
    baseline: object,
    *,
    terrain_solver: object,
    split_top_at_cliff_edges: bool = True,
) -> tuple[bpy.types.Mesh, dict[str, Any]]:
    reset_ssc_deformation_audit()
    _log(f"analytic surface sampler: {sampler_label_for_backend(terrain_solver.backend)}")
    subdiv = DEFAULT_SURFACE_SUBDIVISIONS
    radius = baseline.HEX_RADIUS
    bottom_z = -baseline.BASE_THICKNESS
    hex_coords = set(model.map.tiles.keys())

    verts: list[tuple[float, float, float]] = []
    top_faces: list[tuple[int, int, int]] = []
    top_cache: dict[tuple[Any, ...], int] = {}
    merge_owner: dict[tuple[tuple[float, float], int], tuple[int, int]] = {}
    sector_grids: dict[tuple[int, int, int, int], dict[tuple[int, int], int]] = {}
    face_keys: set[tuple[int, int, int]] = set()
    height_epsilon = 1e-5
    bottom_cache: dict[tuple[float, float], int] = {}

    cliff_neighbor_pairs: set[frozenset[tuple[int, int]]] = {
        frozenset((cliff.tile_a, cliff.tile_b)) for cliff in model.cliff_edge_graph
    }
    cliff_physical_edges_by_tile = _build_cliff_physical_edges_by_tile(model)

    ts05_mesh_audit = None
    try:
        from eom_terrain_tps_cliff_release import (
            TpsCliffReleaseTerrainSolver,
            Ts05MeshSamplingAudit,
        )

        if isinstance(terrain_solver, TpsCliffReleaseTerrainSolver):
            ts05_mesh_audit = Ts05MeshSamplingAudit(
                terrain_solver,
                model,
                radius=radius,
                subdiv=subdiv,
            )
            terrain_solver.begin_mesh_sampling_audit(ts05_mesh_audit)
            ts05_mesh_audit.print_representative_cliff_ownership()
            sample_tile_key = next(iter(model.map.tiles.keys()), None)
            print(
                "TS05_MESH === TS05_MESH_COORD_CONFIRM === "
                "build_analytic_terrain_mesh passes handdrawn (q_h, r_h) to sample_world; "
                f"map.tile_key_sample={sample_tile_key!r} "
                f"key_type="
                f"{type(sample_tile_key[0]).__name__ if sample_tile_key else 'n/a'}"
            )
    except ImportError:
        pass

    def tile_cliff_physical_edges(q: int, r: int) -> frozenset[int]:
        return cliff_physical_edges_by_tile.get((q, r), frozenset())

    def _incident_physical_edges_at_sample(
        sector: int,
        *,
        at_corner: bool,
        si: int,
        sj: int,
    ) -> tuple[int, ...]:
        if at_corner:
            if si == subdiv and sj == 0:
                return ((sector - 1) % 6, sector)
            return (sector, (sector + 1) % 6)
        return ()

    def sample_on_cliff_boundary(
        q: int,
        r: int,
        sector: int,
        *,
        at_sector_outer_edge: bool,
        at_corner: bool,
        si: int,
        sj: int,
    ) -> bool:
        if not split_top_at_cliff_edges:
            return False
        cliff_edges = tile_cliff_physical_edges(q, r)
        if not cliff_edges:
            return False
        if at_sector_outer_edge and sector in cliff_edges:
            return True
        if at_corner:
            return any(
                edge in cliff_edges
                for edge in _incident_physical_edges_at_sample(
                    sector,
                    at_corner=True,
                    si=si,
                    sj=sj,
                )
            )
        return False

    def tiles_are_cliff_neighbors(
        tile_a: tuple[int, int],
        tile_b: tuple[int, int],
    ) -> bool:
        if tile_a == tile_b:
            return False
        return frozenset((tile_a, tile_b)) in cliff_neighbor_pairs

    def add_bottom_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = bottom_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, bottom_z))
        bottom_cache[key] = idx
        return idx

    def add_top_vertex(
        wx: float,
        wy: float,
        wz: float,
        domain_id: int,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_sector_corner: bool = False,
        at_sector_outer_edge: bool = False,
        si: int = 0,
        sj: int = 0,
    ) -> int:
        position_key = pos_key(wx, wy)
        if sector is not None and sample_on_cliff_boundary(
            q,
            r,
            sector,
            at_sector_outer_edge=at_sector_outer_edge,
            at_corner=at_sector_corner,
            si=si,
            sj=sj,
        ):
            cliff_side_key = (position_key, domain_id, q, r)
            cached = top_cache.get(cliff_side_key)
            if cached is not None:
                return cached
            idx = len(verts)
            verts.append((wx, wy, wz))
            top_cache[cliff_side_key] = idx
            return idx

        if split_top_at_cliff_edges:
            merge_key: tuple[Any, ...] = (position_key, domain_id)
        else:
            merge_key = (position_key,)
        if at_sector_corner and sector is not None:
            if split_top_at_cliff_edges:
                tile_key: tuple[Any, ...] = (position_key, domain_id, q, r, sector)
            else:
                tile_key = (position_key, q, r, sector)
        else:
            if split_top_at_cliff_edges:
                tile_key = (position_key, domain_id, q, r)
            else:
                tile_key = (position_key, q, r)

        cached_tile = top_cache.get(tile_key)
        if cached_tile is not None:
            return cached_tile

        cached_merge = top_cache.get(merge_key)
        if cached_merge is not None:
            owner = merge_owner.get(merge_key)
            allow_merge = (
                not split_top_at_cliff_edges
                or owner is None
                or not tiles_are_cliff_neighbors((q, r), owner)
            )
            if allow_merge and abs(verts[cached_merge][2] - wz) <= height_epsilon:
                    top_cache[tile_key] = cached_merge
                    return cached_merge

        idx = len(verts)
        verts.append((wx, wy, wz))
        top_cache[tile_key] = idx
        if cached_merge is None:
            top_cache[merge_key] = idx
            merge_owner[merge_key] = (q, r)
        return idx

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        domain_id = model.tile_domain[(q_h, r_h)]
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)

        for sector in range(6):
            grid: dict[tuple[int, int], int] = {}
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = baseline.sector_barycentric_xy(
                        sector,
                        si,
                        sj,
                        subdiv,
                    )
                    wx = cx + lx
                    wy = cy + ly
                    at_corner = (si == subdiv and sj == 0) or (si == 0 and sj == subdiv)
                    at_outer = si + sj == subdiv
                    sample_kwargs: dict[str, Any] = {
                        "sector": sector,
                        "at_corner": at_corner,
                        "at_sector_outer_edge": at_outer,
                    }
                    if ts05_mesh_audit is not None:
                        sample_kwargs["mesh_si"] = si
                        sample_kwargs["mesh_sj"] = sj
                    wz = terrain_solver.sample_world(
                        wx,
                        wy,
                        q_h,
                        r_h,
                        **sample_kwargs,
                    )
                    vertex_id = add_top_vertex(
                        wx,
                        wy,
                        wz,
                        domain_id,
                        q_h,
                        r_h,
                        sector=sector,
                        at_sector_corner=at_corner,
                        at_sector_outer_edge=at_outer,
                        si=si,
                        sj=sj,
                    )
                    grid[(si, sj)] = vertex_id
                    if ts05_mesh_audit is not None:
                        ts05_mesh_audit.attach_rim_vertex_id(
                            q_h,
                            r_h,
                            sector,
                            si,
                            sj,
                            at_outer,
                            vertex_id,
                        )
                    sj += 1
            sector_grids[(q_h, r_h, domain_id, sector)] = grid

            for si in range(subdiv):
                sj = 0
                while sj <= subdiv - si - 1:
                    v00 = grid[(si, sj)]
                    v10 = grid[(si + 1, sj)]
                    v01 = grid[(si, sj + 1)]
                    wound = baseline.orient_upward_triangle(verts, v00, v10, v01)
                    key = tuple(sorted(wound))
                    if key not in face_keys:
                        face_keys.add(key)
                        top_faces.append(wound)
                    if sj + 1 <= subdiv - (si + 1):
                        v11 = grid[(si + 1, sj + 1)]
                        wound = baseline.orient_upward_triangle(verts, v10, v01, v11)
                        key = tuple(sorted(wound))
                        if key not in face_keys:
                            face_keys.add(key)
                            top_faces.append(wound)
                    sj += 1

    baseline.validate_top_face_winding(verts, top_faces)

    cliff_wall_faces: list[tuple[int, ...]] = []
    cliff_wall_face_keys: set[tuple[int, ...]] = set()
    cliff_wall_verts_before = len(verts)
    cliff_edges_filled = 0
    cliff_segments_filled = 0
    cliff_segments_skipped = 0

    def add_cliff_wall_face(*indices: int) -> None:
        if len(indices) == 4:
            key = tuple(sorted(indices))
        else:
            key = tuple(indices)
        if key in cliff_wall_face_keys:
            return
        cliff_wall_face_keys.add(key)
        cliff_wall_faces.append(indices)

    for cliff in model.cliff_edge_graph:
        tile_a = cliff.tile_a
        tile_b = cliff.tile_b
        domain_a = cliff.domain_a
        domain_b = cliff.domain_b
        direction = _baseline_neighbor_direction(tile_a, tile_b)
        edge_index = _physical_edge_for_baseline_neighbor(direction)
        grid_a = sector_grids[(tile_a[0], tile_a[1], domain_a, edge_index)]
        direction_b = _baseline_neighbor_direction(tile_b, tile_a)
        edge_index_b = _physical_edge_for_baseline_neighbor(direction_b)
        grid_b = sector_grids[(tile_b[0], tile_b[1], domain_b, edge_index_b)]
        indices_a = baseline.outer_edge_grid_indices(grid_a, subdiv)
        indices_b = list(reversed(baseline.outer_edge_grid_indices(grid_b, subdiv)))

        if len(indices_a) != len(indices_b):
            raise RuntimeError(
                f"cliff edge grid mismatch {tile_a}<->{tile_b}: "
                f"{len(indices_a)} vs {len(indices_b)}"
            )

        edge_filled = False
        z_avg_a = sum(verts[i][2] for i in indices_a) / float(len(indices_a))
        z_avg_b = sum(verts[i][2] for i in indices_b) / float(len(indices_b))
        lower_is_b = z_avg_b < z_avg_a

        for seg in range(len(indices_a) - 1):
            a0 = indices_a[seg]
            a1 = indices_a[seg + 1]
            b0 = indices_b[seg]
            b1 = indices_b[seg + 1]
            if a0 == b0 and a1 == b1:
                cliff_segments_skipped += 1
                continue

            z_vals = (verts[a0][2], verts[a1][2], verts[b0][2], verts[b1][2])
            if max(z_vals) - min(z_vals) < height_epsilon:
                cliff_segments_skipped += 1
                continue

            add_cliff_wall_face(a0, a1, b1, b0)

            if lower_is_b:
                lo0, lo1 = b0, b1
            else:
                lo0, lo1 = a0, a1
            bot_lo0 = add_bottom_vertex(verts[lo0][0], verts[lo0][1])
            bot_lo1 = add_bottom_vertex(verts[lo1][0], verts[lo1][1])
            add_cliff_wall_face(lo0, lo1, bot_lo1, bot_lo0)
            cliff_segments_filled += 1
            edge_filled = True

        if edge_filled:
            cliff_edges_filled += 1

    perimeter_segments: list[list[int]] = []
    segment_edge_t: list[list[float]] = []
    perimeter_pos_cache: dict[tuple[float, float], int] = {}

    def canonical_perimeter_index(vertex_index: int) -> int:
        wx, wy, _wz = verts[vertex_index]
        key = pos_key(wx, wy)
        existing = perimeter_pos_cache.get(key)
        if existing is not None:
            return existing
        perimeter_pos_cache[key] = vertex_index
        return vertex_index

    for q_h, r_h in sorted(hex_coords):
        for edge_index in range(6):
            if not _is_map_outer_edge(q_h, r_h, edge_index, hex_coords, baseline):
                continue
            domain_id = model.tile_domain[(q_h, r_h)]
            grid = sector_grids[(q_h, r_h, domain_id, edge_index)]
            indices = [
                canonical_perimeter_index(index)
                for index in baseline.outer_edge_grid_indices(grid, subdiv)
            ]
            edge_ts = [float(step_k) / float(subdiv) for step_k in range(subdiv + 1)]
            perimeter_segments.append(indices)
            segment_edge_t.append(edge_ts)

    perimeter_loop = baseline.chain_perimeter_segments(perimeter_segments)
    _log(f"perimeter validation passed: {len(perimeter_loop)} ordered top vertices")

    rim_cache: dict[tuple[float, float], int] = {}
    skirt_faces: list[tuple[int, ...]] = []
    chamfer_faces: list[tuple[int, ...]] = []

    def add_rim_vertex(wx: float, wy: float, top_z: float, edge_t: float) -> int:
        key = pos_key(wx, wy)
        cached = rim_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, baseline.compute_rim_z(top_z, edge_t)))
        rim_cache[key] = idx
        return idx

    top_to_edge_t: dict[int, float] = {}
    for segment, edge_ts in zip(perimeter_segments, segment_edge_t):
        for vtx, edge_t in zip(segment, edge_ts):
            if vtx not in top_to_edge_t:
                top_to_edge_t[vtx] = edge_t

    loop_count = len(perimeter_loop)
    for i in range(loop_count):
        top_a = perimeter_loop[i]
        top_b = perimeter_loop[(i + 1) % loop_count]
        wx_a, wy_a, wz_a = verts[top_a]
        wx_b, wy_b, wz_b = verts[top_b]
        edge_t_a = top_to_edge_t.get(top_a, 0.0)
        edge_t_b = top_to_edge_t.get(top_b, 0.0)

        rim_a = add_rim_vertex(wx_a, wy_a, wz_a, edge_t_a)
        rim_b = add_rim_vertex(wx_b, wy_b, wz_b, edge_t_b)
        bot_a = add_bottom_vertex(wx_a, wy_a)
        bot_b = add_bottom_vertex(wx_b, wy_b)

        if baseline.OUTER_RIM_DROP > 0.0 and rim_a != top_a:
            chamfer_faces.append((top_a, top_b, rim_b, rim_a))
            skirt_faces.append((rim_a, rim_b, bot_b, bot_a))
        else:
            skirt_faces.append((top_a, top_b, bot_b, bot_a))

    centers = [handdrawn_center_world_xy(q, r, radius) for q, r in hex_coords]
    patch_cx = sum(x for x, _y in centers) / float(len(centers))
    patch_cy = sum(y for _x, y in centers) / float(len(centers))
    center_bottom = len(verts)
    verts.append((patch_cx, patch_cy, bottom_z))

    bottom_faces: list[tuple[int, int, int]] = []
    for i in range(loop_count):
        bot_a = bottom_cache[pos_key(verts[perimeter_loop[i]][0], verts[perimeter_loop[i]][1])]
        bot_b = bottom_cache[
            pos_key(
                verts[perimeter_loop[(i + 1) % loop_count]][0],
                verts[perimeter_loop[(i + 1) % loop_count]][1],
            )
        ]
        bottom_faces.append((center_bottom, bot_b, bot_a))

    skirt_face_count = len(skirt_faces)
    chamfer_face_count = len(chamfer_faces)
    cliff_wall_quad_count = len(cliff_wall_faces)
    top_face_count = len(top_faces)
    cliff_wall_poly_start = top_face_count + skirt_face_count + chamfer_face_count
    side_face_count = skirt_face_count + chamfer_face_count + cliff_wall_quad_count
    bottom_face_count = len(bottom_faces)
    all_faces = top_faces + skirt_faces + chamfer_faces + cliff_wall_faces + bottom_faces
    cliff_wall_vertex_indices = sorted({v for face in cliff_wall_faces for v in face})

    mesh = bpy.data.meshes.new("TerrainMapFull01")
    mesh.from_pydata(verts, [], all_faces)
    baseline.apply_patch_shading(mesh, top_face_count, side_face_count)
    baseline._finalize_mesh(mesh)

    stats = {
        "top_verts": len(set(top_cache.values())),
        "top_faces": top_face_count,
        "cliff_wall_faces": cliff_wall_quad_count,
        "cliff_wall_quads": cliff_wall_quad_count,
        "cliff_wall_poly_start": cliff_wall_poly_start,
        "cliff_wall_poly_count": cliff_wall_quad_count,
        "cliff_wall_vertex_indices": cliff_wall_vertex_indices,
        "cliff_wall_verts": len(cliff_wall_vertex_indices),
        "cliff_wall_new_verts": len(verts) - cliff_wall_verts_before,
        "skirt_face_count": skirt_face_count,
        "chamfer_face_count": chamfer_face_count,
        "cliff_edges_filled": cliff_edges_filled,
        "cliff_segments_filled": cliff_segments_filled,
        "cliff_segments_skipped": cliff_segments_skipped,
        "side_faces": side_face_count,
        "bottom_faces": bottom_face_count,
        "perimeter_verts": len(perimeter_loop),
        "total_verts": len(verts),
        "total_faces": len(all_faces),
        "ssc_deformation": ssc_deformation_audit(),
    }
    solver_stats = terrain_solver.stats
    if solver_stats is not None:
        if terrain_solver.backend.value == "hexpatch_v1":
            stats["hexpatch_v1_sample_stats"] = solver_stats
        elif terrain_solver.backend.value == "global_biharmonic":
            stats["global_biharmonic_stats"] = solver_stats
        elif terrain_solver.backend.value == "variational_spline":
            stats["variational_spline_stats"] = solver_stats
        elif terrain_solver.backend.value == "fem_thin_plate":
            stats["fem_thin_plate_stats"] = solver_stats
    if ts05_mesh_audit is not None:
        terrain_solver.finish_mesh_sampling_audit()
    return mesh, stats


def build_hex_overlay_mesh(model, baseline: object) -> tuple[bpy.types.Mesh, dict[str, int]]:
    subdiv = DEFAULT_SURFACE_SUBDIVISIONS
    radius = baseline.HEX_RADIUS
    hex_coords = set(model.map.tiles.keys())
    seen_edges: set[tuple[tuple[float, float], tuple[float, float]]] = set()
    verts: list[tuple[float, float, float]] = []
    edges: list[tuple[int, int]] = []
    vert_cache: dict[tuple[float, float], int] = {}

    def sample_overlay_z(wx: float, wy: float) -> float:
        tile = handdrawn_tile_at_world(wx, wy, model, radius=radius)
        if tile is None:
            return baseline.BASE_HEIGHT
        q_h, r_h = tile
        return (
            sample_smooth_domain_surface_world(wx, wy, q_h, r_h, model, radius=radius)
            + baseline.HEX_OVERLAY_HEIGHT_OFFSET
        )

    def add_overlay_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = vert_cache.get(key)
        if cached is not None:
            return cached
        wz = sample_overlay_z(wx, wy)
        idx = len(verts)
        verts.append((wx, wy, wz))
        vert_cache[key] = idx
        return idx

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        for edge_index in range(6):
            edge_key = baseline.unique_edge_key(q_b, r_b, edge_index)
            if edge_key in seen_edges:
                continue
            seen_edges.add(edge_key)

            ci = edge_index
            cj = (edge_index + 1) % 6
            bx, by = baseline.corner_xy_local(ci, radius)
            cx_corner, cy_corner = baseline.corner_xy_local(cj, radius)
            prev_idx: int | None = None
            for step_k in range(subdiv + 1):
                wb = float(subdiv - step_k) / float(subdiv)
                wc = float(step_k) / float(subdiv)
                wx = cx + wb * bx + wc * cx_corner
                wy = cy + wb * by + wc * cy_corner
                vtx = add_overlay_vertex(wx, wy)
                if prev_idx is not None:
                    edges.append((prev_idx, vtx))
                prev_idx = vtx

    mesh = bpy.data.meshes.new("HexOverlay")
    mesh.from_pydata(verts, edges, [])
    baseline._finalize_mesh(mesh)
    return mesh, {"unique_edges": len(seen_edges), "overlay_verts": len(verts), "overlay_edges": len(edges)}


def _print_orientation_audit() -> None:
    radius = DEFAULT_HEX_RADIUS
    anchors = ((0, 0), (1, 0), (0, 1))
    world = {tile: handdrawn_center_world_xy(*tile, radius) for tile in anchors}
    x00, y00 = world[(0, 0)]
    x10, y10 = world[(1, 0)]
    x01, y01 = world[(0, 1)]
    _log("--- coordinate orientation audit ---")
    _log(f"world XY (0,0): ({x00:.6f}, {y00:.6f})")
    _log(f"world XY (1,0): ({x10:.6f}, {y10:.6f})")
    _log(f"world XY (0,1): ({x01:.6f}, {y01:.6f})")
    if not (x10 > x00 and abs(y10 - y00) < 1e-6 and x01 > x00 and y01 < y00):
        raise RuntimeError("handdrawn coordinate orientation audit failed")


def _print_model_audit(model, output_path: Path) -> None:
    summary = audit_summary(model)
    _log("--- terrain model audit ---")
    _log(f"map id: {summary['map_id']}")
    _log(f"tile count: {summary['tile_count']}")
    _log(f"q bounds: [{summary['q_bounds'][0]}, {summary['q_bounds'][1]}]")
    _log(f"r bounds: [{summary['r_bounds'][0]}, {summary['r_bounds'][1]}]")
    _log(f"elevation min/max: [{summary['elevation_min_max'][0]}, {summary['elevation_min_max'][1]}]")
    _log(f"smooth edge count: {summary['smooth_edge_count']}")
    _log(f"cliff edge count: {summary['cliff_edge_count']}")
    _log(f"smoothing domain count: {summary['smoothing_domain_count']}")
    _log(f"corner height entries: {summary['corner_height_count']}")
    _log(f"output path: {output_path}")
    _log("--- cliff-edge graph summary ---")
    for record in model.cliff_edge_graph:
        _log(
            "cliff edge: "
            f"{record.tile_a} elev {record.elevation_a} (domain {record.domain_a}) "
            f"<-> {record.tile_b} elev {record.elevation_b} (domain {record.domain_b}) "
            f"delta {record.delta}"
        )


def _print_ssc_corner_audit(model) -> None:
    _log("--- SSC mixed-corner audit ---")
    _log(f"SSC deformation radius factor: {DEFAULT_SSC_DEFORMATION_RADIUS_FACTOR:.4f} of HEX_RADIUS")
    _log(f"detected SSC corners: {len(model.ssc_corners)}")
    for record in model.ssc_corners:
        _log(
            "SSC corner: "
            f"world {record.corner_world} "
            f"cliff {record.cliff_a} <-> {record.cliff_b} "
            f"bridge {record.bridge} "
            f"corner_bc_z {record.target_z:.4f}"
        )

    continuity = audit_ssc_corner_continuity(model, radius=DEFAULT_HEX_RADIUS)
    _log("--- SSC corner continuity audit ---")
    _log(f"SSC corners checked: {continuity['corner_count']}")
    _log(f"passed: {continuity['passed_count']}")
    _log(f"failed: {continuity['failure_count']}")

    if continuity["continuity_ok"]:
        _log("SSC corner continuity: OK")
        return

    _log("SSC corner continuity: FAILED")
    for index, failure in enumerate(continuity["failures"], start=1):
        _log(f"--- SSC continuity failure {index}/{continuity['failure_count']} ---")
        _log(f"corner world XY: {failure['corner_world']}")
        _log(f"corner key (pos_key): {failure['corner_key']}")
        _log(f"corner_bc_z (target): {failure['corner_bc_z']:.6f}")
        _log(f"height spread (max-min): {failure['height_spread']:.6e}")

        topology = failure["topology"]
        _log("incident tiles:")
        for tile_info in topology["incident_tiles"]:
            _log(
                f"  tile {tile_info['tile']} "
                f"elevation {tile_info['elevation']} "
                f"world_z {tile_info['world_z']:.4f} "
                f"role {tile_info['role']} "
                f"corner_index {tile_info['corner_index']}"
            )

        cliff = topology["cliff_pair"]
        _log(
            "cliff pair: "
            f"{cliff['tile_a']} (elev {cliff['elevation_a']}) "
            f"<-> {cliff['tile_b']} (elev {cliff['elevation_b']}) "
            f"delta {cliff['delta']}"
        )
        _log("smooth pairs:")
        for pair in topology["smooth_pairs"]:
            _log(
                f"  {pair['tile_a']} (elev {pair['elevation_a']}) "
                f"<-> {pair['tile_b']} (elev {pair['elevation_b']}) "
                f"delta {pair['delta']}"
            )
        _log(f"bridge tile: {topology['bridge']}")

        if failure["excluded_sector_reports"]:
            _log("excluded sectors (deformation intentionally skipped):")
            for excluded in failure["excluded_sector_reports"]:
                _log(
                    f"  tile {excluded['tile']} sector {excluded['sector']} "
                    f"corner_index {excluded['corner_index']} "
                    f"cliff_sector {excluded['cliff_sector']} "
                    f"reason: {excluded['reason']}"
                )

        _log("participating smooth sector samples:")
        for sample in failure["participating_sample_reports"]:
            tq, tr = sample["tile"]
            _log(
                f"  tile ({tq},{tr}) elev {sample['elevation']} role {sample['tile_role']} "
                f"corner_index {sample['corner_index']} sector {sample['sector']} "
                f"sector_corner_vertex {sample['sector_corner_vertex']}"
            )
            _log(
                f"    sample_world_xy {sample['sample_world_xy']} "
                f"computed_corner_xy {sample['computed_corner_xy']} "
                f"computed_corner_key {sample['computed_corner_key']}"
            )
            _log(
                f"    ssc_corner_key {sample['ssc_corner_key']} "
                f"corner_key_matches {sample['corner_key_matches']} "
                f"local_xy {sample['local_xy']} "
                f"dist_to_ssc_corner {sample['dist_to_ssc_corner']:.6e}"
            )
            _log(
                f"    at_sector_corner_input {sample['at_sector_corner_input']} "
                f"at_sector_corner_detected {sample['at_sector_corner_detected']} "
                f"at_this_ssc_corner {sample['at_this_ssc_corner']}"
            )
            _log(
                f"    radial_base_height {sample['radial_base_height']:.6f} "
                f"corner_bc_z {sample['corner_bc_z']:.6f} "
                f"sampled_height {sample['sampled_height']:.6f}"
            )
            _log(
                f"    expected_height {sample['expected_height']:.6f} "
                f"error_from_corner_bc_z {sample['error_from_corner_bc_z']:.6e} "
                f"error_from_expected {sample['error_from_expected']:.6e}"
            )
            _log(
                f"    deformation_applied {sample['deformation_applied']} "
                f"mode {sample['deformation_mode']} "
                f"falloff_weight {sample['falloff_weight']:.6f} "
                f"zone_radius {sample['deformation_zone_radius']:.6f}"
            )
            if sample["deformation_skip_reason"]:
                _log(f"    deformation_skip_reason: {sample['deformation_skip_reason']}")
            if sample["cliff_sector_excluded"] is not None:
                _log(f"    cliff_sector_excluded {sample['cliff_sector_excluded']}")

    raise RuntimeError(
        f"SSC corner continuity audit failed: {continuity['failure_count']} of "
        f"{continuity['corner_count']} corners (see log above for per-corner detail)"
    )


def _print_smooth_edge_audit(model) -> None:
    _log("--- smooth-edge continuity audit ---")
    audit = audit_smooth_edge_continuity(
        model,
        radius=DEFAULT_HEX_RADIUS,
        subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
    )
    _log(f"smooth edges checked: {audit['smooth_edge_count']}")
    _log(f"height epsilon: {audit['height_epsilon']:.6e}")
    _log(f"subdiv sample points per edge: {audit['subdiv'] + 1}")
    _log(f"global max abs Z diff: {audit['global_max_abs_z_diff']:.6e}")
    _log(f"mismatch count (diff > epsilon): {audit['mismatch_count']}")
    _log("category counts:")
    for category, count in sorted(audit["category_counts"].items()):
        _log(f"  {category}: {count}")
    _log(
        "note: hex overlay draws a line above every hex edge (HEX_OVERLAY_HEIGHT_OFFSET); "
        "a bright line at an edge may be overlay, not a surface Z split. "
        "This audit Z-diff is the source of truth for an actual top-surface gap."
    )
    if audit["mismatch_count"] == 0:
        _log("smooth-edge continuity: all edges within epsilon")
        return

    _log(f"worst smooth edges (top {len(audit['worst_edges'])}):")
    for index, edge in enumerate(audit["worst_edges"], start=1):
        if edge["max_abs_z_diff"] <= audit["height_epsilon"]:
            break
        endpoint_a = edge["endpoint_a"]
        endpoint_b = edge["endpoint_b"]
        _log(
            f"  {index}. {edge['tile_a']} (elev {edge['elevation_a']}) "
            f"<-> {edge['tile_b']} (elev {edge['elevation_b']}) "
            f"delta {edge['delta']} "
            f"category {edge['category']}"
        )
        _log(
            f"     physical edges: {edge['physical_edge_a']} / {edge['physical_edge_b']} "
            f"max abs Z diff {edge['max_abs_z_diff']:.6e} "
            f"peak at subdiv {edge['peak_subdiv_index']} "
            f"world {edge['peak_world_xy']} "
            f"peak_at_endpoint {edge['peak_at_endpoint']} "
            f"touches_ssc {edge['touches_ssc']}"
        )
        _log(
            f"     peak Z: tile_a {edge['peak_z_a']:.6f} tile_b {edge['peak_z_b']:.6f}"
        )
        _log(
            f"     endpoint_a {endpoint_a['corner_world']} "
            f"touching {endpoint_a['touching_count']} "
            f"cliff_pairs {endpoint_a['cliff_pair_count']} "
            f"is_ssc {endpoint_a['is_ssc']} "
            f"is_perimeter {endpoint_a['is_perimeter']}"
        )
        _log(
            f"     endpoint_b {endpoint_b['corner_world']} "
            f"touching {endpoint_b['touching_count']} "
            f"cliff_pairs {endpoint_b['cliff_pair_count']} "
            f"is_ssc {endpoint_b['is_ssc']} "
            f"is_perimeter {endpoint_b['is_perimeter']}"
        )


def _print_mid_edge_invariant_audit(model) -> None:
    _log("--- mid-edge canonical profile audit (§11 sector patch) ---")
    audit = audit_mid_edge_canonical_profile(
        model,
        radius=DEFAULT_HEX_RADIUS,
        subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
    )
    _log(f"smooth edges checked: {audit['smooth_edge_count']}")
    _log(f"median samples checked: {audit['sample_count']}")
    _log(f"height epsilon: {audit['height_epsilon']:.6e}")
    _log(f"global max deviation: {audit['global_max_deviation']:.6e}")
    _log(f"profile ok: {audit['profile_ok']}")
    _log(f"midpoint tile agreement ok: {audit['midpoint_tile_agreement_ok']}")
    if audit["invariant_ok"]:
        _log("mid-edge invariant: all medians match canonical 7-hex reference")
        return
    if audit["midpoint_tile_mismatches"]:
        _log(f"midpoint tile mismatches: {len(audit['midpoint_tile_mismatches'])}")
        for row in audit["midpoint_tile_mismatches"][:5]:
            _log(
                f"  {row['tile_a']} <-> {row['tile_b']} delta {row['delta']} "
                f"world {row['world_xy']} diff {row['abs_diff']:.6e}"
            )
    if audit["worst_profile_failures"]:
        _log(f"profile failures (top {len(audit['worst_profile_failures'])}):")
        for row in audit["worst_profile_failures"][:5]:
            _log(
                f"  tile {row['tile']} neighbor {row['neighbor']} u {row['u']:.3f} "
                f"deviation {row['abs_deviation']:.6e}"
            )


def _print_transverse_spike_audit(model) -> None:
    _log("--- transverse spike seam audit (§11 sector patch) ---")
    audit = audit_transverse_spike_seams(
        model,
        radius=DEFAULT_HEX_RADIUS,
        subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
    )
    _log(f"sample pairs checked: {audit['sample_pairs']}")
    _log(f"global max spike: {audit['global_max_spike']:.6e}")
    _log(
        "note: pre-sector-field baseline ~0.07-0.08 on delta-1 edges; "
        "lower is better (needle-ridge indicator)"
    )
    for row in audit["worst_spikes"][:5]:
        _log(
            f"  tile {row['tile']} sector {row['sector']} step {row['median_step']} "
            f"transverse {row['transverse']} spike {row['abs_spike']:.6e} "
            f"Z {row['z_median']:.6f} vs {row['z_transverse']:.6f}"
        )


def _print_center_corner_ray_audit(model) -> None:
    _log("--- center→corner ray artifact audit (§11 sector patch) ---")
    audit = audit_center_corner_ray_artifacts(
        model,
        radius=DEFAULT_HEX_RADIUS,
        subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
    )
    _log(f"sample pairs checked: {audit['sample_pairs']}")
    _log(f"global max star-shell asymmetry: {audit['global_max_star_shell']:.6e}")
    _log(
        f"global max side-radial decouple: {audit['global_max_side_radial_decouple']:.6e}"
    )
    _log(f"side curve exact: {audit['side_curve_ok']}")
    _log(
        "note: side-radial decouple > 0 confirms side lines no longer follow legacy kernel; "
        "lower star-shell asymmetry vs old radial+correction field is the visual goal"
    )
    for row in audit["worst_star_shells"][:5]:
        _log(
            f"  tile {row['tile']} sector {row['sector']} step {row['radial_step']} "
            f"star {row['star_shell_asymmetry']:.6e} "
            f"side-radial {row['side_radial_decouple']:.6e}"
        )


def _print_hexpatch_audit(model) -> None:
    _log("--- HexPatch/Ribbon audit (TERRAIN_MODEL §§12–13 IDW) ---")
    _log(f"surface sampler: {'hexpatch IDW' if USE_HEXPATCH_SURFACE else 'legacy sector/radial'}")
    audit = audit_hexpatch_suite(
        model,
        radius=DEFAULT_HEX_RADIUS,
        subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
    )
    se = audit["smooth_edge_height"]
    _log(
        f"smooth-edge height mismatch: max {se.get('global_max_abs_z_diff', 0.0):.6e} "
        f"ok={se['ok']}"
    )
    g1 = audit["g1_ribbons"]
    _log(f"G1 ribbon cross-edge slope diff max: {g1['global_max_slope_diff']:.6e} ok={g1['ok']}")
    br = audit["boundary_reproduction"]
    _log(f"boundary reproduction max error: {br['global_max_abs_error']:.6e} ok={br['ok']}")
    cd = audit["cross_derivative"]
    _log(f"cross-derivative reproduction max error: {cd['global_max_abs_error']:.6e} ok={cd['ok']}")
    cen = audit["center"]
    _log(
        f"center exact after bubble: ok={cen['ok']} "
        f"drift before bubble max={cen.get('drift_max', 0.0):.6f} "
        f"mean={cen.get('drift_mean', 0.0):.6f} "
        f"warn_count={cen.get('drift_warn_count', 0)}"
    )
    ns = audit["no_spoke"]
    _log(
        f"no-spoke derivative discontinuity max: {ns['global_max_derivative_discontinuity']:.6e} "
        f"ok={ns['ok']} "
        "(informational; former sector boundaries may still show curvature seams)"
    )


def _print_hexpatch_v1_visual_audit(model, v1_audits: object) -> None:
    graph = model.hexpatch_v1_graph
    if graph is None:
        raise RuntimeError("hexpatch_v1_graph missing on TerrainModel")
    _log("--- HexPatch v1.0 contract audit (HXP-02b visual gate) ---")
    report = v1_audits.audit_hexpatch_v1_suite(model, graph, radius=DEFAULT_HEX_RADIUS)
    _log(v1_audits.format_hexpatch_v1_audit_report(report, fixture_name="handdrawn_full_168_tiles"))
    gate = v1_audits.audit_hexpatch_v1_visual_gate(report)
    _log(v1_audits.format_hexpatch_v1_visual_gate_report(gate))
    if not gate["ok"]:
        raise RuntimeError(
            "HexPatch v1 visual gate failed before regeneration: "
            f"{gate['failures']}"
        )


def _print_hxp03_diagnostic_report(
    *,
    output_path: Path,
    sample_stats: dict[str, int] | None,
) -> None:
    _log("--- HXP-03 HexPatch v1 diagnostic report ---")
    _log(f"USE_HEXPATCH_V1_SURFACE: {USE_HEXPATCH_V1_SURFACE}")
    _log(f"USE_HEXPATCH_SURFACE (IDW default path when v1 off): {USE_HEXPATCH_SURFACE}")
    _log(f"IDW path unchanged when v1 toggle False: {not USE_HEXPATCH_V1_SURFACE}")
    _log(f"blend output path: {output_path}")
    if sample_stats is not None:
        _log(
            "top-surface sample routing: "
            f"v1 S_final={sample_stats.get('hexpatch_v1_total', 0)} "
            f"(all-smooth={sample_stats.get('hexpatch_v1_smooth', 0)} "
            f"mixed-interior={sample_stats.get('hexpatch_v1_mixed_interior', 0)}) "
            f"cliff IDW fallback={sample_stats.get('cliff_fallback_idw', 0)} "
            f"cliff legacy fallback={sample_stats.get('cliff_fallback_legacy', 0)} "
            f"total={sample_stats.get('total', 0)}"
        )
    _log(
        "visual-risk notes: "
        "cliff-adjacent tiles use IDW fallback (Cliff Model v1 deferred); "
        "H3 corner height exact on vertices, gradient jet report-only; "
        "center bubble may dominate where pre-bubble drift is large; "
        "compare against terrain_handdrawn_test_map_full_01.blend (IDW) side-by-side."
    )


def _print_global_biharmonic_diagnostic_report(
    *,
    output_path: Path,
    solve_stats: dict[str, Any] | None,
) -> None:
    _log("--- TS-02 GlobalBiharmonic diagnostic report ---")
    _log(f"USE_GLOBAL_BIHARMONIC_SURFACE: {USE_GLOBAL_BIHARMONIC_SURFACE}")
    _log(f"blend output path: {output_path}")
    if solve_stats is not None:
        _log(f"backend: global_biharmonic (tension={solve_stats.get('tension', 0.0)})")
        _log(f"node_count: {solve_stats.get('node_count', 0)}")
        _log(f"component_count: {solve_stats.get('component_count', 0)}")
        _log(f"pinned_center_count: {solve_stats.get('pinned_center_count', 0)}")
        _log(f"free_boundary_count: {solve_stats.get('free_boundary_count', 0)}")
        _log(f"iteration_count: {solve_stats.get('iteration_count', 0)}")
        _log(f"final_max_update: {solve_stats.get('final_max_update', 0.0)}")
        _log(
            "max_center_constraint_error: "
            f"{solve_stats.get('max_center_constraint_error', 0.0)}"
        )
        _log(f"z_min: {solve_stats.get('z_min', 0.0)}")
        _log(f"z_max: {solve_stats.get('z_max', 0.0)}")
        warnings = solve_stats.get("warnings") or []
        if warnings:
            _log(f"warnings: {'; '.join(warnings)}")
    _log(
        "visual-risk notes: "
        "iterative fair-surface prototype (not exact sparse biharmonic); "
        "cliff/perimeter nodes are free natural boundaries; "
        "compare against terrain_handdrawn_test_map_full_01.blend (IDW) side-by-side."
    )


def _print_variational_spline_diagnostic_report(
    *,
    output_path: Path,
    solve_stats: dict[str, Any] | None,
) -> None:
    _log("--- TS-03 VariationalSpline diagnostic report ---")
    _log(f"USE_VARIATIONAL_SPLINE_SURFACE: {USE_VARIATIONAL_SPLINE_SURFACE}")
    _log(f"blend output path: {output_path}")
    if solve_stats is not None:
        _log(f"backend: {solve_stats.get('backend', 'variational_spline')}")
        _log(
            f"cliff_cut_field_count: {solve_stats.get('cliff_cut_field_count', solve_stats.get('component_count', 0))}"
        )
        _log(f"component_count: {solve_stats.get('component_count', 0)}")
        for comp in solve_stats.get("components") or []:
            _log(
                "  field "
                f"{comp.get('domain_id')}: centers={comp.get('center_count')}, "
                f"matrix_size={comp.get('matrix_size')}, kind={comp.get('kind')}, "
                f"residual={comp.get('solve_residual')}, "
                f"max_center_error={comp.get('max_center_error')}"
            )
        cliff = solve_stats.get("representative_cliff")
        if cliff is not None:
            _log("--- TS-03d representative cliff (4,0) <-> (5,0) ---")
            _log(f"lower tile center Z: {cliff.get('lower_center_z')} (tile {cliff.get('lower_tile')})")
            _log(f"upper tile center Z: {cliff.get('upper_center_z')} (tile {cliff.get('upper_tile')})")
            _log(f"lower rim midpoint Z: {cliff.get('lower_rim_mid_z')}")
            _log(f"upper rim midpoint Z: {cliff.get('upper_rim_mid_z')}")
            _log(f"rim Z gap: {cliff.get('rim_z_gap')}")
            _log(f"expected canonical gap: {cliff.get('expected_canonical_gap')}")
            _log(f"distinct solver fields: {cliff.get('used_distinct_fields')}")
            _log(
                f"field ids: lower={cliff.get('lower_field_id')} "
                f"upper={cliff.get('upper_field_id')}"
            )
        _log(
            "max_center_interpolation_error: "
            f"{solve_stats.get('max_center_interpolation_error', 0.0)}"
        )
        _log(f"max_solve_residual: {solve_stats.get('max_solve_residual', 0.0)}")
        _log(
            "affine_constant_ok: "
            f"{solve_stats.get('affine_constant_ok')} "
            f"(max_error={solve_stats.get('affine_constant_max_error', 0.0)})"
        )
        _log(
            "affine_planar_ok: "
            f"{solve_stats.get('affine_planar_ok')} "
            f"(max_error={solve_stats.get('affine_planar_max_error', 0.0)})"
        )
        _log(f"z_min: {solve_stats.get('z_min', 0.0)}")
        _log(f"z_max: {solve_stats.get('z_max', 0.0)}")
        _log(f"input_z_min: {solve_stats.get('input_z_min', 0.0)}")
        _log(f"input_z_max: {solve_stats.get('input_z_max', 0.0)}")
        _log(f"max_overshoot: {solve_stats.get('max_overshoot', 0.0)}")
        warnings = solve_stats.get("warnings") or []
        if warnings:
            _log(f"warnings: {'; '.join(warnings)}")
    _log(
        "visual-risk notes: "
        "thin-plate spline may overshoot between centers; "
        "cliff-side fields decouple across cliff edges (TS-03d); "
        "compare against terrain_handdrawn_test_map_full_01.blend (IDW) side-by-side."
    )


def _print_tps_cliff_release_diagnostic_report(
    *,
    output_path: Path,
    solve_stats: dict[str, Any] | None,
) -> None:
    _log("--- TS-05 TPS cliff-band release prototype report ---")
    _log(f"USE_TPS_CLIFF_RELEASE: {USE_TPS_CLIFF_RELEASE}")
    _log(f"blend output path: {output_path}")
    if solve_stats is None:
        _log("solve_stats: unavailable")
        return
    release = solve_stats.get("ts05_cliff_release")
    if release is None:
        _log("ts05_cliff_release: unavailable")
        return
    _log(f"connected cliff fronts: {release.get('front_count', 0)}")
    _log(f"side band releases solved: {release.get('band_release_count', 0)}")
    for front in release.get("fronts") or []:
        _log(
            f"  front {front.get('front_id')}: edges={front.get('edge_count')}, "
            f"upper_band_tiles={front.get('upper_band_tiles')}, "
            f"lower_band_tiles={front.get('lower_band_tiles')}, "
            f"upper_anchors={front.get('upper_anchor_count')}, "
            f"lower_anchors={front.get('lower_anchor_count')}"
        )
    rep = release.get("representative_cliff_release")
    if rep is not None:
        _log("--- representative cliff front (4,0) <-> (5,0) rim release ---")
        _log(f"lower rim before correction: {rep.get('lower_rim_before')}")
        _log(f"upper rim before correction: {rep.get('upper_rim_before')}")
        _log(f"lower rim after correction: {rep.get('lower_rim_after')}")
        _log(f"upper rim after correction: {rep.get('upper_rim_after')}")
        _log(f"rim gap before: {rep.get('rim_gap_before')}")
        _log(f"rim gap after: {rep.get('rim_gap_after')}")
        _log(f"expected canonical gap: {rep.get('expected_canonical_gap')}")
    warnings = release.get("warnings") or []
    if warnings:
        _log(f"warnings: {'; '.join(warnings)}")
    band_diags = release.get("band_solve_diagnostics") or []
    if band_diags:
        _log(f"band solve diagnostics ({len(band_diags)} side bands):")
        for diag in band_diags:
            if diag.get("fallback") == "tps" and not diag.get("conflict_messages"):
                continue
            _log(
                f"  front={diag.get('front_id')} side={diag.get('side')}: "
                f"anchors={diag.get('anchor_count_before_dedupe')} "
                f"unique={diag.get('unique_anchor_count_after_dedupe')} "
                f"affine_rank={diag.get('affine_rank')} "
                f"duplicate_xy={diag.get('duplicate_xy_anchors')} "
                f"fallback={diag.get('fallback')}"
                + (" LinAlgError" if diag.get("lin_alg_error") else "")
            )
    _log(
        "visual-risk notes: prototype band re-fit; away from cliffs uses unchanged TS-03; "
        "compare side-by-side with terrain_handdrawn_test_map_full_01_variational_spline.blend."
    )


def _print_fem_thin_plate_diagnostic_report(
    *,
    output_path: Path,
    solve_stats: dict[str, Any] | None,
) -> None:
    _log("--- TS-04 FemThinPlate diagnostic report ---")
    _log(f"USE_FEM_THIN_PLATE_SURFACE: {USE_FEM_THIN_PLATE_SURFACE}")
    _log(f"blend output path: {output_path}")
    if solve_stats is not None:
        _log(f"backend: {solve_stats.get('backend', 'fem_thin_plate')}")
        _log(f"node_count: {solve_stats.get('node_count', 0)}")
        _log(f"triangle_count: {solve_stats.get('triangle_count', 0)}")
        _log(f"cut_mesh_component_count: {solve_stats.get('component_count', 0)}")
        if solve_stats.get("mesh_connected_via_smooth_detour"):
            _log(
                "mesh_connected_via_smooth_detour: true "
                "(one component via legitimate smooth paths — cliff independence "
                "verified by stencil audit, not component count)"
            )
        _log(f"free_dof_count: {solve_stats.get('free_dof_count', 0)}")
        _log(f"laplacian_nnz: {solve_stats.get('laplacian_nnz', 0)}")
        _log(f"cg_solve_blocks: {solve_stats.get('cg_solve_blocks', 0)}")
        _log(f"pinned_center_count: {solve_stats.get('pinned_center_count', 0)}")
        _log(f"cg_iterations: {solve_stats.get('cg_iterations', 0)}")
        _log(f"final_residual: {solve_stats.get('final_residual', 0.0)}")
        _log(f"relative_residual: {solve_stats.get('relative_residual', 0.0)}")
        _log(
            "no_stencil_across_cliff: "
            f"{solve_stats.get('no_stencil_across_cliff')} "
            f"(cross_cliff_stencil_count="
            f"{solve_stats.get('cross_cliff_stencil_count', 0)})"
        )
        rim_gap = solve_stats.get("representative_cliff_rim_gap")
        if rim_gap is not None:
            _log(f"representative_cliff_rim_gap (4,0)-(5,0): {rim_gap}")
        delete_delta = solve_stats.get("delete_opposite_side_max_delta")
        if delete_delta is not None:
            _log(f"delete_opposite_side_max_delta: {delete_delta}")
        _log(
            "max_center_interpolation_error: "
            f"{solve_stats.get('max_center_interpolation_error', 0.0)}"
        )
        _log(
            "affine_constant_ok: "
            f"{solve_stats.get('affine_constant_ok')} "
            f"(max_error={solve_stats.get('affine_constant_max_error', 0.0)})"
        )
        _log(
            "affine_planar_ok: "
            f"{solve_stats.get('affine_planar_ok')} "
            f"(max_error={solve_stats.get('affine_planar_max_error', 0.0)})"
        )
        _log(f"z_min: {solve_stats.get('z_min', 0.0)}")
        _log(f"z_max: {solve_stats.get('z_max', 0.0)}")
        _log(f"input_z_min: {solve_stats.get('input_z_min', 0.0)}")
        _log(f"input_z_max: {solve_stats.get('input_z_max', 0.0)}")
        _log(f"max_overshoot: {solve_stats.get('max_overshoot', 0.0)}")
        _log(f"cliff_cut_two_tile_ok: {solve_stats.get('cliff_cut_two_tile_ok')}")
        delta = solve_stats.get("cross_cliff_decoupling_delta")
        if delta is not None:
            _log(f"cross_cliff_decoupling_delta: {delta}")
        warnings = solve_stats.get("warnings") or []
        if warnings:
            _log(f"warnings: {'; '.join(warnings)}")
    _log(
        "visual-risk notes: "
        "FEM thin-plate on cliff-cut mesh; cliffs are domain cuts; "
        "compare against terrain_handdrawn_test_map_full_01.blend (IDW) side-by-side."
    )


def _adjust_camera(baseline: object, model) -> None:
    radius = baseline.HEX_RADIUS
    wx_values: list[float] = []
    wy_values: list[float] = []
    for q, r in model.map.tiles:
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        for corner_index in range(6):
            q_b, r_b = handdrawn_to_baseline_axial(q, r)
            lx, ly = baseline.corner_xy_local(corner_index, radius)
            wx_values.append(baseline.axial_to_world_xy(q_b, r_b, radius)[0] + lx)
            wy_values.append(baseline.axial_to_world_xy(q_b, r_b, radius)[1] + ly)

    center_x = (min(wx_values) + max(wx_values)) * 0.5
    center_y = (min(wy_values) + max(wy_values)) * 0.5
    extent = max(max(wx_values) - min(wx_values), max(wy_values) - min(wy_values), 1.0)
    cam_obj = bpy.data.objects.get(baseline.CAMERA_NAME)
    if cam_obj is None:
        return
    cam_obj.location = Vector((center_x, center_y - extent * 1.15, extent * 0.75 + 2.5))
    cam_obj.rotation_euler = (math.radians(58.0), 0.0, 0.0)


def _make_cliff_wall_debug_material() -> bpy.types.Material:
    """Flat mid-grey — TS-03e cliff wall visibility debug only."""
    mat = bpy.data.materials.get(CLIFF_WALL_DEBUG_MATERIAL_NAME)
    if mat is not None:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(CLIFF_WALL_DEBUG_MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {CLIFF_WALL_DEBUG_MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (300, 0)
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.location = (0, 0)
    principled.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1.0)
    principled.inputs["Roughness"].default_value = 1.0
    principled.inputs["Specular IOR Level"].default_value = 0.0
    links.new(principled.outputs["BSDF"], out.inputs["Surface"])
    return mat


def _assign_materials_with_cliff_debug(
    mesh: bpy.types.Mesh,
    stats: dict[str, Any],
    *,
    procedural_material: bpy.types.Material,
    side_material: bpy.types.Material,
    cliff_debug_material: bpy.types.Material,
    hide_top_surface: bool,
) -> None:
    """Slot 0 top, 1 other side/bottom, 2 cliff wall quads (mid-grey)."""
    top_face_count = stats["top_faces"]
    cliff_start = stats["cliff_wall_poly_start"]
    cliff_end = cliff_start + stats["cliff_wall_poly_count"]

    mesh.materials.clear()
    mesh.materials.append(procedural_material)
    mesh.materials.append(side_material)
    mesh.materials.append(cliff_debug_material)

    cliff_assigned = 0
    top_assigned = 0
    side_assigned = 0
    for polygon in mesh.polygons:
        if polygon.index < top_face_count:
            polygon.material_index = 0
            top_assigned += 1
        elif cliff_start <= polygon.index < cliff_end:
            polygon.material_index = 2
            cliff_assigned += 1
        else:
            polygon.material_index = 1
            side_assigned += 1

    stats["cliff_wall_material_slot"] = 2
    stats["cliff_wall_material_assigned"] = cliff_assigned
    stats["top_faces_hidden_for_debug"] = hide_top_surface
    _log(f"Material assigned to top faces: {top_assigned}")
    _log(f"Side material assigned to side faces: {side_assigned}")
    _log(f"Cliff debug material assigned to cliff wall quads: {cliff_assigned}")


def _build_cliff_wall_isolated_mesh(
    source_mesh: bpy.types.Mesh,
    stats: dict[str, Any],
) -> bpy.types.Mesh:
    """Extract cliff-wall quads into a standalone mesh (debug isolation; topology unchanged on source)."""
    start = stats["cliff_wall_poly_start"]
    count = stats["cliff_wall_poly_count"]
    vert_remap: dict[int, int] = {}
    new_verts: list[tuple[float, float, float]] = []
    new_faces: list[tuple[int, ...]] = []

    for poly_index in range(start, start + count):
        polygon = source_mesh.polygons[poly_index]
        remapped: list[int] = []
        for vert_index in polygon.vertices:
            mapped = vert_remap.get(vert_index)
            if mapped is None:
                mapped = len(new_verts)
                vert_remap[vert_index] = mapped
                co = source_mesh.vertices[vert_index].co
                new_verts.append((co.x, co.y, co.z))
            remapped.append(mapped)
        new_faces.append(tuple(remapped))

    isolated = bpy.data.meshes.new("CliffWallDebugIsolated")
    isolated.from_pydata(new_verts, [], new_faces)
    isolated.update()
    return isolated


def _mesh_polygon_normal(
    mesh: bpy.types.Mesh,
    polygon: bpy.types.MeshPolygon,
) -> tuple[float, float, float]:
    if len(polygon.vertices) < 3:
        return (0.0, 0.0, 0.0)
    v0 = mesh.vertices[polygon.vertices[0]].co
    v1 = mesh.vertices[polygon.vertices[1]].co
    v2 = mesh.vertices[polygon.vertices[2]].co
    normal = (v1 - v0).cross(v2 - v0)
    if normal.length <= 1e-12:
        return (0.0, 0.0, 0.0)
    normal.normalize()
    return (normal.x, normal.y, normal.z)


def _print_cliff_wall_verification_report(
    *,
    terrain_mesh: bpy.types.Mesh,
    terrain_obj: bpy.types.Object,
    cliff_isolated_obj: bpy.types.Object | None,
    coll: bpy.types.Collection,
    stats: dict[str, Any],
) -> None:
    _log("--- TS-03e cliff wall verification report ---")
    _log(f"DEBUG_SHOW_CLIFF_WALLS: {DEBUG_SHOW_CLIFF_WALLS}")
    _log(f"DEBUG_HIDE_TOP_SURFACE: {DEBUG_HIDE_TOP_SURFACE}")
    _log(f"terrain object: {terrain_obj.name}")
    _log(f"collection: {coll.name}")
    _log(
        f"terrain mesh vertices: {len(terrain_mesh.vertices)}, "
        f"polygons: {len(terrain_mesh.polygons)}"
    )
    _log(f"material slots: {[m.name if m else None for m in terrain_mesh.materials]}")
    _log(f"cliff wall quads (internal counter): {stats['cliff_wall_quads']}")
    _log(f"cliff wall polygon index range: [{stats['cliff_wall_poly_start']}, "
         f"{stats['cliff_wall_poly_start'] + stats['cliff_wall_poly_count']})")
    _log(f"cliff wall unique vertex indices: {stats['cliff_wall_verts']}")
    _log(f"cliff wall verts added during wall pass: {stats['cliff_wall_new_verts']}")
    _log(f"skirt quads: {stats['skirt_face_count']}, chamfer quads: {stats['chamfer_face_count']}")

    cliff_start = stats["cliff_wall_poly_start"]
    cliff_end = cliff_start + stats["cliff_wall_poly_count"]
    cliff_polys = [terrain_mesh.polygons[i] for i in range(cliff_start, cliff_end)]

    quad_count = sum(1 for poly in cliff_polys if len(poly.vertices) == 4)
    tri_count = sum(1 for poly in cliff_polys if len(poly.vertices) == 3)
    _log(f"cliff wall quads in mesh: {quad_count}, triangles: {tri_count}")

    coords: list[tuple[float, float, float]] = []
    vertical_count = 0
    for poly in cliff_polys:
        nx, ny, nz = _mesh_polygon_normal(terrain_mesh, poly)
        if abs(nz) < 0.15:
            vertical_count += 1
        for vert_index in poly.vertices:
            co = terrain_mesh.vertices[vert_index].co
            coords.append((co.x, co.y, co.z))

    if coords:
        xs = [c[0] for c in coords]
        ys = [c[1] for c in coords]
        zs = [c[2] for c in coords]
        _log(
            "cliff wall bounding box: "
            f"X [{min(xs):.3f}, {max(xs):.3f}] "
            f"Y [{min(ys):.3f}, {max(ys):.3f}] "
            f"Z [{min(zs):.4f}, {max(zs):.4f}]"
        )
        _log(f"cliff wall Z range span: {max(zs) - min(zs):.4f}")
    _log(f"cliff wall faces with |normal.z| < 0.15 (vertical-ish): {vertical_count}")

    cliff_vert_indices = stats["cliff_wall_vertex_indices"]
    _log("first 10 cliff wall vertex indices (source mesh):")
    for vert_index in cliff_vert_indices[:10]:
        co = terrain_mesh.vertices[vert_index].co
        _log(f"  v{vert_index}: ({co.x:.4f}, {co.y:.4f}, {co.z:.4f})")

    _log("first 10 cliff wall faces (polygon index, vert indices, z):")
    for poly in cliff_polys[:10]:
        vert_list = list(poly.vertices)
        z_vals = [terrain_mesh.vertices[v].co.z for v in vert_list]
        _log(f"  poly {poly.index}: verts {vert_list}, z {[round(z, 4) for z in z_vals]}")

    if cliff_isolated_obj is not None:
        iso_mesh = cliff_isolated_obj.data
        _log(f"isolated cliff object: {cliff_isolated_obj.name}")
        _log(
            f"isolated cliff mesh: vertices={len(iso_mesh.vertices)}, "
            f"polygons={len(iso_mesh.polygons)}"
        )
        _log(f"isolated cliff hide_viewport: {cliff_isolated_obj.hide_viewport}")

    _log(f"terrain hide_viewport: {terrain_obj.hide_viewport}, hide_render: {terrain_obj.hide_render}")
    if DEBUG_SHOW_CLIFF_WALLS and not DEBUG_HIDE_TOP_SURFACE:
        _log(
            "visibility note: cliff walls use mid-grey slot 2; "
            "production side material is near-black (0.09,0.10,0.09) and is easy to miss."
        )


def _print_ts07a_control_clone_diagnostics(
    *,
    terrain_solver: Any,
    terrain_mesh: bpy.types.Mesh,
    output_path: Path,
) -> None:
    """TS-07a control clone: confirm identical TS-03 path with alternate output only."""
    from collections import Counter

    solver_class = type(terrain_solver).__name__
    mesh_builder = build_analytic_terrain_mesh.__qualname__
    material_path = "baseline.assign_patch_materials"
    slot_names = [mat.name if mat else "<none>" for mat in terrain_mesh.materials]
    slot_poly_counts = Counter(polygon.material_index for polygon in terrain_mesh.polygons)

    print("TS07A_CONTROL_CLONE === diagnostics ===")
    print("TS07A_CONTROL_CLONE=True")
    print(f"TS07A_CONTROL_CLONE   solver_class={solver_class}")
    print(f"TS07A_CONTROL_CLONE   mesh_builder={mesh_builder}")
    print(f"TS07A_CONTROL_CLONE   material_path={material_path}")
    print(f"TS07A_CONTROL_CLONE   output_filename={output_path.name}")
    print(f"TS07A_CONTROL_CLONE   terrain_vertex_count={len(terrain_mesh.vertices)}")
    print(f"TS07A_CONTROL_CLONE   terrain_face_count={len(terrain_mesh.polygons)}")
    for slot_index in sorted(slot_poly_counts):
        name = slot_names[slot_index] if slot_index < len(slot_names) else "<unknown>"
        print(
            f"TS07A_CONTROL_CLONE   material_slot_{slot_index}={name!r} "
            f"poly_count={slot_poly_counts[slot_index]}"
        )


def _ts05_debug_overlay_enabled() -> bool:
    overlay_flag = globals().get("USE_TS05_DEBUG_OVERLAY", True)
    return bool(USE_TPS_CLIFF_RELEASE and overlay_flag)


def _log_ts06_path_invariant(*, use_ts06: bool) -> None:
    """Hard invariant: TS-06 must share TS-03 mesh builder and material assignment."""
    mesh_builder = build_analytic_terrain_mesh.__qualname__
    material_builder = "baseline.assign_patch_materials"
    print(
        "TS06_PATH_INVARIANT === mesh/material path === "
        f"use_ts06={use_ts06}"
    )
    print(
        f"TS06_PATH_INVARIANT   mesh_builder={mesh_builder} "
        f"(same for TS-03 and TS-06: True)"
    )
    print(
        f"TS06_PATH_INVARIANT   material_builder={material_builder} "
        f"(same for TS-03 and TS-06 when debug flags off: True)"
    )
    print(
        "TS06_PATH_INVARIANT   solver_diff=constraint_set_only "
        "(TS-06 adds cliff-rim samples to solve_component_field inputs)"
    )


def _mesh_edge_key(v0: int, v1: int) -> tuple[int, int]:
    return (v0, v1) if v0 < v1 else (v1, v0)


def _print_mesh_geometry_integrity(
    mesh: bpy.types.Mesh,
    stats: dict[str, Any],
    *,
    bottom_z: float,
    z_bottom_tol: float = 1e-4,
) -> None:
    """Pre-save geometry integrity: open edges, material slot counts, cliff wall polys."""
    from collections import Counter

    edge_counts: Counter[tuple[int, int]] = Counter()
    for polygon in mesh.polygons:
        verts = polygon.vertices
        vert_count = len(verts)
        for i in range(vert_count):
            edge_counts[_mesh_edge_key(verts[i], verts[(i + 1) % vert_count])] += 1

    open_edges = [edge for edge, count in edge_counts.items() if count == 1]
    cliff_wall_verts = set(stats.get("cliff_wall_vertex_indices") or [])
    bottom_open = 0
    vertical_open = 0
    top_perimeter_open = 0
    interior_hole_candidates = 0
    hole_samples: list[tuple[int, int]] = []

    for v0, v1 in open_edges:
        z0 = mesh.vertices[v0].co.z
        z1 = mesh.vertices[v1].co.z
        both_bottom = z0 <= bottom_z + z_bottom_tol and z1 <= bottom_z + z_bottom_tol
        one_bottom = (z0 <= bottom_z + z_bottom_tol) ^ (z1 <= bottom_z + z_bottom_tol)
        if both_bottom:
            bottom_open += 1
        elif one_bottom:
            vertical_open += 1
        elif v0 in cliff_wall_verts or v1 in cliff_wall_verts:
            top_perimeter_open += 1
        else:
            top_perimeter_open += 1
            if (
                z0 > bottom_z + 0.01
                and z1 > bottom_z + 0.01
                and abs(z0 - z1) <= 0.002
            ):
                interior_hole_candidates += 1
                if len(hole_samples) < 8:
                    hole_samples.append((v0, v1))

    slot_names = [mat.name if mat else "<none>" for mat in mesh.materials]
    slot_poly_counts = Counter(polygon.material_index for polygon in mesh.polygons)

    cliff_start = stats.get("cliff_wall_poly_start", 0)
    cliff_count = stats.get("cliff_wall_poly_count", 0)
    cliff_material_indices: Counter[int] = Counter()
    for poly_index in range(cliff_start, cliff_start + cliff_count):
        if poly_index < len(mesh.polygons):
            cliff_material_indices[mesh.polygons[poly_index].material_index] += 1

    print("TS06_MESH_INTEGRITY === geometry/material audit ===")
    print(
        f"TS06_MESH_INTEGRITY   open_edges_total={len(open_edges)} "
        f"bottom_cap={bottom_open} vertical_skirt_cliff={vertical_open} "
        f"top_boundary={top_perimeter_open} "
        f"interior_hole_candidates={interior_hole_candidates}"
    )
    if interior_hole_candidates:
        print(
            f"TS06_MESH_INTEGRITY   WARNING interior_hole_candidates="
            f"{interior_hole_candidates} (horizontal open top edges away from cliff walls)"
        )
        for edge in hole_samples:
            v0, v1 = edge
            c0 = mesh.vertices[v0].co
            c1 = mesh.vertices[v1].co
            print(
                f"TS06_MESH_INTEGRITY     edge ({v0},{v1}) "
                f"z=({c0.z:.4f},{c1.z:.4f}) xy="
                f"({c0.x:.3f},{c0.y:.3f})-({c1.x:.3f},{c1.y:.3f})"
            )
    for slot_index in sorted(slot_poly_counts):
        name = slot_names[slot_index] if slot_index < len(slot_names) else "<unknown>"
        print(
            f"TS06_MESH_INTEGRITY   material_slot_{slot_index}={name!r} "
            f"poly_count={slot_poly_counts[slot_index]}"
        )
    cliff_slot = (
        cliff_material_indices.most_common(1)[0][0]
        if cliff_material_indices
        else None
    )
    cliff_mat_name = (
        slot_names[cliff_slot]
        if cliff_slot is not None and cliff_slot < len(slot_names)
        else "<none>"
    )
    print(
        f"TS06_MESH_INTEGRITY   cliff_wall_poly_count={cliff_count} "
        f"cliff_wall_material_slot={cliff_slot} cliff_wall_material_name={cliff_mat_name!r}"
    )
    print(
        f"TS06_MESH_INTEGRITY   cliff_edges_filled={stats.get('cliff_edges_filled', 0)} "
        f"cliff_segments_filled={stats.get('cliff_segments_filled', 0)} "
        f"cliff_segments_skipped={stats.get('cliff_segments_skipped', 0)}"
    )


def _print_ts05_debug_final_report(result: dict[str, Any]) -> None:
    import sys

    print(f"TS05_DEBUG_OVERLAY_REQUESTED={result.get('requested')}")
    print(f"TS05_DEBUG_OVERLAY_BUILDER_CALLED={result.get('builder_called')}")
    print(f"TS05_DEBUG_SKIP_REASON={result.get('skip_reason', 'none')}")
    collection_name = result.get("collection_name")
    print(f"TS05_DEBUG_COLLECTION_CREATED={collection_name if collection_name else 'none'}")
    print(f"TS05_DEBUG_OBJECT_COUNT={result.get('object_count', 0)}")
    if result.get("requested") and int(result.get("object_count", 0)) == 0:
        print(
            "TS05_DEBUG_ZERO_OBJECT_REASON="
            f"{result.get('empty_reason') or result.get('skip_reason') or 'unknown'}"
        )
    sys.stdout.flush()


def _ensure_ts05_debug_overlay_before_save(
    *,
    terrain_solver: Any,
    model: Any,
    coll: bpy.types.Collection,
    ts05_debug: Any | None,
) -> dict[str, Any]:
    import bpy

    result: dict[str, Any] = {
        "requested": _ts05_debug_overlay_enabled(),
        "builder_called": False,
        "skip_reason": "none",
        "collection_name": None,
        "object_count": 0,
        "front_count": 0,
        "empty_reason": "",
    }

    if not result["requested"]:
        result["skip_reason"] = (
            f"flags_disabled(USE_TPS_CLIFF_RELEASE={USE_TPS_CLIFF_RELEASE},"
            f"USE_TS05_DEBUG_OVERLAY={globals().get('USE_TS05_DEBUG_OVERLAY', True)})"
        )
        _print_ts05_debug_final_report(result)
        return result

    try:
        from eom_terrain_tps_cliff_release import TpsCliffReleaseTerrainSolver
        from eom_terrain_tps_cliff_release_debug import (
            TS05_DEBUG_COLLECTION_NAME,
            build_ts05_debug_blender_overlays,
            build_ts05_debug_export,
        )
    except ImportError as exc:
        result["skip_reason"] = f"debug_module_import_failed:{exc}"
        _print_ts05_debug_final_report(result)
        return result

    result["builder_called"] = True
    try:
        if ts05_debug is None:
            if not isinstance(terrain_solver, TpsCliffReleaseTerrainSolver):
                result["skip_reason"] = "terrain_solver_not_tps_cliff_release"
                result["builder_called"] = False
                _print_ts05_debug_final_report(result)
                return result
            _log("TS-05 debug export missing before save; rebuilding from prepared solver")
            ts05_debug = build_ts05_debug_export(
                terrain_solver,
                model,
                radius=DEFAULT_HEX_RADIUS,
                subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
            )

        debug_stats = build_ts05_debug_blender_overlays(
            ts05_debug,
            model,
            parent_collection=coll,
        )
        result["front_count"] = int(debug_stats.get("front_count", 0))
        result["object_count"] = int(debug_stats.get("object_count", 0))
        result["empty_reason"] = str(debug_stats.get("empty_reason", ""))
        result["collection_name"] = TS05_DEBUG_COLLECTION_NAME
        if TS05_DEBUG_COLLECTION_NAME not in bpy.data.collections:
            result["skip_reason"] = "collection_missing_after_build"
        elif result["object_count"] == 0 and result["front_count"] > 0:
            result["skip_reason"] = f"zero_objects:{result['empty_reason'] or 'unknown'}"
        _log(f"TS-05 debug overlay: {debug_stats}")
    except Exception as exc:
        result["skip_reason"] = f"overlay_build_failed:{type(exc).__name__}:{exc}"
        import traceback

        traceback.print_exc()

    _print_ts05_debug_final_report(result)
    return result


def _print_pre_save_collection_diagnostics() -> None:
    print("=== ALL COLLECTIONS ===")
    for collection in bpy.data.collections:
        print(
            f"  {collection.name!r}: "
            f"direct_objects={len(collection.objects)}, "
            f"child_collections={len(collection.children)}"
        )

    print("=== ALL SCENES ===")
    for scene in bpy.data.scenes:
        root = scene.collection
        child_collection_names = [child.name for child in root.children]
        direct_object_names = [obj.name for obj in root.objects]
        print(f"  scene {scene.name!r}:")
        print(f"    child_collections={child_collection_names}")
        print(f"    direct_objects={direct_object_names}")

    print("=== TS05 DEBUG ===")
    if "TS05_Debug" not in bpy.data.collections:
        print("  TS05_Debug: not in bpy.data.collections")
        return

    ts05 = bpy.data.collections["TS05_Debug"]
    print(f"  id={id(ts05)}")
    print(f"  direct_objects={len(ts05.objects)}")
    print(f"  child_collections={[child.name for child in ts05.children]}")
    for child in ts05.children:
        print(f"    {child.name!r}: direct_objects={len(child.objects)}")

    for scene in bpy.data.scenes:
        root = scene.collection
        linked_direct = any(child.name == "TS05_Debug" for child in root.children)

        def _linked_under(parent: bpy.types.Collection) -> bool:
            for child in parent.children:
                if child.name == "TS05_Debug":
                    return True
                if _linked_under(child):
                    return True
            return False

        linked_in_tree = _linked_under(root)
        print(
            f"  scene {scene.name!r}: "
            f"linked_direct_under_root={linked_direct}, "
            f"linked_in_scene_tree={linked_in_tree}"
        )


def _resolve_blend_filename() -> str:
    if USE_TPS_RIM_CONSTRAINTS:
        blend_filename = OUTPUT_BLEND_FILENAME_TPS_RIM_CONSTRAINTS
    elif USE_TPS_CLIFF_RELEASE:
        blend_filename = OUTPUT_BLEND_FILENAME_TPS_CLIFF_RELEASE
    elif USE_FEM_THIN_PLATE_SURFACE:
        blend_filename = OUTPUT_BLEND_FILENAME_FEM_THIN_PLATE
    elif USE_VARIATIONAL_SPLINE_SURFACE:
        if USE_TS07A_TS03_CLONE:
            blend_filename = OUTPUT_BLEND_FILENAME_TS07A_TS03_CLONE
        else:
            blend_filename = OUTPUT_BLEND_FILENAME_VARIATIONAL_SPLINE
    elif USE_GLOBAL_BIHARMONIC_SURFACE:
        blend_filename = OUTPUT_BLEND_FILENAME_GLOBAL_BIHARMONIC
    elif USE_HEXPATCH_V1_SURFACE:
        blend_filename = OUTPUT_BLEND_FILENAME_HEXPATCH_V1
    else:
        blend_filename = OUTPUT_BLEND_FILENAME
    if DEBUG_SHOW_CLIFF_WALLS or DEBUG_HIDE_TOP_SURFACE:
        blend_filename = f"{Path(blend_filename).stem}_cliff_debug.blend"
    return blend_filename


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
        / _resolve_blend_filename()
    )


def _assert_not_frozen_baseline_path(output_path: Path) -> None:
    if output_path.name == FROZEN_BASELINE_BLEND_FILENAME or "_BASELINE_" in output_path.stem:
        raise RuntimeError(
            f"Refusing to overwrite frozen baseline artifact: {output_path.name}. "
            "Runners must never write to *_BASELINE_* blends."
        )


def _print_prototype_traceability_banner(
    *,
    phase: str,
    output_path: Path | None = None,
    solver_backend: object | None = None,
    terrain_solver: object | None = None,
) -> None:
    import sys

    planned_filename = _resolve_blend_filename()
    proto_id = PROTOTYPE_ID or "FULL01-DEFAULT"
    runner = RUNNER_FILE or "generate_terrain_terrainmap_handdrawn_full_01.py (direct)"
    backend_label = (
        getattr(solver_backend, "value", str(solver_backend))
        if solver_backend is not None
        else "pending"
    )
    solver_class = (
        type(terrain_solver).__name__ if terrain_solver is not None else "pending"
    )
    cliff_wall_enabled = bool(DEBUG_SHOW_CLIFF_WALLS or DEBUG_HIDE_TOP_SURFACE)
    ts05_debug_overlay = bool(globals().get("USE_TS05_DEBUG_OVERLAY", True))

    print("=== EOM TERRAIN PROTOTYPE TRACEABILITY ===")
    print(f"TRACEABILITY_PHASE={phase}")
    print(f"PROTOTYPE_ID={proto_id}")
    print(f"RUNNER_FILE={runner}")
    print(f"OUTPUT_BLEND_FILENAME={planned_filename}")
    if output_path is not None:
        print(f"OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"TERRAIN_SOLVER_BACKEND={backend_label}")
    print(f"TERRAIN_SOLVER_CLASS={solver_class}")
    print(f"USE_VARIATIONAL_SPLINE_SURFACE={USE_VARIATIONAL_SPLINE_SURFACE}")
    print(f"CLIFF_WALL_DEBUG_ENABLED={cliff_wall_enabled}")
    print(f"USE_TPS_CLIFF_RELEASE={USE_TPS_CLIFF_RELEASE}")
    print(f"USE_TPS_RIM_CONSTRAINTS={USE_TPS_RIM_CONSTRAINTS}")
    print(f"USE_TS07A_TS03_CLONE={USE_TS07A_TS03_CLONE}")
    print(f"USE_TS05_DEBUG_OVERLAY={ts05_debug_overlay}")
    print("=== END TRACEABILITY ===")
    sys.stdout.flush()


def _save_blend(output_path: Path) -> None:
    _assert_not_frozen_baseline_path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    wm = bpy.context.window_manager
    override: dict[str, Any] = {"scene": scene}
    if wm is not None and wm.windows:
        window = wm.windows[0]
        screen = window.screen
        override["window"] = window
        override["screen"] = screen
        for area in screen.areas:
            if area.type in {"VIEW_3D", "TEXT_EDITOR", "PROPERTIES", "OUTLINER"}:
                region = next((r for r in area.regions if r.type == "WINDOW"), None)
                if region is not None:
                    override["area"] = area
                    override["region"] = region
                    break
    with bpy.context.temp_override(**override):
        bpy.ops.wm.save_as_mainfile(filepath=str(output_path))


def main() -> None:
    import sys

    ts05_debug = None
    _print_prototype_traceability_banner(phase="START")
    sys.stdout.flush()
    if USE_HEXPATCH_V1_SURFACE and not USE_HEXPATCH_SURFACE:
        _log(
            "note: USE_HEXPATCH_V1_SURFACE=True uses IDW fallback on cliff-adjacent tiles; "
            "USE_HEXPATCH_SURFACE=False only affects non-v1 legacy path."
        )
    if USE_TPS_RIM_CONSTRAINTS and USE_TPS_CLIFF_RELEASE:
        raise RuntimeError(
            "USE_TPS_RIM_CONSTRAINTS and USE_TPS_CLIFF_RELEASE are mutually exclusive."
        )
    if USE_TS07A_TS03_CLONE and (
        USE_TPS_RIM_CONSTRAINTS or USE_TPS_CLIFF_RELEASE
    ):
        raise RuntimeError(
            "USE_TS07A_TS03_CLONE is mutually exclusive with TS-05 and TS-06."
        )
    if USE_TS07A_TS03_CLONE and not USE_VARIATIONAL_SPLINE_SURFACE:
        raise RuntimeError(
            "USE_TS07A_TS03_CLONE requires USE_VARIATIONAL_SPLINE_SURFACE=True "
            "(control clone of approved TS-03 variational spline path)."
        )
    if USE_TPS_RIM_CONSTRAINTS and not USE_VARIATIONAL_SPLINE_SURFACE:
        raise RuntimeError(
            "USE_TPS_RIM_CONSTRAINTS requires USE_VARIATIONAL_SPLINE_SURFACE=True "
            "(TS-06 extends TS-03 per-cluster TPS with rim constraints)."
        )
    if USE_TPS_CLIFF_RELEASE and not USE_VARIATIONAL_SPLINE_SURFACE:
        raise RuntimeError(
            "USE_TPS_CLIFF_RELEASE requires USE_VARIATIONAL_SPLINE_SURFACE=True "
            "(TS-05 wraps TS-03; it does not replace the base TPS path)."
        )
    if USE_FEM_THIN_PLATE_SURFACE and (
        USE_VARIATIONAL_SPLINE_SURFACE
        or USE_GLOBAL_BIHARMONIC_SURFACE
        or USE_HEXPATCH_V1_SURFACE
        or not USE_HEXPATCH_SURFACE
    ):
        _log(
            "note: USE_FEM_THIN_PLATE_SURFACE=True selects fem_thin_plate backend "
            "regardless of other USE_* flags."
        )
    if USE_VARIATIONAL_SPLINE_SURFACE and (
        USE_GLOBAL_BIHARMONIC_SURFACE or USE_HEXPATCH_V1_SURFACE or not USE_HEXPATCH_SURFACE
    ):
        _log(
            "note: USE_VARIATIONAL_SPLINE_SURFACE=True selects variational_spline backend "
            "regardless of USE_HEXPATCH_* / USE_GLOBAL_BIHARMONIC_SURFACE flags."
        )
    if USE_GLOBAL_BIHARMONIC_SURFACE and (
        USE_HEXPATCH_V1_SURFACE or not USE_HEXPATCH_SURFACE
    ):
        _log(
            "note: USE_GLOBAL_BIHARMONIC_SURFACE=True selects global_biharmonic backend "
            "regardless of USE_HEXPATCH_* flags."
        )

    terrain_map = parse_terrain_map_json(TERRAIN_MAP_JSON)
    model = build_terrain_model(terrain_map)

    repo_root, examined_starts = _resolve_repo_root()
    _log(f"repo root: {repo_root}")

    baseline = _load_baseline_module(repo_root, examined_starts=examined_starts)
    _assert_baseline_unchanged(baseline)
    baseline.validate_params()
    baseline.validate_material_params()

    core_path = Path(getattr(_terrain_math, "__file__", SCRIPT_DIR / "eom_terrain_math_core.py"))
    v1_audits: object | None = None
    if USE_HEXPATCH_V1_SURFACE:
        _load_hexpatch_v1_surface(core_path)
        v1_audits = _load_hexpatch_v1_audits(core_path)

    solver_backend = resolve_terrain_solver_backend(
        use_fem_thin_plate_surface=USE_FEM_THIN_PLATE_SURFACE,
        use_variational_spline_surface=USE_VARIATIONAL_SPLINE_SURFACE,
        use_global_biharmonic_surface=USE_GLOBAL_BIHARMONIC_SURFACE,
        use_hexpatch_v1_surface=USE_HEXPATCH_V1_SURFACE,
        use_hexpatch_surface=USE_HEXPATCH_SURFACE,
        explicit_backend=TERRAIN_SOLVER_BACKEND,
    )
    if USE_TPS_RIM_CONSTRAINTS:
        from eom_terrain_tps_rim_constraints import (
            TpsRimConstraintsTerrainSolver,
            print_ts06_rim_diag,
        )
        from eom_terrain_variational_spline import VariationalSplineTerrainSolver

        TpsRimConstraintsTerrainSolver.backend = TerrainBackend.variational_spline  # type: ignore[attr-defined]
        terrain_solver = TpsRimConstraintsTerrainSolver()
        terrain_solver.prepare(model, radius=DEFAULT_HEX_RADIUS)
        _log("TS-06 TpsRimConstraints solver active over variational spline clusters")
        base_solver = VariationalSplineTerrainSolver()
        base_solver.prepare(model, radius=DEFAULT_HEX_RADIUS)
        print_ts06_rim_diag(
            model,
            radius=DEFAULT_HEX_RADIUS,
            subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
            base_solver=base_solver,
            ts06_solver=terrain_solver,
        )
    elif USE_TPS_CLIFF_RELEASE:
        from eom_terrain_tps_cliff_release import TpsCliffReleaseTerrainSolver

        TpsCliffReleaseTerrainSolver.backend = TerrainBackend.variational_spline  # type: ignore[attr-defined]
        terrain_solver = TpsCliffReleaseTerrainSolver()
        terrain_solver.prepare(model, radius=DEFAULT_HEX_RADIUS)
        _log("TS-05 TpsCliffRelease wrapper active over variational spline base")
        print(
            f"TS05_DEBUG_OVERLAY_REQUESTED={bool(USE_TPS_CLIFF_RELEASE and USE_TS05_DEBUG_OVERLAY)}"
        )
        if USE_TS05_DEBUG_OVERLAY:
            from eom_terrain_tps_cliff_release_debug import (
                build_ts05_debug_export,
                print_ts05_front_diagnostics,
            )

            ts05_debug = build_ts05_debug_export(
                terrain_solver,
                model,
                radius=DEFAULT_HEX_RADIUS,
                subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
            )
            _log("--- TS-05 release region debug (verbose tile lists) ---")
            print_ts05_front_diagnostics(ts05_debug)
    else:
        terrain_solver = make_terrain_solver(
            solver_backend,
            model,
            radius=DEFAULT_HEX_RADIUS,
            baseline=baseline if (USE_GLOBAL_BIHARMONIC_SURFACE or USE_FEM_THIN_PLATE_SURFACE) else None,
            subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
        )

    output_path = _generated_output_path(repo_root)
    _assert_not_frozen_baseline_path(output_path)

    _print_orientation_audit()
    _print_curvature_influence_audit(baseline)
    _print_model_audit(model, output_path)
    _print_ssc_corner_audit(model)
    _print_smooth_edge_audit(model)
    _print_mid_edge_invariant_audit(model)
    _print_transverse_spike_audit(model)
    _print_center_corner_ray_audit(model)
    if USE_HEXPATCH_V1_SURFACE:
        assert v1_audits is not None
        _print_hexpatch_v1_visual_audit(model, v1_audits)
    elif USE_FEM_THIN_PLATE_SURFACE:
        _log("--- FEM thin-plate pre-mesh solve (TS-04) ---")
        fem_stats = terrain_solver.stats
        if fem_stats is not None:
            _log(f"pre-mesh node_count: {fem_stats.get('node_count', 0)}")
            _log(f"pre-mesh cut_mesh_component_count: {fem_stats.get('component_count', 0)}")
            _log(
                "pre-mesh max_center_interpolation_error: "
                f"{fem_stats.get('max_center_interpolation_error', 0.0)}"
            )
            _log(
                "pre-mesh affine_constant_ok: "
                f"{fem_stats.get('affine_constant_ok')} "
                f"affine_planar_ok: {fem_stats.get('affine_planar_ok')}"
            )
    elif USE_TPS_RIM_CONSTRAINTS:
        _log("--- TS-06 rim-constraint TPS pre-mesh solve ---")
        ts06_stats = terrain_solver.stats
        if ts06_stats is not None:
            rim_report = ts06_stats.get("ts06_rim_constraints") or {}
            _log(f"pre-mesh connected_front_count: {rim_report.get('front_count', 0)}")
            _log(f"pre-mesh total_rim_constraints: {rim_report.get('total_rim_constraints', 0)}")
            _log(
                "pre-mesh max_center_interpolation_error: "
                f"{ts06_stats.get('max_center_interpolation_error', 0.0)}"
            )
    elif USE_TS07A_TS03_CLONE:
        _log("--- TS-07a control clone pre-mesh solve (TS-03 variational spline) ---")
        vs_stats = terrain_solver.stats
        if vs_stats is not None:
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
    elif USE_VARIATIONAL_SPLINE_SURFACE and not USE_TPS_CLIFF_RELEASE:
        _log("--- variational spline pre-mesh solve (TS-03) ---")
        vs_stats = terrain_solver.stats
        if vs_stats is not None:
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
    elif USE_GLOBAL_BIHARMONIC_SURFACE:
        _log("--- global biharmonic pre-mesh solve (TS-02) ---")
        gb_stats = terrain_solver.stats
        if gb_stats is not None:
            _log(f"pre-mesh node_count: {gb_stats.get('node_count', 0)}")
            _log(f"pre-mesh component_count: {gb_stats.get('component_count', 0)}")
            _log(
                "pre-mesh max_center_constraint_error: "
                f"{gb_stats.get('max_center_constraint_error', 0.0)}"
            )
    elif USE_HEXPATCH_SURFACE:
        _print_hexpatch_audit(model)

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

    if USE_TPS_RIM_CONSTRAINTS or (
        USE_VARIATIONAL_SPLINE_SURFACE and not USE_TPS_CLIFF_RELEASE
    ):
        _log_ts06_path_invariant(use_ts06=USE_TPS_RIM_CONSTRAINTS)

    terrain_mesh, stats = build_analytic_terrain_mesh(
        model,
        baseline,
        terrain_solver=terrain_solver,
    )
    baseline.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    cliff_isolated_obj: bpy.types.Object | None = None
    if DEBUG_SHOW_CLIFF_WALLS or DEBUG_HIDE_TOP_SURFACE:
        cliff_debug_material = _make_cliff_wall_debug_material()
        _assign_materials_with_cliff_debug(
            terrain_mesh,
            stats,
            procedural_material=procedural_material,
            side_material=side_material,
            cliff_debug_material=cliff_debug_material,
            hide_top_surface=DEBUG_HIDE_TOP_SURFACE,
        )
        if DEBUG_HIDE_TOP_SURFACE:
            isolated_mesh = _build_cliff_wall_isolated_mesh(terrain_mesh, stats)
            cliff_isolated_obj = bpy.data.objects.new(CLIFF_WALL_OBJECT_NAME, isolated_mesh)
            cliff_isolated_obj.data.materials.append(cliff_debug_material)
            coll.objects.link(cliff_isolated_obj)
            _log(f"cliff wall isolated debug object created: {CLIFF_WALL_OBJECT_NAME}")
    else:
        baseline.assign_patch_materials(
            terrain_mesh,
            stats["top_faces"],
            procedural_material,
            side_material,
        )
    terrain_obj = bpy.data.objects.new(TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)
    if DEBUG_HIDE_TOP_SURFACE:
        terrain_obj.hide_viewport = True
        terrain_obj.hide_render = True
        _log("terrain object hidden for cliff-wall isolation debug")
    _log("terrain mesh created")
    _log(f"top vertices: {stats['top_verts']}")
    _log(f"top faces: {stats['top_faces']}")
    _log(f"cliff placeholder wall faces: {stats['cliff_wall_faces']}")
    _log(
        "cliff edges with solid fill: "
        f"{stats['cliff_edges_filled']} / {len(model.cliff_edge_graph)}"
    )
    _log(f"cliff wall segments filled: {stats['cliff_segments_filled']}")
    _log(f"cliff wall segments skipped (degenerate): {stats['cliff_segments_skipped']}")
    all_cliffs_filled = stats["cliff_edges_filled"] == len(model.cliff_edge_graph)
    _log(f"all cliff edges received solid fill: {all_cliffs_filled}")
    if USE_TPS_RIM_CONSTRAINTS:
        from eom_terrain_tps_rim_constraints import print_ts06_representative_mesh_audit

        print_ts06_representative_mesh_audit(
            model,
            terrain_mesh,
            stats,
            terrain_solver,
            radius=DEFAULT_HEX_RADIUS,
            subdiv=DEFAULT_SURFACE_SUBDIVISIONS,
            bottom_z=-baseline.BASE_THICKNESS,
        )
    if DEBUG_SHOW_CLIFF_WALLS or DEBUG_HIDE_TOP_SURFACE:
        _print_cliff_wall_verification_report(
            terrain_mesh=terrain_mesh,
            terrain_obj=terrain_obj,
            cliff_isolated_obj=cliff_isolated_obj,
            coll=coll,
            stats=stats,
        )
    ssc_audit = stats["ssc_deformation"]
    _log(f"SSC deformation affected samples: {ssc_audit['affected_sample_count']}")
    _log(
        "edge counts unchanged: "
        f"smooth {len(model.smooth_edges)}, cliff {len(model.cliff_edges)}"
    )
    if USE_HEXPATCH_V1_SURFACE:
        _print_hxp03_diagnostic_report(
            output_path=output_path,
            sample_stats=stats.get("hexpatch_v1_sample_stats"),
        )
    if USE_FEM_THIN_PLATE_SURFACE:
        _print_fem_thin_plate_diagnostic_report(
            output_path=output_path,
            solve_stats=stats.get("fem_thin_plate_stats"),
        )
    if USE_VARIATIONAL_SPLINE_SURFACE:
        _print_variational_spline_diagnostic_report(
            output_path=output_path,
            solve_stats=stats.get("variational_spline_stats"),
        )
    if USE_TPS_CLIFF_RELEASE:
        _print_tps_cliff_release_diagnostic_report(
            output_path=output_path,
            solve_stats=stats.get("variational_spline_stats"),
        )
    if USE_GLOBAL_BIHARMONIC_SURFACE:
        _print_global_biharmonic_diagnostic_report(
            output_path=output_path,
            solve_stats=stats.get("global_biharmonic_stats"),
        )
    _log(f"total vertices: {stats['total_verts']}")
    _log(f"total faces: {stats['total_faces']}")

    overlay_material = baseline.make_overlay_material()
    overlay_mesh, overlay_stats = build_hex_overlay_mesh(model, baseline)
    overlay_obj = bpy.data.objects.new(OVERLAY_OBJECT_NAME, overlay_mesh)
    overlay_obj.data.materials.append(overlay_material)
    coll.objects.link(overlay_obj)
    _log("hex overlay created")
    _log(f"unique overlay edges: {overlay_stats['unique_edges']}")

    baseline.setup_camera_and_lights()
    _adjust_camera(baseline, model)
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

    ts05_overlay_result = _ensure_ts05_debug_overlay_before_save(
        terrain_solver=terrain_solver,
        model=model,
        coll=coll,
        ts05_debug=ts05_debug,
    )
    if ts05_overlay_result.get("requested"):
        from eom_terrain_tps_cliff_release_debug import TS05_DEBUG_COLLECTION_NAME

        if TS05_DEBUG_COLLECTION_NAME not in bpy.data.collections:
            raise RuntimeError(
                f"TS-05 debug overlay requested but {TS05_DEBUG_COLLECTION_NAME!r} "
                "is missing from bpy.data.collections before save"
            )

    if USE_TPS_RIM_CONSTRAINTS or (
        USE_VARIATIONAL_SPLINE_SURFACE and not USE_TPS_CLIFF_RELEASE
    ):
        _print_mesh_geometry_integrity(
            terrain_mesh,
            stats,
            bottom_z=-baseline.BASE_THICKNESS,
        )
        if USE_TPS_RIM_CONSTRAINTS:
            ts05_in_scene = "TS05_Debug" in bpy.data.collections
            print(
                f"TS06_MESH_INTEGRITY   ts05_debug_collection_present={ts05_in_scene} "
                f"(must be False for TS-06)"
            )

    if USE_TS07A_TS03_CLONE:
        _print_ts07a_control_clone_diagnostics(
            terrain_solver=terrain_solver,
            terrain_mesh=terrain_mesh,
            output_path=output_path,
        )

    _print_prototype_traceability_banner(
        phase="END",
        output_path=output_path,
        solver_backend=solver_backend,
        terrain_solver=terrain_solver,
    )

    if SAVE_BLEND:
        if ts05_overlay_result.get("requested"):
            print("PRE_SAVE filepath:", bpy.data.filepath)
            print(
                "PRE_SAVE collections:",
                "TS05_Debug" in bpy.data.collections,
            )
            if "TS05_Debug" in bpy.data.collections:
                c = bpy.data.collections["TS05_Debug"]
                print("PRE_SAVE object count:", len(c.objects))
            else:
                raise RuntimeError("TS05_Debug does not exist immediately before save.")
            _print_pre_save_collection_diagnostics()

        _save_blend(output_path)

        if ts05_overlay_result.get("requested"):
            print(
                "POST_SAVE collections:",
                "TS05_Debug" in bpy.data.collections,
            )
            if "TS05_Debug" in bpy.data.collections:
                c = bpy.data.collections["TS05_Debug"]
                print("POST_SAVE object count:", len(c.objects))
            else:
                print("POST_SAVE: TS05_Debug missing after save")

        _log(f"saved blend: {output_path}")

    _log("done")


if __name__ == "__main__":
    main()
