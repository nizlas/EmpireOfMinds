# N3c.6 shared runtime 3D terrain world (presentation/integration-side).
#
# The single reusable assembly of the accepted N3 chain:
#   caller-supplied WorldMap -> Ts08CutLattice -> Ts08HeightSolver
#   -> Ts08SurfaceGeometry -> top/wall ArrayMesh + N3c.3a/3b materials
#   -> N3c.4 TerrainCollision -> orbit camera -> N3c.5 tile/cliff picking.
#
# Locked dual-entry direction (docs/CURRENT_ARCHITECTURE.md,
# docs/PHASE_PLAN.md): remote multiplayer runs against the remote
# authoritative server; the future one-PC debug mode runs against a locally
# running authoritative server. Both use the same client-server API/action
# path and both feed THIS scene an already constructed authoritative
# WorldMap (server-fed WorldMap path = N7). This component:
# - never loads or constructs the WorldMap itself (the caller owns it) and
#   never mutates it — read-only input;
# - never constructs gameplay state and has no dependency on the legacy
#   HexMap / Scenario path;
# - never chooses the solver backend: the backend string is caller-supplied
#   (Ts08HeightSolver.BACKEND_*). There is deliberately no backend policy
#   here — the dev preview and the dev runtime harness own their own
#   policies.
#
# Picking is exposed as presentation output only: `terrain_picked(pick)` is
# emitted for every resolved left-click (tile / cliff / no pick as defined
# by TerrainPicker) and `last_pick` mirrors the latest result — suitable
# input for later N4 selection/overlays. No selection state, overlays,
# rings, or gameplay here.
#
# Lighting: the N3c.7 production rig (terrain_lighting.gd) is built here so
# every entry (dev harness, dev preview, future server-fed gameplay) shares
# the exact same deterministic lighting/environment.
extends Node3D

signal terrain_picked(pick: Dictionary)

const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")
const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")
const TerrainCollision = preload("res://presentation/terrain_collision.gd")
const TerrainPicker = preload("res://presentation/terrain_picker.gd")
const TerrainLighting = preload("res://presentation/world/terrain_lighting.gd")
const OrbitCameraScript = preload("res://presentation/world/orbit_camera.gd")

# Read-only after build() (references, never copies; never mutated here).
var world_map = null
var geometry = null
var backend_used := ""
var material_stage := "final"
var timings: Dictionary = {}
var counts: Dictionary = {}
var last_pick: Dictionary = {}

var camera: Camera3D = null

var _top_material: ShaderMaterial = null
var _wall_material: ShaderMaterial = null
var _wall_triangle_map := PackedInt32Array()
var _pending_pick_screen_pos := Vector2.ZERO
var _pick_requested := false


# Builds the full terrain world from an already constructed authoritative
# WorldMap. `backend` must be a Ts08HeightSolver backend id (caller-supplied;
# no policy here). Returns false (with push_error) on failure.
func build(
	p_world_map,
	backend: String,
	p_material_stage := "final",
	verbose_solve := false
) -> bool:
	if p_world_map == null:
		push_error("terrain_world: build requires a constructed WorldMap")
		return false
	world_map = p_world_map
	backend_used = backend
	material_stage = p_material_stage

	var t0 := Time.get_ticks_msec()
	var lattice = Ts08CutLattice.build_from_world_map(world_map)
	timings["lattice_msec"] = Time.get_ticks_msec() - t0
	print("terrain_world: lattice %d ms (%d nodes)" % [timings["lattice_msec"], lattice.node_count])

	var solve = Ts08HeightSolver.solve(world_map, lattice, verbose_solve, backend)
	if solve == null or not solve.converged:
		push_error("terrain_world: height solve failed (backend %s)" % backend)
		return false
	timings["solve_msec"] = solve.solve_msec
	print("terrain_world: solve %d ms, converged=%s" % [solve.solve_msec, solve.converged])

	geometry = Ts08SurfaceGeometry.build(world_map, lattice, solve.heights)
	if geometry == null:
		push_error("terrain_world: surface geometry build failed")
		return false
	timings["geometry_msec"] = geometry.build_msec
	print(
		"terrain_world: geometry %d ms (%d wall faces: %d quads, %d crack-tip triangles)"
		% [
			geometry.build_msec,
			geometry.wall_faces.size(),
			geometry.wall_quad_count,
			geometry.wall_triangle_count,
		]
	)
	counts = {
		"nodes": lattice.node_count,
		"top_triangles": geometry.top_triangles.size() / 3,
		"wall_faces": geometry.wall_faces.size(),
		"wall_quads": geometry.wall_quad_count,
		"wall_triangles": geometry.wall_triangle_count,
	}

	var t_mesh := Time.get_ticks_msec()
	var top_mesh := _build_top_mesh()
	if top_mesh == null:
		return false
	var top_instance := MeshInstance3D.new()
	top_instance.name = "TopSurface"
	top_instance.mesh = top_mesh
	add_child(top_instance)
	var wall_mesh := _build_wall_mesh()
	if wall_mesh != null:
		var wall_instance := MeshInstance3D.new()
		wall_instance.name = "CliffWalls"
		wall_instance.mesh = wall_mesh
		add_child(wall_instance)
	timings["mesh_msec"] = Time.get_ticks_msec() - t_mesh

	var t_collision := Time.get_ticks_msec()
	var collision_body := TerrainCollision.build_static_body(geometry)
	add_child(collision_body)
	_wall_triangle_map = TerrainPicker.build_wall_triangle_map(geometry)
	timings["collision_msec"] = Time.get_ticks_msec() - t_collision
	var top_shape: ConcavePolygonShape3D = collision_body.get_node(
		TerrainCollision.TOP_SHAPE_NAME
	).shape
	var wall_shape_node := collision_body.get_node_or_null(TerrainCollision.WALL_SHAPE_NAME)
	counts["collision_top_triangles"] = top_shape.get_faces().size() / 3
	counts["collision_wall_triangles"] = (
		wall_shape_node.shape.get_faces().size() / 3 if wall_shape_node != null else 0
	)
	print(
		"terrain_world: collision %d ms (%d top + %d wall triangles)"
		% [
			timings["collision_msec"],
			counts["collision_top_triangles"],
			counts["collision_wall_triangles"],
		]
	)

	add_child(TerrainLighting.build_rig(top_mesh.get_aabb()))
	camera = OrbitCameraScript.new()
	camera.name = "OrbitCamera"
	add_child(camera)
	camera.configure_from_aabb(top_mesh.get_aabb())
	camera.current = true
	return true


# Sets the material debug stage on both terrain shaders (presentation-side
# diagnostic capability of the N3c.3a/3b materials; dev UIs own the cycling).
func set_material_stage(stage: String) -> void:
	if _top_material == null:
		return
	material_stage = stage
	TerrainSurfaceMaterial.set_debug_stage(_top_material, stage)
	if _wall_material != null:
		TerrainCliffWallMaterial.set_debug_stage(_wall_material, stage)


# Resolves one screen position against the terrain collision and publishes
# the result (last_pick + terrain_picked). Presentation output only.
func pick_at_screen_position(screen_pos: Vector2) -> Dictionary:
	var pick := _resolve_screen_pick(screen_pos)
	last_pick = pick
	terrain_picked.emit(pick)
	return pick


# N3c.5: a plain left-click requests a pick raycast (Shift+LMB stays pan;
# the orbit camera keeps seeing the same events). The raycast itself runs in
# _physics_process, where the physics space is safe to query.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed or button.shift_pressed:
		return
	_pending_pick_screen_pos = button.position
	_pick_requested = true


func _physics_process(_delta: float) -> void:
	if not _pick_requested:
		return
	_pick_requested = false
	pick_at_screen_position(_pending_pick_screen_pos)


func _resolve_screen_pick(screen_pos: Vector2) -> Dictionary:
	if camera == null or world_map == null or geometry == null:
		return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	return TerrainPicker.resolve_pick(hit, world_map, geometry, _wall_triangle_map)


# Top surface from the builder's Y-up oriented triangles and smooth normals,
# with the N3c.3a world-anchored UVs and slope-aware tangents. Godot front
# faces are clockwise, so the index buffer emits each triangle in reversed
# order.
func _build_top_mesh() -> ArrayMesh:
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
	arrays[Mesh.ARRAY_TEX_UV] = TerrainSurfaceMaterial.build_world_uv_array(geometry.top_positions)
	arrays[Mesh.ARRAY_TANGENT] = TerrainSurfaceMaterial.build_top_surface_tangents(
		geometry.top_normals
	)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_top_material = TerrainSurfaceMaterial.create_material(material_stage)
	if _top_material == null:
		push_error("terrain_world: failed to create the terrain surface material")
		return null
	mesh.surface_set_material(0, _top_material)
	return mesh


# Wall faces are stored counter-clockwise around the outward normal that
# points toward the lower tile. Flat shading: the N3c.3b module emits the
# deterministic fan triangulation with wall-local UVs and per-triangle
# tangents (identical vertex stream to the collision shape).
func _build_wall_mesh() -> ArrayMesh:
	if geometry.wall_faces.is_empty():
		return null
	var wall_arrays: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = wall_arrays["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = wall_arrays["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = wall_arrays["uvs"]
	arrays[Mesh.ARRAY_TANGENT] = wall_arrays["tangents"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_wall_material = TerrainCliffWallMaterial.create_material(material_stage)
	if _wall_material == null:
		push_error("terrain_world: failed to create the cliff-wall material")
		return mesh
	mesh.surface_set_material(0, _wall_material)
	return mesh
