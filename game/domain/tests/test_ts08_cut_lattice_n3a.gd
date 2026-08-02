# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_cut_lattice_n3a.gd
#
# N3a topology parity against the N2 golden via the compact digest manifest
# (game/domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1.json).
# The manifest stores counts plus SHA-256 digests over complete canonical
# streams; this test rebuilds the same streams from the native lattice and
# compares digests. Canonical encoding is documented in the manifest itself
# and in tools/blender/terrain/generate_ts08_n3a_parity_manifest.py.
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")

var _total := 0
var _any_fail := false

const MANIFEST_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1.json"
const REFERENCE_MAP_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const N2_CONTENT_HASH := "4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce"

# Reference-map golden values (test-only; production lattice code is generic).
const EXPECTED_NODE_COUNT := 74129
const EXPECTED_TRIANGLE_COUNT := 145152
const EXPECTED_CENTER_PIN_COUNT := 168
const EXPECTED_CLIFF_EDGE_COUNT := 78
const EXPECTED_DUPLICATED_CLIFF_LINE_NODES := 861

const QUANT_SCALE := 1000000.0


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
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	_check(world_map.identity.content_hash == REFERENCE_MAP_HASH, "reference map hash")

	var build_a := Ts08CutLattice.build_from_world_map(world_map)
	var build_b := Ts08CutLattice.build_from_world_map(world_map)
	var digests_a := _compute_stream_digests(build_a)
	var digests_b := _compute_stream_digests(build_b)

	# Two independent full builds must be identical.
	_check(build_a.node_count == build_b.node_count, "deterministic node_count")
	_check(digests_a == digests_b, "deterministic rerun (all stream digests equal)")

	# Generic production audit: zero cross-cliff adjacency on the built lattice.
	var audit := Ts08CutLattice.audit_topology(build_a)
	_check(audit["passed"], "topology audit: %s" % str(audit["failures"]))
	_check(audit["adjacency_cross_cliff_violations"] == 0, "zero cross-cliff adjacency")

	# Reference-map golden counts (test-owned, not production constants).
	var cliff_pairs := Ts08CutLattice._build_cliff_neighbor_pairs(world_map)
	_check(build_a.node_count == EXPECTED_NODE_COUNT, "node count golden")
	_check(build_a.triangles.size() == EXPECTED_TRIANGLE_COUNT, "triangle count golden")
	_check(build_a.pinned_world_y.size() == EXPECTED_CENTER_PIN_COUNT, "center pin count golden")
	_check(cliff_pairs.size() == EXPECTED_CLIFF_EDGE_COUNT, "cliff edge count golden")
	_check(
		audit["duplicated_cliff_line_nodes"] == EXPECTED_DUPLICATED_CLIFF_LINE_NODES,
		"duplicated cliff-line nodes golden"
	)

	var manifest := _load_parity_manifest()
	if manifest.is_empty():
		_finish()
		return
	_compare_parity_manifest(build_a, digests_a, manifest)
	_finish()


func _compare_parity_manifest(build, digests: Dictionary, manifest: Dictionary) -> void:
	_check(int(manifest.get("schema_version", -1)) == 2, "manifest schema_version")
	_check(manifest.get("source_n2_content_hash", "") == N2_CONTENT_HASH, "manifest N2 hash lock")

	var counts: Dictionary = manifest.get("counts", {})
	_check(build.node_count == int(counts.get("node_count", -1)), "manifest node_count parity")
	_check(
		build.triangles.size() == int(counts.get("triangle_count", -1)),
		"manifest triangle_count parity"
	)
	_check(
		build.pinned_world_y.size() == int(counts.get("center_pin_count", -1)),
		"manifest center_pin_count parity"
	)
	_check(
		Ts08CutLattice._count_duplicated_cliff_line_nodes(build)
		== int(counts.get("duplicated_cliff_line_nodes", -1)),
		"manifest duplicated_cliff_line_nodes parity"
	)

	var manifest_digests: Dictionary = manifest.get("digests", {})
	for name in [
		"node_identities_sha256",
		"pos_keys_sha256",
		"sheet_ids_sha256",
		"godot_xz_sha256",
		"triangles_sha256",
		"center_pins_sha256",
	]:
		_check(
			str(digests.get(name, "")) != "" and digests.get(name, "") == manifest_digests.get(name, "?"),
			"digest parity: %s" % name
		)


# Round half away from zero onto the 1e-6 integer grid; matches
# quantize_micro in generate_ts08_n3a_parity_manifest.py.
func _quantize_micro(value: float) -> int:
	var scaled := value * QUANT_SCALE
	if scaled >= 0.0:
		return int(floor(scaled + 0.5))
	return -int(floor(-scaled + 0.5))


# Pos-key parts stored inside node keys are float64 Arrays; BuildResult's
# Vector2 fields are float32 and must not feed the canonical streams.
func _pos_key_parts_from_node_key(key: Array) -> Array:
	if key[0] is String:
		return key[1]
	return key[0]


func _node_identity_line(key: Array, pkx: int, pky: int) -> String:
	if key[0] is String:
		var tag: String = key[0]
		if tag == "crack_tip":
			return "crack_tip;%d;%d" % [pkx, pky]
		if tag == "corner_split":
			return "corner_split;%d;%d;%d" % [pkx, pky, int(key[2])]
		if tag == "cliff_line":
			return "cliff_line;%d;%d;%d;%d;%d" % [pkx, pky, int(key[2]), int(key[3]), int(key[4])]
		push_error("Unknown node key tag: %s" % tag)
		return "invalid"
	if key.size() == 5:
		return "tile_corner;%d;%d;%d;%d;%d;%d" % [
			pkx, pky, int(key[1]), int(key[2]), int(key[3]), int(key[4])
		]
	if key.size() == 4:
		return "tile_pos_sheet;%d;%d;%d;%d;%d" % [pkx, pky, int(key[1]), int(key[2]), int(key[3])]
	push_error("Unknown node key shape: %s" % str(key))
	return "invalid"


func _compute_stream_digests(build) -> Dictionary:
	var identities := StreamHasher.new()
	var pos_keys := StreamHasher.new()
	var sheet_ids := StreamHasher.new()
	var godot_xz := StreamHasher.new()
	for index in build.node_keys.size():
		var key: Array = build.node_keys[index]
		var pk: Array = _pos_key_parts_from_node_key(key)
		var pkx := _quantize_micro(float(pk[0]))
		var pky := _quantize_micro(float(pk[1]))
		identities.add_line(_node_identity_line(key, pkx, pky))
		pos_keys.add_line("%d;%d" % [pkx, pky])
		sheet_ids.add_line("%d" % build.node_sheet_ids[index])
		# godot x == plane x, godot z == -plane y; on the 1e-6 grid these are
		# exactly the pos-key micro-ints (equivalence asserted when the
		# manifest is generated from N2).
		godot_xz.add_line("%d;%d" % [pkx, -pky])
	var triangles := StreamHasher.new()
	for tri in _canonical_triangle_set(build.triangles):
		triangles.add_line("%d;%d;%d" % [tri[0], tri[1], tri[2]])
	var pins := StreamHasher.new()
	var pin_indices: Array = build.pinned_world_y.keys()
	pin_indices.sort()
	for node_index in pin_indices:
		var hex: Vector2i = build.pin_hex_by_node[node_index]
		pins.add_line("%d;%d;%d;%d" % [
			node_index,
			hex.x,
			hex.y,
			_quantize_micro(float(build.pinned_world_y[node_index])),
		])
	return {
		"node_identities_sha256": identities.hex_digest(),
		"pos_keys_sha256": pos_keys.hex_digest(),
		"sheet_ids_sha256": sheet_ids.hex_digest(),
		"godot_xz_sha256": godot_xz.hex_digest(),
		"triangles_sha256": triangles.hex_digest(),
		"center_pins_sha256": pins.hex_digest(),
	}


func _canonical_triangle_set(triangles: Array) -> Array:
	var out: Array = []
	for tri in triangles:
		var sorted_tri: Array = [tri[0], tri[1], tri[2]]
		sorted_tri.sort()
		out.append(sorted_tri)
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2]
	)
	return out


func _load_parity_manifest() -> Dictionary:
	_check(FileAccess.file_exists(MANIFEST_PATH), "parity manifest readable at %s" % MANIFEST_PATH)
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "parity manifest JSON parses")
	if not parsed is Dictionary:
		return {}
	return parsed


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Ts08CutLattice N3a tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
