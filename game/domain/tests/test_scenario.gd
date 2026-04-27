# Headless: godot --headless --path game -s res://domain/tests/test_scenario.gd
extends SceneTree
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	_check(sc.units().size() == 3, "tiny scenario should have 3 units")
	_check(
		sc.unit_by_id(1) != null and sc.unit_by_id(1).id == 1,
		"unit 1 should exist with id 1"
	)
	_check(
		sc.unit_by_id(2) != null and sc.unit_by_id(2).id == 2,
		"unit 2 should exist with id 2"
	)
	_check(
		sc.unit_by_id(3) != null and sc.unit_by_id(3).id == 3,
		"unit 3 should exist with id 3"
	)
	_check(sc.unit_by_id(99) == null, "unit 99 should not exist")
	_check(
		sc.units_at(HexCoordScript.new(0, 0)).size() == 1,
		"exactly one unit at (0,0)"
	)
	_check(
		sc.units_at(HexCoordScript.new(-1, 0)).size() == 0,
		"WATER hex has no unit in canonical fixture"
	)
	_check(sc.units_owned_by(0).size() == 2, "owner 0 has 2 units")
	_check(sc.units_owned_by(1).size() == 1, "owner 1 has 1 unit")
	var ulist = sc.units()
	var idx = 0
	while idx < ulist.size():
		var uu = ulist[idx]
		_check(
			sc.map.has(uu.position),
			"each unit position must be on the map"
		)
		idx = idx + 1
	var arr = sc.units()
	arr.pop_back()
	_check(
		sc.units().size() == 3,
		"mutating a duplicate from units() must not shrink internal list"
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
