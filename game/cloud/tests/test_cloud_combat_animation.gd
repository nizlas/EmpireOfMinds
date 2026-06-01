# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_combat_animation.gd
extends SceneTree

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const MainScript = preload("res://main.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var attack_action := {
		"schema_version": 1,
		"action_type": "attack_unit",
		"actor_id": 0,
		"attacker_id": 2,
		"defender_id": 3,
	}
	var attack_response := {
		"accepted": true,
		"revision": 2,
		"snapshot": {"scenario": {}},
		"event": {
			"action_type": "attack_unit",
			"attacker_position": [1.0, 0.0],
			"defender_position": [1.0, -1.0],
			"defender_damage_taken": 30.0,
			"retaliated": true,
		},
	}
	var anim_req: Dictionary = CloudClientScript.combat_animation_request_from_response(
		attack_response,
		attack_action,
	)
	_check(bool(anim_req.get("should_animate", false)), "attack_unit accepted with event should_animate")
	_check(int(anim_req.get("attacker_q", -1)) == 1, "attacker_q int coerced")
	_check(int(anim_req.get("attacker_r", -1)) == 0, "attacker_r int coerced")
	_check(int(anim_req.get("defender_q", -1)) == 1, "defender_q int coerced")
	_check(int(anim_req.get("defender_r", -1)) == -1, "defender_r int coerced")
	_check(int(anim_req.get("defender_damage_taken", -1)) == 30, "defender_damage_taken int")
	_check(bool(anim_req.get("retaliated", false)), "retaliated from event")

	var move_action := {
		"schema_version": MoveUnitScript.SCHEMA_VERSION,
		"action_type": MoveUnitScript.ACTION_TYPE,
		"actor_id": 0,
		"unit_id": 1,
		"from": [0, 0],
		"to": [1, 0],
	}
	var move_response := {
		"accepted": true,
		"snapshot": {"scenario": {}},
		"event": {"action_type": "move_unit", "from": [0, 0], "to": [1, 0]},
	}
	var move_req: Dictionary = CloudClientScript.combat_animation_request_from_response(
		move_response,
		move_action,
	)
	_check(not bool(move_req.get("should_animate", false)), "move_unit does not animate")

	var rejected_req: Dictionary = CloudClientScript.combat_animation_request_from_response(
		{"accepted": false, "reason": "movement_exhausted"},
		attack_action,
	)
	_check(not bool(rejected_req.get("should_animate", false)), "rejected attack does not animate")

	var missing_event_req: Dictionary = CloudClientScript.combat_animation_request_from_response(
		{"accepted": true, "snapshot": {"scenario": {}}},
		attack_action,
	)
	_check(not bool(missing_event_req.get("should_animate", false)), "missing event falls back no animate")

	var bad_pos_req: Dictionary = CloudClientScript.combat_animation_request_from_response(
		{
			"accepted": true,
			"snapshot": {"scenario": {}},
			"event": {"action_type": "attack_unit", "attacker_position": [1]},
		},
		attack_action,
	)
	_check(not bool(bad_pos_req.get("should_animate", false)), "invalid positions fall back no animate")

	var main = MainScript.new()
	get_root().add_child(main)
	_check(not main.cloud_session_blocks_map_input(), "main blocks false when idle")
	main.set("_cloud_combat_anim_busy", true)
	_check(main.cloud_session_blocks_map_input(), "main blocks true when combat anim busy")
	main.set("_cloud_combat_anim_busy", false)
	_check(not main.cloud_session_blocks_map_input(), "main blocks false after busy reset")
	main.free()

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
