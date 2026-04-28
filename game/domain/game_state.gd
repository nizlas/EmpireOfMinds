# Authoritative local session: current Scenario, TurnState, and ActionLog. Mutations only via try_apply.
# See docs/ACTIONS.md, docs/TURNS.md, docs/ARCHITECTURE_PRINCIPLES.md
class_name GameState
extends RefCounted

const ScenarioScript = preload("res://domain/scenario.gd")
const ActionLogScript = preload("res://domain/action_log.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnStateScript = preload("res://domain/turn_state.gd")
const _GAME_STATE_SCRIPT = preload("res://domain/game_state.gd")

var scenario
var log
var turn_state

func _init(initial_scenario) -> void:
	scenario = initial_scenario
	log = ActionLogScript.new()
	turn_state = TurnStateScript.new([0, 1], 0, 1)

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
	if at != MoveUnitScript.ACTION_TYPE and at != EndTurnScript.ACTION_TYPE:
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
	if at == EndTurnScript.ACTION_TYPE:
		var er = EndTurnScript.validate(turn_state, action)
		if not er["ok"]:
			return {"accepted": false, "reason": er["reason"], "index": -1}
		var prev_turn_number = turn_state.turn_number
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
		return {"accepted": true, "reason": "", "index": e_idx}
	return {"accepted": false, "reason": "unknown_action_type", "index": -1}

static func make_tiny_test_state():
	return _GAME_STATE_SCRIPT.new(ScenarioScript.make_tiny_test_scenario())
