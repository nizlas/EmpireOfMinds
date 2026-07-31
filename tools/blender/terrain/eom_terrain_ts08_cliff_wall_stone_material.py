# Empire of Minds — TS-08 cliff wall stone material + wall-local UV helper.
# Material/UV presentation pass only; does not modify solver or wall geometry.

from __future__ import annotations

import math
from typing import Any

from eom_terrain_math_core import DEFAULT_HEX_RADIUS, handdrawn_to_baseline_axial
from eom_terrain_ts08_cliff_walls import WALL_MATERIAL_INDEX

CLIFF_WALL_STONE_MATERIAL_NAME = "TS08_Cliff_Wall_Stone"
CLIFF_WALL_UV_LAYER_NAME = "EOM_CliffWallUV"
# First-pass wall-local UV scale (U along cliff tangent, V = world height).
WALL_UV_U_SCALE = 0.35
WALL_UV_V_SCALE = 0.35
WALL_STONE_ROUGHNESS = 0.88
WALL_STONE_ALBEDO_MULTIPLIER = 0.55
WALL_STONE_NORMAL_STRENGTH = 0.55


def make_cliff_wall_stone_material(
    baseline: Any,
    stone_albedo_path: Any,
    stone_normal_path: Any,
    stone_roughness_path: Any,
) -> Any:
    """PBR stone material for vertical cliff wall faces (matte rock, no metal)."""
    import bpy

    existing = bpy.data.materials.get(CLIFF_WALL_STONE_MATERIAL_NAME)
    if existing is not None:
        bpy.data.materials.remove(existing)

    mat = bpy.data.materials.new(CLIFF_WALL_STONE_MATERIAL_NAME)
    mat.use_nodes = True
    node_tree = mat.node_tree
    if node_tree is None:
        raise RuntimeError(f"material {CLIFF_WALL_STONE_MATERIAL_NAME!r} has no node tree")
    nodes = node_tree.nodes
    links = node_tree.links
    nodes.clear()

    out = baseline._new_node(nodes, "ShaderNodeOutputMaterial")
    out.location = (520, 0)
    principled = baseline._new_node(nodes, "ShaderNodeBsdfPrincipled")
    principled.location = (220, 0)
    baseline._require_input(principled, "Metallic").default_value = 0.0
    baseline._require_input(principled, "Roughness").default_value = WALL_STONE_ROUGHNESS
    baseline._require_input(principled, "Specular IOR Level").default_value = 0.25

    uv_map = baseline._new_node(nodes, "ShaderNodeUVMap")
    uv_map.location = (-820, 0)
    uv_map.uv_map = CLIFF_WALL_UV_LAYER_NAME

    mapping = baseline._new_node(nodes, "ShaderNodeMapping")
    mapping.location = (-620, 0)
    links.new(baseline._require_output(uv_map, "UV"), baseline._require_input(mapping, "Vector"))

    albedo_image = baseline._load_stone_image(
        "EOM_Stone_Albedo_TS08Wall",
        stone_albedo_path,
        "sRGB",
    )
    normal_image = baseline._load_stone_image(
        "EOM_Stone_Normal_TS08Wall",
        stone_normal_path,
        "Non-Color",
    )
    roughness_image = baseline._load_stone_image(
        "EOM_Stone_Roughness_TS08Wall",
        stone_roughness_path,
        "Non-Color",
    )

    albedo_tex = baseline._new_image_texture_node(nodes, albedo_image, (-420, 120))
    normal_tex = baseline._new_image_texture_node(nodes, normal_image, (-420, -80))
    roughness_tex = baseline._new_image_texture_node(nodes, roughness_image, (-420, -280))
    mapped = baseline._require_output(mapping, "Vector")
    links.new(mapped, baseline._require_input(albedo_tex, "Vector"))
    links.new(mapped, baseline._require_input(normal_tex, "Vector"))
    links.new(mapped, baseline._require_input(roughness_tex, "Vector"))

    albedo_multiply = baseline._new_color_mix_node(nodes, "MULTIPLY", (-180, 120))
    albedo_multiply.factor.default_value = 1.0
    links.new(baseline._require_output(albedo_tex, "Color"), albedo_multiply.color1)
    tint = baseline._new_node(nodes, "ShaderNodeRGB")
    tint.location = (-360, 40)
    baseline._require_output(tint, "Color").default_value = (
        WALL_STONE_ALBEDO_MULTIPLIER,
        WALL_STONE_ALBEDO_MULTIPLIER,
        WALL_STONE_ALBEDO_MULTIPLIER,
        1.0,
    )
    links.new(baseline._require_output(tint, "Color"), albedo_multiply.color2)
    links.new(albedo_multiply.output, baseline._require_input(principled, "Base Color"))

    normal_map = baseline._new_node(nodes, "ShaderNodeNormalMap")
    normal_map.location = (-40, -80)
    baseline._require_input(normal_map, "Strength").default_value = WALL_STONE_NORMAL_STRENGTH
    links.new(baseline._require_output(normal_tex, "Color"), baseline._require_input(normal_map, "Color"))
    links.new(baseline._require_output(normal_map, "Normal"), baseline._require_input(principled, "Normal"))

    links.new(
        baseline._require_output(roughness_tex, "Color"),
        baseline._require_input(principled, "Roughness"),
    )
    links.new(baseline._require_output(principled, "BSDF"), baseline._require_input(out, "Surface"))
    return mat


def _face_cliff_tangent_xy(
    mesh: Any,
    indices: tuple[int, ...],
) -> tuple[float, float]:
    """Pick the most horizontal edge as cliff tangent (U axis)."""
    best_horiz = 0.0
    tangent_x, tangent_y = 1.0, 0.0
    count = len(indices)
    for edge_index in range(count):
        v0 = mesh.vertices[indices[edge_index]].co
        v1 = mesh.vertices[indices[(edge_index + 1) % count]].co
        dx = float(v1.x - v0.x)
        dy = float(v1.y - v0.y)
        dz = abs(float(v1.z - v0.z))
        horiz = math.hypot(dx, dy)
        if horiz <= 1e-9:
            continue
        if horiz > best_horiz and dz <= horiz * 0.65:
            best_horiz = horiz
            tangent_x = dx / horiz
            tangent_y = dy / horiz
    if best_horiz <= 1e-9:
        return 1.0, 0.0
    return tangent_x, tangent_y


def assign_cliff_wall_local_uv(
    mesh: Any,
    wall_build: Any,
    *,
    top_face_count: int,
    u_scale: float = WALL_UV_U_SCALE,
    v_scale: float = WALL_UV_V_SCALE,
    layer_name: str = CLIFF_WALL_UV_LAYER_NAME,
) -> dict[str, Any]:
    """First-pass wall-local UVs: U along cliff tangent, V from world height."""
    if u_scale <= 0.0 or v_scale <= 0.0:
        raise ValueError("wall UV scales must be > 0")

    existing = mesh.uv_layers.get(layer_name)
    if existing is not None:
        mesh.uv_layers.remove(existing)
    uv_layer = mesh.uv_layers.new(name=layer_name)
    mesh.uv_layers.active = uv_layer
    layer_index = mesh.uv_layers.find(layer_name)
    if layer_index < 0:
        raise RuntimeError(f"UV layer {layer_name!r} missing after creation")
    mesh.uv_layers.active_index = layer_index

    wall_loop_count = 0
    degenerate_loops = 0
    u_span = 0.0
    v_span = 0.0
    u_values: list[float] = []
    v_values: list[float] = []

    for wall_index, record in enumerate(wall_build.wall_face_records):
        poly_index = top_face_count + wall_index
        if poly_index >= len(mesh.polygons):
            raise RuntimeError(
                f"wall polygon index out of range: {poly_index} (faces={len(mesh.polygons)})"
            )
        poly = mesh.polygons[poly_index]
        indices = tuple(poly.vertices)
        if indices != record.vertex_indices:
            indices = record.vertex_indices
        tangent_x, tangent_y = _face_cliff_tangent_xy(mesh, indices)

        for loop_idx in range(poly.loop_start, poly.loop_start + poly.loop_total):
            vert_idx = mesh.loops[loop_idx].vertex_index
            co = mesh.vertices[vert_idx].co
            u = (float(co.x) * tangent_x + float(co.y) * tangent_y) * u_scale
            v = float(co.z) * v_scale
            if not (math.isfinite(u) and math.isfinite(v)):
                raise RuntimeError(
                    f"non-finite wall UV at face {wall_index} vert {vert_idx}: ({u}, {v})"
                )
            uv_layer.data[loop_idx].uv = (u, v)
            wall_loop_count += 1
            u_values.append(u)
            v_values.append(v)
            if abs(u) < 1e-9 and abs(v) < 1e-9:
                degenerate_loops += 1

    if wall_loop_count <= 0:
        raise RuntimeError("wall UV assignment found no wall-face loops")

    if u_values and v_values:
        u_span = max(u_values) - min(u_values)
        v_span = max(v_values) - min(v_values)

    mesh.update()
    return {
        "layer_name": layer_name,
        "wall_loop_count": wall_loop_count,
        "wall_face_count": len(wall_build.wall_face_records),
        "degenerate_loops": degenerate_loops,
        "u_span": u_span,
        "v_span": v_span,
        "u_scale": u_scale,
        "v_scale": v_scale,
        "mapping_mode": "first_pass_wall_local_u_along_tangent_v_world_height",
    }


def apply_ts08_cliff_wall_stone_presentation(
    mesh: Any,
    mesh_stats: dict[str, Any],
    wall_build: Any,
    baseline: Any,
    stone_albedo_path: Any,
    stone_normal_path: Any,
    stone_roughness_path: Any,
) -> tuple[Any, dict[str, Any]]:
    """Create cliff wall stone material and assign wall-local UVs."""
    wall_material = make_cliff_wall_stone_material(
        baseline,
        stone_albedo_path,
        stone_normal_path,
        stone_roughness_path,
    )
    uv_stats = assign_cliff_wall_local_uv(
        mesh,
        wall_build,
        top_face_count=int(mesh_stats["top_faces"]),
    )
    return wall_material, {
        "wall_material_name": CLIFF_WALL_STONE_MATERIAL_NAME,
        "stone_albedo_path": str(stone_albedo_path),
        "stone_normal_path": str(stone_normal_path),
        "stone_roughness_path": str(stone_roughness_path),
        "wall_material_index": WALL_MATERIAL_INDEX,
        "wall_faces_assigned": int(mesh_stats.get("wall_faces", len(wall_build.wall_faces))),
        **uv_stats,
    }


def audit_wall_stone_material(mesh: Any, *, top_face_count: int) -> tuple[list[str], dict[str, Any]]:
    """Read-only checks for cliff wall stone material assignment."""
    failures: list[str] = []
    info: dict[str, Any] = {}

    if len(mesh.materials) <= WALL_MATERIAL_INDEX:
        failures.append("missing wall material slot")
        return failures, info

    wall_mat = mesh.materials[WALL_MATERIAL_INDEX]
    info["wall_material_name"] = wall_mat.name
    if wall_mat.name != CLIFF_WALL_STONE_MATERIAL_NAME:
        failures.append(
            f"wall material name: got {wall_mat.name!r}, expected {CLIFF_WALL_STONE_MATERIAL_NAME!r}"
        )

    has_stone_albedo = False
    if wall_mat.use_nodes and wall_mat.node_tree is not None:
        for node in wall_mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                name_lower = node.image.name.lower()
                filepath = getattr(node.image, "filepath", "") or ""
                if "stone" in name_lower or "stone" in filepath.lower():
                    has_stone_albedo = True
                    info["stone_albedo_image"] = node.image.name
                    info["stone_albedo_source"] = filepath
                    break
    info["has_stone_albedo"] = has_stone_albedo
    if not has_stone_albedo:
        failures.append("wall material missing identifiable stone albedo image")

    uv_layer = mesh.uv_layers.get(CLIFF_WALL_UV_LAYER_NAME)
    info["wall_uv_layer"] = CLIFF_WALL_UV_LAYER_NAME
    info["wall_uv_layer_present"] = uv_layer is not None
    if uv_layer is None:
        failures.append(f"missing wall UV layer {CLIFF_WALL_UV_LAYER_NAME!r}")
        return failures, info

    top_on_wall_mat = 0
    wall_on_wall_mat = 0
    degenerate_wall_loops = 0
    wall_loop_count = 0
    for poly in mesh.polygons:
        if poly.index < top_face_count:
            if poly.material_index == WALL_MATERIAL_INDEX:
                top_on_wall_mat += 1
            continue
        if poly.material_index != WALL_MATERIAL_INDEX:
            failures.append(f"wall polygon {poly.index} material_index={poly.material_index}")
        else:
            wall_on_wall_mat += 1
        for loop_idx in range(poly.loop_start, poly.loop_start + poly.loop_total):
            uv = uv_layer.data[loop_idx].uv
            wall_loop_count += 1
            if abs(uv[0]) < 1e-9 and abs(uv[1]) < 1e-9:
                degenerate_wall_loops += 1

    info["top_faces_on_wall_material"] = top_on_wall_mat
    info["wall_faces_on_wall_material"] = wall_on_wall_mat
    info["wall_loop_count"] = wall_loop_count
    info["degenerate_wall_loops"] = degenerate_wall_loops

    if top_on_wall_mat > 0:
        failures.append(f"{top_on_wall_mat} top faces assigned to wall material")
    if wall_on_wall_mat <= 0:
        failures.append("no wall faces assigned to wall material slot")
    if wall_loop_count <= 0:
        failures.append("no wall UV loops found")
    if degenerate_wall_loops == wall_loop_count and wall_loop_count > 0:
        failures.append("all wall UV loops are zero/degenerate")

    return failures, info
