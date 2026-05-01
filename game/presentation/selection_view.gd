# Derived overlay: selected hex ring + legal destination fills. No input; no domain mutation.
# See docs/RENDERING.md, docs/SELECTION.md
class_name SelectionView
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var scenario
var layout
var selection
## Phase 4.5c: shared with MapView / main.
var projection

static func compute_overlay_items(a_scenario, a_layout, a_selection) -> Array:
	assert(HexCoordScript != null)
	assert(MovementRulesScript != null)
	assert(SelectionStateScript != null)
	if a_scenario == null or a_layout == null or a_selection == null:
		return []
	if a_selection.is_empty():
		return []
	var u = a_scenario.unit_by_id(a_selection.unit_id)
	if u == null:
		return []
	var out = []
	var wu = a_layout.hex_to_world(u.position.q, u.position.r)
	var cu = a_layout.hex_corners(wu)
	out.append({
		"kind": "selected_ring",
		"coord": u.position,
		"world": wu,
		"corners": cu,
	})
	var dests = MovementRulesScript.legal_destinations(a_scenario, a_selection.unit_id)
	var j = 0
	while j < dests.size():
		var d = dests[j]
		var w = a_layout.hex_to_world(d.q, d.r)
		out.append({
			"kind": "destination_fill",
			"coord": d,
			"world": w,
			"corners": a_layout.hex_corners(w),
		})
		j = j + 1
	return out

func _ready() -> void:
	if scenario == null:
		scenario = ScenarioScript.make_tiny_test_scenario()
	if layout == null:
		layout = HexLayoutScript.new()
	if selection == null:
		selection = SelectionStateScript.new()
	queue_redraw()

func _draw() -> void:
	if projection == null:
		projection = MapPlaneProjectionScript.new()
	var fill_col = Color(1.0, 1.0, 1.0, 0.20)
	var ring_col = Color(1.0, 1.0, 1.0, 0.95)
	var items = compute_overlay_items(scenario, layout, selection)
	var k = 0
	while k < items.size():
		var item = items[k]
		var corners = item["corners"] as PackedVector2Array
		var corners_p = PackedVector2Array()
		corners_p.resize(corners.size())
		var cidx2 = 0
		while cidx2 < corners.size():
			corners_p[cidx2] = projection.to_presentation(corners[cidx2])
			cidx2 = cidx2 + 1
		if item["kind"] == "destination_fill":
			draw_colored_polygon(corners_p, fill_col)
		elif item["kind"] == "selected_ring":
			var ring_pts = PackedVector2Array()
			var cidx = 0
			while cidx < corners_p.size():
				ring_pts.append(corners_p[cidx])
				cidx = cidx + 1
			ring_pts.append(corners_p[0])
			draw_polyline(ring_pts, ring_col, 3.0)
		k = k + 1
