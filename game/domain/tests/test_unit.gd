# Headless: godot --headless --path game -s res://domain/tests/test_unit.gd
extends SceneTree
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	_check(
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)).id == 1,
		"unit id should be 1"
	)
	_check(
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)).owner_id == 0,
		"owner_id should be 0"
	)
	_check(
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)).position.equals(HexCoordScript.new(0, 0)),
		"position should equal (0,0)"
	)
	var u1 = UnitScript.new(1, 0, HexCoordScript.new(0, 0))
	var u2 = UnitScript.new(1, 0, HexCoordScript.new(0, 0))
	_check(
		u1.equals(u2),
		"two units with the same id should be equal by equals()"
	)
	_check(
		not UnitScript.new(1, 0, HexCoordScript.new(0, 0)).equals(
			UnitScript.new(2, 0, HexCoordScript.new(0, 0))
		),
		"different id should not be equal"
	)
	var u3 = UnitScript.new(1, 0, HexCoordScript.new(0, 0))
	_check(u3.equals_id(1), "equals_id(1) should be true")
	_check(not u3.equals_id(2), "equals_id(2) should be false for id 1")
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
