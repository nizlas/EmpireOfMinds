# Headless: godot --headless --path game -s res://domain/tests/test_end_turn.gd
extends SceneTree
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnStateScript = preload("res://domain/turn_state.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var ts = TurnStateScript.new([0, 1], 0, 1)
	var a = EndTurnScript.make(0)
	_check(a["schema_version"] == EndTurnScript.SCHEMA_VERSION, "schema_version")
	_check(a["action_type"] == EndTurnScript.ACTION_TYPE, "action_type")
	_check(a["actor_id"] == 0, "actor_id")
	var r0 = EndTurnScript.validate(null, a)
	_check(not r0["ok"] and r0["reason"] == "turn_state_null", "turn_state_null")
	var r1 = EndTurnScript.validate(ts, null)
	_check(not r1["ok"] and r1["reason"] == "wrong_action_type", "null action")
	var r2 = EndTurnScript.validate(ts, {"foo": 1})
	_check(not r2["ok"] and r2["reason"] == "wrong_action_type", "missing action_type")
	var r3 = EndTurnScript.validate(ts, {"action_type": "move_unit"})
	_check(not r3["ok"] and r3["reason"] == "wrong_action_type", "wrong action_type string")
	var r4 = EndTurnScript.validate(ts, {"action_type": EndTurnScript.ACTION_TYPE})
	_check(
		not r4["ok"] and r4["reason"] == "unsupported_schema_version",
		"no schema_version"
	)
	var r5 = EndTurnScript.validate(
		ts,
		{"action_type": EndTurnScript.ACTION_TYPE, "schema_version": 99, "actor_id": 0}
	)
	_check(
		not r5["ok"] and r5["reason"] == "unsupported_schema_version",
		"bad schema_version"
	)
	var r6 = EndTurnScript.validate(
		ts,
		{"action_type": EndTurnScript.ACTION_TYPE, "schema_version": EndTurnScript.SCHEMA_VERSION}
	)
	_check(not r6["ok"] and r6["reason"] == "malformed_action", "missing actor_id")
	var r7 = EndTurnScript.validate(
		ts,
		{
			"action_type": EndTurnScript.ACTION_TYPE,
			"schema_version": EndTurnScript.SCHEMA_VERSION,
			"actor_id": "nope",
		}
	)
	_check(not r7["ok"] and r7["reason"] == "malformed_action", "actor_id not int")
	var ok = EndTurnScript.validate(ts, EndTurnScript.make(0))
	_check(ok["ok"], "valid struct")
	var ts_before_i = ts.current_index
	var ts2 = EndTurnScript.apply(ts, EndTurnScript.make(0))
	_check(ts2.current_index == 1 and ts2.turn_number == 1, "apply advances")
	_check(ts.current_index == ts_before_i, "apply does not mutate input turn_state")
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
