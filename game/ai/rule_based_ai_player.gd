# Deterministic rule-based AI: city loop (FoundCity, SetCityProduction), then one MoveUnit per turn (Policy), else EndTurn.
# See docs/AI_LAYER.md
class_name RuleBasedAIPlayer
extends RefCounted

const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const RuleBasedAIPolicyScript = preload("res://ai/rule_based_ai_policy.gd")

static func _player_owns_no_cities(scenario, owner_id: int) -> bool:
	if scenario == null:
		return true
	return scenario.cities_owned_by(owner_id).size() == 0


static func _player_has_city_without_project(scenario, owner_id: int) -> bool:
	if scenario == null:
		return false
	var cl = scenario.cities_owned_by(owner_id)
	var i = 0
	while i < cl.size():
		var c = cl[i]
		if c.current_project == null:
			return true
		i = i + 1
	return false


static func _first_of_action_type(legal_actions: Array, action_type: String):
	var j = 0
	while j < legal_actions.size():
		var a = legal_actions[j]
		if typeof(a) == TYPE_DICTIONARY and a.get("action_type", "") == action_type:
			return a
		j = j + 1
	return null


static func decide(game_state, legal_actions: Array) -> Dictionary:
	if legal_actions.size() == 0:
		return {}
	if game_state != null:
		var cp = game_state.turn_state.current_player_id()
		var scen = game_state.scenario
		if _player_owns_no_cities(scen, cp):
			var f0 = _first_of_action_type(legal_actions, FoundCityScript.ACTION_TYPE)
			if f0 != null:
				return f0
		if _player_has_city_without_project(scen, cp):
			var s0 = _first_of_action_type(legal_actions, SetCityProductionScript.ACTION_TYPE)
			if s0 != null:
				return s0
		if RuleBasedAIPolicyScript.has_actor_moved_this_turn(game_state.log, cp):
			var e_m = _first_of_action_type(legal_actions, EndTurnScript.ACTION_TYPE)
			if e_m != null:
				return e_m
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
