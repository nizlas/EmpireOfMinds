# Canonical prototype tech-tree node grid + dependency edge routing (presentation only).
class_name TechTreeNodeLayout
extends RefCounted

const GridScript = preload("res://presentation/tech_tree_grid_layout.gd")

const CANONICAL_COLUMN_COUNT: int = 9
const CANONICAL_ROW_COUNT: int = 4
const LINE_STROKE_DESIGN_PX: float = 4.0
const FINAL_BUS_AFTER_COLUMN: int = 8

const NODE_LAYOUT_BY_TITLE: Dictionary = {
	"Foraging Systems": {"column": 1, "row": 1},
	"Oral Surveying": {"column": 1, "row": 2},
	"Stone Tools": {"column": 1, "row": 3},
	"Controlled Fire": {"column": 1, "row": 4},
	"Seasonal Calendars": {"column": 2, "row": 1},
	"Animal Tracking": {"column": 2, "row": 2},
	"Pottery Craft": {"column": 2, "row": 4},
	"Agrarian Practice": {"column": 3, "row": 1},
	"Pastoral Herding": {"column": 3, "row": 2},
	"Basic Mining": {"column": 3, "row": 3},
	"Mudbrick Construction": {"column": 3, "row": 4},
	"River Irrigation": {"column": 4, "row": 1},
	"Textile Work": {"column": 4, "row": 2},
	"Fishing Methods": {"column": 5, "row": 1},
	"Counting Marks": {"column": 5, "row": 4},
	"Timber Working": {"column": 6, "row": 2},
	"Bronze Alloying": {"column": 6, "row": 3},
	"Wheelwrighting": {"column": 7, "row": 2},
	"Simple Levers": {"column": 8, "row": 3},
	"Glyphic Records": {"column": 8, "row": 4},
	"Exoplanet Expedition": {"column": 9, "row": 2},
}

const TECH_TREE_EDGES: Array = [
	{"from": "Foraging Systems", "to": "Seasonal Calendars", "route": "straight"},
	{"from": "Foraging Systems", "to": "Animal Tracking", "route": "bend", "bend_after": 1},
	{"from": "Oral Surveying", "to": "Animal Tracking", "route": "straight"},
	{"from": "Seasonal Calendars", "to": "Agrarian Practice", "route": "straight"},
	{"from": "Agrarian Practice", "to": "River Irrigation", "route": "straight"},
	{"from": "River Irrigation", "to": "Fishing Methods", "route": "straight"},
	{"from": "Animal Tracking", "to": "Pastoral Herding", "route": "straight"},
	{"from": "Pastoral Herding", "to": "Textile Work", "route": "straight"},
	{"from": "Textile Work", "to": "Fishing Methods", "route": "bend", "bend_after": 4},
	{"from": "Stone Tools", "to": "Basic Mining", "route": "straight"},
	{"from": "Basic Mining", "to": "Timber Working", "route": "bend", "bend_after": 5},
	{"from": "Basic Mining", "to": "Bronze Alloying", "route": "straight"},
	{"from": "Timber Working", "to": "Wheelwrighting", "route": "straight"},
	{"from": "Bronze Alloying", "to": "Simple Levers", "route": "straight"},
	{"from": "Controlled Fire", "to": "Pottery Craft", "route": "straight"},
	{"from": "Pottery Craft", "to": "Mudbrick Construction", "route": "straight"},
	{"from": "Mudbrick Construction", "to": "Counting Marks", "route": "straight"},
	{"from": "Counting Marks", "to": "Glyphic Records", "route": "straight"},
	{"from": "Fishing Methods", "to": "Exoplanet Expedition", "route": "final_bus", "bus_after": 8},
	{"from": "Wheelwrighting", "to": "Exoplanet Expedition", "route": "final_bus", "bus_after": 8},
	{"from": "Simple Levers", "to": "Exoplanet Expedition", "route": "final_bus", "bus_after": 8},
	{"from": "Glyphic Records", "to": "Exoplanet Expedition", "route": "final_bus", "bus_after": 8},
]


static func segment_index_for_column(column_1_indexed: int) -> int:
	return int((column_1_indexed - 1) / 3)


static func local_column_index(column_1_indexed: int) -> int:
	return (column_1_indexed - 1) % 3


## bg3 mirrors slot X positions; canonical C7..C9 labels flip against local 0..2 only.
static func local_column_index_for_node(column_1_indexed: int) -> int:
	var segment_index: int = segment_index_for_column(column_1_indexed)
	var local_col: int = local_column_index(column_1_indexed)
	var slot: int = GridScript.segment_slot_for_index(segment_index)
	if slot >= 0 and GridScript.segment_mirror_grid(slot):
		return GridScript.COLUMN_COUNT - 1 - local_col
	return local_col


static func row_layout_index(row_1_indexed: int) -> int:
	return row_1_indexed - 1


static func layout_for_title(title: String) -> Dictionary:
	return NODE_LAYOUT_BY_TITLE.get(title, {}) as Dictionary


static func layout_for_tech_id(tech_id: String, tech_by_id: Dictionary) -> Dictionary:
	var entry: Dictionary = tech_by_id.get(tech_id, {}) as Dictionary
	if entry.is_empty():
		return {}
	return layout_for_title(str(entry.get("title", "")))


static func prototype_nodes(tech_by_id: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var titles: Array = NODE_LAYOUT_BY_TITLE.keys()
	titles.sort_custom(func(a: String, b: String) -> bool:
		var la: Dictionary = NODE_LAYOUT_BY_TITLE[a]
		var lb: Dictionary = NODE_LAYOUT_BY_TITLE[b]
		var ca: int = int(la.get("column", 0))
		var cb: int = int(lb.get("column", 0))
		if ca != cb:
			return ca < cb
		return int(la.get("row", 0)) < int(lb.get("row", 0))
	)
	var i: int = 0
	while i < titles.size():
		var title: String = str(titles[i])
		var layout: Dictionary = NODE_LAYOUT_BY_TITLE[title]
		var tech_id: String = _tech_id_for_title(title, tech_by_id)
		if tech_id.is_empty():
			i += 1
			continue
		var content: Dictionary = tech_by_id[tech_id] as Dictionary
		out.append({
			"tech_id": tech_id,
			"title": title,
			"column": int(layout["column"]),
			"row": int(layout["row"]),
			"content": content,
		})
		i += 1
	return out


static func total_node_count() -> int:
	return NODE_LAYOUT_BY_TITLE.size()


static func line_stroke_width(viewport_height: float = -1.0) -> float:
	return LINE_STROKE_DESIGN_PX * GridScript.content_scale(viewport_height)


static func tech_item_position_for_node(
	column_1_indexed: int,
	row_1_indexed: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> Vector2:
	var segment_index: int = segment_index_for_column(column_1_indexed)
	var local_col: int = local_column_index_for_node(column_1_indexed)
	var row_in_column: int = row_layout_index(row_1_indexed)
	var slot: int = GridScript.segment_slot_for_index(segment_index)
	var center_grid: bool = GridScript.segment_center_grid(slot) if slot >= 0 else false
	var mirror_grid: bool = GridScript.segment_mirror_grid(slot) if slot >= 0 else false
	return GridScript.tech_item_position(
		segment_index,
		local_col,
		row_in_column,
		segment_display_widths,
		CANONICAL_ROW_COUNT,
		center_grid,
		mirror_grid,
		viewport_height,
	)


static func node_output_point(rect: Rect2) -> Vector2:
	return Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5)


static func node_input_point(rect: Rect2) -> Vector2:
	return Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)


static func bend_x_after_column_scroll(
	after_column_1_indexed: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> float:
	var left_col: int = after_column_1_indexed
	var right_col: int = after_column_1_indexed + 1
	var left_out: Vector2 = tech_item_position_for_node(
		left_col,
		2,
		segment_display_widths,
		viewport_height,
	)
	var right_in: Vector2 = tech_item_position_for_node(
		right_col,
		2,
		segment_display_widths,
		viewport_height,
	)
	var item_w: float = (
		GridScript.TECH_ITEM_DISPLAY_HEIGHT
		* GridScript.TECH_ITEM_WIDTH_PER_HEIGHT
		* GridScript.content_scale(viewport_height)
	)
	var left_edge: float = left_out.x
	var right_edge: float = right_in.x
	return (left_edge + item_w + right_edge) * 0.5


static func final_bus_x_scroll(
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> float:
	return bend_x_after_column_scroll(FINAL_BUS_AFTER_COLUMN, segment_display_widths, viewport_height)


static func build_dependency_polylines(
	rects_by_title: Dictionary,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> Array:
	var stroke: float = line_stroke_width(viewport_height)
	var out: Array = []
	var final_bus_edges: Array = []
	var i: int = 0
	while i < TECH_TREE_EDGES.size():
		var edge: Dictionary = TECH_TREE_EDGES[i]
		var route: String = str(edge.get("route", "straight"))
		if route == "final_bus":
			final_bus_edges.append(edge)
			i += 1
			continue
		var polyline: PackedVector2Array = _polyline_for_edge(
			edge,
			rects_by_title,
			segment_display_widths,
			viewport_height,
		)
		if polyline.size() >= 2:
			out.append({"points": polyline, "width": stroke})
		i += 1
	if not final_bus_edges.is_empty():
		var bus_polylines: Array = _final_bus_polylines(
			final_bus_edges,
			rects_by_title,
			segment_display_widths,
			viewport_height,
			stroke,
		)
		out.append_array(bus_polylines)
	return out


static func _polyline_for_edge(
	edge: Dictionary,
	rects_by_title: Dictionary,
	segment_display_widths: Array,
	viewport_height: float,
) -> PackedVector2Array:
	var from_title: String = str(edge.get("from", ""))
	var to_title: String = str(edge.get("to", ""))
	if not rects_by_title.has(from_title) or not rects_by_title.has(to_title):
		return PackedVector2Array()
	var from_rect: Rect2 = rects_by_title[from_title] as Rect2
	var to_rect: Rect2 = rects_by_title[to_title] as Rect2
	var start: Vector2 = node_output_point(from_rect)
	var end: Vector2 = node_input_point(to_rect)
	var route: String = str(edge.get("route", "straight"))
	if route == "bend":
		var bend_after: int = int(edge.get("bend_after", 0))
		var bend_x: float = bend_x_after_column_scroll(
			bend_after,
			segment_display_widths,
			viewport_height,
		)
		return PackedVector2Array([
			start,
			Vector2(bend_x, start.y),
			Vector2(bend_x, end.y),
			end,
		])
	if absf(start.y - end.y) < 1.0:
		return PackedVector2Array([start, end])
	var mid_x: float = (start.x + end.x) * 0.5
	return PackedVector2Array([
		start,
		Vector2(mid_x, start.y),
		Vector2(mid_x, end.y),
		end,
	])


static func _final_bus_polylines(
	edges: Array,
	rects_by_title: Dictionary,
	segment_display_widths: Array,
	viewport_height: float,
	stroke: float,
) -> Array:
	var target_title: String = "Exoplanet Expedition"
	if not rects_by_title.has(target_title):
		return []
	var target_rect: Rect2 = rects_by_title[target_title] as Rect2
	var target_in: Vector2 = node_input_point(target_rect)
	var bus_x: float = final_bus_x_scroll(segment_display_widths, viewport_height)
	var source_ys: Array[float] = []
	var i: int = 0
	while i < edges.size():
		var from_title: String = str((edges[i] as Dictionary).get("from", ""))
		if rects_by_title.has(from_title):
			var from_rect: Rect2 = rects_by_title[from_title] as Rect2
			source_ys.append(node_output_point(from_rect).y)
		i += 1
	if source_ys.is_empty():
		return []
	source_ys.sort()
	var bus_top: float = source_ys[0]
	var bus_bottom: float = source_ys[source_ys.size() - 1]
	var out: Array = []
	i = 0
	while i < edges.size():
		var from_title: String = str((edges[i] as Dictionary).get("from", ""))
		if not rects_by_title.has(from_title):
			i += 1
			continue
		var from_rect: Rect2 = rects_by_title[from_title] as Rect2
		var start: Vector2 = node_output_point(from_rect)
		out.append({
			"points": PackedVector2Array([start, Vector2(bus_x, start.y)]),
			"width": stroke,
		})
		i += 1
	out.append({
		"points": PackedVector2Array([
			Vector2(bus_x, bus_top),
			Vector2(bus_x, bus_bottom),
		]),
		"width": stroke,
	})
	out.append({
		"points": PackedVector2Array([
			Vector2(bus_x, target_in.y),
			target_in,
		]),
		"width": stroke,
	})
	return out


static func edge_references_valid_titles() -> bool:
	var i: int = 0
	while i < TECH_TREE_EDGES.size():
		var edge: Dictionary = TECH_TREE_EDGES[i]
		var from_title: String = str(edge.get("from", ""))
		var to_title: String = str(edge.get("to", ""))
		if not NODE_LAYOUT_BY_TITLE.has(from_title) or not NODE_LAYOUT_BY_TITLE.has(to_title):
			return false
		i += 1
	return true


static func _tech_id_for_title(title: String, tech_by_id: Dictionary) -> String:
	var keys: Array = tech_by_id.keys()
	var i: int = 0
	while i < keys.size():
		var key: String = str(keys[i])
		var entry: Dictionary = tech_by_id[key] as Dictionary
		if str(entry.get("title", "")) == title:
			return key
		i += 1
	return ""
