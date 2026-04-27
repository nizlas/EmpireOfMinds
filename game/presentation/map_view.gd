# Draws a HexMap in world space. Domain is read-only; no gameplay state, no input.
# See res://domain/* and docs/RENDERING.md
class_name MapView
extends Node2D

const HexMapScript = preload("res://domain/hex_map.gd")
# Preload coordinate script with map view for consistent headless class resolution; coords come from a_map.
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

@export var hex_tile_size: float = 32.0

var map
var layout

static func _terrain_to_color(terrain: int) -> Color:
	if terrain == HexMapScript.Terrain.PLAINS:
		return Color(0.50, 0.78, 0.47)
	if terrain == HexMapScript.Terrain.WATER:
		return Color(0.20, 0.45, 0.80)
	return Color(1.0, 0.0, 1.0)

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
		}
		out.append(entry)
		i = i + 1
	return out

func _ready() -> void:
	if map == null:
		map = HexMapScript.make_tiny_test_map()
	if layout == null:
		layout = HexLayoutScript.new()
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
		draw_colored_polygon(corners, col)
		j = j + 1
