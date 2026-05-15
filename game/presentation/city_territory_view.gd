# Selected-city territory outline (Phase 5.1.16i). **read-only** domain; **MapCamera** / **HexLayout** anchored.
# **Design correction:** **`EmpireBorderView`** is the **only** realm/faction **border-like** outline (**selection-independent**). Tiles owned by the **selected** city must **not** be shown with a **second perimeter stroke** — ownership/work intent belongs on **citizen / head markers** per hex (**dim** = city-owned, **not** worked; **highlighted** = worked; **swap** glyph later). **`CityTerritoryView`** **`_draw`** stays **dormant** (no visible rim in normal or city-selected mode); **`Line2D`** pool + static perimeter helpers remain for **`EmpireBorderView`** / tests only unless a future slice deliberately revives rim drawing.
# Perimeter **topology** static API remains for tests and **`EmpireBorderView`** reuse; closed loops **are** **traced** via **logical corner adjacency** (layout **world** keys — camera-independent). **No** screen-space
# sorting, **no** centroid angle order, **no** global polygon triangulation. **Line2D** continuous stroked paths with
# **round joints** (no default **joint dots** / rivets). **Debug** endpoint caps remain **opt-in** only.
# See docs/RENDERING.md
class_name CityTerritoryView
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")

## **Axial neighbor direction** `d` (**`HexCoord.Direction`** **E=0 … SE=5**) → **hex edge index** `i` (**`hex_corners[i]`→`[(i+1)%6]`**).
static var _edge_index_by_axial_direction_cache: PackedByteArray = PackedByteArray()
static var _PINNED_EDGE_INDEX_BY_AXIAL_DIRECTION: PackedByteArray = PackedByteArray([5, 4, 3, 2, 1, 0])

## **Lattice** vertex key (**world** space from **HexLayout** only — **pan/zoom** does not affect it).
const WORLD_VERTEX_KEY_MUL: float = 1024.0

## Stroke scale — pinned in tests.
const TERRITORY_OUTER_W_MUL: float = 11.0
const TERRITORY_OUTER_W_MIN: float = 9.0
const TERRITORY_OUTER_W_MAX: float = 44.0

## Debug-only round caps — **never** used on the normal **`Line2D`** path.
const TERRITORY_DEBUG_CAP_RADIUS_FRAC_OUTER: float = 0.52
const TERRITORY_DEBUG_CAP_RADIUS_FRAC_INNER: float = 0.48

## Inward shift (**presentation px**) for the indigo stroke ≈ **`outer_w *`** (clamped in `_draw`).
const TERRITORY_INNER_INSET_FRAC: float = 0.40
const TERRITORY_INNER_INSET_MIN: float = 2.5
const TERRITORY_INNER_INSET_MAX: float = 24.0

const _ENV_DEBUG_CAPS: String = "EOM_DEBUG_CITY_TERRITORY_CAPS"

static func territory_fills_owned_tiles() -> bool:
	return false

static func territory_inner_stroke_color() -> Color:
	return Color(0.10, 0.09, 0.26, 0.94)

const _OUTER_ALPHA: float = 0.94
const _INNER_ALPHA: float = 0.92
const _INNER_WIDTH_FRAC: float = 0.44

@export var debug_log_city_territory: bool = false
@export var debug_force_visible_style: bool = false
@export var debug_draw_territory_endpoint_caps: bool = false

const _ENV_DEBUG_LOG: String = "EOM_DEBUG_CITY_TERRITORY"
const _ENV_DEBUG_VISIBLE: String = "EOM_DEBUG_CITY_TERRITORY_VISIBLE"

const _DBG_OUTER_W_MIN: float = 14.0
const _DBG_OUTER_W_MAX: float = 28.0
const _DBG_INNER_FRAC: float = 0.48

var scenario = null
var layout = null
var camera = null
var selection = null

var _perim_line_outer: Array = []
var _perim_line_inner: Array = []


static func _coord_key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


static func world_corner_key(w: Vector2) -> String:
	var xi: int = int(roundf(w.x * WORLD_VERTEX_KEY_MUL))
	var yi: int = int(roundf(w.y * WORLD_VERTEX_KEY_MUL))
	return "%d,%d" % [xi, yi]


## **Unit** perpendicular to edge **ab** (tests / inward fallback).
static func inward_unit_normal_for_edge(a: Vector2, b: Vector2, toward_point: Vector2) -> Vector2:
	var mid: Vector2 = (a + b) * 0.5
	var edge: Vector2 = b - a
	var el: float = edge.length()
	if el < 1e-6:
		return Vector2.ZERO
	var u: Vector2 = edge / el
	var n: Vector2 = Vector2(-u.y, u.x)
	if n.dot(toward_point - mid) < 0.0:
		n = -n
	return n


## **Unit** vector from **segment midpoint** toward **owning tile center** in **presentation** space.
static func territory_inward_unit_presentation(
	p_cam, p_layout, owner_q: int, owner_r: int, wa_world: Vector2, wb_world: Vector2
) -> Vector2:
	if p_cam == null or p_layout == null:
		return Vector2.ZERO
	var pa: Vector2 = p_cam.to_presentation(wa_world)
	var pb: Vector2 = p_cam.to_presentation(wb_world)
	var mid: Vector2 = (pa + pb) * 0.5
	var cw: Vector2 = p_layout.hex_to_world(owner_q, owner_r)
	var c_pres: Vector2 = p_cam.to_presentation(cw)
	var to_center: Vector2 = c_pres - mid
	if to_center.length_squared() < 1e-12:
		return inward_unit_normal_for_edge(pa, pb, c_pres)
	return to_center.normalized()


static func average_presentation_inward_vectors(in_list: Array) -> Vector2:
	if in_list.is_empty():
		return Vector2.ZERO
	var s: Vector2 = Vector2.ZERO
	var i: int = 0
	while i < in_list.size():
		s += in_list[i] as Vector2
		i += 1
	if s.length_squared() < 1e-12:
		return in_list[0] as Vector2
	return s.normalized()


## **Inner** stroke offset at a **perimeter corner** (two incident half-edges) in **presentation** space.
static func territory_inner_corner_offset_presentation(
	p_cam, p_layout, inset_px: float, e_prev: Dictionary, e_cur: Dictionary
) -> Vector2:
	var wa: Vector2 = e_cur["wa"] as Vector2
	var pa: Vector2 = p_cam.to_presentation(wa)
	var qp: int = int(e_prev["q"])
	var rp: int = int(e_prev["r"])
	var wap: Vector2 = e_prev["wa"] as Vector2
	var wbp: Vector2 = e_prev["wb"] as Vector2
	var qc: int = int(e_cur["q"])
	var rc: int = int(e_cur["r"])
	var wac: Vector2 = e_cur["wa"] as Vector2
	var wbc: Vector2 = e_cur["wb"] as Vector2
	var in_prev: Vector2 = territory_inward_unit_presentation(p_cam, p_layout, qp, rp, wap, wbp)
	var in_cur: Vector2 = territory_inward_unit_presentation(p_cam, p_layout, qc, rc, wac, wbc)
	var avg_in: Vector2 = average_presentation_inward_vectors([in_prev, in_cur])
	return pa + avg_in * inset_px


static func try_axial_from_owned_tile_entry(entry) -> Variant:
	if entry == null or typeof(entry) != TYPE_OBJECT:
		return null
	return Vector2i(int(entry.q), int(entry.r))


static func owned_key_set_from_coords(owned_coords: Array) -> Dictionary:
	var s: Dictionary = {}
	var i: int = 0
	while i < owned_coords.size():
		var ax = try_axial_from_owned_tile_entry(owned_coords[i])
		if ax != null:
			var v: Vector2i = ax as Vector2i
			s[_coord_key(v.x, v.y)] = true
		i += 1
	return s


static func neighbor_qr(q: int, r: int, direction: int) -> Vector2i:
	var off: Vector2i = HexCoordScript.DIRECTIONS[direction]
	return Vector2i(q + off.x, r + off.y)


static func _compute_edge_index_for_axial_direction(p_layout, q: int, r: int, direction: int) -> int:
	var C0: Vector2 = p_layout.hex_to_world(q, r)
	var nb: Vector2i = neighbor_qr(q, r, direction)
	var C1: Vector2 = p_layout.hex_to_world(nb.x, nb.y)
	var shared_mid: Vector2 = (C0 + C1) * 0.5
	var corners: PackedVector2Array = p_layout.hex_corners(C0)
	var best_i: int = 0
	var best_ds: float = INF
	var i: int = 0
	while i < 6:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 6]
		var close: Vector2 = Geometry2D.get_closest_point_to_segment(shared_mid, a, b)
		var ds: float = shared_mid.distance_squared_to(close)
		if ds < best_ds:
			best_ds = ds
			best_i = i
		i += 1
	return best_i


static func edge_index_table_for_layout(p_layout) -> PackedByteArray:
	if p_layout == null:
		return _PINNED_EDGE_INDEX_BY_AXIAL_DIRECTION
	if _edge_index_by_axial_direction_cache.size() == 6:
		return _edge_index_by_axial_direction_cache
	var out: PackedByteArray = PackedByteArray()
	var d: int = 0
	while d < 6:
		out.append(_compute_edge_index_for_axial_direction(p_layout, 0, 0, d))
		d += 1
	_edge_index_by_axial_direction_cache = out
	return out


static func verify_pinned_axial_edge_table_matches_layout(p_layout) -> bool:
	if p_layout == null:
		return false
	var fresh: PackedByteArray = PackedByteArray()
	var d2: int = 0
	while d2 < 6:
		fresh.append(_compute_edge_index_for_axial_direction(p_layout, 0, 0, d2))
		d2 += 1
	var i3: int = 0
	while i3 < 6:
		if int(fresh[i3]) != int(_PINNED_EDGE_INDEX_BY_AXIAL_DIRECTION[i3]):
			return false
		i3 += 1
	return true


static func territory_border_edge_count(owned_coords: Array) -> int:
	var s: Dictionary = owned_key_set_from_coords(owned_coords)
	if s.is_empty():
		return 0
	var n: int = 0
	for key in s:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue
		var q: int = int(parts[0])
		var r: int = int(parts[1])
		var d: int = 0
		while d < 6:
			var nb: Vector2i = neighbor_qr(q, r, d)
			if not s.has(_coord_key(nb.x, nb.y)):
				n += 1
			d += 1
	return n


## Sorted **`"q,r,dir"`** perimeter half-edges — **camera-independent** topology signature.
static func territory_perimeter_axial_signature(owned_coords: Array) -> String:
	var s: Dictionary = owned_key_set_from_coords(owned_coords)
	if s.is_empty():
		return ""
	var keys: Array = []
	for hk in s:
		var parts: PackedStringArray = hk.split(",")
		if parts.size() != 2:
			continue
		var q: int = int(parts[0])
		var r: int = int(parts[1])
		var d: int = 0
		while d < 6:
			var nb: Vector2i = neighbor_qr(q, r, d)
			if not s.has(_coord_key(nb.x, nb.y)):
				keys.append("%d,%d,%d" % [q, r, d])
			d += 1
	keys.sort()
	var out: String = ""
	var ki: int = 0
	while ki < keys.size():
		if ki > 0:
			out += ";"
		out += keys[ki]
		ki += 1
	return out


## **Perimeter vertex** key (**`world_corner_key`**) → endpoint touches count (expect **2** on a simple ring).
static func territory_perimeter_vertex_valence_by_key(p_layout, owned_coords: Array, edge_tab: PackedByteArray) -> Dictionary:
	var s: Dictionary = owned_key_set_from_coords(owned_coords)
	var counts: Dictionary = {}
	if s.is_empty() or p_layout == null:
		return counts
	for hk in s:
		var parts: PackedStringArray = hk.split(",")
		if parts.size() != 2:
			continue
		var q: int = int(parts[0])
		var r: int = int(parts[1])
		var wc: Vector2 = p_layout.hex_to_world(q, r)
		var corn2: PackedVector2Array = p_layout.hex_corners(wc)
		var d: int = 0
		while d < 6:
			var nb: Vector2i = neighbor_qr(q, r, d)
			if s.has(_coord_key(nb.x, nb.y)):
				d += 1
				continue
			var ei: int = int(edge_tab[d])
			var wa: Vector2 = corn2[ei]
			var wb: Vector2 = corn2[(ei + 1) % 6]
			var ka: String = world_corner_key(wa)
			var kb: String = world_corner_key(wb)
			counts[ka] = int(counts.get(ka, 0)) + 1
			counts[kb] = int(counts.get(kb, 0)) + 1
			d += 1
	return counts


static func territory_join_topology_signature(p_layout, owned_coords: Array, edge_tab: PackedByteArray) -> String:
	var v: Dictionary = territory_perimeter_vertex_valence_by_key(p_layout, owned_coords, edge_tab)
	var ks: Array = v.keys()
	ks.sort()
	var out: String = ""
	var ki: int = 0
	while ki < ks.size():
		if ki > 0:
			out += ";"
		out += "%s=%d" % [str(ks[ki]), int(v[ks[ki]])]
		ki += 1
	return out


static func territory_perimeter_world_corner_key_count(p_layout, owned_coords: Array, edge_tab: PackedByteArray) -> int:
	var s: Dictionary = owned_key_set_from_coords(owned_coords)
	if s.is_empty() or p_layout == null:
		return 0
	var corners: Dictionary = {}
	for hk in s:
		var parts: PackedStringArray = hk.split(",")
		if parts.size() != 2:
			continue
		var q: int = int(parts[0])
		var r: int = int(parts[1])
		var wc: Vector2 = p_layout.hex_to_world(q, r)
		var corn2: PackedVector2Array = p_layout.hex_corners(wc)
		var d: int = 0
		while d < 6:
			var nb: Vector2i = neighbor_qr(q, r, d)
			if s.has(_coord_key(nb.x, nb.y)):
				d += 1
				continue
			var ei: int = int(edge_tab[d])
			var wa: Vector2 = corn2[ei]
			var wb: Vector2 = corn2[(ei + 1) % 6]
			corners[world_corner_key(wa)] = true
			corners[world_corner_key(wb)] = true
			d += 1
	return corners.size()


## Perimeter half-edges in **axial signature order** with **world** endpoints + **layout** corner keys (**`ka`→`kb`** along owned tile boundary).
static func territory_perimeter_world_segments_detailed(p_layout, owned_coords: Array, edge_tab: PackedByteArray) -> Array:
	var sig: String = territory_perimeter_axial_signature(owned_coords)
	if sig.is_empty() or p_layout == null:
		return []
	var out: Array = []
	for token in sig.split(";"):
		var bits: PackedStringArray = token.split(",")
		if bits.size() != 3:
			continue
		var q: int = int(bits[0])
		var r: int = int(bits[1])
		var d: int = int(bits[2])
		var wc: Vector2 = p_layout.hex_to_world(q, r)
		var corn2: PackedVector2Array = p_layout.hex_corners(wc)
		var ei: int = int(edge_tab[d])
		var wa: Vector2 = corn2[ei]
		var wb: Vector2 = corn2[(ei + 1) % 6]
		out.append(
			{
				"q": q,
				"r": r,
				"dir": d,
				"wa": wa,
				"wb": wb,
				"ka": world_corner_key(wa),
				"kb": world_corner_key(wb),
			}
		)
	return out


## **Trace** closed loops: each loop is an **Array** of **indices** into **`edges`** (only **corner adjacency** **`kb`→`ka`**).
static func trace_territory_perimeter_loops_edge_indices(edges: Array) -> Array:
	var edge_count: int = edges.size()
	if edge_count == 0:
		return []
	var outgoing: Dictionary = {}
	var bi: int = 0
	while bi < edge_count:
		var e: Dictionary = edges[bi] as Dictionary
		var ka: String = str(e["ka"])
		if not outgoing.has(ka):
			outgoing[ka] = []
		(outgoing[ka] as Array).append(bi)
		bi += 1
	var visited: Array = []
	visited.resize(edge_count)
	var bj: int = 0
	while bj < edge_count:
		visited[bj] = false
		bj += 1
	var all_loops: Array = []
	var s: int = 0
	while s < edge_count:
		if visited[s]:
			s += 1
			continue
		var loop_e: Array = []
		var cur: int = s
		while true:
			if visited[cur]:
				break
			visited[cur] = true
			loop_e.append(cur)
			var ek: Dictionary = edges[cur] as Dictionary
			var end_key: String = str(ek["kb"])
			var start_key: String = str(edges[s]["ka"])
			if end_key == start_key and loop_e.size() > 1:
				break
			var cand: Array = outgoing.get(end_key, []) as Array
			var nxt: int = -1
			var best: int = 2147483647
			var ck: int = 0
			while ck < cand.size():
				var cid: int = int(cand[ck])
				if not visited[cid] and cid < best:
					best = cid
					nxt = cid
				ck += 1
			if nxt < 0:
				push_warning("CityTerritoryView: broken perimeter at corner %s" % end_key)
				break
			cur = nxt
		all_loops.append(loop_e)
		s += 1
	return all_loops


static func territory_perimeter_loops_connect_adjacent_half_edges(edges: Array, loops: Array) -> bool:
	var li: int = 0
	while li < loops.size():
		var loop: Array = loops[li] as Array
		var n: int = loop.size()
		if n < 3:
			return false
		var t: int = 0
		while t < n:
			var e0: Dictionary = edges[int(loop[t])] as Dictionary
			var e1: Dictionary = edges[int(loop[(t + 1) % n])] as Dictionary
			if str(e0["kb"]) != str(e1["ka"]):
				return false
			t += 1
		li += 1
	return true


static func _canonical_rotate_loop_tokens(tokens: Array) -> String:
	var n: int = tokens.size()
	if n == 0:
		return ""
	var best: String = ""
	var rot: int = 0
	while rot < n:
		var cand: String = ""
		var k: int = 0
		while k < n:
			if k > 0:
				cand += "|"
			cand += str(tokens[(rot + k) % n])
			k += 1
		if best.is_empty() or cand < best:
			best = cand
		rot += 1
	return best


## **Stable** fingerprint for **loop set**: each loop **canonical rotation** of **`q,r,d`** chain; **loops** sorted lexicographically.
static func territory_perimeter_loops_axial_signature(edges: Array, loops: Array) -> String:
	var loop_strs: Array = []
	var li: int = 0
	while li < loops.size():
		var loop: Array = loops[li] as Array
		var tokens: Array = []
		var lj: int = 0
		while lj < loop.size():
			var e: Dictionary = edges[int(loop[lj])] as Dictionary
			tokens.append("%d,%d,%d" % [int(e["q"]), int(e["r"]), int(e["dir"])])
			lj += 1
		loop_strs.append(_canonical_rotate_loop_tokens(tokens))
		li += 1
	loop_strs.sort()
	var out: String = ""
	var si: int = 0
	while si < loop_strs.size():
		if si > 0:
			out += ";"
		out += str(loop_strs[si])
		si += 1
	return out


static func territory_traced_loop_edge_count_total(loops: Array) -> int:
	var sum: int = 0
	var i: int = 0
	while i < loops.size():
		sum += (loops[i] as Array).size()
		i += 1
	return sum


static func hex_edge_world_length(p_layout) -> float:
	if p_layout == null:
		return 0.0
	var c0: Vector2 = p_layout.hex_to_world(0, 0)
	var corn: PackedVector2Array = p_layout.hex_corners(c0)
	return corn[0].distance_to(corn[1])


static func perimeter_segments_are_local_hex_edges(p_layout, owned_coords: Array, edge_tab: PackedByteArray) -> bool:
	var s: Dictionary = owned_key_set_from_coords(owned_coords)
	if s.is_empty():
		return true
	var el: float = hex_edge_world_length(p_layout)
	if el < 1e-6:
		return false
	var tol: float = 0.02 * el
	for hk in s:
		var parts: PackedStringArray = hk.split(",")
		if parts.size() != 2:
			continue
		var q: int = int(parts[0])
		var r: int = int(parts[1])
		var wc: Vector2 = p_layout.hex_to_world(q, r)
		var corn2: PackedVector2Array = p_layout.hex_corners(wc)
		var d: int = 0
		while d < 6:
			var nb: Vector2i = neighbor_qr(q, r, d)
			if s.has(_coord_key(nb.x, nb.y)):
				d += 1
				continue
			var ei: int = int(edge_tab[d])
			var len: float = corn2[ei].distance_to(corn2[(ei + 1) % 6])
			if absf(len - el) > tol:
				return false
			d += 1
	return true


static func territory_accent_color_for_city(p_scenario, city_id: int) -> Color:
	if p_scenario == null or city_id < 0:
		return Color(0.55, 0.55, 0.55, 1.0)
	var cty = p_scenario.city_by_id(city_id)
	if cty == null:
		return Color(0.55, 0.55, 0.55, 1.0)
	return UnitNameplateViewScript.owner_nameplate_accent_color(int(cty.owner_id))


static func territory_outer_color_for_city(p_scenario, city_id: int) -> Color:
	var c: Color = territory_accent_color_for_city(p_scenario, city_id)
	return Color(c.r, c.g, c.b, _OUTER_ALPHA)


static func _hex_world_center(p_layout, q: int, r: int) -> Vector2:
	if p_layout == null:
		return Vector2.ZERO
	return p_layout.hex_to_world(q, r)


func _env_truthy(key: String) -> bool:
	var v: String = OS.get_environment(key)
	if v.is_empty():
		return false
	var t: String = v.strip_edges().to_lower()
	return t == "1" or t == "true" or t == "yes" or t == "on"


func _want_debug_log() -> bool:
	return debug_log_city_territory or _env_truthy(_ENV_DEBUG_LOG)


func _want_debug_visible() -> bool:
	return debug_force_visible_style or _env_truthy(_ENV_DEBUG_VISIBLE)


func _want_debug_territory_caps() -> bool:
	return debug_draw_territory_endpoint_caps or _env_truthy(_ENV_DEBUG_CAPS)


func _hide_territory_lines_from(idx: int) -> void:
	var i: int = idx
	while i < _perim_line_outer.size():
		(_perim_line_outer[i] as Line2D).visible = false
		(_perim_line_inner[i] as Line2D).visible = false
		i += 1


func _ensure_territory_line_pairs_needed(need: int) -> void:
	while _perim_line_outer.size() < need:
		var lo: Line2D = Line2D.new()
		lo.closed = true
		lo.joint_mode = Line2D.LINE_JOINT_ROUND
		lo.begin_cap_mode = Line2D.LINE_CAP_NONE
		lo.end_cap_mode = Line2D.LINE_CAP_NONE
		lo.antialiased = true
		lo.z_index = 0
		var li: Line2D = Line2D.new()
		li.closed = true
		li.joint_mode = Line2D.LINE_JOINT_ROUND
		li.begin_cap_mode = Line2D.LINE_CAP_NONE
		li.end_cap_mode = Line2D.LINE_CAP_NONE
		li.antialiased = true
		li.z_index = 1
		add_child(lo)
		add_child(li)
		_perim_line_outer.append(lo)
		_perim_line_inner.append(li)


func _presentation_outer_points_for_loop(edges: Array, loop: Array) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var j: int = 0
	while j < loop.size():
		var e: Dictionary = edges[int(loop[j])] as Dictionary
		pts.append(camera.to_presentation(e["wa"] as Vector2))
		j += 1
	return pts


func _presentation_inner_points_for_loop(edges: Array, loop: Array, inset_px: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = loop.size()
	var j: int = 0
	while j < n:
		var e_prev: Dictionary = edges[int(loop[(j - 1 + n) % n])] as Dictionary
		var e_cur: Dictionary = edges[int(loop[j])] as Dictionary
		pts.append(territory_inner_corner_offset_presentation(camera, layout, inset_px, e_prev, e_cur))
		j += 1
	return pts


func _debug_draw_territory_endpoint_caps_if_enabled(
	cap_outer: Dictionary, cap_inner: Dictionary, r_o: float, r_i: float, outer_rgb: Color, inner_col: Color
) -> void:
	if not _want_debug_territory_caps():
		return
	for k in cap_outer:
		draw_circle(cap_outer[k] as Vector2, r_o, outer_rgb)
	for k2 in cap_inner:
		draw_circle(cap_inner[k2] as Vector2, r_i, inner_col)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var dbg_log: bool = _want_debug_log()
	_hide_territory_lines_from(0)

	if scenario == null or layout == null:
		if dbg_log:
			print(
				"[EOM_CITY_TERRITORY] visible=%s scenario=%s layout=%s camera=%s selection=%s has_city=%s city_id=%s … (early)" % [
					str(visible),
					str(scenario != null),
					str(layout != null),
					str(camera != null),
					str(selection != null),
					str(selection.has_city() if selection != null else false),
					str(selection.city_id if selection != null else -999),
				]
			)
		return

	if dbg_log:
		var hc: bool = selection.has_city() if selection != null else false
		var cid: int = int(selection.city_id) if hc else -999
		print(
			(
				"[EOM_CITY_TERRITORY] dormant=true (realm outline is EmpireBorderView); "
				+ "selection_has_city=%s city_id=%s — no selected-city border rim"
			)
			% [str(hc), str(cid)]
		)
	return
