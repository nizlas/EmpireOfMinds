# Player-submitted completion of a progress/science id; unlocks flow via ProgressUnlockResolver in GameState.
# See docs/ACTIONS.md, Phase 3.4e. No apply() — GameState owns resolver + log.
class_name CompleteProgress
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "complete_progress"

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")


static func make(actor_id: int, progress_id: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"progress_id": progress_id,
	}


static func validate(progress_state, action) -> Dictionary:
	if progress_state == null:
		return {"ok": false, "reason": "progress_state_null"}
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
	if not action.has("actor_id") or typeof(action["actor_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if not action.has("progress_id") or typeof(action["progress_id"]) != TYPE_STRING:
		return {"ok": false, "reason": "malformed_action"}
	var pid = action["progress_id"] as String
	if pid.is_empty():
		return {"ok": false, "reason": "malformed_action"}
	if not ProgressDefinitionsScript.has(pid):
		return {"ok": false, "reason": "unknown_progress_id"}
	if progress_state.has_completed_progress(int(action["actor_id"]), pid):
		return {"ok": false, "reason": "progress_already_completed"}
	return {"ok": true, "reason": ""}
