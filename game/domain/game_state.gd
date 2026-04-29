# Authoritative local session: current Scenario, TurnState, and ActionLog. Mutations only via try_apply.
# See docs/ACTIONS.md, docs/TURNS.md, docs/ARCHITECTURE_PRINCIPLES.md
class_name GameState
extends RefCounted

const ScenarioScript = preload("res://domain/scenario.gd")
const ActionLogScript = preload("res://domain/action_log.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ProgressUnlockResolverScript = preload("res://domain/progress_unlock_resolver.gd")
const TurnStateScript = preload("res://domain/turn_state.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")
const _GAME_STATE_SCRIPT = preload("res://domain/game_state.gd")

var scenario
var log
var turn_state
var progress_state

func _init(initial_scenario, p_progress_state = null) -> void:
	scenario = initial_scenario
	log = ActionLogScript.new()
	turn_state = TurnStateScript.new([0, 1], 0, 1)
	if p_progress_state == null:
		progress_state = ProgressStateScript.with_default_unlocks_for_players(turn_state.players)
	else:
		progress_state = p_progress_state
	var init_delivery = ProductionDeliveryScript.deliver_pending_for_player(
		scenario,
		turn_state.current_player_id()
	)
	scenario = init_delivery["scenario"]
	var init_ev = init_delivery["events"] as Array
	var iv = 0
	while iv < init_ev.size():
		log.append(init_ev[iv])
		iv = iv + 1

func try_apply(action) -> Dictionary:
	if action == null:
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	if typeof(action) != TYPE_DICTIONARY:
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	if not action.has("action_type"):
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	var at = action["action_type"]
	if typeof(at) != TYPE_STRING:
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	if (
		at != MoveUnitScript.ACTION_TYPE
		and at != EndTurnScript.ACTION_TYPE
		and at != FoundCityScript.ACTION_TYPE
		and at != SetCityProductionScript.ACTION_TYPE
		and at != CompleteProgressScript.ACTION_TYPE
	):
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	if not action.has("actor_id") or typeof(action["actor_id"]) != TYPE_INT:
		return {"accepted": false, "reason": "malformed_action", "index": -1}
	if action["actor_id"] != turn_state.current_player_id():
		return {"accepted": false, "reason": "not_current_player", "index": -1}
	if at == MoveUnitScript.ACTION_TYPE:
		var r = MoveUnitScript.validate(scenario, action)
		if not r["ok"]:
			return {"accepted": false, "reason": r["reason"], "index": -1}
		scenario = MoveUnitScript.apply(scenario, action)
		var entry = {
			"schema_version": action["schema_version"],
			"action_type": action["action_type"],
			"actor_id": action["actor_id"],
			"unit_id": action["unit_id"],
			"from": (action["from"] as Array).duplicate(),
			"to": (action["to"] as Array).duplicate(),
			"result": "accepted",
		}
		var idx = log.append(entry)
		return {"accepted": true, "reason": "", "index": idx}
	if at == FoundCityScript.ACTION_TYPE:
		var fr = FoundCityScript.validate(scenario, action)
		if not fr["ok"]:
			return {"accepted": false, "reason": fr["reason"], "index": -1}
		var created_city_id = scenario.peek_next_city_id()
		scenario = FoundCityScript.apply(scenario, action)
		var fc_entry = {
			"schema_version": action["schema_version"],
			"action_type": action["action_type"],
			"actor_id": action["actor_id"],
			"unit_id": action["unit_id"],
			"city_id": created_city_id,
			"position": (action["position"] as Array).duplicate(),
			"result": "accepted",
		}
		var fc_idx = log.append(fc_entry)
		return {"accepted": true, "reason": "", "index": fc_idx}
	if at == SetCityProductionScript.ACTION_TYPE:
		var spr = SetCityProductionScript.validate(scenario, action)
		if not spr["ok"]:
			return {"accepted": false, "reason": spr["reason"], "index": -1}
		var project_id_gate = str(action.get("project_id", ""))
		if (
			progress_state != null
			and project_id_gate != SetCityProductionScript.PROJECT_ID_NONE
			and not progress_state.has_unlocked_target(
				int(action["actor_id"]),
				"city_project",
				project_id_gate
			)
		):
			return {"accepted": false, "reason": "project_not_unlocked", "index": -1}
		scenario = SetCityProductionScript.apply(scenario, action)
		var sp_entry = {
			"schema_version": action["schema_version"],
			"action_type": action["action_type"],
			"actor_id": action["actor_id"],
			"city_id": action["city_id"],
			"project_id": action["project_id"],
			"result": "accepted",
		}
		var sp_idx = log.append(sp_entry)
		return {"accepted": true, "reason": "", "index": sp_idx}
	if at == CompleteProgressScript.ACTION_TYPE:
		var cpr = CompleteProgressScript.validate(progress_state, action)
		if not cpr["ok"]:
			return {"accepted": false, "reason": cpr["reason"], "index": -1}
		var resolver_result = ProgressUnlockResolverScript.complete_progress(
			progress_state,
			int(action["actor_id"]),
			str(action["progress_id"])
		)
		if not resolver_result["ok"]:
			return {
				"accepted": false,
				"reason": str(resolver_result["reason"]),
				"index": -1,
			}
		progress_state = resolver_result["progress_state"]
		var cp_entry = {
			"schema_version": action["schema_version"],
			"action_type": action["action_type"],
			"actor_id": action["actor_id"],
			"progress_id": action["progress_id"],
			"unlocked_targets": resolver_result["unlocked_targets"],
			"result": "accepted",
		}
		var cp_idx = log.append(cp_entry)
		return {"accepted": true, "reason": "", "index": cp_idx}
	if at == EndTurnScript.ACTION_TYPE:
		var er = EndTurnScript.validate(turn_state, action)
		if not er["ok"]:
			return {"accepted": false, "reason": er["reason"], "index": -1}
		var ending_player_id = turn_state.current_player_id()
		var prev_turn_number = turn_state.turn_number
		var tick_result = ProductionTickScript.apply_for_player(scenario, ending_player_id)
		scenario = tick_result["scenario"]
		var tick_events = tick_result["events"] as Array
		var tvi = 0
		while tvi < tick_events.size():
			log.append(tick_events[tvi])
			tvi = tvi + 1
		turn_state = EndTurnScript.apply(turn_state, action)
		var e_entry = {
			"schema_version": action["schema_version"],
			"action_type": action["action_type"],
			"actor_id": action["actor_id"],
			"turn_number_before": prev_turn_number,
			"next_player_id": turn_state.current_player_id(),
			"result": "accepted",
		}
		var e_idx = log.append(e_entry)
		var delivery_result = ProductionDeliveryScript.deliver_pending_for_player(
			scenario,
			turn_state.current_player_id()
		)
		scenario = delivery_result["scenario"]
		var del_ev = delivery_result["events"] as Array
		var di = 0
		while di < del_ev.size():
			log.append(del_ev[di])
			di = di + 1
		return {"accepted": true, "reason": "", "index": e_idx}
	return {"accepted": false, "reason": "unknown_action_type", "index": -1}

static func make_tiny_test_state():
	return _GAME_STATE_SCRIPT.new(ScenarioScript.make_tiny_test_scenario())
