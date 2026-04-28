# Headless: godot --headless --path game -s res://domain/tests/test_move_unit.gd
extends SceneTree
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	var a = MoveUnitScript.make(0, 1, 0, 0, 1, -1)
	_check(a["schema_version"] == MoveUnitScript.SCHEMA_VERSION, "schema_version")
	_check(a["action_type"] == MoveUnitScript.ACTION_TYPE, "action_type")
	_check(a["actor_id"] == 0 and a["unit_id"] == 1, "ids")
	_check((a["from"] as Array)[0] == 0 and (a["from"] as Array)[1] == 0, "from")
	_check((a["to"] as Array)[0] == 1 and (a["to"] as Array)[1] == -1, "to")
	var r0 = MoveUnitScript.validate(null, a)
	_check(not r0["ok"] and r0["reason"] == "scenario_null", "scenario_null")
	var r1 = MoveUnitScript.validate(sc, null)
	_check(not r1["ok"] and r1["reason"] == "wrong_action_type", "null action")
	var r2 = MoveUnitScript.validate(sc, {"foo": 1})
	_check(not r2["ok"] and r2["reason"] == "wrong_action_type", "missing action_type")
	var r3 = MoveUnitScript.validate(sc, {"action_type": "end_turn"})
	_check(not r3["ok"] and r3["reason"] == "wrong_action_type", "wrong action_type")
	var r4 = MoveUnitScript.validate(sc, {"action_type": MoveUnitScript.ACTION_TYPE})
	_check(not r4["ok"] and r4["reason"] == "unsupported_schema_version", "no schema")
	var r5 = MoveUnitScript.validate(
		sc,
		{
			"schema_version": 99,
			"action_type": MoveUnitScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"from": [0, 0],
			"to": [1, -1],
		}
	)
	_check(not r5["ok"] and r5["reason"] == "unsupported_schema_version", "bad schema")
	var r6 = MoveUnitScript.validate(
		sc,
		{
			"schema_version": MoveUnitScript.SCHEMA_VERSION,
			"action_type": MoveUnitScript.ACTION_TYPE,
			"unit_id": 1,
			"from": [0, 0],
			"to": [1, -1],
		}
	)
	_check(not r6["ok"] and r6["reason"] == "malformed_action", "malformed missing actor")
	var r7 = MoveUnitScript.validate(
		sc,
		MoveUnitScript.make(0, 99, 0, 0, 1, -1)
	)
	_check(not r7["ok"] and r7["reason"] == "unknown_unit", "unknown_unit")
	var r8 = MoveUnitScript.validate(
		sc,
		MoveUnitScript.make(1, 1, 0, 0, 1, -1)
	)
	_check(not r8["ok"] and r8["reason"] == "actor_not_owner", "actor_not_owner")
	var r9 = MoveUnitScript.validate(
		sc,
		MoveUnitScript.make(0, 1, 5, 5, 1, -1)
	)
	_check(
		not r9["ok"] and r9["reason"] == "from_does_not_match_unit_position",
		"from mismatch"
	)
	var r10 = MoveUnitScript.validate(
		sc,
		MoveUnitScript.make(0, 1, 0, 0, -1, 0)
	)
	_check(not r10["ok"] and r10["reason"] == "destination_not_legal", "water dest")
	var ok = MoveUnitScript.validate(sc, MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(ok["ok"], "legal validate")
	var sc_before = sc
	var u_before = sc.unit_by_id(1)
	var new_sc = MoveUnitScript.apply(sc, MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(
		new_sc.unit_by_id(1).position.equals(HexCoordScript.new(1, -1)),
		"moved position"
	)
	_check(
		u_before.position.equals(HexCoordScript.new(0, 0)),
		"old unit ref unchanged"
	)
	_check(sc_before == sc, "old scenario ref unchanged object")
	_check(new_sc.units().size() == 3, "still 3 units")
	_check(new_sc.unit_by_id(2).id == 2 and new_sc.unit_by_id(3).id == 3, "other ids")
	_check(new_sc.map.has(HexCoordScript.new(0, 0)), "map still valid")
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
