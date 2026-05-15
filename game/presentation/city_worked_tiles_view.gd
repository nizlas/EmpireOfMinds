# Selected-city **citizen / head** markers (**Phase 5.1.17j**, draw gate **5.1.17j.1**). File/class **`CityWorkedTilesView`** retained to avoid scene/rename churn.
# **read-only**: **`City.owned_tiles`**, **`CityYields.yield_breakdown_for_city`(..).`worked_tiles`** — **no** presentation-side recomputation of which tiles are worked.
# **v0:** **no** marker on the **city center** hex (city marker / nameplate already identifies it).
# **`_draw`** and **`compute_draw_marker_items`** run **only** when **`CityViewState`** is **PLANNING** (**Manage Citizens**). **City-selected NORMAL** = **City Hub** only, **no** citizen markers.
# **v0:** **only** **`draw_texture_rect`** citizen marker PNGs — **no** per-tile hex **polygon** **fills** / translucent tints (overlapping alpha reads as **seams** on **painterly** terrain).
# No input. See **[RENDERING.md](../../docs/RENDERING.md)**.
class_name CityWorkedTilesView
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

const _CITIZEN_DIM_PATH: String = "res://assets/prototype/map_markers/city_citizens/citizen_marker_dim.png"
const _CITIZEN_WORKED_PATH: String = "res://assets/prototype/map_markers/city_citizens/citizen_marker_worked.png"

var scenario = null
var layout = null
var camera = null
var selection = null
## Required for **PLANNING** draw: **`is_planning()`** after **Manage Citizens**.
var city_view_state = null

var _tex_dim: Texture2D
var _tex_worked: Texture2D


## **PLANNING-only** draw tuning ( **`_draw`** never runs in **NORMAL**). Tests pin keys **without** image assertions.
static func planning_marker_draw_style() -> Dictionary:
	return {
		"citizen_icon_height_ratio": 0.38,
		"planning_scale_mul": 1.95,
		# planning_y_offset_icon_ratio: added to center y as icon_side * ratio; negative moves up on screen.
		"planning_y_offset_icon_ratio": -0.24,
		"planning_alpha_mul": 1.08,
		"normal_alpha": 1.0,
	}


static func _load_rgba(path: String) -> Texture2D:
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		return null
	if res is Texture2D:
		return res as Texture2D
	return null


static func _worked_key_set_from_breakdown(p_scenario, city) -> Dictionary:
	var bd: Dictionary = CityYieldsScript.yield_breakdown_for_city(p_scenario, city)
	var wsrc: Array = bd.get("worked_tiles", []) as Array
	var keys: Dictionary = {}
	var wi: int = 0
	while wi < wsrc.size():
		var hx = wsrc[wi]
		wi += 1
		if hx == null:
			continue
		keys["%d,%d" % [int(hx.q), int(hx.r)]] = true
	return keys


## **Logical** citizen marker list for the **current city selection** ( **`dim`** / **`worked`** ) — **not** gated by **PLANNING** (for tests / inspection). **`_draw`** uses this **only** when **`CityViewState.is_planning()`**.
## One item per **owned** hex **except** the city **center**: **`kind`** **`"worked"`** if that coord appears in **`yield_breakdown_for_city`(..).`worked_tiles`**, else **`"dim"`**.
## **Order:** sort by **`q`** ascending, then **`r`** ascending. Fresh **`HexCoord`** instances and dicts each call.
static func compute_worked_marker_items(p_scenario, p_selection) -> Array:
	var out: Array = []
	if p_scenario == null or p_selection == null:
		return out
	if not p_selection.has_city():
		return out
	var cty = p_scenario.city_by_id(int(p_selection.city_id))
	if cty == null:
		return out
	var worked_keys: Dictionary = _worked_key_set_from_breakdown(p_scenario, cty)
	var cq: int = int(cty.position.q)
	var cr: int = int(cty.position.r)
	var cells: Array = []
	var oi: int = 0
	while oi < cty.owned_tiles.size():
		var ot = cty.owned_tiles[oi]
		oi += 1
		if ot == null or typeof(ot) != TYPE_OBJECT or not (ot is HexCoord):
			continue
		var hc: HexCoord = ot as HexCoord
		if int(hc.q) == cq and int(hc.r) == cr:
			continue
		cells.append(Vector2i(int(hc.q), int(hc.r)))
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y
	)
	var ci: int = 0
	while ci < cells.size():
		var v: Vector2i = cells[ci]
		ci += 1
		var k: String = "%d,%d" % [v.x, v.y]
		var kind: String = "worked" if worked_keys.has(k) else "dim"
		out.append({"coord": HexCoordScript.new(v.x, v.y), "kind": kind})
	return out


## Items that **`_draw`** would paint: **empty** unless **`p_city_view_state.is_planning()`**; else same as **`compute_worked_marker_items`**.
static func compute_draw_marker_items(p_scenario, p_selection, p_city_view_state) -> Array:
	if p_city_view_state == null or not p_city_view_state.is_planning():
		return []
	return compute_worked_marker_items(p_scenario, p_selection)


func _ready() -> void:
	## **No mipmaps:** **`TEXTURE_FILTER_LINEAR`** avoids mipmapped minification that **softened** edges and **bled** alpha into **painterly** terrain at map scale.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex_dim = _load_rgba(_CITIZEN_DIM_PATH)
	_tex_worked = _load_rgba(_CITIZEN_WORKED_PATH)
	if _tex_dim == null:
		push_warning("CityWorkedTilesView: missing or invalid %s" % _CITIZEN_DIM_PATH)
	if _tex_worked == null:
		push_warning("CityWorkedTilesView: missing or invalid %s" % _CITIZEN_WORKED_PATH)
	queue_redraw()


func _draw() -> void:
	if scenario == null or layout == null or camera == null or selection == null:
		return
	if city_view_state == null or not city_view_state.is_planning():
		return
	if not selection.has_city():
		return
	if _tex_dim == null and _tex_worked == null:
		return
	var st: Dictionary = planning_marker_draw_style()
	var ratio: float = float(st.get("citizen_icon_height_ratio", 0.38))
	var scale_mul: float = float(st.get("planning_scale_mul", 1.95))
	var y_off_ratio: float = float(st.get("planning_y_offset_icon_ratio", -0.24))
	var alpha: float = float(st.get("normal_alpha", 1.0)) * float(st.get("planning_alpha_mul", 1.08))
	alpha = clampf(alpha, 0.0, 1.0)
	var hex_h: float = HexLayoutScript.SIZE * 2.0
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
		var kind: String = str(d.get("kind", "dim"))
		var tex: Texture2D = _tex_worked if kind == "worked" else _tex_dim
		if tex == null:
			continue
		var q: int = int(cc.q)
		var r: int = int(cc.r)
		var world_c: Vector2 = layout.hex_to_world(q, r)
		var anchor_pres: Vector2 = camera.to_presentation(world_c)
		var pscale: float = camera.perspective_scale_at(world_c)
		var icon_side: float = hex_h * ratio * pscale * scale_mul
		var cy: float = anchor_pres.y + icon_side * y_off_ratio
		var rect: Rect2 = Rect2(anchor_pres.x - icon_side * 0.5, cy - icon_side * 0.5, icon_side, icon_side)
		draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, alpha))
