# Map-anchored **CityYields** icon overlay (Phase **5.1.16f**). **read-only** domain; scales with **MapCamera**.
# See docs/RENDERING.md
class_name TileYieldOverlayView
extends Node2D

const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")

const STABLE_YIELD_ORDER := ["food", "production", "science", "coin"]

## Phase **5.1.16f** follow-up (~**2×** prior **0.18** / **6–32** band): still **map-anchored** via **pscale**.
const YIELD_ICON_HEX_SIZE_RATIO: float = 0.36
const YIELD_ICON_MIN_PX: float = 12.0
const YIELD_ICON_MAX_PX: float = 64.0
const YIELD_ICON_COLUMN_STEP_RATIO: float = 0.95
const YIELD_ICON_ROW_STEP_RATIO: float = 0.85

const _PATH_FOOD: String = "res://assets/prototype/yield_icons/food_resource.png"
const _PATH_PRODUCTION: String = "res://assets/prototype/yield_icons/production_resource.png"
const _PATH_SCIENCE: String = "res://assets/prototype/yield_icons/science_resource.png"
const _PATH_COIN: String = "res://assets/prototype/yield_icons/coin_resource.png"

## Wired by **main** alongside other map layers.
var scenario = null
var layout = null
var camera = null
## Phase **5.2.4k:** when set, overlay entries skip hexes not explored for **current_player_id**.
var game_state = null

var _tex_food: Texture2D
var _tex_production: Texture2D
var _tex_science: Texture2D
var _tex_coin: Texture2D
var _missing_logged: bool = false


static func _load_yield_texture(path: String) -> Texture2D:
	## Same load path as **CitiesView** / **UnitsView** marker PNGs (**ResourceLoader** + **Texture2D**).
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		return res as Texture2D
	return null


func _configure_texture_filtering() -> void:
	## Matches **UnitsView** / **CitiesView** / **TerrainForegroundView** (**TEXTURE_FILTER_LINEAR_WITH_MIPMAPS**).
	## Yield **.import** files use **mipmaps/generate=true** like **map_markers/** so minification stays smooth.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func compute_active_yield_columns(yields: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if yields == null or typeof(yields) != TYPE_DICTIONARY:
		return out
	var i: int = 0
	while i < STABLE_YIELD_ORDER.size():
		var yid: String = STABLE_YIELD_ORDER[i]
		if CityYieldsScript.get_yield(yields, yid) > 0:
			out.append(yid)
		i += 1
	return out


static func compute_icon_metrics(pscale: float) -> Dictionary:
	var icon_size: float = clampf(
		HexLayoutScript.SIZE * YIELD_ICON_HEX_SIZE_RATIO * pscale,
		YIELD_ICON_MIN_PX,
		YIELD_ICON_MAX_PX
	)
	return {
		"icon_size": icon_size,
		"column_step_x": icon_size * YIELD_ICON_COLUMN_STEP_RATIO,
		"row_step_y": icon_size * YIELD_ICON_ROW_STEP_RATIO,
	}


static func compute_icon_entries_for_hex(
	anchor_pres: Vector2, yields: Dictionary, metrics: Dictionary
) -> Array:
	var out: Array = []
	var cols: Array = compute_active_yield_columns(yields)
	if cols.is_empty():
		return out
	var icon_size: float = float(metrics["icon_size"])
	var column_step_x: float = float(metrics["column_step_x"])
	var row_step_y: float = float(metrics["row_step_y"])
	var ncols: int = cols.size()
	var group_width: float = float(ncols - 1) * column_step_x
	var start_x: float = anchor_pres.x - group_width * 0.5
	var cj: int = 0
	while cj < ncols:
		var yid: String = str(cols[cj])
		var cnt: int = CityYieldsScript.get_yield(yields, yid)
		var cx: float = start_x + float(cj) * column_step_x
		var half_span: float = 0.0
		if cnt > 1:
			half_span = float(cnt - 1) * row_step_y * 0.5
		var k: int = 0
		while k < cnt:
			var cy: float = anchor_pres.y - half_span + float(k) * row_step_y
			var rect: Rect2 = Rect2(cx - icon_size * 0.5, cy - icon_size * 0.5, icon_size, icon_size)
			out.append(
				{
					"yield_id": yid,
					"column_index": cj,
					"stack_index": k,
					"center_pres": Vector2(cx, cy),
					"rect": rect,
				}
			)
			k += 1
		cj += 1
	return out


static func compute_overlay_entries(p_scenario, p_layout, p_camera, p_game_state = null) -> Array:
	var all: Array = []
	if p_scenario == null or p_layout == null or p_camera == null:
		return all
	var m = p_scenario.map
	if m == null:
		return all
	var coord_list: Array = m.coords()
	var ci: int = 0
	while ci < coord_list.size():
		var coord = coord_list[ci]
		if not PresentationVisibilityScript.should_draw_map_detail_for_current_player(p_game_state, coord):
			ci += 1
			continue
		var ydict: Dictionary = CityYieldsScript.empty()
		var at_city: Array = p_scenario.cities_at(coord)
		if at_city.size() > 0:
			# Per-hex overlay: city **center** shows **`city_center_yield`** only (local tile rule).
			# **`city_total_yield`** (buildings, worked tiles, etc.) stays in **City Hub** / totals — not repeated on the map cell.
			ydict = CityYieldsScript.city_center_yield(m, at_city[0])
		else:
			ydict = CityYieldsScript.raw_terrain_yield(m, coord)
		if compute_active_yield_columns(ydict).is_empty():
			ci += 1
			continue
		var world: Vector2 = p_layout.hex_to_world(coord.q, coord.r)
		var anchor_pres: Vector2 = p_camera.to_presentation(world)
		var pscale: float = p_camera.perspective_scale_at(world)
		var metrics: Dictionary = compute_icon_metrics(pscale)
		var hex_entries: Array = compute_icon_entries_for_hex(anchor_pres, ydict, metrics)
		var ei: int = 0
		while ei < hex_entries.size():
			var ent = hex_entries[ei]
			if typeof(ent) == TYPE_DICTIONARY:
				(ent as Dictionary)["coord"] = coord
			all.append(ent)
			ei += 1
		ci += 1
	return all


func _texture_for_yield_id(yield_id: String) -> Texture2D:
	match yield_id:
		"food":
			return _tex_food
		"production":
			return _tex_production
		"science":
			return _tex_science
		"coin":
			return _tex_coin
		_:
			return null


func _fallback_letter(yield_id: String) -> String:
	match yield_id:
		"food":
			return "F"
		"production":
			return "P"
		"science":
			return "S"
		"coin":
			return "C"
		_:
			return "?"


func _fallback_color(yield_id: String) -> Color:
	match yield_id:
		"food":
			return Color(0.45, 0.72, 0.38, 1.0)
		"production":
			return Color(0.62, 0.52, 0.38, 1.0)
		"science":
			return Color(0.42, 0.55, 0.78, 1.0)
		"coin":
			return Color(0.78, 0.66, 0.32, 1.0)
		_:
			return Color(0.7, 0.7, 0.7, 1.0)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex_food = _load_yield_texture(_PATH_FOOD)
	_tex_production = _load_yield_texture(_PATH_PRODUCTION)
	_tex_science = _load_yield_texture(_PATH_SCIENCE)
	_tex_coin = _load_yield_texture(_PATH_COIN)
	if (
		_tex_food == null
		or _tex_production == null
		or _tex_science == null
		or _tex_coin == null
	):
		if not _missing_logged:
			push_warning(
				"TileYieldOverlayView: one or more yield icons missing under res://assets/prototype/yield_icons/; using letter fallback"
			)
			_missing_logged = true
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if scenario == null or layout == null:
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 11
	var ents: Array = compute_overlay_entries(scenario, layout, camera, game_state)
	var di: int = 0
	while di < ents.size():
		var e = ents[di]
		if typeof(e) != TYPE_DICTIONARY:
			di += 1
			continue
		var d: Dictionary = e as Dictionary
		var yid: String = str(d.get("yield_id", ""))
		var rect: Rect2 = d.get("rect", Rect2()) as Rect2
		var tex: Texture2D = _texture_for_yield_id(yid)
		if tex != null:
			## Same draw path as textured **CitiesView** / **UnitsView** markers: tile=false, full modulate.
			draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
		else:
			var col: Color = _fallback_color(yid)
			var pad: float = rect.size.x * 0.12
			var inner: Rect2 = Rect2(rect.position.x + pad, rect.position.y + pad, rect.size.x - 2.0 * pad, rect.size.y - 2.0 * pad)
			draw_circle(inner.get_center(), inner.size.x * 0.45, Color(0.12, 0.11, 0.1, 0.55))
			if font != null:
				var letter: String = _fallback_letter(yid)
				var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
				var tp: Vector2 = inner.get_center() - Vector2(sz.x * 0.5, fsize * 0.4)
				draw_string(font, tp, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
		di += 1
