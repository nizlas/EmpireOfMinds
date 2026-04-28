# Headless: godot --headless --path game -s res://ai/tests/test_rule_based_ai_player.gd
extends SceneTree
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var d0 = RuleBasedAIPlayerScript.decide(null, [])
	_check(d0.is_empty(), "empty legal -> empty dict")
	var et = EndTurnScript.make(0)
	var only_end = [et]
	var d1 = RuleBasedAIPlayerScript.decide(null, only_end)
	_check(_action_equals(d1, et), "only EndTurn chosen")
	var mv = MoveUnitScript.make(0, 1, 0, 0, -1, 1)
	var mixed = [et, mv]
	var d2 = RuleBasedAIPlayerScript.decide(null, mixed)
	_check(_action_equals(d2, mv), "prefers MoveUnit when listed after EndTurn")
	var d2b = RuleBasedAIPlayerScript.decide(null, mixed)
	_check(_action_equals(d2, d2b), "deterministic same input")
	var mv2 = MoveUnitScript.make(0, 1, 0, 0, 0, 1)
	var two_moves = [mv, mv2]
	var d3 = RuleBasedAIPlayerScript.decide(null, two_moves)
	_check(_action_equals(d3, mv), "first MoveUnit wins")
	_check(_action_matches_list(d3, two_moves), "choice in list")
	var junk_list = [{"foo": 1}, {"action_type": "nope"}]
	var d4 = RuleBasedAIPlayerScript.decide(null, junk_list)
	_check(d4.is_empty(), "no known actions -> empty")
	var gs = GameStateScript.make_tiny_test_state()
	var rm = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, -1, 1))
	_check(rm["accepted"], "setup move for policy branch")
	var leg = LegalActionsScript.for_current_player(gs)
	var d5 = RuleBasedAIPlayerScript.decide(gs, leg)
	_check(d5.get("action_type", "") == EndTurnScript.ACTION_TYPE, "after one move pick EndTurn")
	_check(int(d5.get("actor_id", -1)) == 0, "EndTurn actor 0")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _action_matches_list(action: Dictionary, legal: Array) -> bool:
	var i = 0
	while i < legal.size():
		if _action_equals(action, legal[i]):
			return true
		i = i + 1
	return false

func _action_equals(a: Dictionary, b) -> bool:
	if typeof(b) != TYPE_DICTIONARY:
		return false
	for k in a:
		if not b.has(k):
			return false
		var va = a[k]
		var vb = b[k]
		if va is Array and vb is Array:
			var aa = va as Array
			var ab = vb as Array
			if aa.size() != ab.size():
				return false
			var j = 0
			while j < aa.size():
				if aa[j] != ab[j]:
					return false
				j = j + 1
		else:
			if va != vb:
				return false
	for k2 in b:
		if not a.has(k2):
			return false
	return true

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
