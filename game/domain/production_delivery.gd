# Engine-only delivery of ready city production when a player becomes current. Not a player action.
# See docs/ACTIONS.md, docs/CITIES.md, docs/TURNS.md
class_name ProductionDelivery
extends RefCounted

const SCHEMA_VERSION: int = 1
const EVENT_TYPE: String = "unit_produced"
const PRODUCE_UNIT_TYPE: String = "produce_unit"

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const UnitScript = preload("res://domain/unit.gd")

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


static func deliver_pending_for_player(a_scenario, owner_id: int) -> Dictionary:
	if a_scenario == null:
		return {"scenario": a_scenario, "events": []}
	var clist = a_scenario.cities()
	var ready_ids: Array = []
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
		if str(pd.get("project_type", "")) != PRODUCE_UNIT_TYPE:
			ri = ri + 1
			continue
		ready_ids.append(c.id)
		ri = ri + 1
	_sort_int_ids_asc(ready_ids)
	if ready_ids.size() == 0:
		return {"scenario": a_scenario, "events": []}

	var delivered: Dictionary = {}
	var ev_i = 0
	while ev_i < ready_ids.size():
		delivered[ready_ids[ev_i] as int] = true
		ev_i = ev_i + 1

	var events: Array = []
	var running_next_unit_id = a_scenario.peek_next_unit_id()
	var completion_order: Array = []
	var ci0 = 0
	while ci0 < ready_ids.size():
		var rcid = ready_ids[ci0] as int
		var cty = a_scenario.city_by_id(rcid)
		var unit_id = running_next_unit_id
		running_next_unit_id = running_next_unit_id + 1
		var up_ev: Dictionary = {}
		up_ev["schema_version"] = 1
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
		new_units.append(UnitScript.new(cp["unit_id"] as int, cy.owner_id, cy.position))
		cpi = cpi + 1

	var new_cities: Array = []
	var ci = 0
	while ci < clist.size():
		var c2 = clist[ci]
		if delivered.has(c2.id):
			new_cities.append(CityScript.new(c2.id, c2.owner_id, c2.position, null))
		else:
			new_cities.append(c2)
		ci = ci + 1

	var new_scenario = ScenarioScript.new(
		a_scenario.map,
		new_units,
		new_cities,
		running_next_unit_id,
		a_scenario.peek_next_city_id()
	)
	return {"scenario": new_scenario, "events": events}
