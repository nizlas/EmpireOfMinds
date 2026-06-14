# Empire of Minds — 7-hex flat-top terrain prototype generator (Blender only).
# Run from Blender Scripting workspace: Open this file → Run Script.
# Requires bpy (not available outside Blender).

import math
import os
import sys

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Tunable parameters
# ---------------------------------------------------------------------------

# Circumradius: center to outer corner (flat-top hex, edge-to-edge spacing).
HEX_RADIUS = 1.0

# Solid thickness below the top surface (world Z).
BASE_THICKNESS = 0.35

# Inner flat plateau radius as a fraction of HEX_RADIUS (0 < factor < 1).
INNER_RADIUS_FACTOR = 0.55

# World Z units per elevation level step.
ELEVATION_STEP = 0.4

PLAIN_LEVEL = 0
HILL_LEVEL = 1

# Parametric top-surface refinement (analytic height; not mesh subdivision modifier).
SURFACE_SUBDIVISIONS = 8
INNER_FLAT_RADIUS_FACTOR = 0.12
HEIGHT_PROFILE = "quadratic"

# Repo-relative output (resolved from this script's location).
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUTPUT_DIR = os.path.join(
    REPO_ROOT,
    "game",
    "assets",
    "prototype",
    "3d",
    "terrain",
    "prototype_3d_terrain",
    "generated",
)
OUTPUT_BLEND_PATH = os.path.join(OUTPUT_DIR, "terrain_prototype_7_hex.blend")
OUTPUT_GLB_PATH = os.path.join(OUTPUT_DIR, "terrain_prototype_7_hex.glb")

SAVE_BLEND = True
EXPORT_GLB = False

# Collection / object names
COLLECTION_NAME = "EOM_Terrain_Prototype"
MATERIAL_NAME = "EOM_Terrain_Prototype"
CAMERA_NAME = "PrototypeCamera"
SUN_NAME = "PrototypeSun"


def _log(message: str) -> None:
    print(f"[EOM terrain] {message}")


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
    """Best-effort override dict for bpy.ops save/export in Scripting workspace."""
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


# ---------------------------------------------------------------------------
# Axial hex grid (flat-top, Red Blob Games convention)
#
# Neighbor directions (index → dq, dr):
#   0 East (+1, 0)
#   1 Northeast (+1, -1)
#   2 Northwest (0, -1)
#   3 West (-1, 0)
#   4 Southwest (-1, +1)
#   5 Southeast (0, +1)
#
# Corners 0..5 are CCW starting at 30° (upper-right vertex).
# Edge i connects corner i → corner (i+1) % 6.
# Physical edge shared with neighbor direction d uses edge index (d - 1) % 6.
#   e.g. East (d=0) → edge 5 between corners 5 (330°) and 0 (30°).
# ---------------------------------------------------------------------------

NEIGHBOR_DIRS = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)

# 7-hex cluster: center + six neighbors. (q, r, elevation_level, terrain_label)
PROTOTYPE_HEXES = (
    (0, 0, PLAIN_LEVEL, "Plain"),
    (1, 0, HILL_LEVEL, "Hill"),  # east neighbor — shared edge slopes 0 → 1
    (1, -1, PLAIN_LEVEL, "Plain"),
    (0, -1, PLAIN_LEVEL, "Plain"),
    (-1, 0, PLAIN_LEVEL, "Plain"),
    (-1, 1, PLAIN_LEVEL, "Plain"),
    (0, 1, PLAIN_LEVEL, "Plain"),
)


def level_to_z(level: int) -> float:
    return float(level) * ELEVATION_STEP


def axial_to_world_xy(q: int, r: int, radius: float) -> tuple[float, float]:
    """Flat-top hex center from axial (q, r). Circumradius = radius."""
    x = radius * math.sqrt(3.0) * (float(q) + float(r) * 0.5)
    y = radius * 1.5 * float(r)
    return x, y


def corner_xy_local(corner_index: int, radius: float) -> tuple[float, float]:
    """Corner offset from hex center; CCW from 30° (flat-top)."""
    angle_deg = 60.0 * float(corner_index) + 30.0
    angle_rad = math.radians(angle_deg)
    return radius * math.cos(angle_rad), radius * math.sin(angle_rad)


def edge_index_for_neighbor_direction(direction: int) -> int:
    """Map axial neighbor direction 0..5 to local edge index 0..5."""
    return (direction - 1) % 6


def neighbor_axial(q: int, r: int, direction: int) -> tuple[int, int]:
    dq, dr = NEIGHBOR_DIRS[direction]
    return q + dq, r + dr


def pos_key(x: float, y: float, precision: int = 6) -> tuple[float, float]:
    return (round(x, precision), round(y, precision))


def build_hex_level_lookup() -> dict[tuple[int, int], int]:
    return {(q, r): level for q, r, level, _label in PROTOTYPE_HEXES}


def edge_blend_level(
    q: int,
    r: int,
    direction: int,
    hex_levels: dict[tuple[int, int], int],
) -> float:
    """Two-hex edge blend in level units (before ELEVATION_STEP)."""
    self_level = hex_levels[(q, r)]
    dq, dr = NEIGHBOR_DIRS[direction]
    nk = (q + dq, r + dr)
    if nk not in hex_levels:
        return float(self_level)
    return (float(self_level) + float(hex_levels[nk])) * 0.5


def build_corner_height_map(
    hex_levels: dict[tuple[int, int], int],
) -> dict[tuple[float, float], float]:
    """
    Shared lattice-corner heights: average elevation of every hex that touches
    the corner. Two hexes → halfway blend; three hexes → triple average.

    In a 7-hex cluster, outer lattice corners where plain + hill + plain meet
    become (0+1+0)/3 in level units — not the pure two-hex 0.5 midpoint.
    That yields a shared sloped rim (no vertical cliff) when both meshes use
    the same keyed corner Z.
    """
    contributors: dict[tuple[float, float], list[int]] = {}
    for q, r, level, _label in PROTOTYPE_HEXES:
        cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
        for ci in range(6):
            lx, ly = corner_xy_local(ci, HEX_RADIUS)
            wx, wy = cx + lx, cy + ly
            key = pos_key(wx, wy)
            contributors.setdefault(key, []).append(level)

    return {
        key: sum(levels) / float(len(levels)) * ELEVATION_STEP
        for key, levels in contributors.items()
    }


def validate_surface_params() -> None:
    if not isinstance(SURFACE_SUBDIVISIONS, int) or SURFACE_SUBDIVISIONS < 1:
        raise ValueError(
            f"SURFACE_SUBDIVISIONS must be an integer >= 1, got {SURFACE_SUBDIVISIONS!r}"
        )
    if not (0.0 <= INNER_FLAT_RADIUS_FACTOR < 1.0):
        raise ValueError(
            f"INNER_FLAT_RADIUS_FACTOR must be in [0.0, 1.0), got {INNER_FLAT_RADIUS_FACTOR!r}"
        )
    if HEIGHT_PROFILE not in ("linear", "smoothstep", "ease_in_cubic", "quadratic"):
        raise ValueError(
            f"HEIGHT_PROFILE must be 'linear', 'smoothstep', 'ease_in_cubic', or 'quadratic', "
            f"got {HEIGHT_PROFILE!r}"
        )


def height_profile_weight(t: float) -> float:
    t_clamped = max(0.0, min(1.0, t))
    if HEIGHT_PROFILE == "linear":
        return t_clamped
    if HEIGHT_PROFILE == "smoothstep":
        return t_clamped * t_clamped * (3.0 - 2.0 * t_clamped)
    if HEIGHT_PROFILE == "ease_in_cubic":
        return t_clamped * t_clamped * (2.0 - t_clamped)
    if HEIGHT_PROFILE == "quadratic":
        return t_clamped * t_clamped
    return t_clamped * t_clamped * (3.0 - 2.0 * t_clamped)


def analytic_surface_height(
    center_height: float,
    edge_height: float,
    radial: float,
) -> float:
    if radial <= INNER_FLAT_RADIUS_FACTOR:
        return center_height
    denom = 1.0 - INNER_FLAT_RADIUS_FACTOR
    t = (radial - INNER_FLAT_RADIUS_FACTOR) / denom
    t = max(0.0, min(1.0, t))
    profile = height_profile_weight(t)
    return center_height + (edge_height - center_height) * profile


def sector_barycentric_xy(
    sector: int,
    si: int,
    sj: int,
    subdiv: int,
) -> tuple[float, float, float, float]:
    """
    Barycentric grid in sector `sector` (triangle: center, corner i, corner i+1).
    si, sj >= 0, si + sj <= subdiv. Returns local lx, ly, radial [0..1], edge_t [0..1].
    """
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, HEX_RADIUS)
    cx, cy = corner_xy_local(cj, HEX_RADIUS)
    denom = float(subdiv)
    wb = float(si) / denom
    wc = float(sj) / denom
    lx = wb * bx + wc * cx
    ly = wb * by + wc * cy
    # Barycentric radial: 0 at center, 1 anywhere on the outer chord (corner i → corner i+1).
    radial = (float(si) + float(sj)) / denom
    edge_t = (float(sj) / float(si + sj)) if (si + sj) > 0 else 0.0
    return lx, ly, radial, edge_t


def sector_edge_height(
    q: int,
    r: int,
    sector: int,
    edge_t: float,
    corner_heights: dict[tuple[float, float], float],
) -> float:
    ci = sector
    cj = (sector + 1) % 6
    hi = corner_heights[corner_world_key(q, r, ci)]
    hj = corner_heights[corner_world_key(q, r, cj)]
    return hi * (1.0 - edge_t) + hj * edge_t


def subdivided_outer_edge_world(
    q: int,
    r: int,
    sector: int,
    step_k: int,
    corner_heights: dict[tuple[float, float], float],
    level: int,
) -> tuple[float, float, float, tuple[float, float]]:
    """Sample k=0..SURFACE_SUBDIVISIONS along sector outer edge (corner i → corner i+1)."""
    subdiv = SURFACE_SUBDIVISIONS
    si = subdiv - step_k
    sj = step_k
    lx, ly, radial, edge_t = sector_barycentric_xy(sector, si, sj, subdiv)
    cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
    wx, wy = cx + lx, cy + ly
    center_height = level_to_z(level)
    edge_height = sector_edge_height(q, r, sector, edge_t, corner_heights)
    wz = analytic_surface_height(center_height, edge_height, radial)
    return wx, wy, wz, pos_key(wx, wy)


def _remove_unused_datablocks(block_collection) -> None:
    for block in list(block_collection):
        if block.users == 0:
            block_collection.remove(block)


def clear_scene() -> None:
    """Context-independent scene reset (no bpy.ops)."""
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

    # World-consistent noise via object-space coordinates (shared material instance).
    tex_coord = _new_node(nodes, "ShaderNodeTexCoord")
    tex_coord.location = (-900, 0)

    mapping = _new_node(nodes, "ShaderNodeMapping")
    mapping.location = (-700, 0)
    _require_input(mapping, "Scale").default_value = (0.35, 0.35, 0.35)

    noise = _new_node(nodes, "ShaderNodeTexNoise")
    noise.location = (-500, 100)
    _require_input(noise, "Scale").default_value = 2.2
    _require_input(noise, "Detail").default_value = 4.0

    layer_weight = _new_node(nodes, "ShaderNodeLayerWeight")
    layer_weight.location = (-500, -120)
    _require_input(layer_weight, "Blend").default_value = 0.35

    ramp = _new_node(nodes, "ShaderNodeValToRGB")
    ramp.location = (-300, 100)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.12, 0.16, 0.08, 1.0)  # dark earth green
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (0.28, 0.24, 0.14, 1.0)  # lighter soil

    slope_dark = _new_node(nodes, "ShaderNodeRGB")
    slope_dark.location = (-300, -220)
    _require_output(slope_dark, "Color").default_value = (0.08, 0.09, 0.07, 1.0)

    # Blender 4.x/5.x: ShaderNodeMixRGB removed → ShaderNodeMix (RGBA).
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


def build_hex_mesh(
    q: int,
    r: int,
    level: int,
    terrain_label: str,
    corner_heights: dict[tuple[float, float], float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> tuple[bpy.types.Object, dict]:
    cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
    center_height = level_to_z(level)
    bottom_z = -BASE_THICKNESS
    subdiv = SURFACE_SUBDIVISIONS

    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    top_cache: dict[tuple[float, float], int] = {}
    bottom_cache: dict[tuple[float, float], int] = {}
    sector_grid: list[dict[tuple[int, int], int]] = []

    def add_top_vertex(wx: float, wy: float, wz: float) -> int:
        key = pos_key(wx, wy)
        cached = top_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, wz))
        top_cache[key] = idx
        return idx

    def add_bottom_vertex(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        cached = bottom_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, bottom_z))
        bottom_cache[key] = idx
        return idx

    for sector in range(6):
        grid: dict[tuple[int, int], int] = {}
        for si in range(subdiv + 1):
            sj_max = subdiv - si
            sj = 0
            while sj <= sj_max:
                lx, ly, radial, edge_t = sector_barycentric_xy(sector, si, sj, subdiv)
                wx = cx + lx
                wy = cy + ly
                edge_height = sector_edge_height(q, r, sector, edge_t, corner_heights)
                wz = analytic_surface_height(center_height, edge_height, radial)
                grid[(si, sj)] = add_top_vertex(wx, wy, wz)
                sj += 1
        sector_grid.append(grid)

        # Top triangles (CCW from +Z).
        for si in range(subdiv):
            sj = 0
            while sj <= subdiv - si - 1:
                v00 = grid[(si, sj)]
                v10 = grid[(si + 1, sj)]
                v01 = grid[(si, sj + 1)]
                faces.append((v00, v10, v01))
                if sj + 1 <= subdiv - (si + 1):
                    v11 = grid[(si + 1, sj + 1)]
                    faces.append((v10, v01, v11))
                sj += 1

        # Side walls along outer sector edge (subdivided top → bottom).
        for step_k in range(subdiv):
            si_a = subdiv - step_k
            sj_a = step_k
            si_b = subdiv - step_k - 1
            sj_b = step_k + 1
            top_a = grid[(si_a, sj_a)]
            top_b = grid[(si_b, sj_b)]
            wx_a, wy_a, _ = verts[top_a]
            wx_b, wy_b, _ = verts[top_b]
            bot_a = add_bottom_vertex(wx_a, wy_a)
            bot_b = add_bottom_vertex(wx_b, wy_b)
            faces.append((top_a, top_b, bot_b, bot_a))

    center_bottom = len(verts)
    verts.append((cx, cy, bottom_z))

    # Bottom cap: fan per sector along subdivided outer ring.
    for sector in range(6):
        grid = sector_grid[sector]
        for step_k in range(subdiv):
            si_a = subdiv - step_k
            sj_a = step_k
            si_b = subdiv - step_k - 1
            sj_b = step_k + 1
            wx_a, wy_a, _ = verts[grid[(si_a, sj_a)]]
            wx_b, wy_b, _ = verts[grid[(si_b, sj_b)]]
            bot_a = bottom_cache[pos_key(wx_a, wy_a)]
            bot_b = bottom_cache[pos_key(wx_b, wy_b)]
            faces.append((center_bottom, bot_b, bot_a))

    mesh = bpy.data.meshes.new(f"HexMesh_{q}_{r}")
    mesh.from_pydata(verts, [], faces)
    _finalize_mesh(mesh)

    obj_name = f"Hex_{q}_{r}_{terrain_label}"
    obj = bpy.data.objects.new(obj_name, mesh)
    obj.data.materials.append(material)
    collection.objects.link(obj)
    stats = {"verts": len(verts), "faces": len(faces)}
    return obj, stats


def setup_camera_and_lights() -> None:
    scene = _active_scene()
    cam_data = bpy.data.cameras.new(CAMERA_NAME)
    cam_obj = bpy.data.objects.new(CAMERA_NAME, cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    # Oblique strategy-style overview.
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
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    override = _ops_context_override()
    if SAVE_BLEND:
        with bpy.context.temp_override(**override):
            bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND_PATH)
        _log(f"saved blend: {OUTPUT_BLEND_PATH}")
    if EXPORT_GLB:
        with bpy.context.temp_override(**override):
            bpy.ops.export_scene.gltf(
                filepath=OUTPUT_GLB_PATH,
                export_format="GLB",
                use_selection=False,
            )
        _log(f"exported GLB: {OUTPUT_GLB_PATH}")


WORLD_XY_TOLERANCE = 1e-5
WORLD_Z_TOLERANCE = 1e-5


def opposite_neighbor_direction(direction: int) -> int:
    return (direction + 3) % 6


def corner_world_key(q: int, r: int, corner_index: int, radius: float = HEX_RADIUS) -> tuple[float, float]:
    cx, cy = axial_to_world_xy(q, r, radius)
    lx, ly = corner_xy_local(corner_index, radius)
    return pos_key(cx + lx, cy + ly)


def edge_endpoint_keys(q: int, r: int, edge_index: int, radius: float = HEX_RADIUS) -> frozenset:
    """World XY keys for the two corners bounding edge_index (order-independent)."""
    return frozenset(
        {
            corner_world_key(q, r, edge_index, radius),
            corner_world_key(q, r, (edge_index + 1) % 6, radius),
        }
    )


def log_shared_edge_check(
    hex_levels: dict[tuple[int, int], int],
    corner_heights: dict[tuple[float, float], float],
) -> None:
    """Sanity log for center ↔ east hill shared geometry."""
    two_hex_blend = edge_blend_level(0, 0, 0, hex_levels) * ELEVATION_STEP
    _log(
        f"two-hex east edge blend (plain/hill only): Z ≈ {two_hex_blend:.4f}"
    )

    center_q, center_r = 0, 0
    east_q, east_r = 1, 0
    east_dir = 0  # center → east
    west_dir = opposite_neighbor_direction(east_dir)  # east → center (3)

    edge_center = edge_index_for_neighbor_direction(east_dir)  # 5: corners 5–0
    edge_east = edge_index_for_neighbor_direction(west_dir)  # 2: corners 2–3

    cx0, cy0 = axial_to_world_xy(center_q, center_r, HEX_RADIUS)
    cx1, cy1 = axial_to_world_xy(east_q, east_r, HEX_RADIUS)
    center_distance = math.hypot(cx1 - cx0, cy1 - cy0)
    expected_distance = math.sqrt(3.0) * HEX_RADIUS
    assert abs(center_distance - expected_distance) < WORLD_XY_TOLERANCE, (
        f"center/east distance {center_distance:.6f} != "
        f"sqrt(3)*R {expected_distance:.6f}"
    )
    _log(
        f"center↔east distance: {center_distance:.6f} "
        f"(expected {expected_distance:.6f})"
    )

    center_keys = edge_endpoint_keys(center_q, center_r, edge_center)
    east_keys = edge_endpoint_keys(east_q, east_r, edge_east)
    assert center_keys == east_keys, (
        "center/east shared-edge XY mismatch: "
        f"center edge {edge_center} keys {sorted(center_keys)} vs "
        f"east edge {edge_east} keys {sorted(east_keys)}"
    )

    _log(
        f"shared physical edge: center edge {edge_center} corners "
        f"({edge_center}, {(edge_center + 1) % 6}) ↔ east edge {edge_east} "
        f"corners ({edge_east}, {(edge_east + 1) % 6})"
    )

    for key in sorted(center_keys):
        assert key in corner_heights, f"missing corner height for {key}"
        z = corner_heights[key]
        _log(
            f"shared lattice corner {key}: Z={z:.4f} "
            f"(3-hex avg where plain+hill+plain meet)"
        )

    # Subdivided samples along the full shared edge (center sector 5 ↔ east sector 2).
    subdiv = SURFACE_SUBDIVISIONS
    center_samples = [
        subdivided_outer_edge_world(
            center_q, center_r, edge_center, step_k, corner_heights, hex_levels[(center_q, center_r)]
        )
        for step_k in range(subdiv + 1)
    ]
    east_samples = [
        subdivided_outer_edge_world(
            east_q, east_r, edge_east, step_k, corner_heights, hex_levels[(east_q, east_r)]
        )
        for step_k in range(subdiv + 1)
    ]
    assert len(center_samples) == len(east_samples), "subdivided edge sample count mismatch"
    _log(f"subdivided shared-edge samples: {len(center_samples)} per hex")

    for step_k in range(subdiv + 1):
        rev_k = subdiv - step_k
        wx_c, wy_c, wz_c, _ = center_samples[step_k]
        wx_e, wy_e, wz_e, _ = east_samples[rev_k]
        assert abs(wx_c - wx_e) < WORLD_XY_TOLERANCE, (
            f"subdivided edge XY mismatch at step {step_k}: "
            f"center ({wx_c:.6f},{wy_c:.6f}) vs east ({wx_e:.6f},{wy_e:.6f})"
        )
        assert abs(wy_c - wy_e) < WORLD_XY_TOLERANCE, (
            f"subdivided edge Y mismatch at step {step_k}"
        )
        assert abs(wz_c - wz_e) < WORLD_Z_TOLERANCE, (
            f"subdivided edge Z mismatch at step {step_k}: "
            f"center {wz_c:.6f} vs east {wz_e:.6f}"
        )

    _log("shared-edge validation passed (corners + subdivided edge chain)")


def main() -> None:
    validate_surface_params()
    _log(f"Blender version: {_blender_version_label()}")
    _log("generating 7-hex flat-top prototype…")
    _log(f"repo root: {REPO_ROOT}")
    _log(f"surface subdivisions: {SURFACE_SUBDIVISIONS}")
    _log(f"inner flat radius factor: {INNER_FLAT_RADIUS_FACTOR}")
    _log(f"height profile: {HEIGHT_PROFILE}")

    clear_scene()
    coll = ensure_collection(COLLECTION_NAME)
    material = make_terrain_material()
    _log("material created")

    hex_levels = build_hex_level_lookup()
    corner_heights = build_corner_height_map(hex_levels)
    log_shared_edge_check(hex_levels, corner_heights)

    total_verts = 0
    total_faces = 0
    for q, r, level, terrain_label in PROTOTYPE_HEXES:
        _obj, stats = build_hex_mesh(q, r, level, terrain_label, corner_heights, material, coll)
        total_verts += stats["verts"]
        total_faces += stats["faces"]
        _log(
            f"hex ({q},{r}) {terrain_label}: "
            f"{stats['verts']} verts, {stats['faces']} faces"
        )
    _log(
        f"meshes created: {len(PROTOTYPE_HEXES)}; "
        f"total {total_verts} verts, {total_faces} faces"
    )

    setup_camera_and_lights()
    setup_render_and_world()
    save_outputs()
    _log("done")


if __name__ == "__main__":
    main()
