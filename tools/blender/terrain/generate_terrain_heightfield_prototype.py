# Empire of Minds — 7-hex flat-top terrain heightfield prototype (Blender only).
# Run from Blender Scripting workspace: Open this file → Run Script.
# Requires bpy (not available outside Blender).
#
# Milestone note: the per-hex analytic prototype remains in generate_terrain_prototype.py.

import math
import os

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

SURFACE_SUBDIVISIONS = 8

# Global patch heightfield (inverse-distance weighted hex-center influences).
HEIGHTFIELD_MODE = "idw"
HEIGHTFIELD_FALLOFF = 2.0
HEIGHTFIELD_EPSILON = 1e-6

# Optional mild top flattening near hex centers (default off — no artificial plateau).
HEIGHT_PROFILE = "quadratic"
TOP_FLATTEN_STRENGTH = 0.0
TOP_FLATTEN_RADIUS = 0.0

# Exposed outer perimeter: lower top edge slightly for a softer exterior silhouette.
OUTER_RIM_SOFTENING = 0.25
OUTER_RIM_FALLOFF = 1.5

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
OUTPUT_BLEND_PATH = os.path.join(OUTPUT_DIR, "terrain_prototype_7_hex_heightfield.blend")
OUTPUT_GLB_PATH = os.path.join(OUTPUT_DIR, "terrain_prototype_7_hex_heightfield.glb")

SAVE_BLEND = True
EXPORT_GLB = False

COLLECTION_NAME = "EOM_Terrain_Heightfield_Prototype"
MATERIAL_NAME = "EOM_Terrain_Heightfield_Prototype"
CAMERA_NAME = "PrototypeHeightfieldCamera"
SUN_NAME = "PrototypeHeightfieldSun"

WORLD_XY_TOLERANCE = 1e-5
WORLD_Z_TOLERANCE = 1e-5


def _log(message: str) -> None:
    print(f"[EOM terrain heightfield] {message}")


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


# ---------------------------------------------------------------------------
# Axial hex grid (flat-top, Red Blob Games convention)
# ---------------------------------------------------------------------------

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
    (1, 0, HILL_LEVEL, "Hill"),
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
    if HEIGHTFIELD_MODE not in ("idw",):
        raise ValueError(
            f"HEIGHTFIELD_MODE must be 'idw', got {HEIGHTFIELD_MODE!r}"
        )
    if HEIGHTFIELD_FALLOFF <= 0.0:
        raise ValueError(
            f"HEIGHTFIELD_FALLOFF must be > 0, got {HEIGHTFIELD_FALLOFF!r}"
        )
    if HEIGHTFIELD_EPSILON <= 0.0:
        raise ValueError(
            f"HEIGHTFIELD_EPSILON must be > 0, got {HEIGHTFIELD_EPSILON!r}"
        )
    if HEIGHT_PROFILE not in ("linear", "smoothstep", "ease_in_cubic", "quadratic"):
        raise ValueError(
            f"HEIGHT_PROFILE must be 'linear', 'smoothstep', 'ease_in_cubic', or 'quadratic', "
            f"got {HEIGHT_PROFILE!r}"
        )
    if not (0.0 <= TOP_FLATTEN_STRENGTH <= 1.0):
        raise ValueError(
            f"TOP_FLATTEN_STRENGTH must be in [0, 1], got {TOP_FLATTEN_STRENGTH!r}"
        )
    if not (0.0 <= TOP_FLATTEN_RADIUS < 1.0):
        raise ValueError(
            f"TOP_FLATTEN_RADIUS must be in [0, 1), got {TOP_FLATTEN_RADIUS!r}"
        )
    if OUTER_RIM_SOFTENING < 0.0:
        raise ValueError(
            f"OUTER_RIM_SOFTENING must be >= 0, got {OUTER_RIM_SOFTENING!r}"
        )
    if OUTER_RIM_FALLOFF <= 0.0:
        raise ValueError(
            f"OUTER_RIM_FALLOFF must be > 0, got {OUTER_RIM_FALLOFF!r}"
        )


def level_to_z(level: float) -> float:
    return level * ELEVATION_STEP


def axial_to_world_xy(q: int, r: int, radius: float) -> tuple[float, float]:
    x = radius * math.sqrt(3.0) * (float(q) + float(r) * 0.5)
    y = radius * 1.5 * float(r)
    return x, y


def corner_xy_local(corner_index: int, radius: float) -> tuple[float, float]:
    angle_deg = 60.0 * float(corner_index) + 30.0
    angle_rad = math.radians(angle_deg)
    return radius * math.cos(angle_rad), radius * math.sin(angle_rad)


def edge_index_for_neighbor_direction(direction: int) -> int:
    """Physical edge index shared with axial neighbor direction 0..5 (flat-top)."""
    return (5 - direction) % 6


def neighbor_direction_for_physical_edge(edge_index: int) -> int:
    """Axial neighbor direction across physical edge (corner i → corner i+1)."""
    return (5 - edge_index) % 6


def opposite_neighbor_direction(direction: int) -> int:
    return (direction + 3) % 6


def pos_key(x: float, y: float, precision: int = 6) -> tuple[float, float]:
    return (round(x, precision), round(y, precision))


def build_hex_level_lookup() -> dict[tuple[int, int], int]:
    return {(q, r): level for q, r, level, _label in PROTOTYPE_HEXES}


def build_hex_coords_set(hex_levels: dict[tuple[int, int], int]) -> set[tuple[int, int]]:
    return set(hex_levels.keys())


def has_neighbor(
    q: int,
    r: int,
    direction: int,
    hex_coords: set[tuple[int, int]],
) -> bool:
    dq, dr = NEIGHBOR_DIRS[direction]
    return (q + dq, r + dr) in hex_coords


def classify_hex_edge(
    q: int,
    r: int,
    edge_index: int,
    hex_coords: set[tuple[int, int]],
) -> str:
    direction = neighbor_direction_for_physical_edge(edge_index)
    if has_neighbor(q, r, direction, hex_coords):
        return "internal_shared_edge"
    return "exposed_patch_edge"


def is_exposed_edge(
    q: int,
    r: int,
    edge_index: int,
    hex_coords: set[tuple[int, int]],
) -> bool:
    return classify_hex_edge(q, r, edge_index, hex_coords) == "exposed_patch_edge"


def build_hex_influences() -> list[tuple[float, float, float]]:
    """Hex centers as (world_x, world_y, level) for global heightfield."""
    return [
        (*axial_to_world_xy(q, r, HEX_RADIUS), float(level))
        for q, r, level, _label in PROTOTYPE_HEXES
    ]


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


def sample_heightfield_level(wx: float, wy: float, influences: list[tuple[float, float, float]]) -> float:
    """
    IDW blend of hex-center levels:
      w_i = 1 / (d_i + epsilon)^p
      level = sum(w_i * level_i) / sum(w_i)
    """
    weight_sum = 0.0
    level_sum = 0.0
    for cx, cy, level in influences:
        dist = math.hypot(wx - cx, wy - cy)
        weight = 1.0 / (dist + HEIGHTFIELD_EPSILON) ** HEIGHTFIELD_FALLOFF
        weight_sum += weight
        level_sum += weight * level
    if weight_sum <= 0.0:
        raise RuntimeError("heightfield weight sum is zero")
    return level_sum / weight_sum


def sample_heightfield(wx: float, wy: float, influences: list[tuple[float, float, float]]) -> float:
    level = sample_heightfield_level(wx, wy, influences)
    return level_to_z(level)


def apply_top_flatten(
    wx: float,
    wy: float,
    wz: float,
    influences: list[tuple[float, float, float]],
) -> float:
    """Optional mild flattening near hex centers (disabled when strength or radius is 0)."""
    if TOP_FLATTEN_STRENGTH <= 0.0 or TOP_FLATTEN_RADIUS <= 0.0:
        return wz
    best_strength = 0.0
    best_target = wz
    for cx, cy, level in influences:
        dist = math.hypot(wx - cx, wy - cy) / HEX_RADIUS
        if dist >= TOP_FLATTEN_RADIUS:
            continue
        t = dist / TOP_FLATTEN_RADIUS
        local = 1.0 - height_profile_weight(t)
        if local > best_strength:
            best_strength = local
            best_target = level_to_z(level)
    if best_strength <= 0.0:
        return wz
    blend = TOP_FLATTEN_STRENGTH * best_strength
    return wz + (best_target - wz) * blend


def compute_rim_softened_z(wz_top: float, edge_t: float) -> float:
    """Rim perimeter layer only — does not alter main top heightfield samples."""
    if OUTER_RIM_SOFTENING <= 0.0:
        return wz_top
    bulge = 4.0 * edge_t * (1.0 - edge_t)
    drop = OUTER_RIM_SOFTENING * ELEVATION_STEP * (bulge ** OUTER_RIM_FALLOFF)
    return wz_top - drop


def sample_top_surface_height(
    wx: float,
    wy: float,
    influences: list[tuple[float, float, float]],
) -> float:
    """Main top surface: global heightfield only (no rim softening)."""
    wz = sample_heightfield(wx, wy, influences)
    return apply_top_flatten(wx, wy, wz, influences)


def sector_barycentric_xy(
    sector: int,
    si: int,
    sj: int,
    subdiv: int,
) -> tuple[float, float, float, float]:
    ci = sector
    cj = (sector + 1) % 6
    bx, by = corner_xy_local(ci, HEX_RADIUS)
    cx, cy = corner_xy_local(cj, HEX_RADIUS)
    denom = float(subdiv)
    wb = float(si) / denom
    wc = float(sj) / denom
    lx = wb * bx + wc * cx
    ly = wb * by + wc * cy
    radial = (float(si) + float(sj)) / denom
    edge_t = (float(sj) / float(si + sj)) if (si + sj) > 0 else 0.0
    return lx, ly, radial, edge_t


def outer_edge_barycentric_indices(step_k: int, subdiv: int) -> tuple[int, int, float]:
    """Ordered sample k=0..subdiv along physical edge (corner i → corner i+1)."""
    si = subdiv - step_k
    sj = step_k
    edge_t = float(step_k) / float(subdiv)
    return si, sj, edge_t


def subdivided_edge_world_xy(
    q: int,
    r: int,
    edge_index: int,
    step_k: int,
    subdiv: int,
) -> tuple[float, float, float]:
    si, sj, edge_t = outer_edge_barycentric_indices(step_k, subdiv)
    lx, ly, _, _ = sector_barycentric_xy(edge_index, si, sj, subdiv)
    cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
    return cx + lx, cy + ly, edge_t


def subdivided_shared_edge_world(
    q: int,
    r: int,
    edge_index: int,
    step_k: int,
    influences: list[tuple[float, float, float]],
) -> tuple[float, float, float]:
    subdiv = SURFACE_SUBDIVISIONS
    wx, wy, _ = subdivided_edge_world_xy(q, r, edge_index, step_k, subdiv)
    wz = sample_top_surface_height(wx, wy, influences)
    return wx, wy, wz


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

    layer_weight = _new_node(nodes, "ShaderNodeLayerWeight")
    layer_weight.location = (-500, -120)
    _require_input(layer_weight, "Blend").default_value = 0.35

    ramp = _new_node(nodes, "ShaderNodeValToRGB")
    ramp.location = (-300, 100)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.12, 0.16, 0.08, 1.0)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (0.28, 0.24, 0.14, 1.0)

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


def build_hex_mesh(
    q: int,
    r: int,
    level: int,
    terrain_label: str,
    influences: list[tuple[float, float, float]],
    hex_coords: set[tuple[int, int]],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> tuple[bpy.types.Object, dict]:
    cx, cy = axial_to_world_xy(q, r, HEX_RADIUS)
    bottom_z = -BASE_THICKNESS
    subdiv = SURFACE_SUBDIVISIONS

    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    top_cache: dict[tuple[float, float], int] = {}
    bottom_cache: dict[tuple[float, float], int] = {}
    rim_cache: dict[tuple[float, float], int] = {}
    sector_grid: list[dict[tuple[int, int], int]] = []

    skirt_faces = 0
    chamfer_faces = 0
    internal_edge_count = 0
    exposed_edge_count = 0

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

    def add_rim_vertex(wx: float, wy: float, wz_rim: float) -> int:
        key = pos_key(wx, wy)
        cached = rim_cache.get(key)
        if cached is not None:
            return cached
        idx = len(verts)
        verts.append((wx, wy, wz_rim))
        rim_cache[key] = idx
        return idx

    # --- Top surface (full hex; heightfield only, no rim on top layer) ---
    for sector in range(6):
        grid: dict[tuple[int, int], int] = {}
        for si in range(subdiv + 1):
            sj_max = subdiv - si
            sj = 0
            while sj <= sj_max:
                lx, ly, _radial, _edge_t = sector_barycentric_xy(sector, si, sj, subdiv)
                wx = cx + lx
                wy = cy + ly
                wz = sample_top_surface_height(wx, wy, influences)
                grid[(si, sj)] = add_top_vertex(wx, wy, wz)
                sj += 1
        sector_grid.append(grid)

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

    for sector in range(6):
        if classify_hex_edge(q, r, sector, hex_coords) == "internal_shared_edge":
            internal_edge_count += 1
        else:
            exposed_edge_count += 1

    # --- Exposed perimeter: ordered rim + skirt (no geometry on internal edges) ---
    for sector in range(6):
        if not is_exposed_edge(q, r, sector, hex_coords):
            continue

        grid = sector_grid[sector]
        for step_k in range(subdiv):
            si_a, sj_a, edge_t_a = outer_edge_barycentric_indices(step_k, subdiv)
            si_b, sj_b, edge_t_b = outer_edge_barycentric_indices(step_k + 1, subdiv)

            top_a = grid[(si_a, sj_a)]
            top_b = grid[(si_b, sj_b)]
            wx_a, wy_a, wz_top_a = verts[top_a]
            wx_b, wy_b, wz_top_b = verts[top_b]

            wz_rim_a = compute_rim_softened_z(wz_top_a, edge_t_a)
            wz_rim_b = compute_rim_softened_z(wz_top_b, edge_t_b)
            rim_a = add_rim_vertex(wx_a, wy_a, wz_rim_a)
            rim_b = add_rim_vertex(wx_b, wy_b, wz_rim_b)

            bot_a = add_bottom_vertex(wx_a, wy_a)
            bot_b = add_bottom_vertex(wx_b, wy_b)

            if OUTER_RIM_SOFTENING > 0.0 and rim_a != top_a:
                faces.append((top_a, top_b, rim_b, rim_a))
                chamfer_faces += 1
                faces.append((rim_a, rim_b, bot_b, bot_a))
            else:
                faces.append((top_a, top_b, bot_b, bot_a))
            skirt_faces += 1

    # --- Bottom cap (entire hex perimeter; no side walls on internal edges) ---
    center_bottom = len(verts)
    verts.append((cx, cy, bottom_z))

    for sector in range(6):
        grid = sector_grid[sector]
        for step_k in range(subdiv):
            si_a, sj_a, _ = outer_edge_barycentric_indices(step_k, subdiv)
            si_b, sj_b, _ = outer_edge_barycentric_indices(step_k + 1, subdiv)
            wx_a, wy_a, _ = verts[grid[(si_a, sj_a)]]
            wx_b, wy_b, _ = verts[grid[(si_b, sj_b)]]
            add_bottom_vertex(wx_a, wy_a)
            add_bottom_vertex(wx_b, wy_b)
            bot_a = bottom_cache[pos_key(wx_a, wy_a)]
            bot_b = bottom_cache[pos_key(wx_b, wy_b)]
            faces.append((center_bottom, bot_b, bot_a))

    # --- Mesh sanity ---
    for face in faces:
        assert len(set(face)) == len(face), f"degenerate face in hex ({q},{r}): {face}"

    mesh = bpy.data.meshes.new(f"HexMeshHF_{q}_{r}")
    mesh.from_pydata(verts, [], faces)
    _finalize_mesh(mesh)

    obj_name = f"HexHF_{q}_{r}_{terrain_label}"
    obj = bpy.data.objects.new(obj_name, mesh)
    obj.data.materials.append(material)
    collection.objects.link(obj)
    stats = {
        "verts": len(verts),
        "faces": len(faces),
        "skirt_faces": skirt_faces,
        "chamfer_faces": chamfer_faces,
        "rim_verts": len(rim_cache),
        "internal_edges": internal_edge_count,
        "exposed_edges": exposed_edge_count,
    }
    return obj, stats


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

    area_data = bpy.data.lights.new("PrototypeHeightfieldFill", type="AREA")
    area_data.energy = 120.0
    area_data.size = 6.0
    area_obj = bpy.data.objects.new("PrototypeHeightfieldFill", area_data)
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

    world = bpy.data.worlds.get("EOM_Terrain_Heightfield_World")
    if world is None:
        world = bpy.data.worlds.new("EOM_Terrain_Heightfield_World")
    scene.world = world
    world.use_nodes = True
    world_tree = world.node_tree
    if world_tree is None:
        raise RuntimeError("EOM_Terrain_Heightfield_World has no node tree")

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


def log_heightfield_config(influences: list[tuple[float, float, float]]) -> None:
    _log(
        f"global heightfield configured: mode={HEIGHTFIELD_MODE}, "
        f"falloff={HEIGHTFIELD_FALLOFF}, epsilon={HEIGHTFIELD_EPSILON}"
    )
    _log(
        f"top flatten: strength={TOP_FLATTEN_STRENGTH}, radius={TOP_FLATTEN_RADIUS}, "
        f"profile={HEIGHT_PROFILE}"
    )
    _log(
        f"outer rim softening: strength={OUTER_RIM_SOFTENING}, "
        f"falloff={OUTER_RIM_FALLOFF}"
    )
    for cx, cy, level in influences:
        _log(f"  influence center ({cx:.3f},{cy:.3f}) level={level:.1f}")


def log_center_to_east_profile(influences: list[tuple[float, float, float]]) -> None:
    """Diagnostic: sample heights along center → east hill center line."""
    cx0, cy0 = axial_to_world_xy(0, 0, HEX_RADIUS)
    cx1, cy1 = axial_to_world_xy(1, 0, HEX_RADIUS)
    prev_z: float | None = None
    for i in range(5):
        t = float(i) / 4.0
        wx = cx0 + t * (cx1 - cx0)
        wy = cy0 + t * (cy1 - cy0)
        z = sample_heightfield(wx, wy, influences)
        level = z / ELEVATION_STEP
        _log(
            f"center→east profile t={t:.2f}: ({wx:.4f},{wy:.4f}) "
            f"level={level:.4f} Z={z:.4f}"
        )
        if prev_z is not None and z < prev_z - 1e-6:
            _log(
                f"warning: height dip between t={t - 0.25:.2f} and t={t:.2f} "
                f"({prev_z:.4f} → {z:.4f})"
            )
        prev_z = z


def log_edge_classification_audit(hex_coords: set[tuple[int, int]]) -> dict[str, int]:
    """Deterministic axial-neighbor audit for all seven hexes."""
    totals = {"internal_shared_edge": 0, "exposed_patch_edge": 0}
    for q, r, _level, label in PROTOTYPE_HEXES:
        internal_edges: list[int] = []
        exposed_edges: list[int] = []
        for edge_index in range(6):
            kind = classify_hex_edge(q, r, edge_index, hex_coords)
            totals[kind] += 1
            if kind == "internal_shared_edge":
                internal_edges.append(edge_index)
            else:
                exposed_edges.append(edge_index)
        _log(
            f"hex ({q},{r}) {label}: internal edges {internal_edges}, "
            f"exposed edges {exposed_edges}"
        )
    _log(
        f"edge audit totals: {totals['internal_shared_edge']} internal, "
        f"{totals['exposed_patch_edge']} exposed "
        f"(expect 24 internal + 18 exposed for 7-hex cluster)"
    )
    assert totals["internal_shared_edge"] == 24, (
        f"unexpected internal edge count {totals['internal_shared_edge']}"
    )
    assert totals["exposed_patch_edge"] == 18, (
        f"unexpected exposed edge count {totals['exposed_patch_edge']}"
    )
    return totals


def validate_internal_edge_symmetry(hex_coords: set[tuple[int, int]]) -> None:
    """Each internal edge must be internal from both adjacent hexes."""
    for q, r in hex_coords:
        for edge_index in range(6):
            if classify_hex_edge(q, r, edge_index, hex_coords) != "internal_shared_edge":
                continue
            direction = neighbor_direction_for_physical_edge(edge_index)
            dq, dr = NEIGHBOR_DIRS[direction]
            nq, nr = q + dq, r + dr
            assert (nq, nr) in hex_coords, (
                f"internal edge ({q},{r}) edge {edge_index} missing neighbor"
            )
            neighbor_edge = edge_index_for_neighbor_direction(
                opposite_neighbor_direction(direction)
            )
            neighbor_kind = classify_hex_edge(nq, nr, neighbor_edge, hex_coords)
            assert neighbor_kind == "internal_shared_edge", (
                f"asymmetric edge: ({q},{r}) edge {edge_index} internal but "
                f"({nq},{nr}) edge {neighbor_edge} is {neighbor_kind}"
            )
    _log("internal edge symmetry validation passed")


def log_shared_edge_check(
    influences: list[tuple[float, float, float]],
    hex_coords: set[tuple[int, int]],
) -> None:
    center_q, center_r = 0, 0
    east_q, east_r = 1, 0
    east_dir = 0
    west_dir = opposite_neighbor_direction(east_dir)

    edge_center = edge_index_for_neighbor_direction(east_dir)
    edge_east = edge_index_for_neighbor_direction(west_dir)

    assert classify_hex_edge(center_q, center_r, edge_center, hex_coords) == (
        "internal_shared_edge"
    )
    assert classify_hex_edge(east_q, east_r, edge_east, hex_coords) == (
        "internal_shared_edge"
    )

    subdiv = SURFACE_SUBDIVISIONS
    center_samples = [
        subdivided_shared_edge_world(
            center_q, center_r, edge_center, step_k, influences
        )
        for step_k in range(subdiv + 1)
    ]
    east_samples = [
        subdivided_shared_edge_world(
            east_q, east_r, edge_east, step_k, influences
        )
        for step_k in range(subdiv + 1)
    ]
    assert len(center_samples) == len(east_samples), "subdivided edge sample count mismatch"
    _log(f"subdivided shared-edge samples: {len(center_samples)} per hex")

    for step_k in range(subdiv + 1):
        rev_k = subdiv - step_k
        wx_c, wy_c, wz_c = center_samples[step_k]
        wx_e, wy_e, wz_e = east_samples[rev_k]
        assert abs(wx_c - wx_e) < WORLD_XY_TOLERANCE, (
            f"subdivided edge XY mismatch at step {step_k}"
        )
        assert abs(wy_c - wy_e) < WORLD_XY_TOLERANCE, (
            f"subdivided edge Y mismatch at step {step_k}"
        )
        assert abs(wz_c - wz_e) < WORLD_Z_TOLERANCE, (
            f"subdivided edge Z mismatch at step {step_k}: "
            f"center {wz_c:.6f} vs east {wz_e:.6f}"
        )

    _log("shared-edge validation passed (subdivided edge chain, no skirt on internal edge)")


def validate_all_internal_edge_heights(
    influences: list[tuple[float, float, float]],
    hex_coords: set[tuple[int, int]],
) -> None:
    """Every internal edge: matching XYZ samples from both hexes."""
    subdiv = SURFACE_SUBDIVISIONS
    checked = 0
    for q, r in hex_coords:
        for edge_index in range(6):
            if classify_hex_edge(q, r, edge_index, hex_coords) != "internal_shared_edge":
                continue
            direction = neighbor_direction_for_physical_edge(edge_index)
            dq, dr = NEIGHBOR_DIRS[direction]
            nq, nr = q + dq, r + dr
            neighbor_edge = edge_index_for_neighbor_direction(
                opposite_neighbor_direction(direction)
            )
            for step_k in range(subdiv + 1):
                rev_k = subdiv - step_k
                ax, ay, az = subdivided_shared_edge_world(
                    q, r, edge_index, step_k, influences
                )
                bx, by, bz = subdivided_shared_edge_world(
                    nq, nr, neighbor_edge, rev_k, influences
                )
                assert abs(ax - bx) < WORLD_XY_TOLERANCE
                assert abs(ay - by) < WORLD_XY_TOLERANCE
                assert abs(az - bz) < WORLD_Z_TOLERANCE
            checked += 1
    _log(f"all internal edge height checks passed ({checked} internal edges)")


def main() -> None:
    validate_params()
    _log(f"Blender version: {_blender_version_label()}")
    _log("generating 7-hex heightfield prototype…")
    _log(f"repo root: {REPO_ROOT}")
    _log(f"surface subdivisions: {SURFACE_SUBDIVISIONS}")

    clear_scene()
    coll = ensure_collection(COLLECTION_NAME)

    influences = build_hex_influences()
    hex_levels = build_hex_level_lookup()
    hex_coords = build_hex_coords_set(hex_levels)
    log_heightfield_config(influences)
    log_center_to_east_profile(influences)
    log_edge_classification_audit(hex_coords)
    validate_internal_edge_symmetry(hex_coords)
    log_shared_edge_check(influences, hex_coords)
    validate_all_internal_edge_heights(influences, hex_coords)

    material = make_terrain_material()
    _log("material created")

    total_verts = 0
    total_faces = 0
    total_skirt_faces = 0
    total_chamfer_faces = 0
    total_rim_verts = 0
    for q, r, level, terrain_label in PROTOTYPE_HEXES:
        _obj, stats = build_hex_mesh(
            q, r, level, terrain_label, influences, hex_coords, material, coll
        )
        total_verts += stats["verts"]
        total_faces += stats["faces"]
        total_skirt_faces += stats["skirt_faces"]
        total_chamfer_faces += stats["chamfer_faces"]
        total_rim_verts += stats["rim_verts"]
        _log(
            f"hex ({q},{r}) {terrain_label}: "
            f"{stats['verts']} verts, {stats['faces']} faces, "
            f"internal edges {stats['internal_edges']}, "
            f"exposed edges {stats['exposed_edges']}, "
            f"skirt faces {stats['skirt_faces']}, "
            f"chamfer faces {stats['chamfer_faces']}, "
            f"rim verts {stats['rim_verts']}"
        )
    _log(
        f"meshes created: {len(PROTOTYPE_HEXES)}; "
        f"total {total_verts} verts, {total_faces} faces, "
        f"skirt faces {total_skirt_faces}, chamfer faces {total_chamfer_faces}, "
        f"rim verts {total_rim_verts}"
    )
    _log("outer rim softening applied on exposed patch perimeter only")

    setup_camera_and_lights()
    setup_render_and_world()
    save_outputs()
    _log("done")


if __name__ == "__main__":
    main()
