# Headless: godot --headless --path game -s res://domain/tests/test_turn_flow.gd
extends SceneTree
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var bad_malformed = gs.try_apply(
		{
			"schema_version": EndTurnScript.SCHEMA_VERSION,
			"action_type": EndTurnScript.ACTION_TYPE,
		}
	)
	_check(
		not bad_malformed["accepted"] and bad_malformed["reason"] == "malformed_action",
		"gate malformed missing actor_id"
	)
	var bad_move_owner = gs.try_apply(MoveUnitScript.make(1, 3, 0, -1, 0, 0))
	_check(
		not bad_move_owner["accepted"] and bad_move_owner["reason"] == "not_current_player",
		"MoveUnit wrong current player"
	)
	var bad_end = gs.try_apply(EndTurnScript.make(1))
	_check(
		not bad_end["accepted"] and bad_end["reason"] == "not_current_player",
		"EndTurn wrong actor before gate"
	)
	var tn0 = gs.turn_state.turn_number
	var cp0 = gs.turn_state.current_player_id()
	var mv = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(mv["accepted"], "MoveUnit accepted")
	_check(gs.turn_state.turn_number == tn0, "move does not advance turn_number")
	_check(gs.turn_state.current_player_id() == cp0, "move does not change current player")
	var en = gs.try_apply(EndTurnScript.make(0))
	_check(en["accepted"], "EndTurn accepted")
	_check(gs.turn_state.current_player_id() == 1, "now player 1")
	_check(gs.turn_state.turn_number == 1, "still same round number")
	var mv2 = gs.try_apply(MoveUnitScript.make(1, 3, 0, -1, 0, 0))
	_check(mv2["accepted"], "player 1 moves unit 3")
	_check(
		gs.scenario.unit_by_id(3).position.equals(HexCoordScript.new(0, 0)),
		"unit 3 at destination"
	)
	var en2 = gs.try_apply(EndTurnScript.make(1))
	_check(en2["accepted"], "second EndTurn")
	_check(gs.turn_state.current_player_id() == 0, "back to player 0")
	_check(gs.turn_state.turn_number == 2, "turn counter after full cycle")
	var entry = gs.log.get_entry(3)
	_check(entry["action_type"] == EndTurnScript.ACTION_TYPE, "log entry is EndTurn")
	_check(entry["turn_number_before"] == 1, "logged turn_number_before")
	_check(entry["next_player_id"] == 0, "logged next_player_id")
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
