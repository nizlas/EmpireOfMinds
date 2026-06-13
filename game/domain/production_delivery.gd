# Engine-only delivery of ready city production when a player becomes current. Not a player action.
# See docs/ACTIONS.md, docs/CITIES.md, docs/TURNS.md
class_name ProductionDelivery
extends RefCounted

const SCHEMA_VERSION: int = 1
const EVENT_TYPE: String = "unit_produced"
const EVENT_TYPE_BUILDING_COMPLETED: String = "building_completed"
const PRODUCE_UNIT_TYPE: String = "produce_unit"
const BUILD_BUILDING_TYPE: String = "build_building"

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")

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


static func _append_building_id_sorted(building_ids: Array, building_id: String) -> Array:
	var out: Array = []
	var i: int = 0
	while i < building_ids.size():
		out.append(str(building_ids[i]))
		i = i + 1
	if building_id == "" or out.has(building_id):
		return out
	out.append(building_id)
	var a: int = 0
	while a < out.size():
		var b: int = a + 1
		while b < out.size():
			if str(out[a]) > str(out[b]):
				var tmp = out[a]
				out[a] = out[b]
				out[b] = tmp
			b = b + 1
		a = a + 1
	return out


static func deliver_pending_for_player(a_scenario, owner_id: int) -> Dictionary:
	if a_scenario == null:
		return {"scenario": a_scenario, "events": []}
	var clist = a_scenario.cities()
	var ready_unit_ids: Array = []
	var ready_build_ids: Array = []
	var ri = 0
	while ri < clist.size():
		var c = clist[ri]
		if c.owner_id != owner_id or c.current_project == null:
			ri = ri + 1
			continue
		if typeof(c.current_project) != TYPE_DICTIONARY:
			ri = ri + 1
			continue
		var pd = c.current_project as Dictionary
		if not bool(pd.get("ready", false)):
			ri = ri + 1
			continue
		var ptype = str(pd.get("project_type", ""))
		if ptype == PRODUCE_UNIT_TYPE:
			ready_unit_ids.append(c.id)
		elif ptype == BUILD_BUILDING_TYPE:
			ready_build_ids.append(c.id)
		ri = ri + 1
	_sort_int_ids_asc(ready_unit_ids)
	_sort_int_ids_asc(ready_build_ids)
	if ready_unit_ids.size() == 0 and ready_build_ids.size() == 0:
		return {"scenario": a_scenario, "events": []}

	var delivered: Dictionary = {}
	var building_delivered: Dictionary = {}
	var events: Array = []
	var running_next_unit_id = a_scenario.peek_next_unit_id()

	var bi = 0
	while bi < ready_build_ids.size():
		var bcid = ready_build_ids[bi] as int
		delivered[bcid] = true
		var bcy = a_scenario.city_by_id(bcid)
		var building_id = "hearth"
		if bcy.current_project != null and typeof(bcy.current_project) == TYPE_DICTIONARY:
			var bcp = bcy.current_project as Dictionary
			if bcp.has("project_id"):
				var bpid = str(bcp["project_id"])
				if bpid != "" and CityProjectDefinitionsScript.has(bpid):
					var reg_bid = CityProjectDefinitionsScript.produces_building_id(bpid)
					if reg_bid != "":
						building_id = reg_bid
		var b_ev: Dictionary = {}
		b_ev["schema_version"] = SCHEMA_VERSION
		b_ev["action_type"] = EVENT_TYPE_BUILDING_COMPLETED
		b_ev["actor_id"] = owner_id
		b_ev["city_id"] = bcid
		b_ev["building_id"] = building_id
		b_ev["project_type"] = BUILD_BUILDING_TYPE
		b_ev["source"] = "engine"
		b_ev["result"] = "accepted"
		if bcy.current_project != null and typeof(bcy.current_project) == TYPE_DICTIONARY:
			var bcp2 = bcy.current_project as Dictionary
			if bcp2.has("project_id"):
				b_ev["project_id"] = str(bcp2["project_id"])
		events.append(b_ev)
		building_delivered[bcid] = building_id
		bi = bi + 1

	var completion_order: Array = []
	var ci0 = 0
	while ci0 < ready_unit_ids.size():
		var rcid = ready_unit_ids[ci0] as int
		delivered[rcid] = true
		var cty = a_scenario.city_by_id(rcid)
		var unit_id = running_next_unit_id
		running_next_unit_id = running_next_unit_id + 1
		var up_ev: Dictionary = {}
		up_ev["schema_version"] = SCHEMA_VERSION
		up_ev["action_type"] = EVENT_TYPE
		up_ev["actor_id"] = owner_id
		up_ev["city_id"] = rcid
		up_ev["unit_id"] = unit_id
		up_ev["position"] = [cty.position.q, cty.position.r]
		up_ev["project_type"] = PRODUCE_UNIT_TYPE
		up_ev["source"] = "engine"
		up_ev["result"] = "accepted"
		events.append(up_ev)
		var rec: Dictionary = {}
		rec["city_id"] = rcid
		rec["unit_id"] = unit_id
		completion_order.append(rec)
		ci0 = ci0 + 1

	var new_units: Array = []
	var ulist = a_scenario.units()
	var ui = 0
	while ui < ulist.size():
		new_units.append(ulist[ui])
		ui = ui + 1
	var cpi = 0
	while cpi < completion_order.size():
		var cp = completion_order[cpi] as Dictionary
		var ccid = cp["city_id"] as int
		var cy = a_scenario.city_by_id(ccid)
		var produced_type = "warrior"
		if cy.current_project != null and typeof(cy.current_project) == TYPE_DICTIONARY:
			var cyp = cy.current_project as Dictionary
			if cyp.has("project_id"):
				var pid = str(cyp["project_id"])
				if pid != "" and CityProjectDefinitionsScript.has(pid):
					var t = CityProjectDefinitionsScript.produces_unit_type(pid)
					if t != "":
						produced_type = t
		new_units.append(UnitScript.new(cp["unit_id"] as int, cy.owner_id, cy.position, produced_type))
		cpi = cpi + 1

	var new_cities: Array = []
	var ci = 0
	while ci < clist.size():
		var c2 = clist[ci]
		if not delivered.has(c2.id):
			new_cities.append(c2)
			ci = ci + 1
			continue
		var new_building_ids = c2.building_ids
		if building_delivered.has(c2.id):
			new_building_ids = _append_building_id_sorted(
				c2.building_ids,
				str(building_delivered[c2.id])
			)
		new_cities.append(
			CityScript.new(
				c2.id,
				c2.owner_id,
				c2.position,
				null,
				c2.city_name,
				c2.is_capital,
				new_building_ids,
				c2.owned_tiles,
				c2.population,
				c2.manual_worked_tiles,
				c2.food_stored,
				c2.worked_tiles_mode
			)
		)
		ci = ci + 1

	var new_scenario = ScenarioScript.new(
		a_scenario.map,
		new_units,
		new_cities,
		running_next_unit_id,
		a_scenario.peek_next_city_id(),
		a_scenario.lightning_tree_hex,
	)
	return {"scenario": new_scenario, "events": events}
