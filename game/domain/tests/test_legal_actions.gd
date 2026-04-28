# Headless: godot --headless --path game -s res://domain/tests/test_legal_actions.gd
extends SceneTree
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var empty = LegalActionsScript.for_current_player(null)
	_check(empty.size() == 0, "null game_state empty list")
	var gs = GameStateScript.make_tiny_test_state()
	var L = LegalActionsScript.for_current_player(gs)
	_check(L.size() > 0, "nonempty legal list")
	var last = L[L.size() - 1]
	_check(last["action_type"] == EndTurnScript.ACTION_TYPE, "last is EndTurn")
	_check(last["actor_id"] == 0, "EndTurn actor 0")
	var move_count = 0
	var li = 0
	while li < L.size() - 1:
		var e = L[li]
		_check(e["actor_id"] == 0, "move actor 0")
		_check(e["action_type"] == MoveUnitScript.ACTION_TYPE, "move type")
		var vr = MoveUnitScript.validate(gs.scenario, e)
		_check(vr["ok"], "emitted move validates: %s" % vr.get("reason", ""))
		move_count = move_count + 1
		li = li + 1
	_check(move_count > 0, "at least one move for p0")
	var first = L[0]
	_check(first["unit_id"] == 1, "first move unit 1")
	_check((first["to"] as Array)[0] == -1 and (first["to"] as Array)[1] == 1, "first dest (-1,1)")
	var r_end = gs.try_apply(EndTurnScript.make(0))
	_check(r_end["accepted"], "manual advance to p1")
	var L1 = LegalActionsScript.for_current_player(gs)
	_check(L1.size() > 0, "p1 nonempty")
	var last1 = L1[L1.size() - 1]
	_check(last1["action_type"] == EndTurnScript.ACTION_TYPE, "p1 last EndTurn")
	_check(last1["actor_id"] == 1, "p1 EndTurn actor")
	var lj = 0
	while lj < L1.size():
		_check(L1[lj]["actor_id"] == 1, "p1 all entries actor 1")
		lj = lj + 1
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
