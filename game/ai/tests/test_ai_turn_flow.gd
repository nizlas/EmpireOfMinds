# Headless: godot --headless --path game -s res://ai/tests/test_ai_turn_flow.gd
extends SceneTree
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

const MAX_AI_STEPS: int = 20

var _total = 0
var _any_fail = false

func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var steps0 = 0
	while gs.turn_state.current_player_id() == 0 and steps0 < MAX_AI_STEPS:
		var legal0 = LegalActionsScript.for_current_player(gs)
		var act0 = RuleBasedAIPlayerScript.decide(gs, legal0)
		_check(not act0.is_empty(), "p0 nonempty decision")
		var r0 = gs.try_apply(act0)
		_check(r0["accepted"], "p0 try_apply accepted")
		steps0 = steps0 + 1
	_check(gs.turn_state.current_player_id() == 1, "p0 AI completes turn within MAX_AI_STEPS")
	var steps1 = 0
	while not (gs.turn_state.turn_number == 2 and gs.turn_state.current_player_id() == 0):
		if steps1 >= MAX_AI_STEPS:
			break
		var legal1 = LegalActionsScript.for_current_player(gs)
		var act1 = RuleBasedAIPlayerScript.decide(gs, legal1)
		_check(not act1.is_empty(), "p1 nonempty decision")
		var r1 = gs.try_apply(act1)
		_check(r1["accepted"], "p1 try_apply accepted")
		steps1 = steps1 + 1
	_check(gs.turn_state.turn_number == 2 and gs.turn_state.current_player_id() == 0, "full cycle within MAX_AI_STEPS")
	var n_move0 = 0
	var n_move1 = 0
	var end_order = []
	var log_i = 0
	while log_i < gs.log.size():
		var ent = gs.log.get_entry(log_i)
		var at = ent.get("action_type", "")
		if at == MoveUnitScript.ACTION_TYPE:
			var aid = int(ent.get("actor_id", -1))
			if aid == 0:
				n_move0 = n_move0 + 1
			if aid == 1:
				n_move1 = n_move1 + 1
		if at == EndTurnScript.ACTION_TYPE:
			end_order.append(int(ent.get("actor_id", -1)))
		log_i = log_i + 1
	_check(n_move0 == 1, "exactly one move_unit for actor 0")
	_check(n_move1 == 1, "exactly one move_unit for actor 1")
	_check(end_order.size() == 2, "exactly two end_turn entries")
	_check(end_order[0] == 0 and end_order[1] == 1, "end_turn order 0 then 1")
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
