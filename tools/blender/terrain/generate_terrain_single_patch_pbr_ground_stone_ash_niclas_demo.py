# Empire of Minds — Niclas idle/kick demo on approved Blender porting terrain baseline.
# Run from Blender Scripting workspace: Open → Run Script.
# Requires bpy (not available outside Blender).
#
# Visual demo only: places Niclas on the locked 7-hex terrain baseline and loops
# Idle_3 → Flying_Fist_Kick with preserved kick root motion.
# Does not modify the terrain baseline script, materials, or Godot gameplay code.

import importlib.util
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Demo parameters
# ---------------------------------------------------------------------------

NICLAS_IDLE_DURATION_SECONDS = 2.5
NICLAS_START_HEIGHT_OFFSET = 0.0
NICLAS_RESET_FRAMES = 2

NICLAS_IDLE_ACTION_NAME = "Idle_3"
NICLAS_KICK_ACTION_NAME = "Flying_Fist_Kick"
NICLAS_RESET_ACTION_NAME = "EOM_Niclas_Reset"

# West outer hex with center (0,0) between it and hill hex (1,0).
NICLAS_START_HEX_Q = -1
NICLAS_START_HEX_R = 0
NICLAS_FACE_NEIGHBOR_Q = 0
NICLAS_FACE_NEIGHBOR_R = 0

# Offset start position backward along facing so kick root motion fits on flat ground.
NICLAS_START_BACK_OFFSET_HEX = 0.35

# Deterministic character height relative to hex width (flat-to-flat).
NICLAS_TARGET_HEIGHT_AS_HEX_FRACTION = 0.18
HEIGHT_SCALE_TOLERANCE = 0.20

# Canonical render mesh from niclas_3d.glb (Godot uses the skinned GLB root mesh).
NICLAS_RENDER_MESH_NAME = "char1"
NICLAS_ARMATURE_NAME = "Armature"
NICLAS_ROOT_NAME = "EOM_Niclas_Root"

# glTF imports typically face +Y in Blender; rotate so character forward aligns to terrain facing.
NICLAS_FORWARD_YAW_OFFSET_DEG = -90.0
# Additional CCW turn from above after base facing is applied (object transform only).
NICLAS_TURN_CCW_DEG = 135.0
YAW_TOLERANCE = 1e-4

# Minimum dot alignment between actual and expected facing toward target hex (0, 0).
DEMO_XY_TOLERANCE = 1e-4

NICLAS_GLB_REL_PATH = Path("game/assets/prototype/3d/units/niclas/niclas_3d.glb")

NICLAS_COLLECTION_NAME = "EOM_Niclas_Demo"

OUTPUT_BLEND_FILENAME = (
    "terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash_niclas_demo.blend"
)
OUTPUT_GLB_FILENAME = (
    "terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash_niclas_demo.glb"
)
OUTPUT_ASSETS_MARKER = "game/assets/prototype/3d/terrain"

SAVE_BLEND = True
EXPORT_GLB = False

TERRAIN_BASELINE_SCRIPT = "generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py"
TERRAIN_BASELINE_BLEND = (
    "terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.blend"
)

REPO_ROOT: Path | None = None
OUTPUT_DIR: Path | None = None
OUTPUT_BLEND_PATH: Path | None = None
OUTPUT_GLB_PATH: Path | None = None

_HELPER_MESH_NAME_MARKERS = (
    "collision",
    "proxy",
    "bounds",
    "helper",
    "lod",
    "control",
    "preview",
)


def _log(message: str) -> None:
    print(f"[EOM Niclas demo] {message}")


def _snapshot_object_transform(obj: bpy.types.Object) -> dict:
    return {
        "location": tuple(obj.location),
        "rotation_euler": tuple(obj.rotation_euler),
        "scale": tuple(obj.scale),
        "matrix_world": tuple(tuple(row) for row in obj.matrix_world),
        "hide_viewport": obj.hide_viewport,
        "hide_render": obj.hide_render,
    }


def _assert_transform_unchanged(
    before: dict,
    after: dict,
    *,
    label: str,
    tolerance: float = 1e-5,
) -> None:
    for key in ("location", "rotation_euler", "scale"):
        for bi, ai in zip(before[key], after[key]):
            if abs(bi - ai) > tolerance:
                raise RuntimeError(
                    f"{label} transform changed ({key}): before={before[key]!r} after={after[key]!r}"
                )
    if before["hide_viewport"] != after["hide_viewport"]:
        raise RuntimeError(f"{label} hide_viewport changed")
    if before["hide_render"] != after["hide_render"]:
        raise RuntimeError(f"{label} hide_render changed")


def _terrain_hex_width(terrain: object) -> float:
    return 2.0 * terrain.HEX_RADIUS * math.sqrt(3.0)


def _mesh_material_names(mesh_obj: bpy.types.Object) -> list[str]:
    names: list[str] = []
    for slot in mesh_obj.material_slots:
        if slot.material is not None:
            names.append(slot.material.name)
    return names


def _armature_modifier_target(mesh_obj: bpy.types.Object) -> bpy.types.Object | None:
    for modifier in mesh_obj.modifiers:
        if modifier.type == "ARMATURE":
            return modifier.object
    return None


def _world_bbox_corners(obj: bpy.types.Object) -> list[Vector]:
    bpy.context.view_layer.update()
    return [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]


def _world_bbox_z_range(obj: bpy.types.Object) -> tuple[float, float]:
    corners = _world_bbox_corners(obj)
    zs = [corner.z for corner in corners]
    return min(zs), max(zs)


def _world_bbox_height(obj: bpy.types.Object) -> float:
    min_z, max_z = _world_bbox_z_range(obj)
    return max_z - min_z


def _world_bbox_min_max(obj: bpy.types.Object) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    corners = _world_bbox_corners(obj)
    min_corner = (
        min(corner.x for corner in corners),
        min(corner.y for corner in corners),
        min(corner.z for corner in corners),
    )
    max_corner = (
        max(corner.x for corner in corners),
        max(corner.y for corner in corners),
        max(corner.z for corner in corners),
    )
    return min_corner, max_corner


def _read_mesh_lowest_world_z(mesh_obj: bpy.types.Object) -> float:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    eval_obj = mesh_obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    try:
        if not mesh.vertices:
            raise RuntimeError(f"Evaluated mesh has no vertices: {mesh_obj.name!r}")
        return min((eval_obj.matrix_world @ vertex.co).z for vertex in mesh.vertices)
    finally:
        eval_obj.to_mesh_clear()


def _format_transform(obj: bpy.types.Object) -> str:
    location = tuple(obj.location)
    rotation = tuple(obj.rotation_euler)
    scale = tuple(obj.scale)
    return f"location={location} rotation_euler={rotation} scale={scale}"


def _print_niclas_transform_audit(
    terrain: object,
    *,
    root_obj: bpy.types.Object,
    armature_obj: bpy.types.Object,
    render_mesh_obj: bpy.types.Object,
    animation_state: dict,
) -> None:
    scene = bpy.context.scene
    previous_frame = scene.frame_current

    hex_cx, hex_cy = terrain.axial_to_world_xy(
        NICLAS_START_HEX_Q,
        NICLAS_START_HEX_R,
        terrain.HEX_RADIUS,
    )
    sx, sy, _start_cx, _start_cy, _forward_xy = _terrain_forward_and_start_xy(terrain)
    terrain_surface_z_at_hex = terrain.sample_radial_height(hex_cx, hex_cy)
    terrain_surface_z_at_start = terrain.sample_radial_height(sx, sy)

    _log("transform audit (read-only):")
    _log(f"  {NICLAS_ROOT_NAME}: {_format_transform(root_obj)}")
    _log(f"  {NICLAS_ARMATURE_NAME}: {_format_transform(armature_obj)}")
    _log(f"  {NICLAS_RENDER_MESH_NAME}: {_format_transform(render_mesh_obj)}")

    bbox_min, bbox_max = _world_bbox_min_max(render_mesh_obj)
    _log(f"  {NICLAS_RENDER_MESH_NAME} world_bbox_min={bbox_min}")
    _log(f"  {NICLAS_RENDER_MESH_NAME} world_bbox_max={bbox_max}")

    modifier_target = _armature_modifier_target(render_mesh_obj)
    _log(
        f"  {NICLAS_RENDER_MESH_NAME} armature_modifier_target="
        f"{modifier_target.name if modifier_target is not None else None!r}"
    )

    _log(
        f"  terrain_surface_z axial=({NICLAS_START_HEX_Q},{NICLAS_START_HEX_R}) "
        f"world=({hex_cx:.6f},{hex_cy:.6f}) z={terrain_surface_z_at_hex:.6f}"
    )
    _log(
        f"  terrain_surface_z start_xy=({sx:.6f},{sy:.6f}) z={terrain_surface_z_at_start:.6f}"
    )

    if armature_obj.animation_data is not None:
        _log("  NLA strips:")
        for track in armature_obj.animation_data.nla_tracks:
            for strip in track.strips:
                action_name = strip.action.name if strip.action is not None else None
                _log(
                    f"    - {strip.name!r} action={action_name!r} "
                    f"timeline={int(strip.frame_start)}..{int(strip.frame_end)}"
                )
    else:
        _log("  NLA strips: none")

    kick_frame = int(animation_state["idle_frames"]) + 1
    for label, frame in (("frame_1", 1), ("kick_frame", kick_frame)):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        bbox_foot_z, _bbox_top_z = _world_bbox_z_range(render_mesh_obj)
        mesh_min_z = _read_mesh_lowest_world_z(render_mesh_obj)
        _log(
            f"  {label} (timeline frame {frame}): "
            f"char1_bbox_min_z={bbox_foot_z:.6f} char1_mesh_min_z={mesh_min_z:.6f}"
        )

    niclas_objects = _objects_in_niclas_collection()
    _log(f"  {NICLAS_COLLECTION_NAME} objects={[obj.name for obj in niclas_objects]}")

    scene.frame_set(previous_frame)


def _log_imported_object_audit(obj: bpy.types.Object) -> None:
    parent_name = obj.parent.name if obj.parent is not None else None
    collections = [coll.name for coll in obj.users_collection]
    data_name = obj.data.name if obj.data is not None else None
    armature_modifier = None
    if obj.type == "MESH":
        target = _armature_modifier_target(obj)
        armature_modifier = target.name if target is not None else None
    custom_props = list(obj.keys()) if obj.keys() else []
    min_corner, max_corner = _world_bbox_z_range(obj) if obj.type in {"MESH", "ARMATURE"} else (0.0, 0.0)
    _log("imported object:")
    _log(f"  name={obj.name}")
    _log(f"  type={obj.type}")
    _log(f"  parent={parent_name}")
    _log(f"  data name={data_name}")
    _log(f"  collections={collections}")
    _log(f"  hide_viewport={obj.hide_viewport}")
    _log(f"  hide_render={obj.hide_render}")
    _log(f"  dimensions={tuple(obj.dimensions)}")
    _log(f"  world_bbox_z=({min_corner:.4f}, {max_corner:.4f})")
    _log(f"  materials={_mesh_material_names(obj) if obj.type == 'MESH' else []}")
    _log(f"  armature_modifier={armature_modifier}")
    if custom_props:
        _log(f"  custom_properties={custom_props}")


def _is_helper_mesh_name(name: str) -> bool:
    lower = name.lower()
    if lower == NICLAS_RENDER_MESH_NAME.lower():
        return False
    if any(marker in lower for marker in _HELPER_MESH_NAME_MARKERS):
        return True
    bone_like = {
        "hips",
        "spine",
        "neck",
        "head",
        "shoulder",
        "arm",
        "forearm",
        "hand",
        "upleg",
        "leg",
        "foot",
        "toe",
    }
    return any(token in lower for token in bone_like)


def _make_material_opaque(mat: bpy.types.Material) -> None:
    if mat is None:
        return
    if hasattr(mat, "blend_method"):
        mat.blend_method = "OPAQUE"
    if hasattr(mat, "surface_render_method"):
        render_method = mat.blend_method if hasattr(mat, "blend_method") else "OPAQUE"
        if render_method == "OPAQUE":
            try:
                mat.surface_render_method = "DITHERED"
            except TypeError:
                try:
                    mat.surface_render_method = "Opaque"
                except TypeError:
                    pass
    mat.use_backface_culling = True
    if mat.node_tree is not None:
        for node in mat.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            alpha_input = node.inputs.get("Alpha")
            if alpha_input is not None:
                alpha_input.default_value = 1.0


def _fix_render_mesh_materials(mesh_obj: bpy.types.Object) -> None:
    for slot in mesh_obj.material_slots:
        _make_material_opaque(slot.material)


def _material_is_opaque_enough(mat: bpy.types.Material | None) -> bool:
    if mat is None:
        return True
    if hasattr(mat, "blend_method"):
        transparent_methods = {"BLEND", "BLENDED", "ALPHA_BLEND", "ALPHA_HASH"}
        if mat.blend_method in transparent_methods:
            return False
    if hasattr(mat, "surface_render_method") and mat.surface_render_method == "BLENDED":
        if hasattr(mat, "blend_method") and mat.blend_method not in {"BLEND", "BLENDED"}:
            return True
        return False
    return True


def _expected_root_yaw(forward_xy: Vector) -> float:
    return (
        math.atan2(forward_xy.y, forward_xy.x)
        + math.radians(NICLAS_FORWARD_YAW_OFFSET_DEG)
        + math.radians(NICLAS_TURN_CCW_DEG)
    )


def _yaw_delta(actual_yaw: float, expected_yaw: float) -> float:
    return (actual_yaw - expected_yaw + math.pi) % (2.0 * math.pi) - math.pi


def _configure_armature_display(armature_obj: bpy.types.Object) -> None:
    armature_obj.show_in_front = False
    for display_type in ("WIRE", "STICK", "OCTAHEDRAL"):
        try:
            armature_obj.display_type = display_type
            break
        except TypeError:
            continue
    if armature_obj.data is not None and hasattr(armature_obj.data, "display_type"):
        for display_type in ("WIRE", "STICK", "OCTAHEDRAL"):
            try:
                armature_obj.data.display_type = display_type
                break
            except TypeError:
                continue
    if armature_obj.pose is not None:
        for pose_bone in armature_obj.pose.bones:
            pose_bone.custom_shape = None
            if hasattr(pose_bone, "hide"):
                pose_bone.hide = True
    armature_obj.hide_viewport = True
    armature_obj.hide_render = True
    _log(
        "armature viewport hidden: "
        f"hide_viewport={armature_obj.hide_viewport} hide_render={armature_obj.hide_render} "
        f"display_type={armature_obj.display_type!r} show_in_front={armature_obj.show_in_front}"
    )


def _configure_timeline_playback(cycle_frames: int) -> None:
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = int(cycle_frames)
    scene.frame_set(scene.frame_start)
    _log(
        f"timeline playback configured: frame_start={scene.frame_start} "
        f"frame_end={scene.frame_end} frame_current={scene.frame_current}"
    )


def _capture_armature_pose(armature_obj: bpy.types.Object) -> dict[str, tuple[tuple, tuple, tuple]]:
    pose: dict[str, tuple[tuple, tuple, tuple]] = {}
    for pose_bone in armature_obj.pose.bones:
        pose[pose_bone.name] = (
            tuple(pose_bone.location),
            tuple(pose_bone.rotation_quaternion),
            tuple(pose_bone.scale),
        )
    return pose


def _apply_armature_pose(
    armature_obj: bpy.types.Object,
    pose: dict[str, tuple[tuple, tuple, tuple]],
) -> None:
    for bone_name, (location, rotation, scale) in pose.items():
        pose_bone = armature_obj.pose.bones.get(bone_name)
        if pose_bone is None:
            continue
        pose_bone.location = location
        pose_bone.rotation_quaternion = rotation
        pose_bone.scale = scale


def _keyframe_armature_pose(armature_obj: bpy.types.Object, frame: int) -> None:
    for pose_bone in armature_obj.pose.bones:
        pose_bone.keyframe_insert(data_path="location", frame=frame)
        pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        pose_bone.keyframe_insert(data_path="scale", frame=frame)


def _create_reset_action(
    armature_obj: bpy.types.Object,
    *,
    kick_end_pose: dict[str, tuple[tuple, tuple, tuple]],
    idle_start_pose: dict[str, tuple[tuple, tuple, tuple]],
    reset_frames: int,
) -> bpy.types.Action:
    if reset_frames <= 0:
        raise RuntimeError("Reset segment must contain at least one frame")

    existing = bpy.data.actions.get(NICLAS_RESET_ACTION_NAME)
    if existing is not None:
        bpy.data.actions.remove(existing)

    reset_action = bpy.data.actions.new(NICLAS_RESET_ACTION_NAME)
    scene = bpy.context.scene
    previous_frame = scene.frame_current

    if armature_obj.animation_data is None:
        armature_obj.animation_data_create()
    anim_data = armature_obj.animation_data
    previous_use_nla = anim_data.use_nla
    previous_action = anim_data.action
    anim_data.use_nla = False
    anim_data.action = reset_action

    _apply_armature_pose(armature_obj, kick_end_pose)
    _keyframe_armature_pose(armature_obj, 0)
    _apply_armature_pose(armature_obj, idle_start_pose)
    _keyframe_armature_pose(armature_obj, reset_frames - 1)

    anim_data.use_nla = previous_use_nla
    anim_data.action = previous_action
    scene.frame_set(previous_frame)
    return reset_action


def _remove_runtime_python_handlers() -> None:
    for handler_list in (bpy.app.handlers.frame_change_post, bpy.app.handlers.load_post):
        for handler in list(handler_list):
            handler_name = getattr(handler, "__name__", "")
            if handler_name.startswith("eom_niclas_demo"):
                handler_list.remove(handler)


def _remove_embedded_python_handlers() -> None:
    _remove_runtime_python_handlers()
    legacy_text = bpy.data.texts.get("EOM_Niclas_Demo_LoopHandler")
    if legacy_text is not None:
        bpy.data.texts.remove(legacy_text)
    for obj in bpy.data.objects:
        for key in ("eom_niclas_demo_cycle_frames", "eom_niclas_demo_start_matrix"):
            if key in obj:
                del obj[key]


def _assert_no_embedded_python_handlers() -> None:
    if bpy.data.texts.get("EOM_Niclas_Demo_LoopHandler") is not None:
        raise RuntimeError("Embedded loop handler Text block must not remain in demo blend")
    for obj in bpy.data.objects:
        for key in ("eom_niclas_demo_cycle_frames", "eom_niclas_demo_start_matrix"):
            if key in obj:
                raise RuntimeError(f"Embedded loop handler metadata must not remain on {obj.name!r}")
    for handler_list in (bpy.app.handlers.frame_change_post, bpy.app.handlers.load_post):
        for handler in handler_list:
            handler_name = getattr(handler, "__name__", "")
            if handler_name.startswith("eom_niclas_demo"):
                raise RuntimeError(
                    f"Runtime loop handler {handler_name!r} must not remain registered"
                )


def _ensure_niclas_demo_collection() -> bpy.types.Collection:
    niclas_coll = bpy.data.collections.get(NICLAS_COLLECTION_NAME)
    if niclas_coll is None:
        niclas_coll = bpy.data.collections.new(NICLAS_COLLECTION_NAME)
        bpy.context.scene.collection.children.link(niclas_coll)
    return niclas_coll


def _link_object_to_collection(obj: bpy.types.Object, target_coll: bpy.types.Collection) -> None:
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    target_coll.objects.link(obj)


def _assert_terrain_object_ready(terrain: object, terrain_obj: bpy.types.Object, *, label: str) -> None:
    if terrain_obj.name != terrain.TERRAIN_OBJECT_NAME:
        raise RuntimeError(f"{label}: terrain object name mismatch")
    if terrain_obj.type != "MESH":
        raise RuntimeError(f"{label}: terrain object must be MESH")
    if terrain_obj.data is None:
        raise RuntimeError(f"{label}: terrain mesh data missing")
    if terrain_obj.hide_viewport or terrain_obj.hide_render:
        raise RuntimeError(f"{label}: terrain object is hidden")
    width = max(terrain_obj.dimensions.x, terrain_obj.dimensions.y)
    if width <= 0.1:
        raise RuntimeError(f"{label}: terrain dimensions look invalid: {terrain_obj.dimensions!r}")
    _log(
        f"{label}: terrain object={terrain_obj.name!r} dimensions={tuple(terrain_obj.dimensions)} "
        f"hex_width={_terrain_hex_width(terrain):.4f}"
    )


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


def _terrain_baseline_script_path(repo_root: Path) -> Path:
    return (
        repo_root
        / "tools"
        / "blender"
        / "terrain"
        / TERRAIN_BASELINE_SCRIPT
    )


def _resolve_repo_root() -> tuple[Path, list[Path]]:
    examined_starts = _candidate_start_paths()
    if not examined_starts:
        raise RuntimeError(
            "No start path candidates for repo root resolution. "
            "Open the external .py file in Blender or save the .blend inside the repo."
        )

    last_error: RuntimeError | None = None
    repo_root: Path | None = None
    for start in examined_starts:
        try:
            repo_root = find_repo_root(start)
            break
        except RuntimeError as exc:
            last_error = exc

    if repo_root is None:
        starts_text = "\n".join(f"- {path}" for path in examined_starts)
        raise RuntimeError(
            "Could not locate Empire of Minds repo root.\n\n"
            f"Examined starts:\n{starts_text}\n\n"
            f"Last error: {last_error}"
        )

    return repo_root, examined_starts


def resolve_demo_output_paths() -> tuple[Path, Path, Path, Path]:
    global REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH
    if (
        REPO_ROOT is not None
        and OUTPUT_DIR is not None
        and OUTPUT_BLEND_PATH is not None
        and OUTPUT_GLB_PATH is not None
    ):
        return REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH

    repo_root, _examined_starts = _resolve_repo_root()
    _log(f"repo root: {repo_root}")

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
    REPO_ROOT = repo_root
    OUTPUT_DIR = output_dir
    OUTPUT_BLEND_PATH = output_dir / OUTPUT_BLEND_FILENAME
    OUTPUT_GLB_PATH = output_dir / OUTPUT_GLB_FILENAME
    return REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH


def _load_terrain_baseline_module(repo_root: Path, *, examined_starts: list[Path]) -> object:
    terrain_path = _terrain_baseline_script_path(repo_root)
    if not terrain_path.is_file():
        starts_text = "\n".join(f"- {path}" for path in examined_starts)
        raise RuntimeError(
            "Terrain baseline script not found.\n\n"
            f"Examined starts:\n{starts_text}\n\n"
            f"Resolved repo root:\n{repo_root}\n\n"
            f"Expected baseline:\n{terrain_path}"
        )

    _log(f"terrain baseline script: {terrain_path}")

    module_name = "eom_terrain_blender_porting_baseline"
    spec = importlib.util.spec_from_file_location(module_name, terrain_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load terrain baseline module from {terrain_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _assert_terrain_baseline_unchanged(terrain: object) -> None:
    if getattr(terrain, "ALLOW_BLENDER_PORTING_BASELINE_RETUNE", True):
        raise RuntimeError(
            "Terrain baseline retune flag must be False for Niclas demo "
            f"(got {getattr(terrain, 'ALLOW_BLENDER_PORTING_BASELINE_RETUNE', None)!r})"
        )
    if getattr(terrain, "USE_FINE_DETAIL", True):
        raise RuntimeError("Terrain baseline must keep USE_FINE_DETAIL=False")
    if getattr(terrain, "DEBUG_MATERIAL_STAGE", "") != "final":
        raise RuntimeError("Terrain baseline must keep DEBUG_MATERIAL_STAGE='final'")
    if getattr(terrain, "OUTPUT_BLEND_FILENAME", "") == OUTPUT_BLEND_FILENAME:
        raise RuntimeError("Demo output filename must differ from terrain baseline blend name")
    if getattr(terrain, "OUTPUT_GLB_FILENAME", "") == OUTPUT_GLB_FILENAME:
        raise RuntimeError("Demo output filename must differ from terrain baseline GLB name")


def _build_terrain_from_baseline(terrain: object, repo_root: Path) -> bpy.types.Object:
    terrain.validate_params()
    terrain.validate_material_params()

    ground_albedo_path, ground_normal_path, ground_roughness_path = (
        terrain.resolve_ground_texture_paths(repo_root)
    )
    stone_albedo_path, stone_normal_path, stone_roughness_path = (
        terrain.resolve_stone_texture_paths(repo_root)
    )
    ash_albedo_path, ash_normal_path, ash_roughness_path = terrain.resolve_ash_texture_paths(
        repo_root
    )

    terrain.clear_scene()
    coll = terrain.ensure_collection(terrain.COLLECTION_NAME)
    hex_coords = terrain.build_hex_coords_set()

    procedural_material = terrain.make_pbr_ground_stone_ash_terrain_material(
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
    side_material = terrain.make_side_terrain_material()

    terrain_mesh, stats = terrain.build_single_patch_mesh(hex_coords)
    terrain.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    terrain.assign_patch_materials(
        terrain_mesh,
        stats["top_faces"],
        procedural_material,
        side_material,
    )
    terrain_obj = bpy.data.objects.new(terrain.TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)

    if terrain.CREATE_HEX_OVERLAY:
        overlay_material = terrain.make_overlay_material()
        overlay_mesh, _overlay_stats = terrain.build_hex_overlay_mesh()
        overlay_obj = bpy.data.objects.new(terrain.OVERLAY_OBJECT_NAME, overlay_mesh)
        overlay_obj.data.materials.append(overlay_material)
        coll.objects.link(overlay_obj)

    terrain.setup_camera_and_lights()
    terrain.setup_render_and_world()
    _log(
        "terrain baseline built via imported module "
        f"({TERRAIN_BASELINE_SCRIPT}); material graph untouched"
    )
    return terrain_obj


def _resolve_niclas_glb_path(repo_root: Path) -> Path:
    glb_path = repo_root / NICLAS_GLB_REL_PATH
    if not glb_path.is_file():
        raise RuntimeError(f"Niclas GLB not found: {glb_path}")
    return glb_path


def _snapshot_terrain_mesh_identity(terrain_obj: bpy.types.Object) -> dict:
    mesh = terrain_obj.data
    material_names = tuple(
        slot.material.name if slot.material is not None else None
        for slot in terrain_obj.material_slots
    )
    return {
        "mesh_data_name": mesh.name,
        "vertex_count": len(mesh.vertices),
        "polygon_count": len(mesh.polygons),
        "material_names": material_names,
    }


def _assert_terrain_mesh_identity_unchanged(before: dict, after: dict, *, label: str) -> None:
    for key in ("mesh_data_name", "vertex_count", "polygon_count", "material_names"):
        if before[key] != after[key]:
            raise RuntimeError(
                f"{label} terrain mesh identity changed ({key}): "
                f"before={before[key]!r} after={after[key]!r}"
            )


def _find_canonical_render_mesh(
    imported_objects: list[bpy.types.Object],
    armature_obj: bpy.types.Object,
) -> bpy.types.Object:
    exact_matches = [
        obj
        for obj in imported_objects
        if obj.type == "MESH"
        and (
            obj.name == NICLAS_RENDER_MESH_NAME
            or obj.name.startswith(f"{NICLAS_RENDER_MESH_NAME}.")
        )
        and _armature_modifier_target(obj) == armature_obj
    ]
    if len(exact_matches) == 1:
        return exact_matches[0]

    skinned = [
        obj
        for obj in imported_objects
        if obj.type == "MESH" and _armature_modifier_target(obj) == armature_obj
    ]
    if len(skinned) == 1:
        return skinned[0]
    names = [obj.name for obj in skinned]
    raise RuntimeError(
        "Could not identify canonical Niclas render mesh "
        f"(expected {NICLAS_RENDER_MESH_NAME!r} skinned to armature); candidates={names!r}"
    )


def _import_niclas_asset(
    glb_path: Path,
    terrain: object,
    terrain_obj: bpy.types.Object,
    *,
    terrain_transform_before: dict,
    terrain_mesh_before: dict,
) -> dict:
    if terrain_obj.name not in bpy.data.objects:
        raise RuntimeError("Terrain object must exist before Niclas import")

    objects_before = set(bpy.data.objects)
    actions_before = {action.name for action in bpy.data.actions}

    _log(f"importing Niclas GLB into isolated collection {NICLAS_COLLECTION_NAME!r}")
    bpy.ops.import_scene.gltf(filepath=str(glb_path))

    imported_objects = [obj for obj in bpy.data.objects if obj not in objects_before]
    if not imported_objects:
        raise RuntimeError("Niclas GLB import produced no new objects")

    _log("GLB import audit (before cleanup):")
    for obj in sorted(imported_objects, key=lambda item: item.name):
        _log_imported_object_audit(obj)

    armatures = [obj for obj in imported_objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        names = [obj.name for obj in armatures]
        raise RuntimeError(
            f"Expected exactly one imported armature, got {len(armatures)}: {names!r}"
        )
    armature_obj = armatures[0]

    render_mesh_obj = _find_canonical_render_mesh(imported_objects, armature_obj)
    helper_meshes = [
        obj
        for obj in imported_objects
        if obj.type == "MESH" and obj != render_mesh_obj
    ]

    _log(f"canonical armature={armature_obj.name!r}")
    _log(f"canonical render mesh={render_mesh_obj.name!r}")
    _log(
        "white bumpy ball cause: "
        "imported helper mesh(es) such as Icosphere / bone preview geometry "
        "without skinning (not deformed by armature)"
    )
    _log(
        "semi-transparent giant cause: "
        f"{render_mesh_obj.name!r} kept at import scale 1.0 with material alphaMode=BLEND "
        "from GLB (Material_1); fixed to opaque after cleanup"
    )
    if helper_meshes:
        _log(f"helper meshes to remove: {[obj.name for obj in helper_meshes]}")

    new_actions = [action for action in bpy.data.actions if action.name not in actions_before]
    _log("imported actions:")
    for action in sorted(new_actions, key=lambda item: item.name):
        frame_start, frame_end = action.frame_range
        _log(f"- {action.name} (frames {frame_start:.0f}..{frame_end:.0f})")

    removed_helpers: list[str] = []
    for obj in list(imported_objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            removed_helpers.append(f"{obj.name} ({obj.type})")
            bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.type == "MESH" and obj != render_mesh_obj:
            removed_helpers.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.type == "EMPTY":
            removed_helpers.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)

    if removed_helpers:
        _log(f"removed imported helper/clutter: {', '.join(removed_helpers)}")

    _fix_render_mesh_materials(render_mesh_obj)

    niclas_coll = _ensure_niclas_demo_collection()
    root_obj = bpy.data.objects.new(NICLAS_ROOT_NAME, None)
    niclas_coll.objects.link(root_obj)

    armature_world = armature_obj.matrix_world.copy()
    armature_obj.parent = root_obj
    armature_obj.matrix_world = armature_world

    for obj in (root_obj, render_mesh_obj):
        obj.hide_viewport = False
        obj.hide_render = False
        _link_object_to_collection(obj, niclas_coll)
    _link_object_to_collection(root_obj, niclas_coll)
    _configure_armature_display(armature_obj)
    _link_object_to_collection(armature_obj, niclas_coll)

    hex_width = _terrain_hex_width(terrain)
    imported_height = _world_bbox_height(render_mesh_obj)
    if imported_height <= 1e-6:
        raise RuntimeError(
            f"Imported Niclas render mesh height is invalid: {imported_height!r}"
        )
    target_height = hex_width * NICLAS_TARGET_HEIGHT_AS_HEX_FRACTION
    applied_scale = target_height / imported_height

    _log(f"hex width={hex_width:.4f}")
    _log(f"imported character height={imported_height:.4f}")
    _log(f"target character height={target_height:.4f}")
    _log(f"applied uniform scale={applied_scale:.6f}")

    terrain_transform_after = _snapshot_object_transform(terrain_obj)
    _assert_transform_unchanged(
        terrain_transform_before,
        terrain_transform_after,
        label=terrain.TERRAIN_OBJECT_NAME,
    )
    terrain_mesh_after = _snapshot_terrain_mesh_identity(terrain_obj)
    _assert_terrain_mesh_identity_unchanged(
        terrain_mesh_before,
        terrain_mesh_after,
        label=terrain.TERRAIN_OBJECT_NAME,
    )

    if terrain_obj.parent is not None and terrain_obj.parent.name == NICLAS_ROOT_NAME:
        raise RuntimeError("Terrain object must not be parented under Niclas root")

    return {
        "armature_obj": armature_obj,
        "render_mesh_obj": render_mesh_obj,
        "root_obj": root_obj,
        "niclas_coll": niclas_coll,
        "applied_scale": applied_scale,
        "imported_height": imported_height,
        "target_height": target_height,
        "hex_width": hex_width,
        "removed_helpers": removed_helpers,
    }


def _resolve_action_or_fail(action_name: str, imported_action_names: list[str]) -> bpy.types.Action:
    if action_name in bpy.data.actions:
        return bpy.data.actions[action_name]
    available = sorted(action.name for action in bpy.data.actions)
    raise RuntimeError(
        f"Required action {action_name!r} not found. Available actions: {available!r}"
    )


def _scene_fps() -> float:
    scene = bpy.context.scene
    base = float(scene.render.fps_base) if scene.render.fps_base else 1.0
    return float(scene.render.fps) / base


def _seconds_to_frames(seconds: float, fps: float) -> int:
    if seconds <= 0.0:
        raise RuntimeError(f"Duration must be > 0 seconds, got {seconds!r}")
    return max(1, int(round(seconds * fps)))


def _full_action_frame_length(action: bpy.types.Action) -> int:
    frame_start, frame_end = action.frame_range
    length = int(round(frame_end - frame_start)) + 1
    if length <= 0:
        raise RuntimeError(f"Action {action.name!r} has invalid frame range {action.frame_range}")
    return length


def _terrain_forward_and_start_xy(terrain: object) -> tuple[float, float, float, float, Vector]:
    cx, cy = terrain.axial_to_world_xy(
        NICLAS_START_HEX_Q,
        NICLAS_START_HEX_R,
        terrain.HEX_RADIUS,
    )
    nx, ny = terrain.axial_to_world_xy(
        NICLAS_FACE_NEIGHBOR_Q,
        NICLAS_FACE_NEIGHBOR_R,
        terrain.HEX_RADIUS,
    )
    forward_xy = Vector((nx - cx, ny - cy, 0.0))
    forward_len_sq = forward_xy.length_squared
    if forward_len_sq <= 1e-12:
        raise RuntimeError("Niclas facing neighbor resolves to zero-length direction")
    forward_xy.normalize()

    back_offset = NICLAS_START_BACK_OFFSET_HEX * terrain.HEX_RADIUS
    sx = cx - forward_xy.x * back_offset
    sy = cy - forward_xy.y * back_offset
    return sx, sy, cx, cy, forward_xy


def _place_niclas_root(
    terrain: object,
    root_obj: bpy.types.Object,
    render_mesh_obj: bpy.types.Object,
    *,
    sx: float,
    sy: float,
    forward_xy: Vector,
    applied_scale: float,
) -> None:
    root_obj.location = Vector((sx, sy, 0.0))
    root_obj.scale = Vector((applied_scale, applied_scale, applied_scale))
    root_obj.rotation_euler = Vector((0.0, 0.0, _expected_root_yaw(forward_xy)))

    terrain_z = terrain.sample_radial_height(sx, sy) + NICLAS_START_HEIGHT_OFFSET
    bpy.context.view_layer.update()
    foot_z, _top_z = _world_bbox_z_range(render_mesh_obj)
    root_obj.location.z = terrain_z - foot_z
    _log(
        f"placement applied on {NICLAS_ROOT_NAME!r} only "
        f"(scale={applied_scale:.6f}, yaw_deg={math.degrees(root_obj.rotation_euler.z):.3f}, "
        f"turn_ccw_deg={NICLAS_TURN_CCW_DEG:.1f})"
    )


def _setup_niclas_demo_animation(
    armature_obj: bpy.types.Object,
    *,
    idle_action: bpy.types.Action,
    kick_action: bpy.types.Action,
) -> dict:
    if NICLAS_IDLE_DURATION_SECONDS <= 0.0:
        raise RuntimeError("NICLAS_IDLE_DURATION_SECONDS must be > 0")

    fps = _scene_fps()
    idle_frames = _seconds_to_frames(NICLAS_IDLE_DURATION_SECONDS, fps)
    kick_frames = _full_action_frame_length(kick_action)
    kick_end_frame = idle_frames + kick_frames

    if armature_obj.animation_data is None:
        armature_obj.animation_data_create()
    anim_data = armature_obj.animation_data
    anim_data.action = None
    anim_data.use_nla = True

    for track in list(anim_data.nla_tracks):
        anim_data.nla_tracks.remove(track)

    track = anim_data.nla_tracks.new()
    track.name = "Niclas Actions"

    idle_start = 1
    idle_strip = track.strips.new("Idle", idle_start, idle_action)
    idle_strip.blend_type = "REPLACE"
    idle_strip.extrapolation = "NOTHING"
    idle_strip.action_frame_start = idle_action.frame_range[0]
    idle_strip.action_frame_end = idle_action.frame_range[0] + idle_frames - 1
    idle_strip.frame_end = idle_start + idle_frames - 1

    kick_start = idle_start + idle_frames
    kick_strip = track.strips.new("Kick", kick_start, kick_action)
    kick_strip.blend_type = "REPLACE"
    kick_strip.extrapolation = "NOTHING"
    kick_strip.action_frame_start = kick_action.frame_range[0]
    kick_strip.action_frame_end = kick_action.frame_range[1]
    kick_strip.frame_end = kick_start + kick_frames - 1

    scene = bpy.context.scene
    scene.frame_set(1)
    bpy.context.view_layer.update()
    idle_start_pose = _capture_armature_pose(armature_obj)

    scene.frame_set(kick_end_frame)
    bpy.context.view_layer.update()
    kick_end_pose = _capture_armature_pose(armature_obj)

    reset_action = _create_reset_action(
        armature_obj,
        kick_end_pose=kick_end_pose,
        idle_start_pose=idle_start_pose,
        reset_frames=NICLAS_RESET_FRAMES,
    )

    reset_start = kick_end_frame + 1
    reset_strip = track.strips.new("Reset", reset_start, reset_action)
    reset_strip.blend_type = "REPLACE"
    reset_strip.extrapolation = "NOTHING"
    reset_strip.action_frame_start = 0
    reset_strip.action_frame_end = NICLAS_RESET_FRAMES - 1
    reset_strip.frame_end = reset_start + NICLAS_RESET_FRAMES - 1

    cycle_frames = kick_end_frame + NICLAS_RESET_FRAMES
    _configure_timeline_playback(cycle_frames)
    _remove_embedded_python_handlers()

    animation_state = {
        "armature_obj": armature_obj,
        "cycle_frames": cycle_frames,
        "idle_frames": idle_frames,
        "kick_frames": kick_frames,
        "reset_frames": NICLAS_RESET_FRAMES,
        "fps": fps,
        "reset_action": reset_action,
    }

    _log(f"idle_action={idle_action.name!r}")
    _log(f"kick_action={kick_action.name!r}")
    _log(f"reset_action={reset_action.name!r}")
    _log(f"scene_fps={fps:.3f}")
    _log(f"idle_duration_seconds={NICLAS_IDLE_DURATION_SECONDS}")
    _log(f"idle_timeline_frames={idle_frames}")
    _log(f"kick_full_frames={kick_frames} (full action frame range preserved)")
    _log(f"reset_timeline_frames={NICLAS_RESET_FRAMES}")
    _log(f"cycle_frames={cycle_frames}")
    _log(
        "loop mechanism=NLA strips (idle trimmed, full kick, keyed reset segment); "
        "no embedded Python handlers"
    )
    return animation_state


def _maybe_adjust_camera_for_demo(terrain: object) -> None:
    scene = bpy.context.scene
    camera = scene.camera
    if camera is None:
        return
    hill_cx, hill_cy = terrain.hill_center_xy()
    start_cx, start_cy = terrain.axial_to_world_xy(
        NICLAS_START_HEX_Q,
        NICLAS_START_HEX_R,
        terrain.HEX_RADIUS,
    )
    mid = Vector(((hill_cx + start_cx) * 0.5, (hill_cy + start_cy) * 0.5, 0.0))
    loc = camera.location.copy()
    loc.x = loc.x * 0.8 + mid.x * 0.2
    loc.y = loc.y * 0.8 + mid.y * 0.2
    camera.location = loc
    _log("camera nudged toward Niclas/hill midpoint (position only; baseline lights/world kept)")


def _objects_in_niclas_collection() -> list[bpy.types.Object]:
    niclas_coll = bpy.data.collections.get(NICLAS_COLLECTION_NAME)
    if niclas_coll is None:
        return []
    return list(niclas_coll.objects)


def _assert_demo_scene(
    terrain: object,
    *,
    terrain_obj: bpy.types.Object,
    terrain_transform_before: dict,
    terrain_mesh_before: dict,
    armature_obj: bpy.types.Object,
    render_mesh_obj: bpy.types.Object,
    root_obj: bpy.types.Object,
    idle_action: bpy.types.Action,
    kick_action: bpy.types.Action,
    animation_state: dict,
    applied_scale: float,
    target_height: float,
    removed_helpers: list[str],
) -> None:
    if terrain_obj.name not in bpy.data.objects:
        raise RuntimeError("Terrain object missing after Niclas import")

    terrain_transform_after = _snapshot_object_transform(terrain_obj)
    _assert_transform_unchanged(
        terrain_transform_before,
        terrain_transform_after,
        label=terrain.TERRAIN_OBJECT_NAME,
    )
    terrain_mesh_after = _snapshot_terrain_mesh_identity(terrain_obj)
    _assert_terrain_mesh_identity_unchanged(
        terrain_mesh_before,
        terrain_mesh_after,
        label=terrain.TERRAIN_OBJECT_NAME,
    )
    if terrain_obj.hide_viewport or terrain_obj.hide_render:
        raise RuntimeError("Terrain object must remain visible after Niclas import")
    if terrain_obj.parent is not None and terrain_obj.parent.name == NICLAS_ROOT_NAME:
        raise RuntimeError("Terrain object must not be parented under Niclas root")

    niclas_objects = _objects_in_niclas_collection()
    armatures = [obj for obj in niclas_objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(
            f"Expected exactly one canonical Niclas armature, got {len(armatures)}"
        )
    if armatures[0] != armature_obj:
        raise RuntimeError("Canonical Niclas armature mismatch")

    if _armature_modifier_target(render_mesh_obj) != armature_obj:
        raise RuntimeError("Canonical render mesh is not bound to canonical armature")

    if armature_obj.hide_viewport is not True or armature_obj.hide_render is not True:
        raise RuntimeError("Canonical armature must be hidden from viewport and render")
    if armature_obj.show_in_front is not False:
        raise RuntimeError("Canonical armature show_in_front must be False")

    render_meshes = [
        obj
        for obj in niclas_objects
        if obj.type == "MESH"
        and not obj.hide_viewport
        and not obj.hide_render
    ]
    if len(render_meshes) != 1 or render_meshes[0] != render_mesh_obj:
        names = [obj.name for obj in render_meshes]
        raise RuntimeError(
            f"Expected exactly one visible Niclas render mesh, got {names!r}"
        )

    for obj in niclas_objects:
        if obj.type in {"CAMERA", "LIGHT"}:
            raise RuntimeError(f"Imported camera/light remains in Niclas demo: {obj.name}")
        if obj.type == "MESH" and obj != render_mesh_obj:
            if not obj.hide_viewport or not obj.hide_render:
                raise RuntimeError(
                    f"Helper/proxy mesh still render-visible in Niclas demo: {obj.name}"
                )
        if obj.type == "MESH" and obj != render_mesh_obj and _is_helper_mesh_name(obj.name):
            raise RuntimeError(f"Helper mesh name still present in Niclas demo: {obj.name}")

    scaled_height = _world_bbox_height(render_mesh_obj)
    if abs(scaled_height - target_height) > target_height * HEIGHT_SCALE_TOLERANCE:
        raise RuntimeError(
            "Niclas height after scaling out of tolerance "
            f"(actual={scaled_height:.4f}, target={target_height:.4f})"
        )

    for mat_name in _mesh_material_names(render_mesh_obj):
        mat = bpy.data.materials.get(mat_name)
        if not _material_is_opaque_enough(mat):
            raise RuntimeError(f"Niclas render material must be opaque: {mat_name!r}")

    sx, sy, start_cx, start_cy, expected_facing_xy = _terrain_forward_and_start_xy(terrain)
    terrain_z = terrain.sample_radial_height(sx, sy) + NICLAS_START_HEIGHT_OFFSET
    foot_z, _top_z = _world_bbox_z_range(render_mesh_obj)
    if abs(foot_z - terrain_z) > 0.05:
        raise RuntimeError(
            f"Niclas feet not aligned to terrain (foot_z={foot_z:.4f}, terrain_z={terrain_z:.4f})"
        )

    if armature_obj.animation_data is None or not armature_obj.animation_data.use_nla:
        raise RuntimeError("Niclas armature must use NLA for idle/kick demo")
    strip_actions = [
        strip.action.name
        for track in armature_obj.animation_data.nla_tracks
        for strip in track.strips
        if strip.action is not None
    ]
    if idle_action.name not in strip_actions or kick_action.name not in strip_actions:
        raise RuntimeError(
            f"Idle/kick actions must be on canonical armature NLA; strips={strip_actions!r}"
        )
    if NICLAS_RESET_ACTION_NAME not in strip_actions:
        raise RuntimeError(
            f"Reset action must be on canonical armature NLA; strips={strip_actions!r}"
        )

    if armature_obj.type != "ARMATURE":
        raise RuntimeError("Niclas armature object missing")

    if idle_action.name != NICLAS_IDLE_ACTION_NAME:
        raise RuntimeError(f"Unexpected idle action: {idle_action.name!r}")
    if kick_action.name != NICLAS_KICK_ACTION_NAME:
        raise RuntimeError(f"Unexpected kick action: {kick_action.name!r}")

    kick_frames = _full_action_frame_length(kick_action)
    if kick_frames != int(animation_state["kick_frames"]):
        raise RuntimeError("Kick strip must use the full imported action frame range")
    if int(animation_state["reset_frames"]) != NICLAS_RESET_FRAMES:
        raise RuntimeError("Reset segment frame count mismatch")

    if NICLAS_IDLE_DURATION_SECONDS <= 0.0:
        raise RuntimeError("Idle duration must be positive")

    if (NICLAS_START_HEX_Q, NICLAS_START_HEX_R) != (-1, 0):
        raise RuntimeError(
            "Niclas start hex must be west outer hex (-1,0) opposite hill with center between"
        )
    if (NICLAS_FACE_NEIGHBOR_Q, NICLAS_FACE_NEIGHBOR_R) != (0, 0):
        raise RuntimeError("Niclas target hex must be center hex (0,0)")
    if (terrain.HILL_AXIAL_Q, terrain.HILL_AXIAL_R) != (1, 0):
        raise RuntimeError("Hill hex must be east hill hex (1,0)")

    if root_obj.location.z < terrain_z - 0.05:
        raise RuntimeError("Niclas start point appears below terrain top surface")

    expected_yaw = _expected_root_yaw(expected_facing_xy)
    yaw_delta = _yaw_delta(root_obj.rotation_euler.z, expected_yaw)
    if abs(yaw_delta) > YAW_TOLERANCE:
        raise RuntimeError(
            "Niclas root yaw must include base facing plus CCW turn "
            f"(actual={math.degrees(root_obj.rotation_euler.z):.3f}°, "
            f"expected={math.degrees(expected_yaw):.3f}°, "
            f"turn_ccw_deg={NICLAS_TURN_CCW_DEG:.1f})"
        )

    back_offset = NICLAS_START_BACK_OFFSET_HEX * terrain.HEX_RADIUS
    expected_sx = start_cx - expected_facing_xy.x * back_offset
    expected_sy = start_cy - expected_facing_xy.y * back_offset
    if (
        abs(sx - expected_sx) > DEMO_XY_TOLERANCE
        or abs(sy - expected_sy) > DEMO_XY_TOLERANCE
    ):
        raise RuntimeError(
            "Niclas start position must sit behind start hex center along opposite facing "
            f"(actual=({sx:.6f}, {sy:.6f}), expected=({expected_sx:.6f}, {expected_sy:.6f}))"
        )

    if (
        abs(root_obj.location.x - sx) > DEMO_XY_TOLERANCE
        or abs(root_obj.location.y - sy) > DEMO_XY_TOLERANCE
    ):
        raise RuntimeError("Niclas root XY must match computed demo start position")

    scene = bpy.context.scene
    cycle_frames = int(animation_state["cycle_frames"])
    if scene.frame_start != 1 or scene.frame_end != cycle_frames:
        raise RuntimeError(
            "Timeline must cover one full idle→kick→reset loop "
            f"(frame_start={scene.frame_start}, frame_end={scene.frame_end}, "
            f"expected 1..{cycle_frames})"
        )
    if scene.frame_current != scene.frame_start:
        raise RuntimeError(
            f"Timeline current frame must be frame_start ({scene.frame_start}), "
            f"got {scene.frame_current}"
        )

    _assert_no_embedded_python_handlers()

    _log(
        "facing validation: "
        f"start_hex=(-1,0) placement_hex=(-1,0) turn_ccw_deg={NICLAS_TURN_CCW_DEG:.1f} "
        f"root_yaw_deg={math.degrees(root_obj.rotation_euler.z):.3f}"
    )
    _log(
        f"terrain transform before/after unchanged for {terrain.TERRAIN_OBJECT_NAME!r}; "
        f"removed helpers={len(removed_helpers)}"
    )
    _log(
        f"canonical armature={armature_obj.name!r} "
        f"canonical render mesh={render_mesh_obj.name!r} "
        f"applied scale={applied_scale:.6f} rotation_ccw_deg={NICLAS_TURN_CCW_DEG:.1f}"
    )

    if OUTPUT_BLEND_FILENAME == TERRAIN_BASELINE_BLEND:
        raise RuntimeError("Demo blend output must differ from terrain baseline output")


def _ops_context_override() -> dict:
    window = bpy.context.window
    if window is None:
        raise RuntimeError("No Blender context window for operator override")
    screen = window.screen
    if screen is None:
        raise RuntimeError("No Blender context screen for operator override")
    scene = bpy.context.scene
    view_layer = bpy.context.view_layer
    return {
        "window": window,
        "screen": screen,
        "area": screen.areas[0] if screen.areas else None,
        "region": screen.areas[0].regions[-1] if screen.areas and screen.areas[0].regions else None,
        "scene": scene,
        "view_layer": view_layer,
    }


def save_demo_outputs() -> None:
    if OUTPUT_DIR is None or OUTPUT_BLEND_PATH is None or OUTPUT_GLB_PATH is None:
        raise RuntimeError("Demo output paths not resolved")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    _remove_embedded_python_handlers()
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
    repo_root, examined_starts = _resolve_repo_root()
    _log(f"repo root: {repo_root}")

    global REPO_ROOT, OUTPUT_DIR, OUTPUT_BLEND_PATH, OUTPUT_GLB_PATH
    if REPO_ROOT is None:
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
        REPO_ROOT = repo_root
        OUTPUT_DIR = output_dir
        OUTPUT_BLEND_PATH = output_dir / OUTPUT_BLEND_FILENAME
        OUTPUT_GLB_PATH = output_dir / OUTPUT_GLB_FILENAME

    terrain = _load_terrain_baseline_module(repo_root, examined_starts=examined_starts)
    _assert_terrain_baseline_unchanged(terrain)

    _log("building approved Blender porting terrain baseline (imported module, no retune)…")
    terrain_obj = _build_terrain_from_baseline(terrain, repo_root)
    _assert_terrain_object_ready(terrain, terrain_obj, label="after terrain build")
    terrain_transform_before = _snapshot_object_transform(terrain_obj)
    terrain_mesh_before = _snapshot_terrain_mesh_identity(terrain_obj)

    glb_path = _resolve_niclas_glb_path(repo_root)
    _log(f"importing Niclas asset: {glb_path}")
    niclas_import = _import_niclas_asset(
        glb_path,
        terrain,
        terrain_obj,
        terrain_transform_before=terrain_transform_before,
        terrain_mesh_before=terrain_mesh_before,
    )

    armature_obj = niclas_import["armature_obj"]
    render_mesh_obj = niclas_import["render_mesh_obj"]
    root_obj = niclas_import["root_obj"]
    applied_scale = niclas_import["applied_scale"]

    imported_action_names = sorted(action.name for action in bpy.data.actions)
    idle_action = _resolve_action_or_fail(NICLAS_IDLE_ACTION_NAME, imported_action_names)
    kick_action = _resolve_action_or_fail(NICLAS_KICK_ACTION_NAME, imported_action_names)

    sx, sy, _cx, _cy, forward_xy = _terrain_forward_and_start_xy(terrain)
    _place_niclas_root(
        terrain,
        root_obj,
        render_mesh_obj,
        sx=sx,
        sy=sy,
        forward_xy=forward_xy,
        applied_scale=applied_scale,
    )

    animation_state = _setup_niclas_demo_animation(
        armature_obj,
        idle_action=idle_action,
        kick_action=kick_action,
    )
    _maybe_adjust_camera_for_demo(terrain)

    _print_niclas_transform_audit(
        terrain,
        root_obj=root_obj,
        armature_obj=armature_obj,
        render_mesh_obj=render_mesh_obj,
        animation_state=animation_state,
    )

    _assert_demo_scene(
        terrain,
        terrain_obj=terrain_obj,
        terrain_transform_before=terrain_transform_before,
        terrain_mesh_before=terrain_mesh_before,
        armature_obj=armature_obj,
        render_mesh_obj=render_mesh_obj,
        root_obj=root_obj,
        idle_action=idle_action,
        kick_action=kick_action,
        animation_state=animation_state,
        applied_scale=applied_scale,
        target_height=niclas_import["target_height"],
        removed_helpers=niclas_import["removed_helpers"],
    )

    _log(
        "start hex axial=(%d,%d) face_neighbor=(%d,%d) "
        "start_xyz=(%.3f, %.3f, %.3f) scale=%.6f turn_ccw_deg=%.1f root_yaw_deg=%.3f"
        % (
            NICLAS_START_HEX_Q,
            NICLAS_START_HEX_R,
            NICLAS_FACE_NEIGHBOR_Q,
            NICLAS_FACE_NEIGHBOR_R,
            root_obj.location.x,
            root_obj.location.y,
            root_obj.location.z,
            applied_scale,
            NICLAS_TURN_CCW_DEG,
            math.degrees(root_obj.rotation_euler.z),
        )
    )
    _log(
        "demo audit: "
        f"target_height={niclas_import['target_height']:.4f} "
        f"scale={applied_scale:.6f} "
        f"rotation_ccw_deg={NICLAS_TURN_CCW_DEG:.1f} "
        f"kept=Armature,char1,{NICLAS_ROOT_NAME} "
        f"removed={niclas_import['removed_helpers']} "
        f"armature_hidden={armature_obj.hide_viewport and armature_obj.hide_render} "
        f"timeline={bpy.context.scene.frame_start}..{bpy.context.scene.frame_current}.."
        f"{bpy.context.scene.frame_end} "
        f"requires_auto_run=NO "
        f"terrain_unchanged=YES"
    )
    _log(
        "Godot reference: unit_3d_idle_variation.gd "
        f"(idle={NICLAS_IDLE_ACTION_NAME!r}, kick={NICLAS_KICK_ACTION_NAME!r}); "
        "asset=game/assets/prototype/3d/units/niclas/niclas_3d.glb"
    )
    _log(
        "root motion: preserved on imported armature bones (Hips/root motion); "
        "loop reset keyed in NLA reset strip, no Python handlers"
    )

    save_demo_outputs()
    _log("done — press Play on timeline to preview idle→kick→reset loop")


if __name__ == "__main__":
    main()
