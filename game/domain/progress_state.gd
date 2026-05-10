# Player-specific unlock state (metadata for gating). Not part of Scenario. See docs/PROGRESSION_MODEL.md.

# Immutable snapshots: mutating helpers return new ProgressState. No content-registry preloads.

# Phase 5.1.12c — per-owner current_research_id for ScienceTick routing ("" = auto-target).
# Phase 5.1.12d — default unlocks include produce_unit:settler (Train Settler baseline).

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





static func _sort_strings_asc(ids: Array) -> void:

	var a = 0

	while a < ids.size():

		var b = a + 1

		while b < ids.size():

			if str(ids[a]) > str(ids[b]):

				var tmp = ids[a]

				ids[a] = ids[b]

				ids[b] = tmp

			b = b + 1

		a = a + 1





static func _science_progress_from_raw(raw) -> Dictionary:

	var out: Dictionary = {}

	if typeof(raw) != TYPE_DICTIONARY:

		return out

	var ks = (raw as Dictionary).keys()

	var sorted_k: Array = []

	var si = 0

	while si < ks.size():

		sorted_k.append(str(ks[si]))

		si = si + 1

	_sort_strings_asc(sorted_k)

	var ki = 0

	while ki < sorted_k.size():

		var pid = sorted_k[ki]

		var v = (raw as Dictionary).get(pid, 0)

		if typeof(v) != TYPE_INT:

			v = int(v)

		out[pid] = int(v)

		ki = ki + 1

	return out





static func _observation_flags_from_raw(raw) -> Dictionary:

	var out: Dictionary = {}

	if typeof(raw) != TYPE_DICTIONARY:

		return out

	var ks = (raw as Dictionary).keys()

	var sorted_k: Array = []

	var si = 0

	while si < ks.size():

		sorted_k.append(str(ks[si]))

		si = si + 1

	_sort_strings_asc(sorted_k)

	var ki = 0

	while ki < sorted_k.size():

		var pid = sorted_k[ki]

		if bool((raw as Dictionary).get(pid, false)):

			out[pid] = true

		ki = ki + 1

	return out





static func _science_snapshot(inner: Dictionary) -> Dictionary:

	return _science_progress_from_raw(inner.get("science_progress", {}))





static func _observation_snapshot(inner: Dictionary) -> Dictionary:

	return _observation_flags_from_raw(inner.get("science_observation_flags", {}))





static func _inner_copy(inner0: Dictionary) -> Dictionary:

	return {

		"unlocked_targets": (inner0["unlocked_targets"] as Array).duplicate(true),

		"completed_progress_ids": (inner0["completed_progress_ids"] as Array).duplicate(),

		"science_progress": _science_snapshot(inner0),

		"science_observation_flags": _observation_snapshot(inner0),

		"current_research_id": str(inner0.get("current_research_id", "")),

	}





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





static func _normalize_completed_progress_ids(raw: Array) -> Array:

	var out: Array = []

	var ri = 0

	while ri < raw.size():

		var item = raw[ri]

		assert(typeof(item) == TYPE_STRING, "completed_progress_id must be String")

		out.append(str(item))

		ri = ri + 1

	_sort_strings_asc(out)

	var dedup: Array = []

	var di = 0

	while di < out.size():

		if dedup.size() == 0 or str(dedup[dedup.size() - 1]) != str(out[di]):

			dedup.append(str(out[di]))

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

		var cp_raw: Array = []

		if entry.has("completed_progress_ids"):

			var cp = entry["completed_progress_ids"]

			assert(typeof(cp) == TYPE_ARRAY, "completed_progress_ids must be Array")

			cp_raw = cp

		inner["completed_progress_ids"] = _normalize_completed_progress_ids(cp_raw)

		var sp_raw = {}

		if entry.has("science_progress"):

			var sp0 = entry["science_progress"]

			assert(typeof(sp0) == TYPE_DICTIONARY, "science_progress must be Dictionary")

			sp_raw = sp0

		inner["science_progress"] = _science_progress_from_raw(sp_raw)

		var ob_raw = {}

		if entry.has("science_observation_flags"):

			var ob0 = entry["science_observation_flags"]

			assert(typeof(ob0) == TYPE_DICTIONARY, "science_observation_flags must be Dictionary")

			ob_raw = ob0

		inner["science_observation_flags"] = _observation_flags_from_raw(ob_raw)

		var cr = ""

		if entry.has("current_research_id") and typeof(entry["current_research_id"]) == TYPE_STRING:

			cr = str(entry["current_research_id"])

		inner["current_research_id"] = cr

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

		var row2: Dictionary = {}

		row2["target_type"] = "city_project"

		row2["target_id"] = "produce_unit:settler"

		built[oid] = {

			"unlocked_targets": [row1, row2],

			"completed_progress_ids": [],

			"science_progress": {},

			"science_observation_flags": {},

			"current_research_id": "",

		}

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





func completed_progress_ids_for(owner_id: int) -> Array:

	if not _by_owner.has(owner_id):

		return []

	var inner: Dictionary = _by_owner[owner_id]

	return (inner["completed_progress_ids"] as Array).duplicate()





func has_completed_progress(owner_id: int, progress_id: String) -> bool:

	var arr = completed_progress_ids_for(owner_id)

	var i = 0

	while i < arr.size():

		if str(arr[i]) == str(progress_id):

			return true

		i = i + 1

	return false





func has_unlocked_target(owner_id: int, target_type: String, target_id: String) -> bool:

	var arr = unlocked_targets_for(owner_id)

	var i = 0

	while i < arr.size():

		var d = arr[i] as Dictionary

		if str(d["target_type"]) == target_type and str(d["target_id"]) == target_id:

			return true

		i = i + 1

	return false





func science_progress_for(owner_id: int, progress_id: String) -> int:

	if not _by_owner.has(owner_id):

		return 0

	var inner: Dictionary = _by_owner[owner_id]

	var sp = inner.get("science_progress", {})

	if typeof(sp) != TYPE_DICTIONARY:

		return 0

	var sd = sp as Dictionary

	if not sd.has(progress_id):

		return 0

	return int(sd[progress_id])





func has_observation_bonus_granted(owner_id: int, progress_id: String) -> bool:

	if not _by_owner.has(owner_id):

		return false

	var inner: Dictionary = _by_owner[owner_id]

	var fl = inner.get("science_observation_flags", {})

	if typeof(fl) != TYPE_DICTIONARY:

		return false

	return bool((fl as Dictionary).get(progress_id, false))





func current_research_for(owner_id: int) -> String:

	if not _by_owner.has(owner_id):

		return ""

	return str((_by_owner[owner_id] as Dictionary).get("current_research_id", ""))





func with_current_research(owner_id: int, science_id: String) -> ProgressState:

	var built: Dictionary = {}

	var existing_oids = owner_ids()

	var oi = 0

	var found_owner = false

	while oi < existing_oids.size():

		var oid = int(existing_oids[oi])

		var inner0: Dictionary = _by_owner[oid]

		var row = _inner_copy(inner0)

		if oid == owner_id:

			found_owner = true

			row["current_research_id"] = str(science_id)

		built[oid] = {

			"unlocked_targets": row["unlocked_targets"],

			"completed_progress_ids": _normalize_completed_progress_ids(

				row["completed_progress_ids"] as Array

			),

			"science_progress": row["science_progress"],

			"science_observation_flags": row["science_observation_flags"],

			"current_research_id": str(row["current_research_id"]),

		}

		oi = oi + 1

	if not found_owner:

		built[owner_id] = {

			"unlocked_targets": [],

			"completed_progress_ids": [],

			"science_progress": {},

			"science_observation_flags": {},

			"current_research_id": str(science_id),

		}

	return _PROGRESS_STATE_SCRIPT.new(built)





func with_science_progress_added(owner_id: int, progress_id: String, delta: int) -> ProgressState:

	var built: Dictionary = {}

	var existing_oids = owner_ids()

	var oi = 0

	var found_owner = false

	while oi < existing_oids.size():

		var oid = int(existing_oids[oi])

		var inner0: Dictionary = _by_owner[oid]

		var row = _inner_copy(inner0)

		var ut: Array = row["unlocked_targets"] as Array

		var cp: Array = row["completed_progress_ids"] as Array

		var sp = row["science_progress"] as Dictionary

		var obs = row["science_observation_flags"] as Dictionary

		var cr = str(row["current_research_id"])

		if oid == owner_id:

			found_owner = true

			var next_sp: Dictionary = {}

			var sk = sp.keys()

			var ski = 0

			while ski < sk.size():

				var k0 = str(sk[ski])

				next_sp[k0] = int(sp[k0])

				ski = ski + 1

			var cur = int(next_sp.get(progress_id, 0))

			next_sp[progress_id] = cur + int(delta)

			sp = _science_progress_from_raw(next_sp)

		built[oid] = {

			"unlocked_targets": ut,

			"completed_progress_ids": _normalize_completed_progress_ids(cp),

			"science_progress": sp,

			"science_observation_flags": obs,

			"current_research_id": cr,

		}

		oi = oi + 1

	if not found_owner:

		var sp_new: Dictionary = {}

		sp_new[progress_id] = int(delta)

		built[owner_id] = {

			"unlocked_targets": [],

			"completed_progress_ids": [],

			"science_progress": _science_progress_from_raw(sp_new),

			"science_observation_flags": {},

			"current_research_id": "",

		}

	return _PROGRESS_STATE_SCRIPT.new(built)





func with_observation_bonus_granted(owner_id: int, progress_id: String) -> ProgressState:

	var built: Dictionary = {}

	var existing_oids = owner_ids()

	var oi = 0

	var found_owner = false

	while oi < existing_oids.size():

		var oid = int(existing_oids[oi])

		var inner0: Dictionary = _by_owner[oid]

		var row = _inner_copy(inner0)

		var ut: Array = row["unlocked_targets"] as Array

		var cp: Array = row["completed_progress_ids"] as Array

		var sp = row["science_progress"] as Dictionary

		var obs = row["science_observation_flags"] as Dictionary

		var cr = str(row["current_research_id"])

		if oid == owner_id:

			found_owner = true

			var next_obs: Dictionary = {}

			var ok = obs.keys()

			var oj = 0

			while oj < ok.size():

				var ko = str(ok[oj])

				next_obs[ko] = true

				oj = oj + 1

			next_obs[progress_id] = true

			obs = _observation_flags_from_raw(next_obs)

		built[oid] = {

			"unlocked_targets": ut,

			"completed_progress_ids": _normalize_completed_progress_ids(cp),

			"science_progress": sp,

			"science_observation_flags": obs,

			"current_research_id": cr,

		}

		oi = oi + 1

	if not found_owner:

		var f1: Dictionary = {}

		f1[progress_id] = true

		built[owner_id] = {

			"unlocked_targets": [],

			"completed_progress_ids": [],

			"science_progress": {},

			"science_observation_flags": _observation_flags_from_raw(f1),

			"current_research_id": "",

		}

	return _PROGRESS_STATE_SCRIPT.new(built)





func with_progress_id_completed(owner_id: int, progress_id: String) -> ProgressState:

	var built: Dictionary = {}

	var existing_oids = owner_ids()

	var oi = 0

	var found_owner = false

	while oi < existing_oids.size():

		var oid = int(existing_oids[oi])

		var inner0: Dictionary = _by_owner[oid]

		var row = _inner_copy(inner0)

		var ut: Array = row["unlocked_targets"] as Array

		var cp: Array = row["completed_progress_ids"] as Array

		var sp = row["science_progress"] as Dictionary

		var obs = row["science_observation_flags"] as Dictionary

		var cr = str(row["current_research_id"])

		if oid == owner_id:

			found_owner = true

			var already = false

			var ci = 0

			while ci < cp.size():

				if str(cp[ci]) == str(progress_id):

					already = true

					break

				ci = ci + 1

			if not already:

				cp.append(progress_id)

		built[oid] = {

			"unlocked_targets": ut,

			"completed_progress_ids": _normalize_completed_progress_ids(cp),

			"science_progress": sp,

			"science_observation_flags": obs,

			"current_research_id": cr,

		}

		oi = oi + 1

	if not found_owner:

		built[owner_id] = {

			"unlocked_targets": [],

			"completed_progress_ids": _normalize_completed_progress_ids([progress_id]),

			"science_progress": {},

			"science_observation_flags": {},

			"current_research_id": "",

		}

	return _PROGRESS_STATE_SCRIPT.new(built)





func with_target_unlocked(owner_id: int, target_type: String, target_id: String) -> ProgressState:

	var built: Dictionary = {}

	var existing_oids = owner_ids()

	var oi = 0

	var found_owner = false

	while oi < existing_oids.size():

		var oid = int(existing_oids[oi])

		var inner0: Dictionary = _by_owner[oid]

		var row = _inner_copy(inner0)

		var raw: Array = (row["unlocked_targets"] as Array).duplicate(true)

		var cp_keep: Array = row["completed_progress_ids"] as Array

		var sp = row["science_progress"] as Dictionary

		var obs = row["science_observation_flags"] as Dictionary

		var cr = str(row["current_research_id"])

		if oid == owner_id:

			found_owner = true

			var add_row: Dictionary = {}

			add_row["target_type"] = target_type

			add_row["target_id"] = target_id

			raw.append(add_row)

		built[oid] = {

			"unlocked_targets": raw,

			"completed_progress_ids": _normalize_completed_progress_ids(cp_keep),

			"science_progress": sp,

			"science_observation_flags": obs,

			"current_research_id": cr,

		}

		oi = oi + 1

	if not found_owner:

		var single: Dictionary = {}

		single["target_type"] = target_type

		single["target_id"] = target_id

		built[owner_id] = {

			"unlocked_targets": [single],

			"completed_progress_ids": [],

			"science_progress": {},

			"science_observation_flags": {},

			"current_research_id": "",

		}

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

		var ca = completed_progress_ids_for(oid)

		var cb = o.completed_progress_ids_for(oid)

		if ca.size() != cb.size():

			return false

		var k = 0

		while k < ca.size():

			if str(ca[k]) != str(cb[k]):

				return false

			k = k + 1

		var inner_a: Dictionary = _by_owner[oid]

		var inner_b: Dictionary = o._by_owner[oid]

		var map_a = _science_snapshot(inner_a)

		var map_b = _science_snapshot(inner_b)

		var union_sp: Array = []

		var ka = map_a.keys()

		var kai = 0

		while kai < ka.size():

			union_sp.append(str(ka[kai]))

			kai = kai + 1

		var kb = map_b.keys()

		var kbi = 0

		while kbi < kb.size():

			var ks = str(kb[kbi])

			var dup = false

			var u = 0

			while u < union_sp.size():

				if str(union_sp[u]) == ks:

					dup = true

					break

				u = u + 1

			if not dup:

				union_sp.append(ks)

			kbi = kbi + 1

		_sort_strings_asc(union_sp)

		var pi = 0

		while pi < union_sp.size():

			var pk = str(union_sp[pi])

			if int(map_a.get(pk, 0)) != int(map_b.get(pk, 0)):

				return false

			pi = pi + 1

		var fa = _observation_snapshot(inner_a)

		var fb = _observation_snapshot(inner_b)

		var union_f: Array = []

		var fa_k = fa.keys()

		var fai = 0

		while fai < fa_k.size():

			union_f.append(str(fa_k[fai]))

			fai = fai + 1

		var fb_k = fb.keys()

		var fbi = 0

		while fbi < fb_k.size():

			var fks = str(fb_k[fbi])

			var dupf = false

			var vf = 0

			while vf < union_f.size():

				if str(union_f[vf]) == fks:

					dupf = true

					break

				vf = vf + 1

			if not dupf:

				union_f.append(fks)

			fbi = fbi + 1

		_sort_strings_asc(union_f)

		var qi = 0

		while qi < union_f.size():

			var fk = str(union_f[qi])

			var ta = fa.has(fk)

			var tb = fb.has(fk)

			if ta != tb:

				return false

			qi = qi + 1

		if current_research_for(oid) != o.current_research_for(oid):

			return false

		i = i + 1

	return true

