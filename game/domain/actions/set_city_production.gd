# SetCityProduction: versioned Dictionary, structural validate, apply replaces one City's current_project in a new Scenario.
# See docs/ACTIONS.md, docs/CITIES.md
class_name SetCityProduction
extends RefCounted

const SCHEMA_VERSION: int = 2
const ACTION_TYPE: String = "set_city_production"
const PROJECT_ID_NONE: String = "none"
const PROJECT_ID_PRODUCE_UNIT_WARRIOR: String = "produce_unit:warrior"
const PROJECT_TYPE_PRODUCE_UNIT: String = "produce_unit"
const PROJECT_TYPE_NONE: String = "none"

const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")

static func make(actor_id: int, city_id: int, project_id: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"city_id": city_id,
		"project_id": project_id,
	}


static func _city_already_has_matching_produce_project(city, requested_project_id: String) -> bool:
	if city.current_project == null:
		return false
	if typeof(city.current_project) != TYPE_DICTIONARY:
		return false
	var d = city.current_project as Dictionary
	if not d.has("project_type"):
		return false
	if d["project_type"] != PROJECT_TYPE_PRODUCE_UNIT:
		return false
	if d.has("project_id"):
		return str(d["project_id"]) == requested_project_id
	return true


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
	if not action.has("project_id") or typeof(action["project_id"]) != TYPE_STRING:
		return {"ok": false, "reason": "malformed_action"}
	var target = a_scenario.city_by_id(action["city_id"])
	if target == null:
		return {"ok": false, "reason": "unknown_city"}
	if target.owner_id != action["actor_id"]:
		return {"ok": false, "reason": "actor_not_owner"}
	var project_id = action["project_id"] as String
	if project_id != PROJECT_ID_NONE and not CityProjectDefinitionsScript.has(project_id):
		return {"ok": false, "reason": "unsupported_project_id"}
	if project_id != PROJECT_ID_NONE and _city_already_has_matching_produce_project(target, project_id):
		return {"ok": false, "reason": "project_already_set"}
	if project_id == PROJECT_ID_NONE and target.current_project == null:
		return {"ok": false, "reason": "project_already_set"}
	return {"ok": true, "reason": ""}


static func apply(a_scenario, action):
	var vr = validate(a_scenario, action)
	assert(vr["ok"], "SetCityProduction.apply called with invalid action")
	var target_id = action["city_id"] as int
	var project_id = action["project_id"] as String
	var new_project = null
	if project_id != PROJECT_ID_NONE:
		var def = CityProjectDefinitionsScript.get_definition(project_id)
		assert(def != null)
		new_project = {
			"project_type": def["project_type"],
			"project_id": project_id,
			"progress": 0,
			"cost": int(def["cost"]),
			"ready": false,
		}
	var new_cities = []
	var clist = a_scenario.cities()
	var ci = 0
	while ci < clist.size():
		var c = clist[ci]
		if c.id == target_id:
			new_cities.append(CityScript.new(c.id, c.owner_id, c.position, new_project))
		else:
			new_cities.append(c)
		ci = ci + 1
	return ScenarioScript.new(
		a_scenario.map,
		a_scenario.units(),
		new_cities,
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id()
	)
