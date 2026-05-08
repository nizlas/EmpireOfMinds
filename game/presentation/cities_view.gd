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

const _CITY_MARKER_PATH = "res://assets/prototype/map_markers/city_marker.png"

## **Debug:** last **`CitiesView._draw`** count when markers draw on **`self`** (not when delegated to **TFV**).
static var debug_last_city_markers_drawn_on_own_canvas: int = 0
## **Debug:** last **`CitiesView._draw`** delegation when wired to **`TerrainForegroundView`**.
static var debug_last_draw_delegated: bool = false

var scenario
var layout
## Phase 4.5m: **MapCamera** shared with other map layers. 4.5h: projected hex center + perspective_scale_at; city_marker_center_y_offset_ratio unused in _draw.
var camera
## Phase **4.6q:** when set, city markers draw in **`TerrainForegroundView`** (merged depth sort or pass **2**); **`CitiesView._draw`** skips.
var terrain_foreground_view
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
	if scenario == null:
		scenario = ScenarioScript.make_tiny_test_scenario()
	if layout == null:
		layout = HexLayoutScript.new()
	_city_icon_tex = CitiesView._load_rgba_marker_texture(_CITY_MARKER_PATH)
	if _city_icon_tex == null:
		push_warning("CitiesView: failed to load city_marker.png, using diamond fallback")
	queue_redraw()

## Same **`Rect2`** as **`draw_texture_rect`** for the PNG path; **`size.x <= 0`** when unlabeled / diamond fallback.
func city_marker_texture_rect_presentation(anchor_pres: Vector2, pscale: float) -> Rect2:
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


## **`world_center`** for diamond fallback world-space corners; **`anchor_pres`** / **`pscale`** match **`MapCamera`** projection for textured path.
func draw_city_marker_at(
	canvas: CanvasItem,
	world_center: Vector2,
	anchor_pres: Vector2,
	pscale: float,
	owner_id: int
) -> void:
	var col: Color = CitiesView._owner_to_color(owner_id)
	var half: float = HexLayoutScript.SIZE * diamond_half_extent_ratio
	var outline: Color = Color(0.0, 0.0, 0.0, 0.55)
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var icon_side: float = hex_h * city_icon_height_ratio
	var side: float = icon_side * pscale
	if _city_icon_tex != null:
		var rect: Rect2 = Rect2(
			anchor_pres.x - side * 0.5, anchor_pres.y - side * 0.5, side, side
		)
		canvas.draw_texture_rect(_city_icon_tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
	else:
		var pts: PackedVector2Array = PackedVector2Array(
			[
				camera.to_presentation(world_center + Vector2(0, -half)),
				camera.to_presentation(world_center + Vector2(half, 0)),
				camera.to_presentation(world_center + Vector2(0, half)),
				camera.to_presentation(world_center + Vector2(-half, 0)),
			]
		)
		canvas.draw_colored_polygon(pts, col)
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
		draw_city_marker_at(self, world_center, anchor_pres, pscale, int(item["owner_id"]))
		j = j + 1
	CitiesView.debug_last_city_markers_drawn_on_own_canvas = items.size()
