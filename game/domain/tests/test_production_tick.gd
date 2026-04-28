# Headless: godot --headless --path game -s res://domain/tests/test_production_tick.gd
extends SceneTree

const ProductionTickScript = preload("res://domain/production_tick.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _proj(p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = cost
	return d


func _init() -> void:
	var m0 = HexMapScript.make_tiny_test_map()
	var u0 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var sc0 = ScenarioScript.new(m0, u0, [], 50, 60)
	var r0 = ProductionTickScript.apply_for_player(sc0, 0)
	_check(r0["scenario"] == sc0, "no cities same scenario ref")
	_check((r0["events"] as Array).size() == 0, "no events")

	var m1 = HexMapScript.make_tiny_test_map()
	var u1 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c1a = CityScript.new(1, 0, HexCoordScript.new(1, -1), null)
	var sc1 = ScenarioScript.new(m1, u1, [c1a], 50, 60)
	var r1 = ProductionTickScript.apply_for_player(sc1, 0)
	_check((r1["events"] as Array).size() == 0, "null project no tick")

	var m2 = HexMapScript.make_tiny_test_map()
	var u2 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c2 = CityScript.new(2, 0, HexCoordScript.new(1, -1), _proj(0, 2))
	var p2_old = (c2.current_project as Dictionary).duplicate(true)
	var sc2 = ScenarioScript.new(m2, u2, [c2], 70, 80)
	var r2 = ProductionTickScript.apply_for_player(sc2, 0)
	var ev2 = r2["events"] as Array
	_check(ev2.size() == 1, "one event")
	var e0 = ev2[0] as Dictionary
	_check(e0["action_type"] == ProductionTickScript.EVENT_TYPE, "event type")
	_check(e0["city_id"] == 2 and e0["progress_before"] == 0 and e0["progress_after"] == 1, "event numbers")
	_check(e0["cost"] == 2 and e0["source"] == "engine" and e0["result"] == "accepted", "event meta")
	var ns2 = r2["scenario"]
	_check(ns2.city_by_id(2).current_project["progress"] == 1, "new scenario progress")
	_check(int(p2_old["progress"]) == 0, "old dict snapshot")
	_check(c2.current_project["progress"] == 0, "original city untouched")
	_check(ns2.map == m2, "map same ref")
	_check(ns2.peek_next_unit_id() == 70 and ns2.peek_next_city_id() == 80, "peek preserved")

	var m3 = HexMapScript.make_tiny_test_map()
	var u3 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cp0 = CityScript.new(2, 1, HexCoordScript.new(1, -1), _proj(5, 2))
	var cp1 = CityScript.new(1, 0, HexCoordScript.new(0, -1), _proj(1, 2))
	var cp5 = CityScript.new(5, 0, HexCoordScript.new(1, 0), _proj(0, 2))
	var sc3 = ScenarioScript.new(m3, u3, [cp5, cp0, cp1], 90, 100)
	var r3 = ProductionTickScript.apply_for_player(sc3, 0)
	var ev3 = r3["events"] as Array
	_check(ev3.size() == 2, "two p0 cities")
	var ed0 = ev3[0] as Dictionary
	var ed1 = ev3[1] as Dictionary
	_check(ed0["city_id"] == 1 and ed1["city_id"] == 5, "events sorted by id")
	_check(cp0.current_project["progress"] == 5, "p1 city untouched progress")

	var m4 = HexMapScript.make_tiny_test_map()
	var u4 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c4 = CityScript.new(3, 0, HexCoordScript.new(1, -1), _proj(2, 2))
	var sc4 = ScenarioScript.new(m4, u4, [c4], 10, 20)
	var r4 = ProductionTickScript.apply_for_player(sc4, 0)
	var ns4 = r4["scenario"]
	_check(ns4.city_by_id(3).current_project["progress"] == 3, "exceeds cost ok")

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
