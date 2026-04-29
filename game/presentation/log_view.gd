# Read-only debug text for accepted ActionLog entries. No polling; controllers call refresh().
# Uses GameState.log.size() / get_entry(i) only. See docs/RENDERING.md, docs/ACTIONS.md.
extends Label

const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")

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
	if at == FoundCityScript.ACTION_TYPE:
		var uid_fc = 0
		var cid_fc = 0
		if entry.has("unit_id") and typeof(entry["unit_id"]) == TYPE_INT:
			uid_fc = entry["unit_id"]
		if entry.has("city_id") and typeof(entry["city_id"]) == TYPE_INT:
			cid_fc = entry["city_id"]
		var pq = 0
		var pr = 0
		if entry.has("position"):
			var pa = entry["position"] as Array
			if pa.size() >= 2:
				pq = int(pa[0])
				pr = int(pa[1])
		return "[%d] P%d found city c%d at (%d,%d) from u%d" % [idx, actor_id, cid_fc, pq, pr, uid_fc]
	if at == SetCityProductionScript.ACTION_TYPE:
		var cid_sp = 0
		if entry.has("city_id") and typeof(entry["city_id"]) == TYPE_INT:
			cid_sp = entry["city_id"]
		var project_id = String(entry.get("project_id", "?"))
		return "[%d] P%d set_city_production c%d %s" % [idx, actor_id, cid_sp, project_id]
	if at == CompleteProgressScript.ACTION_TYPE:
		var prog_id = String(entry.get("progress_id", "?"))
		var n_unlocks = 0
		if entry.has("unlocked_targets") and typeof(entry["unlocked_targets"]) == TYPE_ARRAY:
			n_unlocks = (entry["unlocked_targets"] as Array).size()
		return "[%d] P%d complete_progress %s (+%d unlocks)" % [idx, actor_id, prog_id, n_unlocks]
	if at == ProductionTickScript.EVENT_TYPE:
		var cid_pr = 0
		var ptt = "?"
		var pb = 0
		var pa = 0
		var co = 0
		if entry.has("city_id") and typeof(entry["city_id"]) == TYPE_INT:
			cid_pr = entry["city_id"]
		if entry.has("project_type") and typeof(entry["project_type"]) == TYPE_STRING:
			ptt = entry["project_type"]
		if entry.has("progress_before") and typeof(entry["progress_before"]) == TYPE_INT:
			pb = entry["progress_before"]
		if entry.has("progress_after") and typeof(entry["progress_after"]) == TYPE_INT:
			pa = entry["progress_after"]
		if entry.has("cost") and typeof(entry["cost"]) == TYPE_INT:
			co = entry["cost"]
		return "[%d] P%d production c%d %s %d->%d/%d" % [idx, actor_id, cid_pr, ptt, pb, pa, co]
	if at == ProductionDeliveryScript.EVENT_TYPE:
		var cid_up = 0
		var uid_up = 0
		var uq = 0
		var ur = 0
		if entry.has("city_id") and typeof(entry["city_id"]) == TYPE_INT:
			cid_up = entry["city_id"]
		if entry.has("unit_id") and typeof(entry["unit_id"]) == TYPE_INT:
			uid_up = entry["unit_id"]
		if entry.has("position"):
			var pos_a = entry["position"] as Array
			if pos_a.size() >= 2:
				uq = int(pos_a[0])
				ur = int(pos_a[1])
		return "[%d] P%d produced u%d at (%d,%d) from c%d" % [idx, actor_id, uid_up, uq, ur, cid_up]
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
