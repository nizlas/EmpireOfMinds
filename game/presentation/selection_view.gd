# Derived overlay: selected hex ring + legal destination fills. No input; no domain mutation.
# See docs/RENDERING.md, docs/SELECTION.md
class_name SelectionView
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

var scenario
var layout
var selection
## Phase 4.5m: **MapCamera** shared with MapView / main.
var camera
## Slice C8: optional server-provided move destinations (HexCoord list); see compute_overlay_items.
var cloud_destination_coords: Array = []
## Slice C10: optional server-provided attack targets (defender hexes).
var cloud_attack_target_coords: Array = []

static func compute_overlay_items(
	a_scenario,
	a_layout,
	a_selection,
	cloud_dests: Array = [],
	cloud_attack_dests: Array = [],
) -> Array:
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
	var dests: Array = []
	if cloud_dests.size() > 0:
		dests = cloud_dests.duplicate()
	else:
		dests = MovementRulesScript.legal_destinations(a_scenario, a_selection.unit_id)
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
	var atk_dests: Array = []
	if cloud_attack_dests.size() > 0:
		atk_dests = cloud_attack_dests.duplicate()
	var aj = 0
	while aj < atk_dests.size():
		var ad = atk_dests[aj]
		var aw = a_layout.hex_to_world(ad.q, ad.r)
		out.append({
			"kind": "attack_target_fill",
			"coord": ad,
			"world": aw,
			"corners": a_layout.hex_corners(aw),
		})
		aj = aj + 1
	return out

func _draw() -> void:
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var fill_col = Color(1.0, 1.0, 1.0, 0.20)
	var attack_fill_col = Color(0.95, 0.35, 0.30, 0.28)
	var ring_col = Color(1.0, 1.0, 1.0, 0.95)
	var items = compute_overlay_items(
		scenario,
		layout,
		selection,
		cloud_destination_coords,
		cloud_attack_target_coords,
	)
	var k = 0
	while k < items.size():
		var item = items[k]
		var corners = item["corners"] as PackedVector2Array
		var corners_p = PackedVector2Array()
		corners_p.resize(corners.size())
		var cidx2 = 0
		while cidx2 < corners.size():
			corners_p[cidx2] = camera.to_presentation(corners[cidx2])
			cidx2 = cidx2 + 1
		if item["kind"] == "destination_fill":
			draw_colored_polygon(corners_p, fill_col)
		elif item["kind"] == "attack_target_fill":
			draw_colored_polygon(corners_p, attack_fill_col)
		elif item["kind"] == "selected_ring":
			var ring_pts = PackedVector2Array()
			var cidx = 0
			while cidx < corners_p.size():
				ring_pts.append(corners_p[cidx])
				cidx = cidx + 1
			ring_pts.append(corners_p[0])
			draw_polyline(ring_pts, ring_col, 3.0)
		k = k + 1
