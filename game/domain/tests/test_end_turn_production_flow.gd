# Headless: godot --headless --path game -s res://domain/tests/test_end_turn_production_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")

var _total = 0
var _any_fail = false


func _proj(p: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = 2
	return d


func _proj_ready(p: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = 2
	d["ready"] = true
	return d


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var us = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c_p0_pos = HexCoordScript.new(1, -1)
	var c_p0 = CityScript.new(1, 0, c_p0_pos, _proj(0))
	var c_p1 = CityScript.new(2, 1, HexCoordScript.new(0, -1), _proj(0))
	var scen = ScenarioScript.new(m, us, [c_p1, c_p0], 30, 40)
	var gs = GameStateScript.new(scen)

	var et0 = gs.try_apply(EndTurnScript.make(0))
	_check(et0["accepted"] and et0["index"] == 1, "end turn index et0")
	_check(gs.log.size() == 2, "progress + end_turn")
	var lg0 = gs.log.get_entry(0) as Dictionary
	var lg1 = gs.log.get_entry(1) as Dictionary
	_check(lg0["action_type"] == ProductionTickScript.EVENT_TYPE and lg0["city_id"] == 1, "first is production c1")
	_check(lg1["action_type"] == EndTurnScript.ACTION_TYPE, "second is end_turn")
	_check(gs.scenario.city_by_id(1).current_project["progress"] == 1, "p0 city ticked")
	_check(gs.scenario.city_by_id(2).current_project["progress"] == 0, "p1 city not ticked")

	var et1 = gs.try_apply(EndTurnScript.make(1))
	_check(et1["accepted"] and et1["index"] == 3, "second cycle end index")
	_check(gs.log.size() == 4, "two more entries")
	_check(gs.log.get_entry(2)["city_id"] == 2, "p1 production")
	_check(gs.log.get_entry(3)["action_type"] == EndTurnScript.ACTION_TYPE, "end_turn follows")

	var et2 = gs.try_apply(EndTurnScript.make(0))
	_check(et2["accepted"] and et2["index"] == 5, "end_turn index before delivery tail")
	_check(gs.log.size() == 6, "prog end only for p0 end")
	var lg4 = gs.log.get_entry(4) as Dictionary
	var lg5 = gs.log.get_entry(5) as Dictionary
	_check(lg4["action_type"] == ProductionTickScript.EVENT_TYPE and lg4["city_id"] == 1, "second tick production")
	_check(lg5["action_type"] == EndTurnScript.ACTION_TYPE, "end_turn after progress")
	_check(
		bool((gs.scenario.city_by_id(1).current_project as Dictionary).get("ready", false)),
		"p0 city ready pending"
	)
	_check(gs.scenario.unit_by_id(30) == null, "no unit until p1 ends")
	_check(gs.scenario.peek_next_unit_id() == 30, "peek not consumed yet")

	var et3 = gs.try_apply(EndTurnScript.make(1))
	_check(et3["accepted"] and et3["index"] == 7, "p1 end_turn index")
	_check(gs.log.size() == 9, "p1 tick end then p0 delivery")
	var lg6 = gs.log.get_entry(6) as Dictionary
	var lg7 = gs.log.get_entry(7) as Dictionary
	var lg8 = gs.log.get_entry(8) as Dictionary
	_check(lg6["action_type"] == ProductionTickScript.EVENT_TYPE and lg6["city_id"] == 2, "p1 progress")
	_check(lg7["action_type"] == EndTurnScript.ACTION_TYPE, "p1 end_turn")
	_check(lg8["action_type"] == ProductionDeliveryScript.EVENT_TYPE, "unit_produced after p1 end_turn")
	_check(lg8["unit_id"] == 30 and lg8["city_id"] == 1, "allocated unit from peek")
	_check(gs.scenario.city_by_id(1).current_project == null, "p0 city cleared after delivery")
	var u30 = gs.scenario.unit_by_id(30)
	_check(u30 != null and u30.owner_id == 0 and u30.position.equals(c_p0_pos), "unit at city hex")
	_check(gs.scenario.peek_next_unit_id() == 31, "next unit id bumped")

	var sp = gs.try_apply(SetCityProductionScript.make(0, 1, "produce_unit"))
	_check(sp["accepted"], "set production after completion")
	_check(gs.scenario.city_by_id(1).current_project != null, "new project set")
	_check(
		(gs.scenario.city_by_id(1).current_project as Dictionary)["progress"] == 0,
		"fresh project progress"
	)

	# Two completions: deliver after P1 ends with both ready
	var m1 = HexMapScript.make_tiny_test_map()
	var us1 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var ct1 = CityScript.new(1, 0, HexCoordScript.new(0, -1), _proj(1))
	var ct2 = CityScript.new(2, 0, HexCoordScript.new(1, -1), _proj(1))
	var scen2 = ScenarioScript.new(m1, us1, [ct2, ct1], 50, 60)
	var gs1 = GameStateScript.new(scen2)
	var et_a = gs1.try_apply(EndTurnScript.make(0))
	_check(et_a["accepted"] and et_a["index"] == 2, "p0 end index first batch")
	_check(gs1.log.size() == 3, "two prog one end")
	var et_b = gs1.try_apply(EndTurnScript.make(1))
	_check(et_b["accepted"] and et_b["index"] == 3, "p1 end_turn index")
	_check(gs1.log.size() == 6, "end two units")
	_check(gs1.log.get_entry(3)["action_type"] == EndTurnScript.ACTION_TYPE, "p1 end_turn")
	_check((gs1.log.get_entry(4) as Dictionary)["city_id"] == 1, "first delivered city id order")
	_check((gs1.log.get_entry(5) as Dictionary)["city_id"] == 2, "second delivery")
	_check(gs1.scenario.peek_next_unit_id() == 52, "two new units")

	# _init delivery when scenario starts with ready for current player
	var m_init = HexMapScript.make_tiny_test_map()
	var u_init = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cr = CityScript.new(1, 0, HexCoordScript.new(1, -1), _proj_ready(2))
	var sc_init = ScenarioScript.new(m_init, u_init, [cr], 200, 300)
	var gs_init = GameStateScript.new(sc_init)
	_check(gs_init.log.size() == 1, "init delivery logged")
	var le = gs_init.log.get_entry(0) as Dictionary
	_check(le["action_type"] == ProductionDeliveryScript.EVENT_TYPE, "init unit_produced")
	_check(gs_init.scenario.unit_by_id(200) != null, "unit from init")
	_check(gs_init.scenario.city_by_id(1).current_project == null, "city cleared init")

	var m2 = HexMapScript.make_tiny_test_map()
	var us2 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var ca = CityScript.new(5, 0, HexCoordScript.new(1, 0), _proj(0))
	var cb = CityScript.new(1, 0, HexCoordScript.new(1, -1), _proj(0))
	var sc2 = ScenarioScript.new(m2, us2, [ca, cb], 11, 22)
	var gs2 = GameStateScript.new(sc2)
	var etx = gs2.try_apply(EndTurnScript.make(0))
	_check(etx["index"] == 2, "two progress one end")
	var g0 = gs2.log.get_entry(0) as Dictionary
	var g1 = gs2.log.get_entry(1) as Dictionary
	_check(g0["city_id"] == 1 and g1["city_id"] == 5, "production order by id")

	var bad = gs2.try_apply(EndTurnScript.make(0))
	_check(not bad["accepted"] and bad["reason"] == "not_current_player", "wrong player no tick")
	var sz = gs2.log.size()
	_check(sz == 3, "no log on reject")

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
