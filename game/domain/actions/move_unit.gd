# MoveUnit action: build Dictionary, validate against Scenario + MovementRules, apply as new immutable Scenario.
# See docs/ACTIONS.md
class_name MoveUnit
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "move_unit"

const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")

static func make(actor_id: int, unit_id: int, from_q: int, from_r: int, to_q: int, to_r: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"unit_id": unit_id,
		"from": [from_q, from_r],
		"to": [to_q, to_r],
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
	if not action.has("actor_id") or not action.has("unit_id") or not action.has("from") or not action.has("to"):
		return {"ok": false, "reason": "malformed_action"}
	if typeof(action["actor_id"]) != TYPE_INT or typeof(action["unit_id"]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if typeof(action["from"]) != TYPE_ARRAY or typeof(action["to"]) != TYPE_ARRAY:
		return {"ok": false, "reason": "malformed_action"}
	var from_a = action["from"] as Array
	var to_a = action["to"] as Array
	if from_a.size() != 2 or to_a.size() != 2:
		return {"ok": false, "reason": "malformed_action"}
	if typeof(from_a[0]) != TYPE_INT or typeof(from_a[1]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	if typeof(to_a[0]) != TYPE_INT or typeof(to_a[1]) != TYPE_INT:
		return {"ok": false, "reason": "malformed_action"}
	var u = a_scenario.unit_by_id(action["unit_id"])
	if u == null:
		return {"ok": false, "reason": "unknown_unit"}
	if u.owner_id != action["actor_id"]:
		return {"ok": false, "reason": "actor_not_owner"}
	var from_c = HexCoordScript.new(from_a[0], from_a[1])
	if not u.position.equals(from_c):
		return {"ok": false, "reason": "from_does_not_match_unit_position"}
	var to_c = HexCoordScript.new(to_a[0], to_a[1])
	var legals = MovementRulesScript.legal_destinations(a_scenario, action["unit_id"])
	var dest_ok = false
	var li = 0
	while li < legals.size():
		if legals[li].equals(to_c):
			dest_ok = true
			break
		li = li + 1
	if not dest_ok:
		return {"ok": false, "reason": "destination_not_legal"}
	return {"ok": true, "reason": ""}

static func apply(a_scenario, action):
	var vr = validate(a_scenario, action)
	assert(vr["ok"], "MoveUnit.apply called with invalid action")
	var to_a = action["to"] as Array
	var new_units = []
	var i = 0
	var ulist = a_scenario.units()
	while i < ulist.size():
		var u = ulist[i]
		if u.id == action["unit_id"]:
			new_units.append(
				UnitScript.new(
					u.id,
					u.owner_id,
					HexCoordScript.new(to_a[0] as int, to_a[1] as int)
				)
			)
		else:
			new_units.append(u)
		i = i + 1
	return ScenarioScript.new(a_scenario.map, new_units)
