# Draws unit markers in world space from a Scenario. Domain is read-only; markers are derived, not owned as gameplay state.
# See docs/RENDERING.md — Phase 4.3f: textured markers are icon-only; selection reads from SelectionView hex overlay.
class_name UnitsView
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

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
	if owner_id == 0:
		return Color(0.92, 0.76, 0.14)
	if owner_id == 1:
		return Color(0.88, 0.17, 0.22)
	return Color(1.0, 0.0, 1.0)

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

func _draw() -> void:
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var items = UnitsView.compute_marker_items(scenario, layout)
	var r = HexLayoutScript.SIZE * marker_radius_ratio
	var j = 0
	var font = ThemeDB.fallback_font
	var type_font_size = 11
	var hex_h = HexLayoutScript.SIZE * 2.0
	var icon_side = hex_h * unit_icon_height_ratio
	while j < items.size():
		var item = items[j]
		var coord = item["coord"]
		var world_center = layout.hex_to_world(coord.q, coord.r)
		var col = item["color"] as Color
		var tid: String = str(item.get("type_id", ""))
		var utex = _texture_for_type_id(tid)
		var anchor_pres = camera.to_presentation(world_center)
		var pscale = camera.perspective_scale_at(world_center)
		if utex != null:
			var side = icon_side * pscale
			var piv = _resolved_marker_pivot(tid)
			var rect = Rect2(
				anchor_pres.x - side * piv.x,
				anchor_pres.y - side * piv.y,
				side,
				side
			)
			draw_texture_rect(utex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
		else:
			# Fallback: circle + glyph stay centered on projected hex center (no sprite pivot).
			draw_circle(anchor_pres, r * pscale, col)
			if not tid.is_empty():
				var glyph = tid.substr(0, 1).to_upper()
				var tw = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, type_font_size).x
				var o = Vector2(-tw * 0.5, font.get_ascent(type_font_size) * 0.05)
				draw_string(
					font,
					anchor_pres + o,
					glyph,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					type_font_size,
					Color(0.08, 0.07, 0.06, 0.92)
				)

		j = j + 1
