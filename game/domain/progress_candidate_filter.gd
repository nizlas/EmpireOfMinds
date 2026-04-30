# Filters ProgressDetector candidates to the current player (actor_id gate only). Phase 3.4h.
# Does not validate CompleteProgress — GameState.try_apply remains authoritative.
# See docs/PROGRESSION_MODEL.md
class_name ProgressCandidateFilter
extends RefCounted

const ProgressDetectorScript = preload("res://domain/progress_detector.gd")

static func for_current_player(game_state) -> Array:
	var out: Array = []
	if game_state == null:
		return out
	if game_state.turn_state == null:
		return out
	var cur = int(game_state.turn_state.current_player_id())
	var raw: Array = ProgressDetectorScript.suggested_complete_progress_actions(game_state)
	var i = 0
	while i < raw.size():
		var item = raw[i]
		if typeof(item) == TYPE_DICTIONARY:
			var c = item as Dictionary
			if c.has("actor_id") and typeof(c["actor_id"]) == TYPE_INT and int(c["actor_id"]) == cur:
				out.append(c)
		i = i + 1
	return out
