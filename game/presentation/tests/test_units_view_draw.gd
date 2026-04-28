# Headless: godot --headless --path game -s res://presentation/tests/test_units_view_draw.gd
extends SceneTree
const UnitsViewScript = preload("res://presentation/units_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var items = UnitsViewScript.compute_marker_items(sc, layout)
	_check(
		items.size() == sc.units().size(),
		"marker items should match number of domain units"
	)
	var id_seen = {}
	var i = 0
	while i < items.size():
		var it = items[i]
		var uid = it["unit_id"]
		if not id_seen.has(uid):
			id_seen[uid] = 0
		id_seen[uid] = id_seen[uid] + 1
		_check(
			sc.map.has(it["coord"]),
			"each marker coord should be on the map"
		)
		_check(
			not it["coord"].equals(HexCoordScript.new(-1, 0)),
			"WATER cell should have no unit marker in canonical scenario"
		)
		var exp_w = layout.hex_to_world(it["coord"].q, it["coord"].r)
		_check(
			(it["world"] as Vector2).is_equal_approx(exp_w),
			"world position should match layout.hex_to_world for coord"
		)
		i = i + 1
	var ulist = sc.units()
	var k = 0
	while k < ulist.size():
		var uu = ulist[k]
		_check(
			id_seen.get(uu.id, 0) == 1,
			"each unit id from domain should appear exactly once in items"
		)
		k = k + 1
	var c0: Color
	var c0_set = false
	var c1: Color
	var c1_set = false
	var m = 0
	while m < items.size():
		var it2 = items[m]
		if it2["owner_id"] == 0:
			if not c0_set:
				c0 = it2["color"]
				c0_set = true
			_check(
				(it2["color"] as Color).is_equal_approx(c0),
				"owner 0 items should share the same color"
			)
		if it2["owner_id"] == 1:
			if not c1_set:
				c1 = it2["color"]
				c1_set = true
		m = m + 1
	_check(c0_set, "should have at least one owner-0 item")
	_check(c1_set, "should have at least one owner-1 item")
	_check(
		not c1.is_equal_approx(c0),
		"owner-1 color should differ from owner-0 color"
	)
	_check(
		UnitsViewScript.compute_marker_items(null, layout).size() == 0,
		"null scenario should produce no items"
	)
	_check(
		UnitsViewScript.compute_marker_items(sc, null).size() == 0,
		"null layout should produce no items"
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
