# Empire of Minds — 7-hex single-patch radial hill prototype (Blender only).
# Run from Blender Scripting workspace: Open → Run Script.
# Requires bpy (not available outside Blender).
#
# Milestones preserved elsewhere:
#   generate_terrain_prototype.py
#   generate_terrain_heightfield_prototype.py
#
# Future Godot picking (not implemented here):
#   1. raycast against EOM_Terrain_SinglePatch
#   2. read world hit position
#   3. world XY → axial (q, r)
#   4. lookup hex gameplay data

import math
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

OUTPUT_BLEND_FILENAME = "terrain_prototype_7_hex_single_patch.blend"
OUTPUT_GLB_FILENAME = "terrain_prototype_7_hex_single_patch.glb"
OUTPUT_ASSETS_MARKER = "game/assets/prototype/3d/terrain"

SAVE_BLEND = True
EXPORT_GLB = False

COLLECTION_NAME = "EOM_Terrain_Prototype"
TERRAIN_OBJECT_NAME = "EOM_Terrain_SinglePatch"
OVERLAY_OBJECT_NAME = "EOM_Hex_Overlay"
MATERIAL_NAME = "EOM_Terrain_Prototype"
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
    print(f"[EOM terrain single-patch] {message}")


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


def make_terrain_material() -> bpy.types.Material:
    mat = bpy.data.materials.get(MATERIAL_NAME)
    if mat is not None:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    out = _new_node(nodes, "ShaderNodeOutputMaterial")
    out.location = (600, 0)

    principled = _new_node(nodes, "ShaderNodeBsdfPrincipled")
    principled.location = (300, 0)
    _require_input(principled, "Roughness").default_value = 0.85

    tex_coord = _new_node(nodes, "ShaderNodeTexCoord")
    tex_coord.location = (-900, 0)

    mapping = _new_node(nodes, "ShaderNodeMapping")
    mapping.location = (-700, 0)
    _require_input(mapping, "Scale").default_value = (0.35, 0.35, 0.35)

    noise = _new_node(nodes, "ShaderNodeTexNoise")
    noise.location = (-500, 100)
    _require_input(noise, "Scale").default_value = 2.2
    _require_input(noise, "Detail").default_value = 4.0

    ramp = _new_node(nodes, "ShaderNodeValToRGB")
    ramp.location = (-300, 100)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.12, 0.16, 0.08, 1.0)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (0.28, 0.24, 0.14, 1.0)

    layer_weight = _new_node(nodes, "ShaderNodeLayerWeight")
    layer_weight.location = (-500, -120)
    _require_input(layer_weight, "Blend").default_value = 0.35

    slope_dark = _new_node(nodes, "ShaderNodeRGB")
    slope_dark.location = (-300, -220)
    _require_output(slope_dark, "Color").default_value = (0.08, 0.09, 0.07, 1.0)

    try:
        mix_slope = nodes.new("ShaderNodeMixRGB")
        mix_slope.blend_type = "MULTIPLY"
        mix_in_a, mix_in_b, mix_in_fac = "Color1", "Color2", "Fac"
        mix_out_name = "Color"
    except RuntimeError:
        mix_slope = nodes.new("ShaderNodeMix")
        mix_slope.data_type = "RGBA"
        mix_slope.blend_type = "MULTIPLY"
        mix_in_a, mix_in_b, mix_in_fac = "A", "B", "Factor"
        mix_out_name = "Result"
    mix_slope.location = (-80, -40)
    _require_input(mix_slope, mix_in_fac, "Fac", "Factor").default_value = 0.55

    links.new(_require_output(tex_coord, "Object"), _require_input(mapping, "Vector"))
    links.new(_require_output(mapping, "Vector"), _require_input(noise, "Vector"))
    links.new(_require_output(noise, "Fac"), _require_input(ramp, "Fac"))
    links.new(
        _require_output(ramp, "Color"),
        _require_input(mix_slope, mix_in_a, "Color1", "A"),
    )
    links.new(
        _require_output(layer_weight, "Facing"),
        _require_input(mix_slope, mix_in_fac, "Fac", "Factor"),
    )
    links.new(
        _require_output(slope_dark, "Color"),
        _require_input(mix_slope, mix_in_b, "Color2", "B"),
    )
    links.new(
        _require_output(mix_slope, mix_out_name, "Color", "Result"),
        _require_input(principled, "Base Color"),
    )
    links.new(_require_output(principled, "BSDF"), _require_input(out, "Surface"))

    return mat


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
    resolve_output_paths()
    hill_cx, hill_cy = hill_center_xy()
    _log(f"Blender version: {_blender_version_label()}")
    _log("generating 7-hex single-patch radial hill prototype…")
    _log(f"surface subdivisions: {SURFACE_SUBDIVISIONS}")
    _log(f"hill profile: {HILL_PROFILE}")
    _log(f"hill center: ({hill_cx:.4f}, {hill_cy:.4f}) axial ({HILL_AXIAL_Q},{HILL_AXIAL_R})")
    _log(f"hill radius: {HILL_RADIUS:.4f}")
    _log(f"hill height: {HILL_HEIGHT:.4f}")

    validate_radial_symmetry()

    clear_scene()
    coll = ensure_collection(COLLECTION_NAME)
    hex_coords = build_hex_coords_set()

    terrain_material = make_terrain_material()
    _log("material created")

    terrain_mesh, stats = build_single_patch_mesh(hex_coords)
    terrain_obj = bpy.data.objects.new(TERRAIN_OBJECT_NAME, terrain_mesh)
    terrain_obj.data.materials.append(terrain_material)
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
    save_outputs()
    _log("done")


if __name__ == "__main__":
    main()
