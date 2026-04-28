# Headless: godot --headless --path game -s res://ai/tests/test_rule_based_ai_policy.gd
extends SceneTree
const RuleBasedAIPolicyScript = preload("res://ai/rule_based_ai_policy.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const ActionLogScript = preload("res://domain/action_log.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(null, 0), "null log -> false")
	var log0 = ActionLogScript.new()
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(log0, 0), "empty log -> false")
	var gs = GameStateScript.make_tiny_test_state()
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 0), "fresh state p0 no move")
	var r1 = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, -1, 1))
	_check(r1["accepted"], "move applies")
	_check(RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 0), "after p0 move -> true for 0")
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 1), "p1 not moved this segment")
	var r2 = gs.try_apply(EndTurnScript.make(0))
	_check(r2["accepted"], "end p0")
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 0), "after EndTurn boundary -> false for 0")
	var r3 = gs.try_apply(MoveUnitScript.make(1, 3, 0, -1, 0, 0))
	_check(r3["accepted"], "p1 move applies")
	_check(RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 1), "after p1 move -> true for 1")
	_check(not RuleBasedAIPolicyScript.has_actor_moved_this_turn(gs.log, 0), "p0 still false in p1 segment")
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
