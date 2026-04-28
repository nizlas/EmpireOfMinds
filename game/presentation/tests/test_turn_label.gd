# Headless: godot --headless --path game -s res://presentation/tests/test_turn_label.gd
extends SceneTree
const TurnLabelScript = preload("res://presentation/turn_label.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	_check(TurnLabelScript.compute_text(null) == "", "null game_state text")
	var gs = GameStateScript.make_tiny_test_state()
	_check(TurnLabelScript.compute_text(gs) == "Turn 1 — Player 0", "initial label")
	var r1 = gs.try_apply(EndTurnScript.make(0))
	_check(r1["accepted"], "first EndTurn applies")
	_check(TurnLabelScript.compute_text(gs) == "Turn 1 — Player 1", "after one EndTurn")
	var r2 = gs.try_apply(EndTurnScript.make(1))
	_check(r2["accepted"], "second EndTurn applies")
	_check(TurnLabelScript.compute_text(gs) == "Turn 2 — Player 0", "after two EndTurns")
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
