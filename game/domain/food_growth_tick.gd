# Per-turn food surplus → **food_stored** → population growth embryo (Phase 5.1.19b). Domain-only.
# See docs/CITIES.md
class_name FoodGrowthTick
extends RefCounted

const SCHEMA_VERSION: int = 1
const EVENT_TYPE_PROGRESS: String = "food_growth_progress"
const EVENT_TYPE_GREW: String = "city_grew"

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


static func growth_threshold(pop: int) -> int:
	var p: int = maxi(1, int(pop))
	var j: int = p - 1
	return 15 + j * 8 + int(floor(pow(float(j), 1.5)))


static func apply_for_player(a_scenario, owner_id: int) -> Dictionary:
	if a_scenario == null:
		return {"scenario": a_scenario, "events": []}
	var owned: Array = a_scenario.cities_owned_by(owner_id)
	if owned.is_empty():
		return {"scenario": a_scenario, "events": []}
	var ids: Array = []
	var oi: int = 0
	while oi < owned.size():
		var oc = owned[oi]
		if oc != null:
			ids.append(oc.id)
		oi += 1
	_sort_int_ids_asc(ids)
	var updates: Dictionary = {}
	var events: Array = []
	var ii: int = 0
	while ii < ids.size():
		var cid: int = ids[ii] as int
		var city = a_scenario.city_by_id(cid)
		if city == null:
			ii += 1
			continue
		var y: Dictionary = CityYieldsScript.city_total_yield(a_scenario, city)
		var total_food: int = int(y.get("food", 0))
		var consumption: int = city.population * 2
		var surplus: int = total_food - consumption
		if surplus <= 0:
			ii += 1
			continue
		var old_pop: int = city.population
		var old_stored: int = city.food_stored
		var threshold: int = growth_threshold(old_pop)
		var new_stored: int = old_stored + surplus
		var new_pop: int = old_pop
		if new_stored >= threshold:
			new_pop = old_pop + 1
			new_stored -= threshold
		var prog: Dictionary = {}
		prog["schema_version"] = SCHEMA_VERSION
		prog["action_type"] = EVENT_TYPE_PROGRESS
		prog["source"] = "engine"
		prog["result"] = "accepted"
		prog["actor_id"] = owner_id
		prog["city_id"] = cid
		prog["food_stored_before"] = old_stored
		prog["food_stored_after"] = new_stored
		prog["population_before"] = old_pop
		prog["population_after"] = new_pop
		prog["total_food"] = total_food
		prog["consumption"] = consumption
		prog["surplus"] = surplus
		prog["growth_threshold"] = threshold
		events.append(prog)
		if new_pop > old_pop:
			var grew: Dictionary = {}
			grew["schema_version"] = SCHEMA_VERSION
			grew["action_type"] = EVENT_TYPE_GREW
			grew["source"] = "engine"
			grew["result"] = "accepted"
			grew["actor_id"] = owner_id
			grew["city_id"] = cid
			grew["population_before"] = old_pop
			grew["population_after"] = new_pop
			grew["food_stored_after"] = new_stored
			events.append(grew)
		updates[cid] = {"population": new_pop, "food_stored": new_stored}
		ii += 1
	if updates.is_empty():
		return {"scenario": a_scenario, "events": []}
	var clist: Array = a_scenario.cities()
	var new_cities: Array = []
	var ci: int = 0
	while ci < clist.size():
		var c2 = clist[ci]
		if updates.has(c2.id):
			var u: Dictionary = updates[c2.id] as Dictionary
			new_cities.append(
				CityScript.new(
					c2.id,
					c2.owner_id,
					c2.position,
					c2.current_project,
					c2.city_name,
					c2.is_capital,
					c2.building_ids,
					c2.owned_tiles,
					u["population"] as int,
					c2.manual_worked_tiles,
					u["food_stored"] as int,
					c2.worked_tiles_mode
				)
			)
		else:
			new_cities.append(c2)
		ci += 1
	var new_scenario = ScenarioScript.new(
		a_scenario.map,
		a_scenario.units(),
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id(),
		a_scenario.lightning_tree_hex,
	)
	return {"scenario": new_scenario, "events": events}
