# Read-only progress candidate generator. Phase 3.4g — does not mutate GameState or call try_apply.
# Phase 5.1.8a: controlled_fire candidate requires observing the prototype Lightning-Scarred Tree (optional scenario landmark).
# See docs/PROGRESSION_MODEL.md
class_name ProgressDetector
extends RefCounted

const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

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
	if game_state.scenario == null:
		return out
	var tree_hex = game_state.scenario.lightning_tree_hex
	if tree_hex == null:
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
		if game_state.progress_state.has_completed_progress(player_id, "controlled_fire"):
			pi = pi + 1
			continue
		if _player_observed_lightning_tree(game_state.log, player_id, tree_hex):
			out.append(CompleteProgressScript.make(player_id, "controlled_fire"))
		pi = pi + 1
	return out


static func _player_observed_lightning_tree(action_log, actor_id: int, tree_hex) -> bool:
	if action_log == null or tree_hex == null:
		return false
	if not action_log.has_method("size") or not action_log.has_method("get_entry"):
		return false
	var n = action_log.size()
	var i = 0
	while i < n:
		var entry = action_log.get_entry(i)
		if typeof(entry) != TYPE_DICTIONARY:
			i = i + 1
			continue
		var d = entry as Dictionary
		if str(d.get("result", "")) != "accepted":
			i = i + 1
			continue
		if str(d.get("action_type", "")) != MoveUnitScript.ACTION_TYPE:
			i = i + 1
			continue
		if not d.has("actor_id") or typeof(d["actor_id"]) != TYPE_INT:
			i = i + 1
			continue
		if int(d["actor_id"]) != actor_id:
			i = i + 1
			continue
		if not d.has("to") or typeof(d["to"]) != TYPE_ARRAY:
			i = i + 1
			continue
		var to_a = d["to"] as Array
		if to_a.size() != 2:
			i = i + 1
			continue
		if typeof(to_a[0]) != TYPE_INT or typeof(to_a[1]) != TYPE_INT:
			i = i + 1
			continue
		var to_c = HexCoordScript.new(int(to_a[0]), int(to_a[1]))
		if to_c.equals(tree_hex):
			return true
		var neigh = tree_hex.neighbors()
		var ni = 0
		while ni < neigh.size():
			if to_c.equals(neigh[ni]):
				return true
			ni = ni + 1
		i = i + 1
	return false
