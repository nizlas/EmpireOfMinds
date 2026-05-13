# Headless: godot --headless --path game -s res://domain/tests/test_scenario_city_territory.gd
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
	var c1_owned: Array = [HexCoordScript.new(1, -1), HexCoordScript.new(0, -1)]
	var c1 = CityScript.new(1, 0, HexCoordScript.new(1, -1), null, "", false, null, c1_owned)
	var c2 = CityScript.new(2, 1, HexCoordScript.new(1, 0))
	var sc = ScenarioScript.new(m, [u0], [c1, c2])
	var p1 = HexCoordScript.new(1, -1)
	var p0n = HexCoordScript.new(0, -1)
	_check(sc.tile_owner_city_id(p1) == 1, "tile_owner_city_id center")
	_check(sc.tile_owner_city_id(p0n) == 1, "tile_owner_city_id owned neighbor")
	_check(sc.city_owning_tile(p1).id == 1, "city_owning_tile returns row")
	_check(sc.tile_is_owned(p1), "tile_is_owned true for territory")
	_check(not sc.tile_is_owned(HexCoordScript.new(-1, 0)), "water hex unowned in this fixture")
	_check(sc.tile_owner_city_id(HexCoordScript.new(9, 9)) == -1, "tile_owner_city_id -1 when unowned")
	_check(sc.city_owning_tile(HexCoordScript.new(9, 9)) == null, "city_owning_tile null when unowned")
	var t1 = sc.tiles_owned_by_city(1)
	_check(t1.size() == 2 and t1[0].equals(p1) and t1[1].equals(p0n), "tiles_owned_by_city lists")
	t1.pop_back()
	_check(sc.tiles_owned_by_city(1).size() == 2, "tiles_owned_by_city defensive copy")
	_check(sc.tiles_owned_by_city(99).is_empty(), "unknown city id yields empty list")

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
