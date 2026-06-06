# Headless: canonical tech-tree node grid + dependency routing (presentation only).
extends SceneTree

const NodeLayoutScript = preload("res://presentation/tech_tree_node_layout.gd")
const GridScript = preload("res://presentation/tech_tree_grid_layout.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_layout_catalog()
	_test_prototype_nodes()
	_test_segment_three_column_order()
	_test_edge_references()
	_test_straight_routing()
	_test_bend_routing()
	_test_final_bus_routing()
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


func _rect_for_title(title: String, widths: Array, viewport_h: float) -> Rect2:
	var layout: Dictionary = NodeLayoutScript.layout_for_title(title)
	var column: int = int(layout.get("column", 0))
	var row: int = int(layout.get("row", 0))
	var pos: Vector2 = NodeLayoutScript.tech_item_position_for_node(
		column,
		row,
		widths,
		viewport_h,
	)
	var item_h: float = (
		GridScript.TECH_ITEM_DISPLAY_HEIGHT * GridScript.content_scale(viewport_h)
	)
	var item_w: float = item_h * GridScript.TECH_ITEM_WIDTH_PER_HEIGHT
	return Rect2(pos, Vector2(item_w, item_h))


func _rects_for_titles(titles: Array, widths: Array, viewport_h: float) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < titles.size():
		var title: String = str(titles[i])
		out[title] = _rect_for_title(title, widths, viewport_h)
		i += 1
	return out


func _polyline_for_edge(edge: Dictionary, rects: Dictionary, widths: Array, viewport_h: float) -> PackedVector2Array:
	var all: Array = NodeLayoutScript.build_dependency_polylines(rects, widths, viewport_h)
	var from_title: String = str(edge.get("from", ""))
	var to_title: String = str(edge.get("to", ""))
	if not rects.has(from_title) or not rects.has(to_title):
		return PackedVector2Array()
	var start: Vector2 = NodeLayoutScript.node_output_point(rects[from_title])
	var end: Vector2 = NodeLayoutScript.node_input_point(rects[to_title])
	var i: int = 0
	while i < all.size():
		var entry: Dictionary = all[i]
		var points: PackedVector2Array = entry.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2:
			i += 1
			continue
		if points[0].is_equal_approx(start) and points[points.size() - 1].is_equal_approx(end):
			return points
		if points[0].is_equal_approx(start):
			return points
		i += 1
	return PackedVector2Array()


func _test_layout_catalog() -> void:
	_check(
		NodeLayoutScript.NODE_LAYOUT_BY_TITLE.size() == 21,
		"layout catalog has twenty-one nodes",
	)
	_check(
		NodeLayoutScript.TECH_TREE_EDGES.size() == 22,
		"prototype edge list has twenty-two edges",
	)
	var exo: Dictionary = NodeLayoutScript.layout_for_title("Exoplanet Expedition")
	_check(int(exo.get("column", 0)) == 9, "Exoplanet Expedition column is 9")
	_check(int(exo.get("row", 0)) == 2, "Exoplanet Expedition row is 2")


func _test_prototype_nodes() -> void:
	var nodes: Array[Dictionary] = ContentScript.prototype_nodes()
	_check(nodes.size() == 21, "prototype_nodes returns twenty-one entries")
	var seen_titles: Dictionary = {}
	var i: int = 0
	while i < nodes.size():
		var node: Dictionary = nodes[i]
		var title: String = str(node.get("title", ""))
		_check(NodeLayoutScript.NODE_LAYOUT_BY_TITLE.has(title), "node title in layout: %s" % title)
		_check(not seen_titles.has(title), "unique rendered title: %s" % title)
		seen_titles[title] = true
		var layout: Dictionary = NodeLayoutScript.layout_for_title(title)
		_check(int(node.get("column", -1)) == int(layout["column"]), "column for %s" % title)
		_check(int(node.get("row", -1)) == int(layout["row"]), "row for %s" % title)
		_check(not (node.get("content", {}) as Dictionary).is_empty(), "content for %s" % title)
		i += 1


func _test_segment_three_column_order() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var viewport_h: float = GridScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
	var c7: Vector2 = NodeLayoutScript.tech_item_position_for_node(7, 2, widths, viewport_h)
	var c8_levers: Vector2 = NodeLayoutScript.tech_item_position_for_node(8, 3, widths, viewport_h)
	var c8_glyph: Vector2 = NodeLayoutScript.tech_item_position_for_node(8, 4, widths, viewport_h)
	var c9: Vector2 = NodeLayoutScript.tech_item_position_for_node(9, 2, widths, viewport_h)
	_check(c7.x < c8_levers.x, "segment 3 column 7 is left of column 8")
	_check(c8_levers.x < c9.x, "segment 3 column 8 is left of column 9 (Exoplanet)")
	_check(c8_glyph.x < c9.x, "segment 3 column 8 glyph column is left of column 9")
	_check(
		GridScript.segment_layout_mode_for_index(2) == "mirror",
		"segment 3 still uses mirrored slot coordinates on bg3",
	)
	var old_c9_slot: Vector2 = GridScript.tech_item_position(
		2,
		2,
		1,
		widths,
		NodeLayoutScript.CANONICAL_ROW_COUNT,
		false,
		true,
		viewport_h,
	)
	var old_c7_slot: Vector2 = GridScript.tech_item_position(
		2,
		0,
		1,
		widths,
		NodeLayoutScript.CANONICAL_ROW_COUNT,
		false,
		true,
		viewport_h,
	)
	_check(
		c7.is_equal_approx(old_c9_slot),
		"C7 keeps former mirrored local-slot-2 pixel (label flip only)",
	)
	_check(
		c9.is_equal_approx(old_c7_slot),
		"C9 keeps former mirrored local-slot-0 pixel (label flip only)",
	)


func _test_edge_references() -> void:
	_check(NodeLayoutScript.edge_references_valid_titles(), "all edges reference layout titles")


func _test_straight_routing() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var viewport_h: float = GridScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
	var rects: Dictionary = _rects_for_titles(
		["Foraging Systems", "Seasonal Calendars"],
		widths,
		viewport_h,
	)
	var edge: Dictionary = {"from": "Foraging Systems", "to": "Seasonal Calendars", "route": "straight"}
	var points: PackedVector2Array = _polyline_for_edge(edge, rects, widths, viewport_h)
	_check(points.size() == 2, "straight same-row edge is one segment")
	if points.size() == 2:
		_check(absf(points[0].y - points[1].y) < 1.0, "straight same-row edge is horizontal")


func _test_bend_routing() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var viewport_h: float = GridScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
	var bend5_rects: Dictionary = _rects_for_titles(
		["Basic Mining", "Timber Working"],
		widths,
		viewport_h,
	)
	var bend5_edge: Dictionary = {
		"from": "Basic Mining",
		"to": "Timber Working",
		"route": "bend",
		"bend_after": 5,
	}
	var bend5: PackedVector2Array = _polyline_for_edge(bend5_edge, bend5_rects, widths, viewport_h)
	_check(bend5.size() == 4, "Basic Mining -> Timber Working uses three segments")
	if bend5.size() == 4:
		var bend5_x: float = NodeLayoutScript.bend_x_after_column_scroll(5, widths, viewport_h)
		_check(absf(bend5[1].x - bend5_x) < 1.0, "bend_after=5 vertical kink x between C5 and C6")
		_check(absf(bend5[2].x - bend5_x) < 1.0, "bend_after=5 vertical segment shares kink x")
		_check(absf(bend5[1].y - bend5[0].y) < 1.0, "bend_after=5 first segment horizontal")
		_check(absf(bend5[3].y - bend5[2].y) < 1.0, "bend_after=5 last segment horizontal")

	var bend4_rects: Dictionary = _rects_for_titles(
		["Textile Work", "Fishing Methods"],
		widths,
		viewport_h,
	)
	var bend4_edge: Dictionary = {
		"from": "Textile Work",
		"to": "Fishing Methods",
		"route": "bend",
		"bend_after": 4,
	}
	var bend4: PackedVector2Array = _polyline_for_edge(bend4_edge, bend4_rects, widths, viewport_h)
	_check(bend4.size() == 4, "Textile Work -> Fishing Methods uses bent routing")
	if bend4.size() == 4:
		var bend4_x: float = NodeLayoutScript.bend_x_after_column_scroll(4, widths, viewport_h)
		_check(absf(bend4[1].x - bend4_x) < 1.0, "bend_after=4 vertical kink x between C4 and C5")


func _test_final_bus_routing() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var viewport_h: float = GridScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
	var titles: Array = [
		"Fishing Methods",
		"Wheelwrighting",
		"Simple Levers",
		"Glyphic Records",
		"Exoplanet Expedition",
	]
	var rects: Dictionary = _rects_for_titles(titles, widths, viewport_h)
	var polylines: Array = NodeLayoutScript.build_dependency_polylines(rects, widths, viewport_h)
	_check(polylines.size() >= 6, "final_bus emits stubs, bus, and target connector")
	var bus_x: float = NodeLayoutScript.final_bus_x_scroll(widths, viewport_h)
	var target_in: Vector2 = NodeLayoutScript.node_input_point(rects["Exoplanet Expedition"])
	var bus_vertical_found: bool = false
	var target_connector_found: bool = false
	var stub_count: int = 0
	var pi: int = 0
	while pi < polylines.size():
		var entry: Dictionary = polylines[pi]
		var points: PackedVector2Array = entry.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() == 2:
			if absf(points[0].x - bus_x) < 1.0 and absf(points[1].x - bus_x) < 1.0:
				if absf(points[0].y - points[1].y) > 1.0:
					bus_vertical_found = true
			if points[0].is_equal_approx(target_in) or points[1].is_equal_approx(target_in):
				var other: Vector2 = points[1] if points[0].is_equal_approx(target_in) else points[0]
				if absf(other.x - bus_x) < 1.5 and absf(other.y - target_in.y) < 1.0:
					target_connector_found = true
			if absf(points[1].x - bus_x) < 1.0 and absf(points[0].y - points[1].y) < 1.0:
				stub_count += 1
		pi += 1
	_check(bus_vertical_found, "final_bus draws shared vertical bus after C8")
	_check(stub_count >= 4, "final_bus draws horizontal stubs from prerequisites")
	_check(target_connector_found, "final_bus connects horizontally into Exoplanet Expedition")
