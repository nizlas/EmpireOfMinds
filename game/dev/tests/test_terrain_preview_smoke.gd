# Headless test: godot --headless --path game -s res://dev/tests/test_terrain_preview_smoke.gd
#
# N3c.2 preview-scene smoke test: instantiates the terrain preview scene
# exactly as the editor's F6 does (no command-line arguments) and verifies
# the real runtime chain ran (WorldMap -> Ts08CutLattice -> Ts08HeightSolver
# -> Ts08SurfaceGeometry -> dev ArrayMesh) and the scene assembled its
# meshes, orbit camera, and HUD. Backend selector defaults to Auto (native
# when the built extension is available, otherwise GDScript).
#
# N3c.3a preview assembly: the top surface must use the three-layer PBR
# splatting ShaderMaterial with world-anchored UVs and tangents baked into
# the mesh; the HUD shows the active material stage.
#
# N3c.3b preview assembly: cliff walls must use the Stage-3a stone PBR
# ShaderMaterial with wall-local UVs and per-triangle tangents baked into the
# wall mesh, sharing the stone texture instances with the top material; the
# M key keeps both materials synchronized on one debug stage.
extends SceneTree

const PREVIEW_SCENE_PATH := "res://dev/terrain_preview/terrain_preview.tscn"
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")
const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")

const EXPECTED_NODE_COUNT := 74129
const EXPECTED_TOP_TRIANGLE_COUNT := 145152
const EXPECTED_WALL_FACE_COUNT := 936

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	var scene: PackedScene = load(PREVIEW_SCENE_PATH)
	_check(scene != null, "preview scene loads")
	if scene == null:
		_finish()
		return
	var preview = scene.instantiate()
	_check(preview != null, "preview scene instantiates")
	if preview == null:
		_finish()
		return

	# From SceneTree._init the node's _ready runs on the first iteration,
	# so wait for it before inspecting the assembled scene.
	root.add_child(preview)
	await preview.ready

	_check(preview.backend_used != "", "a backend was selected and reported")
	print("smoke: backend_used=%s" % preview.backend_used)
	print("smoke: timings=%s" % str(preview.timings))
	for key in ["lattice_msec", "solve_msec", "geometry_msec", "mesh_msec"]:
		_check(
			preview.timings.has(key) and int(preview.timings[key]) >= 0,
			"timing recorded: %s" % key
		)

	_check(int(preview.counts.get("nodes", 0)) == EXPECTED_NODE_COUNT, "node count")
	_check(
		int(preview.counts.get("top_triangles", 0)) == EXPECTED_TOP_TRIANGLE_COUNT,
		"top triangle count"
	)
	_check(
		int(preview.counts.get("wall_faces", 0)) == EXPECTED_WALL_FACE_COUNT,
		"wall face count"
	)

	var top_material: Material = null
	var wall_material: Material = null
	var top = preview.get_node_or_null("TopSurface")
	_check(
		top is MeshInstance3D and top.mesh != null and top.mesh.get_surface_count() == 1,
		"top-surface ArrayMesh present"
	)
	if top is MeshInstance3D and top.mesh != null and top.mesh.get_surface_count() == 1:
		top_material = top.mesh.surface_get_material(0)
		_check(
			top_material is ShaderMaterial
			and top_material.shader != null
			and top_material.shader.resource_path == TerrainSurfaceMaterial.SHADER_PATH,
			"top surface uses the N3c.3a splatting ShaderMaterial"
		)
		_check(preview.material_stage == "final", "default material stage is final")
		if top_material is ShaderMaterial:
			_check(
				int(top_material.get_shader_parameter("debug_stage")) == 0,
				"debug_stage uniform matches the final stage"
			)
			var bound_textures := true
			for param: String in TerrainSurfaceMaterial.TEXTURE_PATHS.keys():
				if not (top_material.get_shader_parameter(param) is Texture2D):
					bound_textures = false
			_check(bound_textures, "all nine splatting textures bound")
		var arrays: Array = top.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_check(uvs.size() == vertices.size(), "world-anchored UVs baked per vertex")
		var uv_matches := uvs.size() > 0
		for i in mini(uvs.size(), 500):
			if uvs[i].distance_to(TerrainSurfaceMaterial.world_uv(vertices[i])) > 1e-5:
				uv_matches = false
				break
		_check(uv_matches, "baked UVs follow (x*0.35, -z*0.35)")
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		_check(tangents.size() == vertices.size() * 4, "tangents baked per vertex")
		_check_reference_map_tangents(arrays, tangents)
	var walls = preview.get_node_or_null("CliffWalls")
	_check(
		walls is MeshInstance3D and walls.mesh != null and walls.mesh.get_surface_count() == 1,
		"cliff-wall ArrayMesh present"
	)
	if walls is MeshInstance3D and walls.mesh != null and walls.mesh.get_surface_count() == 1:
		wall_material = walls.mesh.surface_get_material(0)
		_check(
			wall_material is ShaderMaterial
			and wall_material.shader != null
			and wall_material.shader.resource_path == TerrainCliffWallMaterial.SHADER_PATH,
			"cliff walls use the N3c.3b stone PBR ShaderMaterial"
		)
		if wall_material is ShaderMaterial:
			_check(
				int(wall_material.get_shader_parameter("debug_stage")) == 0,
				"wall debug_stage matches the final stage"
			)
			var wall_bound := true
			for param: String in TerrainCliffWallMaterial.TEXTURE_PATHS.keys():
				if not (wall_material.get_shader_parameter(param) is Texture2D):
					wall_bound = false
			_check(wall_bound, "all three wall stone textures bound")
			if top_material is ShaderMaterial:
				var shared := true
				for param: String in TerrainCliffWallMaterial.TEXTURE_PATHS.keys():
					if (
						wall_material.get_shader_parameter(param)
						!= top_material.get_shader_parameter(param)
					):
						shared = false
				_check(shared, "wall stone textures shared in place with the top material")
		var wall_arrays: Array = walls.mesh.surface_get_arrays(0)
		var wall_vertices: PackedVector3Array = wall_arrays[Mesh.ARRAY_VERTEX]
		var wall_uvs: PackedVector2Array = wall_arrays[Mesh.ARRAY_TEX_UV]
		var wall_tangents: PackedFloat32Array = wall_arrays[Mesh.ARRAY_TANGENT]
		_check(
			wall_uvs.size() == wall_vertices.size(),
			"wall-local UVs baked per wall vertex"
		)
		_check(
			wall_tangents.size() == wall_vertices.size() * 4,
			"wall tangents baked per wall vertex"
		)
		var v_rule_ok := wall_vertices.size() > 0
		for i in mini(wall_vertices.size(), 500):
			if (
				absf(
					wall_uvs[i].y
					- wall_vertices[i].y * TerrainCliffWallMaterial.WALL_UV_V_SCALE
				) > 1e-5
			):
				v_rule_ok = false
				break
		_check(v_rule_ok, "baked wall V follows world Y * 0.35")

	# M cycles final -> ash_mask and must keep both shaders synchronized.
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	preview._unhandled_key_input(key)
	_check(preview.material_stage == "ash_mask", "M key cycles the material stage")
	if top_material is ShaderMaterial and wall_material is ShaderMaterial:
		_check(
			int(top_material.get_shader_parameter("debug_stage")) == 1
			and int(wall_material.get_shader_parameter("debug_stage")) == 1,
			"top and wall materials stay synchronized on the stage"
		)

	var camera = preview.get_node_or_null("OrbitCamera")
	_check(camera is Camera3D, "orbit camera present")
	if camera is Camera3D:
		_check(camera.current, "orbit camera is current")
		var state: Dictionary = camera.camera_state()
		_check(float(state["distance"]) > 0.0, "orbit camera framed (distance > 0)")

	var hud = preview.get_node_or_null("Hud")
	_check(hud is CanvasLayer, "HUD layer present")
	if hud is CanvasLayer:
		var labels: Array[String] = []
		_collect_labels(hud, labels)
		var backend_shown := false
		var controls_shown := false
		var stage_shown := false
		for text in labels:
			if text.begins_with("backend: %s" % preview.backend_used):
				backend_shown = true
			if text.contains("orbit") and text.contains("zoom"):
				controls_shown = true
			if text == "material: %s" % preview.material_stage:
				stage_shown = true
		_check(backend_shown, "HUD shows the backend actually used")
		_check(controls_shown, "HUD shows the desktop controls")
		_check(stage_shown, "HUD shows the active material stage")

	_finish()


# N3c.3a tangent basis on the real (non-flat) reference-map top surface:
# every tangent finite, unit length, orthogonal to its smooth normal, w = +1
# handedness, and deterministic across two independent builds. The reference
# map must actually exercise slopes in both X and Z (flat-only is
# insufficient). The mesh stores normals/tangents octahedral-compressed, so
# strict checks run on the exact helper output rebuilt from the mesh normals;
# the baked mesh tangents are compared within quantization tolerance.
func _check_reference_map_tangents(arrays: Array, mesh_tangents: PackedFloat32Array) -> void:
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var exact := TerrainSurfaceMaterial.build_top_surface_tangents(normals)
	var bad_finite := 0
	var bad_unit := 0
	var bad_orthogonal := 0
	var bad_handedness := 0
	var bad_mesh_match := 0
	var max_dot := 0.0
	var x_sloped := 0
	var z_sloped := 0
	for i in normals.size():
		var n := normals[i]
		var t := Vector3(exact[4 * i], exact[4 * i + 1], exact[4 * i + 2])
		var w := exact[4 * i + 3]
		if not (t.is_finite() and is_finite(w)):
			bad_finite += 1
			continue
		if absf(t.length() - 1.0) > 1e-5:
			bad_unit += 1
		var d := absf(t.dot(n))
		max_dot = maxf(max_dot, d)
		if d > 1e-5:
			bad_orthogonal += 1
		# Binormal cross(N, T) * w must point along dP/dv ∝ (0, nz/ny, -1).
		if w != 1.0 or n.cross(t).dot(Vector3(0.0, n.z / maxf(n.y, 1e-6), -1.0)) <= 0.0:
			bad_handedness += 1
		# Baked mesh tangent equals the exact one up to octahedral compression.
		var mt := Vector3(
			mesh_tangents[4 * i], mesh_tangents[4 * i + 1], mesh_tangents[4 * i + 2]
		)
		if mesh_tangents[4 * i + 3] != w or mt.distance_to(t) > 2e-3:
			bad_mesh_match += 1
		if absf(n.x) > 0.1:
			x_sloped += 1
		if absf(n.z) > 0.1:
			z_sloped += 1
	print("smoke: tangents max |dot(T, N)| = %s over %d vertices" % [max_dot, normals.size()])
	print("smoke: sloped normals: |nx|>0.1 on %d, |nz|>0.1 on %d vertices" % [x_sloped, z_sloped])
	_check(bad_finite == 0, "every reference-map tangent finite")
	_check(bad_unit == 0, "every reference-map tangent unit length")
	_check(bad_orthogonal == 0, "every tangent orthogonal to its smooth normal (<= 1e-5)")
	_check(bad_handedness == 0, "w = +1 with binormal along dP/dv on every vertex")
	_check(
		bad_mesh_match == 0,
		"baked mesh tangents match the exact build within compression tolerance"
	)
	_check(
		x_sloped > 100 and z_sloped > 100,
		"reference map exercises slopes in both X and Z (non-flat coverage)"
	)
	var rebuilt := TerrainSurfaceMaterial.build_top_surface_tangents(normals)
	_check(rebuilt == exact, "tangents deterministic across two independent builds")


func _collect_labels(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append(node.text)
	for child in node.get_children():
		_collect_labels(child, out)


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Terrain preview smoke tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
