# Headless: godot --headless --path game -s res://domain/tests/test_scenario_cities.gd
extends SceneTree
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u0 = UnitScript.new(7, 0, HexCoordScript.new(0, 0))
	var cs = [CityScript.new(1, 0, HexCoordScript.new(1, -1)), CityScript.new(2, 1, HexCoordScript.new(1, 0))]
	var sc = ScenarioScript.new(m, [u0], cs)
	_check(sc.cities().size() == 2, "two cities stored")
	_check(sc.city_by_id(1) != null and sc.city_by_id(1).id == 1, "city_by_id 1")
	_check(sc.city_by_id(2) != null and sc.city_by_id(2).owner_id == 1, "city_by_id 2 owner")
	_check(sc.city_by_id(99) == null, "missing city null")
	_check(
		sc.cities_at(HexCoordScript.new(1, -1)).size() == 1,
		"one city at (1,-1)"
	)
	_check(sc.cities_owned_by(0).size() == 1, "owner 0 one city")
	_check(sc.cities_owned_by(1).size() == 1, "owner 1 one city")
	var dup = sc.cities()
	dup.pop_back()
	_check(sc.cities().size() == 2, "cities() duplicate is defensive copy")
	_check(sc.peek_next_unit_id() == 8, "auto next unit id max(7)+1")
	_check(sc.peek_next_city_id() == 3, "auto next city id max(2)+1")
	var sc2 = ScenarioScript.new(m, [u0], cs, 100, 50)
	_check(sc2.peek_next_unit_id() == 100, "explicit next unit id preserved")
	_check(sc2.peek_next_city_id() == 50, "explicit next city id preserved")
	var tiny = ScenarioScript.make_tiny_test_scenario()
	_check(tiny.cities().size() == 0, "tiny fixture has no cities")
	_check(tiny.peek_next_city_id() == 1, "no cities implies next city id 1")
	_check(
		tiny.peek_next_unit_id() == 4,
		"tiny fixture units 1,2,3 imply next unit id 4"
	)
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
