# FoundCity action: versioned Dictionary, structural validate, apply returns new Scenario with founder removed and city appended.
# See docs/ACTIONS.md, docs/CITIES.md
class_name FoundCity
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "found_city"

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")

static func make(actor_id: int, unit_id: int, q: int, r: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"unit_id": unit_id,
		"position": [q, r],
	}

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
	if not action.has("unit_id") or typeof(action["unit_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if not action.has("position"):
		return {"ok": false, "reason": "malformed_action"}
	if typeof(action["position"]) != TYPE_ARRAY:
		return {"ok": false, "reason": "malformed_action"}
	var pos_a = action["position"] as Array
	if pos_a.size() != 2:
		return {"ok": false, "reason": "malformed_action"}
	if typeof(pos_a[0]) != TYPE_INT or typeof(pos_a[1]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	var u = a_scenario.unit_by_id(action["unit_id"])
	if u == null:
		return {"ok": false, "reason": "unknown_unit"}
	if u.owner_id != action["actor_id"]:
		return {"ok": false, "reason": "actor_not_owner"}
	var pos_c = HexCoordScript.new(pos_a[0], pos_a[1])
	if not u.position.equals(pos_c):
		return {"ok": false, "reason": "unit_not_at_position"}
	if not a_scenario.map.has(pos_c):
		return {"ok": false, "reason": "tile_not_on_map"}
	if a_scenario.map.terrain_at(pos_c) == HexMapScript.Terrain.WATER:
		return {"ok": false, "reason": "tile_is_water"}
	if a_scenario.cities_at(pos_c).size() > 0:
		return {"ok": false, "reason": "tile_already_has_city"}
	return {"ok": true, "reason": ""}

static func apply(a_scenario, action):
	var vr = validate(a_scenario, action)
	assert(vr["ok"], "FoundCity.apply called with invalid action")
	var pos_a = action["position"] as Array
	var q = pos_a[0] as int
	var r = pos_a[1] as int
	var new_city_id = a_scenario.peek_next_city_id()
	var new_units = []
	var ulist = a_scenario.units()
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		if u.id != action["unit_id"]:
			new_units.append(u)
		i = i + 1
	var new_cities = []
	var clist = a_scenario.cities()
	var ci = 0
	while ci < clist.size():
		new_cities.append(clist[ci])
		ci = ci + 1
	new_cities.append(CityScript.new(new_city_id, action["actor_id"], HexCoordScript.new(q, r)))
	return ScenarioScript.new(
		a_scenario.map,
		new_units,
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id() + 1
	)
