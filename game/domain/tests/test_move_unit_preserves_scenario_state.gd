# Headless: godot --headless --path game -s res://domain/tests/test_move_unit_preserves_scenario_state.gd
extends SceneTree
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u0 = UnitScript.new(7, 0, HexCoordScript.new(0, 0))
	var city = CityScript.new(2, 1, HexCoordScript.new(1, 0))
	var cs = [city]
	var sc = ScenarioScript.new(m, [u0], cs, 50, 40)
	var action = MoveUnitScript.make(0, 7, 0, 0, 1, -1)
	var v = MoveUnitScript.validate(sc, action)
	_check(v["ok"], "move should be legal for fixture")
	var before_u = sc.unit_by_id(7)
	var before_city_ids = sc.cities().size()
	var nu = MoveUnitScript.apply(sc, action)
	_check(nu.cities().size() == before_city_ids, "city count preserved")
	_check(nu.city_by_id(2) != null, "city 2 still present")
	_check(
		nu.city_by_id(2).owner_id == 1 and nu.city_by_id(2).position.q == 1 and nu.city_by_id(2).position.r == 0,
		"city id owner position unchanged"
	)
	_check(
		nu.city_by_id(2).equals(city),
		"same City value identity via equals(id)"
	)
	_check(nu.peek_next_unit_id() == 50, "next_unit_id unchanged")
	_check(nu.peek_next_city_id() == 40, "next_city_id unchanged")
	_check(
		nu.unit_by_id(7).position.q == 1 and nu.unit_by_id(7).position.r == -1,
		"moved unit at destination in returned scenario"
	)
	_check(
		before_u.position.q == 0 and before_u.position.r == 0,
		"original unit object position unchanged (immutable ref)"
	)
	_check(
		sc.unit_by_id(7).position.q == 0 and sc.unit_by_id(7).position.r == 0,
		"input scenario unit still at old hex"
	)
	_check(sc.cities().size() == 1, "input scenario city count unchanged")
	_check(
		sc.city_by_id(2).position.q == 1 and sc.city_by_id(2).position.r == 0,
		"input scenario city position unchanged"
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
