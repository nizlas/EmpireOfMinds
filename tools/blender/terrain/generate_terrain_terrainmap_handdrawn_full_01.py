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
SAVE_BLEND = True
# §§12–13 HexPatch IDW evaluator (SharedCorner/Ribbon + center bubble). Legacy sector path when False.
USE_HEXPATCH_SURFACE = True
# HXP-03: side-blend v1.0 S_final diagnostic path. Default off; does not replace IDW unless True.
USE_HEXPATCH_V1_SURFACE = False

OUTPUT_BLEND_PATH: Path | None = None


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


_terrain_math = _load_terrain_math_core()
_hexpatch_surface = _load_hexpatch_surface(
    Path(getattr(_terrain_math, "__file__", SCRIPT_DIR / "eom_terrain_math_core.py"))
)
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
    hexpatch_v1_sampler: object | None = None,
) -> tuple[bpy.types.Mesh, dict[str, Any]]:
    reset_ssc_deformation_audit()
    if USE_HEXPATCH_V1_SURFACE:
        sampler_label = "hexpatch v1.0 S_final (HXP-03 diagnostic)"
    elif USE_HEXPATCH_SURFACE:
        sampler_label = "hexpatch IDW (§§12–13)"
    else:
        sampler_label = "legacy sector/radial"
    _log(f"analytic surface sampler: {sampler_label}")
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
    ) -> int:
        position_key = pos_key(wx, wy)
        merge_key = (position_key, domain_id)
        if at_sector_corner and sector is not None:
            tile_key = (position_key, domain_id, q, r, sector)
        else:
            tile_key = (position_key, domain_id, q, r)

        cached_tile = top_cache.get(tile_key)
        if cached_tile is not None:
            return cached_tile

        cached_merge = top_cache.get(merge_key)
        if cached_merge is not None and abs(verts[cached_merge][2] - wz) <= height_epsilon:
            owner = merge_owner.get(merge_key)
            if owner is None or not tiles_are_cliff_neighbors((q, r), owner):
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
                    if USE_HEXPATCH_V1_SURFACE:
                        assert hexpatch_v1_sampler is not None

                        def _idw_fallback(fwx: float, fwy: float, fq: int, fr: int) -> float:
                            return sample_hexpatch_surface_world(
                                fwx,
                                fwy,
                                fq,
                                fr,
                                model,
                                radius=radius,
                            )

                        def _legacy_fallback(
                            fwx: float,
                            fwy: float,
                            fq: int,
                            fr: int,
                            *,
                            fsector: int = sector,
                            fat_corner: bool = at_corner,
                        ) -> float:
                            wz_legacy = sample_smooth_domain_surface_world(
                                fwx,
                                fwy,
                                fq,
                                fr,
                                model,
                                radius=radius,
                                sector=fsector,
                                at_sector_corner=fat_corner,
                            )
                            if si + sj == subdiv:
                                shared_z = shared_edge_z_at(model, pos_key(fwx, fwy))
                                if shared_z is not None:
                                    wz_legacy = shared_z
                            return wz_legacy

                        wz, _route = hexpatch_v1_sampler.sample_world(
                            wx,
                            wy,
                            q_h,
                            r_h,
                            idw_fallback=_idw_fallback,
                            legacy_fallback=_legacy_fallback,
                        )
                    elif USE_HEXPATCH_SURFACE:
                        wz = sample_hexpatch_surface_world(
                            wx,
                            wy,
                            q_h,
                            r_h,
                            model,
                            radius=radius,
                        )
                    else:
                        wz = sample_smooth_domain_surface_world(
                            wx,
                            wy,
                            q_h,
                            r_h,
                            model,
                            radius=radius,
                            sector=sector,
                            at_sector_corner=at_corner,
                        )
                        if si + sj == subdiv:
                            shared_z = shared_edge_z_at(model, pos_key(wx, wy))
                            if shared_z is not None:
                                wz = shared_z
                    grid[(si, sj)] = add_top_vertex(
                        wx,
                        wy,
                        wz,
                        domain_id,
                        q_h,
                        r_h,
                        sector=sector,
                        at_sector_corner=at_corner,
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

    top_face_count = len(top_faces)
    side_face_count = len(skirt_faces) + len(chamfer_faces) + len(cliff_wall_faces)
    bottom_face_count = len(bottom_faces)
    all_faces = top_faces + skirt_faces + chamfer_faces + cliff_wall_faces + bottom_faces

    mesh = bpy.data.meshes.new("TerrainMapFull01")
    mesh.from_pydata(verts, [], all_faces)
    baseline.apply_patch_shading(mesh, top_face_count, side_face_count)
    baseline._finalize_mesh(mesh)

    stats = {
        "top_verts": len(set(top_cache.values())),
        "top_faces": top_face_count,
        "cliff_wall_faces": len(cliff_wall_faces),
        "cliff_wall_verts": len(verts) - cliff_wall_verts_before,
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
    if hexpatch_v1_sampler is not None:
        stats["hexpatch_v1_sample_stats"] = hexpatch_v1_sampler.stats.as_dict()
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


def _save_blend(output_path: Path) -> None:
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
    if USE_HEXPATCH_V1_SURFACE and not USE_HEXPATCH_SURFACE:
        _log(
            "note: USE_HEXPATCH_V1_SURFACE=True uses IDW fallback on cliff-adjacent tiles; "
            "USE_HEXPATCH_SURFACE=False only affects non-v1 legacy path."
        )

    terrain_map = parse_terrain_map_json(TERRAIN_MAP_JSON)
    model = build_terrain_model(terrain_map)

    repo_root, examined_starts = _resolve_repo_root()
    _log(f"repo root: {repo_root}")

    core_path = Path(getattr(_terrain_math, "__file__", SCRIPT_DIR / "eom_terrain_math_core.py"))
    hexpatch_v1_sampler: object | None = None
    v1_audits: object | None = None
    if USE_HEXPATCH_V1_SURFACE:
        v1_surface = _load_hexpatch_v1_surface(core_path)
        v1_audits = _load_hexpatch_v1_audits(core_path)
        hexpatch_v1_sampler = v1_surface.HexPatchV1SurfaceSampler.from_model(
            model,
            radius=DEFAULT_HEX_RADIUS,
        )

    baseline = _load_baseline_module(repo_root, examined_starts=examined_starts)
    _assert_baseline_unchanged(baseline)
    baseline.validate_params()
    baseline.validate_material_params()

    blend_filename = (
        OUTPUT_BLEND_FILENAME_HEXPATCH_V1
        if USE_HEXPATCH_V1_SURFACE
        else OUTPUT_BLEND_FILENAME
    )
    output_path = (
        repo_root
        / "game"
        / "assets"
        / "prototype"
        / "3d"
        / "terrain"
        / "prototype_3d_terrain"
        / "generated"
        / blend_filename
    )

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
    else:
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

    terrain_mesh, stats = build_analytic_terrain_mesh(
        model,
        baseline,
        hexpatch_v1_sampler=hexpatch_v1_sampler,
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
    _log(
        "cliff edges with solid fill: "
        f"{stats['cliff_edges_filled']} / {len(model.cliff_edge_graph)}"
    )
    _log(f"cliff wall segments filled: {stats['cliff_segments_filled']}")
    _log(f"cliff wall segments skipped (degenerate): {stats['cliff_segments_skipped']}")
    all_cliffs_filled = stats["cliff_edges_filled"] == len(model.cliff_edge_graph)
    _log(f"all cliff edges received solid fill: {all_cliffs_filled}")
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

    if SAVE_BLEND:
        _save_blend(output_path)
        _log(f"saved blend: {output_path}")

    _log("done")


if __name__ == "__main__":
    main()
