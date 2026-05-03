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
	var rr = Rect2(100.0, 50.0, 40.0, 48.0)
	const TamScript = preload("res://presentation/texture_alpha_metrics.gd")
	var msett: Dictionary = TamScript.metrics_for_res_path(
		UnitsViewScript.marker_texture_res_path("settler")
	)
	_check(msett.get("ok", false), "alpha metrics should load for settler marker PNG")
	if msett.get("ok", false):
		_check(int(msett["bottom_padding_px"]) >= 0, "bottom_padding_px should be non-negative")
	var uv_align: UnitsViewScript = UnitsViewScript.new()
	uv_align._ready()
	var anch: Vector2 = Vector2(512.0, 384.0)
	var psc: float = 1.0
	var urect: Rect2 = uv_align.unit_marker_texture_rect_presentation(anch, psc, "settler")
	if urect.size.x > 0.0:
		var raw_b: Vector2 = UnitsViewScript.unit_png_bottom_center_from_rect(urect)
		var pad_s: float = TamScript.scaled_bottom_padding_y(msett, urect.size.y)
		var eff_pt: Vector2 = raw_b - Vector2(0.0, pad_s)
		_check(
			eff_pt.distance_to(anch) < 0.02,
			"textured unit effective bottom (opaque) should match anchor_pres"
		)
	var urect_w: Rect2 = uv_align.unit_marker_texture_rect_presentation(anch, psc, "warrior")
	if urect_w.size.x > 0.0:
		var mwarr: Dictionary = TamScript.metrics_for_res_path(
			UnitsViewScript.marker_texture_res_path("warrior")
		)
		var raw_w: Vector2 = UnitsViewScript.unit_png_bottom_center_from_rect(urect_w)
		var pad_w: float = TamScript.scaled_bottom_padding_y(mwarr, urect_w.size.y)
		var eff_w: Vector2 = raw_w - Vector2(0.0, pad_w)
		_check(
			eff_w.distance_to(anch) < 0.02,
			"warrior textured effective bottom should match anchor_pres"
		)
	uv_align.queue_free()
	var bc = UnitsViewScript.unit_png_bottom_center_from_rect(rr)
	_check(
		bc.is_equal_approx(Vector2(120.0, 98.0)),
		"PNG bottom-center is rect mid-x and position.y+size.y"
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
