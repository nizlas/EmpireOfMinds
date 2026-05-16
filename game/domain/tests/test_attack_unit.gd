# Headless: godot --headless --path game -s res://domain/tests/test_attack_unit.gd
extends SceneTree

const AttackUnitScript = preload("res://domain/actions/attack_unit.gd")
const CombatRulesScript = preload("res://domain/combat_rules.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")

var _total = 0
var _any_fail = false


func _make_adjacent_warriors() -> Variant:
	var m = HexMapScript.make_tiny_test_map()
	var w0 = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior")
	var w1 = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior")
	return ScenarioScript.new(m, [w0, w1])


func _init() -> void:
	var sc = _make_adjacent_warriors()
	var a = AttackUnitScript.make(0, 10, 11)
	var r0 = AttackUnitScript.validate(null, a)
	_check(not r0["ok"] and r0["reason"] == "scenario_null", "scenario_null")
	var r1 = AttackUnitScript.validate(sc, null)
	_check(not r1["ok"] and r1["reason"] == "wrong_action_type", "null action")
	var r2 = AttackUnitScript.validate(sc, {"action_type": "move_unit"})
	_check(not r2["ok"] and r2["reason"] == "wrong_action_type", "wrong type")
	var r3 = AttackUnitScript.validate(
		sc,
		{
			"schema_version": 99,
			"action_type": AttackUnitScript.ACTION_TYPE,
			"actor_id": 0,
			"attacker_id": 10,
			"defender_id": 11,
		}
	)
	_check(not r3["ok"] and r3["reason"] == "unsupported_schema_version", "bad schema")
	var r4 = AttackUnitScript.validate(
		sc,
		{"schema_version": 1, "action_type": AttackUnitScript.ACTION_TYPE, "actor_id": 0}
	)
	_check(not r4["ok"] and r4["reason"] == "malformed_action", "malformed missing ids")
	var r5 = AttackUnitScript.validate(sc, AttackUnitScript.make(0, 99, 11))
	_check(not r5["ok"] and r5["reason"] == "unknown_attacker", "unknown_attacker")
	var r6 = AttackUnitScript.validate(sc, AttackUnitScript.make(0, 10, 99))
	_check(not r6["ok"] and r6["reason"] == "unknown_defender", "unknown_defender")
	var r7 = AttackUnitScript.validate(sc, AttackUnitScript.make(1, 10, 11))
	_check(not r7["ok"] and r7["reason"] == "actor_not_owner", "actor_not_owner")
	var m2 = HexMapScript.make_tiny_test_map()
	var s_att = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "settler")
	var w_en = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior")
	var sc_s = ScenarioScript.new(m2, [s_att, w_en])
	var vr_s = AttackUnitScript.validate(sc_s, AttackUnitScript.make(0, 10, 11))
	_check(not vr_s["ok"] and vr_s["reason"] == "attacker_not_warrior", "attacker_not_warrior")
	var w_a = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior")
	var s_df = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "settler")
	var sc_d = ScenarioScript.new(m2, [w_a, s_df])
	var vr_d = AttackUnitScript.validate(sc_d, AttackUnitScript.make(0, 10, 11))
	_check(not vr_d["ok"] and vr_d["reason"] == "defender_not_warrior", "defender_not_warrior")
	var w_same = UnitScript.new(12, 0, HexCoordScript.new(0, -1), "warrior")
	var sc_own = ScenarioScript.new(m2, [w_a, w_same])
	var vr_o = AttackUnitScript.validate(sc_own, AttackUnitScript.make(0, 10, 12))
	_check(not vr_o["ok"] and vr_o["reason"] == "cannot_attack_own_unit", "cannot_attack_own_unit")
	var w_a_far = UnitScript.new(10, 0, HexCoordScript.new(1, 0), "warrior")
	var w_far = UnitScript.new(13, 1, HexCoordScript.new(0, -1), "warrior")
	var sc_far = ScenarioScript.new(m2, [w_a_far, w_far])
	var vr_f = AttackUnitScript.validate(sc_far, AttackUnitScript.make(0, 10, 13))
	_check(not vr_f["ok"] and vr_f["reason"] == "defender_not_adjacent", "defender_not_adjacent")
	var w_ex = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior", 0, 100)
	var w_en2 = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior")
	var sc_ex = ScenarioScript.new(m2, [w_ex, w_en2])
	var vr_ex = AttackUnitScript.validate(sc_ex, AttackUnitScript.make(0, 10, 11))
	_check(not vr_ex["ok"] and vr_ex["reason"] == "movement_exhausted", "movement_exhausted")
	var ok = AttackUnitScript.validate(sc, a)
	_check(ok["ok"], "legal validate")
	var cr = CombatRulesScript.resolve_attack(sc, a)
	var new_sc = AttackUnitScript.apply_with_result(sc, a, cr)
	var ua = new_sc.unit_by_id(10)
	var ud = new_sc.unit_by_id(11)
	_check(ua != null and ud != null, "both units exist")
	_check(ua.remaining_movement == 0, "attacker mp 0")
	_check(ua.current_hp == 70 and ud.current_hp == 70, "hp after mutual 30")
	_check(ud.remaining_movement == 2, "defender mp unchanged")
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
