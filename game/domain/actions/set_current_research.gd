# Player-selected active science for per-turn yield routing. Phase 5.1.12c. Applied only via GameState.try_apply.
class_name SetCurrentResearch
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "set_current_research"

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const ScienceAvailabilityScript = preload("res://domain/science_availability.gd")


static func make(actor_id: int, science_id: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"science_id": science_id,
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
	if not action.has("science_id") or typeof(action["science_id"]) != TYPE_STRING:
		return {"ok": false, "reason": "malformed_action"}
	var sid = action["science_id"] as String
	if sid.is_empty():
		return {"ok": true, "reason": ""}
	if not ProgressDefinitionsScript.has(sid):
		return {"ok": false, "reason": "unknown_science"}
	if not ProgressDefinitionsScript.is_science(sid):
		return {"ok": false, "reason": "not_a_science"}
	var actor = int(action["actor_id"])
	if progress_state.has_completed_progress(actor, sid):
		return {"ok": false, "reason": "already_completed"}
	if not ScienceAvailabilityScript.is_available(progress_state, actor, sid):
		return {"ok": false, "reason": "prerequisites_not_met"}
	return {"ok": true, "reason": ""}
