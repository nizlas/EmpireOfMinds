# Headless: godot --headless --path game -s res://domain/tests/test_game_state.gd
extends SceneTree
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(gs.scenario.units().size() == 3, "tiny state 3 units")
	_check(gs.log.size() == 0, "log starts empty")
	var bad_t = gs.try_apply({"action_type": "no_such_action"})
	_check(
		not bad_t["accepted"] and bad_t["reason"] == "unknown_action_type" and bad_t["index"] == -1,
		"unknown action type"
	)
	_check(gs.log.size() == 0, "no log on unknown")
	var bad_m = gs.try_apply(
		{
			"schema_version": MoveUnitScript.SCHEMA_VERSION,
			"action_type": MoveUnitScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"from": [0, 0],
			"to": [-1, 0],
		}
	)
	_check(not bad_m["accepted"], "illegal move rejected")
	_check(gs.log.size() == 0, "no log on reject")
	_check(
		gs.scenario.unit_by_id(1).position.equals(HexCoordScript.new(0, 0)),
		"scenario unchanged on reject"
	)
	var old_ref = gs.scenario
	var a1 = MoveUnitScript.make(0, 1, 0, 0, 1, -1)
	var r1 = gs.try_apply(a1)
	_check(r1["accepted"] and r1["index"] == 0, "first apply accepted")
	_check(gs.log.size() == 1, "log one")
	_check(gs.scenario != old_ref, "scenario ref replaced")
	_check(
		gs.scenario.unit_by_id(1).position.equals(HexCoordScript.new(1, -1)),
		"unit 1 moved"
	)
	_check(
		old_ref.unit_by_id(1).position.equals(HexCoordScript.new(0, 0)),
		"old scenario snapshot unchanged"
	)
	var entry0 = gs.log.get_entry(0)
	_check(entry0["result"] == "accepted", "logged accepted")
	_check(entry0["unit_id"] == 1, "log unit_id")
	var a2 = MoveUnitScript.make(0, 2, 1, 0, 0, 1)
	var r2 = gs.try_apply(a2)
	_check(r2["accepted"] and r2["index"] == 1, "second apply")
	_check(gs.log.size() == 2, "log two")
	_check(
		gs.scenario.unit_by_id(2).position.equals(HexCoordScript.new(0, 1)),
		"unit 2 moved"
	)
	var bad2 = gs.try_apply(
		MoveUnitScript.make(0, 1, 0, 0, 1, 0)
	)
	_check(not bad2["accepted"], "stale from rejected")
	_check(gs.log.size() == 2, "log still two after reject")
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
