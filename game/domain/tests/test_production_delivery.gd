# Headless: godot --headless --path game -s res://domain/tests/test_production_delivery.gd
extends SceneTree

const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _proj_ready(p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = cost
	d["ready"] = true
	return d


func _init() -> void:
	var rnull = ProductionDeliveryScript.deliver_pending_for_player(null, 0)
	_check(rnull["scenario"] == null, "null scenario")
	_check((rnull["events"] as Array).size() == 0, "null no events")

	var m0 = HexMapScript.make_tiny_test_map()
	var u0 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c0 = CityScript.new(1, 0, HexCoordScript.new(1, -1), _proj_ready(2, 2))
	var sc0 = ScenarioScript.new(m0, u0, [c0], 100, 200)
	var r0 = ProductionDeliveryScript.deliver_pending_for_player(sc0, 1)
	_check(r0["scenario"] == sc0, "no ready for wrong owner")
	_check((r0["events"] as Array).size() == 0, "no events wrong owner")

	var r0b = ProductionDeliveryScript.deliver_pending_for_player(sc0, 0)
	var ev0 = r0b["events"] as Array
	_check(ev0.size() == 1, "one unit_produced")
	var e0 = ev0[0] as Dictionary
	_check(e0["action_type"] == ProductionDeliveryScript.EVENT_TYPE, "event type")
	_check(e0["source"] == "engine" and e0["result"] == "accepted", "event meta")
	_check(e0["unit_id"] == 100 and e0["city_id"] == 1 and e0["actor_id"] == 0, "ids")
	var ns0 = r0b["scenario"]
	_check(ns0.city_by_id(1).current_project == null, "city cleared")
	_check(ns0.peek_next_unit_id() == 101 and ns0.peek_next_city_id() == 200, "counters")
	var u100 = ns0.unit_by_id(100)
	_check(u100 != null and u100.owner_id == 0 and u100.position.equals(c0.position), "unit state")
	_check(u100.type_id == "warrior", "produced unit type warrior")
	_check(c0.current_project != null and bool((c0.current_project as Dictionary).get("ready", false)), "orig city untouched")

	var m1 = HexMapScript.make_tiny_test_map()
	var u1 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cb = CityScript.new(5, 0, HexCoordScript.new(1, 0), _proj_ready(2, 2))
	var ca = CityScript.new(1, 0, HexCoordScript.new(0, -1), _proj_ready(2, 2))
	var sc1 = ScenarioScript.new(m1, u1, [cb, ca], 50, 60)
	var r1 = ProductionDeliveryScript.deliver_pending_for_player(sc1, 0)
	var ev1 = r1["events"] as Array
	_check(ev1.size() == 2, "two events")
	_check((ev1[0] as Dictionary)["city_id"] == 1, "first city id order")
	_check((ev1[0] as Dictionary)["unit_id"] == 50, "first unit id")
	_check((ev1[1] as Dictionary)["city_id"] == 5, "second city id")
	_check((ev1[1] as Dictionary)["unit_id"] == 51, "second unit id")
	var ns1 = r1["scenario"]
	_check(ns1.unit_by_id(50).type_id == "warrior", "first delivery warrior")
	_check(ns1.unit_by_id(51).type_id == "warrior", "second delivery warrior")

	var m2 = HexMapScript.make_tiny_test_map()
	var u2 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var d_wrong: Dictionary = {}
	d_wrong["project_type"] = "future_kind"
	d_wrong["progress"] = 3
	d_wrong["cost"] = 2
	d_wrong["ready"] = true
	var cw = CityScript.new(3, 0, HexCoordScript.new(1, -1), d_wrong)
	var sc2 = ScenarioScript.new(m2, u2, [cw], 70, 80)
	var r2 = ProductionDeliveryScript.deliver_pending_for_player(sc2, 0)
	_check(r2["scenario"] == sc2, "non-produce not delivered")
	_check((r2["events"] as Array).size() == 0, "no events future ready")

	var rsecond = ProductionDeliveryScript.deliver_pending_for_player(r1["scenario"], 0)
	_check((rsecond["events"] as Array).size() == 0, "second deliver idempotent")

	var m_pid = HexMapScript.make_tiny_test_map()
	var u_pid = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var d_canon: Dictionary = {}
	d_canon["project_type"] = "produce_unit"
	d_canon["project_id"] = "produce_unit:warrior"
	d_canon["progress"] = 2
	d_canon["cost"] = 2
	d_canon["ready"] = true
	var c_pid = CityScript.new(1, 0, HexCoordScript.new(1, -1), d_canon)
	var sc_pid = ScenarioScript.new(m_pid, u_pid, [c_pid], 300, 400)
	var r_pid = ProductionDeliveryScript.deliver_pending_for_player(sc_pid, 0)
	var ns_pid = r_pid["scenario"]
	_check(ns_pid.unit_by_id(300).type_id == "warrior", "registry project_id yields warrior")

	var m_unk = HexMapScript.make_tiny_test_map()
	var u_unk = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var d_unk: Dictionary = {}
	d_unk["project_type"] = "produce_unit"
	d_unk["project_id"] = "produce_unit:future"
	d_unk["progress"] = 2
	d_unk["cost"] = 2
	d_unk["ready"] = true
	var c_unk = CityScript.new(1, 0, HexCoordScript.new(1, -1), d_unk)
	var sc_unk = ScenarioScript.new(m_unk, u_unk, [c_unk], 310, 410)
	var r_unk = ProductionDeliveryScript.deliver_pending_for_player(sc_unk, 0)
	var ns_unk = r_unk["scenario"]
	_check(ns_unk.unit_by_id(310).type_id == "warrior", "unknown project_id falls back warrior")

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
