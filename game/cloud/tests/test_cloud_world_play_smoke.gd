# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_world_play_smoke.gd
#
# N6 production world-play scene smoke test: cloud_world_play builds the
# shared TerrainWorld + N4 anchor UI from a verified snapshot v3 and fails
# explicitly (visible error, no fallback map) on identity mismatch. The
# network fetch is exercised by the end-to-end flow; this test feeds the
# snapshot directly through the same bootstrap entry the scene uses.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
extends SceneTree

const REFERENCE_MAP_ID := "handdrawn_test_map_full_01"
const REFERENCE_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"

var _total := 0
var _any_fail := false


func _good_snapshot() -> Dictionary:
	return {
		"match_id": "m_smoke",
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
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene")) ==
			"res://cloud/cloud_front_door.tscn",
		"cloud front door stays the project main scene (no default-entry cutover)"
	)
	var packed: PackedScene = load("res://cloud/world_play/cloud_world_play.tscn") as PackedScene
	_check(packed != null, "cloud_world_play scene loads")
	if packed == null:
		_finish()
		return
	var scene = packed.instantiate()
	_check(scene != null, "cloud_world_play instantiates")

	# Identity mismatch: explicit failure, no fallback, no world built.
	var bad := _good_snapshot()
	(bad["map"] as Dictionary)["content_hash"] = "0".repeat(64)
	_check(not scene.bootstrap_from_snapshot(bad), "hash mismatch bootstrap returns false")
	_check(scene.world == null, "hash mismatch builds no world (no fallback)")
	_check(
		str(scene.bootstrap_error).contains("content_hash mismatch"),
		"hash mismatch error is explicit and visible"
	)

	# Verified snapshot: shared TerrainWorld + N4 anchor UI.
	_check(scene.bootstrap_from_snapshot(_good_snapshot()), "verified snapshot bootstraps")
	_check(str(scene.bootstrap_error) == "", "bootstrap error cleared on success")
	var world = scene.world
	_check(
		world != null and world == scene.get_node_or_null("TerrainWorld")
			and world.get_script() == load("res://presentation/world/terrain_world.gd"),
		"scene builds the exact shared runtime-world component"
	)
	var anchor_ui = scene.anchor_ui
	_check(
		anchor_ui != null and anchor_ui == scene.get_node_or_null("WorldAnchorUi")
			and anchor_ui.get_script() == load("res://presentation/world/world_anchor_ui.gd"),
		"scene attaches the shared N4 projected anchor UI"
	)
	if world != null:
		_check(
			world.world_map != null and world.world_map.identity.map_id == REFERENCE_MAP_ID
				and world.world_map.identity.content_hash == REFERENCE_HASH,
			"world built from the verified canonical map"
		)
		_check(
			world.tile_anchors.size() == world.world_map.tile_count(),
			"one anchor per canonical tile"
		)
	scene.free()
	_finish()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("CloudWorldPlaySmoke tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
