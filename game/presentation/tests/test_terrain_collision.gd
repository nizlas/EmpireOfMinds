# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_collision.gd
#
# N3c.4 deterministic terrain collision (derived data only):
# - reference-map counts: 145,152 top triangles and 1,852 wall triangles;
# - every emitted collision triangle finite and non-degenerate;
# - collision triangles correspond exactly to the rendered geometry (top
#   faces re-derived independently from the accepted index order; wall faces
#   equal to the rendered wall vertex stream);
# - bit-identical output across independent builds;
# - physics raycasts hit representative terrain centers at the solved
#   surface height (top shape) and representative cliff walls (wall shape),
#   with the single-sided physics normals facing up / outward;
# - collision creation does not mutate WorldMap, the lattice, the heights,
#   or the surface geometry.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const TerrainCollision = preload("res://presentation/terrain_collision.gd")
const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# Reference-map golden values (test-owned, from the accepted N3c slices).
const EXPECTED_TOP_TRIANGLE_COUNT := 145152
const EXPECTED_WALL_TRIANGLE_COUNT := 1852
# Physics hit tolerance: float32 positions + physics-engine face tolerance.
const RAY_HIT_TOLERANCE := 1e-3

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	if not _require_native_extension():
		_finish()
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	var lattice = Ts08CutLattice.build_from_world_map(world_map)
	print("native height solve starting...")
	var solve = Ts08HeightSolver.solve(world_map, lattice, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(solve != null and solve.converged, "native height solve converged")
	if solve == null:
		_finish()
		return
	var geometry = Ts08SurfaceGeometry.build(world_map, lattice, solve.heights)
	_check(geometry != null, "surface geometry builds")
	if geometry == null:
		_finish()
		return

	# --- input snapshots (no-mutation contract) ---
	var map_hash: String = world_map.identity.content_hash
	var lattice_node_count: int = lattice.node_count
	var lattice_xz: Array[Vector2] = lattice.node_godot_xz.duplicate()
	var heights_before: PackedFloat64Array = solve.heights.duplicate()
	var top_positions_before: PackedVector3Array = geometry.top_positions.duplicate()
	var top_triangles_before: PackedInt32Array = geometry.top_triangles.duplicate()
	var top_normals_before: PackedVector3Array = geometry.top_normals.duplicate()
	var wall_indices_before: Array = []
	for record in geometry.wall_faces:
		wall_indices_before.append(record.vertex_indices.duplicate())

	# --- build shapes (timing + memory-relevant counts) ---
	var t0 := Time.get_ticks_msec()
	var shapes: Dictionary = TerrainCollision.build_shapes(geometry)
	var build_msec := Time.get_ticks_msec() - t0
	var top_shape: ConcavePolygonShape3D = shapes["top_shape"]
	var wall_shape: ConcavePolygonShape3D = shapes["wall_shape"]
	var top_faces := top_shape.get_faces()
	var wall_faces := wall_shape.get_faces()
	print(
		"collision shapes: %d ms (%d top + %d wall triangles; %d + %d face vertices)"
		% [
			build_msec, shapes["top_triangle_count"], shapes["wall_triangle_count"],
			top_faces.size(), wall_faces.size(),
		]
	)
	_check(
		shapes["top_triangle_count"] == EXPECTED_TOP_TRIANGLE_COUNT
		and top_faces.size() == EXPECTED_TOP_TRIANGLE_COUNT * 3,
		"top shape carries 145,152 triangles"
	)
	_check(
		shapes["wall_triangle_count"] == EXPECTED_WALL_TRIANGLE_COUNT
		and wall_faces.size() == EXPECTED_WALL_TRIANGLE_COUNT * 3,
		"wall shape carries 1,852 triangles"
	)

	_check_faces_finite_nondegenerate(top_faces, "top")
	_check_faces_finite_nondegenerate(wall_faces, "wall")

	# --- exact correspondence with the rendered geometry ---
	var expected_top := PackedVector3Array()
	expected_top.resize(geometry.top_triangles.size())
	var cursor := 0
	for t in geometry.top_triangles.size() / 3:
		expected_top[cursor] = geometry.top_positions[geometry.top_triangles[3 * t]]
		expected_top[cursor + 1] = geometry.top_positions[geometry.top_triangles[3 * t + 2]]
		expected_top[cursor + 2] = geometry.top_positions[geometry.top_triangles[3 * t + 1]]
		cursor += 3
	_check(
		top_faces == expected_top,
		"top collision faces equal the rendered index order exactly (bit-identical)"
	)
	var rendered_walls: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	_check(
		wall_faces == rendered_walls["vertices"],
		"wall collision faces equal the rendered wall vertex stream (bit-identical)"
	)

	# --- determinism across independent builds ---
	var shapes_again: Dictionary = TerrainCollision.build_shapes(geometry)
	_check(
		shapes_again["top_shape"].get_faces() == top_faces
		and shapes_again["wall_shape"].get_faces() == wall_faces,
		"collision faces bit-identical across independent builds"
	)

	# --- static body assembly ---
	var body := TerrainCollision.build_static_body(geometry)
	_check(
		body is StaticBody3D and body.name == StringName("TerrainCollision"),
		"one clearly named static terrain body"
	)
	var top_node := body.get_node_or_null("TopSurfaceCollision")
	var wall_node := body.get_node_or_null("CliffWallCollision")
	_check(
		top_node is CollisionShape3D and top_node.shape is ConcavePolygonShape3D
		and wall_node is CollisionShape3D and wall_node.shape is ConcavePolygonShape3D,
		"separate named top and wall collision shapes"
	)

	# --- physics raycasts ---
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.find_world_3d().direct_space_state
	_check(space != null, "physics space available")
	if space != null:
		_check_top_raycasts(space, body, geometry)
		_check_wall_raycasts(space, body, geometry)

	# --- no-mutation contract ---
	_check(world_map.identity.content_hash == map_hash, "WorldMap unchanged")
	_check(
		lattice.node_count == lattice_node_count and lattice.node_godot_xz == lattice_xz,
		"lattice unchanged"
	)
	_check(solve.heights == heights_before, "solved heights unchanged (bit-identical)")
	var geometry_unchanged: bool = (
		geometry.top_positions == top_positions_before
		and geometry.top_triangles == top_triangles_before
		and geometry.top_normals == top_normals_before
		and geometry.wall_faces.size() == wall_indices_before.size()
	)
	if geometry_unchanged:
		for i in geometry.wall_faces.size():
			if geometry.wall_faces[i].vertex_indices != wall_indices_before[i]:
				geometry_unchanged = false
				break
	_check(geometry_unchanged, "surface geometry unchanged (bit-identical)")

	_finish()


func _check_faces_finite_nondegenerate(faces: PackedVector3Array, label: String) -> void:
	var bad_finite := 0
	var degenerate := 0
	for t in faces.size() / 3:
		var a := faces[3 * t]
		var b := faces[3 * t + 1]
		var c := faces[3 * t + 2]
		if not (a.is_finite() and b.is_finite() and c.is_finite()):
			bad_finite += 1
			continue
		if (b - a).cross(c - a).length_squared() <= 0.0:
			degenerate += 1
	_check(bad_finite == 0, "every %s collision triangle finite" % label)
	_check(degenerate == 0, "every %s collision triangle non-degenerate (area > 0)" % label)


# Downward rays over representative terrain points must hit the TOP shape at
# the solved surface height. Sample vertices are spread deterministically
# across the map; positions whose XZ is shared by duplicated seam nodes
# (upper/lower cliff sheets) are skipped, since the height there is
# intentionally multivalued.
func _check_top_raycasts(space: PhysicsDirectSpaceState3D, body: StaticBody3D, geometry) -> void:
	var xz_counts: Dictionary = {}
	for p in geometry.top_positions:
		var key := "%.6f|%.6f" % [p.x, p.z]
		xz_counts[key] = int(xz_counts.get(key, 0)) + 1

	var n: int = geometry.top_positions.size()
	var samples := 0
	var hits := 0
	var height_ok := 0
	var shape_ok := 0
	var max_err := 0.0
	for k in 16:
		var index := (n * k) / 16 + 137
		if index >= n:
			continue
		var p: Vector3 = geometry.top_positions[index]
		if int(xz_counts["%.6f|%.6f" % [p.x, p.z]]) > 1:
			continue
		samples += 1
		var params := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, p.y + 10.0, p.z), Vector3(p.x, p.y - 10.0, p.z)
		)
		var hit := space.intersect_ray(params)
		if hit.is_empty() or hit["collider"] != body:
			continue
		hits += 1
		var err: float = absf(float(hit["position"].y) - p.y)
		max_err = maxf(max_err, err)
		if err <= RAY_HIT_TOLERANCE:
			height_ok += 1
		if int(hit["shape"]) == 0:
			shape_ok += 1
	print(
		"top raycasts: %d samples, %d hits, max height error %s"
		% [samples, hits, max_err]
	)
	_check(samples >= 10, "enough unique-XZ terrain sample points")
	_check(hits == samples, "every top raycast hits the terrain body")
	_check(height_ok == hits, "every top hit is at the solved surface height (<= 1e-3)")
	_check(shape_ok == hits, "every top hit lands on the top-surface shape (index 0)")


# Horizontal rays from outside representative cliff walls must hit the WALL
# shape on its outward (lower-tile-facing) front face.
func _check_wall_raycasts(space: PhysicsDirectSpaceState3D, body: StaticBody3D, geometry) -> void:
	var candidates: Array = []
	var quad_indices: Array = []
	var tip_index := -1
	for i in geometry.wall_faces.size():
		var face: PackedInt32Array = geometry.wall_faces[i].vertex_indices
		if face.size() == 4:
			quad_indices.append(i)
		elif tip_index < 0:
			tip_index = i
	candidates.append(quad_indices[0])
	candidates.append(quad_indices[quad_indices.size() / 2])
	candidates.append(quad_indices[quad_indices.size() - 1])
	if tip_index >= 0:
		candidates.append(tip_index)

	var hits := 0
	var shape_ok := 0
	var plane_ok := 0
	for face_index: int in candidates:
		var face: PackedInt32Array = geometry.wall_faces[face_index].vertex_indices
		var centroid := Vector3.ZERO
		for node in face:
			centroid += geometry.top_positions[node]
		centroid /= float(face.size())
		var p0: Vector3 = geometry.top_positions[face[0]]
		var p1: Vector3 = geometry.top_positions[face[1]]
		var p2: Vector3 = geometry.top_positions[face[2]]
		# Outward normal of the oriented record (points toward the lower tile).
		var outward := (p1 - p0).cross(p2 - p0).normalized()
		var params := PhysicsRayQueryParameters3D.create(
			centroid + outward * 0.5, centroid - outward * 0.5
		)
		var hit := space.intersect_ray(params)
		if hit.is_empty() or hit["collider"] != body:
			continue
		hits += 1
		if int(hit["shape"]) == 1:
			shape_ok += 1
		if absf((Vector3(hit["position"]) - centroid).dot(outward)) <= RAY_HIT_TOLERANCE:
			plane_ok += 1
	print("wall raycasts: %d candidates, %d hits" % [candidates.size(), hits])
	_check(hits == candidates.size(), "every wall raycast hits the terrain body")
	_check(shape_ok == hits, "every wall hit lands on the cliff-wall shape (index 1)")
	_check(plane_ok == hits, "every wall hit lies on the wall face plane (<= 1e-3)")


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
	print("TerrainCollision tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
