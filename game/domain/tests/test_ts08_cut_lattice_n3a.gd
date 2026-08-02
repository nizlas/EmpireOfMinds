# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_cut_lattice_n3a.gd
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")

var _total := 0
var _any_fail := false

const MANIFEST_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1.json"
const REFERENCE_MAP_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const N2_CONTENT_HASH := "4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce"
const POS_KEY_TOL := 1e-6


func _round6(value: float) -> float:
	return round(value * 1000000.0) / 1000000.0


func _pos_key_from_node_key(key: Variant) -> Array:
	if key is Array and not key.is_empty():
		if key[0] is String and key.size() > 1 and key[1] is Array and key[1].size() == 2:
			return [_round6(float(key[1][0])), _round6(float(key[1][1]))]
		if key[0] is Array and key[0].size() == 2:
			return [_round6(float(key[0][0])), _round6(float(key[0][1]))]
	return [0.0, 0.0]


func _rounded_pos_key_pairs_from_keys(keys: Array) -> Array:
	var out: Array = []
	for key in keys:
		out.append(_pos_key_from_node_key(key))
	return out


func _init() -> void:
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	_check(world_map.identity.content_hash == REFERENCE_MAP_HASH, "reference map hash")

	var build_a := Ts08CutLattice.build_from_world_map(world_map)
	var build_b := Ts08CutLattice.build_from_world_map(world_map)
	_test_deterministic_rerun(build_a, build_b)

	var cliff_pairs := Ts08CutLattice._build_cliff_neighbor_pairs(world_map)
	var audit := Ts08CutLattice.audit_topology(build_a, cliff_pairs)
	_check(audit["passed"], "topology audit: %s" % str(audit["failures"]))
	_check(build_a.node_count == Ts08CutLattice.EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT, "node count golden")
	_check(build_a.triangles.size() == Ts08CutLattice.EXPECTED_TRIANGLE_COUNT, "triangle count golden")
	_check(build_a.pinned_world_y.size() == Ts08CutLattice.EXPECTED_CENTER_PIN_COUNT, "center pin count golden")
	_check(cliff_pairs.size() == Ts08CutLattice.EXPECTED_CLIFF_EDGE_COUNT, "cliff edge count golden")
	_check(
		audit["duplicated_cliff_line_nodes"] == Ts08CutLattice.EXPECTED_DUPLICATED_CLIFF_LINE_NODES,
		"duplicated cliff-line nodes golden"
	)
	_check(audit["adjacency_cross_cliff_violations"] == 0, "cross-cliff adjacency golden")

	var manifest := _load_parity_manifest()
	if manifest.is_empty():
		_finish()
		return
	_compare_parity_manifest(build_a, manifest)
	_finish()


func _test_deterministic_rerun(build_a, build_b) -> void:
	_check(build_a.node_count == build_b.node_count, "deterministic node_count")
	_check(_encode_node_keys(build_a.node_keys) == _encode_node_keys(build_b.node_keys), "deterministic node_keys")
	_check(build_a.node_sheet_ids == build_b.node_sheet_ids, "deterministic sheet_ids")
	_check(
		_rounded_pos_key_pairs_from_keys(build_a.node_keys)
		== _rounded_pos_key_pairs_from_keys(build_b.node_keys),
		"deterministic pos_keys"
	)
	_check(_triangle_set(build_a.triangles) == _triangle_set(build_b.triangles), "deterministic triangle set")


func _compare_parity_manifest(build, manifest: Dictionary) -> void:
	_check(manifest.get("source_n2_content_hash", "") == N2_CONTENT_HASH, "manifest N2 hash lock")
	_check(build.node_count == int(manifest.get("node_count", -1)), "manifest node_count parity")
	_check(build.triangles.size() == int(manifest.get("triangle_count", -1)), "manifest triangle_count parity")

	var manifest_nodes: Dictionary = manifest.get("nodes", {})
	var manifest_pos_keys: Array = manifest_nodes.get("pos_keys", [])
	var manifest_sheet_ids: Array = manifest_nodes.get("sheet_ids", [])
	var manifest_node_keys: Array = manifest_nodes.get("node_keys", [])

	for index in build.node_sheet_ids.size():
		if int(manifest_sheet_ids[index]) != build.node_sheet_ids[index]:
			_check(false, "sheet_id mismatch at %d" % index)
			return
	_check(true, "sheet_ids parity")

	for index in build.node_pos_keys.size():
		var manifest_pk: Array = manifest_pos_keys[index]
		var built_pk: Array = _pos_key_from_node_key(build.node_keys[index])
		if absf(built_pk[0] - _round6(float(manifest_pk[0]))) > POS_KEY_TOL:
			_check(false, "pos_key mismatch at %d" % index)
			return
		if absf(built_pk[1] - _round6(float(manifest_pk[1]))) > POS_KEY_TOL:
			_check(false, "pos_key mismatch at %d" % index)
			return
	_check(true, "pos_keys parity")

	_check(
		JSON.stringify(_encode_node_keys(build.node_keys))
		== JSON.stringify(_normalize_manifest_node_keys(manifest_node_keys)),
		"node_keys parity"
	)

	var manifest_positions: Array = manifest_nodes.get("positions_xyz", [])
	for index in build.node_godot_xz.size():
		var xz: Vector2 = build.node_godot_xz[index]
		var manifest_pos: Array = manifest_positions[index]
		if absf(xz.x - float(manifest_pos[0])) > 1e-6 or absf(xz.y - float(manifest_pos[2])) > 1e-6:
			_check(false, "godot xz mismatch at %d" % index)
			return
	_check(true, "godot xz parity")

	_check(
		_triangle_set(build.triangles) == _triangle_set_from_manifest(manifest.get("triangles", [])),
		"triangle set parity"
	)

	var manifest_pins: Array = manifest.get("center_pins", [])
	var pin_ok := true
	for pin in manifest_pins:
		var node_index: int = int(pin["node_index"])
		var q: int = int(pin["q"])
		var r: int = int(pin["r"])
		var pinned_y: float = float(pin["pinned_world_y"])
		if not build.pin_hex_by_node.has(node_index):
			pin_ok = false
			break
		var mapped: Vector2i = build.pin_hex_by_node[node_index]
		if mapped.x != q or mapped.y != r or absf(float(build.pinned_world_y[node_index]) - pinned_y) > 1e-6:
			pin_ok = false
			break
	_check(pin_ok, "center pin mapping parity")


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


func _pos_keys_close(pk: Vector2, manifest_pk: Array) -> bool:
	return (
		absf(_round6(pk.x) - _round6(float(manifest_pk[0]))) <= POS_KEY_TOL
		and absf(_round6(pk.y) - _round6(float(manifest_pk[1]))) <= POS_KEY_TOL
	)


func _encode_node_keys(keys: Array) -> Array:
	var encoded: Array = []
	for key in keys:
		encoded.append(Ts08CutLattice.encode_node_key(key))
	return encoded


func _normalize_manifest_node_keys(keys: Array) -> Array:
	var encoded: Array = []
	for key in keys:
		if key is Array:
			var copy: Array = []
			for part in key:
				copy.append(_normalize_manifest_part(part))
			encoded.append(copy)
		else:
			encoded.append(key)
	return encoded


func _normalize_manifest_part(part: Variant) -> Variant:
	if part is Array and part.size() == 2:
		return [float(part[0]), float(part[1])]
	if part is float and part == floor(part):
		return int(part)
	return part


func _encode_node_keys_from_manifest(keys: Array) -> Array:
	var encoded: Array = []
	for key in keys:
		if key is Array:
			var copy: Array = []
			for part in key:
				if part is Array and part.size() == 2:
					copy.append([float(part[0]), float(part[1])])
				else:
					copy.append(part)
			encoded.append(copy)
		else:
			encoded.append(key)
	return encoded


func _triangle_set(triangles: Array) -> Array:
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


func _triangle_set_from_manifest(triangles: Array) -> Array:
	var out: Array = []
	for tri in triangles:
		var sorted_tri: Array = [int(tri[0]), int(tri[1]), int(tri[2])]
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
