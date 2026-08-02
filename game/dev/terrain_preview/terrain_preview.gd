# Development-only N3b terrain preview. NOT runtime-world integration.
#
# Builds the top surface from the N3a cut lattice (X/Z positions, triangles)
# and the N3b solver heights (Y) — solver output only, never N2 heights.
# Neutral material, simple lighting, fixed oblique camera framing the map.
# No cliff walls, no production materials, no collision, no gameplay.
#
# Open interactively:
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn
# Render a PNG and quit (written to game/dev/terrain_preview/output/, ignored):
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --screenshot
extends Node3D

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const SCREENSHOT_PATH := "res://dev/terrain_preview/output/terrain_preview.png"


func _ready() -> void:
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
	print("terrain_preview: solving heights (about a minute)...")
	var solve = Ts08HeightSolver.solve(world_map, build, true)
	print("terrain_preview: solve %d ms, converged=%s" % [solve.solve_msec, solve.converged])

	var mesh := _build_surface_mesh(build, solve)
	print("terrain_preview: mesh AABB=%s" % mesh.get_aabb())
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	_add_lighting()
	var aabb := mesh.get_aabb()
	_add_camera(aabb)

	if "--screenshot" in OS.get_cmdline_user_args():
		_save_screenshot()


func _build_surface_mesh(build, solve) -> ArrayMesh:
	var vertices := PackedVector3Array()
	vertices.resize(build.node_count)
	for i in build.node_count:
		var xz: Vector2 = build.node_godot_xz[i]
		vertices[i] = Vector3(xz.x, solve.heights[i], xz.y)

	# Apply Y-up triangle winding, mirroring the N2 exporter
	# (_orient_upward_triangle_y_up): the raw Stage-0 lattice stores its two
	# barycentric triangle families with opposite plane orientation, so each
	# triangle is oriented counter-clockwise from above first. Godot front
	# faces are clockwise, so the index buffer emits the reversed order.
	# Smooth per-vertex normals come from area-weighted accumulation of the
	# upward face normals.
	var indices := PackedInt32Array()
	indices.resize(build.triangles.size() * 3)
	var normals := PackedVector3Array()
	normals.resize(build.node_count)
	var cursor := 0
	for tri in build.triangles:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		var pa := vertices[a]
		var pb := vertices[b]
		var pc := vertices[c]
		var ny := (pb.z - pa.z) * (pc.x - pa.x) - (pb.x - pa.x) * (pc.z - pa.z)
		if ny < 0.0:
			var swap := b
			b = c
			c = swap
			var swap_p := pb
			pb = pc
			pc = swap_p
		var face_normal := (pb - pa).cross(pc - pa)
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal
		indices[cursor] = a
		indices[cursor + 1] = c
		indices[cursor + 2] = b
		cursor += 3
	for i in normals.size():
		if normals[i].length_squared() > 0.0:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
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
