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


func _proj_kind(kind: String, p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = kind
	d["progress"] = p
	d["cost"] = cost
	return d


func _proj_ready_flag(p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = cost
	d["ready"] = true
	return d


func _init() -> void:
	# Identity: no tickable cities
	var m0 = HexMapScript.make_tiny_test_map()
	var u0 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var sc0 = ScenarioScript.new(m0, u0, [], 50, 60)
	var r0 = ProductionTickScript.apply_for_player(sc0, 0)
	_check(r0["scenario"] == sc0, "no cities same scenario ref")
	_check((r0["events"] as Array).size() == 0, "no events")

	# Null project: no tick
	var m1 = HexMapScript.make_tiny_test_map()
	var u1 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c1a = CityScript.new(1, 0, HexCoordScript.new(1, -1), null)
	var sc1 = ScenarioScript.new(m1, u1, [c1a], 50, 60)
	var r1 = ProductionTickScript.apply_for_player(sc1, 0)
	_check((r1["events"] as Array).size() == 0, "null project no tick")

	# Single progress, no completion
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
	var pr2 = ns2.city_by_id(2).current_project as Dictionary
	_check(pr2["progress"] == 1 and pr2["ready"] == false, "new scenario progress not ready")
	_check(int(p2_old["progress"]) == 0, "old dict snapshot")
	_check(c2.current_project["progress"] == 0, "original city untouched")
	_check(ns2.map == m2, "map same ref")
	_check(ns2.peek_next_unit_id() == 70 and ns2.peek_next_city_id() == 80, "peek preserved")

	# Two P0 cities: event order by city id; other owner untouched
	var m3 = HexMapScript.make_tiny_test_map()
	var u3 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cp0 = CityScript.new(2, 1, HexCoordScript.new(1, 0), _proj(5, 2))
	var cp1 = CityScript.new(1, 0, HexCoordScript.new(0, -1), _proj(0, 2))
	var cp5 = CityScript.new(5, 0, HexCoordScript.new(1, -1), _proj(0, 2))
	var sc3 = ScenarioScript.new(m3, u3, [cp5, cp0, cp1], 90, 100)
	var r3 = ProductionTickScript.apply_for_player(sc3, 0)
	var ev3 = r3["events"] as Array
	_check(ev3.size() == 2, "two p0 cities")
	var ed0 = ev3[0] as Dictionary
	var ed1 = ev3[1] as Dictionary
	_check(ed0["city_id"] == 1 and ed1["city_id"] == 5, "events sorted by id")
	_check(cp0.current_project["progress"] == 5, "p1 city untouched progress")

	# Completion: ready true, no unit, no unit_produced, peek unchanged
	var m4 = HexMapScript.make_tiny_test_map()
	var u4 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c4 = CityScript.new(3, 0, HexCoordScript.new(1, -1), _proj(2, 2))
	var sc4 = ScenarioScript.new(m4, u4, [c4], 10, 20)
	var r4 = ProductionTickScript.apply_for_player(sc4, 0)
	var ev4 = r4["events"] as Array
	_check(ev4.size() == 1, "progress only")
	var ep0 = ev4[0] as Dictionary
	_check(ep0["action_type"] == ProductionTickScript.EVENT_TYPE, "first progress")
	_check(ep0["progress_after"] == 3, "progress_after old+1")
	var ns4 = r4["scenario"]
	var pr4 = ns4.city_by_id(3).current_project as Dictionary
	_check(pr4["ready"] == true and pr4["progress"] == 3, "marked ready overflow ok")
	_check(ns4.peek_next_unit_id() == 10 and ns4.peek_next_city_id() == 20, "peek unchanged")
	_check(ns4.units().size() == sc4.units().size(), "no new unit")

	# No completion: cost not reached
	var m5 = HexMapScript.make_tiny_test_map()
	var u5 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c5 = CityScript.new(4, 0, HexCoordScript.new(1, -1), _proj(0, 5))
	var sc5 = ScenarioScript.new(m5, u5, [c5], 12, 21)
	var r5 = ProductionTickScript.apply_for_player(sc5, 0)
	_check((r5["events"] as Array).size() == 1, "only progress")
	_check(
		(r5["scenario"].city_by_id(4).current_project as Dictionary)["ready"] == false,
		"not ready below cost"
	)
	_check(r5["scenario"].peek_next_unit_id() == 12, "no unit id bump")

	# Defensive: non-produce_unit at threshold
	var m6 = HexMapScript.make_tiny_test_map()
	var u6 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c6 = CityScript.new(6, 0, HexCoordScript.new(1, -1), _proj_kind("future_kind", 1, 2))
	var sc6 = ScenarioScript.new(m6, u6, [c6], 13, 22)
	var r6 = ProductionTickScript.apply_for_player(sc6, 0)
	var ev6 = r6["events"] as Array
	_check(ev6.size() == 1, "progress only for future_kind")
	_check(r6["scenario"].city_by_id(6).current_project["progress"] == 2, "still has project")
	_check((r6["scenario"].city_by_id(6).current_project as Dictionary)["ready"] == false, "not ready")
	_check(r6["scenario"].peek_next_unit_id() == 13, "no new unit id")

	# Two cities hit ready: production_progress only
	var m7 = HexMapScript.make_tiny_test_map()
	var u7 = [UnitScript.new(9, 0, HexCoordScript.new(0, 0))]
	var pos1 = HexCoordScript.new(0, -1)
	var pos2 = HexCoordScript.new(1, -1)
	var c7b = CityScript.new(2, 0, pos2, _proj(1, 2))
	var c7a = CityScript.new(1, 0, pos1, _proj(1, 2))
	var sc7 = ScenarioScript.new(m7, u7, [c7b, c7a], 100, 200)
	var r7 = ProductionTickScript.apply_for_player(sc7, 0)
	var ev7 = r7["events"] as Array
	_check(ev7.size() == 2, "two progress only")
	_check((ev7[0] as Dictionary)["city_id"] == 1, "ev0 c1")
	_check((ev7[1] as Dictionary)["city_id"] == 2, "ev1 c2")
	var ns7 = r7["scenario"]
	_check(ns7.peek_next_unit_id() == 100, "peek unchanged")
	_check((ns7.city_by_id(1).current_project as Dictionary)["ready"] == true, "c1 ready")
	_check((ns7.city_by_id(2).current_project as Dictionary)["ready"] == true, "c2 ready")
	_check(ns7.units().size() == 1, "still one unit")

	# Mixed: one ready threshold, one partial
	var m8 = HexMapScript.make_tiny_test_map()
	var u8 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cx1 = CityScript.new(1, 0, HexCoordScript.new(0, -1), _proj(1, 2))
	var cx5 = CityScript.new(5, 0, HexCoordScript.new(1, -1), _proj(0, 2))
	var sc8 = ScenarioScript.new(m8, u8, [cx5, cx1], 50, 60)
	var r8 = ProductionTickScript.apply_for_player(sc8, 0)
	var ev8 = r8["events"] as Array
	_check(ev8.size() == 2, "two progress")
	var ns8 = r8["scenario"]
	_check((ns8.city_by_id(1).current_project as Dictionary)["ready"] == true, "c1 ready")
	_check(
		(ns8.city_by_id(5).current_project as Dictionary)["progress"] == 1
		and (ns8.city_by_id(5).current_project as Dictionary)["ready"] == false,
		"c5 partial"
	)
	_check(ns8.peek_next_unit_id() == 50, "no unit allocated")

	# No aliasing
	var m9 = HexMapScript.make_tiny_test_map()
	var u9 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c9 = CityScript.new(3, 0, HexCoordScript.new(1, -1), _proj(0, 3))
	var before_p = c9.current_project["progress"]
	var sc9 = ScenarioScript.new(m9, u9, [c9], 77, 88)
	var r9 = ProductionTickScript.apply_for_player(sc9, 0)
	var scn9 = r9["scenario"]
	scn9.city_by_id(3).current_project["progress"] = 99
	_check(c9.current_project["progress"] == before_p, "input city not aliased to new project dict")

	# ready city skipped
	var m10 = HexMapScript.make_tiny_test_map()
	var u10 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c10 = CityScript.new(8, 0, HexCoordScript.new(1, -1), _proj_ready_flag(2, 2))
	var sc10 = ScenarioScript.new(m10, u10, [c10], 55, 66)
	var r10 = ProductionTickScript.apply_for_player(sc10, 0)
	_check(r10["scenario"] == sc10, "skip ready same ref")
	_check((r10["events"] as Array).size() == 0, "no tick for ready")

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
