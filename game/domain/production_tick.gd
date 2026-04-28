# Engine-only production progress when a player ends their turn. Not a player action; invoked from GameState end_turn only.
# See docs/ACTIONS.md, docs/CITIES.md, docs/TURNS.md
class_name ProductionTick
extends RefCounted

const SCHEMA_VERSION: int = 1
const EVENT_TYPE: String = "production_progress"
const PRODUCTION_PER_TURN: int = 1

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")

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


static func apply_for_player(a_scenario, owner_id: int) -> Dictionary:
	var clist = a_scenario.cities()
	var ids_to_tick: Array = []
	var hi = 0
	while hi < clist.size():
		var hc = clist[hi]
		if hc.owner_id == owner_id and hc.current_project != null:
			ids_to_tick.append(hc.id)
		hi = hi + 1
	_sort_int_ids_asc(ids_to_tick)
	if ids_to_tick.size() == 0:
		return {"scenario": a_scenario, "events": []}

	var events: Array = []
	var ei = 0
	while ei < ids_to_tick.size():
		var cid = ids_to_tick[ei] as int
		var c = a_scenario.city_by_id(cid)
		var proj_src = c.current_project as Dictionary
		var proj_for_event = proj_src.duplicate(true)
		var old_progress = int(proj_for_event["progress"])
		var new_progress = old_progress + PRODUCTION_PER_TURN
		var cost_v = int(proj_for_event["cost"])
		var ptype = proj_for_event["project_type"]
		var ptype_str = str(ptype)
		var ev: Dictionary = {}
		ev["schema_version"] = SCHEMA_VERSION
		ev["action_type"] = EVENT_TYPE
		ev["actor_id"] = owner_id
		ev["city_id"] = cid
		ev["project_type"] = ptype_str
		ev["progress_before"] = old_progress
		ev["progress_after"] = new_progress
		ev["cost"] = cost_v
		ev["source"] = "engine"
		ev["result"] = "accepted"
		events.append(ev)
		ei = ei + 1

	var new_cities: Array = []
	var ci = 0
	while ci < clist.size():
		var c2 = clist[ci]
		if c2.owner_id == owner_id and c2.current_project != null:
			var proj_new = (c2.current_project as Dictionary).duplicate(true)
			var op = int(proj_new["progress"])
			proj_new["progress"] = op + PRODUCTION_PER_TURN
			new_cities.append(CityScript.new(c2.id, c2.owner_id, c2.position, proj_new))
		else:
			new_cities.append(c2)
		ci = ci + 1

	var new_scenario = ScenarioScript.new(
		a_scenario.map,
		a_scenario.units(),
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id()
	)
	return {"scenario": new_scenario, "events": events}
