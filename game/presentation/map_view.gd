# Draws a HexMap in world space. Domain is read-only; no gameplay state, no input.
# Forest decoration (4.6h): composed scatter of tree symbol rasters under tree_symbols/ on decorated PLAINS.
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

const FOREST_BACK_CLUMP_01: Texture2D = preload("res://assets/prototype/terrain/forest/forest_back_clump_01.png")
const FOREST_BACK_CLUMP_02: Texture2D = preload("res://assets/prototype/terrain/forest/forest_back_clump_02.png")

## Phase **4.6g** — raster back clump choice (**4100–4199** band; **do** **not** overlap **4.6e** **foreground** salts).
const _SALT_BACK_ASSET_TEX: int = 4100
## Phase **4.6h** — **back** symbol scatter (**4200–4299**).
const _SALT_BACK_SYM_COUNT: int = 4200
const _SALT_BACK_SYM_BASE: int = 4210
const _EOM_ENV_FOREST_GRID_PERFECT: String = "EOM_DEBUG_FOREST_GRID_PERFECT"

const _PLAINS_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/plains_painterly.png"
const _WATER_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/water_painterly.png"

@export var hex_tile_size: float = 128.0
## World units per one UV tile along X/Y; larger = less frequent texture repeat (presentation-only).
@export var terrain_texture_world_scale: float = 512.0
## Phase 4.6b: fraction of PLAINS cells that get procedural forest *decoration* (not Terrain.FOREST).
@export_range(0.0, 1.0) var forest_density_ratio: float = 0.25
## Multiplies alpha of back-canopy circles/lines (Phase 4.6b-debug — keep muted but readable over terrain art).
@export_range(0.0, 3.0) var forest_back_opacity: float = 0.85
## Phase **4.6g:** **large** patch **back** (**MapView**); **off** when **4.6h** **symbol** scatter is primary.
@export var use_forest_asset_overlays: bool = false
@export_range(0.0, 1.0) var forest_back_asset_opacity: float = 0.90
## Phase **4.6h:** **`use_forest_symbol_scatter`** — **forest** **decoration** = composed **scatter** of **tree** **symbol** PNGs (**`tree_symbols/`**); optional **fallback** to **procedural**/ **patch**.
@export var use_forest_symbol_scatter: bool = true
@export_range(0.0, 1.0) var forest_back_symbol_opacity: float = 0.84

var map
var layout
## Wired by main; Phase 4.5m **MapCamera** (wraps **MapPlaneProjection** + plane offset). Defaults in _draw for headless safety.
var camera
## Optional **4.6q:** wired by **main** — when **`TerrainForegroundView`** perfect-grid debug is on, back-forest overlays are skipped (non-dotted); only **`MapView` terrain + detail** draw here. **`forest_grid_debug_isolated`** on TFV also suppresses back forest.
var terrain_foreground_view
## **Headless / isolated debug:** count of **back** forest draw calls (**symbols** / **asset** / **procedural**) this **`MapView._draw`**; **`TerrainForegroundView`** reads it after **`MapView`** draws.
var debug_plains_back_forest_draw_calls: int = 0
## **Pipeline debug:** back-forest **symbol** scatter draw count this frame (**MapView** only).
var debug_plains_back_symbol_draws: int = 0
## **Pipeline debug:** back-forest **asset** patch draw count this frame.
var debug_plains_back_asset_draws: int = 0
## **Pipeline debug:** back-forest **procedural** draw count this frame.
var debug_plains_back_procedural_draws: int = 0

var _plains_terrain_tex: Texture2D
var _water_terrain_tex: Texture2D
var _forest_tree_symbols: Array[Texture2D] = []  # Cached tree symbol textures (building blocks for forest decoration).
var _forest_symbol_scatter_unavailable_logged: bool = false

const _TREE_SYMBOL_COUNT: int = 20

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


static func _tree_symbol_res_path(idx_1_based: int) -> String:
	return "res://assets/prototype/terrain/tree_symbols/tree_symbol_%02d.png" % idx_1_based


static func _mix255_u(h: int, shift: int) -> float:
	return float((h >> shift) & 0xFF) / 255.0


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


func _draw_plains_forest_back_asset(proj, world: Vector2, q: int, r: int) -> void:
	# Phase 4.6g: **hex-owned** back clump; **below** units (**MapView** layer). **Deterministic** texture **01**/**02**.
	var anchor_pres: Vector2 = proj.to_presentation(world)
	var pscale: float = proj.perspective_scale_at(world)
	var h: float = HexLayoutScript.SIZE * pscale
	var wrect: float = h * 2.2
	var hrect: float = h * 1.7
	var tex: Texture2D = (
		FOREST_BACK_CLUMP_01
		if (PlainsForestScript.cell_mix(q, r, _SALT_BACK_ASSET_TEX) & 1) == 0
		else FOREST_BACK_CLUMP_02
	)
	var rect: Rect2 = Rect2(
		anchor_pres.x - wrect * 0.5,
		anchor_pres.y - hrect * 0.25,
		wrect,
		hrect
	)
	draw_texture_rect(
		tex,
		rect,
		false,
		Color(1.0, 1.0, 1.0, clampf(forest_back_asset_opacity, 0.0, 1.0))
	)


func _reload_forest_tree_symbols_if_needed() -> void:
	if _forest_tree_symbols.size() == _TREE_SYMBOL_COUNT:
		return
	_forest_tree_symbols.clear()
	var ii: int = 1
	while ii <= _TREE_SYMBOL_COUNT:
		var res = ResourceLoader.load(MapView._tree_symbol_res_path(ii), "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			_forest_tree_symbols.append(res as Texture2D)
		else:
			_forest_tree_symbols.clear()
			return
		ii += 1


func _forest_symbol_scatter_ready() -> bool:
	return _forest_tree_symbols.size() == _TREE_SYMBOL_COUNT


func _draw_plains_forest_back_symbols(proj, world: Vector2, q: int, r: int) -> void:
	# Phase 4.6k: **ellipse-fill** around **hub** (**anchor** **+** **(0,** **0.06×base)**); **no** **upper**-**arc** **zoning** — **full**-**hex** **forest** **mass**.
	# Phase 4.6n: density tuned **18..30 → 14..22** — moderate reduction from the 4.6m bump per visual review.
	# Placement / size formula unchanged; salts unchanged.
	var anchor_pres: Vector2 = proj.to_presentation(world)
	var pscale: float = proj.perspective_scale_at(world)
	var base: float = HexLayoutScript.SIZE * pscale
	var n_sym: int = 14 + (PlainsForestScript.cell_mix(q, r, _SALT_BACK_SYM_COUNT) % 9)
	var op: float = clampf(forest_back_symbol_opacity, 0.0, 1.0)
	var col: Color = Color(0.93, 0.87, 0.80, op)
	var hub: Vector2 = anchor_pres + Vector2(0.0, base * 0.06)
	var si: int = 0
	while si < n_sym:
		var h: int = PlainsForestScript.cell_mix(q, r, _SALT_BACK_SYM_BASE + si)
		var ti: int = h % _TREE_SYMBOL_COUNT
		var tex: Texture2D = _forest_tree_symbols[ti]
		# Perceived size ~1.7× prior 0.30..0.46 band; placement unchanged.
		var side: float = base * (0.51 + MapView._mix255_u(h, 8) * 0.27) * 0.5
		var ang: float = TAU * float((h >> 9) & 1023) / 1024.0
		var rad_scale: float = 0.30 + float((h >> 19) & 255) / 255.0 * 0.70
		var rx: float = base * (0.45 + MapView._mix255_u(h, 24) * 0.27)
		var ry: float = base * (0.30 + MapView._mix255_u(h, 0) * 0.28)
		var pr: Vector2 = hub + Vector2(cos(ang) * rx * rad_scale, sin(ang) * ry * rad_scale)
		draw_texture_rect(tex, Rect2(pr.x - side * 0.5, pr.y - side, side, side), false, col)
		si += 1


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
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw()

func _forest_grid_map_back_suppressed() -> bool:
	if OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1":
		return true
	if terrain_foreground_view != null and is_instance_valid(terrain_foreground_view):
		var tfv = terrain_foreground_view
		if bool(tfv.forest_grid_debug_perfect):
			return true
		if tfv.resolved_forest_grid_debug_suppress_map_back():
			return true
		if tfv.resolved_forest_grid_debug_isolated():
			return true
	return false


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
	debug_plains_back_forest_draw_calls = 0
	debug_plains_back_symbol_draws = 0
	debug_plains_back_asset_draws = 0
	debug_plains_back_procedural_draws = 0
	var items = compute_draw_items(map, layout)
	var dbg_perf_plains_back_suppressed: int = 0
	var tfv_suppress: bool = _forest_grid_map_back_suppressed()
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
				if tfv_suppress:
					# **4.6q:** **MapView** back scatter / asset / procedural (no TFV root dots) — optional suppress.
					dbg_perf_plains_back_suppressed += 1
				else:
					_reload_forest_tree_symbols_if_needed()
					if use_forest_symbol_scatter and _forest_symbol_scatter_ready():
						debug_plains_back_forest_draw_calls += 1
						debug_plains_back_symbol_draws += 1
						_draw_plains_forest_back_symbols(camera, item["world"] as Vector2, coord.q, coord.r)
					elif use_forest_asset_overlays:
						debug_plains_back_forest_draw_calls += 1
						debug_plains_back_asset_draws += 1
						_draw_plains_forest_back_asset(camera, item["world"] as Vector2, coord.q, coord.r)
					else:
						debug_plains_back_forest_draw_calls += 1
						debug_plains_back_procedural_draws += 1
						_draw_plains_forest_back(camera, item["world"] as Vector2, coord.q, coord.r)
		j = j + 1
	var iso_f: bool = false
	var perf_f: bool = false
	var sup_f: bool = false
	var tfv_ok: bool = terrain_foreground_view != null and is_instance_valid(terrain_foreground_view)
	if tfv_ok:
		var tfvx = terrain_foreground_view
		iso_f = bool(tfvx.resolved_forest_grid_debug_isolated())
		perf_f = bool(tfvx.forest_grid_debug_perfect)
		sup_f = bool(tfvx.resolved_forest_grid_debug_suppress_map_back())
	print(
		(
			"[EOM_DEBUG_FOREST_PIPELINE] MapView forest suppression: isolated=%s perfect=%s suppress_map_back=%s suppressed_hexes=%d back_draws_total=%d back_sym=%d back_asset=%d back_proc=%d tfv_wired=%s"
		)
		% [
			iso_f,
			perf_f,
			sup_f,
			dbg_perf_plains_back_suppressed,
			debug_plains_back_forest_draw_calls,
			debug_plains_back_symbol_draws,
			debug_plains_back_asset_draws,
			debug_plains_back_procedural_draws,
			tfv_ok,
		]
	)
	if tfv_suppress and dbg_perf_plains_back_suppressed > 0:
		print(
			(
				"[EOM_DEBUG_FOREST_GRID] MapView: suppressed back-forest on %d decorated PLAINS hexes (TFV perfect / suppress_map_back / forest_grid_debug_isolated); debug_plains_back_forest_draw_calls=%d"
			)
			% [dbg_perf_plains_back_suppressed, debug_plains_back_forest_draw_calls]
		)
