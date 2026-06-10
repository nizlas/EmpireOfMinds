# Draws city map marker icons in world space from Scenario.cities(). Derived view only; no input.
# See docs/RENDERING.md, docs/CITIES.md — Phase 4.3f: textured city is icon-only (no rings).
class_name CitiesView
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

const _CITY_MARKER_PATH = "res://assets/prototype/map_markers/city_marker.png"
## TEMP DIAG — remove after city 3D vs 2D path audit (June 2026).
const _CITY_DRAW_DIAG_LABEL: String = "3D CITY"
const _CITY_DRAW_DIAG_2D_TINT: Color = Color(1.0, 0.0, 1.0, 1.0)
const _CITY_DRAW_DIAG_LABEL_COLOR: Color = Color(0.1, 1.0, 0.25, 1.0)

## **Debug:** last **`CitiesView._draw`** count when markers draw on **`self`** (not when delegated to **TFV**).
static var debug_last_city_markers_drawn_on_own_canvas: int = 0
## TEMP DIAG — once-per-city draw-path log keys for **`EMPIRE_USE_3D_MODELS=1`** audit.
static var _city_draw_diag_logged: Dictionary = {}
## **Debug:** last **`CitiesView._draw`** delegation when wired to **`TerrainForegroundView`**.
static var debug_last_draw_delegated: bool = false

var scenario
var layout
## Phase 4.5m: **MapCamera** shared with other map layers. 4.5h: projected hex center + perspective_scale_at; city_marker_center_y_offset_ratio unused in _draw.
var camera
## Phase **4.6q:** when set, city markers draw in **`TerrainForegroundView`** (merged depth sort or pass **2**); **`CitiesView._draw`** skips.
var terrain_foreground_view
## Experimental 3D city markers (ancient_village) — blit via **`draw_city_marker_at`** when TFV depth merge is active.
var city_3d_markers_view
## Real 3D city instances on **MapPresentation3DLayer** (when **`real_3d_city_enabled`**).
var map_presentation_3d_layer
## Not used for textured placement (**4.5h**: anchor = **camera.to_presentation(layout.hex_to_world)**). Kept for API/scene compatibility.
@export var city_marker_center_y_offset_ratio: float = 0.0
@export var diamond_half_extent_ratio: float = 0.28
## Icon height as a fraction of pointy-top hex height (2 * HexLayout.SIZE). Phase 4.3f.
@export var city_icon_height_ratio: float = 0.90
var _city_icon_tex: Texture2D

static func _owner_to_color(owner_id: int) -> Color:
	if owner_id == 0:
		return Color(0.25, 0.65, 0.95)
	if owner_id == 1:
		return Color(0.45, 0.35, 0.90)
	return Color(0.0, 0.85, 0.75)


func delegates_city_markers_to_terrain_foreground() -> bool:
	return terrain_foreground_view != null and is_instance_valid(terrain_foreground_view)


## TEMP DIAG — active when **`EMPIRE_USE_3D_MODELS=1`** (3D experiment session).
static func _city_draw_diag_active() -> bool:
	return Warrior3DExperimentScript.is_models_flag_enabled()


static func _log_city_draw_diag_once(city_id: int, path: String) -> void:
	if not _city_draw_diag_active():
		return
	var key: String = "%d:%s" % [city_id, path]
	if _city_draw_diag_logged.has(key):
		return
	_city_draw_diag_logged[key] = true
	print("[CityDrawDiag] city_id=%d path=%s" % [city_id, path])


static func _draw_city_draw_diag_label(canvas: CanvasItem, anchor_pres: Vector2, label: String) -> void:
	if not _city_draw_diag_active():
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var label_pos: Vector2 = anchor_pres + Vector2(-36.0, -28.0)
	canvas.draw_string(
		font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _CITY_DRAW_DIAG_LABEL_COLOR
	)


static func compute_marker_items(a_scenario, a_layout) -> Array:
	assert(CityScript != null)
	assert(HexCoordScript != null)
	if a_scenario == null or a_layout == null:
		return []
	var out = []
	var clist = a_scenario.cities()
	var i = 0
	while i < clist.size():
		var c = clist[i]
		var w = a_layout.hex_to_world(c.position.q, c.position.r)
		var d = {
			"city_id": c.id,
			"owner_id": c.owner_id,
			"coord": c.position,
			"world": w,
			"color": _owner_to_color(c.owner_id),
		}
		out.append(d)
		i = i + 1
	return out

static func _load_rgba_marker_texture(path: String) -> Texture2D:
	# Phase 4.3i — true-alpha PNGs loaded directly (no background keying).
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		return null
	if res is Texture2D:
		return res as Texture2D
	return null

func _ready() -> void:
	# Phase 4.3h/4.3i — downscale: linear + mipmaps (marker imports only).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# **`scenario`** / **`layout`** wired by **`main.gd`** or tests — not **`make_tiny_test_scenario()`** here
	# (cloud boot must not render local placeholder cities).
	_city_icon_tex = CitiesView._load_rgba_marker_texture(_CITY_MARKER_PATH)
	if _city_icon_tex == null:
		push_warning("CitiesView: failed to load city_marker.png, using diamond fallback")
	queue_redraw()

## Same **`Rect2`** as **`draw_texture_rect`** for the PNG path; **`size.x <= 0`** when unlabeled / diamond fallback.
func city_marker_texture_rect_presentation(anchor_pres: Vector2, pscale: float) -> Rect2:
	if Warrior3DExperimentScript.should_render_city_as_3d() and city_3d_markers_view != null:
		return city_3d_markers_view.marker_display_rect(anchor_pres, pscale)
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var icon_side: float = hex_h * city_icon_height_ratio * pscale
	if _city_icon_tex == null:
		return Rect2()
	return Rect2(
		anchor_pres.x - icon_side * 0.5,
		anchor_pres.y - icon_side * 0.5,
		icon_side,
		icon_side
	)


## **Bottom-center** of **`city_marker_texture_rect_presentation`** when textured; else **`anchor_pres`**.
func city_effective_depth_presentation(anchor_pres: Vector2, pscale: float) -> Vector2:
	var r: Rect2 = city_marker_texture_rect_presentation(anchor_pres, pscale)
	if r.size.x <= 0.0:
		return anchor_pres
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y)


## TFV marker depth-sort anchor: 3D cities use building-silhouette point; 2D uses **`city_effective_depth_presentation`**.
func city_depth_sort_anchor_presentation(anchor_pres: Vector2, pscale: float) -> Vector2:
	if Warrior3DExperimentScript.should_render_city_as_3d() and city_3d_markers_view != null:
		return city_3d_markers_view.depth_sort_anchor_pres(anchor_pres, pscale)
	return city_effective_depth_presentation(anchor_pres, pscale)


## **`world_center`** for diamond fallback world-space corners; **`anchor_pres`** / **`pscale`** match **`MapCamera`** projection for textured path.
func _uses_real_scene_3d_city() -> bool:
	return (
		map_presentation_3d_layer != null
		and map_presentation_3d_layer.uses_real_3d_city()
	)


func _uses_city_blit_path() -> bool:
	if not Warrior3DExperimentScript.should_render_city_as_3d():
		return false
	if map_presentation_3d_layer == null:
		return true
	return map_presentation_3d_layer.uses_city_blit_fallback()


func draw_city_marker_at(
	canvas: CanvasItem,
	world_center: Vector2,
	anchor_pres: Vector2,
	pscale: float,
	owner_id: int,
	city_id: int = -1,
) -> void:
	if Warrior3DExperimentScript.should_render_city_as_3d():
		var city_for_diag = null
		if scenario != null and city_id >= 0:
			var clist: Array = scenario.cities()
			var ci: int = 0
			while ci < clist.size():
				if int(clist[ci].id) == city_id:
					city_for_diag = clist[ci]
					break
				ci += 1
		if map_presentation_3d_layer != null and city_id >= 0:
			map_presentation_3d_layer.log_city_visibility_diag_once(city_id, city_for_diag)
		var use_blit: bool = (
			map_presentation_3d_layer.should_auto_blit_for_city(city_id)
			if map_presentation_3d_layer != null
			else _uses_city_blit_path()
		)
		if not use_blit:
			_log_city_draw_diag_once(city_id, "real_scene_3d")
			return
		if use_blit and map_presentation_3d_layer != null and city_id >= 0:
			var reason: String = "explicit_blit_fallback"
			if not map_presentation_3d_layer.is_composite_viewport_ready():
				reason = "composite_viewport_invalid"
			elif not map_presentation_3d_layer.is_city_active_in_real_3d(city_id):
				reason = "real_3d_instance_not_ready"
			map_presentation_3d_layer.warn_auto_blit_fallback_once(city_id, reason)
		if city_3d_markers_view != null and city_id >= 0 and use_blit:
			if city_3d_markers_view.try_draw_city_marker_at(
				canvas, anchor_pres, pscale, city_id, owner_id
			):
				_log_city_draw_diag_once(city_id, "3d_ancient_village")
				_draw_city_draw_diag_label(canvas, anchor_pres, _CITY_DRAW_DIAG_LABEL)
				return
		elif city_3d_markers_view == null:
			push_warning(
				"CitiesView: EMPIRE_USE_3D_MODELS=1 but city_3d_markers_view is null; 2D fallback"
			)
		elif city_id < 0:
			push_warning(
				"CitiesView: 3D city draw skipped (city_id=%d); 2D fallback" % city_id
			)
		_log_city_draw_diag_once(city_id, "2d_fallback_magenta")
		_draw_2d_city_marker(canvas, world_center, anchor_pres, pscale, owner_id, true)
		return
	_log_city_draw_diag_once(city_id, "2d_normal")
	_draw_2d_city_marker(canvas, world_center, anchor_pres, pscale, owner_id, false)


func _draw_2d_city_marker(
	canvas: CanvasItem,
	world_center: Vector2,
	anchor_pres: Vector2,
	pscale: float,
	owner_id: int,
	magenta_fallback_in_3d_mode: bool,
) -> void:
	var col: Color = CitiesView._owner_to_color(owner_id)
	var half: float = HexLayoutScript.SIZE * diamond_half_extent_ratio
	var outline: Color = Color(0.0, 0.0, 0.0, 0.55)
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var icon_side: float = hex_h * city_icon_height_ratio
	var side: float = icon_side * pscale
	var tint: Color = (
		_CITY_DRAW_DIAG_2D_TINT if magenta_fallback_in_3d_mode else Color(1.0, 1.0, 1.0, 1.0)
	)
	if _city_icon_tex != null:
		var rect: Rect2 = Rect2(
			anchor_pres.x - side * 0.5, anchor_pres.y - side * 0.5, side, side
		)
		canvas.draw_texture_rect(_city_icon_tex, rect, false, tint)
	else:
		var pts: PackedVector2Array = PackedVector2Array(
			[
				camera.to_presentation(world_center + Vector2(0, -half)),
				camera.to_presentation(world_center + Vector2(half, 0)),
				camera.to_presentation(world_center + Vector2(0, half)),
				camera.to_presentation(world_center + Vector2(-half, 0)),
			]
		)
		canvas.draw_colored_polygon(pts, col if not magenta_fallback_in_3d_mode else _CITY_DRAW_DIAG_2D_TINT)
		var outline_pts: PackedVector2Array = pts.duplicate()
		outline_pts.append(pts[0])
		canvas.draw_polyline(outline_pts, outline, 1.0, true)

func _draw() -> void:
	CitiesView.debug_last_draw_delegated = false
	CitiesView.debug_last_city_markers_drawn_on_own_canvas = 0
	if delegates_city_markers_to_terrain_foreground():
		CitiesView.debug_last_draw_delegated = true
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var items = compute_marker_items(scenario, layout)
	var j = 0
	while j < items.size():
		var item = items[j]
		var coord = item["coord"]
		var world_center: Vector2 = layout.hex_to_world(coord.q, coord.r)
		var anchor_pres: Vector2 = camera.to_presentation(world_center)
		var pscale: float = camera.perspective_scale_at(world_center)
		draw_city_marker_at(
			self, world_center, anchor_pres, pscale, int(item["owner_id"]), int(item["city_id"])
		)
		j = j + 1
	CitiesView.debug_last_city_markers_drawn_on_own_canvas = items.size()
