# Headless: godot --headless --path game -s res://cloud/tests/test_server_snapshot_adapter.gd
extends SceneTree

const ServerSnapshotAdapterScript = preload("res://cloud/server_snapshot_adapter.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _mini_snapshot_v2() -> Dictionary:
	return {
		"match_id": "m_snap_test",
		"schema_version": 2,
		"revision": 3,
		"scenario": {
			"next_unit_id": 10,
			"next_city_id": 4,
			"lightning_tree_hex": [0, 0],
			"map": {
				"cells": [
					{"q": 0, "r": 0, "terrain": "plains", "landform": "flat", "woods": true},
					{"q": 1, "r": 0, "terrain": "grassland", "landform": "hills", "woods": false},
				]
			},
			"units": [
				{
					"id": 1,
					"owner_id": 0,
					"position": [0, 0],
					"type_id": "settler",
					"remaining_movement": 2,
					"current_hp": 5,
				}
			],
			"cities": [
				{
					"id": 2,
					"owner_id": 0,
					"position": [1, 0],
					"current_project": null,
					"city_name": "Alpha",
					"is_capital": true,
					"building_ids": [],
					"owned_tiles": [[1, 0], [0, 0]],
					"population": 2,
					"manual_worked_tiles": [],
					"food_stored": 3,
					"worked_tiles_mode": "auto",
				}
			],
		},
		"turn_state": {"players": [0, 1], "current_index": 1, "turn_number": 5},
		"progress_state": {
			"by_owner": [
				{
					"owner_id": 0,
					"unlocked_targets": [{"target_type": "city_project", "target_id": "produce_unit:settler"}],
					"completed_progress_ids": [],
					"science_progress": {},
					"science_observation_flags": {},
					"current_research_id": "",
				}
			]
		},
	}


func _init() -> void:
	var snap = _mini_snapshot_v2()
	var gs = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	_check(gs != null, "adapter returns GameState")
	_check(gs.has_method("try_apply"), "session facade shape")
	var scen = gs.scenario
	var u1 = scen.unit_by_id(1)
	_check(u1 != null, "unit 1")
	_check(u1.id == 1 and u1.owner_id == 0, "unit id owner")
	_check(u1.position.equals(HexCoordScript.new(0, 0)), "unit position")
	_check(str(u1.type_id) == "settler", "type_id")
	_check(u1.remaining_movement == 2, "remaining_movement")
	_check(u1.current_hp == 5, "current_hp")
	var c2 = scen.city_by_id(2)
	_check(c2 != null, "city 2")
	_check(c2.owner_id == 0, "city owner")
	_check(c2.position.equals(HexCoordScript.new(1, 0)), "city position")
	_check(c2.owned_tiles.size() == 2, "owned tiles count")
	_check(c2.population == 2 and c2.food_stored == 3, "pop food")
	_check(str(c2.city_name) == "Alpha", "city name")
	_check(scen.peek_next_unit_id() == 10, "next_unit_id")
	_check(scen.peek_next_city_id() == 4, "next_city_id")
	_check(
		scen.lightning_tree_hex != null and scen.lightning_tree_hex.equals(HexCoordScript.new(0, 0)),
		"lightning_tree_hex",
	)
	_check(gs.turn_state.current_player_id() == 1, "current player from turn_state")
	var po = gs.progress_state._by_owner.get(0)
	_check(po != null, "progress row owner 0")
	var ut = po.get("unlocked_targets", [])
	var ok_ut = false
	if ut is Array and (ut as Array).size() > 0:
		var z = (ut as Array)[0]
		if typeof(z) == TYPE_DICTIONARY:
			ok_ut = str((z as Dictionary).get("target_id", "")) == "produce_unit:settler"
	_check(ok_ut, "unlocked_targets preserved")
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
