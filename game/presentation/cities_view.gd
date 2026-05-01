# Draws city map marker icons in world space from Scenario.cities(). Derived view only; no input.
# See docs/RENDERING.md, docs/CITIES.md — Phase 4.3f: textured city is icon-only (no rings).
class_name CitiesView
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const _CITY_MARKER_PATH = "res://assets/prototype/map_markers/city_marker.png"

var scenario
var layout
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

func _draw() -> void:
	var items = compute_marker_items(scenario, layout)
	var half = HexLayoutScript.SIZE * diamond_half_extent_ratio
	var outline = Color(0.0, 0.0, 0.0, 0.55)
	var hex_h = HexLayoutScript.SIZE * 2.0
	var icon_side = hex_h * city_icon_height_ratio
	var j = 0
	while j < items.size():
		var item = items[j]
		var world = item["world"] as Vector2
		var col = item["color"] as Color
		if _city_icon_tex != null:
			var rect = Rect2(world.x - icon_side * 0.5, world.y - icon_side * 0.5, icon_side, icon_side)
			draw_texture_rect(_city_icon_tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
		else:
			var pts = PackedVector2Array(
				[
					world + Vector2(0, -half),
					world + Vector2(half, 0),
					world + Vector2(0, half),
					world + Vector2(-half, 0),
				]
			)
			draw_colored_polygon(pts, col)
			var outline_pts = pts.duplicate()
			outline_pts.append(pts[0])
			draw_polyline(outline_pts, outline, 1.0, true)
		j = j + 1
