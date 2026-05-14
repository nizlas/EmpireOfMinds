# Always-on **empire** outline (Phase **5.1.17h**, strength correction **5.1.17h.1**): union of **`City.owned_tiles`** per **`owner_id`**; outer perimeter only.

# Visual strength matches legacy **`CityTerritoryView`** **outer + inner** rim (owner-colored outer + indigo inset inner); selection-independent.

# Read-only **`Scenario`** / **`HexLayout`** / **`MapCamera`** — **no** **`SelectionState`**, **no** **`CityYields`**, **no** worked tiles.

# Perimeter topology via **`CityTerritoryView`** static helpers (**half-edges**, loop trace).

# See **[RENDERING.md](../../docs/RENDERING.md)**, **[CITY_UX.md](../../docs/CITY_UX.md)**.

class_name EmpireBorderView

extends Node2D



const CityTerritoryViewScript = preload("res://presentation/city_territory_view.gd")

const MapCameraScript = preload("res://presentation/map_camera.gd")

const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")



## Matches **`CityTerritoryView`** **`_OUTER_ALPHA`** / **`_INNER_ALPHA`** / **`_INNER_WIDTH_FRAC`** for identical rim weight.

const EMPIRE_OUTER_ALPHA: float = 0.94

const EMPIRE_INNER_ALPHA: float = 0.92

const EMPIRE_INNER_WIDTH_FRAC: float = 0.44



var scenario = null

var layout = null

var camera = null



var _perim_line_outer: Array = []

var _perim_line_inner: Array = []





static func distinct_sorted_owner_ids(p_scenario) -> Array:

	var out: Array = []

	if p_scenario == null:

		return out

	var seen: Dictionary = {}

	var cs: Array = p_scenario.cities()

	var ci: int = 0

	while ci < cs.size():

		var cty = cs[ci]

		var oid: int = int(cty.owner_id)

		if not seen.has(oid):

			seen[oid] = true

			out.append(oid)

		ci += 1

	out.sort()

	return out





static func empire_union_owned_coords_for_owner(p_scenario, owner_id: int) -> Array:

	var out: Array = []

	if p_scenario == null:

		return out

	var seen: Dictionary = {}

	var cs: Array = p_scenario.cities()

	var ci: int = 0

	while ci < cs.size():

		var cty = cs[ci]

		if int(cty.owner_id) != owner_id:

			ci += 1

			continue

		var ot: Array = cty.owned_tiles

		var ti: int = 0

		while ti < ot.size():

			var en = ot[ti]

			var ax = CityTerritoryViewScript.try_axial_from_owned_tile_entry(en)

			if ax == null:

				ti += 1

				continue

			var v: Vector2i = ax as Vector2i

			var k: String = "%d,%d" % [v.x, v.y]

			if seen.has(k):

				ti += 1

				continue

			seen[k] = true

			out.append(en)

			ti += 1

		ci += 1

	return out





static func empire_border_half_edge_count_for_owner(p_scenario, owner_id: int) -> int:

	var coords: Array = empire_union_owned_coords_for_owner(p_scenario, owner_id)

	return CityTerritoryViewScript.territory_border_edge_count(coords)





static func empire_border_axial_signature_for_owner(p_scenario, owner_id: int) -> String:

	var coords: Array = empire_union_owned_coords_for_owner(p_scenario, owner_id)

	return CityTerritoryViewScript.territory_perimeter_axial_signature(coords)





static func empire_topology_fingerprint(p_scenario) -> String:

	var ids: Array = distinct_sorted_owner_ids(p_scenario)

	var parts: Array = []

	var ii: int = 0

	while ii < ids.size():

		var oid: int = int(ids[ii])

		parts.append("%d:%s" % [oid, empire_border_axial_signature_for_owner(p_scenario, oid)])

		ii += 1

	var out: String = ""

	var pj: int = 0

	while pj < parts.size():

		if pj > 0:

			out += ";"

		out += str(parts[pj])

		pj += 1

	return out





static func empire_outer_color_for_owner(owner_id: int) -> Color:

	var base: Color = UnitNameplateViewScript.owner_nameplate_accent_color(owner_id)

	return Color(base.r, base.g, base.b, EMPIRE_OUTER_ALPHA)





static func empire_inner_stroke_color() -> Color:

	var inner_base: Color = CityTerritoryViewScript.territory_inner_stroke_color()

	return Color(inner_base.r, inner_base.g, inner_base.b, EMPIRE_INNER_ALPHA)





static func presentation_outer_points_for_loop(p_cam, edges: Array, loop: Array) -> PackedVector2Array:

	var pts: PackedVector2Array = PackedVector2Array()

	var j: int = 0

	while j < loop.size():

		var e: Dictionary = edges[int(loop[j])] as Dictionary

		pts.append(p_cam.to_presentation(e["wa"] as Vector2))

		j += 1

	return pts





static func presentation_inner_points_for_loop(p_cam, p_layout, inset_px: float, edges: Array, loop: Array) -> PackedVector2Array:

	var pts: PackedVector2Array = PackedVector2Array()

	var n: int = loop.size()

	var j: int = 0

	while j < n:

		var e_prev: Dictionary = edges[int(loop[(j - 1 + n) % n])] as Dictionary

		var e_cur: Dictionary = edges[int(loop[j])] as Dictionary

		pts.append(

			CityTerritoryViewScript.territory_inner_corner_offset_presentation(

				p_cam, p_layout, inset_px, e_prev, e_cur

			)

		)

		j += 1

	return pts





static func hex_world_centroid_from_coords(p_layout, coords: Array) -> Vector2:

	if p_layout == null or coords.is_empty():

		return Vector2.ZERO

	var acc: Vector2 = Vector2.ZERO

	var n: int = 0

	var i: int = 0

	while i < coords.size():

		var ax = CityTerritoryViewScript.try_axial_from_owned_tile_entry(coords[i])

		if ax == null:

			i += 1

			continue

		var v: Vector2i = ax as Vector2i

		acc += p_layout.hex_to_world(v.x, v.y)

		n += 1

		i += 1

	if n <= 0:

		return Vector2.ZERO

	return acc / float(n)





func _hide_line_pairs_from(idx: int) -> void:

	var i: int = idx

	while i < _perim_line_outer.size():

		(_perim_line_outer[i] as Line2D).visible = false

		(_perim_line_inner[i] as Line2D).visible = false

		i += 1





func _ensure_line_pairs_needed(need: int) -> void:

	while _perim_line_outer.size() < need:

		var lo: Line2D = Line2D.new()

		lo.closed = true

		lo.joint_mode = Line2D.LINE_JOINT_ROUND

		lo.begin_cap_mode = Line2D.LINE_CAP_NONE

		lo.end_cap_mode = Line2D.LINE_CAP_NONE

		lo.antialiased = true

		lo.z_index = 0

		var li_ln: Line2D = Line2D.new()

		li_ln.closed = true

		li_ln.joint_mode = Line2D.LINE_JOINT_ROUND

		li_ln.begin_cap_mode = Line2D.LINE_CAP_NONE

		li_ln.end_cap_mode = Line2D.LINE_CAP_NONE

		li_ln.antialiased = true

		li_ln.z_index = 1

		add_child(lo)

		add_child(li_ln)

		_perim_line_outer.append(lo)

		_perim_line_inner.append(li_ln)





func _ready() -> void:

	queue_redraw()





func _draw() -> void:

	if scenario == null or layout == null:

		_hide_line_pairs_from(0)

		return

	if camera == null:

		var cam = MapCameraScript.new()

		cam.projection = MapPlaneProjectionScript.new()

		camera = cam

	var edge_tab: PackedByteArray = CityTerritoryViewScript.edge_index_table_for_layout(layout)



	var tasks_outer_pts: Array = []

	var tasks_inner_pts: Array = []

	var tasks_outer_w: Array = []

	var tasks_inner_w: Array = []

	var tasks_outer_col: Array = []

	var tasks_inner_col: Array = []

	var owner_ids: Array = distinct_sorted_owner_ids(scenario)

	var oi: int = 0

	while oi < owner_ids.size():

		var oid: int = int(owner_ids[oi])

		var coords: Array = empire_union_owned_coords_for_owner(scenario, oid)

		if coords.is_empty():

			oi += 1

			continue

		var edges: Array = CityTerritoryViewScript.territory_perimeter_world_segments_detailed(

			layout, coords, edge_tab

		)

		var loops: Array = CityTerritoryViewScript.trace_territory_perimeter_loops_edge_indices(edges)

		var wc: Vector2 = hex_world_centroid_from_coords(layout, coords)

		var psc: float = camera.perspective_scale_at(wc)

		var outer_w: float = clampf(

			CityTerritoryViewScript.TERRITORY_OUTER_W_MUL * psc,

			CityTerritoryViewScript.TERRITORY_OUTER_W_MIN,

			CityTerritoryViewScript.TERRITORY_OUTER_W_MAX,

		)

		var inner_w: float = maxf(outer_w * EMPIRE_INNER_WIDTH_FRAC, 4.0)

		var inset_px: float = clampf(

			CityTerritoryViewScript.TERRITORY_INNER_INSET_FRAC * outer_w,

			CityTerritoryViewScript.TERRITORY_INNER_INSET_MIN,

			CityTerritoryViewScript.TERRITORY_INNER_INSET_MAX,

		)

		var outer_rgb: Color = empire_outer_color_for_owner(oid)

		var inner_col: Color = empire_inner_stroke_color()



		var li: int = 0

		while li < loops.size():

			var loop_one: Array = loops[li] as Array

			var outer_pts: PackedVector2Array = presentation_outer_points_for_loop(camera, edges, loop_one)

			var inner_pts: PackedVector2Array = presentation_inner_points_for_loop(

				camera, layout, inset_px, edges, loop_one

			)

			tasks_outer_pts.append(outer_pts)

			tasks_inner_pts.append(inner_pts)

			tasks_outer_w.append(outer_w)

			tasks_inner_w.append(inner_w)

			tasks_outer_col.append(outer_rgb)

			tasks_inner_col.append(inner_col)

			li += 1

		oi += 1



	var need: int = tasks_outer_pts.size()

	_ensure_line_pairs_needed(need)

	var tk: int = 0

	while tk < need:

		var lo: Line2D = _perim_line_outer[tk] as Line2D

		var li_ln: Line2D = _perim_line_inner[tk] as Line2D

		lo.points = tasks_outer_pts[tk] as PackedVector2Array

		lo.width = float(tasks_outer_w[tk])

		lo.default_color = tasks_outer_col[tk] as Color

		lo.visible = true

		li_ln.points = tasks_inner_pts[tk] as PackedVector2Array

		li_ln.width = float(tasks_inner_w[tk])

		li_ln.default_color = tasks_inner_col[tk] as Color

		li_ln.visible = true

		tk += 1

	_hide_line_pairs_from(need)


