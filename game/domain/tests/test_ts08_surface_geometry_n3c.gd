# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_surface_geometry_n3c.gd
#
# N3c.1 reference-map wall/top-surface parity and determinism, using the
# Release native height-solver backend (BACKEND_NATIVE).
# - top surface: 74,129 vertices, 145,152 Y-up triangles, unit smooth normals;
# - walls: 936 segments/faces, 916 quads, 20 crack-tip triangles, 0 skipped;
# - canonical wall-face stream digest matches the committed Python Stage-3a
#   parity manifest (generate_ts08_n3c_wall_parity_manifest.py);
# - wall-height stats match the manifest within 1e-6 (heights come from the
#   Godot solver, not from N2);
# - two independent geometry builds are bit-identical;
# - no duplicate or zero-area wall faces.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const MANIFEST_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3c_wall_parity_v1.json"
const REFERENCE_MAP_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const N2_CONTENT_HASH := "4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce"

# Reference-map golden values (test-owned).
const EXPECTED_TOP_VERTEX_COUNT := 74129
const EXPECTED_TOP_TRIANGLE_COUNT := 145152
const EXPECTED_WALL_SEGMENT_COUNT := 936
const EXPECTED_WALL_FACE_COUNT := 936
const EXPECTED_WALL_QUAD_COUNT := 916
const EXPECTED_WALL_TRIANGLE_COUNT := 20
const EXPECTED_WALL_SKIPPED_COUNT := 0
const WALL_HEIGHT_STATS_TOL := 1e-6

var _total := 0
var _any_fail := false


# SHA-256 over accumulated UTF-8 lines (each terminated by "\n").
class StreamHasher extends RefCounted:
	var _ctx := HashingContext.new()
	var _buffer := ""

	func _init() -> void:
		_ctx.start(HashingContext.HASH_SHA256)

	func add_line(line: String) -> void:
		_buffer += line + "\n"
		if _buffer.length() >= 65536:
			_ctx.update(_buffer.to_utf8_buffer())
			_buffer = ""

	func hex_digest() -> String:
		if _buffer.length() > 0:
			_ctx.update(_buffer.to_utf8_buffer())
			_buffer = ""
		return _ctx.finish().hex_encode()


func _init() -> void:
	if not _require_native_extension():
		_finish()
		return

	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	_check(world_map.identity.content_hash == REFERENCE_MAP_HASH, "reference map hash")

	var t0 := Time.get_ticks_msec()
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var build_msec := Time.get_ticks_msec() - t0
	print("lattice build: %d ms (%d nodes)" % [build_msec, build.node_count])

	print("native height solve starting...")
	var solve = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(solve != null, "native height solve completed")
	if solve == null:
		_finish()
		return
	print("native solve: %d ms, converged=%s" % [solve.solve_msec, solve.converged])
	_check(solve.converged, "native CG converged")

	# --- geometry build A ---
	var geometry = Ts08SurfaceGeometry.build(world_map, build, solve.heights)
	_check(geometry != null, "geometry build A completed")
	if geometry == null:
		_finish()
		return
	print("geometry build A: %d ms" % geometry.build_msec)

	# --- accepted counts ---
	_check(
		geometry.top_vertex_count == EXPECTED_TOP_VERTEX_COUNT,
		"top vertex count %d" % EXPECTED_TOP_VERTEX_COUNT
	)
	_check(
		geometry.top_triangles.size() == EXPECTED_TOP_TRIANGLE_COUNT * 3,
		"top triangle count %d" % EXPECTED_TOP_TRIANGLE_COUNT
	)
	_check(
		geometry.wall_segment_count == EXPECTED_WALL_SEGMENT_COUNT,
		"wall segment count %d" % EXPECTED_WALL_SEGMENT_COUNT
	)
	_check(
		geometry.wall_faces.size() == EXPECTED_WALL_FACE_COUNT,
		"wall face count %d" % EXPECTED_WALL_FACE_COUNT
	)
	_check(
		geometry.wall_quad_count == EXPECTED_WALL_QUAD_COUNT,
		"wall quad count %d" % EXPECTED_WALL_QUAD_COUNT
	)
	_check(
		geometry.wall_triangle_count == EXPECTED_WALL_TRIANGLE_COUNT,
		"crack-tip triangle count %d" % EXPECTED_WALL_TRIANGLE_COUNT
	)
	_check(
		geometry.wall_skipped_segment_count == EXPECTED_WALL_SKIPPED_COUNT,
		"skipped segment count %d" % EXPECTED_WALL_SKIPPED_COUNT
	)

	# --- top-surface contract ---
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
	_check(non_up == 0, "every top triangle oriented Y-up")
	var bad_normals := 0
	for i in geometry.top_normals.size():
		if absf(geometry.top_normals[i].length() - 1.0) > 1e-5:
			bad_normals += 1
	_check(bad_normals == 0, "smooth top normals unit length")

	# --- wall invariants ---
	var seen_keys: Dictionary = {}
	var duplicates := 0
	var zero_area := 0
	for record in geometry.wall_faces:
		var key := Ts08SurfaceGeometry._face_dedupe_key(record.vertex_indices)
		if seen_keys.has(key):
			duplicates += 1
		seen_keys[key] = true
		var area: float = Ts08SurfaceGeometry.wall_face_area(
			record.vertex_indices, build, solve.heights
		)
		if area <= 1e-12:
			zero_area += 1
	_check(duplicates == 0, "no duplicate wall faces")
	_check(zero_area == 0, "no zero-area wall faces")

	# --- parity vs committed Python Stage-3a manifest ---
	var manifest := _load_manifest()
	if not manifest.is_empty():
		var counts: Dictionary = manifest["counts"]
		_check(
			int(counts["top_vertex_count"]) == geometry.top_vertex_count,
			"manifest top vertex count matches"
		)
		_check(
			int(counts["top_triangle_count"]) * 3 == geometry.top_triangles.size(),
			"manifest top triangle count matches"
		)
		_check(
			int(counts["wall_face_count"]) == geometry.wall_faces.size()
			and int(counts["wall_segment_count"]) == geometry.wall_segment_count
			and int(counts["wall_skipped_segment_count"]) == geometry.wall_skipped_segment_count
			and int(counts["wall_quad_count"]) == geometry.wall_quad_count
			and int(counts["wall_triangle_count"]) == geometry.wall_triangle_count,
			"manifest wall counts match"
		)
		var digest := _wall_faces_digest(geometry)
		var expected_digest: String = manifest["digests"]["wall_faces_sha256"]
		print("wall_faces_sha256 godot=%s" % digest)
		print("wall_faces_sha256 python=%s" % expected_digest)
		_check(digest == expected_digest, "wall-face/topology digest matches Python reference")

		var stats: Dictionary = manifest["wall_height_stats"]
		var h_min: float = geometry.wall_heights[0]
		var h_max: float = h_min
		var h_sum := 0.0
		for h in geometry.wall_heights:
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
			h_sum += h
		var h_mean := h_sum / float(geometry.wall_heights.size())
		print("wall heights: min=%.9f mean=%.9f max=%.9f" % [h_min, h_mean, h_max])
		_check(
			absf(h_min - float(stats["min"])) <= WALL_HEIGHT_STATS_TOL
			and absf(h_mean - float(stats["mean"])) <= WALL_HEIGHT_STATS_TOL
			and absf(h_max - float(stats["max"])) <= WALL_HEIGHT_STATS_TOL,
			"wall-height stats match manifest within 1e-6"
		)

	# --- determinism: independent rebuild is bit-identical ---
	var geometry_b = Ts08SurfaceGeometry.build(world_map, build, solve.heights)
	_check(geometry_b != null, "geometry build B completed")
	if geometry_b != null:
		print("geometry build B: %d ms" % geometry_b.build_msec)
		_check(
			geometry.top_triangles == geometry_b.top_triangles,
			"deterministic top triangles (bit-identical)"
		)
		_check(
			geometry.top_positions == geometry_b.top_positions
			and geometry.top_normals == geometry_b.top_normals,
			"deterministic top positions and normals (bit-identical)"
		)
		_check(
			_wall_faces_digest(geometry) == _wall_faces_digest(geometry_b)
			and geometry.wall_heights == geometry_b.wall_heights,
			"deterministic wall faces and heights (bit-identical)"
		)

	print("=== N3c.1 timings (reference map) ===")
	print("lattice build:      %d ms" % build_msec)
	print("native solve:       %d ms" % solve.solve_msec)
	print("geometry build:     %d ms" % geometry.build_msec)
	_finish()


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(
			false,
			"native extension descriptor missing at %s — build it first (.\\scripts\\build-native.ps1); this test must not silently fall back to GDScript" % DESCRIPTOR_PATH
		)
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		var status := GDExtensionManager.load_extension(DESCRIPTOR_PATH)
		_check(status == GDExtensionManager.LOAD_STATUS_OK, "extension loads (status %d)" % status)
		if status != GDExtensionManager.LOAD_STATUS_OK:
			return false
	_check(ClassDB.can_instantiate(&"EomTerrainNative"), "EomTerrainNative available")
	return ClassDB.can_instantiate(&"EomTerrainNative")


func _load_manifest() -> Dictionary:
	_check(FileAccess.file_exists(MANIFEST_PATH), "wall parity manifest fixture exists")
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_check(manifest is Dictionary, "manifest JSON parses")
	if not manifest is Dictionary:
		return {}
	_check(
		manifest.get("source_map_content_hash", "") == REFERENCE_MAP_HASH,
		"manifest reference map hash lock"
	)
	_check(
		manifest.get("source_n2_content_hash", "") == N2_CONTENT_HASH,
		"manifest N2 content hash lock"
	)
	return manifest


# Canonical wall-face stream, byte-identical to the Python generator:
# QA;RA;QB;RB;SEG;V0;V1;V2[;V3] per emitted face, in emit order.
func _wall_faces_digest(geometry) -> String:
	var hasher := StreamHasher.new()
	for record in geometry.wall_faces:
		var fields: Array = [
			str(record.tile_a.x),
			str(record.tile_a.y),
			str(record.tile_b.x),
			str(record.tile_b.y),
			str(record.segment_index),
		]
		for index in record.vertex_indices:
			fields.append(str(index))
		hasher.add_line(";".join(fields))
	return hasher.hex_digest()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Ts08SurfaceGeometry N3c tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
