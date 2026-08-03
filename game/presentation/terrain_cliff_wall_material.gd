# N3c.3b presentation-side cliff-wall stone material (Stage-3a port).
# Reusable by the dev terrain preview and later presentation consumers;
# materials, shaders, and mesh assembly stay out of the domain layer.
#
# Ports the accepted TS-08 Stage-3a cliff-wall stone presentation baseline in
# tools/blender/terrain/eom_terrain_ts08_cliff_wall_stone_material.py:
# the TS08_Cliff_Wall_Stone PBR material (albedo x 0.55, normal strength
# 0.55, sampled roughness with the inert 0.88 unlinked-socket fallback,
# Metallic 0, Specular IOR Level 0.25) plus the first-pass wall-local UV rule
# (assign_cliff_wall_local_uv). The three stone textures are the existing
# prototype assets, consumed in place and shared byte-for-byte with the
# N3c.3a top-surface material (same loader cache, so both materials hold the
# same Texture2D instances).
#
# Wall-local UV contract (locked): for each original wall polygon (quad or
# crack-tip triangle, BEFORE fan triangulation), pick the most-horizontal
# polygon edge as the cliff tangent using the helper's deterministic
# criterion (largest horizontal length among edges whose vertical rise is at
# most 0.65 x the horizontal length; strictly-greater comparison, edges
# iterated in polygon order, fallback +X). Then per vertex:
#   U = dot(world XZ, tangent XZ) * 0.35
#   V = world Y * 0.35
# Both triangles of a quad share the polygon frame, so the shared diagonal
# vertices carry identical UVs and no seam appears. UVs are never normalized
# or restarted per output triangle.
#
# Axis mapping: Blender computes the tangent from plane (dx, dy) and
# U = (x*tx + y*ty) * 0.35 with (x_b, y_b) = (x, -z). Computing directly from
# Godot positions — tangent from (dx, dz), U = (x*tx + z*tz) * 0.35 — yields
# the identical U because the y_b sign flip appears in both the tangent
# component and the coordinate and cancels in the dot product. The vertical
# criterion uses |dy| (Godot) = |dz| (Blender), and the horizontal length is
# invariant. V = world Y * 0.35 equals Blender's V = z_b * 0.35.
#
# Tangent basis: walls are flat-shaded with per-face normals, so tangents are
# per output triangle: the exact dP/du of the linear wall UV (solved from the
# triangle's positions and UVs), Gram-Schmidt-orthogonalized against the flat
# face normal, with handedness w = sign(dot(cross(N, T), dP/dv)). Finite,
# unit-length, orthogonal, and deterministic by construction; degenerate UV
# determinants fall back to the polygon tangent projected onto the face
# plane, then +X / +Z (all deterministic).
extends RefCounted

const TerrainSurfaceMaterialScript = preload("res://presentation/terrain_surface_material.gd")

const SHADER_PATH := "res://presentation/terrain_cliff_wall.gdshader"

# The three stone maps, reused in place from the N3c.3a top-surface material
# (same resource paths, same runtime loader/cache).
const TEXTURE_PATHS := {
	"stone_albedo_tex": TerrainSurfaceMaterialScript.TEXTURE_BASE + "/stone/stone_albedo.png",
	"stone_normal_tex": TerrainSurfaceMaterialScript.TEXTURE_BASE + "/stone/stone_normal.png",
	"stone_roughness_tex": TerrainSurfaceMaterialScript.TEXTURE_BASE + "/stone/stone_roughness.png",
}

const WALL_UV_U_SCALE := 0.35
const WALL_UV_V_SCALE := 0.35
# Most-horizontal-edge criterion: vertical rise <= 0.65 x horizontal length.
const WALL_TANGENT_MAX_VERTICAL_RATIO := 0.65

# Locked Stage-3a baseline shader parameters (Godot port of
# eom_terrain_ts08_cliff_wall_stone_material.py; wall_roughness_fallback is
# Blender's Principled Roughness default, inert because the roughness map is
# always linked/bound).
const BASELINE_PARAMETERS := {
	"wall_uv_u_scale": WALL_UV_U_SCALE,
	"wall_uv_v_scale": WALL_UV_V_SCALE,
	"wall_albedo_multiplier": 0.55,
	"wall_normal_strength": 0.55,
	"wall_metallic": 0.0,
	"wall_specular_ior_level": 0.25,
	"wall_roughness_fallback": 0.88,
}

# Debug stages are shared with the top-surface material so the preview keeps
# both shaders synchronized on one stage name.
const DEBUG_STAGES := TerrainSurfaceMaterialScript.DEBUG_STAGES


static func create_material(stage: String = "final") -> ShaderMaterial:
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_error("TerrainCliffWallMaterial: failed to load shader at %s" % SHADER_PATH)
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	for param: String in BASELINE_PARAMETERS.keys():
		material.set_shader_parameter(param, BASELINE_PARAMETERS[param])
	for param: String in TEXTURE_PATHS.keys():
		var texture := TerrainSurfaceMaterialScript.load_world_texture(TEXTURE_PATHS[param])
		if texture == null:
			return null
		material.set_shader_parameter(param, texture)
	if not set_debug_stage(material, stage):
		return null
	return material


static func set_debug_stage(material: ShaderMaterial, stage: String) -> bool:
	if not DEBUG_STAGES.has(stage):
		push_error(
			"TerrainCliffWallMaterial: unknown debug stage '%s' (valid: %s)"
			% [stage, ", ".join(DEBUG_STAGES.keys())]
		)
		return false
	material.set_shader_parameter("debug_stage", DEBUG_STAGES[stage])
	return true


# Most-horizontal edge of the original wall polygon as the cliff tangent
# (U axis) in the Godot XZ plane. Direct port of _face_cliff_tangent_xy —
# see the axis-mapping note in the header for why Godot (dx, dz) reproduces
# Blender's plane-coordinate result exactly.
static func wall_face_tangent_xz(
	positions: PackedVector3Array, face: PackedInt32Array
) -> Vector2:
	var best_horiz := 0.0
	var tangent := Vector2(1.0, 0.0)
	var count := face.size()
	for edge_index in count:
		var p0 := positions[face[edge_index]]
		var p1 := positions[face[(edge_index + 1) % count]]
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var rise := absf(p1.y - p0.y)
		var horiz := sqrt(dx * dx + dz * dz)
		if horiz <= 1e-9:
			continue
		if horiz > best_horiz and rise <= horiz * WALL_TANGENT_MAX_VERTICAL_RATIO:
			best_horiz = horiz
			tangent = Vector2(dx / horiz, dz / horiz)
	if best_horiz <= 1e-9:
		return Vector2(1.0, 0.0)
	return tangent


# Locked wall-local UV: U along the polygon's cliff tangent, V from world
# height. World-anchored — never normalized or restarted per face/triangle.
static func wall_uv(position: Vector3, tangent_xz: Vector2) -> Vector2:
	return Vector2(
		(position.x * tangent_xz.x + position.z * tangent_xz.y) * WALL_UV_U_SCALE,
		position.y * WALL_UV_V_SCALE
	)


# Flat-shaded wall mesh arrays from the domain wall-face records: fan
# triangulation with duplicated vertices and per-face normals (identical
# vertex output to the accepted N3c.1 preview assembly, reversed (p0, p2, p1)
# order for Godot's clockwise front faces), plus the locked wall-local UVs
# (polygon frame computed BEFORE triangulation) and per-triangle tangents.
# Returns {"vertices", "normals", "uvs", "tangents"}.
static func build_wall_mesh_arrays(
	top_positions: PackedVector3Array, wall_faces: Array
) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	for record in wall_faces:
		var face: PackedInt32Array = record.vertex_indices
		var tangent_xz := wall_face_tangent_xz(top_positions, face)
		var p0: Vector3 = top_positions[face[0]]
		var uv0 := wall_uv(p0, tangent_xz)
		for i in range(1, face.size() - 1):
			var p1: Vector3 = top_positions[face[i]]
			var p2: Vector3 = top_positions[face[i + 1]]
			var normal := (p1 - p0).cross(p2 - p0)
			if normal.length_squared() > 0.0:
				normal = normal.normalized()
			else:
				normal = Vector3.UP
			var uv1 := wall_uv(p1, tangent_xz)
			var uv2 := wall_uv(p2, tangent_xz)
			var tangent := _triangle_tangent(p0, p1, p2, uv0, uv1, uv2, normal, tangent_xz)
			# Reversed order (p0, p2, p1) for Godot's clockwise front faces.
			vertices.append(p0)
			vertices.append(p2)
			vertices.append(p1)
			uvs.append(uv0)
			uvs.append(uv2)
			uvs.append(uv1)
			for _n in 3:
				normals.append(normal)
				tangents.append_array(tangent)
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"tangents": tangents,
	}


# Exact dP/du of the linear wall UV over one output triangle, orthogonalized
# against the flat face normal; w = sign(dot(cross(N, T), dP/dv)) so Godot's
# BINORMAL = cross(NORMAL, TANGENT) * w points along dP/dv. Deterministic
# fallback chain for degenerate UV determinants or projections.
static func _triangle_tangent(
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2,
	normal: Vector3,
	tangent_xz: Vector2
) -> PackedFloat32Array:
	var e1 := p1 - p0
	var e2 := p2 - p0
	var duv1 := uv1 - uv0
	var duv2 := uv2 - uv0
	var det := duv1.x * duv2.y - duv2.x * duv1.y
	var t_raw: Vector3
	var b_raw: Vector3
	if absf(det) > 1e-12:
		var r := 1.0 / det
		t_raw = (e1 * duv2.y - e2 * duv1.y) * r
		b_raw = (e2 * duv1.x - e1 * duv2.x) * r
	else:
		# Degenerate UV area: fall back to the polygon's horizontal cliff
		# tangent; V grows with world height, so +Y stands in for dP/dv.
		t_raw = Vector3(tangent_xz.x, 0.0, tangent_xz.y)
		b_raw = Vector3.UP
	var t := t_raw - normal * normal.dot(t_raw)
	if t.length_squared() <= 1e-18:
		t = Vector3(tangent_xz.x, 0.0, tangent_xz.y)
		t = t - normal * normal.dot(t)
	if t.length_squared() <= 1e-18:
		t = Vector3(1.0, 0.0, 0.0) - normal * normal.x
	if t.length_squared() <= 1e-18:
		t = Vector3(0.0, 0.0, 1.0) - normal * normal.z
	t = t.normalized()
	var w := 1.0 if normal.cross(t).dot(b_raw) >= 0.0 else -1.0
	return PackedFloat32Array([t.x, t.y, t.z, w])
