# Headless: godot --headless --path game -s res://ai/tests/test_ai_turn_flow.gd
extends SceneTree
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

const MAX_AI_STEPS: int = 32

var _total = 0
var _any_fail = false

func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var steps0 = 0
	var p0_found = 0
	var p0_set = 0
	var p0_end = 0
	var saw_found_before_set = false
	while gs.turn_state.current_player_id() == 0 and steps0 < MAX_AI_STEPS:
		var legal0 = LegalActionsScript.for_current_player(gs)
		var act0 = RuleBasedAIPlayerScript.decide(gs, legal0)
		_check(not act0.is_empty(), "p0 nonempty decision")
		_check_no_engine_choice(act0)
		_check(_choice_in_legal(act0, legal0), "p0 choice in legal list")
		var at0 = act0.get("action_type", "")
		if at0 == FoundCityScript.ACTION_TYPE:
			p0_found = p0_found + 1
			saw_found_before_set = true
		if at0 == SetCityProductionScript.ACTION_TYPE:
			_check(saw_found_before_set, "set_city_production after founding intent")
			p0_set = p0_set + 1
		if at0 == EndTurnScript.ACTION_TYPE:
			p0_end = p0_end + 1
		var r0 = gs.try_apply(act0)
		_check(r0["accepted"], "p0 try_apply accepted")
		steps0 = steps0 + 1
	_check(gs.turn_state.current_player_id() == 1, "p0 AI completes turn within MAX_AI_STEPS")
	_check(p0_found >= 1, "p0 at least one found_city")
	_check(p0_set >= 1, "p0 at least one set_city_production")
	_check(p0_end == 1, "p0 exactly one end_turn in segment")

	var steps1 = 0
	while not (gs.turn_state.turn_number == 2 and gs.turn_state.current_player_id() == 0):
		if steps1 >= MAX_AI_STEPS:
			break
		var legal1 = LegalActionsScript.for_current_player(gs)
		var act1 = RuleBasedAIPlayerScript.decide(gs, legal1)
		_check(not act1.is_empty(), "p1 nonempty decision")
		_check_no_engine_choice(act1)
		_check(_choice_in_legal(act1, legal1), "p1 choice in legal list")
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
	_check(n_move1 == 0, "p1 may have no units left to move after founding")
	_check(end_order.size() >= 2, "at least two end_turn entries in log slice checked")
	_check(end_order[0] == 0 and end_order[1] == 1, "end_turn order 0 then 1")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check_no_engine_choice(action: Dictionary) -> void:
	var t = action.get("action_type", "")
	_check(t != "production_progress", "AI must not choose production_progress")
	_check(t != "unit_produced", "AI must not choose unit_produced")


func _choice_in_legal(choice: Dictionary, legal: Array) -> bool:
	var j = 0
	while j < legal.size():
		if _action_dict_equal(choice, legal[j]):
			return true
		j = j + 1
	return false


func _action_dict_equal(a: Dictionary, b) -> bool:
	if typeof(b) != TYPE_DICTIONARY:
		return false
	var bb = b as Dictionary
	for k in a:
		if not bb.has(k):
			return false
		var va = a[k]
		var vb = bb[k]
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
	for k2 in bb:
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
