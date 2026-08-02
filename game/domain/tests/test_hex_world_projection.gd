# Headless test: godot --headless --path game -s res://domain/tests/test_hex_world_projection.gd
extends SceneTree

const HexWorldProjection = preload("res://domain/world/hex_world_projection.gd")

var _total := 0
var _any_fail := false

const SQRT3 := 1.7320508075688772
const EPS := 0.0001


func _init() -> void:
	_test_neighbor_deltas()
	_test_axial_to_world_exact()
	_test_world_to_axial_round_trips()
	_test_jittered_footprints()
	_test_geographic_directions()
	_test_corner_orientation()
	_test_elevation_to_y()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _test_neighbor_deltas() -> void:
	for d in range(6):
		var offset: Vector2i = HexCoord.DIRECTIONS[d]
		var n := HexCoord.new(0, 0).neighbor(d)
		_check(n.q == offset.x and n.r == offset.y, "neighbor delta %d" % d)


func _test_axial_to_world_exact() -> void:
	_check_vec2(HexWorldProjection.axial_to_world_xz(0, 0), Vector2.ZERO, "(0,0)")
	_check_vec2(HexWorldProjection.axial_to_world_xz(1, 0), Vector2(SQRT3, 0.0), "(1,0)")
	_check_vec2(
		HexWorldProjection.axial_to_world_xz(0, 1),
		Vector2(SQRT3 * 0.5, 1.5),
		"(0,1)"
	)
	_check_vec2(
		HexWorldProjection.axial_to_world_xz(1, -1),
		Vector2(SQRT3 * 0.5, -1.5),
		"(1,-1)"
	)


func _test_world_to_axial_round_trips() -> void:
	var samples := [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, -1),
		Vector2i(-3, 5),
	]
	for coord in samples:
		var xz := HexWorldProjection.axial_to_world_xz(coord.x, coord.y)
		var back := HexWorldProjection.world_xz_to_axial(xz.x, xz.y)
		_check(back == coord, "round-trip center (%d,%d)" % [coord.x, coord.y])


func _test_jittered_footprints() -> void:
	var coord := Vector2i(2, 3)
	var center := HexWorldProjection.axial_to_world_xz(coord.x, coord.y)
	var jitter := Vector2(0.05, -0.04)
	var back := HexWorldProjection.world_xz_to_axial(center.x + jitter.x, center.y + jitter.y)
	_check(back == coord, "jittered in-footprint round-trip")


func _test_geographic_directions() -> void:
	var origin := HexWorldProjection.axial_to_world_xz(0, 0)
	var east := HexWorldProjection.axial_to_world_xz(1, 0)
	_check(absf(east.y - origin.y) < EPS, "+q keeps Z unchanged")
	_check(east.x > origin.x, "+q increases X (east)")
	var south_east := HexWorldProjection.axial_to_world_xz(0, 1)
	_check(south_east.y > origin.y, "+r increases Z (south component)")


func _test_corner_orientation() -> void:
	var corners := HexWorldProjection.corner_offsets_xz()
	var has_north := false
	var has_south := false
	for corner: Vector2 in corners:
		if absf(corner.x) < EPS and corner.y < -HexWorldProjection.S + EPS:
			has_north = true
		if absf(corner.x) < EPS and corner.y > HexWorldProjection.S - EPS:
			has_south = true
	_check(has_north and has_south, "corners include north and south points")


func _test_elevation_to_y() -> void:
	_check(
		absf(HexWorldProjection.elevation_to_world_y(1, 0.4) - 0.0) < EPS,
		"elevation 1 -> Y 0.0"
	)
	_check(
		absf(HexWorldProjection.elevation_to_world_y(4, 0.4) - 1.2) < EPS,
		"elevation 4 -> Y 1.2"
	)
	_check(
		absf(HexWorldProjection.elevation_to_world_y(6, 0.4) - 2.0) < EPS,
		"elevation 6 -> Y 2.0"
	)


func _check_vec2(actual: Vector2, expected: Vector2, label: String) -> void:
	_check(absf(actual.x - expected.x) < EPS and absf(actual.y - expected.y) < EPS, label)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)
