# Headless: godot --headless --path game -s res://ai/tests/test_core_loop_ai_smoke.gd
extends SceneTree

const LegalActionsScript = preload("res://domain/legal_actions.gd")
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

const MAX_STEPS: int = 48

var _total = 0
var _any_fail = false

func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var initial_next_unit_id = gs.scenario.peek_next_unit_id()
	var found_city_count = 0
	var set_city_production_count = 0
	var production_progress_count = 0
	var unit_produced_count = 0
	var step = 0
	var goals_met = false
	while step < MAX_STEPS:
		var legal = LegalActionsScript.for_current_player(gs)
		var choice = RuleBasedAIPlayerScript.decide(gs, legal)
		_check(not choice.is_empty(), "nonempty ai choice")
		_check(choice.has("action_type") and typeof(choice["action_type"]) == TYPE_STRING, "choice has action_type string")
		var at = choice["action_type"] as String
		_check(at != ProductionTickScript.EVENT_TYPE, "ai must not choose production_progress")
		_check(at != ProductionDeliveryScript.EVENT_TYPE, "ai must not choose unit_produced")
		var allowed = (
			at == FoundCityScript.ACTION_TYPE
			or at == SetCityProductionScript.ACTION_TYPE
			or at == MoveUnitScript.ACTION_TYPE
			or at == EndTurnScript.ACTION_TYPE
		)
		_check(allowed, "choice is player action type")
		var result = gs.try_apply(choice)
		_check(result["accepted"] == true, "try_apply accepted")

		found_city_count = _count_log_action(gs, FoundCityScript.ACTION_TYPE)
		set_city_production_count = _count_log_action(gs, SetCityProductionScript.ACTION_TYPE)
		production_progress_count = _count_log_action(gs, ProductionTickScript.EVENT_TYPE)
		unit_produced_count = _count_log_action(gs, ProductionDeliveryScript.EVENT_TYPE)

		step = step + 1
		if unit_produced_count >= 1 and gs.turn_state.turn_number >= 2:
			goals_met = true
			break

	_check(goals_met, "reached unit_produced and turn_number>=2 within loop")
	_check(step < MAX_STEPS, "ended before MAX_STEPS")

	_check(found_city_count >= 1, "at least one found_city in log")
	_check(set_city_production_count >= 1, "at least one set_city_production in log")
	_check(production_progress_count >= 1, "at least one production_progress in log")
	_check(unit_produced_count >= 1, "at least one unit_produced in log")
	_check(gs.turn_state.turn_number >= 2, "turn_number >= 2")

	var has_new_unit = _scenario_has_unit_id_at_least(gs.scenario, initial_next_unit_id)
	_check(has_new_unit, "at least one unit with id >= initial peek_next_unit_id")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _count_log_action(gs, action_type: String) -> int:
	var c = 0
	var i = 0
	while i < gs.log.size():
		var e = gs.log.get_entry(i)
		if e.get("action_type", "") == action_type:
			c = c + 1
		i = i + 1
	return c


func _scenario_has_unit_id_at_least(scenario, min_id: int) -> bool:
	var ulist = scenario.units()
	var j = 0
	while j < ulist.size():
		var u = ulist[j]
		if u.id >= min_id:
			return true
		j = j + 1
	return false


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
