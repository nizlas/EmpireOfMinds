# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_cliff_wall_material.gd
#
# N3c.3b cliff-wall stone material (Stage-3a port):
# - locked baseline parameters and the three in-place stone texture paths;
# - deterministic most-horizontal-edge cliff-tangent rule (steep-edge
#   exclusion, strictly-greater first-wins selection, +X fallback);
# - wall-local UV rule U = dot(world XZ, tangent) * 0.35, V = world Y * 0.35,
#   world-anchored (never normalized or restarted per face), equal to the
#   Blender plane-coordinate rule under the axis mapping (x_b, y_b) = (x, -z);
# - fan-triangulated mesh arrays: polygon UV frame computed before
#   triangulation (both quad triangles share the diagonal UVs — no seam),
#   crack-tip triangles handled by the same rule, preserved N3c.1 winding;
# - tangent validity (finite, unit, orthogonal to the flat face normal,
#   handedness consistent with dP/dv) and bit-identical determinism;
# - debug-stage synchronization with the top-surface material;
# - reference-map coverage over all 936 wall faces (916 quads + 20 crack
#   tips) using the Release native height-solver backend.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# Locked Stage-3a expectations, duplicated independently from the module so a
# silent retune of either side fails the test (mirrors
# tools/blender/terrain/eom_terrain_ts08_cliff_wall_stone_material.py).
const EXPECTED_LOCKED_PARAMETERS := {
	"wall_uv_u_scale": 0.35,
	"wall_uv_v_scale": 0.35,
	"wall_albedo_multiplier": 0.55,
	"wall_normal_strength": 0.55,
	"wall_metallic": 0.0,
	"wall_specular_ior_level": 0.25,
	"wall_roughness_fallback": 0.88,
}

# Reference-map golden values (test-owned, from the accepted N3c.1 slice).
const EXPECTED_WALL_FACE_COUNT := 936
const EXPECTED_WALL_QUAD_COUNT := 916
const EXPECTED_WALL_TRIANGLE_COUNT := 20
# (916 quads * 2 + 20 crack tips) triangles * 3 duplicated vertices.
const EXPECTED_WALL_VERTEX_COUNT := 5556

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_locked_parameters_and_textures()
	_test_wall_tangent_rule()
	_test_wall_uv_values()
	_test_mesh_arrays_synthetic()
	_test_debug_stage_sync()
	_test_reference_map()
	_finish()


func _test_locked_parameters_and_textures() -> void:
	print("--- locked baseline parameters and texture paths ---")
	_check(TerrainCliffWallMaterial.TEXTURE_PATHS.size() == 3, "three stone maps declared")
	var reused_in_place := true
	for param: String in TerrainCliffWallMaterial.TEXTURE_PATHS.keys():
		if not TerrainSurfaceMaterial.TEXTURE_PATHS.has(param):
			reused_in_place = false
		elif TerrainCliffWallMaterial.TEXTURE_PATHS[param] != TerrainSurfaceMaterial.TEXTURE_PATHS[param]:
			reused_in_place = false
		if not FileAccess.file_exists(TerrainCliffWallMaterial.TEXTURE_PATHS[param]):
			reused_in_place = false
			print("missing texture: %s" % TerrainCliffWallMaterial.TEXTURE_PATHS[param])
	_check(
		reused_in_place,
		"stone albedo/normal/roughness reuse the top-surface prototype paths in place"
	)

	var material := TerrainCliffWallMaterial.create_material()
	_check(material != null, "material creates")
	if material == null:
		return
	_check(
		material.shader != null
		and material.shader.resource_path == TerrainCliffWallMaterial.SHADER_PATH,
		"shader bound from %s" % TerrainCliffWallMaterial.SHADER_PATH
	)
	_check(
		TerrainCliffWallMaterial.BASELINE_PARAMETERS.size() == EXPECTED_LOCKED_PARAMETERS.size(),
		"baseline parameter set is complete"
	)
	for param: String in EXPECTED_LOCKED_PARAMETERS.keys():
		var actual: Variant = material.get_shader_parameter(param)
		_check(
			actual != null
			and is_equal_approx(float(actual), float(EXPECTED_LOCKED_PARAMETERS[param])),
			"locked parameter %s = %s" % [param, str(EXPECTED_LOCKED_PARAMETERS[param])]
		)

	var all_bound := true
	var all_mipmapped := true
	for param: String in TerrainCliffWallMaterial.TEXTURE_PATHS.keys():
		var texture: Variant = material.get_shader_parameter(param)
		if not (texture is Texture2D) or texture.get_width() <= 0:
			all_bound = false
			continue
		var image: Image = texture.get_image()
		if image == null or not image.has_mipmaps():
			all_mipmapped = false
	_check(all_bound, "all three texture uniforms bound to loaded textures")
	_check(all_mipmapped, "textures carry generated mipmaps for mipmapped sampling")

	# Albedo is sRGB; normal/roughness stay linear; repeating mipmapped
	# sampling; the roughness channel is sampled (0.88 stays the inert
	# unlinked-socket fallback, exactly like the Blender node default).
	var code: String = material.shader.code
	_check(
		code.contains(
			"uniform sampler2D stone_albedo_tex : source_color, repeat_enable, filter_linear_mipmap;"
		),
		"stone_albedo_tex sampled as sRGB with repeat + mipmaps"
	)
	for linear_param in ["stone_normal_tex", "stone_roughness_tex"]:
		_check(
			code.contains(
				"uniform sampler2D %s : repeat_enable, filter_linear_mipmap;" % linear_param
			),
			"%s sampled as linear data with repeat + mipmaps" % linear_param
		)
	_check(
		code.contains("texture(stone_roughness_tex"),
		"roughness is sampled from the map (not the fallback constant)"
	)


func _test_wall_tangent_rule() -> void:
	print("--- deterministic cliff-tangent rule (most-horizontal edge) ---")
	# Quad wall along X (a0, a1 top; b1, b0 bottom). The bottom edge has the
	# same horizontal length as the top edge but runs in reverse; the
	# strictly-greater comparison keeps the first (top) edge — this pins the
	# helper's deterministic first-wins selection.
	var quad_x := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0), Vector3(2.0, 2.0, 0.0),
		Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
	])
	var face := PackedInt32Array([0, 1, 2, 3])
	_check(
		TerrainCliffWallMaterial.wall_face_tangent_xz(quad_x, face) == Vector2(1.0, 0.0),
		"X-run wall: tangent (1, 0) from the first most-horizontal edge"
	)

	# Quad wall along Z.
	var quad_z := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 2.0, 3.0),
		Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 0.0),
	])
	_check(
		TerrainCliffWallMaterial.wall_face_tangent_xz(quad_z, face) == Vector2(0.0, 1.0),
		"Z-run wall: tangent (0, 1)"
	)

	# Steep-edge exclusion: the top edge rises 1.0 over horizontal 1.0
	# (> 0.65 ratio) and must be rejected; the horizontal bottom edge wins
	# even though it runs in the -X direction.
	var steep_top := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 0.0),
		Vector3(1.0, -2.0, 0.0), Vector3(0.0, -2.0, 0.0),
	])
	_check(
		TerrainCliffWallMaterial.wall_face_tangent_xz(steep_top, face) == Vector2(-1.0, 0.0),
		"edges steeper than 0.65x horizontal are excluded"
	)

	# Longest qualifying edge wins.
	var long_top := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0), Vector3(3.0, 1.0, 0.0),
		Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
	])
	_check(
		TerrainCliffWallMaterial.wall_face_tangent_xz(long_top, face) == Vector2(1.0, 0.0),
		"longest qualifying edge provides the tangent"
	)

	# All edges steep or zero-length: deterministic +X fallback.
	var all_steep := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.1, 1.0, 0.0), Vector3(0.1, -1.0, 0.0),
	])
	_check(
		TerrainCliffWallMaterial.wall_face_tangent_xz(
			all_steep, PackedInt32Array([0, 1, 2])
		) == Vector2(1.0, 0.0),
		"no qualifying edge falls back to tangent (1, 0)"
	)


func _test_wall_uv_values() -> void:
	print("--- wall-local UV rule (U along tangent, V = world Y) ---")
	_check(
		is_equal_approx(TerrainCliffWallMaterial.WALL_UV_U_SCALE, 0.35)
		and is_equal_approx(TerrainCliffWallMaterial.WALL_UV_V_SCALE, 0.35),
		"wall UV scales locked at 0.35 / 0.35"
	)
	_check(
		TerrainCliffWallMaterial.wall_uv(
			Vector3(2.0, 3.0, -4.0), Vector2(1.0, 0.0)
		).is_equal_approx(Vector2(0.7, 1.05)),
		"X tangent: U = x * 0.35, V = y * 0.35"
	)
	_check(
		TerrainCliffWallMaterial.wall_uv(
			Vector3(2.0, 3.0, -4.0), Vector2(0.0, 1.0)
		).is_equal_approx(Vector2(-1.4, 1.05)),
		"Z tangent: U = z * 0.35"
	)
	var diagonal := TerrainCliffWallMaterial.wall_uv(Vector3(2.0, 3.0, -4.0), Vector2(0.6, 0.8))
	_check(
		diagonal.is_equal_approx(Vector2((2.0 * 0.6 + (-4.0) * 0.8) * 0.35, 1.05)),
		"diagonal tangent: U = dot(world XZ, tangent) * 0.35"
	)

	# Blender equivalence under (x_b, y_b) = (x, -z): the plane tangent is
	# (t.x, -t.y) and U_b = (x_b * t.x + y_b * (-t.y)) * 0.35 — both sign
	# flips cancel, giving the identical U.
	var p := Vector3(1.7, 2.4, -3.1)
	var t := Vector2(0.6, 0.8)
	var u_blender := (p.x * t.x + (-p.z) * (-t.y)) * 0.35
	_check(
		is_equal_approx(TerrainCliffWallMaterial.wall_uv(p, t).x, u_blender),
		"U equals the Blender plane-coordinate rule under the axis mapping"
	)

	# World-anchored: the UV delta between two points depends only on their
	# offset (a single linear map — never normalized or restarted per face).
	var bases := [Vector3.ZERO, Vector3(4.5, 1.0, -2.25), Vector3(-11.0, 3.5, 8.0)]
	var offsets := [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 2.0, 0.0), Vector3(-0.5, 0.7, 1.3)]
	var anchored := true
	for base: Vector3 in bases:
		for offset: Vector3 in offsets:
			var expected := Vector2(
				(offset.x * t.x + offset.z * t.y) * 0.35, offset.y * 0.35
			)
			var actual := (
				TerrainCliffWallMaterial.wall_uv(base + offset, t)
				- TerrainCliffWallMaterial.wall_uv(base, t)
			)
			if actual.distance_to(expected) > 1e-5:
				anchored = false
	_check(anchored, "UV deltas depend only on the world offset (no restart anywhere)")


func _test_mesh_arrays_synthetic() -> void:
	print("--- wall mesh arrays (fan triangulation, shared polygon frame) ---")
	var positions := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0), Vector3(2.0, 2.0, 0.0),
		Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
	])
	var quad := Ts08SurfaceGeometry.WallFace.new()
	quad.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	var built: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(positions, [quad])
	var vertices: PackedVector3Array = built["vertices"]
	var normals: PackedVector3Array = built["normals"]
	var uvs: PackedVector2Array = built["uvs"]
	var tangents: PackedFloat32Array = built["tangents"]
	_check(vertices.size() == 6, "quad fan-triangulates into two triangles")
	_check(
		normals.size() == 6 and uvs.size() == 6 and tangents.size() == 24,
		"normals, UVs, and tangents emitted per duplicated vertex"
	)
	# Preserved N3c.1 winding: (p0, p2, p1) then (p0, p3, p2).
	_check(
		vertices[0] == positions[0] and vertices[1] == positions[2]
		and vertices[2] == positions[1] and vertices[3] == positions[0]
		and vertices[4] == positions[3] and vertices[5] == positions[2],
		"fan triangulation keeps the accepted reversed winding"
	)
	# Both triangles share the polygon frame: the duplicated diagonal
	# vertices (p0 and p2) carry bit-identical UVs — no diagonal seam.
	_check(
		uvs[0] == uvs[3] and uvs[1] == uvs[5],
		"quad diagonal vertices carry identical UVs in both triangles"
	)
	var frame_tangent := TerrainCliffWallMaterial.wall_face_tangent_xz(
		positions, quad.vertex_indices
	)
	var uv_rule_ok := true
	for i in vertices.size():
		if uvs[i] != TerrainCliffWallMaterial.wall_uv(vertices[i], frame_tangent):
			uv_rule_ok = false
	_check(uv_rule_ok, "every emitted UV follows the polygon-frame rule")
	_check_triangle_tangents(vertices, normals, uvs, tangents, "synthetic quad")

	# Non-planar polygon robustness: real wall quads span two vertical seam
	# columns and are therefore always planar, but the builder must stay
	# valid for generic input — the two fan triangles get different flat
	# normals, each tangent must be orthogonal to its own triangle normal,
	# and the shared diagonal UVs still match (frame computed before
	# triangulation).
	var bent_positions := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0), Vector3(2.0, 1.4, 0.6),
		Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
	])
	var bent := Ts08SurfaceGeometry.WallFace.new()
	bent.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	var bent_built: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		bent_positions, [bent]
	)
	var bent_normals: PackedVector3Array = bent_built["normals"]
	_check(
		not bent_normals[0].is_equal_approx(bent_normals[3]),
		"non-planar quad produces two distinct flat normals"
	)
	var bent_uvs: PackedVector2Array = bent_built["uvs"]
	_check(
		bent_uvs[0] == bent_uvs[3] and bent_uvs[1] == bent_uvs[5],
		"non-planar quad still shares diagonal UVs (no seam)"
	)
	_check_triangle_tangents(
		bent_built["vertices"], bent_normals, bent_uvs, bent_built["tangents"],
		"non-planar quad"
	)

	# Crack-tip triangle: three unique vertices, same deterministic rule.
	var tip_positions := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.2), Vector3(1.0, 0.0, 0.2),
	])
	var tip := Ts08SurfaceGeometry.WallFace.new()
	tip.vertex_indices = PackedInt32Array([0, 1, 2])
	var tip_built: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		tip_positions, [tip]
	)
	var tip_vertices: PackedVector3Array = tip_built["vertices"]
	_check(tip_vertices.size() == 3, "crack-tip triangle emits one triangle")
	_check_triangle_tangents(
		tip_vertices, tip_built["normals"], tip_built["uvs"], tip_built["tangents"],
		"crack-tip triangle"
	)

	# Bit-identical determinism across two independent builds.
	var rebuilt: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(positions, [quad])
	_check(
		rebuilt["vertices"] == built["vertices"]
		and rebuilt["normals"] == built["normals"]
		and rebuilt["uvs"] == built["uvs"]
		and rebuilt["tangents"] == built["tangents"],
		"wall mesh arrays are deterministic (bit-identical)"
	)


func _test_debug_stage_sync() -> void:
	print("--- debug-stage synchronization with the top-surface material ---")
	_check(
		TerrainCliffWallMaterial.DEBUG_STAGES == TerrainSurfaceMaterial.DEBUG_STAGES,
		"wall material shares the top-surface stage set"
	)
	var wall := TerrainCliffWallMaterial.create_material()
	var top := TerrainSurfaceMaterial.create_material()
	if wall == null or top == null:
		_check(false, "both materials create for stage checks")
		return
	for stage: String in TerrainCliffWallMaterial.DEBUG_STAGES.keys():
		var ok := TerrainCliffWallMaterial.set_debug_stage(wall, stage)
		ok = TerrainSurfaceMaterial.set_debug_stage(top, stage) and ok
		_check(
			ok
			and wall.get_shader_parameter("debug_stage")
				== top.get_shader_parameter("debug_stage"),
			"stage '%s' sets the same debug_stage on both materials" % stage
		)
	_check(
		not TerrainCliffWallMaterial.set_debug_stage(wall, "nonsense"),
		"unknown stage is rejected"
	)
	var staged := TerrainCliffWallMaterial.create_material("albedo")
	_check(
		staged != null and int(staged.get_shader_parameter("debug_stage")) == 3,
		"create_material honors the requested stage"
	)
	# In-place texture reuse: both materials hold the same cached instances.
	var shared := true
	for param: String in TerrainCliffWallMaterial.TEXTURE_PATHS.keys():
		if wall.get_shader_parameter(param) != top.get_shader_parameter(param):
			shared = false
	_check(shared, "wall and top materials share the same stone texture instances")


func _test_reference_map() -> void:
	print("--- reference-map wall UVs and tangents (native backend) ---")
	if not _require_native_extension():
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		return
	var lattice = Ts08CutLattice.build_from_world_map(world_map)
	print("native height solve starting...")
	var solve = Ts08HeightSolver.solve(world_map, lattice, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(solve != null and solve.converged, "native height solve converged")
	if solve == null:
		return
	var geometry = Ts08SurfaceGeometry.build(world_map, lattice, solve.heights)
	_check(geometry != null, "surface geometry builds")
	if geometry == null:
		return
	_check(
		geometry.wall_faces.size() == EXPECTED_WALL_FACE_COUNT
		and geometry.wall_quad_count == EXPECTED_WALL_QUAD_COUNT
		and geometry.wall_triangle_count == EXPECTED_WALL_TRIANGLE_COUNT,
		"reference map has 936 wall faces (916 quads + 20 crack tips)"
	)

	var t0 := Time.get_ticks_msec()
	var built: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	print("wall mesh arrays: %d ms" % (Time.get_ticks_msec() - t0))
	var vertices: PackedVector3Array = built["vertices"]
	var uvs: PackedVector2Array = built["uvs"]
	_check(vertices.size() == EXPECTED_WALL_VERTEX_COUNT, "5556 duplicated wall vertices")

	# Every emitted UV must follow the independent re-derivation of the
	# locked rule: polygon tangent from the most-horizontal-edge criterion,
	# U = dot(world XZ, tangent) * 0.35, V = world Y * 0.35.
	var bad_uv := 0
	var cursor := 0
	var u_min := INF
	var u_max := -INF
	var v_min := INF
	var v_max := -INF
	var degenerate_loops := 0
	var x_run_faces := 0
	var z_run_faces := 0
	for record in geometry.wall_faces:
		var face: PackedInt32Array = record.vertex_indices
		var tangent := _independent_tangent(geometry.top_positions, face)
		if absf(tangent.x) > 0.5:
			x_run_faces += 1
		if absf(tangent.y) > 0.5:
			z_run_faces += 1
		for _i in range(1, face.size() - 1):
			for k in 3:
				var pos := vertices[cursor]
				var uv := uvs[cursor]
				var expected_u := (pos.x * tangent.x + pos.z * tangent.y) * 0.35
				var expected_v := pos.y * 0.35
				if (
					not uv.is_finite()
					or absf(uv.x - expected_u) > 1e-5
					or absf(uv.y - expected_v) > 1e-5
				):
					bad_uv += 1
				u_min = minf(u_min, uv.x)
				u_max = maxf(u_max, uv.x)
				v_min = minf(v_min, uv.y)
				v_max = maxf(v_max, uv.y)
				if absf(uv.x) < 1e-9 and absf(uv.y) < 1e-9:
					degenerate_loops += 1
				cursor += 1
	_check(cursor == vertices.size(), "per-face triangle walk covers every vertex")
	_check(bad_uv == 0, "every reference-map wall UV matches the locked rule")
	print(
		"wall UV spans: u %.3f..%.3f, v %.3f..%.3f, degenerate loops %d"
		% [u_min, u_max, v_min, v_max, degenerate_loops]
	)
	_check(u_max - u_min > 0.0 and v_max - v_min > 0.0, "wall UV spans are non-zero")
	_check(degenerate_loops < vertices.size(), "wall UVs are not all zero/degenerate")
	_check(
		x_run_faces > 10 and z_run_faces > 10,
		"wall tangents cover both X-running and Z-running cliffs"
	)

	_check_triangle_tangents(
		vertices, built["normals"], uvs, built["tangents"], "reference map"
	)

	# Bit-identical determinism across two independent builds.
	var rebuilt: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	_check(
		rebuilt["vertices"] == built["vertices"]
		and rebuilt["normals"] == built["normals"]
		and rebuilt["uvs"] == built["uvs"]
		and rebuilt["tangents"] == built["tangents"],
		"reference-map wall arrays are deterministic (bit-identical)"
	)


# Independent copy of the most-horizontal-edge criterion (guards the module
# against silent rule changes).
func _independent_tangent(positions: PackedVector3Array, face: PackedInt32Array) -> Vector2:
	var best := 0.0
	var tangent := Vector2(1.0, 0.0)
	for i in face.size():
		var p0 := positions[face[i]]
		var p1 := positions[face[(i + 1) % face.size()]]
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var horiz := sqrt(dx * dx + dz * dz)
		if horiz <= 1e-9:
			continue
		if horiz > best and absf(p1.y - p0.y) <= horiz * 0.65:
			best = horiz
			tangent = Vector2(dx / horiz, dz / horiz)
	if best <= 1e-9:
		return Vector2(1.0, 0.0)
	return tangent


# Validates every emitted triangle's tangent: finite, unit length, orthogonal
# to the flat face normal, |w| = 1, and the reconstructed binormal
# cross(N, T) * w points along the triangle's true dP/dv.
func _check_triangle_tangents(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	tangents: PackedFloat32Array,
	label: String
) -> void:
	var bad_finite := 0
	var bad_unit := 0
	var bad_orthogonal := 0
	var bad_handedness := 0
	var max_dot := 0.0
	var tri_count := vertices.size() / 3
	for tri in tri_count:
		var base := 3 * tri
		var n := normals[base]
		var t := Vector3(tangents[4 * base], tangents[4 * base + 1], tangents[4 * base + 2])
		var w := tangents[4 * base + 3]
		if not (t.is_finite() and is_finite(w)):
			bad_finite += 1
			continue
		if absf(t.length() - 1.0) > 1e-5:
			bad_unit += 1
		var d := absf(t.dot(n))
		max_dot = maxf(max_dot, d)
		if d > 1e-5:
			bad_orthogonal += 1
		# The mesh stores (p0, p2, p1); recover the original (p0, p1, p2).
		var p0 := vertices[base]
		var p1 := vertices[base + 2]
		var p2 := vertices[base + 1]
		var uv0 := uvs[base]
		var uv1 := uvs[base + 2]
		var uv2 := uvs[base + 1]
		var duv1 := uv1 - uv0
		var duv2 := uv2 - uv0
		var det := duv1.x * duv2.y - duv2.x * duv1.y
		var handed_ok := absf(w) == 1.0
		if handed_ok and absf(det) > 1e-12:
			var dpdv := ((p2 - p0) * duv1.x - (p1 - p0) * duv2.x) / det
			handed_ok = n.cross(t).dot(dpdv) * w > 0.0
		if not handed_ok:
			bad_handedness += 1
	print("%s: %d triangles, max |dot(T, N)| = %s" % [label, tri_count, max_dot])
	_check(bad_finite == 0, "%s: every tangent finite" % label)
	_check(bad_unit == 0, "%s: every tangent unit length" % label)
	_check(bad_orthogonal == 0, "%s: every tangent orthogonal to its flat normal" % label)
	_check(
		bad_handedness == 0,
		"%s: binormal cross(N, T) * w points along dP/dv" % label
	)


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(false, "native GDExtension descriptor present (build it first)")
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			_check(false, "native GDExtension loads")
			return false
	if not ClassDB.can_instantiate(&"EomTerrainNative"):
		_check(false, "EomTerrainNative instantiable")
		return false
	return true


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainCliffWallMaterial tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
