# Immutable per-player explored-tile memory (Phase 5.2.3). Presentation-independent; no fog privacy / networking.
class_name PlayerVisibilityState
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")
const _PLAYER_VISIBILITY_STATE = preload("res://domain/player_visibility_state.gd")

const UNIT_SIGHT_RADIUS: int = 2
const CITY_SIGHT_RADIUS: int = 2

var _by_owner: Dictionary  # int owner_id -> Dictionary Vector2i -> true


static func _sort_ints_asc(ids: Array) -> void:
	var a: int = 0
	while a < ids.size():
		var b: int = a + 1
		while b < ids.size():
			if (ids[a] as int) > (ids[b] as int):
				var tmp = ids[a]
				ids[a] = ids[b]
				ids[b] = tmp
			b = b + 1
		a = a + 1


func _init(p_by_owner: Dictionary = {}) -> void:
	_by_owner = {}
	var ks = p_by_owner.keys()
	var key_list: Array = []
	var ki: int = 0
	while ki < ks.size():
		assert(typeof(ks[ki]) == TYPE_INT, "owner_id must be int")
		key_list.append(ks[ki])
		ki = ki + 1
	_sort_ints_asc(key_list)
	var idx: int = 0
	while idx < key_list.size():
		var owner_id: int = int(key_list[idx])
		var raw = p_by_owner[owner_id]
		assert(typeof(raw) == TYPE_DICTIONARY, "owner entry must be Dictionary")
		var inner: Dictionary = {}
		var ik = (raw as Dictionary).keys()
		var ii: int = 0
		while ii < ik.size():
			var k = ik[ii]
			assert(typeof(k) == TYPE_VECTOR2I, "explored key must be Vector2i")
			inner[k] = true
			ii = ii + 1
		_by_owner[owner_id] = inner
		idx = idx + 1


static func empty_for_players(player_ids: Array) -> PlayerVisibilityState:
	var uniq: Dictionary = {}
	var pi: int = 0
	while pi < player_ids.size():
		uniq[int(player_ids[pi])] = true
		pi = pi + 1
	var owners: Array = uniq.keys()
	_sort_ints_asc(owners)
	var bo: Dictionary = {}
	var oi: int = 0
	while oi < owners.size():
		bo[int(owners[oi])] = {}
		oi = oi + 1
	return _PLAYER_VISIBILITY_STATE.new(bo)


func _inner_for_owner(owner_id: int) -> Dictionary:
	if not _by_owner.has(owner_id):
		return {}
	return _by_owner[owner_id] as Dictionary


func explored_for_player(owner_id: int) -> Array:
	var inner: Dictionary = _inner_for_owner(owner_id)
	var ks = inner.keys()
	var pairs: Array = []
	var i: int = 0
	while i < ks.size():
		var vi: Vector2i = ks[i]
		pairs.append([int(vi.x), int(vi.y)])
		i = i + 1
	var a: int = 0
	while a < pairs.size():
		var b: int = a + 1
		while b < pairs.size():
			var pa: Array = pairs[a] as Array
			var pb: Array = pairs[b] as Array
			if int(pb[0]) < int(pa[0]) or (int(pb[0]) == int(pa[0]) and int(pb[1]) < int(pa[1])):
				var t = pairs[a]
				pairs[a] = pairs[b]
				pairs[b] = t
			b = b + 1
		a = a + 1
	var out: Array = []
	var j: int = 0
	while j < pairs.size():
		var p: Array = pairs[j] as Array
		out.append(HexCoordScript.new(int(p[0]), int(p[1])))
		j = j + 1
	return out


func is_explored(owner_id: int, coord) -> bool:
	if coord == null:
		return false
	if not _by_owner.has(owner_id):
		return false
	var inner: Dictionary = _by_owner[owner_id]
	var vk := Vector2i(int(coord.q), int(coord.r))
	return inner.has(vk)


func with_revealed(owner_id: int, coords: Array) -> PlayerVisibilityState:
	var new_bo: Dictionary = {}
	var ok = _by_owner.keys()
	var oi: int = 0
	while oi < ok.size():
		var oid: int = int(ok[oi])
		var src: Dictionary = _by_owner[oid]
		var cpy: Dictionary = {}
		var sk = src.keys()
		var si: int = 0
		while si < sk.size():
			cpy[sk[si]] = true
			si = si + 1
		new_bo[oid] = cpy
		oi = oi + 1
	if not new_bo.has(owner_id):
		new_bo[owner_id] = {}
	var tgt: Dictionary = new_bo[owner_id]
	var ci: int = 0
	while ci < coords.size():
		var c = coords[ci]
		if c == null:
			ci = ci + 1
			continue
		if c is HexCoord:
			var hc: HexCoord = c as HexCoord
			tgt[Vector2i(int(hc.q), int(hc.r))] = true
		elif typeof(c) == TYPE_ARRAY and (c as Array).size() == 2:
			var ca: Array = c as Array
			tgt[Vector2i(int(ca[0]), int(ca[1]))] = true
		ci = ci + 1
	return _PLAYER_VISIBILITY_STATE.new(new_bo)


func equals(other) -> bool:
	if other == null or not (other is PlayerVisibilityState):
		return false
	var oth: PlayerVisibilityState = other as PlayerVisibilityState
	var k1 = _by_owner.keys()
	var k2 = oth._by_owner.keys()
	if k1.size() != k2.size():
		return false
	_sort_ints_asc(k1)
	_sort_ints_asc(k2)
	var i: int = 0
	while i < k1.size():
		if int(k1[i]) != int(k2[i]):
			return false
		var d1: Dictionary = _by_owner[int(k1[i])]
		var d2: Dictionary = oth._by_owner[int(k2[i])]
		if d1.size() != d2.size():
			return false
		var dk = d1.keys()
		var dj: int = 0
		while dj < dk.size():
			if not d2.has(dk[dj]):
				return false
			dj = dj + 1
		i = i + 1
	return true


static func recompute_for_actor(prev: PlayerVisibilityState, scenario, actor_id: int) -> PlayerVisibilityState:
	if scenario == null or scenario.map == null or prev == null:
		return prev
	var to_add: Array = []
	var map_coords: Array = scenario.map.coords()
	var ulist: Array = scenario.units()
	var ui: int = 0
	while ui < ulist.size():
		var u = ulist[ui]
		if int(u.owner_id) != int(actor_id):
			ui = ui + 1
			continue
		var mi: int = 0
		while mi < map_coords.size():
			var mc = map_coords[mi]
			if HexCoordScript.axial_distance(u.position, mc) <= UNIT_SIGHT_RADIUS:
				to_add.append(mc)
			mi = mi + 1
		ui = ui + 1
	var clist: Array = scenario.cities()
	var ci: int = 0
	while ci < clist.size():
		var cty = clist[ci]
		if int(cty.owner_id) != int(actor_id):
			ci = ci + 1
			continue
		var anchors: Array = [cty.position]
		var oti: int = 0
		while oti < cty.owned_tiles.size():
			anchors.append(cty.owned_tiles[oti])
			oti = oti + 1
		var ai: int = 0
		while ai < anchors.size():
			var ac = anchors[ai]
			var mj: int = 0
			while mj < map_coords.size():
				var mc2 = map_coords[mj]
				if HexCoordScript.axial_distance(ac, mc2) <= CITY_SIGHT_RADIUS:
					to_add.append(mc2)
				mj = mj + 1
			ai = ai + 1
		ci = ci + 1
	var existing: Array = prev.explored_for_player(actor_id)
	var merged: Array = []
	var ei: int = 0
	while ei < existing.size():
		merged.append(existing[ei])
		ei = ei + 1
	var ti: int = 0
	while ti < to_add.size():
		merged.append(to_add[ti])
		ti = ti + 1
	return prev.with_revealed(actor_id, merged)


static func seed_all_players(prev: PlayerVisibilityState, scenario, player_ids: Array) -> PlayerVisibilityState:
	var out: PlayerVisibilityState = prev
	var pi: int = 0
	while pi < player_ids.size():
		out = recompute_for_actor(out, scenario, int(player_ids[pi]))
		pi = pi + 1
	return out
