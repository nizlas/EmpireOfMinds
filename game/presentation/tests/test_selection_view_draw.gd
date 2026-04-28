# Headless: godot --headless --path game -s res://presentation/tests/test_selection_view_draw.gd
extends SceneTree
const SelectionViewScript = preload("res://presentation/selection_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var sel = SelectionStateScript.new()
	var items0 = SelectionViewScript.compute_overlay_items(sc, layout, sel)
	_check(
		items0.size() == 0,
		"empty selection should produce no overlay items"
	)
	sel.select(1)
	var items = SelectionViewScript.compute_overlay_items(sc, layout, sel)
	var ring_count = 0
	var dest_count = 0
	var expected_dests = [
		HexCoordScript.new(1, -1),
		HexCoordScript.new(-1, 1),
		HexCoordScript.new(0, 1),
	]
	var t = 0
	while t < items.size():
		var it = items[t]
		var k = it["kind"]
		var c = it["coord"]
		var corners = it["corners"] as PackedVector2Array
		var wexp = layout.hex_to_world(c.q, c.r)
		_check(
			(it["world"] as Vector2).is_equal_approx(wexp),
			"item world should match hex_to_world"
		)
		_check(corners.size() == 6, "each item should have 6 corners")
		if k == "selected_ring":
			ring_count = ring_count + 1
			_check(
				c.equals(HexCoordScript.new(0, 0)),
				"selected ring should be at (0,0) for unit 1"
			)
		elif k == "destination_fill":
			dest_count = dest_count + 1
			_check(_matches_any_dest(c, expected_dests), "destination should be one of expected")
		t = t + 1
	_check(ring_count == 1, "exactly one selected_ring")
	_check(dest_count == 3, "exactly three destination_fill items")
	sel.select(99)
	var items_bad = SelectionViewScript.compute_overlay_items(sc, layout, sel)
	_check(
		items_bad.size() == 0,
		"unknown unit id should produce no overlay"
	)
	_check(
		SelectionViewScript.compute_overlay_items(null, layout, sel).size() == 0,
		"null scenario should produce []"
	)
	sel.select(1)
	_check(
		SelectionViewScript.compute_overlay_items(sc, null, sel).size() == 0,
		"null layout should produce []"
	)
	_check(
		SelectionViewScript.compute_overlay_items(sc, layout, null).size() == 0,
		"null selection should produce []"
	)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _matches_any_dest(coord, dest_list) -> bool:
	var i = 0
	while i < dest_list.size():
		if coord.equals(dest_list[i]):
			return true
		i = i + 1
	return false

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
