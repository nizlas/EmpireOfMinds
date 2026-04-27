# Headless: godot --headless --path game -s res://presentation/tests/test_map_view_draw.gd
extends SceneTree
const MapViewScript = preload("res://presentation/map_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var layout = HexLayoutScript.new()
	var items = MapViewScript.compute_draw_items(m, layout)
	_check(
		items.size() == m.size(),
		"items.size() should match map.size()"
	)
	var cl = m.coords()
	_check(
		items.size() == cl.size(),
		"items.size() should match coords().size()"
	)
	var cidx = 0
	while cidx < cl.size():
		var dc = cl[cidx]
		var found = 0
		var t = 0
		while t < items.size():
			var it1 = items[t]
			if it1["coord"].equals(dc):
				found = found + 1
			t = t + 1
		_check(
			found == 1,
			"each coord from domain should appear exactly once in items"
		)
		cidx = cidx + 1
	var u = 0
	while u < items.size():
		var it2 = items[u]
		_check(
			m.has(it2["coord"]),
			"draw item coord must be on the map"
		)
		u = u + 1
	var c00: Color
	var cW: Color
	var got00 = false
	var gotW = false
	var v = 0
	while v < items.size():
		var it3 = items[v]
		if it3["coord"].equals(HexCoordScript.new(0, 0)):
			c00 = it3["color"]
			got00 = true
		if it3["coord"].equals(HexCoordScript.new(-1, 0)):
			cW = it3["color"]
			gotW = true
		v = v + 1
	_check(got00, "items should include coord (0,0)")
	_check(gotW, "items should include coord (-1,0)")
	_check(c00 != cW, "WATER and PLAINS cells should have different draw colors")
	var w = 0
	while w < items.size():
		var it4 = items[w]
		_check(
			it4["corners"].size() == 6,
			"each hex should have 6 corner points"
		)
		var coord = it4["coord"]
		var wexp = layout.hex_to_world(coord.q, coord.r)
		_check(
			(it4["world"] as Vector2).is_equal_approx(wexp),
			"item world should match layout.hex_to_world for that coord"
		)
		w = w + 1
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
