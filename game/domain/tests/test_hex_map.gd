# Headless test: godot --headless --path game -s res://domain/tests/test_hex_map.gd
# Explicit preloads: -s runs this script before global class_name registration is reliable.
extends SceneTree
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total := 0
var _any_fail := false

func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	_check(m.size() == 7, "make_tiny_test_map() should have 7 cells")
	_check(m.has(HexCoordScript.new(0, 0)), "has((0,0)) should be true")
	_check(not m.has(HexCoordScript.new(5, 5)), "has((5,5)) should be false")
	_check(
		m.terrain_at(HexCoordScript.new(0, 0)) == HexMapScript.Terrain.PLAINS,
		"terrain (0,0) should be PLAINS"
	)
	_check(
		m.terrain_at(HexCoordScript.new(-1, 0)) == HexMapScript.Terrain.WATER,
		"terrain (-1,0) should be WATER"
	)
	for d in range(6):
		_check(
			m.has(HexCoordScript.new(0, 0).neighbor(d)),
			"neighbor of (0,0) in direction %d should be on map" % d
		)
	var a := HexCoordScript.new(0, 0)
	var b := HexCoordScript.new(0, 0)
	_check(
		m.has(a) and m.has(b),
		"has() should be true for two separately constructed HexCoord(0,0) (value keys, not object identity)"
	)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)
