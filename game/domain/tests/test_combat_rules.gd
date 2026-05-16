# Headless: godot --headless --path game -s res://domain/tests/test_combat_rules.gd
extends SceneTree

const CombatRulesScript = preload("res://domain/combat_rules.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const AttackUnitScript = preload("res://domain/actions/attack_unit.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(
		CombatRulesScript.damage_for_strengths(20, 20) == 30,
		"equal strength deals 30"
	)
	_check(
		CombatRulesScript.damage_for_strengths(0, 200) == 1,
		"lower clamp vs much stronger defender"
	)
	_check(
		CombatRulesScript.damage_for_strengths(200, 0) == 100,
		"upper clamp vs much weaker defender"
	)
	var m = HexMapScript.make_tiny_test_map()
	## Adjacent warriors on tiny map: (0,0) and (1,0) are neighbors.
	var w0 = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior")
	var w1 = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior")
	var sc = ScenarioScript.new(m, [w0, w1])
	var act = AttackUnitScript.make(0, 10, 11)
	var cr = CombatRulesScript.resolve_attack(sc, act)
	_check(cr["defender_damage_taken"] == 30, "defender took 30")
	_check(cr["attacker_damage_taken"] == 30, "attacker took 30 in retaliation")
	_check(bool(cr["retaliated"]), "retaliated")
	_check(not bool(cr["defender_killed"]), "both survive at 70 hp")
	_check(not bool(cr["attacker_killed"]), "both survive")
	var w0b = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior", 2, -1)
	var w1b = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior", 2, 20)
	var sc2 = ScenarioScript.new(m, [w0b, w1b])
	var cr2 = CombatRulesScript.resolve_attack(sc2, act)
	_check(bool(cr2["defender_killed"]), "defender dies from 30 dmg on 20 hp")
	_check(not bool(cr2["retaliated"]), "no retaliation when defender dies first strike")
	_check(int(cr2["attacker_damage_taken"]) == 0, "attacker takes no dmg when no retal")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
