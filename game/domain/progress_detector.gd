# Read-only progress candidate generator. Phase 3.4g — does not mutate GameState or call try_apply.
# See docs/PROGRESSION_MODEL.md
class_name ProgressDetector
extends RefCounted

const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")

static func suggested_complete_progress_actions(game_state) -> Array:
	var out: Array = []
	if game_state == null:
		return out
	if game_state.progress_state == null:
		return out
	if game_state.log == null:
		return out
	if game_state.turn_state == null:
		return out
	var players_raw = game_state.turn_state.players
	if typeof(players_raw) != TYPE_ARRAY:
		return out
	var players = players_raw as Array
	var pi = 0
	while pi < players.size():
		var pid_raw = players[pi]
		if typeof(pid_raw) != TYPE_INT:
			pi = pi + 1
			continue
		var player_id = int(pid_raw)
		if _has_accepted_action(game_state.log, player_id, FoundCityScript.ACTION_TYPE):
			if not game_state.progress_state.has_completed_progress(player_id, "controlled_fire"):
				out.append(CompleteProgressScript.make(player_id, "controlled_fire"))
		pi = pi + 1
	return out


static func _has_accepted_action(action_log, actor_id: int, action_type: String) -> bool:
	if action_log == null:
		return false
	if not action_log.has_method("size") or not action_log.has_method("get_entry"):
		return false
	var n = action_log.size()
	var i = 0
	while i < n:
		var entry = action_log.get_entry(i)
		if typeof(entry) == TYPE_DICTIONARY:
			var d = entry as Dictionary
			if (
				str(d.get("result", "")) == "accepted"
				and str(d.get("action_type", "")) == action_type
				and d.has("actor_id")
				and typeof(d["actor_id"]) == TYPE_INT
				and int(d["actor_id"]) == actor_id
			):
				return true
		i = i + 1
	return false
