# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_surface_geometry_components.gd
#
# N3c.1 surface-geometry builder on small synthetic WorldMaps (GDScript
# solver backend; no native extension required):
# - smooth-edge map -> no wall faces at all;
# - ordinary cliff map -> one quad per seam segment, oriented toward the
#   lower tile, no duplicates, no zero-area faces;
# - cliff-termination map -> crack-tip triangle at the interior case-1
#   corner, quads elsewhere, walls only on the authoritative cliff edge.
extends SceneTree

const WorldMapScript = preload("res://domain/world/world_map.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")
const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")

const ELEVATION_STEP := 0.4
const ELEVATION_BASE := 0
const CLIFF_THRESHOLD := 1
const SUBDIV := Ts08TerrainMathScript.DEFAULT_SURFACE_SUBDIVISIONS

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_smooth_edge_no_walls()
	_test_ordinary_cliff()
	_test_cliff_termination_crack_tip()
	_finish()


func _make_world_map(tiles_elevation: Dictionary):
	var tiles_dict: Dictionary = {}
	for coord: Vector2i in tiles_elevation.keys():
		tiles_dict[coord] = WorldMapScript.WorldTile.new(
			coord.x, coord.y, tiles_elevation[coord]
		)
	var edges: Dictionary = {}
	for coord: Vector2i in tiles_dict.keys():
		for offset: Vector2i in HexCoordScript.DIRECTIONS:
			var neighbor := coord + offset
			if not tiles_dict.has(neighbor):
				continue
			var edge_key := WorldMapScript.normalized_edge_key(coord, neighbor)
			if edges.has(edge_key):
				continue
			var delta: int = absi(
				tiles_dict[coord].elevation - tiles_dict[neighbor].elevation
			)
			var transition := WorldMapScript.EDGE_SMOOTH
			if delta > CLIFF_THRESHOLD:
				transition = WorldMapScript.EDGE_CLIFF
			var pair: Array = WorldMapScript.parse_edge_key(edge_key)
			edges[edge_key] = WorldMapScript.WorldEdge.new(pair[0], pair[1], transition)
	var identity = MapIdentityScript.new("synthetic_geometry_test", 1, "synthetic")
	return WorldMapScript.new(
		identity, ELEVATION_STEP, ELEVATION_BASE, CLIFF_THRESHOLD, tiles_dict, edges
	)


func _build_geometry(tiles_elevation: Dictionary) -> Array:
	var world_map = _make_world_map(tiles_elevation)
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var solve = Ts08HeightSolver.solve(world_map, build)
	var geometry = Ts08SurfaceGeometry.build(world_map, build, solve.heights)
	return [world_map, build, solve, geometry]


func _check_common_top_surface(build, geometry, label: String) -> void:
	_check(geometry != null, "%s: geometry build succeeded" % label)
	if geometry == null:
		return
	_check(geometry.top_vertex_count == build.node_count, "%s: top vertices == lattice nodes" % label)
	_check(
		geometry.top_triangles.size() == build.triangles.size() * 3,
		"%s: top triangles preserved" % label
	)
	var non_up := 0
	var tri_count: int = geometry.top_triangles.size() / 3
	for t in tri_count:
		var a: int = geometry.top_triangles[3 * t]
		var b: int = geometry.top_triangles[3 * t + 1]
		var c: int = geometry.top_triangles[3 * t + 2]
		var pa: Vector3 = geometry.top_positions[a]
		var pb: Vector3 = geometry.top_positions[b]
		var pc: Vector3 = geometry.top_positions[c]
		var ny := (pb.z - pa.z) * (pc.x - pa.x) - (pb.x - pa.x) * (pc.z - pa.z)
		if ny < 0.0:
			non_up += 1
	_check(non_up == 0, "%s: every top triangle oriented Y-up" % label)
	var bad_normals := 0
	for i in geometry.top_normals.size():
		if absf(geometry.top_normals[i].length() - 1.0) > 1e-5:
			bad_normals += 1
	_check(bad_normals == 0, "%s: smooth top normals unit length" % label)


func _check_wall_invariants(build, solve, geometry, label: String) -> void:
	var seen_keys: Dictionary = {}
	var duplicates := 0
	var zero_area := 0
	var bad_size := 0
	for record in geometry.wall_faces:
		var key := Ts08SurfaceGeometry._face_dedupe_key(record.vertex_indices)
		if seen_keys.has(key):
			duplicates += 1
		seen_keys[key] = true
		if record.vertex_indices.size() < 3 or record.vertex_indices.size() > 4:
			bad_size += 1
		var area: float = Ts08SurfaceGeometry.wall_face_area(
			record.vertex_indices, build, solve.heights
		)
		if area <= 1e-12:
			zero_area += 1
	_check(duplicates == 0, "%s: no duplicate wall faces" % label)
	_check(zero_area == 0, "%s: no zero-area wall faces" % label)
	_check(bad_size == 0, "%s: wall faces are triangles or quads only" % label)
	_check(
		geometry.wall_quad_count + geometry.wall_triangle_count == geometry.wall_faces.size(),
		"%s: quad + triangle counts match face list" % label
	)
	_check(
		geometry.wall_heights.size() == geometry.wall_faces.size(),
		"%s: one height delta per wall face" % label
	)


func _test_smooth_edge_no_walls() -> void:
	print("--- smooth edge: two hexes, delta 1 -> no walls ---")
	var parts := _build_geometry({Vector2i(0, 0): 0, Vector2i(1, 0): 1})
	var build = parts[1]
	var geometry = parts[3]
	_check_common_top_surface(build, geometry, "smooth")
	if geometry == null:
		return
	_check(geometry.wall_segment_count == 0, "smooth: zero wall segments")
	_check(geometry.wall_faces.is_empty(), "smooth: no wall faces on smooth edges")
	_check(geometry.wall_skipped_segment_count == 0, "smooth: nothing skipped")


func _test_ordinary_cliff() -> void:
	print("--- ordinary cliff: two hexes, delta 2 -> quads along the seam ---")
	var elevations := {Vector2i(0, 0): 0, Vector2i(1, 0): 2}
	var parts := _build_geometry(elevations)
	var world_map = parts[0]
	var build = parts[1]
	var solve = parts[2]
	var geometry = parts[3]
	_check_common_top_surface(build, geometry, "cliff")
	if geometry == null:
		return
	_check(geometry.wall_segment_count == SUBDIV, "cliff: one segment per subdivision step")
	_check(geometry.wall_skipped_segment_count == 0, "cliff: zero skipped segments")
	_check(geometry.wall_quad_count == SUBDIV, "cliff: all faces are quads")
	_check(geometry.wall_triangle_count == 0, "cliff: no crack-tip triangles")
	_check(geometry.wall_faces.size() == SUBDIV, "cliff: face count")
	_check_wall_invariants(build, solve, geometry, "cliff")
	var pair_ok := true
	var delta_ok := true
	for record in geometry.wall_faces:
		if record.tile_a != Vector2i(0, 0) or record.tile_b != Vector2i(1, 0):
			pair_ok = false
		if record.height_delta <= 0.0:
			delta_ok = false
	_check(pair_ok, "cliff: every face belongs to the authoritative cliff pair")
	_check(delta_ok, "cliff: positive height delta on every face")

	# Deterministic orientation toward the lower tile: the plane-XY Newell
	# normal must point from the higher tile's center toward the lower one's.
	var wrong_orientation := 0
	for record in geometry.wall_faces:
		var normal: Array = Ts08SurfaceGeometry._newell_normal(
			record.vertex_indices, build, solve.heights
		)
		var high := Vector2i(1, 0)
		var low := Vector2i(0, 0)
		var high_xy := Ts08TerrainMathScript.handdrawn_center_world_xy(high.x, high.y)
		var low_xy := Ts08TerrainMathScript.handdrawn_center_world_xy(low.x, low.y)
		var dir := (low_xy - high_xy).normalized()
		var nxy := Vector2(normal[0], normal[1])
		if nxy.length() <= 1e-12 or nxy.normalized().dot(dir) < 0.0:
			wrong_orientation += 1
	_check(wrong_orientation == 0, "cliff: faces oriented toward the lower tile")


func _test_cliff_termination_crack_tip() -> void:
	print("--- cliff termination: crack-tip triangle at interior case-1 corner ---")
	# A=(0,0) elev 0, B=(1,0) elev 2 (cliff), C=(0,1) elev 1 (smooth to both):
	# the corner shared by A, B, C is interior with exactly one cliff pair.
	var elevations := {Vector2i(0, 0): 0, Vector2i(1, 0): 2, Vector2i(0, 1): 1}
	var parts := _build_geometry(elevations)
	var build = parts[1]
	var solve = parts[2]
	var geometry = parts[3]
	_check_common_top_surface(build, geometry, "termination")
	if geometry == null:
		return
	_check(geometry.wall_segment_count == SUBDIV, "termination: one segment per step")
	_check(geometry.wall_skipped_segment_count == 0, "termination: zero skipped segments")
	_check(geometry.wall_triangle_count == 1, "termination: exactly one crack-tip triangle")
	_check(geometry.wall_quad_count == SUBDIV - 1, "termination: quads elsewhere")
	_check_wall_invariants(build, solve, geometry, "termination")
	var cliff_pair_only := true
	for record in geometry.wall_faces:
		if record.tile_a != Vector2i(0, 0) or record.tile_b != Vector2i(1, 0):
			cliff_pair_only = false
	_check(cliff_pair_only, "termination: no walls on the smooth edges")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Ts08SurfaceGeometry component tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
