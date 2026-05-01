# Draws a HexMap in world space. Domain is read-only; no gameplay state, no input.
# See res://domain/* and docs/RENDERING.md
class_name MapView
extends Node2D

const HexMapScript = preload("res://domain/hex_map.gd")
# Preload coordinate script with map view for consistent headless class resolution; coords come from a_map.
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const _PLAINS_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/plains_painterly.png"
const _WATER_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/water_painterly.png"

@export var hex_tile_size: float = 128.0
## World units per one UV tile along X/Y; larger = less frequent texture repeat (presentation-only).
@export var terrain_texture_world_scale: float = 512.0

var map
var layout

var _plains_terrain_tex: Texture2D
var _water_terrain_tex: Texture2D

static func _terrain_to_color(terrain: int) -> Color:
	# Phase 4.1 — readable prototype palette (parchment land vs calm water). Not final art.
	if terrain == HexMapScript.Terrain.PLAINS:
		return Color(0.74, 0.67, 0.52)
	if terrain == HexMapScript.Terrain.WATER:
		return Color(0.28, 0.46, 0.62)
	return Color(1.0, 0.0, 1.0)

static func _world_anchored_corner_uvs(corners: PackedVector2Array, world_scale: float) -> PackedVector2Array:
	# Phase 4.1d: UV from layout/world position so textures read continuous across hexes (presentation-only).
	var n = corners.size()
	var uvs = PackedVector2Array()
	uvs.resize(n)
	if n == 0 or world_scale <= 0.0:
		return uvs
	var inv = 1.0 / world_scale
	var i = 0
	while i < n:
		var p = corners[i]
		uvs[i] = Vector2(p.x * inv, p.y * inv)
		i = i + 1
	return uvs

static func _try_load_terrain_tex(path: String) -> Texture2D:
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		push_warning("MapView: failed to load terrain texture: %s" % path)
		return null
	if res is Texture2D:
		return res as Texture2D
	push_warning("MapView: not a Texture2D: %s" % path)
	return null

static func compute_draw_items(a_map, a_layout) -> Array:
	# Preloaded so headless/entry scripts do not depend on class_name order for the coord type.
	assert(HexCoordScript != null)
	var out = []
	if a_map == null or a_layout == null:
		return out
	var coord_list = a_map.coords()
	var i = 0
	while i < coord_list.size():
		var coord = coord_list[i]
		var terrain = a_map.terrain_at(coord)
		var world = a_layout.hex_to_world(coord.q, coord.r)
		var corners = a_layout.hex_corners(world)
		var color = _terrain_to_color(terrain)
		var entry = {
			"coord": coord,
			"world": world,
			"corners": corners,
			"color": color,
			"terrain": terrain,
		}
		out.append(entry)
		i = i + 1
	return out

func _ready() -> void:
	if map == null:
		map = HexMapScript.make_tiny_test_map()
	if layout == null:
		layout = HexLayoutScript.new()
	_plains_terrain_tex = MapView._try_load_terrain_tex(_PLAINS_TERRAIN_TEX_PATH)
	_water_terrain_tex = MapView._try_load_terrain_tex(_WATER_TERRAIN_TEX_PATH)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()

func _draw() -> void:
	if map == null or layout == null:
		return
	var items = compute_draw_items(map, layout)
	var j = 0
	while j < items.size():
		var item = items[j]
		var corners = item["corners"]
		var col = item["color"]
		var terrain: int = int(item["terrain"])
		var tex: Texture2D
		if terrain == HexMapScript.Terrain.PLAINS:
			tex = _plains_terrain_tex
		elif terrain == HexMapScript.Terrain.WATER:
			tex = _water_terrain_tex
		else:
			tex = null
		if tex != null:
			var uvs = MapView._world_anchored_corner_uvs(corners, terrain_texture_world_scale)
			draw_colored_polygon(corners, Color.WHITE, uvs, tex)
		else:
			draw_colored_polygon(corners, col)
		j = j + 1
