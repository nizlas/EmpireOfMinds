# Draws unit markers in world space from a Scenario. Domain is read-only; markers are derived, not owned as gameplay state.
# See docs/RENDERING.md — Phase 4.3f: textured markers are icon-only; selection reads from SelectionView hex overlay.
class_name UnitsView
extends Node2D

## **Debug (4.6q):** last **`UnitsView._draw`** delegation snapshot (**TerrainForegroundView** logs read this after **`UnitsView`** draws, same frame).
static var debug_last_draw_delegated: bool = false
## **Debug:** count of **`draw_unit_marker_at(..., canvas == self)`** in last **`UnitsView._draw`** (must be **0** when **`terrain_foreground_view`** wired).
static var debug_last_units_drawn_on_own_canvas: int = 0
## **Debug:** last **`draw_texture_rect`** **raw** PNG quad bottom-center (`position + (w/2, h)`).
static var debug_last_unit_png_rect: Rect2 = Rect2()
static var debug_last_unit_png_bottom_center: Vector2 = Vector2.ZERO
## **Debug:** bottom-center of **opaque** AABB after **alpha bottom-padding** compensation (presentation px).
static var debug_last_unit_effective_depth_point: Vector2 = Vector2.ZERO

const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const TextureAlphaMetricsClass = preload("res://presentation/texture_alpha_metrics.gd")
const Warrior3DUnitExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

const _SETTLER_MARKER_PATH = "res://assets/prototype/map_markers/unit_settler_marker.png"
const _WARRIOR_MARKER_PATH = "res://assets/prototype/map_markers/unit_warrior_marker.png"
## **4.5j** — **type_id** → pivot **Vector2** in **0–1** rect space; only entries that differ from **unit_marker_pivot_*** exports.
const _UNIT_MARKER_PIVOT_BY_TYPE: Dictionary = {"settler": Vector2(0.50, 0.86)}

var scenario
var layout
## Wired by main; projected hex center = foot pivot in sprite (**unit_marker_pivot_*** + **4.5j** per-**type_id** table).
var camera
## Wired by main for API compat; Phase 4.3f+ does not draw a unit selection halo — hex highlight only.
var selection
## Phase **4.6p:** when set to a valid **`TerrainForegroundView`** (or any **`CanvasItem`** host), **`_draw`** skips own-canvas markers — **`TerrainForegroundView`** draws them between forest passes.
var terrain_foreground_view
## Experimental 3D warrior markers — blit via **`draw_unit_marker_at`** when TFV depth merge is active.
var warrior_3d_unit_markers_view
@export var marker_radius_ratio: float = 0.35
## Icon height as a fraction of pointy-top hex height (2 * HexLayout.SIZE) when a type icon is loaded. Phase 4.3f.
@export var unit_icon_height_ratio: float = 0.70
## Horizontal pivot in **square** marker rect: **0.5** = image center; **anchor_pres** sits at this fraction from the rect’s **left** edge.
@export var unit_marker_pivot_x_ratio: float = 0.50
## Vertical pivot from **top** of rect (**+Y** down): **0.9** ≈ contact between feet, slightly above image bottom; **anchor_pres** sits at this fraction from the rect’s **top** edge.
@export var unit_marker_pivot_y_ratio: float = 0.90
## Legacy layout-space foot offset; **unused** for textured **`draw_texture_rect`** (**4.5i+** uses pivots). Compat export.
@export var unit_icon_foot_offset_ratio: float = 0.24
var _tex_settler: Texture2D
var _tex_warrior: Texture2D

static func _owner_to_color(owner_id: int) -> Color:
	# Phase 4.2 — slightly stronger fills for readability on parchment / water terrain (prototype).
	# Phase **4.6n:** kept underscored; **`owner_to_color`** is the public alias used by **`TerrainForegroundView`** depth-sorted draw.
	if owner_id == 0:
		return Color(0.92, 0.76, 0.14)
	if owner_id == 1:
		return Color(0.88, 0.17, 0.22)
	return Color(1.0, 0.0, 1.0)


static func owner_to_color(owner_id: int) -> Color:
	return UnitsView._owner_to_color(owner_id)


func delegates_unit_markers_to_terrain_foreground() -> bool:
	return terrain_foreground_view != null and is_instance_valid(terrain_foreground_view)


static func compute_marker_items(a_scenario, a_layout) -> Array:
	assert(UnitScript != null)
	assert(HexCoordScript != null)
	if a_scenario == null or a_layout == null:
		return []
	var out = []
	var ulist = a_scenario.units()
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		var w = a_layout.hex_to_world(u.position.q, u.position.r)
		var d = {
			"unit_id": u.id,
			"owner_id": u.owner_id,
			"type_id": u.type_id,
			"coord": u.position,
			"world": w,
			"color": _owner_to_color(u.owner_id),
		}
		out.append(d)
		i = i + 1
	return out


static func marker_texture_res_path(type_id: String) -> String:
	if type_id == "settler":
		return _SETTLER_MARKER_PATH
	if type_id == "warrior":
		return _WARRIOR_MARKER_PATH
	return ""


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
	# **`scenario`** / **`layout`** wired by **`main.gd`** or tests — not **`make_tiny_test_scenario()`** here.
	_tex_settler = UnitsView._load_rgba_marker_texture(_SETTLER_MARKER_PATH)
	_tex_warrior = UnitsView._load_rgba_marker_texture(_WARRIOR_MARKER_PATH)
	if _tex_settler == null:
		push_warning("UnitsView: failed to load unit_settler_marker.png, settler uses programmatic fallback")
	if _tex_warrior == null:
		push_warning("UnitsView: failed to load unit_warrior_marker.png, warrior uses programmatic fallback")
	queue_redraw()

func _texture_for_type_id(type_id: String) -> Texture2D:
	if type_id == "settler":
		return _tex_settler
	if type_id == "warrior":
		return _tex_warrior
	return null

func _resolved_marker_pivot(type_id: String) -> Vector2:
	if UnitsView._UNIT_MARKER_PIVOT_BY_TYPE.has(type_id):
		return UnitsView._UNIT_MARKER_PIVOT_BY_TYPE[type_id] as Vector2
	return Vector2(unit_marker_pivot_x_ratio, unit_marker_pivot_y_ratio)


## Same **`Rect2`** as **`draw_texture_rect`** for the PNG path; **`size.x <= 0`** if there is no raster marker (programmatic fallback).
## **Textured:** **opaque** bottom (effective foot) **`== anchor_pres`** — raw quad bottom-center at **`anchor_pres + (0, scaled_bottom_padding_y)`** (**`TextureAlphaMetrics`**). **Fallback:** pivot rect when metrics unavailable.
func unit_marker_texture_rect_presentation(
	anchor_pres: Vector2, pscale: float, type_id: String
) -> Rect2:
	var utex = _texture_for_type_id(type_id)
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var icon_side: float = hex_h * unit_icon_height_ratio
	if utex == null:
		return Rect2()
	var side: float = icon_side * pscale
	var path: String = UnitsView.marker_texture_res_path(type_id)
	if not path.is_empty():
		var mm: Dictionary = TextureAlphaMetricsClass.metrics_for_res_path(path)
		var pad_y: float = TextureAlphaMetricsClass.scaled_bottom_padding_y(mm, side)
		if mm.get("ok", false) and int(mm["height"]) > 0:
			return Rect2(anchor_pres.x - side * 0.5, anchor_pres.y + pad_y - side, side, side)
	var piv: Vector2 = _resolved_marker_pivot(type_id)
	return Rect2(
		anchor_pres.x - side * piv.x,
		anchor_pres.y - side * piv.y,
		side,
		side
	)


static func unit_png_bottom_center_from_rect(unit_rect: Rect2) -> Vector2:
	return Vector2(
		unit_rect.position.x + unit_rect.size.x * 0.5,
		unit_rect.position.y + unit_rect.size.y
	)


## **Presentation** anchor used for forest / unit **depth ordering** — same geometry as **`draw_unit_marker_at`**
## (effective / “foot” point after **TextureAlphaMetrics** bottom padding when PNG path; else hex **anchor_pres**).
func unit_effective_depth_presentation(
	anchor_pres: Vector2, pscale: float, type_id: String
) -> Vector2:
	var utex = _texture_for_type_id(type_id)
	if utex == null:
		return anchor_pres
	var rect: Rect2 = unit_marker_texture_rect_presentation(anchor_pres, pscale, type_id)
	if rect.size.x <= 0.0:
		return anchor_pres
	var upath: String = marker_texture_res_path(type_id)
	var mue: Dictionary = TextureAlphaMetricsClass.metrics_for_res_path(upath)
	if mue.get("ok", false) and int(mue["height"]) > 0:
		var raw_bc: Vector2 = unit_png_bottom_center_from_rect(rect)
		var spy: float = TextureAlphaMetricsClass.scaled_bottom_padding_y(mue, rect.size.y)
		return raw_bc - Vector2(0.0, spy)
	return Vector2.ZERO


## Phase **4.6p:** Render one unit marker onto an arbitrary **CanvasItem** (`canvas`).
## Used by **`UnitsView._draw`** (`canvas == self`, legacy path) and **`TerrainForegroundView`**
## pass **2** (`canvas == terrain_foreground_view`) so pivot / scale / fallback logic stays single-sourced.
##
## **`anchor_pres`** = projected hex center (same origin as forest **grid** layout space at **local (0,0)**).
func draw_unit_marker_at(
	canvas: CanvasItem,
	anchor_pres: Vector2,
	pscale: float,
	type_id: String,
	owner_id: int,
	unit_id: int = -1,
) -> void:
	if Warrior3DUnitExperimentScript.should_render_warrior_as_3d(type_id):
		if warrior_3d_unit_markers_view != null and unit_id >= 0:
			warrior_3d_unit_markers_view.draw_unit_marker_at(
				canvas, anchor_pres, pscale, type_id, owner_id, unit_id
			)
		return
	var utex = _texture_for_type_id(type_id)
	if utex != null:
		var rect: Rect2 = unit_marker_texture_rect_presentation(
			anchor_pres, pscale, type_id
		)
		canvas.draw_texture_rect(utex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
		UnitsView.debug_last_unit_png_rect = rect
		UnitsView.debug_last_unit_png_bottom_center = (
			UnitsView.unit_png_bottom_center_from_rect(rect)
		)
		UnitsView.debug_last_unit_effective_depth_point = unit_effective_depth_presentation(
			anchor_pres, pscale, type_id
		)
		return
	# Programmatic path: no PNG quad — clear texture debug snapshot.
	UnitsView.debug_last_unit_png_rect = Rect2()
	UnitsView.debug_last_unit_png_bottom_center = Vector2.ZERO
	UnitsView.debug_last_unit_effective_depth_point = Vector2.ZERO
	# Fallback: circle + glyph stay centered on projected hex center (no sprite pivot).
	var col: Color = UnitsView._owner_to_color(owner_id)
	var r_disk: float = HexLayoutScript.SIZE * marker_radius_ratio
	canvas.draw_circle(anchor_pres, r_disk * pscale, col)
	if type_id.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var type_font_size: int = 11
	var glyph: String = type_id.substr(0, 1).to_upper()
	var tw: float = font.get_string_size(
		glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, type_font_size
	).x
	var o: Vector2 = Vector2(-tw * 0.5, font.get_ascent(type_font_size) * 0.05)
	canvas.draw_string(
		font,
		anchor_pres + o,
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		type_font_size,
		Color(0.08, 0.07, 0.06, 0.92)
	)


func _draw() -> void:
	UnitsView.debug_last_units_drawn_on_own_canvas = 0
	UnitsView.debug_last_draw_delegated = false
	# Phase **4.6p:** when **`terrain_foreground_view`** is wired, unit markers draw in **`TerrainForegroundView`**
	# — **legacy:** between upper / lower forest half-plane passes; **with units + symbol scatter**, a **single depth merge**
	# orders each tree slot vs each unit by **`MapCamera.to_layout`** on shared presentation anchors (**`TerrainForegroundView`**).
	# **`UnitsView._draw`** is a no-op then; **`queue_redraw`** from controllers still pings **`TerrainForegroundView`**
	# via shared controllers. Unwired headless tests keep drawing on **`self`** here.
	if delegates_unit_markers_to_terrain_foreground():
		UnitsView.debug_last_draw_delegated = true
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var items = UnitsView.compute_marker_items(scenario, layout)
	var j = 0
	while j < items.size():
		var item = items[j]
		var coord = item["coord"]
		var world_center = layout.hex_to_world(coord.q, coord.r)
		var owner_id: int = int(item.get("owner_id", -1))
		var tid: String = str(item.get("type_id", ""))
		var anchor_pres = camera.to_presentation(world_center)
		var pscale = camera.perspective_scale_at(world_center)
		draw_unit_marker_at(self, anchor_pres, pscale, tid, owner_id)
		j = j + 1
	UnitsView.debug_last_units_drawn_on_own_canvas = items.size()
