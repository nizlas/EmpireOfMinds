# Authoritative local session: current Scenario + ActionLog. Mutations only via try_apply.
# See docs/ACTIONS.md, docs/ARCHITECTURE_PRINCIPLES.md
class_name GameState
extends RefCounted

const ScenarioScript = preload("res://domain/scenario.gd")
const ActionLogScript = preload("res://domain/action_log.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const _GAME_STATE_SCRIPT = preload("res://domain/game_state.gd")

var scenario
var log

func _init(initial_scenario) -> void:
	scenario = initial_scenario
	log = ActionLogScript.new()

func try_apply(action: Dictionary) -> Dictionary:
	if action == null:
		return {"accepted": false, "reason": "unknown_action_type", "index": -1}
	var at = action.get("action_type", "")
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
	return {"accepted": false, "reason": "unknown_action_type", "index": -1}

static func make_tiny_test_state():
	return _GAME_STATE_SCRIPT.new(ScenarioScript.make_tiny_test_scenario())
