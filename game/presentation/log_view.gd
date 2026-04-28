# Read-only debug text for accepted ActionLog entries. No polling; controllers call refresh().
# Uses GameState.log.size() / get_entry(i) only. See docs/RENDERING.md, docs/ACTIONS.md.
extends Label

const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

const MAX_ENTRIES: int = 10

var game_state

static func _entry_index(entry: Dictionary) -> int:
	if entry.has("index") and typeof(entry["index"]) == TYPE_INT:
		return entry["index"]
	return -1


static func format_entry(entry: Dictionary) -> String:
	var idx = _entry_index(entry)
	if not entry.has("action_type") or typeof(entry["action_type"]) != TYPE_STRING:
		return "[%d] ?" % idx
	var at = entry["action_type"]
	var actor_id = -1
	if entry.has("actor_id") and typeof(entry["actor_id"]) == TYPE_INT:
		actor_id = entry["actor_id"]
	if at == MoveUnitScript.ACTION_TYPE:
		var uid = 0
		if entry.has("unit_id") and typeof(entry["unit_id"]) == TYPE_INT:
			uid = entry["unit_id"]
		var fq = 0
		var fr = 0
		var tq = 0
		var tr = 0
		if entry.has("from"):
			var fa = entry["from"] as Array
			if fa.size() >= 2:
				fq = int(fa[0])
				fr = int(fa[1])
		if entry.has("to"):
			var ta = entry["to"] as Array
			if ta.size() >= 2:
				tq = int(ta[0])
				tr = int(ta[1])
		return "[%d] P%d move_unit unit %d (%d,%d) -> (%d,%d)" % [idx, actor_id, uid, fq, fr, tq, tr]
	if at == EndTurnScript.ACTION_TYPE:
		var tnb = 0
		var np = 0
		if entry.has("turn_number_before") and typeof(entry["turn_number_before"]) == TYPE_INT:
			tnb = entry["turn_number_before"]
		if entry.has("next_player_id") and typeof(entry["next_player_id"]) == TYPE_INT:
			np = entry["next_player_id"]
		return "[%d] P%d end_turn T%d -> P%d" % [idx, actor_id, tnb, np]
	return "[%d] P%d %s" % [idx, actor_id, at]


static func _join_lines(lines: Array) -> String:
	var out = ""
	var li = 0
	while li < lines.size():
		if li > 0:
			out = out + "\n"
		out = out + (lines[li] as String)
		li = li + 1
	return out


static func compute_text(a_game_state, n: int = MAX_ENTRIES) -> String:
	if a_game_state == null or a_game_state.log == null:
		return ""
	var log_ref = a_game_state.log
	var sz = log_ref.size()
	if sz == 0 or n <= 0:
		return ""
	var take = n
	if take > sz:
		take = sz
	var lines = []
	var start = sz - take
	var i = start
	while i < sz:
		var e = log_ref.get_entry(i)
		lines.append(format_entry(e))
		i = i + 1
	return _join_lines(lines)


func refresh() -> void:
	text = compute_text(game_state)
