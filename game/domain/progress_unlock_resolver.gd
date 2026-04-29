# Bridge from ProgressDefinitions to ProgressState: apply concrete_unlocks + systemic_effects only.
# See docs/PROGRESSION_MODEL.md, Phase 3.4d. No future_dependencies application; no GameState integration.
class_name ProgressUnlockResolver
extends RefCounted

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")


static func complete_progress(progress_state, owner_id: int, progress_id: String) -> Dictionary:
	if progress_state == null:
		return {
			"ok": false,
			"reason": "progress_state_null",
			"progress_state": progress_state,
			"unlocked_targets": [],
		}
	if not ProgressDefinitionsScript.has(progress_id):
		return {
			"ok": false,
			"reason": "unknown_progress_id",
			"progress_state": progress_state,
			"unlocked_targets": [],
		}
	if progress_state.has_completed_progress(owner_id, progress_id):
		return {
			"ok": true,
			"reason": "",
			"progress_state": progress_state,
			"unlocked_targets": [],
		}
	var next_state = progress_state.with_progress_id_completed(owner_id, progress_id)
	var newly_unlocked: Array = []
	var source: Array = []
	var cu = ProgressDefinitionsScript.concrete_unlocks(progress_id) as Array
	var si = 0
	while si < cu.size():
		source.append(cu[si])
		si = si + 1
	var se_list = ProgressDefinitionsScript.systemic_effects(progress_id) as Array
	var sj = 0
	while sj < se_list.size():
		source.append(se_list[sj])
		sj = sj + 1
	var ri = 0
	while ri < source.size():
		var row = source[ri] as Dictionary
		var target_type = str(row["target_type"])
		var target_id = str(row["target_id"])
		if not next_state.has_unlocked_target(owner_id, target_type, target_id):
			var add_row: Dictionary = {}
			add_row["target_type"] = target_type
			add_row["target_id"] = target_id
			newly_unlocked.append(add_row)
		next_state = next_state.with_target_unlocked(owner_id, target_type, target_id)
		ri = ri + 1
	return {
		"ok": true,
		"reason": "",
		"progress_state": next_state,
		"unlocked_targets": newly_unlocked,
	}
