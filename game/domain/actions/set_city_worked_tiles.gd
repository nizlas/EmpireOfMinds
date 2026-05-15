# SetCityWorkedTiles: manual worked-tile mode (**manual** idle vs placed); **`[]`** = all citizens idle on worked layer (still **manual** mode).
# See docs/ACTIONS.md, docs/CITIES.md
class_name SetCityWorkedTiles
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "set_city_worked_tiles"

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

static func make(actor_id: int, city_id: int, tiles: Array) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"city_id": city_id,
		"tiles": tiles.duplicate(),
	}


static func _tiles_equal_to_city_manual(city, normalized_pairs: Array) -> bool:
	if city == null:
		return false
	var cur: Array = city.manual_worked_tiles as Array
	if cur.size() != normalized_pairs.size():
		return false
	var i: int = 0
	while i < cur.size():
		var h = cur[i]
		var pr = normalized_pairs[i] as Array
		if h == null or pr.size() != 2:
			return false
		if int(h.q) != int(pr[0]) or int(h.r) != int(pr[1]):
			return false
		i += 1
	return true


static func _city_owns_tile(city, q: int, r: int) -> bool:
	if city == null:
		return false
	var j: int = 0
	while j < city.owned_tiles.size():
		var h = city.owned_tiles[j]
		if h != null and int(h.q) == q and int(h.r) == r:
			return true
		j += 1
	return false


static func validate(a_scenario, action) -> Dictionary:
	if a_scenario == null:
		return {"ok": false, "reason": "scenario_null"}
	if action == null:
		return {"ok": false, "reason": "wrong_action_type"}
	if typeof(action) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "wrong_action_type"}
	if not action.has("action_type"):
		return {"ok": false, "reason": "wrong_action_type"}
	if action["action_type"] != ACTION_TYPE:
		return {"ok": false, "reason": "wrong_action_type"}
	if not action.has("schema_version"):
		return {"ok": false, "reason": "unsupported_schema_version"}
	if action["schema_version"] != SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_schema_version"}
	if not action.has("actor_id") or typeof(action["actor_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if not action.has("city_id") or typeof(action["city_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if not action.has("tiles") or typeof(action["tiles"]) != TYPE_ARRAY:
		return {"ok": false, "reason": "malformed_action"}

	var target = a_scenario.city_by_id(action["city_id"])
	if target == null:
		return {"ok": false, "reason": "unknown_city"}
	if target.owner_id != action["actor_id"]:
		return {"ok": false, "reason": "actor_not_owner"}

	var tiles_a: Array = action["tiles"] as Array
	var pop: int = int(target.population)
	if tiles_a.size() > pop:
		return {"ok": false, "reason": "too_many_tiles"}

	var seen_payload: Dictionary = {}
	var normalized: Array = []
	var ti: int = 0
	while ti < tiles_a.size():
		var ent = tiles_a[ti]
		ti += 1
		if typeof(ent) != TYPE_ARRAY:
			return {"ok": false, "reason": "malformed_action"}
		var pair = ent as Array
		if pair.size() != 2:
			return {"ok": false, "reason": "malformed_action"}
		if typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return {"ok": false, "reason": "malformed_action"}
		var tq: int = pair[0] as int
		var tr: int = pair[1] as int
		var pk := Vector2i(tq, tr)
		if seen_payload.has(pk):
			return {"ok": false, "reason": "duplicate_tile"}
		seen_payload[pk] = true
		if tq == target.position.q and tr == target.position.r:
			return {"ok": false, "reason": "tile_is_center"}
		if not _city_owns_tile(target, tq, tr):
			return {"ok": false, "reason": "tile_not_owned"}
		var ycell = HexCoordScript.new(tq, tr)
		var rw: Dictionary = CityYieldsScript.raw_terrain_yield(a_scenario.map, ycell)
		if not CityYieldsScript._raw_yield_nonzero(rw):
			return {"ok": false, "reason": "tile_zero_yield"}
		normalized.append([tq, tr])

	if str(target.worked_tiles_mode) == CityScript.WORKED_TILES_MODE_MANUAL and _tiles_equal_to_city_manual(
		target,
		normalized
	):
		return {"ok": false, "reason": "assignment_unchanged"}

	return {"ok": true, "reason": ""}


static func apply(a_scenario, action):
	var vr = validate(a_scenario, action)
	assert(vr["ok"], "SetCityWorkedTiles.apply called with invalid action")
	var target_id = action["city_id"] as int
	var tiles_a: Array = action["tiles"] as Array
	var built: Array = []
	var bi: int = 0
	while bi < tiles_a.size():
		var ent = tiles_a[bi] as Array
		built.append(HexCoordScript.new(int(ent[0]), int(ent[1])))
		bi += 1

	var new_cities: Array = []
	var clist = a_scenario.cities()
	var ci: int = 0
	while ci < clist.size():
		var c = clist[ci]
		if c.id == target_id:
			new_cities.append(
				CityScript.new(
					c.id,
					c.owner_id,
					c.position,
					c.current_project,
					c.city_name,
					c.is_capital,
					c.building_ids,
					c.owned_tiles,
					c.population,
					built,
					c.food_stored,
					CityScript.WORKED_TILES_MODE_MANUAL
				)
			)
		else:
			new_cities.append(c)
		ci += 1
	return ScenarioScript.new(
		a_scenario.map,
		a_scenario.units(),
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id(),
		a_scenario.lightning_tree_hex,
	)
