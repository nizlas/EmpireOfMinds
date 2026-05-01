# Draws a HexMap in world space. Domain is read-only; no gameplay state, no input.
# See res://domain/* and docs/RENDERING.md
class_name MapView
extends Node2D

const HexMapScript = preload("res://domain/hex_map.gd")
# Preload coordinate script with map view for consistent headless class resolution; coords come from a_map.
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")

const _PLAINS_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/plains_painterly.png"
const _WATER_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/water_painterly.png"

@export var hex_tile_size: float = 128.0
## World units per one UV tile along X/Y; larger = less frequent texture repeat (presentation-only).
@export var terrain_texture_world_scale: float = 512.0
## Phase 4.6b: fraction of PLAINS cells that get procedural forest *decoration* (not Terrain.FOREST).
@export_range(0.0, 1.0) var forest_density_ratio: float = 0.25
## Multiplies alpha of back-canopy circles/lines (Phase 4.6b-debug — keep muted but readable over terrain art).
@export_range(0.0, 3.0) var forest_back_opacity: float = 1.0

var map
var layout
## Wired by main; Phase 4.5m **MapCamera** (wraps **MapPlaneProjection** + plane offset). Defaults in _draw for headless safety.
var camera

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

static func _terrain_detail_hash(q: int, r: int, salt: int) -> int:
	# Deterministic mixing for Phase 4.1e procedural marks (presentation-only; no RNG).
	return (q * 374761393 + r * 668265263 + salt * 1442695041) & 0x7FFFFFFF

func _draw_plains_detail(proj, world: Vector2, q: int, r: int) -> void:
	var lim: float = HexLayoutScript.SIZE * 0.82
	var k: int = 0
	while k < 5:
		var h: int = MapView._terrain_detail_hash(q, r, k + 11)
		var ang: float = (float(h % 6283) / 6283.0) * TAU
		var rad: float = 14.0 + float((h >> 8) % 52)
		if rad > lim:
			rad = lim - 4.0
		var p: Vector2 = world + Vector2(cos(ang), sin(ang)) * rad
		var al: float = 0.075 + float((h >> 4) & 3) * 0.025
		draw_circle(proj.to_presentation(p), 1.0 + float((h >> 2) & 3) * 0.35, Color(0.40, 0.32, 0.20, al))
		k += 1
	var s: int = 0
	while s < 3:
		var h2: int = MapView._terrain_detail_hash(q, r, s + 99)
		var a0: float = (float(h2 % 360) * PI / 180.0)
		var r0: float = 22.0 + float((h2 >> 10) % 38)
		if r0 > lim:
			r0 = lim - 6.0
		var len: float = 7.0 + float((h2 >> 14) & 15)
		var p0: Vector2 = world + Vector2(cos(a0), sin(a0)) * r0
		var p1: Vector2 = p0 + Vector2(cos(a0 + 0.55), sin(a0 + 0.55)) * len
		draw_line(
			proj.to_presentation(p0),
			proj.to_presentation(p1),
			Color(0.35, 0.45, 0.22, 0.085),
			1.0,
			true
		)
		s += 1

func _draw_water_detail(proj, world: Vector2, q: int, r: int) -> void:
	var lim: float = HexLayoutScript.SIZE * 0.85
	var widx: int = 0
	while widx < 5:
		var h: int = MapView._terrain_detail_hash(q, r, widx + 777)
		var yoff: float = -34.0 + float(h % 69)
		var x0: float = -40.0 + float((h >> 5) % 81)
		var x1: float = x0 + 9.0 + float((h >> 11) % 30)
		var dy: float = float((h >> 17) % 9) - 4.0
		var p0: Vector2 = world + Vector2(x0, yoff)
		var p1: Vector2 = world + Vector2(x1, yoff + dy)
		if p0.distance_to(world) <= lim and p1.distance_to(world) <= lim:
			draw_line(
				proj.to_presentation(p0),
				proj.to_presentation(p1),
				Color(0.82, 0.90, 0.98, 0.06),
				1.0,
				true
			)
		widx += 1

func _draw_terrain_detail_overlay(proj, world: Vector2, terrain: int, q: int, r: int) -> void:
	if terrain == HexMapScript.Terrain.PLAINS:
		_draw_plains_detail(proj, world, q, r)
	elif terrain == HexMapScript.Terrain.WATER:
		_draw_water_detail(proj, world, q, r)


func _draw_plains_forest_back(proj, world: Vector2, q: int, r: int) -> void:
	# Phase 4.6b / 4.6b-polish: 2–3 large overlapping canopy masses (fewer, bigger than speckle pass).
	var op: float = forest_back_opacity
	var size: float = HexLayoutScript.SIZE
	var n_clumps: int = 2 + (PlainsForestScript.cell_mix(q, r, 701) % 2)
	var c: int = 0
	while c < n_clumps:
		var h0: int = PlainsForestScript.cell_mix(q, r, 810 + c * 17)
		var base_ang: float = deg_to_rad(198.0 + float(h0 % 95))
		var base_dist: float = size * (0.20 + float((h0 >> 7) % 28) / 100.0)
		var hub: Vector2 = world + Vector2(cos(base_ang), sin(base_ang)) * base_dist
		var b: int = 0
		while b < 3:
			var hb: int = PlainsForestScript.cell_mix(q, r, 830 + c * 11 + b)
			var da: float = deg_to_rad(float(hb % 70) - 35.0)
			var dd: float = size * (0.06 + float((hb >> 8) % 18) / 100.0)
			var pw: Vector2 = hub + Vector2(cos(base_ang + da), sin(base_ang + da)) * dd
			var pr: Vector2 = proj.to_presentation(pw)
			var rr: float = 11.0 + float((hb >> 4) & 7) * 1.35
			var fill_a: float = (0.11 + float((hb >> 12) & 3) * 0.025) * op
			draw_circle(
				pr,
				rr,
				Color(0.20, 0.40, 0.24, clampf(fill_a, 0.0, 1.0))
			)
			b += 1
		if (PlainsForestScript.cell_mix(q, r, 860 + c) & 1) == 0:
			var hp: int = PlainsForestScript.cell_mix(q, r, 870 + c)
			var hx: Vector2 = proj.to_presentation(hub)
			var rx: float = 14.0 + float((hp >> 5) & 7) * 1.2
			var ry: float = 10.0 + float((hp >> 8) & 7) * 1.0
			var skew: float = deg_to_rad(float((hp >> 11) % 40) - 20.0)
			var cs: float = cos(skew)
			var sn: float = sin(skew)
			var poly: PackedVector2Array = PackedVector2Array([
				hx + Vector2(-rx * cs + 0.3 * ry * sn, -rx * sn - 0.3 * ry * cs),
				hx + Vector2(rx * cs + 0.2 * ry * sn, rx * sn - 0.2 * ry * cs),
				hx + Vector2(0.45 * rx * cs - ry * sn, 0.45 * rx * sn + ry * cs),
				hx + Vector2(-0.35 * rx * cs - 0.75 * ry * sn, -0.35 * rx * sn + 0.75 * ry * cs),
			])
			var pa: float = (0.08 + float((hp >> 14) & 3) * 0.018) * op
			draw_colored_polygon(poly, Color(0.22, 0.36, 0.22, clampf(pa, 0.0, 1.0)))
		c += 1


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

func _projected_corners(proj, corners: PackedVector2Array) -> PackedVector2Array:
	var out = PackedVector2Array()
	out.resize(corners.size())
	var i = 0
	while i < corners.size():
		out[i] = proj.to_presentation(corners[i])
		i += 1
	return out

func _draw() -> void:
	if map == null or layout == null:
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	var items = compute_draw_items(map, layout)
	var j = 0
	while j < items.size():
		var item = items[j]
		var corners = item["corners"]
		var col = item["color"]
		var terrain: int = int(item["terrain"])
		var corners_draw = _projected_corners(camera, corners)
		var tex: Texture2D
		if terrain == HexMapScript.Terrain.PLAINS:
			tex = _plains_terrain_tex
		elif terrain == HexMapScript.Terrain.WATER:
			tex = _water_terrain_tex
		else:
			tex = null
		if tex != null:
			# UVs stay anchored to layout/world corners (4.1d); polygons use projected screen positions (4.5c).
			var uvs = MapView._world_anchored_corner_uvs(corners, terrain_texture_world_scale)
			draw_colored_polygon(corners_draw, Color.WHITE, uvs, tex)
		else:
			draw_colored_polygon(corners_draw, col)
		var coord = item["coord"]
		_draw_terrain_detail_overlay(camera, item["world"] as Vector2, terrain, coord.q, coord.r)
		if terrain == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated(coord.q, coord.r, forest_density_ratio):
				_draw_plains_forest_back(camera, item["world"] as Vector2, coord.q, coord.r)
		j = j + 1
