# Headless test: godot --headless --path game -s res://domain/tests/test_world_map_foundation.gd
extends SceneTree

const HexWorldProjection = preload("res://domain/world/hex_world_projection.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const MapIdentity = preload("res://domain/world/map_identity.gd")
const WorldMap = preload("res://domain/world/world_map.gd")

var _total := 0
var _any_fail := false

const REFERENCE_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const CLIFF_EDGE_GOLDEN := 78
const SMOOTH_EDGE_GOLDEN := 374
const TOTAL_EDGE_GOLDEN := 452
# Shared canonical edge-stream digest (N5 cross-language parity). The same
# constant is pinned in server/tests/test_world_map_loader.py; any edge-rule
# change must update both loaders and both pinned constants together.
const EDGE_STREAM_DIGEST := "b3f613b49ef518cd4ee229ac7e89c12560e145cb235916dbc7d301e6d040cb7f"
const SQRT3 := 1.7320508075688772
const EPS := 0.0001


func _init() -> void:
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return

	_test_identity(world_map)
	_test_golden_counts(world_map)
	_test_bounds(world_map)
	_test_import_boundary_pins()
	_test_edge_normalization(world_map)
	_test_edge_stream_digest(world_map)
	_test_manifest_freshness()
	_finish()


func _test_identity(world_map) -> void:
	var identity = world_map.identity
	_check(identity.map_id == "handdrawn_test_map_full_01", "map_id")
	_check(identity.schema_version == 1, "schema_version")
	_check(identity.content_hash == REFERENCE_HASH, "content_hash")

	var clone = MapIdentity.from_dict(identity.to_dict())
	_check(identity.equals(clone), "MapIdentity round-trip equals")


func _test_golden_counts(world_map) -> void:
	_check(world_map.tile_count() == 168, "tile count")
	_check(world_map.edge_count() == TOTAL_EDGE_GOLDEN, "edge count")
	_check(world_map.cliff_edge_count() == CLIFF_EDGE_GOLDEN, "cliff edge count")
	_check(world_map.smooth_edge_count() == SMOOTH_EDGE_GOLDEN, "smooth edge count")
	var elev = world_map.elevation_range()
	_check(elev.x == 1 and elev.y == 6, "elevation range")


func _test_bounds(world_map) -> void:
	var q_bounds = world_map.bounds_q()
	var r_bounds = world_map.bounds_r()
	_check(q_bounds.x == -7 and q_bounds.y == 10, "q bounds")
	_check(r_bounds.x == 0 and r_bounds.y == 15, "r bounds")
	_check(world_map.elevation_base == 1, "default elevation_base")
	_check(absf(world_map.elevation_step - 0.4) < EPS, "elevation_step")


func _test_import_boundary_pins() -> void:
	_check_vec2(HexWorldProjection.axial_to_world_xz(1, 0), Vector2(SQRT3, 0.0), "pin (1,0)")
	_check_vec2(
		HexWorldProjection.axial_to_world_xz(0, 1),
		Vector2(SQRT3 * 0.5, 1.5),
		"pin (0,1)"
	)
	_check_vec2(
		HexWorldProjection.axial_to_world_xz(1, -1),
		Vector2(SQRT3 * 0.5, -1.5),
		"pin (1,-1)"
	)


func _test_edge_normalization(world_map) -> void:
	var seen: Dictionary = {}
	for edge in world_map.all_edges():
		var key := WorldMap.normalized_edge_key(edge.tile_a, edge.tile_b)
		_check(key == WorldMap.normalized_edge_key(edge.tile_b, edge.tile_a), "edge key symmetric")
		_check(not seen.has(key), "edge unique")
		seen[key] = true
		_check(
			WorldMap.compare_tile_coords(edge.tile_a, edge.tile_b) < 0,
			"edge stored min_lex first"
		)
		_check(
			edge.transition == WorldMap.EDGE_SMOOTH or edge.transition == WorldMap.EDGE_CLIFF,
			"edge transition valid"
		)


func _test_edge_stream_digest(world_map) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for edge in world_map.all_edges():
		var line := "%d;%d;%d;%d;%s\n" % [
			edge.tile_a.x, edge.tile_a.y, edge.tile_b.x, edge.tile_b.y, edge.transition
		]
		ctx.update(line.to_utf8_buffer())
	var digest := ctx.finish().hex_encode()
	_check(digest == EDGE_STREAM_DIGEST, "edge stream digest matches Python parity golden")


func _test_manifest_freshness() -> void:
	var manifest_path := "res://content/maps/manifest.json"
	_check(FileAccess.file_exists(manifest_path), "manifest exists")
	var text := FileAccess.get_file_as_string(manifest_path)
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary and parsed.has("maps"), "manifest shape")
	var maps: Array = parsed["maps"]
	_check(maps.size() >= 1, "manifest has entries")
	var entry: Dictionary = maps[0]
	_check(entry.get("content_hash") == REFERENCE_HASH, "manifest content_hash")
	_check(entry.get("map_id") == "handdrawn_test_map_full_01", "manifest map_id")


func _finish() -> void:
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check_vec2(actual: Vector2, expected: Vector2, label: String) -> void:
	_check(absf(actual.x - expected.x) < EPS and absf(actual.y - expected.y) < EPS, label)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)
