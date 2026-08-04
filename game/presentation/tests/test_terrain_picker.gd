# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_picker.gd
#
# N3c.5 deterministic tile/cliff-edge picking:
# - representative top raycasts resolve to the expected canonical tiles
#   (hit X/Z through HexWorldProjection.world_xz_to_axial, validated against
#   WorldMap);
# - representative first/middle/last wall quads and a crack tip resolve to
#   the expected authoritative cliff edges with BOTH adjacent tiles (locked
#   rule: never silently the lower or upper tile);
# - the wall triangle metadata aligns one-to-one with the 1,852 wall
#   collision triangles; both fan triangles of every quad share one source
#   WallFace; every entry references an existing authoritative WorldMap
#   cliff edge;
# - lookup and results are deterministic;
# - miss / foreign collider / invalid or missing face indices fail without
#   guessing;
# - picking mutates neither WorldMap, geometry, nor collision data.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const TerrainPicker = preload("res://presentation/terrain_picker.gd")
const TerrainCollision = preload("res://presentation/terrain_collision.gd")
const WorldMapScript = preload("res://domain/world/world_map.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const EXPECTED_WALL_TRIANGLE_COUNT := 1852

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	if not _require_native_extension():
		_finish()
		return
	var world_map = MapContentLoader.load_reference_world_map()
	var lattice = Ts08CutLattice.build_from_world_map(world_map)
	print("native height solve starting...")
	var solve = Ts08HeightSolver.solve(world_map, lattice, false, Ts08HeightSolver.BACKEND_NATIVE)
	var geometry = Ts08SurfaceGeometry.build(world_map, lattice, solve.heights)
	_check(world_map != null and solve.converged and geometry != null, "reference chain builds")

	# --- input snapshots (no-mutation contract) ---
	var map_hash: String = world_map.identity.content_hash
	var tile_count: int = world_map.tile_count()
	var edge_count: int = world_map.edge_count()
	var heights_before: PackedFloat64Array = solve.heights.duplicate()
	var top_positions_before: PackedVector3Array = geometry.top_positions.duplicate()
	var top_triangles_before: PackedInt32Array = geometry.top_triangles.duplicate()
	var wall_identity_before: Array = []
	for record in geometry.wall_faces:
		wall_identity_before.append([
			record.tile_a, record.tile_b, record.segment_index,
			record.vertex_indices.duplicate(),
		])

	# --- wall triangle metadata ---
	var wall_map: PackedInt32Array = TerrainPicker.build_wall_triangle_map(geometry)
	_check(
		wall_map.size() == EXPECTED_WALL_TRIANGLE_COUNT,
		"metadata aligns one-to-one with the 1,852 wall collision triangles"
	)
	_check(
		wall_map == TerrainPicker.build_wall_triangle_map(geometry),
		"wall triangle metadata deterministic (bit-identical)"
	)

	# Both fan triangles of every quad share one source WallFace; crack tips
	# emit exactly one entry; the walk covers the whole metadata array.
	var cursor := 0
	var alignment_ok := true
	for face_index in geometry.wall_faces.size():
		var vertex_count: int = geometry.wall_faces[face_index].vertex_indices.size()
		for _t in vertex_count - 2:
			if cursor >= wall_map.size() or wall_map[cursor] != face_index:
				alignment_ok = false
				break
			cursor += 1
		if not alignment_ok:
			break
	_check(
		alignment_ok and cursor == wall_map.size(),
		"both quad fan triangles share one WallFace; crack tips map once; full coverage"
	)

	# Every metadata entry references an existing authoritative cliff edge.
	var edges_ok := true
	for face_index in wall_map:
		var record = geometry.wall_faces[face_index]
		if not world_map.has_edge_between(record.tile_a, record.tile_b):
			edges_ok = false
			break
		if world_map.edge_between(record.tile_a, record.tile_b).transition != WorldMapScript.EDGE_CLIFF:
			edges_ok = false
			break
	_check(edges_ok, "every wall lookup entry references an authoritative WorldMap cliff edge")

	# --- physics setup ---
	var body := TerrainCollision.build_static_body(geometry)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.find_world_3d().direct_space_state
	_check(space != null, "physics space available")

	_check_tile_picks(space, world_map, geometry, wall_map)
	_check_cliff_picks(space, world_map, geometry, wall_map)
	_check_rejections(body, world_map, geometry, wall_map)

	# --- determinism of resolution ---
	var tile_hit := _ray(space, _tile_center_ray_origin(world_map, 0), Vector3.DOWN * 40.0)
	var pick_a := TerrainPicker.resolve_pick(tile_hit, world_map, geometry, wall_map)
	var pick_b := TerrainPicker.resolve_pick(tile_hit, world_map, geometry, wall_map)
	_check(not pick_a.is_empty() and pick_a == pick_b, "pick resolution deterministic")

	# --- no-mutation contract ---
	_check(
		world_map.identity.content_hash == map_hash
		and world_map.tile_count() == tile_count
		and world_map.edge_count() == edge_count,
		"WorldMap unchanged"
	)
	_check(solve.heights == heights_before, "solved heights unchanged (bit-identical)")
	var geometry_unchanged: bool = (
		geometry.top_positions == top_positions_before
		and geometry.top_triangles == top_triangles_before
		and geometry.wall_faces.size() == wall_identity_before.size()
	)
	if geometry_unchanged:
		for i in geometry.wall_faces.size():
			var record = geometry.wall_faces[i]
			var before: Array = wall_identity_before[i]
			if (
				record.tile_a != before[0] or record.tile_b != before[1]
				or record.segment_index != before[2] or record.vertex_indices != before[3]
			):
				geometry_unchanged = false
				break
	_check(geometry_unchanged, "surface geometry unchanged (bit-identical)")
	var top_faces_expected := TerrainCollision.build_top_faces(geometry)
	var wall_faces_expected := TerrainCollision.build_wall_faces(geometry)
	_check(
		body.get_node("TopSurfaceCollision").shape.get_faces() == top_faces_expected
		and body.get_node("CliffWallCollision").shape.get_faces() == wall_faces_expected,
		"collision data unchanged (bit-identical)"
	)

	_finish()


# Downward rays over representative tile centers must resolve to those tiles.
func _check_tile_picks(space, world_map, geometry, wall_map: PackedInt32Array) -> void:
	var coords: Array[Vector2i] = world_map.tile_coords()
	var samples := 0
	var resolved := 0
	for k in 12:
		var coord: Vector2i = coords[(coords.size() * k) / 12]
		samples += 1
		var hit := _ray(space, _tile_center_ray_origin(world_map, (coords.size() * k) / 12), Vector3.DOWN * 40.0)
		if hit.is_empty():
			continue
		var pick := TerrainPicker.resolve_pick(hit, world_map, geometry, wall_map)
		if (
			pick.get("kind", "") == TerrainPicker.KIND_TILE
			and pick.get("tile", Vector2i(9999, 9999)) == coord
		):
			resolved += 1
	print("tile picks: %d samples, %d resolved to the expected canonical tile" % [samples, resolved])
	_check(samples == 12 and resolved == samples, "representative top raycasts resolve to the expected tiles")


# Rays into representative wall faces (first/middle/last quad + a crack tip)
# must resolve to the exact authoritative edge of their source WallFace.
func _check_cliff_picks(space, world_map, geometry, wall_map: PackedInt32Array) -> void:
	var quad_indices: Array = []
	var tip_index := -1
	for i in geometry.wall_faces.size():
		if geometry.wall_faces[i].vertex_indices.size() == 4:
			quad_indices.append(i)
		elif tip_index < 0:
			tip_index = i
	var candidates: Array = [
		quad_indices[0],
		quad_indices[quad_indices.size() / 2],
		quad_indices[quad_indices.size() - 1],
	]
	if tip_index >= 0:
		candidates.append(tip_index)

	var resolved := 0
	var face_index_valid := 0
	for face_index: int in candidates:
		var record = geometry.wall_faces[face_index]
		var face: PackedInt32Array = record.vertex_indices
		var centroid := Vector3.ZERO
		for node in face:
			centroid += geometry.top_positions[node]
		centroid /= float(face.size())
		var p0: Vector3 = geometry.top_positions[face[0]]
		var p1: Vector3 = geometry.top_positions[face[1]]
		var p2: Vector3 = geometry.top_positions[face[2]]
		var outward := (p1 - p0).cross(p2 - p0).normalized()
		var hit := _ray(space, centroid + outward * 0.5, -outward)
		if hit.is_empty():
			continue
		if int(hit.get("face_index", -1)) >= 0:
			face_index_valid += 1
		var pick := TerrainPicker.resolve_pick(hit, world_map, geometry, wall_map)
		var expected_key: String = WorldMapScript.normalized_edge_key(record.tile_a, record.tile_b)
		var expected_tiles: Array = WorldMapScript.parse_edge_key(expected_key)
		if (
			pick.get("kind", "") == TerrainPicker.KIND_CLIFF
			and pick.get("edge_key", "") == expected_key
			and pick.get("tile_a", Vector2i(9999, 9999)) == expected_tiles[0]
			and pick.get("tile_b", Vector2i(9999, 9999)) == expected_tiles[1]
		):
			resolved += 1
	print("cliff picks: %d candidates, %d resolved to the expected edge" % [candidates.size(), resolved])
	_check(
		face_index_valid == candidates.size(),
		"physics reports a valid face_index on every wall hit"
	)
	_check(
		resolved == candidates.size(),
		"first/middle/last quads and a crack tip resolve to the expected cliff edges"
	)


# Miss, foreign collider, and invalid/missing face indices must produce no
# pick — never a guess.
func _check_rejections(body: StaticBody3D, world_map, geometry, wall_map: PackedInt32Array) -> void:
	_check(
		TerrainPicker.resolve_pick({}, world_map, geometry, wall_map).is_empty(),
		"miss produces no pick"
	)
	var foreign := StaticBody3D.new()
	foreign.name = "SomethingElse"
	var foreign_hit := {
		"collider": foreign, "shape": 0, "face_index": 0, "position": Vector3.ZERO,
	}
	_check(
		TerrainPicker.resolve_pick(foreign_hit, world_map, geometry, wall_map).is_empty(),
		"foreign collider produces no pick"
	)
	foreign.free()
	var negative := {"collider": body, "shape": 1, "face_index": -1, "position": Vector3.ZERO}
	_check(
		TerrainPicker.resolve_pick(negative, world_map, geometry, wall_map).is_empty(),
		"face_index -1 on the wall shape produces no pick"
	)
	var out_of_range := {
		"collider": body, "shape": 1,
		"face_index": EXPECTED_WALL_TRIANGLE_COUNT, "position": Vector3.ZERO,
	}
	_check(
		TerrainPicker.resolve_pick(out_of_range, world_map, geometry, wall_map).is_empty(),
		"out-of-range face_index produces no pick"
	)
	var missing := {"collider": body, "shape": 1, "position": Vector3.ZERO}
	_check(
		TerrainPicker.resolve_pick(missing, world_map, geometry, wall_map).is_empty(),
		"missing face_index produces no pick"
	)
	var off_map := {
		"collider": body, "shape": 0, "face_index": 0,
		"position": Vector3(1000.0, 0.0, 1000.0),
	}
	_check(
		TerrainPicker.resolve_pick(off_map, world_map, geometry, wall_map).is_empty(),
		"top hit resolving outside the WorldMap produces no pick"
	)


func _tile_center_ray_origin(world_map, coord_index: int) -> Vector3:
	var coords: Array[Vector2i] = world_map.tile_coords()
	var coord: Vector2i = coords[coord_index]
	var xz: Vector2 = HexWorldProjectionScript.axial_to_world_xz(coord.x, coord.y)
	return Vector3(xz.x, 20.0, xz.y)


func _ray(space, from: Vector3, direction: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, from + direction)
	return space.intersect_ray(params)


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
	print("TerrainPicker tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
