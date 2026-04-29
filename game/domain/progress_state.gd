# Player-specific unlock state (metadata for gating). Not part of Scenario. See docs/PROGRESSION_MODEL.md.
# Immutable snapshots: mutating helpers return new ProgressState. No content-registry preloads.
class_name ProgressState
extends RefCounted

const _PROGRESS_STATE_SCRIPT = preload("res://domain/progress_state.gd")

var _by_owner: Dictionary


static func _sort_ints_asc(ids: Array) -> void:
	var a = 0
	while a < ids.size():
		var b = a + 1
		while b < ids.size():
			if (ids[a] as int) > (ids[b] as int):
				var tmp = ids[a]
				ids[a] = ids[b]
				ids[b] = tmp
			b = b + 1
		a = a + 1


static func _sort_target_rows(targets: Array) -> void:
	var a = 0
	while a < targets.size():
		var b = a + 1
		while b < targets.size():
			var da = targets[a] as Dictionary
			var db = targets[b] as Dictionary
			var sa = str(da["target_type"])
			var sb = str(db["target_type"])
			if sb < sa or (sb == sa and str(db["target_id"]) < str(da["target_id"])):
				var t = targets[a]
				targets[a] = targets[b]
				targets[b] = t
			b = b + 1
		a = a + 1


static func _normalize_unlocked_targets(raw: Array) -> Array:
	var out: Array = []
	var ri = 0
	while ri < raw.size():
		var item = raw[ri]
		assert(typeof(item) == TYPE_DICTIONARY, "each unlock must be Dictionary")
		var d = item as Dictionary
		assert(d.has("target_type") and typeof(d["target_type"]) == TYPE_STRING, "target_type string")
		assert(d.has("target_id") and typeof(d["target_id"]) == TYPE_STRING, "target_id string")
		var row: Dictionary = {}
		row["target_type"] = str(d["target_type"])
		row["target_id"] = str(d["target_id"])
		out.append(row)
		ri = ri + 1
	_sort_target_rows(out)
	var dedup: Array = []
	var di = 0
	while di < out.size():
		if dedup.size() == 0:
			dedup.append((out[di] as Dictionary).duplicate(true))
		else:
			var prev = dedup[dedup.size() - 1] as Dictionary
			var cur = out[di] as Dictionary
			var same_type = str(prev["target_type"]) == str(cur["target_type"])
			var same_id = str(prev["target_id"]) == str(cur["target_id"])
			if not (same_type and same_id):
				dedup.append(cur.duplicate(true))
		di = di + 1
	return dedup


func _init(p_by_owner: Dictionary = {}) -> void:
	_by_owner = {}
	var key_list: Array = []
	var ks = p_by_owner.keys()
	var ki = 0
	while ki < ks.size():
		var k = ks[ki]
		assert(typeof(k) == TYPE_INT, "owner_id must be int")
		key_list.append(k)
		ki = ki + 1
	_sort_ints_asc(key_list)
	var idx = 0
	while idx < key_list.size():
		var owner_id = key_list[idx] as int
		var entry = p_by_owner[owner_id]
		assert(typeof(entry) == TYPE_DICTIONARY, "owner entry must be Dictionary")
		assert(entry.has("unlocked_targets"), "missing unlocked_targets")
		var ut = entry["unlocked_targets"]
		assert(typeof(ut) == TYPE_ARRAY, "unlocked_targets must be Array")
		var inner: Dictionary = {}
		inner["unlocked_targets"] = _normalize_unlocked_targets(ut as Array)
		_by_owner[owner_id] = inner
		idx = idx + 1


static func with_default_unlocks_for_players(player_ids: Array) -> ProgressState:
	var uniq: Array = []
	var pi = 0
	while pi < player_ids.size():
		var pid = int(player_ids[pi])
		var found = false
		var uj = 0
		while uj < uniq.size():
			if int(uniq[uj]) == pid:
				found = true
				break
			uj = uj + 1
		if not found:
			uniq.append(pid)
		pi = pi + 1
	_sort_ints_asc(uniq)
	var built: Dictionary = {}
	var bi = 0
	while bi < uniq.size():
		var oid = uniq[bi] as int
		var row1: Dictionary = {}
		row1["target_type"] = "city_project"
		row1["target_id"] = "produce_unit:warrior"
		built[oid] = {"unlocked_targets": [row1]}
		bi = bi + 1
	return _PROGRESS_STATE_SCRIPT.new(built)


func owner_ids() -> Array:
	var key_list: Array = []
	var ks2 = _by_owner.keys()
	var ki = 0
	while ki < ks2.size():
		key_list.append(ks2[ki])
		ki = ki + 1
	_sort_ints_asc(key_list)
	return key_list.duplicate()


func unlocked_targets_for(owner_id: int) -> Array:
	if not _by_owner.has(owner_id):
		return []
	var inner: Dictionary = _by_owner[owner_id]
	return (inner["unlocked_targets"] as Array).duplicate(true)


func has_unlocked_target(owner_id: int, target_type: String, target_id: String) -> bool:
	var arr = unlocked_targets_for(owner_id)
	var i = 0
	while i < arr.size():
		var d = arr[i] as Dictionary
		if str(d["target_type"]) == target_type and str(d["target_id"]) == target_id:
			return true
		i = i + 1
	return false


func with_target_unlocked(owner_id: int, target_type: String, target_id: String) -> ProgressState:
	var built: Dictionary = {}
	var existing_oids = owner_ids()
	var oi = 0
	var found_owner = false
	while oi < existing_oids.size():
		var oid = int(existing_oids[oi])
		var inner0: Dictionary = _by_owner[oid]
		var raw: Array = (inner0["unlocked_targets"] as Array).duplicate(true)
		if oid == owner_id:
			found_owner = true
			var add_row: Dictionary = {}
			add_row["target_type"] = target_type
			add_row["target_id"] = target_id
			raw.append(add_row)
		built[oid] = {"unlocked_targets": raw}
		oi = oi + 1
	if not found_owner:
		var single: Dictionary = {}
		single["target_type"] = target_type
		single["target_id"] = target_id
		built[owner_id] = {"unlocked_targets": [single]}
	return _PROGRESS_STATE_SCRIPT.new(built)


func equals(other) -> bool:
	if other == null:
		return false
	if not (other is ProgressState):
		return false
	var o: ProgressState = other
	var a_ids = owner_ids()
	var b_ids = o.owner_ids()
	if a_ids.size() != b_ids.size():
		return false
	var i = 0
	while i < a_ids.size():
		if int(a_ids[i]) != int(b_ids[i]):
			return false
		var oid = int(a_ids[i])
		var oa = unlocked_targets_for(oid)
		var ob = o.unlocked_targets_for(oid)
		if oa.size() != ob.size():
			return false
		var j = 0
		while j < oa.size():
			var da = oa[j] as Dictionary
			var db = ob[j] as Dictionary
			if str(da["target_type"]) != str(db["target_type"]):
				return false
			if str(da["target_id"]) != str(db["target_id"]):
				return false
			j = j + 1
		i = i + 1
	return true
