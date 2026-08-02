# Headless test: godot --headless --path game -s res://domain/tests/test_map_content_loader.gd
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const WorldMap = preload("res://domain/world/world_map.gd")

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_valid_minimal_fixture()
	_test_invalid_fixtures()
	_test_raw_hash_from_bytes()
	_finish()


func _test_valid_minimal_fixture() -> void:
	var path := "res://domain/tests/fixtures/world/envelope_valid_minimal.json"
	var result = MapContentLoader.try_load_world_map_from_res_path(path)
	_check(result["ok"], "valid minimal fixture loads")
	if not result["ok"]:
		return
	var world_map = result["world_map"]
	_check(world_map.tile_count() == 2, "minimal tile count")
	_check(world_map.cliff_edge_count() == 1, "minimal cliff edge from delta rule")


func _test_invalid_fixtures() -> void:
	var cases := [
		"res://domain/tests/fixtures/world/envelope_invalid_missing_schema.json",
		"res://domain/tests/fixtures/world/envelope_invalid_bad_origin.json",
	]
	for path in cases:
		var result = MapContentLoader.try_load_world_map_from_res_path(path)
		_check(not result["ok"], "invalid fixture rejected: %s" % path)


func _test_raw_hash_from_bytes() -> void:
	var path := "res://content/maps/reference/handdrawn_test_map_full_01.json"
	var raw := FileAccess.get_file_as_bytes(path)
	var hash_value = MapContentLoader.sha256_hex_lower(raw)
	_check(
		hash_value == "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6",
		"raw-byte hash from res copy"
	)


func _finish() -> void:
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)
