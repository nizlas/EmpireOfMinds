# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_client_payloads.gd
extends SceneTree

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")

var _total = 0
var _any_fail = false


const CloudSessionScript = preload("res://cloud/cloud_session.gd")


func _init() -> void:
	var csess = CloudSessionScript.new()
	_check(
		str(csess.base_url) == "http://127.0.0.1:8000",
		"CloudSession default base_url is 127.0.0.1 (avoid localhost IPv6 delay on Windows)",
	)
	csess.free()
	var base = "http://127.0.0.1:8000/"
	var m = "m_abc"
	var p = CloudClientScript.legal_actions_path(m, 0, 2, -1)
	_check(
		p == "/v1/matches/m_abc/legal-actions?actor_id=0&selected_unit_id=2",
		"legal-actions URL with unit",
	)
	var p2 = CloudClientScript.legal_actions_path(m, 1, -1, 3)
	_check(
		p2 == "/v1/matches/m_abc/legal-actions?actor_id=1&selected_city_id=3",
		"legal-actions URL with city",
	)
	var mb = CloudClientScript.matches_base("http://127.0.0.1:8000", "/v1/matches")
	_check(mb == "http://127.0.0.1:8000/v1/matches", "matches_base strips slash")
	_check(CloudClientScript.should_create_match(""), "empty match_id -> create")
	_check(CloudClientScript.should_create_match("  "), "whitespace match_id -> create")
	_check(not CloudClientScript.should_create_match("m_abc"), "non-empty match_id -> reconnect")
	_check(
		CloudClientScript.get_match_path("m_abc") == "/v1/matches/m_abc",
		"get_match_path",
	)
	_check(not CloudClientScript.should_apply_snapshot({}), "reject empty")
	_check(
		not CloudClientScript.should_apply_snapshot({"accepted": false, "reason": "x"}),
		"reject not accepted",
	)
	_check(
		not CloudClientScript.should_apply_snapshot({"_error": "http", "accepted": true}),
		"reject transport error",
	)
	_check(
		CloudClientScript.should_apply_snapshot({"accepted": true, "snapshot": {"scenario": {}}}),
		"accept with snapshot key",
	)
	var et = EndTurnScript.make(0)
	_check(int(et["actor_id"]) == 0, "end_turn actor")
	_check(str(et["action_type"]) == "end_turn", "end_turn type")
	var mv = {
		"schema_version": MoveUnitScript.SCHEMA_VERSION,
		"action_type": MoveUnitScript.ACTION_TYPE,
		"actor_id": 0,
		"unit_id": 1,
		"from": [0, 0],
		"to": [1, 0],
	}
	_check(str(mv["action_type"]) == "move_unit", "move payload shape")
	var from_server_floats = {
		"schema_version": 1.0,
		"action_type": "move_unit",
		"actor_id": 0.0,
		"unit_id": 2.0,
		"from": [0.0, 0.0],
		"to": [1.0, -1.0],
	}
	var norm_move = CloudClientScript.normalize_api_action_for_post(from_server_floats)
	_check(typeof(norm_move["actor_id"]) == TYPE_INT, "move actor_id coerced to int (JSON.parse uses float)")
	_check(typeof(norm_move["unit_id"]) == TYPE_INT, "move unit_id coerced to int")
	_check(
		typeof((norm_move["from"] as Array)[0]) == TYPE_INT,
		"move from[0] int",
	)
	_check(
		typeof((norm_move["to"] as Array)[1]) == TYPE_INT,
		"move to[1] int",
	)
	var from_server_attack_floats = {
		"schema_version": 1.0,
		"action_type": "attack_unit",
		"actor_id": 0.0,
		"attacker_id": 2.0,
		"defender_id": 3.0,
	}
	var norm_attack = CloudClientScript.normalize_api_action_for_post(from_server_attack_floats)
	_check(typeof(norm_attack["attacker_id"]) == TYPE_INT, "attack attacker_id coerced to int")
	_check(typeof(norm_attack["defender_id"]) == TYPE_INT, "attack defender_id coerced to int")
	_check(not norm_attack.has("from"), "attack POST has no from/to")
	_check(not norm_attack.has("to"), "attack POST has no to")
	var combat_map = HexMapScript.make_tiny_test_map()
	var combat_units = [
		UnitScript.new(2, 0, HexCoordScript.new(1, 0), "warrior"),
		UnitScript.new(3, 1, HexCoordScript.new(0, -1), "warrior"),
	]
	var combat_scen = ScenarioScript.new(combat_map, combat_units)
	var legal_attacks: Array = [
		{
			"schema_version": 1,
			"action_type": "attack_unit",
			"actor_id": 0,
			"attacker_id": 2,
			"defender_id": 3,
		},
	]
	var atk_pack: Dictionary = CloudClientScript.build_attack_maps_from_legal_actions(
		legal_attacks,
		combat_scen,
	)
	var atk_map: Dictionary = atk_pack["attack_map"] as Dictionary
	_check(atk_map.has(CloudClientScript.hex_action_key(0, -1)), "attack map keyed by defender hex")
	_check((atk_pack["attack_targets"] as Array).size() == 1, "one attack target coord")
	var j_move = JSON.new()
	var mv_wire = JSON.stringify(norm_move)
	_check(j_move.parse(mv_wire) == OK, "move normalized json parses")
	var mv_data = j_move.data
	_check(
		typeof(mv_data) == TYPE_DICTIONARY and not (mv_data as Dictionary).has("action"),
		"POST body is flat action not wrapped in action key",
	)
	_check(CloudClientScript.hex_action_key(1, -2) == "1,-2", "hex_action_key negatives")
	var a1 = {"action_type": "move_unit", "to": [1, 0]}
	var a2 = {"action_type": "move_unit", "to": [0, -1]}
	var mm2: Dictionary = {}
	mm2[CloudClientScript.hex_action_key(1, 0)] = a1
	mm2[CloudClientScript.hex_action_key(0, -1)] = a2
	_check(mm2.has(CloudClientScript.hex_action_key(1, 0)), "move map key build 1")
	_check(mm2.size() == 2, "two dest keys")
	var sp = InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	sp.echo = false
	_check(CloudClientScript.is_cloud_space_end_turn_shortcut(true, sp), "space cloud shortcut")
	_check(not CloudClientScript.is_cloud_space_end_turn_shortcut(false, sp), "space off when not cloud")
	sp.pressed = false
	_check(not CloudClientScript.is_cloud_space_end_turn_shortcut(true, sp), "space not pressed")
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
