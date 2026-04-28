# EndTurn action: advance TurnState via GameState.try_apply. Validate is structural only; current-player gate is in GameState.
# See docs/TURNS.md, docs/ACTIONS.md
class_name EndTurn
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "end_turn"

const TurnStateScript = preload("res://domain/turn_state.gd")

static func make(actor_id: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
	}

static func validate(turn_state, action) -> Dictionary:
	if turn_state == null:
		return {"ok": false, "reason": "turn_state_null"}
	if action == null:
		return {"ok": false, "reason": "wrong_action_type"}
	if typeof(action) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "wrong_action_type"}
	if not action.has("action_type"):
		return {"ok": false, "reason": "wrong_action_type"}
	if action["action_type"] != ACTION_TYPE:
		return {"ok": false, "reason": "wrong_action_type"}
	if not action.has("schema_version"):
		return {"ok": false, "reason": "unsupported_schema_version"}
	if action["schema_version"] != SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_schema_version"}
	if not action.has("actor_id"):
		return {"ok": false, "reason": "malformed_action"}
	if typeof(action["actor_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	return {"ok": true, "reason": ""}

static func apply(turn_state, action):
	var vr = validate(turn_state, action)
	assert(vr["ok"], "EndTurn.apply called with invalid action")
	return turn_state.advance()
