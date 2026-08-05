# Headless: godot --headless --path game -s res://domain/tests/test_map_content_loader_by_id.gd
#
# N6: MapContentLoader.load_world_map_by_id resolves canonical maps through
# the derived-package manifest (game/content/maps/manifest.json). Strict:
# unknown/empty map_id fails with an explicit error and never a fallback.
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")

const REFERENCE_MAP_ID := "handdrawn_test_map_full_01"
const REFERENCE_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const TILE_COUNT_GOLDEN := 168

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_reference_map_loads_by_id()
	_test_by_id_matches_direct_path_load()
	_test_unknown_map_id_fails()
	_test_empty_map_id_fails()
	_finish()


func _test_reference_map_loads_by_id() -> void:
	var result: Dictionary = MapContentLoader.try_load_world_map_by_id(REFERENCE_MAP_ID)
	_check(bool(result["ok"]), "reference map loads by id")
	if not result["ok"]:
		return
	var world_map = result["world_map"]
	_check(world_map.identity.map_id == REFERENCE_MAP_ID, "loaded identity map_id")
	_check(world_map.identity.schema_version == 1, "loaded identity schema_version")
	_check(world_map.identity.content_hash == REFERENCE_HASH, "loaded identity content_hash golden")
	_check(world_map.tile_count() == TILE_COUNT_GOLDEN, "loaded tile count golden")


func _test_by_id_matches_direct_path_load() -> void:
	var by_id = MapContentLoader.load_world_map_by_id(REFERENCE_MAP_ID)
	var direct = MapContentLoader.load_reference_world_map()
	_check(
		by_id != null and direct != null and by_id.identity.equals(direct.identity),
		"by-id load and direct reference load agree on identity"
	)


func _test_unknown_map_id_fails() -> void:
	var result: Dictionary = MapContentLoader.try_load_world_map_by_id("no_such_map_xyz")
	_check(not bool(result["ok"]), "unknown map_id rejected")
	_check(result["world_map"] == null, "unknown map_id yields no world map (no fallback)")
	_check(
		str(result["error"]).contains("no_such_map_xyz"),
		"unknown map_id error names the requested id"
	)


func _test_empty_map_id_fails() -> void:
	var result: Dictionary = MapContentLoader.try_load_world_map_by_id("  ")
	_check(not bool(result["ok"]), "empty map_id rejected")
	_check(result["world_map"] == null, "empty map_id yields no world map")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("MapContentLoaderById tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
