# Headless: godot --headless --path game -s res://domain/tests/test_attack_unit_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const AttackUnitScript = preload("res://domain/actions/attack_unit.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")

var _total = 0
var _any_fail = false


func _make_state_two_warriors() -> Variant:
	var m = HexMapScript.make_tiny_test_map()
	var w0 = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior")
	var w1 = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior")
	var sc = ScenarioScript.new(m, [w0, w1])
	return GameStateScript.new(sc)


func _init() -> void:
	var gs = _make_state_two_warriors()
	var act = AttackUnitScript.make(0, 10, 11)
	var r_ok = gs.try_apply(act)
	_check(bool(r_ok["accepted"]), "accepted legal attack")
	var ent = gs.log.get_entry(int(r_ok["index"]))
	_check(int(ent["defender_damage_taken"]) == 30, "log defender_damage")
	_check(int(ent["attacker_damage_taken"]) == 30, "log attacker_damage")
	_check(bool(ent["retaliated"]), "log retaliated")
	var ua = gs.scenario.unit_by_id(10)
	_check(ua.remaining_movement == 0, "attacker mp consumed")
	var r2 = gs.try_apply(AttackUnitScript.make(0, 10, 11))
	_check(not r2["accepted"] and r2["reason"] == "movement_exhausted", "second attack rejected")

	var gs3 = _make_state_two_warriors()
	var w0l = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior", 2, -1)
	var w1l = UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior", 2, 20)
	var sc3 = ScenarioScript.new(HexMapScript.make_tiny_test_map(), [w0l, w1l])
	var gs_lethal = GameStateScript.new(sc3)
	var r_lethal = gs_lethal.try_apply(AttackUnitScript.make(0, 10, 11))
	_check(bool(r_lethal["accepted"]), "lethal accepted")
	_check(gs_lethal.scenario.unit_by_id(11) == null, "defender removed")
	var ent2 = gs_lethal.log.get_entry(int(r_lethal["index"]))
	_check(int(ent2["attacker_damage_taken"]) == 0, "no retal dmg logged")

	var gs_np = _make_state_two_warriors()
	var r_np = gs_np.try_apply(AttackUnitScript.make(1, 10, 11))
	_check(not r_np["accepted"] and r_np["reason"] == "not_current_player", "wrong player")

	var gs_mal = _make_state_two_warriors()
	var r_mal = gs_mal.try_apply(
		{"schema_version": 1, "action_type": AttackUnitScript.ACTION_TYPE, "actor_id": 0}
	)
	_check(not r_mal["accepted"] and r_mal["reason"] == "malformed_action", "malformed")

	var gs_unk = _make_state_two_warriors()
	var r_unk = gs_unk.try_apply(
		{
			"schema_version": 1,
			"action_type": "attack_unit_typo",
			"actor_id": 0,
			"attacker_id": 10,
			"defender_id": 11,
		}
	)
	_check(not r_unk["accepted"] and r_unk["reason"] == "unknown_action_type", "unknown action")

	var m_mv = HexMapScript.make_tiny_test_map()
	var w_mv = UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior", 2, 55)
	var sc_mv = ScenarioScript.new(m_mv, [w_mv])
	var gs_mv = GameStateScript.new(sc_mv)
	var mv = MoveUnitScript.make(0, 10, 0, 0, 1, -1)
	var r_mv = gs_mv.try_apply(mv)
	_check(bool(r_mv["accepted"]), "move accepted")
	var um = gs_mv.scenario.unit_by_id(10)
	_check(um.current_hp == 55, "wounded hp preserved on move")

	var gs_et = GameStateScript.new(
		ScenarioScript.new(
			HexMapScript.make_tiny_test_map(),
			[
				UnitScript.new(10, 0, HexCoordScript.new(0, 0), "warrior", 2, 44),
				UnitScript.new(11, 1, HexCoordScript.new(1, 0), "warrior"),
			],
		)
	)
	var r_e0 = gs_et.try_apply(EndTurnScript.make(0))
	_check(bool(r_e0["accepted"]), "end turn p0")
	var r_e1 = gs_et.try_apply(EndTurnScript.make(1))
	_check(bool(r_e1["accepted"]), "end turn p1")
	var w_back = gs_et.scenario.unit_by_id(10)
	_check(w_back.current_hp == 44, "hp preserved after turn cycle mp refresh")

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
