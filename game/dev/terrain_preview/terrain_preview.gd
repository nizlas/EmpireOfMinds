# Development-only N3b/N3c terrain preview. NOT runtime-world integration.
#
# Consumes the domain-only Ts08SurfaceGeometry builder (N3c.1): top surface
# from the N3a cut lattice plus N3b solver heights, and Stage-3a cliff-wall
# faces along authoritative WorldMap cliff edges (darker neutral material).
# Solver output only, never N2 heights. Neutral materials, simple lighting,
# fixed oblique camera framing the map. No production materials, no
# collision, no gameplay.
#
# Open interactively (GDScript solver, about a minute):
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn
# Fast generation with the built native extension (fails clearly if absent):
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --native
# Render a PNG and quit (written to game/dev/terrain_preview/output/, ignored):
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --screenshot [--native]
extends Node3D

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")

const SCREENSHOT_PATH := "res://dev/terrain_preview/output/terrain_preview.png"
const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"


func _ready() -> void:
	var use_native := "--native" in OS.get_cmdline_user_args()
	if use_native and not _load_native_extension():
		push_error(
			"terrain_preview: --native requested but the GDExtension is unavailable; "
			+ "build it first (.\\scripts\\build-native.ps1)"
		)
		get_tree().quit(1)
		return

	print("terrain_preview: loading WorldMap...")
	var world_map = MapContentLoader.load_reference_world_map()
	if world_map == null:
		push_error("terrain_preview: reference WorldMap failed to load")
		get_tree().quit(1)
		return
	print("terrain_preview: building cut lattice...")
	var t0 := Time.get_ticks_msec()
	var build = Ts08CutLattice.build_from_world_map(world_map)
	print("terrain_preview: lattice %d ms (%d nodes)" % [Time.get_ticks_msec() - t0, build.node_count])

	var backend: String = (
		Ts08HeightSolver.BACKEND_NATIVE if use_native else Ts08HeightSolver.BACKEND_GDSCRIPT
	)
	if use_native:
		print("terrain_preview: solving heights (native backend)...")
	else:
		print("terrain_preview: solving heights (GDScript backend, about a minute)...")
	var solve = Ts08HeightSolver.solve(world_map, build, not use_native, backend)
	if solve == null:
		push_error("terrain_preview: height solve failed (backend %s)" % backend)
		get_tree().quit(1)
		return
	print("terrain_preview: solve %d ms, converged=%s" % [solve.solve_msec, solve.converged])

	print("terrain_preview: building surface geometry...")
	var geometry = Ts08SurfaceGeometry.build(world_map, build, solve.heights)
	if geometry == null:
		push_error("terrain_preview: surface geometry build failed")
		get_tree().quit(1)
		return
	print(
		"terrain_preview: geometry %d ms (%d wall faces: %d quads, %d crack-tip triangles)"
		% [
			geometry.build_msec,
			geometry.wall_faces.size(),
			geometry.wall_quad_count,
			geometry.wall_triangle_count,
		]
	)

	var top_mesh := _build_top_mesh(geometry)
	var top_instance := MeshInstance3D.new()
	top_instance.mesh = top_mesh
	add_child(top_instance)

	var wall_mesh := _build_wall_mesh(geometry)
	if wall_mesh != null:
		var wall_instance := MeshInstance3D.new()
		wall_instance.mesh = wall_mesh
		add_child(wall_instance)

	_add_lighting()
	var aabb := top_mesh.get_aabb()
	print("terrain_preview: mesh AABB=%s" % aabb)
	_add_camera(aabb)

	if "--screenshot" in OS.get_cmdline_user_args():
		_save_screenshot()


func _load_native_extension() -> bool:
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR_PATH):
		return false
	if not GDExtensionManager.is_extension_loaded(NATIVE_DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(NATIVE_DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			return false
	return ClassDB.can_instantiate(&"EomTerrainNative")


# Top surface from the builder's Y-up oriented triangles and smooth normals.
# Godot front faces are clockwise, so the index buffer emits each triangle
# in reversed order.
func _build_top_mesh(geometry) -> ArrayMesh:
	var tri_count: int = geometry.top_triangles.size() / 3
	var indices := PackedInt32Array()
	indices.resize(geometry.top_triangles.size())
	var cursor := 0
	for t in tri_count:
		indices[cursor] = geometry.top_triangles[3 * t]
		indices[cursor + 1] = geometry.top_triangles[3 * t + 2]
		indices[cursor + 2] = geometry.top_triangles[3 * t + 1]
		cursor += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geometry.top_positions
	arrays[Mesh.ARRAY_NORMAL] = geometry.top_normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.58, 0.58, 0.56)
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


# Wall faces are stored counter-clockwise around the outward normal that
# points toward the lower tile (plane->Godot is a rotation, so the winding
# carries over). Flat shading: fan-triangulate each polygon with duplicated
# vertices and per-face normals; reversed index order for Godot front faces.
func _build_wall_mesh(geometry) -> ArrayMesh:
	if geometry.wall_faces.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for record in geometry.wall_faces:
		var face: PackedInt32Array = record.vertex_indices
		var p0: Vector3 = geometry.top_positions[face[0]]
		for i in range(1, face.size() - 1):
			var p1: Vector3 = geometry.top_positions[face[i]]
			var p2: Vector3 = geometry.top_positions[face[i + 1]]
			var normal := (p1 - p0).cross(p2 - p0)
			if normal.length_squared() > 0.0:
				normal = normal.normalized()
			else:
				normal = Vector3.UP
			# Reversed order (p0, p2, p1) for Godot's clockwise front faces.
			vertices.append(p0)
			vertices.append(p2)
			vertices.append(p1)
			for _n in 3:
				normals.append(normal)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Simple darker neutral wall material (dev preview only).
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.32, 0.30)
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _add_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	light.light_energy = 1.0
	add_child(light)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.15, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.85)
	environment.ambient_light_energy = 0.35
	world_environment.environment = environment
	add_child(world_environment)


func _add_camera(aabb: AABB) -> void:
	var center := aabb.get_center()
	var extent := maxf(aabb.size.x, aabb.size.z)
	var camera := Camera3D.new()
	# Fixed oblique view framing the whole map.
	var direction := Vector3(0.62, 0.78, 0.70).normalized()
	camera.position = center + direction * (1.1 * extent)
	add_child(camera)
	camera.look_at(center, Vector3.UP)
	camera.far = 4.0 * extent + 100.0
	camera.current = true


func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var global_path := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var error := image.save_png(global_path)
	if error == OK:
		print("terrain_preview: screenshot saved to %s" % global_path)
	else:
		push_error("terrain_preview: failed to save screenshot (%d)" % error)
	get_tree().quit(0 if error == OK else 1)
