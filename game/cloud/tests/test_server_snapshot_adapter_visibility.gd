# Headless: godot --headless --path game -s res://cloud/tests/test_server_snapshot_adapter_visibility.gd
extends SceneTree

const ServerSnapshotAdapterScript = preload("res://cloud/server_snapshot_adapter.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var snap: Dictionary = {
		"schema_version": 2,
		"scenario": {
			"next_unit_id": 2,
			"next_city_id": 1,
			"lightning_tree_hex": null,
			"map": {
				"cells": [
					{"q": 0, "r": 0, "terrain": "plains", "landform": "flat", "woods": false},
					{"q": 5, "r": 5, "terrain": "plains", "landform": "flat", "woods": false},
				]
			},
			"units": [
				{
					"id": 1,
					"owner_id": 0,
					"position": [0, 0],
					"type_id": "warrior",
					"remaining_movement": 2,
					"current_hp": 100,
				}
			],
			"cities": [],
		},
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
		"progress_state": {"by_owner": []},
		"visibility_state": {
			"by_owner": [
				{"owner_id": 0, "explored": [[0, 0], [5, 5]]},
				{"owner_id": 1, "explored": [[1, 1]]},
			]
		},
	}
	var gs = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	_check(gs != null, "adapter returns GameState")
	_check(
		gs.visibility_state.is_explored(0, HexCoordScript.new(5, 5)),
		"restores explored (5,5) not in current unit sight",
	)
	_check(
		not gs.visibility_state.is_explored(0, HexCoordScript.new(1, 1)),
		"P0 does not get P1 explored tiles",
	)
	var gs2 = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(
		{"schema_version": 2, "scenario": snap["scenario"], "turn_state": snap["turn_state"]}
	)
	_check(gs2 != null, "snapshot without visibility_state still builds")
	_check(
		gs2.visibility_state.is_explored(0, HexCoordScript.new(0, 0)),
		"fallback seed explores unit start",
	)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
