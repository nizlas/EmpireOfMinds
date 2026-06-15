# Empire of Minds — 7-hex single-patch PBR ground + stone + ash world-UV prototype (Blender only).
# Run from Blender Scripting workspace: Open → Run Script.
# Requires bpy (not available outside Blender).
#
# Builds on the approved ground + stone PBR UV baseline and adds full ash PBR via the
# existing ash splat weight. Stone weight applies unchanged after ground/ash blending.
#
# Milestones preserved elsewhere:
#   generate_terrain_prototype.py
#   generate_terrain_heightfield_prototype.py
#   generate_terrain_single_patch_prototype.py
#   generate_terrain_single_patch_material_prototype.py
#   generate_terrain_single_patch_pbr_ground_prototype.py
#   generate_terrain_single_patch_pbr_ground_uv_prototype.py
#   generate_terrain_single_patch_pbr_ground_stone_prototype.py
#
# Future Godot picking (not implemented here):
#   1. raycast against EOM_Terrain_SinglePatch
#   2. read world hit position
#   3. world XY → axial (q, r)
#   4. lookup hex gameplay data

import math
from dataclasses import dataclass
from pathlib import Path

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Tunable parameters
# ---------------------------------------------------------------------------

HEX_RADIUS = 1.0
BASE_THICKNESS = 0.35
ELEVATION_STEP = 0.4

PLAIN_LEVEL = 0
HILL_LEVEL = 1
HILL_AXIAL_Q = 1
HILL_AXIAL_R = 0

SURFACE_SUBDIVISIONS = 12

BASE_HEIGHT = 0.0
HILL_RADIUS = HEX_RADIUS * 2.2
HILL_HEIGHT = ELEVATION_STEP
HILL_PROFILE = "smootherstep"

TOP_FLATTEN_RADIUS = 0.0
TOP_FLATTEN_STRENGTH = 0.0

OUTER_RIM_DROP = 0.08
OUTER_RIM_PROFILE = "smoothstep"

CREATE_HEX_OVERLAY = True
HEX_OVERLAY_HEIGHT_OFFSET = 0.02
HEX_OVERLAY_THICKNESS = 0.008

OUTPUT_BLEND_FILENAME = (
    "terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.blend"
)
OUTPUT_GLB_FILENAME = (
    "terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.glb"
)
OUTPUT_ASSETS_MARKER = "game/assets/prototype/3d/terrain"

SAVE_BLEND = True
EXPORT_GLB = False

# ---------------------------------------------------------------------------
# APPROVED BLENDER PORTING BASELINE
# Verified in Blender 5.1.2.
# This is the reproducible source baseline for the upcoming Godot port.
# Overall luminance is not final and must be validated in Godot runtime lighting.
# Do not retune during the port unless a dedicated baseline revision is requested.
#
# This baseline is approved as the reproducible Blender source for Godot porting.
# Overall luminance remains subject to validation in the Godot runtime lighting
# environment. Do not retune this Blender source during the port unless a dedicated
# baseline revision is explicitly requested.
# ---------------------------------------------------------------------------

ALLOW_BLENDER_PORTING_BASELINE_RETUNE = False

APPROVED_BLENDER_PORTING_BASELINE = {
    "ASH_ALBEDO_TINT_STRENGTH": 0.0,
    "ASH_NORMAL_STRENGTH": 0.55,
    "ASH_ROUGHNESS_MULTIPLIER": 1.0,
    "ASH_ROUGHNESS_VARIATION_STRENGTH": 0.0,
    "ASH_WEIGHT_INPUT_MIN": 0.30,
    "ASH_WEIGHT_INPUT_MAX": 0.95,
    "USE_ASH_BREAKUP": True,
    "ASH_BREAKUP_NOISE_SCALE": 0.75,
    "ASH_BREAKUP_NOISE_DETAIL": 2.0,
    "ASH_BREAKUP_NOISE_ROUGHNESS": 0.55,
    "ASH_BREAKUP_MIN": 0.35,
    "ASH_BREAKUP_MAX": 0.75,
    "ASH_BREAKUP_STRENGTH": 0.75,
    "STONE_ALBEDO_MULTIPLIER": 0.55,
    "STONE_ALBEDO_TINT_STRENGTH": 0.0,
    "STONE_NORMAL_STRENGTH": 0.65,
    "STONE_ROUGHNESS_MULTIPLIER": 1.0,
    "STONE_ROUGHNESS_VARIATION_STRENGTH": 0.0,
    "USE_SLOPE_BLEND": True,
    "USE_LARGE_SCALE_VARIATION": True,
    "USE_FINE_DETAIL": False,
    "USE_ROUGHNESS_VARIATION": True,
    "USE_PROCEDURAL_BUMP": True,
    "LARGE_NOISE_SCALE": 0.18,
    "LARGE_NOISE_DETAIL": 4.0,
    "LARGE_NOISE_ROUGHNESS": 0.45,
    "FINE_NOISE_SCALE": 2.8,
    "FINE_NOISE_DETAIL": 8.0,
    "FINE_NOISE_STRENGTH": 0.10,
    "SLOPE_BLEND_START": 0.96,
    "SLOPE_BLEND_END": 0.90,
    "USE_STONE_BREAKUP": True,
    "STONE_BREAKUP_NOISE_SCALE": 2.0,
    "STONE_BREAKUP_NOISE_DETAIL": 1,
    "STONE_BREAKUP_NOISE_ROUGHNESS": 1,
    "STONE_BREAKUP_STRENGTH": 0.080,
    "BASE_ROUGHNESS": 0.88,
    "ROUGHNESS_VARIATION_STRENGTH": 0.08,
    "BUMP_STRENGTH": 0.12,
    "BUMP_DISTANCE": 0.02,
    "WORLD_UV_SCALE": 0.35,
    "WORLD_UV_LAYER_NAME": "EOM_WorldUV",
    "GROUND_ALBEDO_TINT_STRENGTH": 0.15,
    "GROUND_NORMAL_STRENGTH": 0.65,
    "GROUND_ROUGHNESS_MULTIPLIER": 1.0,
    "GROUND_ROUGHNESS_VARIATION_STRENGTH": 0.08,
    "DEBUG_MATERIAL_STAGE": "final",
}

# Approved Blender porting baseline for ash PBR.
# Do not retune during unrelated work or during the Godot port.
ASH_TEXTURE_SOURCE_DIR = (
    "game/assets/prototype/3d/terrain/prototype_3d_terrain/source/materials/ash"
)
ASH_ALBEDO_FILENAME = "ash_albedo.png"
ASH_NORMAL_FILENAME = "ash_normal.png"
ASH_ROUGHNESS_FILENAME = "ash_roughness.png"

ASH_ALBEDO_TINT_STRENGTH = 0.0
ASH_NORMAL_STRENGTH = 0.55
ASH_ROUGHNESS_MULTIPLIER = 1.0
ASH_ROUGHNESS_VARIATION_STRENGTH = 0.0

# Approved Blender porting baseline for ash coverage and breakup.
# Preserves broad world structure while producing local ash fields.
ASH_WEIGHT_INPUT_MIN = 0.30
ASH_WEIGHT_INPUT_MAX = 0.95

# Ash breakup subdivides the existing broad regional ash source into softer local ash fields.
# It must not create fine speckle, hard islands, or high-frequency mottling.
USE_ASH_BREAKUP = True

ASH_BREAKUP_NOISE_SCALE = 0.75
ASH_BREAKUP_NOISE_DETAIL = 2.0
ASH_BREAKUP_NOISE_ROUGHNESS = 0.55

ASH_BREAKUP_MIN = 0.35
ASH_BREAKUP_MAX = 0.75
ASH_BREAKUP_STRENGTH = 0.75

# Approved Blender porting baseline for stone PBR.
# Do not retune during unrelated work or during the Godot port.
STONE_TEXTURE_SOURCE_DIR = (
    "game/assets/prototype/3d/terrain/prototype_3d_terrain/source/materials/stone"
)
STONE_ALBEDO_FILENAME = "stone_albedo.png"
STONE_NORMAL_FILENAME = "stone_normal.png"
STONE_ROUGHNESS_FILENAME = "stone_roughness.png"

# Darkens the generated stone albedo before splat blending.
# 1.0 preserves the source texture; lower values darken it.
# Do not use this control to change stone-mask coverage.
STONE_ALBEDO_MULTIPLIER = 0.55

STONE_ALBEDO_TINT_STRENGTH = 0.0
STONE_NORMAL_STRENGTH = 0.65
STONE_ROUGHNESS_MULTIPLIER = 1.0
STONE_ROUGHNESS_VARIATION_STRENGTH = 0.0

# Procedural material toggles and palette (proof-of-concept; colors replaceable later).
USE_SLOPE_BLEND = True
USE_LARGE_SCALE_VARIATION = True
# Fine-detail albedo modulation is intentionally disabled in the Blender porting baseline.
# When enabled, it produced a global gray patchy haze over the clean
# ground/ash/stone PBR result.
# The parameters remain for future dedicated experiments only.
USE_FINE_DETAIL = False
USE_ROUGHNESS_VARIATION = True
USE_PROCEDURAL_BUMP = True

# Damped dark olive-brown ground / dark ashy soil / cold blue-gray stone.
GROUND_BASE_COLOR = (0.08, 0.11, 0.045, 1.0)
ASH_BASE_COLOR = (0.055, 0.045, 0.035, 1.0)
STONE_BASE_COLOR = (0.16, 0.21, 0.27, 1.0)

LARGE_NOISE_SCALE = 0.18
LARGE_NOISE_DETAIL = 4.0
LARGE_NOISE_ROUGHNESS = 0.45

# Fine-noise parameters remain for future dedicated experiments; inactive while USE_FINE_DETAIL=False.
FINE_NOISE_SCALE = 2.8
FINE_NOISE_DETAIL = 8.0
FINE_NOISE_STRENGTH = 0.10

# Normal Z: higher = flatter; stone increases as Z falls between these thresholds.
SLOPE_BLEND_START = 0.96
SLOPE_BLEND_END = 0.90

# Low-frequency noise perturbs the stone transition boundary away from a clean radial ring.
USE_STONE_BREAKUP = True
STONE_BREAKUP_NOISE_SCALE = 2.0
STONE_BREAKUP_NOISE_DETAIL = 1
STONE_BREAKUP_NOISE_ROUGHNESS = 1
STONE_BREAKUP_STRENGTH = 0.080

BASE_ROUGHNESS = 0.88
ROUGHNESS_VARIATION_STRENGTH = 0.08

BUMP_STRENGTH = 0.12
BUMP_DISTANCE = 0.02

# Tileable ground PBR inputs (resolved from repo root at runtime).
GROUND_TEXTURE_SOURCE_DIR = (
    "game/assets/prototype/3d/terrain/prototype_3d_terrain/source/materials/ground"
)
GROUND_ALBEDO_FILENAME = "ground_albedo.png"
GROUND_NORMAL_FILENAME = "ground_normal.png"
GROUND_ROUGHNESS_FILENAME = "ground_roughness.png"

# Higher = more tile repeats per world unit; lower = larger material detail.
# Must stay shared across all future terrain chunks (same origin, axes, scale).
WORLD_UV_SCALE = 0.35
WORLD_UV_LAYER_NAME = "EOM_WorldUV"

GROUND_ALBEDO_TINT_STRENGTH = 0.15
GROUND_NORMAL_STRENGTH = 0.65
GROUND_ROUGHNESS_MULTIPLIER = 1.0
GROUND_ROUGHNESS_VARIATION_STRENGTH = 0.08

# Route procedural color stages directly to Principled Base Color for Blender debugging.
DEBUG_MATERIAL_STAGE = "final"
VALID_DEBUG_MATERIAL_STAGES = (
    "ground",
    "ground_albedo",
    "ground_roughness",
    "ground_pbr",
    "ash_albedo",
    "ash_albedo_raw",
    "ash_albedo_diffuse",
    "ash_normal",
    "ash_roughness",
    "ash_mask",
    "ash_mask_raw",
    "ash_breakup_raw",
    "ash_mask_combined_raw",
    "ash_mask_remapped_raw",
    "ground_ash_pbr",
    "stone_albedo",
    "stone_normal",
    "stone_roughness",
    "ground_stone_pbr",
    "ground_stone_ash_pbr",
    "ash",
    "ground_ash",
    "stone_mask",
    "stone",
    "fine",
    "final",
)

# Object-space coordinates from the single-patch mesh (continuous over the whole patch).
MATERIAL_COORD_SOURCE = "Object"

COLLECTION_NAME = "EOM_Terrain_Prototype"
TERRAIN_OBJECT_NAME = "EOM_Terrain_SinglePatch"
OVERLAY_OBJECT_NAME = "EOM_Hex_Overlay"
PROCEDURAL_MATERIAL_NAME = "EOM_Terrain_PBR_Ground_Stone_Ash_Prototype"
SIDE_MATERIAL_NAME = "EOM_Terrain_Side_PBR_Ground_Stone_Ash_Prototype"
OVERLAY_MATERIAL_NAME = "EOM_Hex_Overlay"
CAMERA_NAME = "PrototypeCamera"
SUN_NAME = "PrototypeSun"

WORLD_XY_TOLERANCE = 1e-5
WORLD_Z_TOLERANCE = 1e-5
HEIGHT_TOLERANCE = 1e-5

# Resolved at runtime via resolve_output_paths() (Blender Text Block safe).
REPO_ROOT: Path | None = None
OUTPUT_DIR: Path | None = None
OUTPUT_BLEND_PATH: Path | None = None
OUTPUT_GLB_PATH: Path | None = None
_OUTPUT_START_PATH: Path | None = None


def _log(message: str) -> None:
    print(f"[EOM terrain ash PBR] {message}")


def _audit_log(message: str) -> None:
    print(f"[EOM ash brightness audit] {message}")


def _optional_input(node: bpy.types.Node, *socket_names: str):
    for name in socket_names:
        sock = node.inputs.get(name)
        if sock is not None:
            return sock
    return None


def _optional_output(node: bpy.types.Node, *socket_names: str):
    for name in socket_names:
        sock = node.outputs.get(name)
        if sock is not None:
            return sock
    return None


def _set_optional_input_default(
    node: bpy.types.Node,
    socket_names: tuple[str, ...],
    value,
    *,
    log_label: str,
) -> bool:
    sock = _optional_input(node, *socket_names)
    if sock is None:
        _log(f"diagnostic diffuse: {log_label} socket not available")
        return False
    sock.default_value = value
    return True


ASH_WEIGHT_REMAP_FLOAT_TOLERANCE = 1e-6


def _float_default_value(socket: bpy.types.NodeSocket) -> float:
    value = socket.default_value
    if isinstance(value, (int, float)):
        return float(value)
    raise RuntimeError(
        f"expected float socket default on {socket.node.name}.{socket.name}, "
        f"got {type(value)!r}"
    )


def _float_defaults_close(
    actual: float,
    expected: float,
    *,
    rel_tol: float = ASH_WEIGHT_REMAP_FLOAT_TOLERANCE,
    abs_tol: float = ASH_WEIGHT_REMAP_FLOAT_TOLERANCE,
) -> bool:
    return math.isclose(actual, expected, rel_tol=rel_tol, abs_tol=abs_tol)


def _map_range_float_input(node: bpy.types.Node, label: str) -> bpy.types.NodeSocket:
    fallbacks = {
        "From Min": ("From_Min",),
        "From Max": ("From_Max",),
        "To Min": ("To_Min",),
        "To Max": ("To_Max",),
    }
    return _require_input(node, label, *fallbacks.get(label, ()))


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    for candidate in [start, *start.parents]:
        if (candidate / "game").is_dir() and (candidate / "tools").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate Empire of Minds repo root from: {start}")


def _candidate_start_paths() -> list[Path]:
    candidates: list[Path] = []
    seen: set[str] = set()

    def add(path: Path | None) -> None:
        if path is None:
            return
        try:
            resolved = path.resolve()
        except OSError:
            return
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

    return candidates


def _assert_output_path_not_duplicated(path: Path) -> None:
    normalized = path.resolve().as_posix().lower()
    marker = OUTPUT_ASSETS_MARKER.lower()
    if normalized.count(marker) > 1:
        raise RuntimeError(
            f"Duplicated assets path segment in output path: {path}"
        )


def resolve_output_paths() -> tuple[Path, Path, Path, Path]:
    global REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH, _OUTPUT_START_PATH

    if (
        REPO_ROOT is not None
        and OUTPUT_DIR is not None
        and OUTPUT_BLEND_PATH is not None
        and OUTPUT_GLB_PATH is not None
    ):
        return REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH

    start_paths = _candidate_start_paths()
    if not start_paths:
        raise RuntimeError(
            "No start path candidates for repo root resolution. "
            "Open the external .py file in Blender or save the .blend inside the repo."
        )

    last_error: RuntimeError | None = None
    repo_root: Path | None = None
    used_start: Path | None = None
    for start in start_paths:
        try:
            repo_root = find_repo_root(start)
            used_start = start
            break
        except RuntimeError as exc:
            last_error = exc

    if repo_root is None or used_start is None:
        raise RuntimeError(
            "Could not locate Empire of Minds repo root from any candidate. "
            f"Last error: {last_error}"
        )

    output_dir = (
        repo_root
        / "game"
        / "assets"
        / "prototype"
        / "3d"
        / "terrain"
        / "prototype_3d_terrain"
        / "generated"
    )
    blend_path = output_dir / OUTPUT_BLEND_FILENAME
    glb_path = output_dir / OUTPUT_GLB_FILENAME

    for path in (output_dir, blend_path, glb_path):
        _assert_output_path_not_duplicated(path)

    REPO_ROOT = repo_root
    OUTPUT_DIR = output_dir
    OUTPUT_BLEND_PATH = blend_path
    OUTPUT_GLB_PATH = glb_path
    _OUTPUT_START_PATH = used_start

    _log(f"Repo root: {repo_root} (from start: {used_start})")
    _log(f"Output blend: {blend_path}")
    return repo_root, output_dir, blend_path, glb_path


def orient_upward_triangle(
    vertices: list[tuple[float, float, float]],
    a: int,
    b: int,
    c: int,
) -> tuple[int, int, int]:
    va = Vector(vertices[a])
    vb = Vector(vertices[b])
    vc = Vector(vertices[c])
    normal_z = (vb - va).cross(vc - va).z
    if abs(normal_z) < 1e-10:
        raise RuntimeError(f"Degenerate top triangle: {(a, b, c)}")
    if normal_z < 0.0:
        return (a, c, b)
    return (a, b, c)


def append_upward_triangle(
    faces: list[tuple[int, int, int]],
    vertices: list[tuple[float, float, float]],
    a: int,
    b: int,
    c: int,
) -> None:
    faces.append(orient_upward_triangle(vertices, a, b, c))


def validate_top_face_winding(
    vertices: list[tuple[float, float, float]],
    top_faces: list[tuple[int, int, int]],
) -> None:
    upward = 0
    downward = 0
    for a, b, c in top_faces:
        va = Vector(vertices[a])
        vb = Vector(vertices[b])
        vc = Vector(vertices[c])
        normal_z = (vb - va).cross(vc - va).z
        if abs(normal_z) < 1e-10:
            raise RuntimeError(f"Degenerate top triangle in validation: {(a, b, c)}")
        if normal_z < 0.0:
            downward += 1
        else:
            upward += 1
    if downward > 0:
        raise RuntimeError(
            f"Top face winding invalid: {upward} upward, {downward} downward"
        )
    _log(f"Top face winding validated: {upward} upward, {downward} downward")


def _blender_version_label() -> str:
    ver = bpy.app.version
    return f"{ver[0]}.{ver[1]}.{ver[2]}"


def _active_scene() -> bpy.types.Scene:
    if bpy.context.scene is not None:
        return bpy.context.scene
    if not bpy.data.scenes:
        raise RuntimeError("no Blender scene available")
    return bpy.data.scenes[0]


def _require_input(node: bpy.types.Node, socket_name: str, *fallback_names: str):
    for name in (socket_name,) + fallback_names:
        sock = node.inputs.get(name)
        if sock is not None:
            return sock
    raise KeyError(
        f"{node.bl_idname} missing input {socket_name!r}"
        + (f" (also tried {fallback_names})" if fallback_names else "")
    )


def _require_output(node: bpy.types.Node, socket_name: str, *fallback_names: str):
    for name in (socket_name,) + fallback_names:
        sock = node.outputs.get(name)
        if sock is not None:
            return sock
    raise KeyError(
        f"{node.bl_idname} missing output {socket_name!r}"
        + (f" (also tried {fallback_names})" if fallback_names else "")
    )


def _new_node(nodes: bpy.types.Nodes, *type_names: str) -> bpy.types.Node:
    last_error: RuntimeError | None = None
    for type_name in type_names:
        try:
            return nodes.new(type_name)
        except RuntimeError as exc:
            last_error = exc
    raise RuntimeError(f"could not create node {type_names}: {last_error}")


def _finalize_mesh(mesh: bpy.types.Mesh) -> None:
    """Blender 4.x/5.x: no Mesh.calc_normals(); update lets Blender build normals."""
    mesh.validate(verbose=True)
    mesh.update()


def _ops_context_override() -> dict:
    scene = _active_scene()
    wm = bpy.context.window_manager
    if wm is None or not wm.windows:
        return {"scene": scene}
    window = wm.windows[0]
    screen = window.screen
    for area in screen.areas:
        if area.type in {"VIEW_3D", "TEXT_EDITOR", "PROPERTIES", "OUTLINER"}:
            region = next((r for r in area.regions if r.type == "WINDOW"), None)
            if region is not None:
                return {
                    "window": window,
                    "screen": screen,
                    "area": area,
                    "region": region,
                    "scene": scene,
                }
    return {"window": window, "screen": screen, "scene": scene}


NEIGHBOR_DIRS = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)

PROTOTYPE_HEXES = (
    (0, 0, PLAIN_LEVEL, "Plain"),
    (HILL_AXIAL_Q, HILL_AXIAL_R, HILL_LEVEL, "Hill"),
    (1, -1, PLAIN_LEVEL, "Plain"),
    (0, -1, PLAIN_LEVEL, "Plain"),
    (-1, 0, PLAIN_LEVEL, "Plain"),
    (-1, 1, PLAIN_LEVEL, "Plain"),
    (0, 1, PLAIN_LEVEL, "Plain"),
)


def validate_params() -> None:
    if not isinstance(SURFACE_SUBDIVISIONS, int) or SURFACE_SUBDIVISIONS < 1:
        raise ValueError(
            f"SURFACE_SUBDIVISIONS must be an integer >= 1, got {SURFACE_SUBDIVISIONS!r}"
        )
    if HILL_RADIUS <= 0.0:
        raise ValueError(f"HILL_RADIUS must be > 0, got {HILL_RADIUS!r}")
    if HILL_HEIGHT < 0.0:
        raise ValueError(f"HILL_HEIGHT must be >= 0, got {HILL_HEIGHT!r}")
    if HILL_PROFILE not in ("smootherstep", "quadratic"):
        raise ValueError(
            f"HILL_PROFILE must be 'smootherstep' or 'quadratic', got {HILL_PROFILE!r}"
        )
    if not (0.0 <= TOP_FLATTEN_STRENGTH <= 1.0):
        raise ValueError(
            f"TOP_FLATTEN_STRENGTH must be in [0, 1], got {TOP_FLATTEN_STRENGTH!r}"
        )
    if TOP_FLATTEN_RADIUS < 0.0:
        raise ValueError(
            f"TOP_FLATTEN_RADIUS must be >= 0, got {TOP_FLATTEN_RADIUS!r}"
        )
    if OUTER_RIM_DROP < 0.0:
        raise ValueError(f"OUTER_RIM_DROP must be >= 0, got {OUTER_RIM_DROP!r}")


def _validate_rgba_tuple(name: str, value: tuple[float, float, float, float]) -> None:
    if len(value) != 4:
        raise ValueError(f"{name} must be an RGBA 4-tuple, got {value!r}")
    for channel in value:
        if channel < 0.0 or channel > 1.0:
            raise ValueError(f"{name} channels must be in [0, 1], got {value!r}")


def validate_material_params() -> None:
    for name, color in (
        ("GROUND_BASE_COLOR", GROUND_BASE_COLOR),
        ("ASH_BASE_COLOR", ASH_BASE_COLOR),
        ("STONE_BASE_COLOR", STONE_BASE_COLOR),
    ):
        _validate_rgba_tuple(name, color)

    if LARGE_NOISE_SCALE <= 0.0:
        raise ValueError(f"LARGE_NOISE_SCALE must be > 0, got {LARGE_NOISE_SCALE!r}")
    if FINE_NOISE_SCALE <= 0.0:
        raise ValueError(f"FINE_NOISE_SCALE must be > 0, got {FINE_NOISE_SCALE!r}")
    if SLOPE_BLEND_START <= SLOPE_BLEND_END:
        raise ValueError(
            f"SLOPE_BLEND_START must be > SLOPE_BLEND_END, "
            f"got start={SLOPE_BLEND_START!r}, end={SLOPE_BLEND_END!r}"
        )
    if STONE_BREAKUP_NOISE_SCALE <= 0.0:
        raise ValueError(
            f"STONE_BREAKUP_NOISE_SCALE must be > 0, got {STONE_BREAKUP_NOISE_SCALE!r}"
        )
    if STONE_BREAKUP_STRENGTH < 0.0:
        raise ValueError(
            f"STONE_BREAKUP_STRENGTH must be >= 0, got {STONE_BREAKUP_STRENGTH!r}"
        )
    if not (0.0 <= BASE_ROUGHNESS <= 1.0):
        raise ValueError(f"BASE_ROUGHNESS must be in [0, 1], got {BASE_ROUGHNESS!r}")
    if ROUGHNESS_VARIATION_STRENGTH < 0.0:
        raise ValueError(
            f"ROUGHNESS_VARIATION_STRENGTH must be >= 0, got {ROUGHNESS_VARIATION_STRENGTH!r}"
        )
    if BUMP_STRENGTH < 0.0:
        raise ValueError(f"BUMP_STRENGTH must be >= 0, got {BUMP_STRENGTH!r}")
    if BUMP_DISTANCE < 0.0:
        raise ValueError(f"BUMP_DISTANCE must be >= 0, got {BUMP_DISTANCE!r}")
    if FINE_NOISE_STRENGTH < 0.0:
        raise ValueError(f"FINE_NOISE_STRENGTH must be >= 0, got {FINE_NOISE_STRENGTH!r}")
    if MATERIAL_COORD_SOURCE not in ("Object", "Generated"):
        raise ValueError(
            f"MATERIAL_COORD_SOURCE must be 'Object' or 'Generated', "
            f"got {MATERIAL_COORD_SOURCE!r}"
        )
    if DEBUG_MATERIAL_STAGE not in VALID_DEBUG_MATERIAL_STAGES:
        raise ValueError(
            f"DEBUG_MATERIAL_STAGE must be one of {VALID_DEBUG_MATERIAL_STAGES!r}, "
            f"got {DEBUG_MATERIAL_STAGE!r}"
        )
    if WORLD_UV_SCALE <= 0.0:
        raise ValueError(f"WORLD_UV_SCALE must be > 0, got {WORLD_UV_SCALE!r}")
    if not WORLD_UV_LAYER_NAME:
        raise ValueError("WORLD_UV_LAYER_NAME must be a non-empty string")
    if GROUND_NORMAL_STRENGTH <= 0.0:
        raise ValueError(
            f"GROUND_NORMAL_STRENGTH must be > 0 for tangent-space normal verification, "
            f"got {GROUND_NORMAL_STRENGTH!r}"
        )
    if not (0.0 <= GROUND_ALBEDO_TINT_STRENGTH <= 1.0):
        raise ValueError(
            f"GROUND_ALBEDO_TINT_STRENGTH must be in [0, 1], got {GROUND_ALBEDO_TINT_STRENGTH!r}"
        )
    if GROUND_NORMAL_STRENGTH < 0.0:
        raise ValueError(f"GROUND_NORMAL_STRENGTH must be >= 0, got {GROUND_NORMAL_STRENGTH!r}")
    if GROUND_ROUGHNESS_MULTIPLIER < 0.0:
        raise ValueError(
            f"GROUND_ROUGHNESS_MULTIPLIER must be >= 0, got {GROUND_ROUGHNESS_MULTIPLIER!r}"
        )
    if GROUND_ROUGHNESS_VARIATION_STRENGTH < 0.0:
        raise ValueError(
            f"GROUND_ROUGHNESS_VARIATION_STRENGTH must be >= 0, "
            f"got {GROUND_ROUGHNESS_VARIATION_STRENGTH!r}"
        )
    if STONE_NORMAL_STRENGTH <= 0.0:
        raise ValueError(
            f"STONE_NORMAL_STRENGTH must be > 0 for tangent-space stone normal, "
            f"got {STONE_NORMAL_STRENGTH!r}"
        )
    if not (0.0 <= STONE_ALBEDO_TINT_STRENGTH <= 1.0):
        raise ValueError(
            f"STONE_ALBEDO_TINT_STRENGTH must be in [0, 1], got {STONE_ALBEDO_TINT_STRENGTH!r}"
        )
    if not (0.0 <= STONE_ALBEDO_MULTIPLIER <= 2.0):
        raise ValueError(
            f"STONE_ALBEDO_MULTIPLIER must be in [0, 2], got {STONE_ALBEDO_MULTIPLIER!r}"
        )
    if STONE_ROUGHNESS_MULTIPLIER < 0.0:
        raise ValueError(
            f"STONE_ROUGHNESS_MULTIPLIER must be >= 0, got {STONE_ROUGHNESS_MULTIPLIER!r}"
        )
    if STONE_ROUGHNESS_VARIATION_STRENGTH < 0.0:
        raise ValueError(
            f"STONE_ROUGHNESS_VARIATION_STRENGTH must be >= 0, "
            f"got {STONE_ROUGHNESS_VARIATION_STRENGTH!r}"
        )
    if ASH_NORMAL_STRENGTH <= 0.0:
        raise ValueError(
            f"ASH_NORMAL_STRENGTH must be > 0 for tangent-space ash normal, "
            f"got {ASH_NORMAL_STRENGTH!r}"
        )
    if not (0.0 <= ASH_ALBEDO_TINT_STRENGTH <= 1.0):
        raise ValueError(
            f"ASH_ALBEDO_TINT_STRENGTH must be in [0, 1], got {ASH_ALBEDO_TINT_STRENGTH!r}"
        )
    if ASH_ROUGHNESS_MULTIPLIER < 0.0:
        raise ValueError(
            f"ASH_ROUGHNESS_MULTIPLIER must be >= 0, got {ASH_ROUGHNESS_MULTIPLIER!r}"
        )
    if ASH_ROUGHNESS_VARIATION_STRENGTH < 0.0:
        raise ValueError(
            f"ASH_ROUGHNESS_VARIATION_STRENGTH must be >= 0, "
            f"got {ASH_ROUGHNESS_VARIATION_STRENGTH!r}"
        )
    if ASH_WEIGHT_INPUT_MAX <= ASH_WEIGHT_INPUT_MIN:
        raise ValueError(
            f"ASH_WEIGHT_INPUT_MAX must be > ASH_WEIGHT_INPUT_MIN, "
            f"got min={ASH_WEIGHT_INPUT_MIN!r} max={ASH_WEIGHT_INPUT_MAX!r}"
        )
    if not (0.0 <= ASH_BREAKUP_STRENGTH <= 1.0):
        raise ValueError(
            f"ASH_BREAKUP_STRENGTH must be in [0, 1], got {ASH_BREAKUP_STRENGTH!r}"
        )
    if ASH_BREAKUP_MAX <= ASH_BREAKUP_MIN:
        raise ValueError(
            f"ASH_BREAKUP_MAX must be > ASH_BREAKUP_MIN, "
            f"got min={ASH_BREAKUP_MIN!r} max={ASH_BREAKUP_MAX!r}"
        )
    _validate_blender_porting_baseline()


def _validate_blender_porting_baseline() -> None:
    if ALLOW_BLENDER_PORTING_BASELINE_RETUNE:
        _log("WARNING: Blender porting baseline retuning is enabled")
        return

    current_values = {
        "ASH_ALBEDO_TINT_STRENGTH": ASH_ALBEDO_TINT_STRENGTH,
        "ASH_NORMAL_STRENGTH": ASH_NORMAL_STRENGTH,
        "ASH_ROUGHNESS_MULTIPLIER": ASH_ROUGHNESS_MULTIPLIER,
        "ASH_ROUGHNESS_VARIATION_STRENGTH": ASH_ROUGHNESS_VARIATION_STRENGTH,
        "ASH_WEIGHT_INPUT_MIN": ASH_WEIGHT_INPUT_MIN,
        "ASH_WEIGHT_INPUT_MAX": ASH_WEIGHT_INPUT_MAX,
        "USE_ASH_BREAKUP": USE_ASH_BREAKUP,
        "ASH_BREAKUP_NOISE_SCALE": ASH_BREAKUP_NOISE_SCALE,
        "ASH_BREAKUP_NOISE_DETAIL": ASH_BREAKUP_NOISE_DETAIL,
        "ASH_BREAKUP_NOISE_ROUGHNESS": ASH_BREAKUP_NOISE_ROUGHNESS,
        "ASH_BREAKUP_MIN": ASH_BREAKUP_MIN,
        "ASH_BREAKUP_MAX": ASH_BREAKUP_MAX,
        "ASH_BREAKUP_STRENGTH": ASH_BREAKUP_STRENGTH,
        "STONE_ALBEDO_MULTIPLIER": STONE_ALBEDO_MULTIPLIER,
        "STONE_ALBEDO_TINT_STRENGTH": STONE_ALBEDO_TINT_STRENGTH,
        "STONE_NORMAL_STRENGTH": STONE_NORMAL_STRENGTH,
        "STONE_ROUGHNESS_MULTIPLIER": STONE_ROUGHNESS_MULTIPLIER,
        "STONE_ROUGHNESS_VARIATION_STRENGTH": STONE_ROUGHNESS_VARIATION_STRENGTH,
        "USE_SLOPE_BLEND": USE_SLOPE_BLEND,
        "USE_LARGE_SCALE_VARIATION": USE_LARGE_SCALE_VARIATION,
        "USE_FINE_DETAIL": USE_FINE_DETAIL,
        "USE_ROUGHNESS_VARIATION": USE_ROUGHNESS_VARIATION,
        "USE_PROCEDURAL_BUMP": USE_PROCEDURAL_BUMP,
        "LARGE_NOISE_SCALE": LARGE_NOISE_SCALE,
        "LARGE_NOISE_DETAIL": LARGE_NOISE_DETAIL,
        "LARGE_NOISE_ROUGHNESS": LARGE_NOISE_ROUGHNESS,
        "FINE_NOISE_SCALE": FINE_NOISE_SCALE,
        "FINE_NOISE_DETAIL": FINE_NOISE_DETAIL,
        "FINE_NOISE_STRENGTH": FINE_NOISE_STRENGTH,
        "SLOPE_BLEND_START": SLOPE_BLEND_START,
        "SLOPE_BLEND_END": SLOPE_BLEND_END,
        "USE_STONE_BREAKUP": USE_STONE_BREAKUP,
        "STONE_BREAKUP_NOISE_SCALE": STONE_BREAKUP_NOISE_SCALE,
        "STONE_BREAKUP_NOISE_DETAIL": STONE_BREAKUP_NOISE_DETAIL,
        "STONE_BREAKUP_NOISE_ROUGHNESS": STONE_BREAKUP_NOISE_ROUGHNESS,
        "STONE_BREAKUP_STRENGTH": STONE_BREAKUP_STRENGTH,
        "BASE_ROUGHNESS": BASE_ROUGHNESS,
        "ROUGHNESS_VARIATION_STRENGTH": ROUGHNESS_VARIATION_STRENGTH,
        "BUMP_STRENGTH": BUMP_STRENGTH,
        "BUMP_DISTANCE": BUMP_DISTANCE,
        "WORLD_UV_SCALE": WORLD_UV_SCALE,
        "WORLD_UV_LAYER_NAME": WORLD_UV_LAYER_NAME,
        "GROUND_ALBEDO_TINT_STRENGTH": GROUND_ALBEDO_TINT_STRENGTH,
        "GROUND_NORMAL_STRENGTH": GROUND_NORMAL_STRENGTH,
        "GROUND_ROUGHNESS_MULTIPLIER": GROUND_ROUGHNESS_MULTIPLIER,
        "GROUND_ROUGHNESS_VARIATION_STRENGTH": GROUND_ROUGHNESS_VARIATION_STRENGTH,
        "DEBUG_MATERIAL_STAGE": DEBUG_MATERIAL_STAGE,
    }

    mismatches: list[str] = []
    for name, expected in APPROVED_BLENDER_PORTING_BASELINE.items():
        actual = current_values[name]
        if isinstance(expected, bool):
            if actual is not expected:
                mismatches.append(f"{name}={actual!r}, expected {expected!r}")
            continue
        if isinstance(expected, str):
            if actual != expected:
                mismatches.append(f"{name}={actual!r}, expected {expected!r}")
            continue
        if not isinstance(actual, (int, float)):
            mismatches.append(f"{name}={actual!r}, expected {expected!r}")
            continue
        if not math.isclose(float(actual), float(expected), rel_tol=0.0, abs_tol=1e-9):
            mismatches.append(f"{name}={actual!r}, expected {expected!r}")

    if mismatches:
        raise RuntimeError(
            "Approved Blender porting baseline changed:\n"
            + "\n".join(mismatches)
            + "\n\nDeliberate retuning requires:\n"
            + "1. a dedicated Blender baseline revision task\n"
            + "2. ALLOW_BLENDER_PORTING_BASELINE_RETUNE=True\n"
            + "3. Blender visual verification\n"
            + "4. resetting the flag to False before completion"
        )


def resolve_ash_texture_paths(repo_root: Path) -> tuple[Path, Path, Path]:
    ash_dir = repo_root / Path(ASH_TEXTURE_SOURCE_DIR)
    albedo_path = ash_dir / ASH_ALBEDO_FILENAME
    normal_path = ash_dir / ASH_NORMAL_FILENAME
    roughness_path = ash_dir / ASH_ROUGHNESS_FILENAME
    expected = (
        ("albedo", albedo_path),
        ("normal", normal_path),
        ("roughness", roughness_path),
    )
    missing = [(label, path) for label, path in expected if not path.is_file()]
    if missing:
        lines = [
            "Missing required ash PBR texture file(s).",
            "Expected files:",
            f"  albedo:    {albedo_path.resolve()}",
            f"  normal:    {normal_path.resolve()}",
            f"  roughness: {roughness_path.resolve()}",
            "Missing:",
        ]
        for label, path in missing:
            lines.append(f"  {label}: {path.resolve()}")
        raise FileNotFoundError("\n".join(lines))
    return albedo_path, normal_path, roughness_path


def resolve_stone_texture_paths(repo_root: Path) -> tuple[Path, Path, Path]:
    stone_dir = repo_root / Path(STONE_TEXTURE_SOURCE_DIR)
    albedo_path = stone_dir / STONE_ALBEDO_FILENAME
    normal_path = stone_dir / STONE_NORMAL_FILENAME
    roughness_path = stone_dir / STONE_ROUGHNESS_FILENAME
    expected = (
        ("albedo", albedo_path),
        ("normal", normal_path),
        ("roughness", roughness_path),
    )
    missing = [(label, path) for label, path in expected if not path.is_file()]
    if missing:
        lines = [
            "Missing required stone PBR texture file(s).",
            "Expected files:",
            f"  albedo:    {albedo_path.resolve()}",
            f"  normal:    {normal_path.resolve()}",
            f"  roughness: {roughness_path.resolve()}",
            "Missing:",
        ]
        for label, path in missing:
            lines.append(f"  {label}: {path.resolve()}")
        raise FileNotFoundError("\n".join(lines))
    return albedo_path, normal_path, roughness_path


def resolve_ground_texture_paths(repo_root: Path) -> tuple[Path, Path, Path]:
    ground_dir = repo_root / Path(GROUND_TEXTURE_SOURCE_DIR)
    albedo_path = ground_dir / GROUND_ALBEDO_FILENAME
    normal_path = ground_dir / GROUND_NORMAL_FILENAME
    roughness_path = ground_dir / GROUND_ROUGHNESS_FILENAME
    expected = (
        ("albedo", albedo_path),
        ("normal", normal_path),
        ("roughness", roughness_path),
    )
    missing = [(label, path) for label, path in expected if not path.is_file()]
    if missing:
        lines = [
            "Missing required ground PBR texture file(s).",
            "Expected files:",
            f"  albedo:    {albedo_path.resolve()}",
            f"  normal:    {normal_path.resolve()}",
            f"  roughness: {roughness_path.resolve()}",
            "Missing:",
        ]
        for label, path in missing:
            lines.append(f"  {label}: {path.resolve()}")
        raise FileNotFoundError("\n".join(lines))
    return albedo_path, normal_path, roughness_path


def _set_image_colorspace(image: bpy.types.Image, colorspace: str) -> None:
    try:
        image.colorspace_settings.name = colorspace
    except (AttributeError, TypeError, ValueError) as exc:
        raise RuntimeError(
            f"Could not set colorspace {colorspace!r} on image {image.name!r}: {exc}"
        ) from exc
    actual = image.colorspace_settings.name
    if actual != colorspace:
        raise RuntimeError(
            f"Image {image.name!r} colorspace expected {colorspace!r}, got {actual!r}"
        )


def _load_pbr_image(
    image_name: str,
    filepath: Path,
    colorspace: str,
    *,
    missing_label: str,
) -> bpy.types.Image:
    resolved = filepath.resolve()
    if not resolved.is_file():
        raise FileNotFoundError(f"{missing_label} texture not found: {resolved}")

    filepath_str = str(resolved)
    existing = bpy.data.images.get(image_name)
    if existing is not None:
        existing_path = bpy.path.abspath(existing.filepath) if existing.filepath else ""
        if existing_path == filepath_str:
            _set_image_colorspace(existing, colorspace)
            return existing
        bpy.data.images.remove(existing)

    image = bpy.data.images.load(filepath_str, check_existing=True)
    image.name = image_name
    _set_image_colorspace(image, colorspace)
    return image


def _load_ground_image(
    image_name: str,
    filepath: Path,
    colorspace: str,
) -> bpy.types.Image:
    return _load_pbr_image(
        image_name,
        filepath,
        colorspace,
        missing_label="Ground",
    )


def _load_stone_image(
    image_name: str,
    filepath: Path,
    colorspace: str,
) -> bpy.types.Image:
    return _load_pbr_image(
        image_name,
        filepath,
        colorspace,
        missing_label="Stone",
    )


def _load_ash_image(
    image_name: str,
    filepath: Path,
    colorspace: str,
) -> bpy.types.Image:
    return _load_pbr_image(
        image_name,
        filepath,
        colorspace,
        missing_label="Ash",
    )


def _new_image_texture_node(
    nodes: bpy.types.Nodes,
    image: bpy.types.Image,
    location: tuple[float, float],
) -> bpy.types.Node:
    tex_node = _new_node(nodes, "ShaderNodeTexImage")
    tex_node.location = location
    tex_node.image = image
    tex_node.extension = "REPEAT"
    tex_node.interpolation = "Linear"
    return tex_node


def _new_vector_mix_node(
    nodes: bpy.types.Nodes,
    location: tuple[float, float],
) -> bpy.types.Node:
    mix_node = _new_node(nodes, "ShaderNodeMix")
    mix_node.data_type = "VECTOR"
    mix_node.blend_type = "MIX"
    mix_node.location = location
    return mix_node


def _new_float_mix_node(
    nodes: bpy.types.Nodes,
    location: tuple[float, float],
) -> bpy.types.Node:
    mix_node = _new_node(nodes, "ShaderNodeMix")
    mix_node.data_type = "FLOAT"
    mix_node.blend_type = "MIX"
    mix_node.location = location
    return mix_node


@dataclass
class ColorMixSockets:
    node: bpy.types.Node
    factor: bpy.types.NodeSocket
    color1: bpy.types.NodeSocket
    color2: bpy.types.NodeSocket
    output: bpy.types.NodeSocket
    node_type: str
    factor_name: str
    color1_name: str
    color2_name: str
    output_name: str


def _socket_is_active(socket: bpy.types.NodeSocket) -> bool:
    if getattr(socket, "hide", False):
        return False
    if hasattr(socket, "enabled") and not socket.enabled:
        return False
    return True


def _active_sockets_by_type(
    sockets,
    socket_type: str,
) -> list[bpy.types.NodeSocket]:
    return [
        socket
        for socket in sockets
        if _socket_is_active(socket)
        and socket.type == socket_type
    ]


def _socket_debug_label(socket: bpy.types.NodeSocket) -> str:
    identifier = getattr(socket, "identifier", socket.name)
    return f"name={socket.name} identifier={identifier} type={socket.type}"


def _socket_binding_label(socket: bpy.types.NodeSocket) -> str:
    identifier = getattr(socket, "identifier", socket.name)
    return f"{socket.name}:{identifier}:{socket.type}"


def _require_active_sockets_by_type(
    sockets,
    socket_type: str,
    *,
    role: str,
    node: bpy.types.Node,
    expected_count: int,
) -> list[bpy.types.NodeSocket]:
    matches = _active_sockets_by_type(sockets, socket_type)
    if len(matches) != expected_count:
        active_details = [
            f"- {_socket_debug_label(socket)}"
            for socket in sockets
            if _socket_is_active(socket)
        ]
        raise RuntimeError(
            f"Expected {expected_count} active {socket_type} {role} sockets on "
            f"{node.bl_idname!r}, found {len(matches)}.\n\n"
            f"Active {role}s:\n" + "\n".join(active_details)
        )
    return matches


def _require_active_socket(
    sockets,
    name: str,
    *,
    role: str,
    node: bpy.types.Node,
) -> bpy.types.NodeSocket:
    matches = [
        socket
        for socket in sockets
        if socket.name == name and _socket_is_active(socket)
    ]
    if len(matches) != 1:
        active_names = [
            socket.name for socket in sockets if _socket_is_active(socket)
        ]
        raise RuntimeError(
            f"Expected exactly one active {role} socket {name!r} on "
            f"{node.bl_idname!r}, found {len(matches)}; "
            f"active sockets: {active_names}"
        )
    return matches[0]


def _active_socket_names(sockets) -> list[str]:
    return [socket.name for socket in sockets if _socket_is_active(socket)]


def _log_color_mix_socket_inventory(node: bpy.types.Node) -> None:
    _log(f"{node.bl_idname} active inputs:")
    for socket in node.inputs:
        if _socket_is_active(socket):
            _log(f"  - {_socket_debug_label(socket)}")
    _log(f"{node.bl_idname} active outputs:")
    for socket in node.outputs:
        if _socket_is_active(socket):
            _log(f"  - {_socket_debug_label(socket)}")


def _log_color_mix_binding(sockets: ColorMixSockets) -> None:
    _log(
        "Color mix binding: "
        f"node_type={sockets.node_type} "
        f"factor={_socket_binding_label(sockets.factor)} "
        f"color1={_socket_binding_label(sockets.color1)} "
        f"color2={_socket_binding_label(sockets.color2)} "
        f"output={_socket_binding_label(sockets.output)}"
    )


def _assert_socket_type(
    socket: bpy.types.NodeSocket,
    expected_type: str,
    *,
    node: bpy.types.Node,
    role: str,
) -> None:
    if socket.type != expected_type:
        raise RuntimeError(
            f"{node.bl_idname!r} {role} socket {_socket_debug_label(socket)} "
            f"expected type {expected_type!r}, got {socket.type!r}"
        )


def _assert_color_mix_links(
    mix: ColorMixSockets,
    label: str,
    *,
    expect_factor_linked: bool,
) -> None:
    if not mix.color1.is_linked:
        raise RuntimeError(f"{label}: color1 socket is not linked")
    if not mix.color2.is_linked:
        raise RuntimeError(f"{label}: color2 socket is not linked")
    if expect_factor_linked and not mix.factor.is_linked:
        raise RuntimeError(f"{label}: factor socket is not linked")

    _assert_socket_type(mix.factor, "VALUE", node=mix.node, role=f"{label} factor")
    _assert_socket_type(mix.color1, "RGBA", node=mix.node, role=f"{label} color1")
    _assert_socket_type(mix.color2, "RGBA", node=mix.node, role=f"{label} color2")
    _assert_socket_type(mix.output, "RGBA", node=mix.node, role=f"{label} output")


def _bind_color_mix_rgb_sockets(node: bpy.types.Node) -> ColorMixSockets:
    # Blender UI labels may differ from Python socket names.
    # Use the actual active socket names exposed by bpy.
    if node.bl_idname != "ShaderNodeMixRGB":
        raise RuntimeError(
            f"expected ShaderNodeMixRGB for RGB mix binding, got {node.bl_idname!r}"
        )
    _log_color_mix_socket_inventory(node)
    factor = _require_active_socket(node.inputs, "Fac", role="input", node=node)
    color1 = _require_active_socket(node.inputs, "Color1", role="input", node=node)
    color2 = _require_active_socket(node.inputs, "Color2", role="input", node=node)
    output = _require_active_socket(node.outputs, "Color", role="output", node=node)
    _assert_socket_type(factor, "VALUE", node=node, role="MixRGB factor")
    _assert_socket_type(color1, "RGBA", node=node, role="MixRGB color1")
    _assert_socket_type(color2, "RGBA", node=node, role="MixRGB color2")
    _assert_socket_type(output, "RGBA", node=node, role="MixRGB output")
    sockets = ColorMixSockets(
        node=node,
        factor=factor,
        color1=color1,
        color2=color2,
        output=output,
        node_type="ShaderNodeMixRGB",
        factor_name=factor.name,
        color1_name=color1.name,
        color2_name=color2.name,
        output_name=output.name,
    )
    _log_color_mix_binding(sockets)
    return sockets


def _bind_color_mix_sockets(node: bpy.types.Node) -> ColorMixSockets:
    # Blender ShaderNodeMix exposes parallel socket sets for multiple
    # data types. Names alone are not sufficient; bind the active RGBA
    # socket set after setting data_type="RGBA".
    node.data_type = "RGBA"
    if node.bl_idname != "ShaderNodeMix":
        raise RuntimeError(
            f"expected ShaderNodeMix for RGBA mix binding, got {node.bl_idname!r}"
        )
    _log_color_mix_socket_inventory(node)

    factor_candidates = [
        socket
        for socket in _active_sockets_by_type(node.inputs, "VALUE")
        if socket.name == "Factor"
    ]
    if len(factor_candidates) != 1:
        active_details = [
            f"- {_socket_debug_label(socket)}"
            for socket in node.inputs
            if _socket_is_active(socket)
        ]
        raise RuntimeError(
            f"Expected exactly one active Factor VALUE input on ShaderNodeMix, "
            f"found {len(factor_candidates)}.\n\n"
            f"Active inputs:\n" + "\n".join(active_details)
        )
    factor = factor_candidates[0]

    color_inputs = _require_active_sockets_by_type(
        node.inputs,
        "RGBA",
        role="input",
        node=node,
        expected_count=2,
    )
    color_outputs = _require_active_sockets_by_type(
        node.outputs,
        "RGBA",
        role="output",
        node=node,
        expected_count=1,
    )

    sockets = ColorMixSockets(
        node=node,
        factor=factor,
        color1=color_inputs[0],
        color2=color_inputs[1],
        output=color_outputs[0],
        node_type="ShaderNodeMix",
        factor_name=factor.name,
        color1_name=color_inputs[0].name,
        color2_name=color_inputs[1].name,
        output_name=color_outputs[0].name,
    )
    _log_color_mix_binding(sockets)
    return sockets


def _new_color_mix_node(
    nodes: bpy.types.Nodes,
    blend_type: str = "MIX",
    location: tuple[float, float] = (0.0, 0.0),
) -> ColorMixSockets:
    try:
        mix_node = nodes.new("ShaderNodeMixRGB")
        mix_node.blend_type = blend_type
        mix_node.location = location
        return _bind_color_mix_rgb_sockets(mix_node)
    except RuntimeError:
        pass

    mix_node = nodes.new("ShaderNodeMix")
    mix_node.blend_type = blend_type
    mix_node.location = location
    return _bind_color_mix_sockets(mix_node)


def axial_to_world_xy(q: int, r: int, radius: float) -> tuple[float, float]:
    x = radius * math.sqrt(3.0) * (float(q) + float(r) * 0.5)
    y = radius * 1.5 * float(r)
    return x, y


def corner_xy_local(corner_index: int, radius: float) -> tuple[float, float]:
    angle_deg = 60.0 * float(corner_index) + 30.0
    angle_rad = math.radians(angle_deg)
    return radius * math.cos(angle_rad), radius * math.sin(angle_rad)


def neighbor_direction_for_physical_edge(edge_index: int) -> int:
    return (5 - edge_index) % 6


def pos_key(x: float, y: float, precision: int = 6) -> tuple[float, float]:
    return (round(x, precision), round(y, precision))


def build_hex_coords_set() -> set[tuple[int, int]]:
    return {(q, r) for q, r, _level, _label in PROTOTYPE_HEXES}


def has_neighbor(
    q: int,
    r: int,
    direction: int,
    hex_coords: set[tuple[int, int]],
) -> bool:
    dq, dr = NEIGHBOR_DIRS[direction]
    return (q + dq, r + dr) in hex_coords


def is_exposed_patch_edge(
    q: int,
    r: int,
    edge_index: int,
    hex_coords: set[tuple[int, int]],
) -> bool:
    direction = neighbor_direction_for_physical_edge(edge_index)
    return not has_neighbor(q, r, direction, hex_coords)


def hill_center_xy() -> tuple[float, float]:
    return axial_to_world_xy(HILL_AXIAL_Q, HILL_AXIAL_R, HEX_RADIUS)


def hill_falloff_weight(t: float) -> float:
    t_clamped = max(0.0, min(1.0, t))
    if HILL_PROFILE == "quadratic":
        return t_clamped * t_clamped
    # smootherstep: zero slope at t=0 and t=1
    return t_clamped * t_clamped * t_clamped * (
        t_clamped * (t_clamped * 6.0 - 15.0) + 10.0
    )


def sample_radial_height(wx: float, wy: float) -> float:
    hill_cx, hill_cy = hill_center_xy()
    dx = wx - hill_cx
    dy = wy - hill_cy
    distance = math.hypot(dx, dy)
    t = distance / HILL_RADIUS
    t = max(0.0, min(1.0, t))
    s = hill_falloff_weight(t)
    height = BASE_HEIGHT + HILL_HEIGHT * (1.0 - s)
    if TOP_FLATTEN_STRENGTH > 0.0 and TOP_FLATTEN_RADIUS > 0.0 and distance < TOP_FLATTEN_RADIUS:
        local_t = distance / TOP_FLATTEN_RADIUS
        flatten = TOP_FLATTEN_STRENGTH * (1.0 - local_t * local_t)
        target = BASE_HEIGHT + HILL_HEIGHT
        height = height + (target - height) * flatten
    return height


def rim_profile_weight(t: float) -> float:
    t_clamped = max(0.0, min(1.0, t))
    if OUTER_RIM_PROFILE == "smoothstep":
        return t_clamped * t_clamped * (3.0 - 2.0 * t_clamped)
    return t_clamped


def compute_rim_z(top_z: float, edge_t: float) -> float:
    if OUTER_RIM_DROP <= 0.0:
        return top_z
    bulge = 4.0 * edge_t * (1.0 - edge_t)
    return top_z - OUTER_RIM_DROP * ELEVATION_STEP * rim_profile_weight(bulge)


def sector_barycentric_xy(
    sector: int,
    si: int,
    sj: int,
    subdiv: int,
) -> tuple[float, float]:
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, HEX_RADIUS)
    cx, cy = corner_xy_local(cj, HEX_RADIUS)
    denom = float(subdiv)
    wb = float(si) / denom
    wc = float(sj) / denom
    return wb * bx + wc * cx, wb * by + wc * cy


def outer_edge_grid_indices(
    grid: dict[tuple[int, int], int],
    subdiv: int,
) -> list[int]:
    return [grid[(subdiv - step_k, step_k)] for step_k in range(subdiv + 1)]


def corner_world_xy(q: int, r: int, corner_index: int) -> tuple[float, float]:
    cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
    lx, ly = corner_xy_local(corner_index, HEX_RADIUS)
    return cx + lx, cy + ly


def unique_edge_key(q: int, r: int, edge_index: int) -> tuple[tuple[float, float], tuple[float, float]]:
    k1 = pos_key(*corner_world_xy(q, r, edge_index))
    k2 = pos_key(*corner_world_xy(q, r, (edge_index + 1) % 6))
    return (k1, k2) if k1 <= k2 else (k2, k1)


def chain_perimeter_segments(segments: list[list[int]]) -> list[int]:
    if not segments:
        raise RuntimeError("no perimeter segments to chain")
    remaining = [list(segment) for segment in segments]
    loop = list(remaining.pop(0))

    while remaining:
        tail = loop[-1]
        head = loop[0]
        found = False
        for index, segment in enumerate(remaining):
            if segment[0] == tail:
                loop.extend(segment[1:])
                remaining.pop(index)
                found = True
                break
            if segment[-1] == tail:
                loop.extend(reversed(segment[:-1]))
                remaining.pop(index)
                found = True
                break
            if segment[-1] == head:
                loop = segment[:-1] + loop
                remaining.pop(index)
                found = True
                break
            if segment[0] == head:
                loop = list(reversed(segment[1:])) + loop
                remaining.pop(index)
                found = True
                break
        if not found:
            raise RuntimeError("perimeter segments do not form a closed loop")

    if len(loop) > 1 and loop[0] == loop[-1]:
        loop = loop[:-1]
    if len(loop) < 3:
        raise RuntimeError(f"perimeter loop too short: {len(loop)}")
    return loop


def validate_radial_symmetry() -> None:
    hill_cx, hill_cy = hill_center_xy()
    test_radius = HILL_RADIUS * 0.55
    reference: float | None = None
    for angle_deg in (0.0, 60.0, 120.0, 180.0, 240.0, 300.0):
        angle_rad = math.radians(angle_deg)
        wx = hill_cx + test_radius * math.cos(angle_rad)
        wy = hill_cy + test_radius * math.sin(angle_rad)
        height = sample_radial_height(wx, wy)
        if reference is None:
            reference = height
        else:
            assert abs(height - reference) < HEIGHT_TOLERANCE, (
                f"radial symmetry mismatch at {angle_deg}°: "
                f"{height:.6f} vs {reference:.6f}"
            )
    _log(
        f"radial symmetry check passed (R={test_radius:.3f}, "
        f"Z≈{reference:.4f} at 6 bearings)"
    )


def _remove_unused_datablocks(block_collection) -> None:
    for block in list(block_collection):
        if block.users == 0:
            block_collection.remove(block)


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    _remove_unused_datablocks(bpy.data.meshes)
    _remove_unused_datablocks(bpy.data.materials)
    _remove_unused_datablocks(bpy.data.cameras)
    _remove_unused_datablocks(bpy.data.lights)
    _log("scene cleared")


def ensure_collection(name: str) -> bpy.types.Collection:
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        _active_scene().collection.children.link(coll)
    return coll


def _math_input(node: bpy.types.Node, index: int = 0):
    if index == 0:
        return _require_input(node, "Value")
    return _require_input(node, "Value_001")


def _unlink_socket_input(links, socket: bpy.types.NodeSocket) -> None:
    for link in list(links):
        if link.to_socket == socket:
            links.remove(link)


def _assert_debug_stage_routing_coverage() -> None:
    """Fail-fast: every VALID_DEBUG_MATERIAL_STAGE has an explicit routing branch."""
    base_color_stages = frozenset(
        {
            "ground",
            "ground_albedo",
            "ground_roughness",
            "ground_pbr",
            "ash_albedo",
            "ash_roughness",
            "ash_mask",
            "ground_ash_pbr",
            "stone_albedo",
            "stone_roughness",
            "ground_stone_pbr",
            "ground_stone_ash_pbr",
            "ash",
            "ground_ash",
            "stone_mask",
            "stone",
            "fine",
            "final",
        }
    )
    neutral_base_stages = frozenset({"ash_normal", "stone_normal"})
    pbr_override_stages = frozenset(
        {
            "ground_pbr",
            "ash_normal",
            "stone_normal",
            "stone_roughness",
            "ground_ash_pbr",
            "ground_stone_pbr",
            "ground_stone_ash_pbr",
            "final",
        }
    )
    diagnostic_output_stages = frozenset(
        {
            "ash_albedo_raw",
            "ash_albedo_diffuse",
            "ash_mask_raw",
            "ash_breakup_raw",
            "ash_mask_combined_raw",
            "ash_mask_remapped_raw",
        }
    )
    covered = base_color_stages | neutral_base_stages | pbr_override_stages | diagnostic_output_stages
    missing = set(VALID_DEBUG_MATERIAL_STAGES) - covered
    if missing:
        raise RuntimeError(
            f"VALID_DEBUG_MATERIAL_STAGES entries lack routing branches: {sorted(missing)!r}"
        )


def _apply_debug_base_color_link(
    links,
    principled: bpy.types.Node,
    stage: str,
    *,
    ground_tinted_output: bpy.types.NodeSocket,
    ground_albedo_output: bpy.types.NodeSocket,
    ground_roughness_visual: bpy.types.NodeSocket,
    ash_albedo_output: bpy.types.NodeSocket,
    ash_roughness_visual: bpy.types.NodeSocket,
    stone_albedo_output: bpy.types.NodeSocket,
    stone_roughness_visual: bpy.types.NodeSocket,
    mix_ground_ash: ColorMixSockets,
    mix_stone: ColorMixSockets,
    mix_ground_stone_debug: ColorMixSockets,
    mix_fine: ColorMixSockets,
    ash_mask_color_output: bpy.types.NodeSocket,
    stone_mask_color_output: bpy.types.NodeSocket,
    debug_neutral_rgb: bpy.types.Node,
) -> None:
    base_color = _require_input(principled, "Base Color")
    _unlink_socket_input(links, base_color)

    stage_outputs = {
        "ground": ground_tinted_output,
        "ground_albedo": ground_albedo_output,
        "ground_roughness": ground_roughness_visual,
        "ground_pbr": ground_tinted_output,
        "ash_albedo": ash_albedo_output,
        "ash_roughness": ash_roughness_visual,
        "ash_mask": ash_mask_color_output,
        "ground_ash_pbr": mix_ground_ash.output,
        "stone_albedo": stone_albedo_output,
        "stone_roughness": stone_roughness_visual,
        "ground_stone_pbr": mix_ground_stone_debug.output,
        "ground_stone_ash_pbr": mix_stone.output,
        "ash": ash_albedo_output,
        "ground_ash": mix_ground_ash.output,
        "stone_mask": stone_mask_color_output,
        "stone": mix_stone.output,
        "fine": mix_fine.output,
        "final": mix_fine.output,
    }
    if stage in {"ash_normal", "stone_normal"}:
        output_socket = _require_output(debug_neutral_rgb, "Color")
    elif stage in stage_outputs:
        output_socket = stage_outputs[stage]
    else:
        raise RuntimeError(f"debug stage {stage!r} has no Base Color routing branch")
    links.new(output_socket, base_color)
    _log(f"DEBUG_MATERIAL_STAGE={stage}")
    _log(
        "Base Color linked from "
        f"{output_socket.node.name}.{output_socket.name} "
        f"({_socket_binding_label(output_socket)})"
    )


def _apply_debug_pbr_surface_overrides(
    links,
    principled: bpy.types.Node,
    stage: str,
    *,
    ground_roughness_output: bpy.types.NodeSocket,
    ground_ash_roughness_output: bpy.types.NodeSocket,
    ground_stone_roughness_output: bpy.types.NodeSocket,
    mixed_roughness_output: bpy.types.NodeSocket,
    ground_normal_map: bpy.types.Node,
    ash_normal_map: bpy.types.Node,
    stone_normal_map: bpy.types.Node,
    ground_ash_normal_output: bpy.types.NodeSocket,
    ground_stone_normal_output: bpy.types.NodeSocket,
    blended_normal_output: bpy.types.NodeSocket,
    combined_normal_output: bpy.types.NodeSocket,
    bump: bpy.types.Node,
    debug_neutral_roughness: bpy.types.NodeSocket,
) -> None:
    roughness_in = _require_input(principled, "Roughness")
    normal_in = _require_input(principled, "Normal")
    bump_normal_in = _require_input(bump, "Normal")

    if stage not in {
        "ground_pbr",
        "ash_normal",
        "stone_normal",
        "stone_roughness",
        "ground_ash_pbr",
        "ground_stone_pbr",
        "ground_stone_ash_pbr",
        "final",
    }:
        return

    if stage == "ground_pbr":
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        _unlink_socket_input(links, bump_normal_in)
        links.new(ground_roughness_output, roughness_in)
        links.new(
            _require_output(ground_normal_map, "Normal"),
            bump_normal_in,
        )
        links.new(combined_normal_output, normal_in)
        _log("ground_pbr debug: ground-only Roughness and Normal")
        return

    if stage == "ash_normal":
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        _unlink_socket_input(links, bump_normal_in)
        links.new(debug_neutral_roughness, roughness_in)
        links.new(_require_output(ash_normal_map, "Normal"), bump_normal_in)
        links.new(combined_normal_output, normal_in)
        _log("ash_normal debug: neutral Base Color, ash tangent-space Normal active")
        return

    if stage == "stone_normal":
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        _unlink_socket_input(links, bump_normal_in)
        links.new(debug_neutral_roughness, roughness_in)
        links.new(_require_output(stone_normal_map, "Normal"), bump_normal_in)
        links.new(combined_normal_output, normal_in)
        _log("stone_normal debug: neutral Base Color, stone tangent-space Normal active")
        return

    if stage == "stone_roughness":
        _unlink_socket_input(links, roughness_in)
        links.new(debug_neutral_roughness, roughness_in)
        _log("stone_roughness debug: stone roughness grayscale on Base Color")
        return

    if stage == "ground_ash_pbr":
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        _unlink_socket_input(links, bump_normal_in)
        links.new(ground_ash_roughness_output, roughness_in)
        links.new(ground_ash_normal_output, bump_normal_in)
        links.new(combined_normal_output, normal_in)
        _log(
            "ground_ash_pbr debug: ground+ash PBR (stone bypassed), "
            "ground/ash Roughness and Normal"
        )
        return

    if stage == "ground_stone_pbr":
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        _unlink_socket_input(links, bump_normal_in)
        links.new(ground_stone_roughness_output, roughness_in)
        links.new(ground_stone_normal_output, bump_normal_in)
        links.new(combined_normal_output, normal_in)
        _log(
            "ground_stone_pbr debug: ground+stone PBR (ash bypassed), "
            "ground/stone Roughness and Normal"
        )
        return

    if stage in {"ground_stone_ash_pbr", "final"}:
        _unlink_socket_input(links, roughness_in)
        _unlink_socket_input(links, normal_in)
        links.new(mixed_roughness_output, roughness_in)
        links.new(combined_normal_output, normal_in)
        if stage == "ground_stone_ash_pbr":
            _log(
                "ground_stone_ash_pbr debug: ground+ash+stone PBR, "
                "mixed Roughness and Normal"
            )
        return

    raise RuntimeError(f"debug stage {stage!r} has no PBR surface override branch")


def _configure_diagnostic_diffuse_principled(
    links,
    principled: bpy.types.Node,
    ash_albedo_socket: bpy.types.NodeSocket,
) -> None:
    """Neutral matte Principled for ash_albedo_diffuse; separate from the final graph."""
    links.new(ash_albedo_socket, _require_input(principled, "Base Color"))
    _require_input(principled, "Metallic").default_value = 0.0
    _require_input(principled, "Roughness").default_value = 1.0
    _set_optional_input_default(
        principled,
        ("Specular IOR Level", "Specular"),
        0.0,
        log_label="Specular IOR Level",
    )
    _set_optional_input_default(
        principled,
        ("Coat Weight",),
        0.0,
        log_label="Coat Weight",
    )
    _set_optional_input_default(
        principled,
        ("Transmission Weight", "Transmission"),
        0.0,
        log_label="Transmission Weight",
    )
    _set_optional_input_default(
        principled,
        ("Emission Strength",),
        0.0,
        log_label="Emission Strength",
    )
    emission_color = _optional_input(principled, "Emission Color", "Emission")
    if emission_color is not None:
        emission_color.default_value = (0.0, 0.0, 0.0, 1.0)
    normal_in = _optional_input(principled, "Normal")
    if normal_in is not None:
        _unlink_socket_input(links, normal_in)


def _configure_ash_breakup_remap_node(remap_node: bpy.types.Node) -> None:
    if hasattr(remap_node, "data_type"):
        remap_node.data_type = "FLOAT"
    remap_node.clamp = True
    _map_range_float_input(remap_node, "From Min").default_value = ASH_BREAKUP_MIN
    _map_range_float_input(remap_node, "From Max").default_value = ASH_BREAKUP_MAX
    _map_range_float_input(remap_node, "To Min").default_value = 0.0
    _map_range_float_input(remap_node, "To Max").default_value = 1.0
    if hasattr(remap_node, "interpolation_type"):
        try:
            remap_node.interpolation_type = "SMOOTHERSTEP"
        except (AttributeError, TypeError, ValueError):
            pass


def _configure_ash_weight_remap_node(remap_node: bpy.types.Node) -> None:
    if hasattr(remap_node, "data_type"):
        remap_node.data_type = "FLOAT"
    remap_node.clamp = True
    _map_range_float_input(remap_node, "From Min").default_value = ASH_WEIGHT_INPUT_MIN
    _map_range_float_input(remap_node, "From Max").default_value = ASH_WEIGHT_INPUT_MAX
    _map_range_float_input(remap_node, "To Min").default_value = 0.0
    _map_range_float_input(remap_node, "To Max").default_value = 1.0
    if hasattr(remap_node, "interpolation_type"):
        try:
            remap_node.interpolation_type = "SMOOTHERSTEP"
        except (AttributeError, TypeError, ValueError):
            pass


def _log_ash_weight_remap_node_state(remap_node: bpy.types.Node) -> None:
    _log(f"ash remap node type={remap_node.bl_idname}")
    interpolation = getattr(remap_node, "interpolation_type", "not available")
    _log(f"ash remap interpolation={interpolation!r}")
    _log(f"ash remap clamp={remap_node.clamp!r}")
    value_sock = _map_range_float_input(remap_node, "Value")
    value_identifier = getattr(value_sock, "identifier", value_sock.name)
    _log(
        "ash remap Value socket "
        f"name={value_sock.name} identifier={value_identifier}"
    )
    for label, expected in (
        ("From Min", ASH_WEIGHT_INPUT_MIN),
        ("From Max", ASH_WEIGHT_INPUT_MAX),
        ("To Min", 0.0),
        ("To Max", 1.0),
    ):
        sock = _map_range_float_input(remap_node, label)
        actual = _float_default_value(sock)
        identifier = getattr(sock, "identifier", sock.name)
        _log(
            f"ash remap {label} socket name={sock.name} identifier={identifier} "
            f"actual={actual} expected={expected}"
        )


def _apply_debug_material_output_link(
    links,
    out: bpy.types.Node,
    stage: str,
    *,
    principled: bpy.types.Node,
    diag_raw_emission: bpy.types.Node,
    diag_diffuse_principled: bpy.types.Node,
    diag_mask_emission: bpy.types.Node,
    diag_breakup_emission: bpy.types.Node,
    diag_combined_emission: bpy.types.Node,
    diag_mask_remapped_emission: bpy.types.Node,
) -> None:
    surface_in = _require_input(out, "Surface")
    _unlink_socket_input(links, surface_in)

    if stage == "ash_albedo_raw":
        links.new(_require_output(diag_raw_emission, "Emission"), surface_in)
        _log("ash_albedo_raw: Material Output from diagnostic Emission (Principled bypassed)")
        return

    if stage == "ash_albedo_diffuse":
        links.new(_require_output(diag_diffuse_principled, "BSDF"), surface_in)
        _log(
            "ash_albedo_diffuse: Material Output from diagnostic matte Principled "
            "(final graph bypassed)"
        )
        return

    if stage == "ash_mask_raw":
        links.new(_require_output(diag_mask_emission, "Emission"), surface_in)
        _log("ash_mask_raw: raw ash weight via Emission (Principled bypassed)")
        return

    if stage == "ash_breakup_raw":
        links.new(_require_output(diag_breakup_emission, "Emission"), surface_in)
        _log("ash_breakup_raw: ash breakup factor via Emission (Principled bypassed)")
        return

    if stage == "ash_mask_combined_raw":
        links.new(_require_output(diag_combined_emission, "Emission"), surface_in)
        _log("ash_mask_combined_raw: combined ash source via Emission (Principled bypassed)")
        return

    if stage == "ash_mask_remapped_raw":
        links.new(_require_output(diag_mask_remapped_emission, "Emission"), surface_in)
        _log("ash_mask_remapped_raw: remapped ash weight via Emission (Principled bypassed)")
        return

    links.new(_require_output(principled, "BSDF"), surface_in)


def _assert_diagnostic_diffuse_principled_configuration(principled: bpy.types.Node) -> None:
    metallic = _require_input(principled, "Metallic")
    if metallic.default_value != 0.0:
        raise RuntimeError("diagnostic diffuse Principled Metallic must be 0.0")

    roughness = _require_input(principled, "Roughness")
    if roughness.default_value != 1.0:
        raise RuntimeError("diagnostic diffuse Principled Roughness must be 1.0")

    normal_in = _optional_input(principled, "Normal")
    if normal_in is not None and normal_in.is_linked:
        raise RuntimeError("diagnostic diffuse Principled Normal must be unlinked")

    specular = _optional_input(principled, "Specular IOR Level", "Specular")
    if specular is not None and specular.default_value != 0.0:
        raise RuntimeError("diagnostic diffuse Principled Specular IOR Level must be 0.0")

    coat = _optional_input(principled, "Coat Weight")
    if coat is not None and coat.default_value != 0.0:
        raise RuntimeError("diagnostic diffuse Principled Coat Weight must be 0.0")

    transmission = _optional_input(
        principled,
        "Transmission Weight",
        "Transmission",
    )
    if transmission is not None and transmission.default_value != 0.0:
        raise RuntimeError("diagnostic diffuse Principled Transmission Weight must be 0.0")

    emission_strength = _optional_input(principled, "Emission Strength")
    if emission_strength is not None and emission_strength.default_value != 0.0:
        raise RuntimeError("diagnostic diffuse Principled Emission Strength must be 0.0")


def _assert_mask_grayscale_uses_factor(
    grayscale_node: bpy.types.Node,
    factor_socket: bpy.types.NodeSocket,
    *,
    label: str,
) -> None:
    expected_source = (
        factor_socket.node.name,
        factor_socket.name,
    )
    for channel in ("Red", "Green", "Blue"):
        channel_in = _require_input(grayscale_node, channel)
        if not channel_in.is_linked:
            raise RuntimeError(f"{label} grayscale {channel} is not linked")
        channel_source = (
            channel_in.links[0].from_node.name,
            channel_in.links[0].from_socket.name,
        )
        if channel_source != expected_source:
            raise RuntimeError(
                f"{label} grayscale {channel} must use "
                f"{expected_source[0]}.{expected_source[1]}, got "
                f"{channel_source[0]}.{channel_source[1]}"
            )


def _assert_ash_breakup_chain(
    *,
    mapping: bpy.types.Node,
    mapped_vector: bpy.types.NodeSocket,
    ash_factor_raw_output: bpy.types.NodeSocket | None,
    ash_breakup_noise: bpy.types.Node | None,
    ash_breakup_remap: bpy.types.Node | None,
    ash_breakup_strength_mix: bpy.types.Node | None,
    ash_combined_mul: bpy.types.Node | None,
    ash_breakup_factor_output: bpy.types.NodeSocket | None,
    ash_combined_raw_output: bpy.types.NodeSocket | None,
) -> None:
    if not USE_LARGE_SCALE_VARIATION:
        return
    if ash_factor_raw_output is None or ash_combined_raw_output is None:
        raise RuntimeError("ash breakup chain sockets missing while USE_LARGE_SCALE_VARIATION is enabled")

    if not USE_ASH_BREAKUP:
        combined_source = (ash_combined_raw_output.node.name, ash_combined_raw_output.name)
        raw_source = (ash_factor_raw_output.node.name, ash_factor_raw_output.name)
        if combined_source != raw_source:
            raise RuntimeError(
                "ash_combined_raw_output must equal ash_factor_raw_output when USE_ASH_BREAKUP is disabled, "
                f"got combined={combined_source[0]}.{combined_source[1]} "
                f"raw={raw_source[0]}.{raw_source[1]}"
            )
        return

    if (
        ash_breakup_noise is None
        or ash_breakup_remap is None
        or ash_breakup_strength_mix is None
        or ash_combined_mul is None
        or ash_breakup_factor_output is None
    ):
        raise RuntimeError("ash breakup nodes missing while USE_ASH_BREAKUP is enabled")

    expected_mapped_source = (mapping.name, "Vector")
    breakup_vector_in = _require_input(ash_breakup_noise, "Vector")
    if not breakup_vector_in.is_linked:
        raise RuntimeError("ash breakup noise Vector input is not linked")
    breakup_vector_source = (
        breakup_vector_in.links[0].from_node.name,
        breakup_vector_in.links[0].from_socket.name,
    )
    if breakup_vector_source != expected_mapped_source:
        raise RuntimeError(
            "ash breakup noise must use world/object-anchored mapped_vector, "
            f"got {breakup_vector_source[0]}.{breakup_vector_source[1]}"
        )
    if breakup_vector_in.links[0].from_socket != mapped_vector:
        raise RuntimeError(
            "ash breakup noise Vector must link from the same mapped_vector socket as procedural masks"
        )

    breakup_scale = _require_input(ash_breakup_noise, "Scale").default_value
    breakup_detail = _require_input(ash_breakup_noise, "Detail").default_value
    breakup_roughness = _require_input(ash_breakup_noise, "Roughness").default_value
    if not _float_defaults_close(breakup_scale, ASH_BREAKUP_NOISE_SCALE):
        raise RuntimeError(
            "ash breakup noise Scale does not match ASH_BREAKUP_NOISE_SCALE "
            f"(actual={breakup_scale!r}, expected={ASH_BREAKUP_NOISE_SCALE!r})"
        )
    if not _float_defaults_close(breakup_detail, ASH_BREAKUP_NOISE_DETAIL):
        raise RuntimeError(
            "ash breakup noise Detail does not match ASH_BREAKUP_NOISE_DETAIL "
            f"(actual={breakup_detail!r}, expected={ASH_BREAKUP_NOISE_DETAIL!r})"
        )
    if not _float_defaults_close(breakup_roughness, ASH_BREAKUP_NOISE_ROUGHNESS):
        raise RuntimeError(
            "ash breakup noise Roughness does not match ASH_BREAKUP_NOISE_ROUGHNESS "
            f"(actual={breakup_roughness!r}, expected={ASH_BREAKUP_NOISE_ROUGHNESS!r})"
        )

    breakup_from_min = _float_default_value(_map_range_float_input(ash_breakup_remap, "From Min"))
    breakup_from_max = _float_default_value(_map_range_float_input(ash_breakup_remap, "From Max"))
    if not _float_defaults_close(breakup_from_min, ASH_BREAKUP_MIN):
        raise RuntimeError(
            "ash breakup remap From Min does not match ASH_BREAKUP_MIN "
            f"(actual={breakup_from_min!r}, expected={ASH_BREAKUP_MIN!r})"
        )
    if not _float_defaults_close(breakup_from_max, ASH_BREAKUP_MAX):
        raise RuntimeError(
            "ash breakup remap From Max does not match ASH_BREAKUP_MAX "
            f"(actual={breakup_from_max!r}, expected={ASH_BREAKUP_MAX!r})"
        )
    if not ash_breakup_remap.clamp:
        raise RuntimeError("ash breakup remap clamp must be enabled")

    strength_factor = _float_default_value(_require_input(ash_breakup_strength_mix, "Factor"))
    if not _float_defaults_close(strength_factor, ASH_BREAKUP_STRENGTH):
        raise RuntimeError(
            "ash breakup strength mix Factor does not match ASH_BREAKUP_STRENGTH "
            f"(actual={strength_factor!r}, expected={ASH_BREAKUP_STRENGTH!r})"
        )
    strength_a = _require_input(ash_breakup_strength_mix, "A")
    if not strength_a.is_linked:
        raise RuntimeError("ash breakup strength mix A must be linked to unity value")
    unity_value = _float_default_value(strength_a.links[0].from_socket)
    if not _float_defaults_close(unity_value, 1.0):
        raise RuntimeError(f"ash breakup strength mix A must be 1.0 (actual={unity_value!r})")
    strength_b = _require_input(ash_breakup_strength_mix, "B")
    if not strength_b.is_linked:
        raise RuntimeError("ash breakup strength mix B is not linked")
    strength_b_source = (strength_b.links[0].from_node.name, strength_b.links[0].from_socket.name)
    expected_breakup_factor = (ash_breakup_remap.name, "Result")
    if strength_b_source != expected_breakup_factor:
        raise RuntimeError(
            "ash breakup strength mix B must use ash_breakup_factor, "
            f"got {strength_b_source[0]}.{strength_b_source[1]}"
        )

    combined_mul_inputs = (
        (_math_input(ash_combined_mul, 0), ash_factor_raw_output),
        (_math_input(ash_combined_mul, 1), _require_output(ash_breakup_strength_mix, "Result")),
    )
    for mul_in, expected_socket in combined_mul_inputs:
        if not mul_in.is_linked:
            raise RuntimeError("ash combined multiply input is not linked")
        actual_source = (mul_in.links[0].from_node.name, mul_in.links[0].from_socket.name)
        expected_source = (expected_socket.node.name, expected_socket.name)
        if actual_source != expected_source:
            raise RuntimeError(
                "ash combined multiply must use raw regional mask and effective breakup, "
                f"expected {expected_source[0]}.{expected_source[1]}, "
                f"got {actual_source[0]}.{actual_source[1]}"
            )

    combined_source = (ash_combined_raw_output.node.name, ash_combined_raw_output.name)
    expected_combined_source = (ash_combined_mul.name, "Value")
    if combined_source != expected_combined_source:
        raise RuntimeError(
            f"ash_combined_raw_output must come from {expected_combined_source[0]}.{expected_combined_source[1]}, "
            f"got {combined_source[0]}.{combined_source[1]}"
        )


def _assert_ash_weight_remap(
    *,
    large_factor_map: bpy.types.Node,
    ash_weight_remap: bpy.types.Node | None,
    ash_factor_raw_output: bpy.types.NodeSocket | None,
    ash_combined_raw_output: bpy.types.NodeSocket | None,
    ash_factor_output: bpy.types.NodeSocket | None,
    mix_ground_ash: ColorMixSockets,
    normal_mix_ground_ash: bpy.types.Node,
    rough_mix_ground_ash: bpy.types.Node,
) -> None:
    if not USE_LARGE_SCALE_VARIATION:
        return
    if ash_factor_raw_output is None or ash_combined_raw_output is None or ash_factor_output is None or ash_weight_remap is None:
        raise RuntimeError("ash weight remap nodes missing while USE_LARGE_SCALE_VARIATION is enabled")

    raw_source = (ash_factor_raw_output.node.name, ash_factor_raw_output.name)
    expected_raw_source = (large_factor_map.name, "Result")
    if raw_source != expected_raw_source:
        raise RuntimeError(
            f"ash_factor_raw_output must come from {expected_raw_source[0]}.{expected_raw_source[1]}, "
            f"got {raw_source[0]}.{raw_source[1]}"
        )

    remap_value_in = _map_range_float_input(ash_weight_remap, "Value")
    if not remap_value_in.is_linked:
        raise RuntimeError("ash weight remap Value input is not linked")
    remap_in_source = (
        remap_value_in.links[0].from_node.name,
        remap_value_in.links[0].from_socket.name,
    )
    combined_source = (ash_combined_raw_output.node.name, ash_combined_raw_output.name)
    if remap_in_source != combined_source:
        raise RuntimeError(
            "ash weight remap must be fed by ash_combined_raw_output, "
            f"got {remap_in_source[0]}.{remap_in_source[1]}"
        )
    if remap_in_source == raw_source and USE_ASH_BREAKUP:
        raise RuntimeError(
            "ash weight remap must not use raw ash_factor_raw_output directly when USE_ASH_BREAKUP is enabled"
        )

    _log_ash_weight_remap_node_state(ash_weight_remap)

    from_min = _float_default_value(_map_range_float_input(ash_weight_remap, "From Min"))
    from_max = _float_default_value(_map_range_float_input(ash_weight_remap, "From Max"))
    to_min = _float_default_value(_map_range_float_input(ash_weight_remap, "To Min"))
    to_max = _float_default_value(_map_range_float_input(ash_weight_remap, "To Max"))
    if not _float_defaults_close(from_min, ASH_WEIGHT_INPUT_MIN):
        raise RuntimeError(
            "ash weight remap From Min does not match ASH_WEIGHT_INPUT_MIN "
            f"(actual={from_min!r}, expected={ASH_WEIGHT_INPUT_MIN!r})"
        )
    if not _float_defaults_close(from_max, ASH_WEIGHT_INPUT_MAX):
        raise RuntimeError(
            "ash weight remap From Max does not match ASH_WEIGHT_INPUT_MAX "
            f"(actual={from_max!r}, expected={ASH_WEIGHT_INPUT_MAX!r})"
        )
    if not _float_defaults_close(to_min, 0.0):
        raise RuntimeError(
            f"ash weight remap To Min must be 0.0 (actual={to_min!r})"
        )
    if not _float_defaults_close(to_max, 1.0):
        raise RuntimeError(
            f"ash weight remap To Max must be 1.0 (actual={to_max!r})"
        )
    if not ash_weight_remap.clamp:
        raise RuntimeError("ash weight remap clamp must be enabled")

    remapped_source = (ash_factor_output.node.name, ash_factor_output.name)
    expected_remapped_source = (ash_weight_remap.name, "Result")
    if remapped_source != expected_remapped_source:
        raise RuntimeError(
            f"ash_factor_output must come from {expected_remapped_source[0]}.{expected_remapped_source[1]}, "
            f"got {remapped_source[0]}.{remapped_source[1]}"
        )

    for label, socket in (
        ("mix_ground_ash", mix_ground_ash.factor),
        ("normal_mix_ground_ash", _require_input(normal_mix_ground_ash, "Factor")),
        ("rough_mix_ground_ash", _require_input(rough_mix_ground_ash, "Factor")),
    ):
        source = _linked_mix_factor_source(socket)
        if source != expected_remapped_source:
            raise RuntimeError(
                f"{label} must use remapped ash_factor_output "
                f"{expected_remapped_source[0]}.{expected_remapped_source[1]}, "
                f"got {source[0]}.{source[1]}"
            )
        if source == expected_raw_source:
            raise RuntimeError(f"{label} must not use raw ash_factor_raw_output directly")


def _assert_ash_brightness_diagnostic_routing(
    links,
    stage: str,
    out: bpy.types.Node,
    *,
    diag_raw_emission: bpy.types.Node,
    diag_diffuse_principled: bpy.types.Node,
    diag_mask_emission: bpy.types.Node,
    diag_mask_grayscale: bpy.types.Node,
    diag_breakup_emission: bpy.types.Node,
    diag_breakup_grayscale: bpy.types.Node,
    diag_combined_emission: bpy.types.Node,
    diag_combined_grayscale: bpy.types.Node,
    diag_mask_remapped_emission: bpy.types.Node,
    diag_mask_remapped_grayscale: bpy.types.Node,
    ash_factor_raw_output: bpy.types.NodeSocket | None,
    ash_breakup_factor_output: bpy.types.NodeSocket | None,
    ash_combined_raw_output: bpy.types.NodeSocket | None,
    ash_factor_output: bpy.types.NodeSocket | None,
) -> None:
    if stage not in {
        "ash_albedo_raw",
        "ash_albedo_diffuse",
        "ash_mask_raw",
        "ash_breakup_raw",
        "ash_mask_combined_raw",
        "ash_mask_remapped_raw",
    }:
        return

    surface_in = _require_input(out, "Surface")
    if not surface_in.is_linked:
        raise RuntimeError(f"{stage!r} debug stage: Material Output Surface is not linked")

    source_node = surface_in.links[0].from_node
    if stage == "ash_albedo_raw":
        if source_node.bl_idname != "ShaderNodeEmission":
            raise RuntimeError(
                f"ash_albedo_raw must feed Material Output from Emission, "
                f"got {source_node.bl_idname!r}"
            )
        if source_node.name != diag_raw_emission.name:
            raise RuntimeError(
                "ash_albedo_raw must use the diagnostic Emission node, "
                f"got {source_node.name!r}"
            )
        return

    if stage == "ash_mask_raw":
        if source_node.bl_idname != "ShaderNodeEmission":
            raise RuntimeError(
                f"ash_mask_raw must feed Material Output from Emission, "
                f"got {source_node.bl_idname!r}"
            )
        if source_node.name != diag_mask_emission.name:
            raise RuntimeError(
                "ash_mask_raw must use the diagnostic raw mask Emission node, "
                f"got {source_node.name!r}"
            )
        emission_color = _require_input(diag_mask_emission, "Color")
        if not emission_color.is_linked:
            raise RuntimeError("ash_mask_raw diagnostic Emission Color is not linked")
        color_link = emission_color.links[0]
        if color_link.from_node.name != diag_mask_grayscale.name:
            raise RuntimeError(
                "ash_mask_raw Emission Color must come from raw grayscale node, "
                f"got {color_link.from_node.name!r}"
            )
        if ash_factor_raw_output is not None:
            _assert_mask_grayscale_uses_factor(
                diag_mask_grayscale,
                ash_factor_raw_output,
                label="ash_mask_raw",
            )
        return

    if stage == "ash_breakup_raw":
        if source_node.bl_idname != "ShaderNodeEmission":
            raise RuntimeError(
                f"ash_breakup_raw must feed Material Output from Emission, "
                f"got {source_node.bl_idname!r}"
            )
        if source_node.name != diag_breakup_emission.name:
            raise RuntimeError(
                "ash_breakup_raw must use the diagnostic breakup Emission node, "
                f"got {source_node.name!r}"
            )
        emission_color = _require_input(diag_breakup_emission, "Color")
        if not emission_color.is_linked:
            raise RuntimeError("ash_breakup_raw diagnostic Emission Color is not linked")
        color_link = emission_color.links[0]
        if color_link.from_node.name != diag_breakup_grayscale.name:
            raise RuntimeError(
                "ash_breakup_raw Emission Color must come from breakup grayscale node, "
                f"got {color_link.from_node.name!r}"
            )
        if ash_breakup_factor_output is not None:
            _assert_mask_grayscale_uses_factor(
                diag_breakup_grayscale,
                ash_breakup_factor_output,
                label="ash_breakup_raw",
            )
        return

    if stage == "ash_mask_combined_raw":
        if source_node.bl_idname != "ShaderNodeEmission":
            raise RuntimeError(
                f"ash_mask_combined_raw must feed Material Output from Emission, "
                f"got {source_node.bl_idname!r}"
            )
        if source_node.name != diag_combined_emission.name:
            raise RuntimeError(
                "ash_mask_combined_raw must use the diagnostic combined Emission node, "
                f"got {source_node.name!r}"
            )
        emission_color = _require_input(diag_combined_emission, "Color")
        if not emission_color.is_linked:
            raise RuntimeError("ash_mask_combined_raw diagnostic Emission Color is not linked")
        color_link = emission_color.links[0]
        if color_link.from_node.name != diag_combined_grayscale.name:
            raise RuntimeError(
                "ash_mask_combined_raw Emission Color must come from combined grayscale node, "
                f"got {color_link.from_node.name!r}"
            )
        if ash_combined_raw_output is not None:
            _assert_mask_grayscale_uses_factor(
                diag_combined_grayscale,
                ash_combined_raw_output,
                label="ash_mask_combined_raw",
            )
        return

    if stage == "ash_mask_remapped_raw":
        if source_node.bl_idname != "ShaderNodeEmission":
            raise RuntimeError(
                f"ash_mask_remapped_raw must feed Material Output from Emission, "
                f"got {source_node.bl_idname!r}"
            )
        if source_node.name != diag_mask_remapped_emission.name:
            raise RuntimeError(
                "ash_mask_remapped_raw must use the diagnostic remapped mask Emission node, "
                f"got {source_node.name!r}"
            )
        emission_color = _require_input(diag_mask_remapped_emission, "Color")
        if not emission_color.is_linked:
            raise RuntimeError("ash_mask_remapped_raw diagnostic Emission Color is not linked")
        color_link = emission_color.links[0]
        if color_link.from_node.name != diag_mask_remapped_grayscale.name:
            raise RuntimeError(
                "ash_mask_remapped_raw Emission Color must come from remapped grayscale node, "
                f"got {color_link.from_node.name!r}"
            )
        if ash_factor_output is not None:
            _assert_mask_grayscale_uses_factor(
                diag_mask_remapped_grayscale,
                ash_factor_output,
                label="ash_mask_remapped_raw",
            )
        return

    if source_node.bl_idname != "ShaderNodeBsdfPrincipled":
        raise RuntimeError(
            f"ash_albedo_diffuse must feed Material Output from Principled BSDF, "
            f"got {source_node.bl_idname!r}"
        )
    if source_node.name != diag_diffuse_principled.name:
        raise RuntimeError(
            "ash_albedo_diffuse must use the diagnostic Principled node, "
            f"got {source_node.name!r}"
        )


def _find_final_principled_node(material: bpy.types.Material) -> bpy.types.Node:
    for node in material.node_tree.nodes:
        if node.bl_idname == "ShaderNodeBsdfPrincipled" and node.label == "EOM_Final_Principled":
            return node
    for node in material.node_tree.nodes:
        if node.bl_idname == "ShaderNodeBsdfPrincipled" and node.label != "EOM_Ash_Diffuse_Diagnostic":
            return node
    raise RuntimeError(f"final Principled node not found in {material.name!r}")


def _log_principled_socket_audit(node: bpy.types.Node, label: str, *socket_names: str) -> None:
    sock = _optional_input(node, *socket_names)
    if sock is None:
        _audit_log(f"principled_{label}=not available")
        return
    if sock.is_linked:
        link = sock.links[0]
        _audit_log(
            f"principled_{label}=linked "
            f"from {link.from_node.name}.{link.from_socket.name}"
        )
        return
    _audit_log(f"principled_{label}={sock.default_value!r}")


def _log_ash_brightness_audit(
    procedural_material: bpy.types.Material,
    *,
    ground_albedo_path: Path,
    ground_normal_path: Path,
    ground_roughness_path: Path,
    ash_albedo_path: Path,
    ash_normal_path: Path,
    ash_roughness_path: Path,
    stone_albedo_path: Path,
    stone_normal_path: Path,
    stone_roughness_path: Path,
) -> None:
    scene = _active_scene()
    _audit_log(f"blender={_blender_version_label()}")
    _audit_log(f"render_engine={scene.render.engine!r}")
    _audit_log(f"debug_material_stage={DEBUG_MATERIAL_STAGE!r}")

    view_settings = scene.view_settings
    for attr in ("view_transform", "look", "exposure", "gamma"):
        if hasattr(view_settings, attr):
            _audit_log(f"{attr}={getattr(view_settings, attr)!r}")
        else:
            _audit_log(f"{attr}=not available")

    world = scene.world
    if world is not None:
        if world.use_nodes and world.node_tree is not None:
            bg = world.node_tree.nodes.get("Background")
            if bg is None:
                for node in world.node_tree.nodes:
                    if node.bl_idname == "ShaderNodeBackground":
                        bg = node
                        break
            if bg is not None:
                color_in = bg.inputs.get("Color")
                strength_in = bg.inputs.get("Strength")
                if color_in is not None:
                    _audit_log(f"world_background_color={color_in.default_value!r}")
                if strength_in is not None:
                    _audit_log(f"world_strength={strength_in.default_value!r}")
            else:
                _audit_log("world_background=Background node not found")
        else:
            _audit_log(f"world_color={world.color!r}")
    else:
        _audit_log("world=none")

    principled = _find_final_principled_node(procedural_material)
    _log_principled_socket_audit(principled, "metallic", "Metallic")
    _log_principled_socket_audit(principled, "roughness", "Roughness")
    _log_principled_socket_audit(principled, "ior", "IOR")
    _log_principled_socket_audit(
        principled,
        "specular_ior_level",
        "Specular IOR Level",
        "Specular",
    )
    _log_principled_socket_audit(principled, "coat_weight", "Coat Weight")
    _log_principled_socket_audit(principled, "sheen_weight", "Sheen Weight")
    _log_principled_socket_audit(
        principled,
        "transmission_weight",
        "Transmission Weight",
        "Transmission",
    )
    _log_principled_socket_audit(
        principled,
        "emission_color",
        "Emission Color",
        "Emission",
    )
    _log_principled_socket_audit(principled, "emission_strength", "Emission Strength")
    _log_principled_socket_audit(principled, "alpha", "Alpha")
    _log_principled_socket_audit(principled, "normal", "Normal")

    image_specs = (
        ("ground_albedo", "EOM_Ground_Albedo", ground_albedo_path),
        ("ground_normal", "EOM_Ground_Normal", ground_normal_path),
        ("ground_roughness", "EOM_Ground_Roughness", ground_roughness_path),
        ("stone_albedo", "EOM_Stone_Albedo", stone_albedo_path),
        ("stone_normal", "EOM_Stone_Normal", stone_normal_path),
        ("stone_roughness", "EOM_Stone_Roughness", stone_roughness_path),
        ("ash_albedo", "EOM_Ash_Albedo", ash_albedo_path),
        ("ash_normal", "EOM_Ash_Normal", ash_normal_path),
        ("ash_roughness", "EOM_Ash_Roughness", ash_roughness_path),
    )
    for label, image_name, path in image_specs:
        image = bpy.data.images.get(image_name)
        if image is None:
            _audit_log(f"{label} image=missing name={image_name!r}")
            continue
        resolved = bpy.path.abspath(image.filepath) if image.filepath else str(path.resolve())
        colorspace = image.colorspace_settings.name
        size = f"{image.size[0]}x{image.size[1]}"
        _audit_log(
            f"{label} colorspace={colorspace!r} path={resolved} size={size}"
        )


def make_pbr_ground_stone_ash_terrain_material(
    ground_albedo_path: Path,
    ground_normal_path: Path,
    ground_roughness_path: Path,
    ash_albedo_path: Path,
    ash_normal_path: Path,
    ash_roughness_path: Path,
    stone_albedo_path: Path,
    stone_normal_path: Path,
    stone_roughness_path: Path,
) -> bpy.types.Material:
    """Approved ground + stone PBR UV baseline + full ash PBR via existing ash splat weight."""
    mat = bpy.data.materials.get(PROCEDURAL_MATERIAL_NAME)
    if mat is not None:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(PROCEDURAL_MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {PROCEDURAL_MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    albedo_image = _load_ground_image("EOM_Ground_Albedo", ground_albedo_path, "sRGB")
    normal_image = _load_ground_image("EOM_Ground_Normal", ground_normal_path, "Non-Color")
    roughness_image = _load_ground_image(
        "EOM_Ground_Roughness",
        ground_roughness_path,
        "Non-Color",
    )
    stone_albedo_image = _load_stone_image("EOM_Stone_Albedo", stone_albedo_path, "sRGB")
    stone_normal_image = _load_stone_image("EOM_Stone_Normal", stone_normal_path, "Non-Color")
    stone_roughness_image = _load_stone_image(
        "EOM_Stone_Roughness",
        stone_roughness_path,
        "Non-Color",
    )
    ash_albedo_image = _load_ash_image("EOM_Ash_Albedo", ash_albedo_path, "sRGB")
    ash_normal_image = _load_ash_image("EOM_Ash_Normal", ash_normal_path, "Non-Color")
    ash_roughness_image = _load_ash_image(
        "EOM_Ash_Roughness",
        ash_roughness_path,
        "Non-Color",
    )
    _log(f"albedo={ash_albedo_path.name}")
    _log(f"normal={ash_normal_path.name}")
    _log(f"roughness={ash_roughness_path.name}")
    _log(f"ground albedo={ground_albedo_path.name}")
    _log(f"ground normal={ground_normal_path.name}")
    _log(f"ground roughness={ground_roughness_path.name}")
    _log(f"stone albedo={stone_albedo_path.name}")
    _log(f"stone normal={stone_normal_path.name}")
    _log(f"stone roughness={stone_roughness_path.name}")
    _log(f"albedo multiplier={STONE_ALBEDO_MULTIPLIER}")
    _log(f"shared UV layer={WORLD_UV_LAYER_NAME}")
    _log(f"shared UV scale={WORLD_UV_SCALE}")
    _log(f"normal strength={ASH_NORMAL_STRENGTH}")
    _log("uses existing ash weight")
    _log("existing stone weight applied after ash blend")

    out = _new_node(nodes, "ShaderNodeOutputMaterial")
    out.location = (1200, 0)

    principled = _new_node(nodes, "ShaderNodeBsdfPrincipled")
    principled.location = (900, 80)
    principled.label = "EOM_Final_Principled"
    _require_input(principled, "Roughness").default_value = BASE_ROUGHNESS

    tex_coord = _new_node(nodes, "ShaderNodeTexCoord")
    tex_coord.location = (-1500, 0)

    mapping = _new_node(nodes, "ShaderNodeMapping")
    mapping.location = (-1300, 0)
    _require_input(mapping, "Scale").default_value = (1.0, 1.0, 1.0)

    coord_output = _require_output(tex_coord, MATERIAL_COORD_SOURCE)
    links.new(coord_output, _require_input(mapping, "Vector"))
    mapped_vector = _require_output(mapping, "Vector")

    # Top faces use world-anchored planar XY UV (mesh layer EOM_WorldUV).
    # Cliff/side surfaces require a separate projection/material strategy in later work.
    ground_uv_map = _new_node(nodes, "ShaderNodeUVMap")
    ground_uv_map.location = (-1300, -360)
    ground_uv_map.uv_map = WORLD_UV_LAYER_NAME
    ground_uv_vector = _require_output(ground_uv_map, "UV")

    ground_uv_mapping = _new_node(nodes, "ShaderNodeMapping")
    ground_uv_mapping.location = (-1180, -360)
    ground_uv_mapping.label = "Ground UV Mapping"
    _require_input(ground_uv_mapping, "Scale").default_value = (1.0, 1.0, 1.0)
    links.new(ground_uv_vector, _require_input(ground_uv_mapping, "Vector"))
    ground_mapped_uv_vector = _require_output(ground_uv_mapping, "Vector")

    ground_albedo_tex = _new_image_texture_node(nodes, albedo_image, (-1080, -360))
    ground_normal_tex = _new_image_texture_node(nodes, normal_image, (-1080, -520))
    ground_roughness_tex = _new_image_texture_node(nodes, roughness_image, (-1080, -680))
    stone_albedo_tex = _new_image_texture_node(nodes, stone_albedo_image, (-1080, -840))
    stone_normal_tex = _new_image_texture_node(nodes, stone_normal_image, (-1080, -1000))
    stone_roughness_tex = _new_image_texture_node(nodes, stone_roughness_image, (-1080, -1160))
    ash_albedo_tex = _new_image_texture_node(nodes, ash_albedo_image, (-1080, -1320))
    ash_normal_tex = _new_image_texture_node(nodes, ash_normal_image, (-1080, -1480))
    ash_roughness_tex = _new_image_texture_node(nodes, ash_roughness_image, (-1080, -1640))
    links.new(ground_mapped_uv_vector, _require_input(ground_albedo_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(ground_normal_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(ground_roughness_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(stone_albedo_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(stone_normal_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(stone_roughness_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(ash_albedo_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(ash_normal_tex, "Vector"))
    links.new(ground_mapped_uv_vector, _require_input(ash_roughness_tex, "Vector"))
    _assert_shared_pbr_uv_chain(
        nodes,
        ground_uv_mapping,
        (
            ("ground_albedo", ground_albedo_tex),
            ("ground_normal", ground_normal_tex),
            ("ground_roughness", ground_roughness_tex),
            ("stone_albedo", stone_albedo_tex),
            ("stone_normal", stone_normal_tex),
            ("stone_roughness", stone_roughness_tex),
            ("ash_albedo", ash_albedo_tex),
            ("ash_normal", ash_normal_tex),
            ("ash_roughness", ash_roughness_tex),
        ),
        expected_layer_name=WORLD_UV_LAYER_NAME,
    )
    ground_albedo_output = _require_output(ground_albedo_tex, "Color")
    ash_albedo_raw = _require_output(ash_albedo_tex, "Color")

    ground_tint_rgb = _new_node(nodes, "ShaderNodeRGB")
    ground_tint_rgb.location = (-860, -420)
    _require_output(ground_tint_rgb, "Color").default_value = GROUND_BASE_COLOR

    ground_tint_mix = _new_color_mix_node(nodes, "MIX", (-640, -360))
    if GROUND_ALBEDO_TINT_STRENGTH > 0.0:
        ground_tint_mix.factor.default_value = GROUND_ALBEDO_TINT_STRENGTH
    else:
        ground_tint_mix.factor.default_value = 0.0
    links.new(ground_albedo_output, ground_tint_mix.color1)
    links.new(_require_output(ground_tint_rgb, "Color"), ground_tint_mix.color2)
    ground_tinted_output = ground_tint_mix.output

    ash_albedo_output = ash_albedo_raw
    if ASH_ALBEDO_TINT_STRENGTH > 0.0:
        ash_tint_rgb = _new_node(nodes, "ShaderNodeRGB")
        ash_tint_rgb.location = (-860, -1380)
        _require_output(ash_tint_rgb, "Color").default_value = ASH_BASE_COLOR
        ash_tint_mix = _new_color_mix_node(nodes, "MIX", (-640, -1320))
        ash_tint_mix.factor.default_value = ASH_ALBEDO_TINT_STRENGTH
        links.new(ash_albedo_raw, ash_tint_mix.color1)
        links.new(_require_output(ash_tint_rgb, "Color"), ash_tint_mix.color2)
        ash_albedo_output = ash_tint_mix.output

    ground_roughness_scaled = _new_node(nodes, "ShaderNodeMath")
    ground_roughness_scaled.location = (-860, -680)
    ground_roughness_scaled.operation = "MULTIPLY"
    _math_input(ground_roughness_scaled, 1).default_value = GROUND_ROUGHNESS_MULTIPLIER
    links.new(_require_output(ground_roughness_tex, "Color"), _math_input(ground_roughness_scaled, 0))

    ground_roughness_gray = _new_node(nodes, "ShaderNodeCombineColor")
    ground_roughness_gray.location = (-640, -680)
    links.new(
        _require_output(ground_roughness_scaled, "Value"),
        _require_input(ground_roughness_gray, "Red"),
    )
    links.new(
        _require_output(ground_roughness_scaled, "Value"),
        _require_input(ground_roughness_gray, "Green"),
    )
    links.new(
        _require_output(ground_roughness_scaled, "Value"),
        _require_input(ground_roughness_gray, "Blue"),
    )
    ground_roughness_visual = _require_output(ground_roughness_gray, "Color")

    stone_albedo_raw = _require_output(stone_albedo_tex, "Color")

    stone_albedo_multiplier_rgb = _new_node(nodes, "ShaderNodeRGB")
    stone_albedo_multiplier_rgb.location = (-860, -900)
    _require_output(stone_albedo_multiplier_rgb, "Color").default_value = (
        STONE_ALBEDO_MULTIPLIER,
        STONE_ALBEDO_MULTIPLIER,
        STONE_ALBEDO_MULTIPLIER,
        1.0,
    )

    stone_albedo_multiply = _new_color_mix_node(nodes, "MULTIPLY", (-640, -840))
    stone_albedo_multiply.factor.default_value = 1.0
    links.new(stone_albedo_raw, stone_albedo_multiply.color1)
    links.new(
        _require_output(stone_albedo_multiplier_rgb, "Color"),
        stone_albedo_multiply.color2,
    )
    stone_albedo_output = stone_albedo_multiply.output

    if STONE_ALBEDO_TINT_STRENGTH > 0.0:
        stone_tint_rgb = _new_node(nodes, "ShaderNodeRGB")
        stone_tint_rgb.location = (-860, -960)
        _require_output(stone_tint_rgb, "Color").default_value = STONE_BASE_COLOR
        stone_tint_mix = _new_color_mix_node(nodes, "MIX", (-420, -840))
        stone_tint_mix.factor.default_value = STONE_ALBEDO_TINT_STRENGTH
        links.new(stone_albedo_output, stone_tint_mix.color1)
        links.new(_require_output(stone_tint_rgb, "Color"), stone_tint_mix.color2)
        stone_albedo_output = stone_tint_mix.output

    large_noise = _new_node(nodes, "ShaderNodeTexNoise")
    large_noise.location = (-1080, 260)
    _require_input(large_noise, "Scale").default_value = LARGE_NOISE_SCALE
    _require_input(large_noise, "Detail").default_value = LARGE_NOISE_DETAIL
    _require_input(large_noise, "Roughness").default_value = LARGE_NOISE_ROUGHNESS

    large_factor_map = _new_node(nodes, "ShaderNodeMapRange")
    large_factor_map.location = (-860, 260)
    large_factor_map.clamp = True
    _require_input(large_factor_map, "From Min").default_value = 0.35
    _require_input(large_factor_map, "From Max").default_value = 0.65
    _require_input(large_factor_map, "To Min").default_value = 0.0
    _require_input(large_factor_map, "To Max").default_value = 1.0

    fine_noise = _new_node(nodes, "ShaderNodeTexNoise")
    fine_noise.location = (-1080, -120)
    _require_input(fine_noise, "Scale").default_value = FINE_NOISE_SCALE
    _require_input(fine_noise, "Detail").default_value = FINE_NOISE_DETAIL
    _require_input(fine_noise, "Roughness").default_value = 0.55

    debug_neutral_rgb = _new_node(nodes, "ShaderNodeRGB")
    debug_neutral_rgb.location = (-640, -900)
    _require_output(debug_neutral_rgb, "Color").default_value = (0.18, 0.18, 0.18, 1.0)

    debug_neutral_roughness_node = _new_node(nodes, "ShaderNodeValue")
    debug_neutral_roughness_node.location = (1040, -300)
    debug_neutral_roughness_node.label = "Debug Neutral Roughness"
    _require_output(debug_neutral_roughness_node, "Value").default_value = 0.55
    debug_neutral_roughness = _require_output(debug_neutral_roughness_node, "Value")

    stone_roughness_scaled = _new_node(nodes, "ShaderNodeMath")
    stone_roughness_scaled.location = (-860, -1160)
    stone_roughness_scaled.operation = "MULTIPLY"
    _math_input(stone_roughness_scaled, 1).default_value = STONE_ROUGHNESS_MULTIPLIER
    links.new(
        _require_output(stone_roughness_tex, "Color"),
        _math_input(stone_roughness_scaled, 0),
    )

    if USE_ROUGHNESS_VARIATION and STONE_ROUGHNESS_VARIATION_STRENGTH > 0.0:
        stone_rough_sub = _new_node(nodes, "ShaderNodeMath")
        stone_rough_sub.location = (-640, -1240)
        stone_rough_sub.operation = "SUBTRACT"
        _math_input(stone_rough_sub, 1).default_value = 0.5

        stone_rough_mul = _new_node(nodes, "ShaderNodeMath")
        stone_rough_mul.location = (-640, -1160)
        stone_rough_mul.operation = "MULTIPLY"
        _math_input(stone_rough_mul, 1).default_value = STONE_ROUGHNESS_VARIATION_STRENGTH * 2.0

        stone_rough_add = _new_node(nodes, "ShaderNodeMath")
        stone_rough_add.location = (-460, -1160)
        stone_rough_add.operation = "ADD"

        links.new(_require_output(fine_noise, "Fac"), _math_input(stone_rough_sub, 0))
        links.new(_require_output(stone_rough_sub, "Value"), _math_input(stone_rough_mul, 0))
        links.new(_require_output(stone_roughness_scaled, "Value"), _math_input(stone_rough_add, 0))
        links.new(_require_output(stone_rough_mul, "Value"), _math_input(stone_rough_add, 1))
        stone_roughness_value = _require_output(stone_rough_add, "Value")
    else:
        stone_roughness_value = _require_output(stone_roughness_scaled, "Value")

    stone_rough_clamp = _new_node(nodes, "ShaderNodeClamp")
    stone_rough_clamp.location = (-280, -1160)
    _require_input(stone_rough_clamp, "Min").default_value = 0.0
    _require_input(stone_rough_clamp, "Max").default_value = 1.0
    links.new(stone_roughness_value, _require_input(stone_rough_clamp, "Value"))
    stone_roughness_final = _require_output(stone_rough_clamp, "Result")

    stone_roughness_gray = _new_node(nodes, "ShaderNodeCombineColor")
    stone_roughness_gray.location = (-80, -1160)
    links.new(stone_roughness_final, _require_input(stone_roughness_gray, "Red"))
    links.new(stone_roughness_final, _require_input(stone_roughness_gray, "Green"))
    links.new(stone_roughness_final, _require_input(stone_roughness_gray, "Blue"))
    stone_roughness_visual = _require_output(stone_roughness_gray, "Color")

    ash_roughness_scaled = _new_node(nodes, "ShaderNodeMath")
    ash_roughness_scaled.location = (-860, -1640)
    ash_roughness_scaled.operation = "MULTIPLY"
    _math_input(ash_roughness_scaled, 1).default_value = ASH_ROUGHNESS_MULTIPLIER
    links.new(
        _require_output(ash_roughness_tex, "Color"),
        _math_input(ash_roughness_scaled, 0),
    )

    if USE_ROUGHNESS_VARIATION and ASH_ROUGHNESS_VARIATION_STRENGTH > 0.0:
        ash_rough_sub = _new_node(nodes, "ShaderNodeMath")
        ash_rough_sub.location = (-640, -1720)
        ash_rough_sub.operation = "SUBTRACT"
        _math_input(ash_rough_sub, 1).default_value = 0.5

        ash_rough_mul = _new_node(nodes, "ShaderNodeMath")
        ash_rough_mul.location = (-640, -1640)
        ash_rough_mul.operation = "MULTIPLY"
        _math_input(ash_rough_mul, 1).default_value = ASH_ROUGHNESS_VARIATION_STRENGTH * 2.0

        ash_rough_add = _new_node(nodes, "ShaderNodeMath")
        ash_rough_add.location = (-460, -1640)
        ash_rough_add.operation = "ADD"

        links.new(_require_output(fine_noise, "Fac"), _math_input(ash_rough_sub, 0))
        links.new(_require_output(ash_rough_sub, "Value"), _math_input(ash_rough_mul, 0))
        links.new(_require_output(ash_roughness_scaled, "Value"), _math_input(ash_rough_add, 0))
        links.new(_require_output(ash_rough_mul, "Value"), _math_input(ash_rough_add, 1))
        ash_roughness_value = _require_output(ash_rough_add, "Value")
    else:
        ash_roughness_value = _require_output(ash_roughness_scaled, "Value")

    ash_rough_clamp = _new_node(nodes, "ShaderNodeClamp")
    ash_rough_clamp.location = (-280, -1640)
    _require_input(ash_rough_clamp, "Min").default_value = 0.0
    _require_input(ash_rough_clamp, "Max").default_value = 1.0
    links.new(ash_roughness_value, _require_input(ash_rough_clamp, "Value"))
    ash_roughness_final = _require_output(ash_rough_clamp, "Result")

    ash_roughness_gray = _new_node(nodes, "ShaderNodeCombineColor")
    ash_roughness_gray.location = (-80, -1640)
    links.new(ash_roughness_final, _require_input(ash_roughness_gray, "Red"))
    links.new(ash_roughness_final, _require_input(ash_roughness_gray, "Green"))
    links.new(ash_roughness_final, _require_input(ash_roughness_gray, "Blue"))
    ash_roughness_visual = _require_output(ash_roughness_gray, "Color")

    mix_ground_ash = _new_color_mix_node(nodes, "MIX", (-420, 320))
    ash_factor_raw_output: bpy.types.NodeSocket | None = None
    ash_factor_output: bpy.types.NodeSocket | None = None
    ash_weight_remap: bpy.types.Node | None = None
    ash_breakup_noise: bpy.types.Node | None = None
    ash_breakup_remap: bpy.types.Node | None = None
    ash_breakup_strength_mix: bpy.types.Node | None = None
    ash_combined_mul: bpy.types.Node | None = None
    ash_breakup_factor_output: bpy.types.NodeSocket | None = None
    ash_combined_raw_output: bpy.types.NodeSocket | None = None
    if USE_LARGE_SCALE_VARIATION:
        links.new(mapped_vector, _require_input(large_noise, "Vector"))
        links.new(_require_output(large_noise, "Fac"), _require_input(large_factor_map, "Value"))
        ash_factor_raw_output = _require_output(large_factor_map, "Result")

        if USE_ASH_BREAKUP:
            ash_breakup_noise = _new_node(nodes, "ShaderNodeTexNoise")
            ash_breakup_noise.location = (-1080, 420)
            ash_breakup_noise.label = "Ash Breakup Noise"
            _require_input(ash_breakup_noise, "Scale").default_value = ASH_BREAKUP_NOISE_SCALE
            _require_input(ash_breakup_noise, "Detail").default_value = ASH_BREAKUP_NOISE_DETAIL
            _require_input(ash_breakup_noise, "Roughness").default_value = ASH_BREAKUP_NOISE_ROUGHNESS
            links.new(mapped_vector, _require_input(ash_breakup_noise, "Vector"))

            ash_breakup_remap = _new_node(nodes, "ShaderNodeMapRange")
            ash_breakup_remap.location = (-860, 420)
            ash_breakup_remap.label = "Ash Breakup Remap"
            _configure_ash_breakup_remap_node(ash_breakup_remap)
            links.new(
                _require_output(ash_breakup_noise, "Fac"),
                _map_range_float_input(ash_breakup_remap, "Value"),
            )
            ash_breakup_factor_output = _require_output(ash_breakup_remap, "Result")

            ash_breakup_one = _new_node(nodes, "ShaderNodeValue")
            ash_breakup_one.location = (-860, 520)
            ash_breakup_one.label = "Ash Breakup Unity"
            _require_output(ash_breakup_one, "Value").default_value = 1.0

            ash_breakup_strength_mix = _new_float_mix_node(nodes, (-720, 420))
            ash_breakup_strength_mix.label = "Ash Breakup Strength Mix"
            _require_input(ash_breakup_strength_mix, "Factor").default_value = ASH_BREAKUP_STRENGTH
            links.new(
                _require_output(ash_breakup_one, "Value"),
                _require_input(ash_breakup_strength_mix, "A"),
            )
            links.new(
                ash_breakup_factor_output,
                _require_input(ash_breakup_strength_mix, "B"),
            )
            effective_breakup_output = _require_output(ash_breakup_strength_mix, "Result")

            ash_combined_mul = _new_node(nodes, "ShaderNodeMath")
            ash_combined_mul.location = (-720, 260)
            ash_combined_mul.label = "Ash Combined Multiply"
            ash_combined_mul.operation = "MULTIPLY"
            links.new(ash_factor_raw_output, _math_input(ash_combined_mul, 0))
            links.new(effective_breakup_output, _math_input(ash_combined_mul, 1))
            ash_combined_raw_output = _require_output(ash_combined_mul, "Value")
        else:
            ash_combined_raw_output = ash_factor_raw_output

        ash_weight_remap = _new_node(nodes, "ShaderNodeMapRange")
        ash_weight_remap.location = (-640, 260)
        ash_weight_remap.label = "Ash Weight Remap"
        _configure_ash_weight_remap_node(ash_weight_remap)
        links.new(ash_combined_raw_output, _map_range_float_input(ash_weight_remap, "Value"))
        ash_factor_output = _require_output(ash_weight_remap, "Result")
        links.new(ash_factor_output, mix_ground_ash.factor)

        _log("ash raw weight source=large_factor_map.Result")
        _log(f"ash breakup enabled={USE_ASH_BREAKUP}")
        if USE_ASH_BREAKUP:
            _log(f"ash breakup scale={ASH_BREAKUP_NOISE_SCALE}")
            _log(f"ash breakup detail={ASH_BREAKUP_NOISE_DETAIL}")
            _log(f"ash breakup roughness={ASH_BREAKUP_NOISE_ROUGHNESS}")
            _log(f"ash breakup remap={ASH_BREAKUP_MIN}..{ASH_BREAKUP_MAX}")
            _log(f"ash breakup strength={ASH_BREAKUP_STRENGTH}")
        _log(f"ash remap input_min={ASH_WEIGHT_INPUT_MIN}")
        _log(f"ash remap input_max={ASH_WEIGHT_INPUT_MAX}")
        _log("final ash remap input source=ash_combined_raw_output")
        _log("ash remapped weight drives albedo/normal/roughness")
    else:
        mix_ground_ash.factor.default_value = 0.0

    # Ground PBR albedo (optionally tinted) replaces the old solid GROUND_BASE_COLOR source.
    links.new(ground_tinted_output, mix_ground_ash.color1)
    links.new(ash_albedo_output, mix_ground_ash.color2)

    ash_mask_color = _new_node(nodes, "ShaderNodeCombineColor")
    ash_mask_color.location = (-80, 320)
    if ash_factor_output is not None:
        links.new(ash_factor_output, _require_input(ash_mask_color, "Red"))
        links.new(ash_factor_output, _require_input(ash_mask_color, "Green"))
        links.new(ash_factor_output, _require_input(ash_mask_color, "Blue"))
    ash_mask_color_output = _require_output(ash_mask_color, "Color")

    geometry = _new_node(nodes, "ShaderNodeNewGeometry", "ShaderNodeGeometry")
    geometry.location = (-860, -40)

    separate_xyz = _new_node(nodes, "ShaderNodeSeparateXYZ")
    separate_xyz.location = (-640, -40)
    links.new(_require_output(geometry, "Normal"), _require_input(separate_xyz, "Vector"))
    normal_z = _require_output(separate_xyz, "Z")

    breakup_noise = _new_node(nodes, "ShaderNodeTexNoise")
    breakup_noise.location = (-860, -200)
    _require_input(breakup_noise, "Scale").default_value = STONE_BREAKUP_NOISE_SCALE
    _require_input(breakup_noise, "Detail").default_value = STONE_BREAKUP_NOISE_DETAIL
    _require_input(breakup_noise, "Roughness").default_value = STONE_BREAKUP_NOISE_ROUGHNESS

    breakup_sub = _new_node(nodes, "ShaderNodeMath")
    breakup_sub.location = (-640, -200)
    breakup_sub.operation = "SUBTRACT"
    _math_input(breakup_sub, 1).default_value = 0.5

    breakup_signed = _new_node(nodes, "ShaderNodeMath")
    breakup_signed.location = (-460, -200)
    breakup_signed.operation = "MULTIPLY"
    _math_input(breakup_signed, 1).default_value = 2.0

    breakup_offset = _new_node(nodes, "ShaderNodeMath")
    breakup_offset.location = (-280, -200)
    breakup_offset.operation = "MULTIPLY"
    _math_input(breakup_offset, 1).default_value = STONE_BREAKUP_STRENGTH

    effective_normal_z = _new_node(nodes, "ShaderNodeMath")
    effective_normal_z.location = (-460, -40)
    effective_normal_z.operation = "ADD"

    slope_map = _new_node(nodes, "ShaderNodeMapRange")
    slope_map.location = (-280, -40)
    slope_map.clamp = True
    _require_input(slope_map, "From Min").default_value = SLOPE_BLEND_END
    _require_input(slope_map, "From Max").default_value = SLOPE_BLEND_START
    _require_input(slope_map, "To Min").default_value = 1.0
    _require_input(slope_map, "To Max").default_value = 0.0

    stone_mask_color = _new_node(nodes, "ShaderNodeCombineColor")
    stone_mask_color.location = (-80, -120)
    stone_factor_output = _require_output(slope_map, "Result")
    links.new(stone_factor_output, _require_input(stone_mask_color, "Red"))
    links.new(stone_factor_output, _require_input(stone_mask_color, "Green"))
    links.new(stone_factor_output, _require_input(stone_mask_color, "Blue"))
    stone_mask_color_output = _require_output(stone_mask_color, "Color")

    if USE_STONE_BREAKUP and STONE_BREAKUP_STRENGTH > 0.0:
        links.new(mapped_vector, _require_input(breakup_noise, "Vector"))
        links.new(_require_output(breakup_noise, "Fac"), _math_input(breakup_sub, 0))
        links.new(_require_output(breakup_sub, "Value"), _math_input(breakup_signed, 0))
        links.new(_require_output(breakup_signed, "Value"), _math_input(breakup_offset, 0))
        links.new(normal_z, _math_input(effective_normal_z, 0))
        links.new(_require_output(breakup_offset, "Value"), _math_input(effective_normal_z, 1))
        links.new(_require_output(effective_normal_z, "Value"), _require_input(slope_map, "Value"))
        _log(
            "Stone breakup: enabled; stone mask uses perturbed normal_z "
            f"(scale={STONE_BREAKUP_NOISE_SCALE}, strength={STONE_BREAKUP_STRENGTH})"
        )
    else:
        links.new(normal_z, _require_input(slope_map, "Value"))
        _log("Stone breakup: disabled; stone mask uses raw normal_z")

    mix_stone = _new_color_mix_node(nodes, "MIX", (-80, 180))
    if USE_SLOPE_BLEND:
        links.new(_require_output(slope_map, "Result"), mix_stone.factor)
    else:
        mix_stone.factor.default_value = 0.0

    links.new(mix_ground_ash.output, mix_stone.color1)
    links.new(stone_albedo_output, mix_stone.color2)

    mix_ground_stone_debug = _new_color_mix_node(nodes, "MIX", (-80, 60))
    links.new(ground_tinted_output, mix_ground_stone_debug.color1)
    links.new(stone_albedo_output, mix_ground_stone_debug.color2)
    links.new(stone_factor_output, mix_ground_stone_debug.factor)

    fine_tint_rgb = _new_node(nodes, "ShaderNodeRGB")
    fine_tint_rgb.location = (-180, -220)
    tint = tuple(min(1.0, c + FINE_NOISE_STRENGTH * 0.35) for c in GROUND_BASE_COLOR[:3]) + (1.0,)
    _require_output(fine_tint_rgb, "Color").default_value = tint

    mix_fine = _new_color_mix_node(nodes, "MIX", (80, 120))
    needs_fine_noise = (
        USE_FINE_DETAIL
        or USE_ROUGHNESS_VARIATION
        or (USE_PROCEDURAL_BUMP and BUMP_STRENGTH > 0.0)
    )
    if needs_fine_noise:
        links.new(mapped_vector, _require_input(fine_noise, "Vector"))

    if USE_FINE_DETAIL:
        fine_factor_map = _new_node(nodes, "ShaderNodeMapRange")
        fine_factor_map.location = (-860, -220)
        fine_factor_map.clamp = True
        _require_input(fine_factor_map, "From Min").default_value = 0.47
        _require_input(fine_factor_map, "From Max").default_value = 0.53
        _require_input(fine_factor_map, "To Min").default_value = 0.0
        _require_input(fine_factor_map, "To Max").default_value = 1.0

        fine_strength_mul = _new_node(nodes, "ShaderNodeMath")
        fine_strength_mul.location = (-640, -220)
        fine_strength_mul.operation = "MULTIPLY"
        _math_input(fine_strength_mul, 1).default_value = FINE_NOISE_STRENGTH

        links.new(_require_output(fine_noise, "Fac"), _require_input(fine_factor_map, "Value"))
        links.new(_require_output(fine_factor_map, "Result"), _math_input(fine_strength_mul, 0))
        links.new(_require_output(fine_strength_mul, "Value"), mix_fine.factor)
    else:
        mix_fine.factor.default_value = 0.0

    links.new(mix_stone.output, mix_fine.color1)
    links.new(_require_output(fine_tint_rgb, "Color"), mix_fine.color2)

    _assert_color_mix_links(
        mix_ground_ash,
        "mix_ground_ash",
        expect_factor_linked=USE_LARGE_SCALE_VARIATION,
    )
    _assert_color_mix_links(
        mix_stone,
        "mix_stone",
        expect_factor_linked=USE_SLOPE_BLEND,
    )
    _assert_color_mix_links(
        mix_fine,
        "mix_fine",
        expect_factor_linked=USE_FINE_DETAIL,
    )

    # Diagnostic ash brightness stages must not modify the approved final material graph.
    diag_raw_emission = _new_node(nodes, "ShaderNodeEmission")
    diag_raw_emission.location = (900, 400)
    diag_raw_emission.label = "EOM_Ash_Raw_Emission"
    _require_input(diag_raw_emission, "Strength").default_value = 1.0
    links.new(ash_albedo_raw, _require_input(diag_raw_emission, "Color"))

    diag_diffuse_principled = _new_node(nodes, "ShaderNodeBsdfPrincipled")
    diag_diffuse_principled.location = (900, 240)
    diag_diffuse_principled.label = "EOM_Ash_Diffuse_Diagnostic"
    _configure_diagnostic_diffuse_principled(
        links,
        diag_diffuse_principled,
        ash_albedo_raw,
    )

    diag_mask_grayscale = _new_node(nodes, "ShaderNodeCombineColor")
    diag_mask_grayscale.location = (700, 520)
    diag_mask_grayscale.label = "EOM_Ash_Mask_Raw_Grayscale"
    if ash_factor_raw_output is not None:
        links.new(ash_factor_raw_output, _require_input(diag_mask_grayscale, "Red"))
        links.new(ash_factor_raw_output, _require_input(diag_mask_grayscale, "Green"))
        links.new(ash_factor_raw_output, _require_input(diag_mask_grayscale, "Blue"))
    diag_mask_grayscale_output = _require_output(diag_mask_grayscale, "Color")

    diag_mask_emission = _new_node(nodes, "ShaderNodeEmission")
    diag_mask_emission.location = (900, 520)
    diag_mask_emission.label = "EOM_Ash_Mask_Raw_Emission"
    _require_input(diag_mask_emission, "Strength").default_value = 1.0
    links.new(diag_mask_grayscale_output, _require_input(diag_mask_emission, "Color"))

    diag_breakup_grayscale = _new_node(nodes, "ShaderNodeCombineColor")
    diag_breakup_grayscale.location = (700, 360)
    diag_breakup_grayscale.label = "EOM_Ash_Breakup_Grayscale"
    if ash_breakup_factor_output is not None:
        links.new(ash_breakup_factor_output, _require_input(diag_breakup_grayscale, "Red"))
        links.new(ash_breakup_factor_output, _require_input(diag_breakup_grayscale, "Green"))
        links.new(ash_breakup_factor_output, _require_input(diag_breakup_grayscale, "Blue"))
    diag_breakup_grayscale_output = _require_output(diag_breakup_grayscale, "Color")

    diag_breakup_emission = _new_node(nodes, "ShaderNodeEmission")
    diag_breakup_emission.location = (900, 360)
    diag_breakup_emission.label = "EOM_Ash_Breakup_Emission"
    _require_input(diag_breakup_emission, "Strength").default_value = 1.0
    links.new(diag_breakup_grayscale_output, _require_input(diag_breakup_emission, "Color"))

    diag_combined_grayscale = _new_node(nodes, "ShaderNodeCombineColor")
    diag_combined_grayscale.location = (700, 600)
    diag_combined_grayscale.label = "EOM_Ash_Mask_Combined_Grayscale"
    if ash_combined_raw_output is not None:
        links.new(ash_combined_raw_output, _require_input(diag_combined_grayscale, "Red"))
        links.new(ash_combined_raw_output, _require_input(diag_combined_grayscale, "Green"))
        links.new(ash_combined_raw_output, _require_input(diag_combined_grayscale, "Blue"))
    diag_combined_grayscale_output = _require_output(diag_combined_grayscale, "Color")

    diag_combined_emission = _new_node(nodes, "ShaderNodeEmission")
    diag_combined_emission.location = (900, 600)
    diag_combined_emission.label = "EOM_Ash_Mask_Combined_Emission"
    _require_input(diag_combined_emission, "Strength").default_value = 1.0
    links.new(diag_combined_grayscale_output, _require_input(diag_combined_emission, "Color"))

    diag_mask_remapped_grayscale = _new_node(nodes, "ShaderNodeCombineColor")
    diag_mask_remapped_grayscale.location = (700, 680)
    diag_mask_remapped_grayscale.label = "EOM_Ash_Mask_Remapped_Grayscale"
    if ash_factor_output is not None:
        links.new(ash_factor_output, _require_input(diag_mask_remapped_grayscale, "Red"))
        links.new(ash_factor_output, _require_input(diag_mask_remapped_grayscale, "Green"))
        links.new(ash_factor_output, _require_input(diag_mask_remapped_grayscale, "Blue"))
    diag_mask_remapped_grayscale_output = _require_output(diag_mask_remapped_grayscale, "Color")

    diag_mask_remapped_emission = _new_node(nodes, "ShaderNodeEmission")
    diag_mask_remapped_emission.location = (900, 680)
    diag_mask_remapped_emission.label = "EOM_Ash_Mask_Remapped_Emission"
    _require_input(diag_mask_remapped_emission, "Strength").default_value = 1.0
    links.new(
        diag_mask_remapped_grayscale_output,
        _require_input(diag_mask_remapped_emission, "Color"),
    )

    if DEBUG_MATERIAL_STAGE not in {
        "ash_albedo_raw",
        "ash_albedo_diffuse",
        "ash_mask_raw",
        "ash_breakup_raw",
        "ash_mask_combined_raw",
        "ash_mask_remapped_raw",
    }:
        _apply_debug_base_color_link(
            links,
            principled,
            DEBUG_MATERIAL_STAGE,
            ground_tinted_output=ground_tinted_output,
            ground_albedo_output=ground_albedo_output,
            ground_roughness_visual=ground_roughness_visual,
            ash_albedo_output=ash_albedo_output,
            ash_roughness_visual=ash_roughness_visual,
            stone_albedo_output=stone_albedo_output,
            stone_roughness_visual=stone_roughness_visual,
            mix_ground_ash=mix_ground_ash,
            mix_stone=mix_stone,
            mix_ground_stone_debug=mix_ground_stone_debug,
            mix_fine=mix_fine,
            ash_mask_color_output=ash_mask_color_output,
            stone_mask_color_output=stone_mask_color_output,
            debug_neutral_rgb=debug_neutral_rgb,
        )

    ground_normal_map = _new_node(nodes, "ShaderNodeNormalMap")
    ground_normal_map.location = (-640, -520)
    ground_normal_map.space = "TANGENT"
    _require_input(ground_normal_map, "Strength").default_value = GROUND_NORMAL_STRENGTH
    links.new(
        _require_output(ground_normal_tex, "Color"),
        _require_input(ground_normal_map, "Color"),
    )

    stone_normal_map = _new_node(nodes, "ShaderNodeNormalMap")
    stone_normal_map.location = (-640, -1000)
    stone_normal_map.space = "TANGENT"
    _require_input(stone_normal_map, "Strength").default_value = STONE_NORMAL_STRENGTH
    links.new(
        _require_output(stone_normal_tex, "Color"),
        _require_input(stone_normal_map, "Color"),
    )

    ash_normal_map = _new_node(nodes, "ShaderNodeNormalMap")
    ash_normal_map.location = (-640, -1480)
    ash_normal_map.space = "TANGENT"
    _require_input(ash_normal_map, "Strength").default_value = ASH_NORMAL_STRENGTH
    links.new(
        _require_output(ash_normal_tex, "Color"),
        _require_input(ash_normal_map, "Color"),
    )

    normal_mix_ground_ash = _new_vector_mix_node(nodes, (220, -520))
    links.new(_require_output(ground_normal_map, "Normal"), _require_input(normal_mix_ground_ash, "A"))
    links.new(_require_output(ash_normal_map, "Normal"), _require_input(normal_mix_ground_ash, "B"))
    if ash_factor_output is not None:
        links.new(ash_factor_output, _require_input(normal_mix_ground_ash, "Factor"))
    ground_ash_normal_output = _require_output(normal_mix_ground_ash, "Result")

    normal_mix_stone = _new_vector_mix_node(nodes, (420, -520))
    links.new(ground_ash_normal_output, _require_input(normal_mix_stone, "A"))
    links.new(_require_output(stone_normal_map, "Normal"), _require_input(normal_mix_stone, "B"))
    links.new(stone_factor_output, _require_input(normal_mix_stone, "Factor"))
    blended_normal_output = _require_output(normal_mix_stone, "Result")

    normal_mix_stone_only = _new_vector_mix_node(nodes, (420, -700))
    links.new(_require_output(ground_normal_map, "Normal"), _require_input(normal_mix_stone_only, "A"))
    links.new(_require_output(stone_normal_map, "Normal"), _require_input(normal_mix_stone_only, "B"))
    links.new(stone_factor_output, _require_input(normal_mix_stone_only, "Factor"))
    ground_stone_normal_output = _require_output(normal_mix_stone_only, "Result")

    bump = _new_node(nodes, "ShaderNodeBump")
    bump.location = (680, -300)
    _require_input(bump, "Strength").default_value = BUMP_STRENGTH
    _require_input(bump, "Distance").default_value = BUMP_DISTANCE
    links.new(blended_normal_output, _require_input(bump, "Normal"))
    if USE_PROCEDURAL_BUMP and BUMP_STRENGTH > 0.0:
        links.new(_require_output(fine_noise, "Fac"), _require_input(bump, "Height"))
    combined_normal_output = _require_output(bump, "Normal")
    links.new(combined_normal_output, _require_input(principled, "Normal"))

    roughness_out = _require_input(principled, "Roughness")
    ground_roughness_base = _require_output(ground_roughness_scaled, "Value")
    if USE_ROUGHNESS_VARIATION and GROUND_ROUGHNESS_VARIATION_STRENGTH > 0.0:
        rough_sub = _new_node(nodes, "ShaderNodeMath")
        rough_sub.location = (500, -120)
        rough_sub.operation = "SUBTRACT"
        _math_input(rough_sub, 1).default_value = 0.5

        rough_mul = _new_node(nodes, "ShaderNodeMath")
        rough_mul.location = (680, -120)
        rough_mul.operation = "MULTIPLY"
        _math_input(rough_mul, 1).default_value = GROUND_ROUGHNESS_VARIATION_STRENGTH * 2.0

        rough_add = _new_node(nodes, "ShaderNodeMath")
        rough_add.location = (860, -120)
        rough_add.operation = "ADD"

        rough_clamp = _new_node(nodes, "ShaderNodeClamp")
        rough_clamp.location = (1040, -120)
        _require_input(rough_clamp, "Min").default_value = 0.0
        _require_input(rough_clamp, "Max").default_value = 1.0

        links.new(_require_output(fine_noise, "Fac"), _math_input(rough_sub, 0))
        links.new(_require_output(rough_sub, "Value"), _math_input(rough_mul, 0))
        links.new(ground_roughness_base, _math_input(rough_add, 0))
        links.new(_require_output(rough_mul, "Value"), _math_input(rough_add, 1))
        links.new(_require_output(rough_add, "Value"), _require_input(rough_clamp, "Value"))
        ground_roughness_final = _require_output(rough_clamp, "Result")
    else:
        ground_roughness_final = ground_roughness_base

    rough_mix_ground_ash = _new_float_mix_node(nodes, (1040, -120))
    links.new(ground_roughness_final, _require_input(rough_mix_ground_ash, "A"))
    links.new(ash_roughness_final, _require_input(rough_mix_ground_ash, "B"))
    if ash_factor_output is not None:
        links.new(ash_factor_output, _require_input(rough_mix_ground_ash, "Factor"))
    ground_ash_roughness_output = _require_output(rough_mix_ground_ash, "Result")

    rough_mix_stone = _new_float_mix_node(nodes, (1220, -120))
    links.new(ground_ash_roughness_output, _require_input(rough_mix_stone, "A"))
    links.new(stone_roughness_final, _require_input(rough_mix_stone, "B"))
    links.new(stone_factor_output, _require_input(rough_mix_stone, "Factor"))
    mixed_roughness_output = _require_output(rough_mix_stone, "Result")

    rough_mix_stone_only = _new_float_mix_node(nodes, (1220, -280))
    links.new(ground_roughness_final, _require_input(rough_mix_stone_only, "A"))
    links.new(stone_roughness_final, _require_input(rough_mix_stone_only, "B"))
    links.new(stone_factor_output, _require_input(rough_mix_stone_only, "Factor"))
    ground_stone_roughness_output = _require_output(rough_mix_stone_only, "Result")
    links.new(mixed_roughness_output, roughness_out)

    _assert_ash_pbr_splat_weights(
        mix_ground_ash=mix_ground_ash,
        normal_mix_ground_ash=normal_mix_ground_ash,
        rough_mix_ground_ash=rough_mix_ground_ash,
        ash_factor_output=ash_factor_output,
        ash_normal_map=ash_normal_map,
    )
    _assert_ash_breakup_chain(
        mapping=mapping,
        mapped_vector=mapped_vector,
        ash_factor_raw_output=ash_factor_raw_output,
        ash_breakup_noise=ash_breakup_noise,
        ash_breakup_remap=ash_breakup_remap,
        ash_breakup_strength_mix=ash_breakup_strength_mix,
        ash_combined_mul=ash_combined_mul,
        ash_breakup_factor_output=ash_breakup_factor_output,
        ash_combined_raw_output=ash_combined_raw_output,
    )
    _assert_ash_weight_remap(
        large_factor_map=large_factor_map,
        ash_weight_remap=ash_weight_remap,
        ash_factor_raw_output=ash_factor_raw_output,
        ash_combined_raw_output=ash_combined_raw_output,
        ash_factor_output=ash_factor_output,
        mix_ground_ash=mix_ground_ash,
        normal_mix_ground_ash=normal_mix_ground_ash,
        rough_mix_ground_ash=rough_mix_ground_ash,
    )
    _assert_final_pbr_blend_order(
        mix_ground_ash=mix_ground_ash,
        mix_stone=mix_stone,
    )
    _assert_stone_pbr_splat_weights(
        mix_stone=mix_stone,
        normal_mix_stone=normal_mix_stone,
        rough_mix_stone=rough_mix_stone,
        stone_factor_output=stone_factor_output,
        ground_normal_map=ground_normal_map,
        stone_normal_map=stone_normal_map,
    )

    if DEBUG_MATERIAL_STAGE not in {
        "ash_albedo_raw",
        "ash_albedo_diffuse",
        "ash_mask_raw",
        "ash_breakup_raw",
        "ash_mask_combined_raw",
        "ash_mask_remapped_raw",
    }:
        _apply_debug_pbr_surface_overrides(
            links,
            principled,
            DEBUG_MATERIAL_STAGE,
            ground_roughness_output=ground_roughness_final,
            ground_ash_roughness_output=ground_ash_roughness_output,
            ground_stone_roughness_output=ground_stone_roughness_output,
            mixed_roughness_output=mixed_roughness_output,
            ground_normal_map=ground_normal_map,
            ash_normal_map=ash_normal_map,
            stone_normal_map=stone_normal_map,
            ground_ash_normal_output=ground_ash_normal_output,
            ground_stone_normal_output=ground_stone_normal_output,
            blended_normal_output=blended_normal_output,
            combined_normal_output=combined_normal_output,
            bump=bump,
            debug_neutral_roughness=debug_neutral_roughness,
        )

    _assert_debug_stage_routing_coverage()
    _assert_diagnostic_diffuse_principled_configuration(diag_diffuse_principled)

    _apply_debug_material_output_link(
        links,
        out,
        DEBUG_MATERIAL_STAGE,
        principled=principled,
        diag_raw_emission=diag_raw_emission,
        diag_diffuse_principled=diag_diffuse_principled,
        diag_mask_emission=diag_mask_emission,
        diag_breakup_emission=diag_breakup_emission,
        diag_combined_emission=diag_combined_emission,
        diag_mask_remapped_emission=diag_mask_remapped_emission,
    )
    _assert_ash_brightness_diagnostic_routing(
        links,
        DEBUG_MATERIAL_STAGE,
        out,
        diag_raw_emission=diag_raw_emission,
        diag_diffuse_principled=diag_diffuse_principled,
        diag_mask_emission=diag_mask_emission,
        diag_mask_grayscale=diag_mask_grayscale,
        diag_breakup_emission=diag_breakup_emission,
        diag_breakup_grayscale=diag_breakup_grayscale,
        diag_combined_emission=diag_combined_emission,
        diag_combined_grayscale=diag_combined_grayscale,
        diag_mask_remapped_emission=diag_mask_remapped_emission,
        diag_mask_remapped_grayscale=diag_mask_remapped_grayscale,
        ash_factor_raw_output=ash_factor_raw_output,
        ash_breakup_factor_output=ash_breakup_factor_output,
        ash_combined_raw_output=ash_combined_raw_output,
        ash_factor_output=ash_factor_output,
    )
    return mat


def make_side_terrain_material() -> bpy.types.Material:
    """Flat dark earth/stone for skirt, chamfer, and bottom — avoids slope halo at rim."""
    mat = bpy.data.materials.get(SIDE_MATERIAL_NAME)
    if mat is not None:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(SIDE_MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {SIDE_MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    out = _new_node(nodes, "ShaderNodeOutputMaterial")
    out.location = (400, 0)

    principled = _new_node(nodes, "ShaderNodeBsdfPrincipled")
    principled.location = (100, 0)
    _require_input(principled, "Base Color").default_value = (0.09, 0.10, 0.09, 1.0)
    _require_input(principled, "Roughness").default_value = 0.92

    links.new(_require_output(principled, "BSDF"), _require_input(out, "Surface"))
    return mat


def _assert_ground_uv_map_layer(uv_map_node: bpy.types.Node, expected_layer_name: str) -> None:
    if uv_map_node.bl_idname != "ShaderNodeUVMap":
        raise RuntimeError(
            f"ground PBR UV source must be ShaderNodeUVMap, got {uv_map_node.bl_idname!r}"
        )
    if uv_map_node.uv_map != expected_layer_name:
        raise RuntimeError(
            f"UV Map node references {uv_map_node.uv_map!r}, expected {expected_layer_name!r}"
        )


def _assert_shared_pbr_uv_chain(
    nodes: bpy.types.Nodes,
    ground_mapping_node: bpy.types.Node,
    texture_nodes: tuple[tuple[str, bpy.types.Node], ...],
    *,
    expected_layer_name: str,
) -> None:
    """Fail-fast: fixed PBR chain is UV Map -> Mapping -> all ground/stone image textures."""
    uv_map_nodes = [node for node in nodes if node.bl_idname == "ShaderNodeUVMap"]
    if len(uv_map_nodes) != 1:
        raise RuntimeError(
            f"expected exactly one ShaderNodeUVMap for PBR textures, found {len(uv_map_nodes)}"
        )
    uv_map_node = uv_map_nodes[0]
    _assert_ground_uv_map_layer(uv_map_node, expected_layer_name)

    if ground_mapping_node.bl_idname != "ShaderNodeMapping":
        raise RuntimeError(
            "shared PBR mapping node must be ShaderNodeMapping, "
            f"got {ground_mapping_node.bl_idname!r}"
        )

    mapping_vector_in = _require_input(ground_mapping_node, "Vector")
    if not mapping_vector_in.is_linked:
        raise RuntimeError("ground UV Mapping Vector input is not linked")
    mapping_in_link = mapping_vector_in.links[0]
    if mapping_in_link.from_node.bl_idname != "ShaderNodeUVMap":
        raise RuntimeError("ground UV Mapping must be fed directly by a ShaderNodeUVMap")
    if mapping_in_link.from_node.name != uv_map_node.name:
        raise RuntimeError(
            "ground UV Mapping must be fed by the sole UV Map node "
            f"{uv_map_node.name!r}, got {mapping_in_link.from_node.name!r}"
        )
    if mapping_in_link.from_socket.name != "UV":
        raise RuntimeError(
            "ground UV Mapping must be fed by the UV Map UV output, "
            f"got {mapping_in_link.from_socket.name!r}"
        )

    mapping_node_name = ground_mapping_node.name
    for label, tex_node in texture_nodes:
        vector_in = _require_input(tex_node, "Vector")
        if not vector_in.is_linked:
            raise RuntimeError(f"{label} texture Vector input is not linked")
        link = vector_in.links[0]
        if link.from_node.bl_idname != "ShaderNodeMapping":
            raise RuntimeError(f"{label} texture must be fed directly by a Mapping node")
        if link.from_node.name != mapping_node_name:
            raise RuntimeError(
                f"{label} texture must be fed by ground UV Mapping "
                f"{mapping_node_name!r}, got {link.from_node.name!r}"
            )
        if link.from_socket.name != "Vector":
            raise RuntimeError(
                f"{label} texture must use Mapping Vector output, "
                f"got {link.from_socket.name!r}"
            )

    uv_map_label = uv_map_node.label.strip() if uv_map_node.label else uv_map_node.name
    mapping_label = (
        ground_mapping_node.label.strip()
        if ground_mapping_node.label
        else ground_mapping_node.name
    )
    _log(f"UV Map node={uv_map_label} layer={expected_layer_name}")
    _log(f"Mapping node={mapping_label}")
    _log("shared by ground, ash, and stone albedo, normal, roughness")


def _assert_final_pbr_blend_order(
    *,
    mix_ground_ash: ColorMixSockets,
    mix_stone: ColorMixSockets,
) -> None:
    stone_color1 = mix_stone.color1
    if not stone_color1.is_linked:
        raise RuntimeError("mix_stone color1 must be linked for ground/ash then stone blend order")
    stone_color1_source = (
        stone_color1.links[0].from_node.name,
        stone_color1.links[0].from_socket.name,
    )
    expected_ground_ash_output = (mix_ground_ash.node.name, mix_ground_ash.output.name)
    if stone_color1_source != expected_ground_ash_output:
        raise RuntimeError(
            "final blend order must be ground/ash first then stone: "
            f"mix_stone color1 must use {expected_ground_ash_output[0]}.{expected_ground_ash_output[1]}, "
            f"got {stone_color1_source[0]}.{stone_color1_source[1]}"
        )


def _assert_ash_pbr_splat_weights(
    *,
    mix_ground_ash: ColorMixSockets,
    normal_mix_ground_ash: bpy.types.Node,
    rough_mix_ground_ash: bpy.types.Node,
    ash_factor_output: bpy.types.NodeSocket | None,
    ash_normal_map: bpy.types.Node,
) -> None:
    if ash_normal_map.space != "TANGENT":
        raise RuntimeError("ash Normal Map must use tangent space")
    if not USE_LARGE_SCALE_VARIATION or ash_factor_output is None:
        return

    expected_source = (
        ash_factor_output.node.name,
        ash_factor_output.name,
    )
    for label, socket in (
        ("mix_ground_ash", mix_ground_ash.factor),
        ("normal_mix_ground_ash", _require_input(normal_mix_ground_ash, "Factor")),
        ("rough_mix_ground_ash", _require_input(rough_mix_ground_ash, "Factor")),
    ):
        source = _linked_mix_factor_source(socket)
        if source != expected_source:
            raise RuntimeError(
                f"{label} does not use the existing ash weight from "
                f"{expected_source[0]}.{expected_source[1]}, got {source[0]}.{source[1]}"
            )


def _linked_mix_factor_source(socket: bpy.types.NodeSocket) -> tuple[str, str]:
    if not socket.is_linked:
        raise RuntimeError("expected stone splat factor socket to be linked")
    link = socket.links[0]
    return link.from_node.name, link.from_socket.name


def _assert_stone_pbr_splat_weights(
    *,
    mix_stone: ColorMixSockets,
    normal_mix_stone: bpy.types.Node,
    rough_mix_stone: bpy.types.Node,
    stone_factor_output: bpy.types.NodeSocket,
    ground_normal_map: bpy.types.Node,
    stone_normal_map: bpy.types.Node,
) -> None:
    if stone_normal_map.space != "TANGENT":
        raise RuntimeError("stone Normal Map must use tangent space")
    if ground_normal_map.space != "TANGENT":
        raise RuntimeError("ground Normal Map must use tangent space")

    expected_source = (
        stone_factor_output.node.name,
        stone_factor_output.name,
    )
    for label, socket in (
        ("mix_stone", mix_stone.factor),
        ("normal_mix_stone", _require_input(normal_mix_stone, "Factor")),
        ("rough_mix_stone", _require_input(rough_mix_stone, "Factor")),
    ):
        source = _linked_mix_factor_source(socket)
        if source != expected_source:
            raise RuntimeError(
                f"{label} does not use the final stone weight from "
                f"{expected_source[0]}.{expected_source[1]}, got {source[0]}.{source[1]}"
            )


def assign_world_anchored_top_uv(
    mesh: bpy.types.Mesh,
    top_face_count: int,
    *,
    scale: float = WORLD_UV_SCALE,
    layer_name: str = WORLD_UV_LAYER_NAME,
) -> dict[str, float | int | tuple[float, float, float, float]]:
    """Assign planar world/object XY UV to top-face loops only (no per-patch normalization)."""
    if top_face_count <= 0:
        raise RuntimeError("no top faces for world UV assignment")
    if scale <= 0.0:
        raise ValueError(f"UV scale must be > 0, got {scale!r}")

    # Top faces use world-anchored planar XY UV.
    # Cliff/side surfaces require a separate projection/material strategy in later work.
    existing = mesh.uv_layers.get(layer_name)
    if existing is not None:
        mesh.uv_layers.remove(existing)
    uv_layer = mesh.uv_layers.new(name=layer_name)
    if mesh.uv_layers.get(layer_name) is None:
        raise RuntimeError(f"UV layer {layer_name!r} missing immediately after creation")
    mesh.uv_layers.active = uv_layer
    layer_index = mesh.uv_layers.find(layer_name)
    if layer_index < 0:
        raise RuntimeError(f"UV layer {layer_name!r} not found in mesh.uv_layers")
    mesh.uv_layers.active_index = layer_index

    top_loop_count = 0
    u_values: list[float] = []
    v_values: list[float] = []
    vert_uv: dict[int, tuple[float, float]] = {}
    uv_tolerance = max(WORLD_XY_TOLERANCE * scale, 1e-6)

    for poly in mesh.polygons:
        if poly.index >= top_face_count:
            continue
        for loop_idx in range(poly.loop_start, poly.loop_start + poly.loop_total):
            vert_idx = mesh.loops[loop_idx].vertex_index
            co = mesh.vertices[vert_idx].co
            u = co.x * scale
            v = co.y * scale
            if not (math.isfinite(u) and math.isfinite(v)):
                raise RuntimeError(
                    f"non-finite UV at top loop {loop_idx} vert {vert_idx}: ({u}, {v})"
                )
            expected_u = co.x * scale
            expected_v = co.y * scale
            if abs(u - expected_u) > uv_tolerance or abs(v - expected_v) > uv_tolerance:
                raise RuntimeError(
                    f"UV at loop {loop_idx} does not match position*scale formula"
                )
            uv_layer.data[loop_idx].uv = (u, v)
            top_loop_count += 1
            u_values.append(u)
            v_values.append(v)
            if vert_idx in vert_uv:
                prev_u, prev_v = vert_uv[vert_idx]
                if abs(prev_u - u) > uv_tolerance or abs(prev_v - v) > uv_tolerance:
                    raise RuntimeError(
                        f"top vertex {vert_idx} UV mismatch across loops: "
                        f"({prev_u}, {prev_v}) vs ({u}, {v})"
                    )
            else:
                vert_uv[vert_idx] = (u, v)

    if top_loop_count <= 0:
        raise RuntimeError("world UV assignment found no top-face loops")

    mesh.update()
    try:
        mesh.calc_tangents(uvmap=layer_name)
    except Exception as exc:
        raise RuntimeError(
            f"mesh.calc_tangents failed for uvmap {layer_name!r}: {exc}"
        ) from exc

    u_min = min(u_values)
    u_max = max(u_values)
    v_min = min(v_values)
    v_max = max(v_values)

    validate_world_anchored_top_uv(
        mesh,
        top_face_count,
        scale=scale,
        layer_name=layer_name,
        uv_bounds=(u_min, u_max, v_min, v_max),
        top_loop_count=top_loop_count,
        vert_uv=vert_uv,
        uv_tolerance=uv_tolerance,
    )

    shared_samples = _sample_shared_top_vertex_uv(mesh, top_face_count, vert_uv, limit=4)
    _log(f"uv_layer={layer_name}")
    _log(f"scale={scale}")
    _log(f"top_loops={top_loop_count}")
    _log(f"uv_bounds=({u_min:.6f}, {u_max:.6f}, {v_min:.6f}, {v_max:.6f})")
    _log("source=world/object XY, not patch-normalized")
    _log("tangent-space normal enabled")
    for vert_idx, uv_pair, loop_count in shared_samples:
        _log(
            f"shared_top_vert={vert_idx} loops={loop_count} uv=({uv_pair[0]:.6f}, {uv_pair[1]:.6f})"
        )

    return {
        "top_loops": top_loop_count,
        "u_min": u_min,
        "u_max": u_max,
        "v_min": v_min,
        "v_max": v_max,
    }


def _sample_shared_top_vertex_uv(
    mesh: bpy.types.Mesh,
    top_face_count: int,
    vert_uv: dict[int, tuple[float, float]],
    *,
    limit: int = 4,
) -> list[tuple[int, tuple[float, float], int]]:
    """Return vertices that appear on multiple top loops (for continuity diagnostics)."""
    loop_hits: dict[int, int] = {}
    for poly in mesh.polygons:
        if poly.index >= top_face_count:
            continue
        for loop_idx in range(poly.loop_start, poly.loop_start + poly.loop_total):
            vert_idx = mesh.loops[loop_idx].vertex_index
            loop_hits[vert_idx] = loop_hits.get(vert_idx, 0) + 1
    shared = [
        (vert_idx, vert_uv[vert_idx], loop_hits[vert_idx])
        for vert_idx in sorted(loop_hits)
        if loop_hits[vert_idx] > 1 and vert_idx in vert_uv
    ]
    return shared[:limit]


def validate_world_anchored_top_uv(
    mesh: bpy.types.Mesh,
    top_face_count: int,
    *,
    scale: float,
    layer_name: str,
    uv_bounds: tuple[float, float, float, float],
    top_loop_count: int,
    vert_uv: dict[int, tuple[float, float]],
    uv_tolerance: float,
) -> None:
    if mesh.uv_layers.get(layer_name) is None:
        raise RuntimeError(f"UV layer {layer_name!r} missing after assignment")
    uv_layer = mesh.uv_layers[layer_name]
    active_layer = mesh.uv_layers.active
    if active_layer is None or active_layer.name != layer_name:
        layer_index = mesh.uv_layers.find(layer_name)
        if layer_index < 0:
            raise RuntimeError(f"UV layer {layer_name!r} not found for active assignment")
        mesh.uv_layers.active_index = layer_index
        active_layer = mesh.uv_layers.active
    if active_layer is None or active_layer.name != layer_name:
        raise RuntimeError(f"active UV layer is not {layer_name!r}")

    u_min, u_max, v_min, v_max = uv_bounds
    if not all(math.isfinite(value) for value in uv_bounds):
        raise RuntimeError(f"non-finite UV bounds: {uv_bounds}")

    # Reject per-patch 0–1 bounds normalization when mesh XY extent exceeds UV span.
    xs = [mesh.vertices[i].co.x for i in vert_uv]
    ys = [mesh.vertices[i].co.y for i in vert_uv]
    expected_u_span = (max(xs) - min(xs)) * scale
    expected_v_span = (max(ys) - min(ys)) * scale
    actual_u_span = u_max - u_min
    actual_v_span = v_max - v_min
    if expected_u_span > uv_tolerance and abs(actual_u_span - expected_u_span) > uv_tolerance:
        raise RuntimeError(
            "top UV U span does not match object XY span * scale (possible normalization)"
        )
    if expected_v_span > uv_tolerance and abs(actual_v_span - expected_v_span) > uv_tolerance:
        raise RuntimeError(
            "top UV V span does not match object XY span * scale (possible normalization)"
        )

    normalized_patch_bounds = (
        abs(u_min) < uv_tolerance
        and abs(v_min) < uv_tolerance
        and abs(u_max - 1.0) < uv_tolerance
        and abs(v_max - 1.0) < uv_tolerance
        and expected_u_span > 1.0 + uv_tolerance
    )
    if normalized_patch_bounds:
        raise RuntimeError(
            "top UV appears patch-normalized to [0,1] while mesh XY extent is larger"
        )

    checked_loops = 0
    for poly in mesh.polygons:
        if poly.index >= top_face_count:
            continue
        for loop_idx in range(poly.loop_start, poly.loop_start + poly.loop_total):
            uv = uv_layer.data[loop_idx].uv
            if not (math.isfinite(uv[0]) and math.isfinite(uv[1])):
                raise RuntimeError(f"non-finite stored UV at loop {loop_idx}: {uv}")
            vert_idx = mesh.loops[loop_idx].vertex_index
            co = mesh.vertices[vert_idx].co
            if abs(uv[0] - co.x * scale) > uv_tolerance or abs(uv[1] - co.y * scale) > uv_tolerance:
                raise RuntimeError(
                    f"loop {loop_idx} UV ({uv[0]}, {uv[1]}) != position*scale "
                    f"({co.x * scale}, {co.y * scale})"
                )
            checked_loops += 1
    if checked_loops != top_loop_count:
        raise RuntimeError(
            f"top loop UV check count mismatch: {checked_loops} vs {top_loop_count}"
        )


def assign_patch_materials(
    mesh: bpy.types.Mesh,
    top_face_count: int,
    procedural_material: bpy.types.Material,
    side_material: bpy.types.Material,
) -> tuple[int, int]:
    """Slot 0 = procedural top; slot 1 = skirt/chamfer/bottom."""
    if top_face_count <= 0:
        raise RuntimeError("no top faces found for material assignment")
    if top_face_count >= len(mesh.polygons):
        raise RuntimeError("no side/bottom faces found for material assignment")

    mesh.materials.clear()
    mesh.materials.append(procedural_material)
    mesh.materials.append(side_material)

    top_assigned = 0
    side_assigned = 0
    for polygon in mesh.polygons:
        if polygon.index < top_face_count:
            polygon.material_index = 0
            top_assigned += 1
        else:
            polygon.material_index = 1
            side_assigned += 1

    if top_assigned <= 0:
        raise RuntimeError("material assignment found no top faces")
    if side_assigned <= 0:
        raise RuntimeError("material assignment found no side/bottom faces")

    _log(f"Material assigned to top faces: {top_assigned}")
    _log(f"Side material assigned to side faces: {side_assigned}")
    return top_assigned, side_assigned


def _log_material_setup() -> None:
    _log("PBR ground + ash + stone material created")
    _log(f"World UV layer: {WORLD_UV_LAYER_NAME}")
    _log(f"World UV scale: {WORLD_UV_SCALE} (U/V = object X/Y * scale)")
    _log(f"Ground albedo tint strength: {GROUND_ALBEDO_TINT_STRENGTH}")
    _log(f"Ground normal strength: {GROUND_NORMAL_STRENGTH}")
    _log(f"Ash normal strength: {ASH_NORMAL_STRENGTH}")
    _log(f"Stone normal strength: {STONE_NORMAL_STRENGTH}")
    _log(f"Stone albedo multiplier: {STONE_ALBEDO_MULTIPLIER}")
    _log(
        "UV chain: ShaderNodeUVMap -> Ground UV Mapping -> "
        "ground/ash/stone PBR textures"
    )
    _log("Ash splat: existing ash weight drives albedo, normal, and roughness")
    _log("Stone splat: existing final stone weight applied after ground/ash blend")
    _log(f"Slope blend: {'enabled' if USE_SLOPE_BLEND else 'disabled'}")
    _log(f"Stone breakup: {'enabled' if USE_STONE_BREAKUP else 'disabled'}")
    _log(f"Large-scale variation: {'enabled' if USE_LARGE_SCALE_VARIATION else 'disabled'}")
    _log(f"Fine detail: {'enabled' if USE_FINE_DETAIL else 'disabled'}")
    _log(f"Roughness variation: {'enabled' if USE_ROUGHNESS_VARIATION else 'disabled'}")
    _log(f"Procedural bump: {'enabled' if USE_PROCEDURAL_BUMP else 'disabled'}")
    _log(f"Coordinate source: {MATERIAL_COORD_SOURCE}")
    _log(f"Slope thresholds: start={SLOPE_BLEND_START}, end={SLOPE_BLEND_END}")
    _log(f"Stone breakup strength: {STONE_BREAKUP_STRENGTH}")
    _log(f"Bump strength: {BUMP_STRENGTH}")


def make_overlay_material() -> bpy.types.Material:
    mat = bpy.data.materials.get(OVERLAY_MATERIAL_NAME)
    if mat is not None:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(OVERLAY_MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {OVERLAY_MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    out = _new_node(nodes, "ShaderNodeOutputMaterial")
    out.location = (300, 0)

    emission = _new_node(nodes, "ShaderNodeEmission")
    emission.location = (0, 0)
    _require_input(emission, "Color").default_value = (0.05, 0.06, 0.08, 1.0)
    _require_input(emission, "Strength").default_value = 1.2

    links.new(_require_output(emission, "Emission"), _require_input(out, "Surface"))
    return mat


def apply_patch_shading(
    mesh: bpy.types.Mesh,
    top_face_count: int,
    side_face_count: int,
) -> int:
    """Smooth top; flat skirt/chamfer/bottom; sharp edges at top-to-side boundary."""
    if top_face_count <= 0:
        raise RuntimeError("no top faces found for shading setup")
    if side_face_count <= 0:
        raise RuntimeError("no side/skirt faces found for shading setup")

    top_indices = set(range(top_face_count))
    side_indices = set(range(top_face_count, top_face_count + side_face_count))

    for polygon in mesh.polygons:
        if polygon.index in top_indices:
            polygon.use_smooth = True
        else:
            polygon.use_smooth = False

    edge_face_members: dict[tuple[int, int], set[int]] = {}
    for polygon in mesh.polygons:
        vert_count = len(polygon.vertices)
        for i in range(vert_count):
            v1 = polygon.vertices[i]
            v2 = polygon.vertices[(i + 1) % vert_count]
            edge_key = (v1, v2) if v1 < v2 else (v2, v1)
            edge_face_members.setdefault(edge_key, set()).add(polygon.index)

    edge_key_to_index: dict[tuple[int, int], int] = {}
    for edge in mesh.edges:
        v1, v2 = edge.vertices[0], edge.vertices[1]
        edge_key = (v1, v2) if v1 < v2 else (v2, v1)
        edge_key_to_index[edge_key] = edge.index

    sharp_count = 0
    for edge_key, face_members in edge_face_members.items():
        top_hits = face_members & top_indices
        side_hits = face_members & side_indices
        if len(top_hits) == 1 and len(side_hits) == 1:
            edge_index = edge_key_to_index.get(edge_key)
            if edge_index is None:
                raise RuntimeError(f"missing mesh edge for top/skirt boundary: {edge_key}")
            mesh.edges[edge_index].use_edge_sharp = True
            sharp_count += 1

    if sharp_count <= 0:
        raise RuntimeError("no top/skirt boundary edges found for sharp shading")

    _log(f"Top faces smooth: {top_face_count}")
    _log(f"Side faces flat: {side_face_count}")
    _log(f"Top/skirt sharp edges: {sharp_count}")
    return sharp_count


def build_single_patch_mesh(hex_coords: set[tuple[int, int]]) -> tuple[bpy.types.Mesh, dict]:
    subdiv = SURFACE_SUBDIVISIONS
    bottom_z = -BASE_THICKNESS

    verts: list[tuple[float, float, float]] = []
    top_faces: list[tuple[int, int, int]] = []
    top_cache: dict[tuple[float, float], int] = {}
    sector_grids: dict[tuple[int, int, int], dict[tuple[int, int], int]] = {}
    face_keys: set[tuple[int, int, int]] = set()

    def add_top_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = top_cache.get(key)
        if cached is not None:
            return cached
        wz = sample_radial_height(wx, wy)
        idx = len(verts)
        verts.append((wx, wy, wz))
        top_cache[key] = idx
        return idx

    # Strategy B: merged sector grids with global world-space vertex cache.
    for q, r, _level, _label in PROTOTYPE_HEXES:
        cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
        for sector in range(6):
            grid: dict[tuple[int, int], int] = {}
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = sector_barycentric_xy(sector, si, sj, subdiv)
                    grid[(si, sj)] = add_top_vertex(cx + lx, cy + ly)
                    sj += 1
            sector_grids[(q, r, sector)] = grid

            for si in range(subdiv):
                sj = 0
                while sj <= subdiv - si - 1:
                    v00 = grid[(si, sj)]
                    v10 = grid[(si + 1, sj)]
                    v01 = grid[(si, sj + 1)]
                    wound = orient_upward_triangle(verts, v00, v10, v01)
                    key = tuple(sorted(wound))
                    if key not in face_keys:
                        face_keys.add(key)
                        top_faces.append(wound)
                    if sj + 1 <= subdiv - (si + 1):
                        v11 = grid[(si + 1, sj + 1)]
                        wound = orient_upward_triangle(verts, v10, v01, v11)
                        key = tuple(sorted(wound))
                        if key not in face_keys:
                            face_keys.add(key)
                            top_faces.append(wound)
                    sj += 1

    validate_top_face_winding(verts, top_faces)

    perimeter_segments: list[list[int]] = []
    segment_edge_t: list[list[float]] = []
    for q, r, _level, _label in PROTOTYPE_HEXES:
        for edge_index in range(6):
            if not is_exposed_patch_edge(q, r, edge_index, hex_coords):
                continue
            grid = sector_grids[(q, r, edge_index)]
            indices = outer_edge_grid_indices(grid, subdiv)
            edge_ts = [float(step_k) / float(subdiv) for step_k in range(subdiv + 1)]
            perimeter_segments.append(indices)
            segment_edge_t.append(edge_ts)

    perimeter_loop = chain_perimeter_segments(perimeter_segments)
    _log(f"perimeter validation passed: {len(perimeter_loop)} ordered top vertices")

    bottom_cache: dict[tuple[float, float], int] = {}
    rim_cache: dict[tuple[float, float], int] = {}
    skirt_faces: list[tuple[int, ...]] = []
    chamfer_faces: list[tuple[int, ...]] = []

    def add_bottom_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = bottom_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, bottom_z))
        bottom_cache[key] = idx
        return idx

    def add_rim_vertex(wx: float, wy: float, top_z: float, edge_t: float) -> int:
        key = pos_key(wx, wy)
        cached = rim_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, compute_rim_z(top_z, edge_t)))
        rim_cache[key] = idx
        return idx

    # Map top index -> edge_t along perimeter for rim profile continuity.
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

        if OUTER_RIM_DROP > 0.0 and rim_a != top_a:
            chamfer_faces.append((top_a, top_b, rim_b, rim_a))
            skirt_faces.append((rim_a, rim_b, bot_b, bot_a))
        else:
            skirt_faces.append((top_a, top_b, bot_b, bot_a))

    patch_cx = sum(axial_to_world_xy(q, r, HEX_RADIUS)[0] for q, r, _, _ in PROTOTYPE_HEXES) / 7.0
    patch_cy = sum(axial_to_world_xy(q, r, HEX_RADIUS)[1] for q, r, _, _ in PROTOTYPE_HEXES) / 7.0
    center_bottom = len(verts)
    verts.append((patch_cx, patch_cy, bottom_z))

    bottom_faces: list[tuple[int, int, int]] = []
    for i in range(loop_count):
        bot_a = bottom_cache[pos_key(verts[perimeter_loop[i]][0], verts[perimeter_loop[i]][1])]
        bot_b = bottom_cache[pos_key(verts[perimeter_loop[(i + 1) % loop_count]][0], verts[perimeter_loop[(i + 1) % loop_count]][1])]
        bottom_faces.append((center_bottom, bot_b, bot_a))

    top_face_count = len(top_faces)
    side_face_count = len(skirt_faces) + len(chamfer_faces)
    bottom_face_count = len(bottom_faces)
    all_faces = top_faces + skirt_faces + chamfer_faces + bottom_faces

    for face in all_faces:
        assert len(set(face)) == len(face), f"degenerate face: {face}"

    mesh = bpy.data.meshes.new("SinglePatchTerrain")
    mesh.from_pydata(verts, [], all_faces)
    apply_patch_shading(mesh, top_face_count, side_face_count)
    _finalize_mesh(mesh)

    stats = {
        "top_verts": len(top_cache),
        "top_faces": top_face_count,
        "side_faces": side_face_count,
        "bottom_faces": bottom_face_count,
        "perimeter_verts": len(perimeter_loop),
        "skirt_faces": len(skirt_faces),
        "chamfer_faces": len(chamfer_faces),
        "total_verts": len(verts),
        "total_faces": len(all_faces),
    }
    return mesh, stats


def build_hex_overlay_mesh() -> tuple[bpy.types.Mesh, dict]:
    subdiv = SURFACE_SUBDIVISIONS
    seen_edges: set[tuple[tuple[float, float], tuple[float, float]]] = set()
    verts: list[tuple[float, float, float]] = []
    edges: list[tuple[int, int]] = []
    vert_cache: dict[tuple[float, float], int] = {}

    def add_overlay_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = vert_cache.get(key)
        if cached is not None:
            return cached
        wz = sample_radial_height(wx, wy) + HEX_OVERLAY_HEIGHT_OFFSET
        idx = len(verts)
        verts.append((wx, wy, wz))
        vert_cache[key] = idx
        return idx

    for q, r, _level, _label in PROTOTYPE_HEXES:
        cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
        for edge_index in range(6):
            edge_key = unique_edge_key(q, r, edge_index)
            if edge_key in seen_edges:
                continue
            seen_edges.add(edge_key)

            ci = edge_index
            cj = (edge_index + 1) % 6
            bx, by = corner_xy_local(ci, HEX_RADIUS)
            cx_corner, cy_corner = corner_xy_local(cj, HEX_RADIUS)
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
    _finalize_mesh(mesh)
    return mesh, {"unique_edges": len(seen_edges), "overlay_verts": len(verts), "overlay_edges": len(edges)}


def setup_camera_and_lights() -> None:
    scene = _active_scene()
    cam_data = bpy.data.cameras.new(CAMERA_NAME)
    cam_obj = bpy.data.objects.new(CAMERA_NAME, cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    cam_obj.location = Vector((0.0, -7.5, 5.8))
    cam_obj.rotation_euler = (math.radians(58.0), 0.0, 0.0)

    sun_data = bpy.data.lights.new(SUN_NAME, type="SUN")
    sun_data.energy = 2.2
    sun_obj = bpy.data.objects.new(SUN_NAME, sun_data)
    sun_obj.location = Vector((4.0, -3.0, 8.0))
    sun_obj.rotation_euler = (math.radians(45.0), math.radians(10.0), math.radians(25.0))
    scene.collection.objects.link(sun_obj)

    area_data = bpy.data.lights.new("PrototypeFill", type="AREA")
    area_data.energy = 120.0
    area_data.size = 6.0
    area_obj = bpy.data.objects.new("PrototypeFill", area_data)
    area_obj.location = Vector((-3.0, 2.0, 4.0))
    scene.collection.objects.link(area_obj)
    _log("camera and lights created")


def setup_render_and_world() -> None:
    scene = _active_scene()
    engine_prefs = ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE")
    chosen_engine: str | None = None
    for engine in engine_prefs:
        try:
            scene.render.engine = engine
            chosen_engine = engine
            break
        except (TypeError, ValueError):
            continue
    if chosen_engine is None:
        _log(f"warning: could not set Eevee; keeping render engine {scene.render.engine!r}")
    else:
        _log(f"render engine: {chosen_engine}")

    world = bpy.data.worlds.get("EOM_Terrain_World")
    if world is None:
        world = bpy.data.worlds.new("EOM_Terrain_World")
    scene.world = world
    world.use_nodes = True
    world_tree = world.node_tree
    if world_tree is None:
        raise RuntimeError("EOM_Terrain_World has no node tree")

    bg = world_tree.nodes.get("Background")
    if bg is None:
        for node in world_tree.nodes:
            if node.bl_idname == "ShaderNodeBackground":
                bg = node
                break
    if bg is None:
        raise RuntimeError("world node tree missing Background node")

    color_in = bg.inputs.get("Color")
    strength_in = bg.inputs.get("Strength")
    if color_in is None or strength_in is None:
        raise KeyError("Background node missing Color and/or Strength inputs")
    color_in.default_value = (0.04, 0.045, 0.05, 1.0)
    strength_in.default_value = 0.35
    _log("world background configured")


def save_outputs() -> None:
    if OUTPUT_DIR is None or OUTPUT_BLEND_PATH is None or OUTPUT_GLB_PATH is None:
        raise RuntimeError("output paths not resolved; call resolve_output_paths() first")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    override = _ops_context_override()
    blend_str = str(OUTPUT_BLEND_PATH)
    glb_str = str(OUTPUT_GLB_PATH)
    if SAVE_BLEND:
        with bpy.context.temp_override(**override):
            bpy.ops.wm.save_as_mainfile(filepath=blend_str)
        _log(f"saved blend: {blend_str}")
    if EXPORT_GLB:
        with bpy.context.temp_override(**override):
            bpy.ops.export_scene.gltf(
                filepath=glb_str,
                export_format="GLB",
                use_selection=False,
            )
        _log(f"exported GLB: {glb_str}")


def main() -> None:
    validate_params()
    validate_material_params()
    repo_root, _output_dir, _blend_path, _glb_path = resolve_output_paths()
    ground_albedo_path, ground_normal_path, ground_roughness_path = resolve_ground_texture_paths(
        repo_root
    )
    stone_albedo_path, stone_normal_path, stone_roughness_path = resolve_stone_texture_paths(
        repo_root
    )
    ash_albedo_path, ash_normal_path, ash_roughness_path = resolve_ash_texture_paths(repo_root)
    hill_cx, hill_cy = hill_center_xy()
    _log(f"Blender version: {_blender_version_label()}")
    _log("generating 7-hex single-patch PBR ground + stone + ash prototype…")
    _log(f"surface subdivisions: {SURFACE_SUBDIVISIONS}")
    _log(f"hill profile: {HILL_PROFILE}")
    _log(f"hill center: ({hill_cx:.4f}, {hill_cy:.4f}) axial ({HILL_AXIAL_Q},{HILL_AXIAL_R})")
    _log(f"hill radius: {HILL_RADIUS:.4f}")
    _log(f"hill height: {HILL_HEIGHT:.4f}")

    validate_radial_symmetry()

    clear_scene()
    coll = ensure_collection(COLLECTION_NAME)
    hex_coords = build_hex_coords_set()

    procedural_material = make_pbr_ground_stone_ash_terrain_material(
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
    side_material = make_side_terrain_material()
    _log_material_setup()

    terrain_mesh, stats = build_single_patch_mesh(hex_coords)
    assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    assign_patch_materials(
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
    _log(f"perimeter vertices: {stats['perimeter_verts']}")
    _log(f"skirt faces: {stats['skirt_faces']}")
    _log(f"chamfer faces: {stats['chamfer_faces']}")
    _log(f"total vertices: {stats['total_verts']}")
    _log(f"total faces: {stats['total_faces']}")

    if CREATE_HEX_OVERLAY:
        overlay_material = make_overlay_material()
        overlay_mesh, overlay_stats = build_hex_overlay_mesh()
        overlay_obj = bpy.data.objects.new(OVERLAY_OBJECT_NAME, overlay_mesh)
        overlay_obj.data.materials.append(overlay_material)
        coll.objects.link(overlay_obj)
        _log("overlay created")
        _log(f"unique overlay edges: {overlay_stats['unique_edges']}")
        _log(f"overlay vertices: {overlay_stats['overlay_verts']}")
        _log(f"overlay edge segments: {overlay_stats['overlay_edges']}")

    setup_camera_and_lights()
    setup_render_and_world()
    _log_ash_brightness_audit(
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
    save_outputs()
    _log("done")


if __name__ == "__main__":
    main()
