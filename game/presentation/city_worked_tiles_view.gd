# Selected-city auto-worked tile markers (Phase 5.1.17e). **read-only**: reads
# **CityYields.yield_breakdown_for_city**(…).worked_tiles **only**. No input, no toggle.
# See docs/RENDERING.md
class_name CityWorkedTilesView
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

## Fraction of **corner→centroid** edge kept (polygon shrinks inward; avoids full-cell fill).
const _INSET_MARKER_FRAC: float = 0.38
const _RING_OUT_FRAC_DELTA: float = 0.06
const _RING_INNER_FRAC_DELTA: float = 0.035

var scenario = null
var layout = null
var camera = null
var selection = null


static func compute_worked_marker_items(p_scenario, p_selection) -> Array:
	var out: Array = []
	if p_scenario == null or p_selection == null:
		return out
	if not p_selection.has_city():
		return out
	var cty = p_scenario.city_by_id(int(p_selection.city_id))
	if cty == null:
		return out
	var bd: Dictionary = CityYieldsScript.yield_breakdown_for_city(p_scenario, cty)
	var src: Array = bd.get("worked_tiles", []) as Array
	var si: int = 0
	while si < src.size():
		var hx = src[si]
		si += 1
		if hx == null:
			continue
		out.append(
			{
				"coord": HexCoordScript.new(hx.q, hx.r),
				"kind": "auto_worked",
			}
		)
	return out


func _presentation_inset_corners_for_hex(q: int, r: int, frac_corner_to_centroid: float) -> PackedVector2Array:
	## Polygon corners pulled **toward hex center** — **fraction of edge** preserved (avoid full-hex fills).
	var w: Vector2 = layout.hex_to_world(q, r)
	var hex_c: PackedVector2Array = layout.hex_corners(w)
	var c_pres: Vector2 = camera.to_presentation(w)
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(6)
	var ik: int = 0
	while ik < 6:
		var wp: Vector2 = hex_c[ik]
		var vp: Vector2 = camera.to_presentation(wp)
		out[ik] = vp.lerp(c_pres, frac_corner_to_centroid)
		ik += 1
	return out


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if scenario == null or layout == null or camera == null or selection == null:
		return
	if not selection.has_city():
		return
	var items: Array = compute_worked_marker_items(scenario, selection)
	var fi: int = 0
	while fi < items.size():
		var ent = items[fi]
		fi += 1
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ent as Dictionary
		var cc = d.get("coord", null)
		if cc == null:
			continue
		var q: int = int(cc.q)
		var r: int = int(cc.r)
		## Aquamarine (**not** amber **territory** / palace warm palette; contrasts **forest** greens).
		var fill_col: Color = Color(0.12, 0.78, 0.88, 0.42)
		var inner: PackedVector2Array = _presentation_inset_corners_for_hex(q, r, _INSET_MARKER_FRAC)
		draw_colored_polygon(inner, fill_col)

		var outer_frac: float = clampf(_INSET_MARKER_FRAC - _RING_OUT_FRAC_DELTA, 0.08, 0.48)
		var outer_pts: PackedVector2Array = _presentation_inset_corners_for_hex(q, r, outer_frac)
		outer_pts.append(outer_pts[0])
		draw_polyline(outer_pts, Color(0.02, 0.35, 0.42, 0.94), 3.85)

		var inner_ring_frac: float = clampf(_INSET_MARKER_FRAC - _RING_INNER_FRAC_DELTA, 0.10, 0.48)
		var inner_pts: PackedVector2Array = _presentation_inset_corners_for_hex(q, r, inner_ring_frac)
		inner_pts.append(inner_pts[0])
		draw_polyline(inner_pts, Color(0.75, 0.98, 1.0, 0.88), 2.15)
