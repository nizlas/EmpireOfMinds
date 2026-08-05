# Headless: godot --headless --path game -s res://cloud/tests/test_world_snapshot_bootstrap.gd
#
# N6: WorldSnapshotBootstrap parse/verify contract. Snapshot v3 carries only
# the MapIdentity (+ revision/turn_state); the client loads canonical content
# by map_id and verifies schema version + raw-byte content hash. Missing
# content or any identity mismatch is an explicit failure with NO fallback.
extends SceneTree

const WorldSnapshotBootstrap = preload("res://cloud/world_snapshot_bootstrap.gd")

const REFERENCE_MAP_ID := "handdrawn_test_map_full_01"
const REFERENCE_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const TILE_COUNT_GOLDEN := 168

var _total := 0
var _any_fail := false


func _good_snapshot() -> Dictionary:
	return {
		"match_id": "m_test",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {
			"map_id": REFERENCE_MAP_ID,
			"schema_version": 1,
			"content_hash": REFERENCE_HASH,
		},
		"revision": 0,
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
	}


func _init() -> void:
	_test_parse_good_snapshot()
	_test_parse_rejections()
	_test_load_and_verify_happy_path()
	_test_identity_mismatches_fail_without_fallback()
	_test_unknown_map_fails_without_fallback()
	_finish()


func _test_parse_good_snapshot() -> void:
	var parsed: Dictionary = WorldSnapshotBootstrap.parse_world_snapshot(_good_snapshot())
	_check(bool(parsed["ok"]), "good v3 snapshot parses")
	_check(str(parsed.get("map_id", "")) == REFERENCE_MAP_ID, "parsed map_id")
	_check(int(parsed.get("schema_version", -1)) == 1, "parsed content schema_version")
	_check(str(parsed.get("content_hash", "")) == REFERENCE_HASH, "parsed content_hash")
	_check(int(parsed.get("revision", -1)) == 0, "parsed revision")
	_check(
		int((parsed.get("turn_state", {}) as Dictionary).get("turn_number", -1)) == 1,
		"parsed turn_state"
	)


func _test_parse_rejections() -> void:
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(null)["ok"]),
		"null snapshot rejected"
	)
	var v2 := _good_snapshot()
	v2["schema_version"] = 2
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(v2)["ok"]),
		"snapshot schema v2 rejected"
	)
	var wrong_kind := _good_snapshot()
	wrong_kind["match_kind"] = "hexmap"
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(wrong_kind)["ok"]),
		"non-world_map kind rejected"
	)
	var no_kind := _good_snapshot()
	no_kind.erase("match_kind")
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(no_kind)["ok"]),
		"absent match_kind rejected"
	)
	var no_map := _good_snapshot()
	no_map.erase("map")
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(no_map)["ok"]),
		"missing map identity rejected"
	)
	var empty_hash := _good_snapshot()
	(empty_hash["map"] as Dictionary)["content_hash"] = ""
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(empty_hash)["ok"]),
		"empty content_hash rejected"
	)
	var no_turn := _good_snapshot()
	no_turn.erase("turn_state")
	_check(
		not bool(WorldSnapshotBootstrap.parse_world_snapshot(no_turn)["ok"]),
		"missing turn_state rejected"
	)


func _test_load_and_verify_happy_path() -> void:
	var result: Dictionary = WorldSnapshotBootstrap.load_and_verify_world_map(_good_snapshot())
	_check(bool(result["ok"]), "load_and_verify succeeds for matching identity")
	var world_map = result["world_map"]
	_check(world_map != null, "world map returned")
	if world_map == null:
		return
	_check(world_map.identity.content_hash == REFERENCE_HASH, "loaded hash equals server hash")
	_check(world_map.tile_count() == TILE_COUNT_GOLDEN, "canonical tile count loaded")


func _test_identity_mismatches_fail_without_fallback() -> void:
	var bad_hash := _good_snapshot()
	(bad_hash["map"] as Dictionary)["content_hash"] = "0".repeat(64)
	var result: Dictionary = WorldSnapshotBootstrap.load_and_verify_world_map(bad_hash)
	_check(not bool(result["ok"]), "content_hash mismatch fails")
	_check(result["world_map"] == null, "content_hash mismatch yields no world map (no fallback)")
	_check(
		str(result["error"]).contains("content_hash mismatch"),
		"content_hash mismatch error is explicit"
	)
	var bad_schema := _good_snapshot()
	(bad_schema["map"] as Dictionary)["schema_version"] = 2
	var result2: Dictionary = WorldSnapshotBootstrap.load_and_verify_world_map(bad_schema)
	_check(
		not bool(result2["ok"]) and result2["world_map"] == null,
		"content schema_version mismatch fails without fallback"
	)


func _test_unknown_map_fails_without_fallback() -> void:
	var unknown := _good_snapshot()
	(unknown["map"] as Dictionary)["map_id"] = "no_such_map_xyz"
	var result: Dictionary = WorldSnapshotBootstrap.load_and_verify_world_map(unknown)
	_check(not bool(result["ok"]), "unknown map_id fails")
	_check(result["world_map"] == null, "unknown map_id yields no world map (no fallback)")
	_check(
		str(result["error"]).contains("no_such_map_xyz"),
		"missing-content error names the map id"
	)


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("WorldSnapshotBootstrap tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
