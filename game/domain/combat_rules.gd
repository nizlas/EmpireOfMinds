# Deterministic melee resolution (Local Combat 0.1). See docs/ACTIONS.md `AttackUnit`.
# `effective_strength` is a hook for future terrain / tactics; today it reads **`UnitDefinitions`** only.
class_name CombatRules
extends RefCounted

const BASE_DAMAGE: int = 30
const STRENGTH_DIVISOR: float = 25.0
const MIN_DAMAGE: int = 1
const MAX_DAMAGE: int = 100

const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

static func effective_strength(unit, _scenario) -> int:
	if unit == null:
		return 0
	return UnitDefinitionsScript.combat_strength_for_type(str(unit.type_id))


## Exposed for tests; **`resolve_attack`** uses the same formula.
static func damage_for_strengths(attacker_strength: int, defender_strength: int) -> int:
	var diff: int = attacker_strength - defender_strength
	var raw: float = float(BASE_DAMAGE) * exp(float(diff) / STRENGTH_DIVISOR)
	var d: int = roundi(raw)
	return clampi(d, MIN_DAMAGE, MAX_DAMAGE)


## Assumes **`AttackUnit.validate`** succeeded. Builds a CombatResult **Dictionary** (loggable primitives).
static func resolve_attack(a_scenario, action: Dictionary) -> Dictionary:
	var attacker = a_scenario.unit_by_id(int(action["attacker_id"]))
	var defender = a_scenario.unit_by_id(int(action["defender_id"]))
	var atk_str: int = effective_strength(attacker, a_scenario)
	var def_str: int = effective_strength(defender, a_scenario)
	var def_dmg: int = damage_for_strengths(atk_str, def_str)
	var def_hp_after: int = maxi(0, int(defender.current_hp) - def_dmg)
	var atk_dmg: int = 0
	var atk_hp_after: int = int(attacker.current_hp)
	var retaliated: bool = false
	if def_hp_after > 0:
		atk_dmg = damage_for_strengths(def_str, atk_str)
		atk_hp_after = maxi(0, int(attacker.current_hp) - atk_dmg)
		retaliated = true
	var defender_killed: bool = def_hp_after <= 0
	var attacker_killed: bool = atk_hp_after <= 0
	return {
		"attacker_id": int(attacker.id),
		"defender_id": int(defender.id),
		"attacker_strength": atk_str,
		"defender_strength": def_str,
		"attacker_damage_taken": int(attacker.current_hp) - atk_hp_after,
		"defender_damage_taken": int(defender.current_hp) - def_hp_after,
		"attacker_hp_before": int(attacker.current_hp),
		"defender_hp_before": int(defender.current_hp),
		"attacker_hp_after": atk_hp_after,
		"defender_hp_after": def_hp_after,
		"attacker_killed": attacker_killed,
		"defender_killed": defender_killed,
		"retaliated": retaliated,
	}
