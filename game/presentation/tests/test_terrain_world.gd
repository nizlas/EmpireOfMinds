# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_world.gd
#
# N3c.6 shared runtime terrain world (game/presentation/world/terrain_world.gd):
# - builds the accepted N3 chain from a caller-supplied WorldMap and a
#   caller-supplied solver backend (no backend policy inside the component);
# - deterministic construction: two independent builds produce bit-identical
#   meshes, collision faces, and picker lookup;
# - parity with the accepted preview output: same named nodes, same
#   reference-map counts, same materials, and collision equal to the
#   rendered geometry;
# - picking propagates as presentation output (terrain_picked signal +
#   last_pick), suitable for later N4 selection/overlays;
# - safe teardown/rebuild: freeing the world and building a new one in the
#   same tree keeps physics picking working;
# - the input WorldMap is never mutated.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")
const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")
const TerrainCollision = preload("res://presentation/terrain_collision.gd")
const TerrainPicker = preload("res://presentation/terrain_picker.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

const EXPECTED_COUNTS := {
	"nodes": 74129,
	"top_triangles": 145152,
	"wall_faces": 936,
	"wall_quads": 916,
	"wall_triangles": 20,
	"collision_top_triangles": 145152,
	"collision_wall_triangles": 1852,
}

var _total := 0
var _any_fail := false
var _signal_picks: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	if not _require_native_extension():
		_finish()
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "caller-side WorldMap loads")
	if world_map == null:
		_finish()
		return

	# --- input snapshots (non-mutation contract) ---
	var map_hash: String = world_map.identity.content_hash
	var tile_count: int = world_map.tile_count()
	var edge_count: int = world_map.edge_count()
	var cliff_count: int = world_map.cliff_edge_count()
	var coords: Array[Vector2i] = world_map.tile_coords()
	var sample_elevations := {}
	for k in 8:
		var coord: Vector2i = coords[(coords.size() * k) / 8]
		sample_elevations[coord] = world_map.tile_elevation(coord.x, coord.y)

	# --- build A (in tree) ---
	var world_a = TerrainWorldScript.new()
	world_a.name = "TerrainWorldA"
	root.add_child(world_a)
	var ok_a: bool = world_a.build(world_map, Ts08HeightSolver.BACKEND_NATIVE)
	_check(ok_a, "world A builds from a caller-supplied WorldMap (native backend)")
	if not ok_a:
		_finish()
		return
	_check(
		world_a.backend_used == Ts08HeightSolver.BACKEND_NATIVE,
		"backend stays caller-supplied"
	)

	# --- parity with the accepted preview output ---
	var counts_ok := true
	for key in EXPECTED_COUNTS:
		if int(world_a.counts.get(key, -1)) != int(EXPECTED_COUNTS[key]):
			counts_ok = false
	_check(counts_ok, "reference-map counts match the accepted preview output")
	var top = world_a.get_node_or_null("TopSurface")
	var walls = world_a.get_node_or_null("CliffWalls")
	var collision = world_a.get_node_or_null("TerrainCollision")
	var camera = world_a.get_node_or_null("OrbitCamera")
	_check(
		top is MeshInstance3D and walls is MeshInstance3D
		and collision is StaticBody3D and camera is Camera3D,
		"named TopSurface/CliffWalls/TerrainCollision/OrbitCamera nodes assembled"
	)
	_check(camera.current, "orbit camera framed and current")
	var top_mat: Material = top.mesh.surface_get_material(0)
	var wall_mat: Material = walls.mesh.surface_get_material(0)
	_check(
		top_mat is ShaderMaterial
		and top_mat.shader.resource_path == TerrainSurfaceMaterial.SHADER_PATH
		and wall_mat is ShaderMaterial
		and wall_mat.shader.resource_path == TerrainCliffWallMaterial.SHADER_PATH,
		"accepted N3c.3a/3b materials bound"
	)
	var top_arrays: Array = top.mesh.surface_get_arrays(0)
	_check(
		top_arrays[Mesh.ARRAY_VERTEX] == world_a.geometry.top_positions,
		"top mesh uses the exact solver-generated positions"
	)
	var top_shape: ConcavePolygonShape3D = collision.get_node("TopSurfaceCollision").shape
	var wall_shape: ConcavePolygonShape3D = collision.get_node("CliffWallCollision").shape
	_check(
		top_shape.get_faces() == TerrainCollision.build_top_faces(world_a.geometry)
		and wall_shape.get_faces() == TerrainCollision.build_wall_faces(world_a.geometry),
		"collision faces equal the accepted derived collision (bit-identical)"
	)
	_check(
		wall_shape.get_faces() == top_wall_vertices(walls),
		"wall collision faces equal the rendered wall vertices (bit-identical)"
	)
	_check(
		world_a._wall_triangle_map == TerrainPicker.build_wall_triangle_map(world_a.geometry),
		"picker lookup equals the accepted N3c.5 metadata"
	)

	# --- deterministic construction (independent build, off tree) ---
	var world_b = TerrainWorldScript.new()
	var ok_b: bool = world_b.build(world_map, Ts08HeightSolver.BACKEND_NATIVE)
	_check(ok_b, "world B builds independently")
	if ok_b:
		var top_b = world_b.get_node("TopSurface")
		var arrays_a: Array = top.mesh.surface_get_arrays(0)
		var arrays_b: Array = top_b.mesh.surface_get_arrays(0)
		_check(
			arrays_a[Mesh.ARRAY_VERTEX] == arrays_b[Mesh.ARRAY_VERTEX]
			and arrays_a[Mesh.ARRAY_INDEX] == arrays_b[Mesh.ARRAY_INDEX]
			and arrays_a[Mesh.ARRAY_TEX_UV] == arrays_b[Mesh.ARRAY_TEX_UV],
			"top mesh deterministic across independent builds (bit-identical)"
		)
		_check(
			top_wall_vertices(world_b.get_node("CliffWalls")) == top_wall_vertices(walls),
			"wall mesh deterministic across independent builds (bit-identical)"
		)
		var collision_b = world_b.get_node("TerrainCollision")
		_check(
			collision_b.get_node("TopSurfaceCollision").shape.get_faces() == top_shape.get_faces()
			and collision_b.get_node("CliffWallCollision").shape.get_faces() == wall_shape.get_faces(),
			"collision deterministic across independent builds (bit-identical)"
		)
		_check(
			world_b._wall_triangle_map == world_a._wall_triangle_map
			and world_b.counts == world_a.counts,
			"picker lookup and counts deterministic"
		)
		world_b.free()

	# --- picking propagation (presentation output) ---
	await physics_frame
	await physics_frame
	world_a.terrain_picked.connect(func(pick: Dictionary) -> void: _signal_picks.append(pick))
	var center: Vector2 = root.get_visible_rect().size / 2.0
	var pick: Dictionary = world_a.pick_at_screen_position(center)
	_check(
		pick.get("kind", "") in [TerrainPicker.KIND_TILE, TerrainPicker.KIND_CLIFF],
		"center-screen pick resolves to a canonical identity"
	)
	print("world A center pick = %s" % str(pick))
	_check(
		_signal_picks.size() == 1 and _signal_picks[0] == pick,
		"terrain_picked signal carries the resolved pick"
	)
	_check(world_a.last_pick == pick, "last_pick mirrors the latest result")
	var pick_repeat: Dictionary = world_a.pick_at_screen_position(center)
	_check(pick_repeat == pick, "pick resolution deterministic")

	# --- safe teardown/rebuild ---
	root.remove_child(world_a)
	world_a.free()
	await physics_frame
	var world_c = TerrainWorldScript.new()
	world_c.name = "TerrainWorldC"
	root.add_child(world_c)
	var ok_c: bool = world_c.build(world_map, Ts08HeightSolver.BACKEND_NATIVE)
	_check(ok_c, "rebuild after teardown succeeds")
	if ok_c:
		await physics_frame
		await physics_frame
		var pick_c: Dictionary = world_c.pick_at_screen_position(center)
		_check(
			pick_c == pick,
			"rebuilt world resolves the same deterministic pick (physics rebound cleanly)"
		)
		root.remove_child(world_c)
		world_c.free()

	# --- input WorldMap non-mutation ---
	var elevations_ok := true
	for coord in sample_elevations:
		if world_map.tile_elevation(coord.x, coord.y) != sample_elevations[coord]:
			elevations_ok = false
	_check(
		world_map.identity.content_hash == map_hash
		and world_map.tile_count() == tile_count
		and world_map.edge_count() == edge_count
		and world_map.cliff_edge_count() == cliff_count
		and elevations_ok,
		"input WorldMap never mutated"
	)

	_finish()


static func top_wall_vertices(walls_node: MeshInstance3D) -> PackedVector3Array:
	var arrays: Array = walls_node.mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


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
	print("TerrainWorld tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
