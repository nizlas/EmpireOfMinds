# City yield vectors and v0 terrain/Center/Palace rules (Phase 5.1.16c). Domain-only; no presentation imports.
# Yield keys: food, production, science, coin — see docs/CITIES.md
class_name CityYields
extends RefCounted

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

const BUILDING_ID_PALACE: String = "palace"

static func empty() -> Dictionary:
	return {"food": 0, "production": 0, "science": 0, "coin": 0}


static func get_yield(y: Dictionary, id: String) -> int:
	if y == null or typeof(y) != TYPE_DICTIONARY:
		return 0
	return int(y.get(id, 0))


static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = empty()
	out["food"] = get_yield(a, "food") + get_yield(b, "food")
	out["production"] = get_yield(a, "production") + get_yield(b, "production")
	out["science"] = get_yield(a, "science") + get_yield(b, "science")
	out["coin"] = get_yield(a, "coin") + get_yield(b, "coin")
	return out


static func raw_terrain_yield(map, coord) -> Dictionary:
	if map == null or coord == null:
		return empty()
	if not map.has(coord):
		return empty()
	var terr: int = int(map.terrain_at(coord))
	if terr == HexMapScript.Terrain.WATER:
		return empty()
	var woods: bool = map.has_woods(coord)
	if woods:
		if terr == HexMapScript.Terrain.GRASSLAND:
			return {"food": 1, "production": 1, "science": 0, "coin": 0}
		if terr == HexMapScript.Terrain.PLAINS:
			return {"food": 1, "production": 2, "science": 0, "coin": 0}
		return empty()
	var lf: int = int(map.landform_at(coord))
	var hills: bool = lf == HexMapScript.Landform.HILLS
	if terr == HexMapScript.Terrain.GRASSLAND:
		if hills:
			return {"food": 1, "production": 1, "science": 0, "coin": 0}
		return {"food": 2, "production": 0, "science": 0, "coin": 0}
	if terr == HexMapScript.Terrain.PLAINS:
		if hills:
			return {"food": 0, "production": 2, "science": 0, "coin": 0}
		return {"food": 1, "production": 1, "science": 0, "coin": 0}
	return empty()


static func city_center_yield(map, city) -> Dictionary:
	if city == null:
		return {"food": 2, "production": 1, "science": 0, "coin": 0}
	var raw: Dictionary = raw_terrain_yield(map, city.position)
	var f: int = maxi(get_yield(raw, "food"), 2)
	var p: int = maxi(get_yield(raw, "production"), 1)
	return {"food": f, "production": p, "science": 0, "coin": 0}


static func palace_yield() -> Dictionary:
	return {"food": 0, "production": 0, "science": 1, "coin": 1}


static func building_yield(building_id: String) -> Dictionary:
	if building_id == BUILDING_ID_PALACE:
		return palace_yield()
	return empty()


static func _raw_yield_nonzero(raw: Dictionary) -> bool:
	return (
		get_yield(raw, "food") != 0
		or get_yield(raw, "production") != 0
		or get_yield(raw, "science") != 0
		or get_yield(raw, "coin") != 0
	)


static func _worked_tile_precedes(map, a, b) -> bool:
	var ra: Dictionary = raw_terrain_yield(map, a)
	var rb: Dictionary = raw_terrain_yield(map, b)
	var fa: int = get_yield(ra, "food")
	var pa: int = get_yield(ra, "production")
	var fb: int = get_yield(rb, "food")
	var pb: int = get_yield(rb, "production")
	var sa: int = fa + pa
	var sb: int = fb + pb
	if sa != sb:
		return sa > sb
	if fa != fb:
		return fa > fb
	if pa != pb:
		return pa > pb
	if a.q != b.q:
		return a.q < b.q
	return a.r < b.r


static func worked_tiles_for_city(p_scenario, city) -> Array:
	var out: Array = []
	if p_scenario == null or city == null:
		return out
	var cmap = p_scenario.map
	if cmap == null:
		return out
	var lim: int = int(city.population)
	if lim <= 0:
		return out
	var candidates: Array = []
	var ei: int = 0
	while ei < city.owned_tiles.size():
		var h = city.owned_tiles[ei]
		ei += 1
		if h == null:
			continue
		if h.q == city.position.q and h.r == city.position.r:
			continue
		var rw: Dictionary = raw_terrain_yield(cmap, h)
		if not _raw_yield_nonzero(rw):
			continue
		candidates.append(h)
	if candidates.is_empty():
		return out
	candidates.sort_custom(func(a, b): return _worked_tile_precedes(cmap, a, b))
	var take: int = mini(lim, candidates.size())
	var ti: int = 0
	while ti < take:
		var ch = candidates[ti]
		out.append(HexCoordScript.new(ch.q, ch.r))
		ti += 1
	return out


static func worked_tiles_yield(p_scenario, city) -> Dictionary:
	var acc: Dictionary = empty()
	var wt: Array = worked_tiles_for_city(p_scenario, city)
	var wi: int = 0
	while wi < wt.size():
		var hx = wt[wi]
		wi += 1
		acc = add(acc, raw_terrain_yield(p_scenario.map, hx))
	return acc


static func city_total_yield(p_scenario, city) -> Dictionary:
	if p_scenario == null or city == null:
		return empty()
	var out: Dictionary = city_center_yield(p_scenario.map, city)
	var j: int = 0
	while j < city.building_ids.size():
		out = add(out, building_yield(str(city.building_ids[j])))
		j = j + 1
	out = add(out, worked_tiles_yield(p_scenario, city))
	return out


# Phase 5.1.17d — decomposition of **city_total_yield** for visibility/tests; pure read-only compose of existing helpers.
static func yield_breakdown_for_city(p_scenario, city) -> Dictionary:
	if p_scenario == null or city == null:
		return {
			"center": empty(),
			"buildings": empty(),
			"worked": empty(),
			"worked_tiles": [],
			"total": empty(),
		}
	var cen: Dictionary = city_center_yield(p_scenario.map, city)
	var bsum: Dictionary = empty()
	var j: int = 0
	while j < city.building_ids.size():
		bsum = add(bsum, building_yield(str(city.building_ids[j])))
		j = j + 1
	var wked: Dictionary = worked_tiles_yield(p_scenario, city)
	var wt_src: Array = worked_tiles_for_city(p_scenario, city)
	var wt_out: Array = []
	var wi: int = 0
	while wi < wt_src.size():
		var hx = wt_src[wi]
		wi += 1
		if hx != null:
			wt_out.append(HexCoordScript.new(hx.q, hx.r))
	var tot: Dictionary = add(add(cen, bsum), wked)
	var out: Dictionary = {
		"center": cen.duplicate(true),
		"buildings": bsum.duplicate(true),
		"worked": wked.duplicate(true),
		"worked_tiles": wt_out,
		"total": tot.duplicate(true),
	}
	return out


static func science_for_player(p_scenario, owner_id: int) -> int:
	if p_scenario == null:
		return 0
	var total: int = 0
	var clist: Array = p_scenario.cities_owned_by(owner_id)
	var i: int = 0
	while i < clist.size():
		total += get_yield(city_total_yield(p_scenario, clist[i]), "science")
		i = i + 1
	return total
