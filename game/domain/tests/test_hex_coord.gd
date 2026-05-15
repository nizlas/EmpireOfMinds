# Headless test: godot --headless --path game -s res://domain/tests/test_hex_coord.gd
# HexCoord is provided by class_name in domain/hex_coord.gd
extends SceneTree

var _total := 0
var _any_fail := false

func _init() -> void:
	# E neighbor: q and r
	var o0 := HexCoord.new(0, 0).neighbor(HexCoord.Direction.E)
	_check(o0.q == 1 and o0.r == 0, "E neighbor of (0,0) should be (1,0)")
	# every direction: neighbor(d) == DIRECTIONS[d] as HexCoord
	for d in range(6):
		var o: Vector2i = HexCoord.DIRECTIONS[d]
		_check(
			HexCoord.new(0, 0).neighbor(d).equals(HexCoord.new(o.x, o.y)),
			"neighbor(%d) should match DIRECTIONS offset" % d
		)
	_check(
		HexCoord.new(0, 0).neighbors().size() == 6,
		"neighbors() should return 6 cells"
	)
	_check(
		HexCoord.new(1, 2).equals(HexCoord.new(1, 2)),
		"equals true for same (q,r)"
	)
	_check(
		not HexCoord.new(1, 2).equals(HexCoord.new(2, 1)),
		"equals false for different (q,r)"
	)
	_check(
		HexCoord.new(3, -2).neighbor(HexCoord.Direction.NW).equals(HexCoord.new(3, -3)),
		"NW of (3,-2) should be (3,-3)"
	)
	var a := HexCoord.new(2, -1)
	var b := HexCoord.new(-1, 3)
	_check(HexCoord.axial_distance(a, b) == HexCoord.axial_distance(b, a), "axial_distance symmetric")
	_check(HexCoord.axial_distance(HexCoord.new(0, 0), HexCoord.new(0, 0)) == 0, "distance to self is 0")
	var nbr := HexCoord.new(0, 0).neighbor(HexCoord.Direction.E)
	_check(HexCoord.axial_distance(HexCoord.new(0, 0), nbr) == 1, "direct neighbor distance 1")
	var two := HexCoord.new(0, 0).neighbor(HexCoord.Direction.E).neighbor(HexCoord.Direction.E)
	_check(HexCoord.axial_distance(HexCoord.new(0, 0), two) == 2, "two-step along axis distance 2")
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
