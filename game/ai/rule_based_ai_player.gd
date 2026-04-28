# Deterministic rule-based AI: one MoveUnit per turn (Policy), else pick first legal MoveUnit, else EndTurn.
# See docs/AI_LAYER.md
class_name RuleBasedAIPlayer
extends RefCounted

const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const RuleBasedAIPolicyScript = preload("res://ai/rule_based_ai_policy.gd")

static func decide(game_state, legal_actions: Array) -> Dictionary:
	if legal_actions.size() == 0:
		return {}
	if game_state != null and RuleBasedAIPolicyScript.has_actor_moved_this_turn(
		game_state.log, game_state.turn_state.current_player_id()
	):
		var lk = 0
		while lk < legal_actions.size():
			var ak = legal_actions[lk]
			if typeof(ak) == TYPE_DICTIONARY and ak.get("action_type", "") == EndTurnScript.ACTION_TYPE:
				return ak
			lk = lk + 1
	var li = 0
	while li < legal_actions.size():
		var a = legal_actions[li]
		if typeof(a) == TYPE_DICTIONARY and a.get("action_type", "") == MoveUnitScript.ACTION_TYPE:
			return a
		li = li + 1
	var lj = 0
	while lj < legal_actions.size():
		var a2 = legal_actions[lj]
		if typeof(a2) == TYPE_DICTIONARY and a2.get("action_type", "") == EndTurnScript.ACTION_TYPE:
			return a2
		lj = lj + 1
	return {}
