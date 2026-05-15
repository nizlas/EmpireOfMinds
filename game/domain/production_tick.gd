# Engine-only production progress when a player ends their turn. Marks produce_unit ready; does not spawn units.
# See docs/ACTIONS.md, docs/CITIES.md, docs/TURNS.md
class_name ProductionTick
extends RefCounted

const SCHEMA_VERSION: int = 1
const EVENT_TYPE: String = "production_progress"
## Deprecated (Phase 5.1.16d): production per turn was a fixed **1**; use **CityYields** via **`_production_per_turn`**.
const PRODUCE_UNIT_TYPE: String = "produce_unit"

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

static func _sort_int_ids_asc(ids: Array) -> void:
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


static func _eligible_for_tick(city, owner_id: int) -> bool:
	if city.owner_id != owner_id:
		return false
	if city.current_project == null:
		return false
	if typeof(city.current_project) != TYPE_DICTIONARY:
		return false
	var pd = city.current_project as Dictionary
	if bool(pd.get("ready", false)):
		return false
	return true


static func _production_per_turn(a_scenario, city) -> int:
	if a_scenario == null or city == null:
		return 0
	var y: Dictionary = CityYieldsScript.city_total_yield(a_scenario, city)
	var p: int = CityYieldsScript.get_yield(y, "production")
	if p <= 0:
		return 0
	return p


static func apply_for_player(a_scenario, owner_id: int) -> Dictionary:
	var clist = a_scenario.cities()
	var ids_to_tick: Array = []
	var hi = 0
	while hi < clist.size():
		var hc = clist[hi]
		if _eligible_for_tick(hc, owner_id) and _production_per_turn(a_scenario, hc) > 0:
			ids_to_tick.append(hc.id)
		hi = hi + 1
	_sort_int_ids_asc(ids_to_tick)
	if ids_to_tick.size() == 0:
		return {"scenario": a_scenario, "events": []}

	var events: Array = []
	var new_project_by_id: Dictionary = {}
	var ei = 0
	while ei < ids_to_tick.size():
		var cid = ids_to_tick[ei] as int
		var c = a_scenario.city_by_id(cid)
		var proj_src = c.current_project as Dictionary
		var project = proj_src.duplicate(true)
		var old_progress = int(project["progress"])
		var delta_p: int = _production_per_turn(a_scenario, c)
		var new_progress = old_progress + delta_p
		project["progress"] = new_progress
		var cost_v = int(project["cost"])
		var ptype_str = str(project["project_type"])
		if ptype_str == PRODUCE_UNIT_TYPE and new_progress >= cost_v:
			project["ready"] = true
		else:
			project["ready"] = false
		new_project_by_id[cid] = project
		var ev_prog: Dictionary = {}
		ev_prog["schema_version"] = SCHEMA_VERSION
		ev_prog["action_type"] = EVENT_TYPE
		ev_prog["actor_id"] = owner_id
		ev_prog["city_id"] = cid
		ev_prog["project_type"] = ptype_str
		ev_prog["progress_before"] = old_progress
		ev_prog["progress_after"] = new_progress
		ev_prog["cost"] = cost_v
		ev_prog["source"] = "engine"
		ev_prog["result"] = "accepted"
		if proj_src.has("project_id"):
			ev_prog["project_id"] = str(proj_src["project_id"])
		events.append(ev_prog)
		ei = ei + 1

	var new_cities: Array = []
	var ci = 0
	while ci < clist.size():
		var c2 = clist[ci]
		if new_project_by_id.has(c2.id):
			var pr = new_project_by_id[c2.id] as Dictionary
			new_cities.append(
				CityScript.new(
					c2.id,
					c2.owner_id,
					c2.position,
					pr,
					c2.city_name,
					c2.is_capital,
					c2.building_ids,
					c2.owned_tiles,
					c2.population,
					c2.manual_worked_tiles
				)
			)
		else:
			new_cities.append(c2)
		ci = ci + 1

	var new_scenario = ScenarioScript.new(
		a_scenario.map,
		a_scenario.units(),
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id(),
		a_scenario.lightning_tree_hex,
	)
	return {"scenario": new_scenario, "events": events}
