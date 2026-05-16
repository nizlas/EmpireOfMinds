# AttackUnit action: adjacent Warrior vs Warrior melee (Local Combat 0.1). See docs/ACTIONS.md.
# Apply path: **`GameState`** calls **`CombatRules.resolve_attack`** once, then **`apply_with_result`**.
class_name AttackUnit
extends RefCounted

const SCHEMA_VERSION: int = 1
const ACTION_TYPE: String = "attack_unit"
const WARRIOR_TYPE: String = "warrior"

const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")

static func make(actor_id: int, attacker_id: int, defender_id: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"action_type": ACTION_TYPE,
		"actor_id": actor_id,
		"attacker_id": attacker_id,
		"defender_id": defender_id,
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
	if (
		not action.has("actor_id")
		or not action.has("attacker_id")
		or not action.has("defender_id")
	):
		return {"ok": false, "reason": "malformed_action"}
	if (
		typeof(action["actor_id"]) != TYPE_INT
		or typeof(action["attacker_id"]) != TYPE_INT
		or typeof(action["defender_id"]) != TYPE_INT
	):
		return {"ok": false, "reason": "malformed_action"}
	var attacker = a_scenario.unit_by_id(action["attacker_id"])
	if attacker == null:
		return {"ok": false, "reason": "unknown_attacker"}
	var defender = a_scenario.unit_by_id(action["defender_id"])
	if defender == null:
		return {"ok": false, "reason": "unknown_defender"}
	if attacker.owner_id != action["actor_id"]:
		return {"ok": false, "reason": "actor_not_owner"}
	if str(attacker.type_id) != WARRIOR_TYPE:
		return {"ok": false, "reason": "attacker_not_warrior"}
	if str(defender.type_id) != WARRIOR_TYPE:
		return {"ok": false, "reason": "defender_not_warrior"}
	if attacker.owner_id == defender.owner_id:
		return {"ok": false, "reason": "cannot_attack_own_unit"}
	if HexCoordScript.axial_distance(attacker.position, defender.position) != 1:
		return {"ok": false, "reason": "defender_not_adjacent"}
	if attacker.remaining_movement < 1:
		return {"ok": false, "reason": "movement_exhausted"}
	return {"ok": true, "reason": ""}


static func apply_with_result(a_scenario, action: Dictionary, combat_result: Dictionary):
	var vr = validate(a_scenario, action)
	assert(vr["ok"], "AttackUnit.apply_with_result called with invalid action")
	var attacker_id: int = int(action["attacker_id"])
	var defender_id: int = int(action["defender_id"])
	var atk_killed: bool = bool(combat_result["attacker_killed"])
	var def_killed: bool = bool(combat_result["defender_killed"])
	var atk_hp_after: int = int(combat_result["attacker_hp_after"])
	var def_hp_after: int = int(combat_result["defender_hp_after"])
	var new_units: Array = []
	var ulist = a_scenario.units()
	var i: int = 0
	while i < ulist.size():
		var u = ulist[i]
		if atk_killed and u.id == attacker_id:
			i = i + 1
			continue
		if def_killed and u.id == defender_id:
			i = i + 1
			continue
		if not atk_killed and u.id == attacker_id:
			new_units.append(
				UnitScript.new(
					u.id,
					u.owner_id,
					u.position,
					u.type_id,
					0,
					atk_hp_after,
				)
			)
			i = i + 1
			continue
		if not def_killed and u.id == defender_id:
			new_units.append(
				UnitScript.new(
					u.id,
					u.owner_id,
					u.position,
					u.type_id,
					u.remaining_movement,
					def_hp_after,
				)
			)
			i = i + 1
			continue
		new_units.append(u)
		i = i + 1
	return ScenarioScript.new(
		a_scenario.map,
		new_units,
		a_scenario.cities(),
		a_scenario.peek_next_unit_id(),
		a_scenario.peek_next_city_id(),
		a_scenario.lightning_tree_hex,
	)
