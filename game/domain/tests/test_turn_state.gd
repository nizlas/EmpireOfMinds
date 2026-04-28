# Headless: godot --headless --path game -s res://domain/tests/test_turn_state.gd
extends SceneTree
const TurnStateScript = preload("res://domain/turn_state.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var ts = TurnStateScript.new([0, 1], 0, 1)
	_check(ts.players.size() == 2 and ts.players[0] == 0 and ts.players[1] == 1, "players copy")
	_check(ts.current_index == 0 and ts.turn_number == 1, "initial index/turn")
	_check(ts.current_player_id() == 0, "current_player_id")
	var a1 = ts.advance()
	_check(a1.current_index == 1 and a1.turn_number == 1, "advance to p1 same turn")
	_check(ts.current_index == 0 and ts.turn_number == 1, "advance does not mutate source")
	var a2 = a1.advance()
	_check(a2.current_index == 0 and a2.turn_number == 2, "wrap increments turn_number")
	var ts_b = TurnStateScript.new([0, 1], 0, 1)
	_check(ts.equals(ts_b), "equals true")
	_check(not ts.equals(a1), "equals false different index")
	_check(not ts.equals(null), "equals null")
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
