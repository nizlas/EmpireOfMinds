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
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")

const FOREST_BACK_CLUMP_01: Texture2D = preload("res://assets/prototype/terrain/forest/forest_back_clump_01.png")
const FOREST_BACK_CLUMP_02: Texture2D = preload("res://assets/prototype/terrain/forest/forest_back_clump_02.png")

## Phase **4.6g** — raster back clump choice (**4100–4199** band; **do** **not** overlap **4.6e** **foreground** salts).
const _SALT_BACK_ASSET_TEX: int = 4100
## Phase **4.6h** — **back** symbol scatter (**4200–4299**).
const _SALT_BACK_SYM_COUNT: int = 4200
const _SALT_BACK_SYM_BASE: int = 4210
const _EOM_ENV_FOREST_GRID_PERFECT: String = "EOM_DEBUG_FOREST_GRID_PERFECT"

const _PLAINS_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/plains_painterly.png"
const _GRASSLAND_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/grassland_painterly.png"
const _PLAINS_HILLS_OVERLAY_LEGACY_PATH: String = "res://assets/prototype/terrain/plains_hills_overlay.png"
const _GRASSLAND_HILLS_OVERLAY_LEGACY_PATH: String = "res://assets/prototype/terrain/grassland_hills_overlay.png"
## Numbered **`plains_hills_overlay_1.png`** … **`_4.png`** (and grassland); fallback to legacy single file if none found.
const _PLAINS_HILLS_OVERLAY_STEM: String = "plains_hills_overlay"
const _GRASSLAND_HILLS_OVERLAY_STEM: String = "grassland_hills_overlay"
const _WATER_TERRAIN_TEX_PATH: String = "res://assets/prototype/terrain/water_painterly.png"

@export var hex_tile_size: float = 128.0
## World units per one UV tile along X/Y; larger = less frequent texture repeat (presentation-only).
@export var terrain_texture_world_scale: float = 512.0
## Visual-only tint on **PLAINS** **HILLS** overlay decal (RGB clamped ~0.75–1.25; alpha folded with **`plains_hills_overlay_opacity`**). Not gameplay.
@export var plains_hills_terrain_modulate: Color = Color.WHITE
## Visual-only tint on **GRASSLAND** **HILLS** overlay decal (same clamp; alpha folded with **`grassland_hills_overlay_opacity`**). Not gameplay.
@export var grassland_hills_terrain_modulate: Color = Color.WHITE
## Inner hex fraction for the HILLS overlay (lerp from center toward full **HexLayout** corners). Confines decal inside the hex.
@export_range(0.1, 1.0) var hills_overlay_scale: float = 1.0
## **PLAINS** **HILLS** overlay alpha multiplier after per-channel tint (presentation-only).
@export_range(0.0, 1.0) var plains_hills_overlay_opacity: float = 0.45
## **GRASSLAND** **HILLS** overlay alpha multiplier after per-channel tint (presentation-only).
@export_range(0.0, 1.0) var grassland_hills_overlay_opacity: float = 0.40
## Sample a tighter rect of the overlay texture around **(0.5,0.5)** in UV space. **1.0** = full texture on the polygon; **> 1.0** zooms **in** (crops transparent PNG borders so the hill mass looks larger); **< 1.0** zooms out.
@export_range(0.5, 2.0) var hills_overlay_uv_zoom: float = 1.24
## When **true**, after each hills overlay draw: outline the **scaled** overlay polygon and the **full** hex in debug colors (presentation-only).
@export var debug_draw_hills_overlay_bounds: bool = false
## **Diagnostic only:** each HILLS overlay draw uses **full hex** scale, **UV zoom 2**, **opacity 1** so tuning/smoke clearly hits **`_draw_hills_overlay`**. Default **off**; do not ship enabled in scenes.
@export var debug_force_hills_overlay_extreme: bool = false
## When **true**, prints one **`[EOM_MAP_PRESENTATION_AUDIT]`** line per **`_draw`** with hex/terrain/forest counters (prototype instrumentation only).
@export var debug_map_presentation_audit: bool = false
## When **true**, prints **`[EOM_DEBUG_FOREST_PIPELINE]`** / related MapView **`[EOM_DEBUG_FOREST_GRID]`** lines each **`_draw`** (off by default to avoid editor drag from console I/O).
@export var debug_mapview_forest_pipeline_log: bool = false
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
## Prototype / visual-review only: when non-empty, forest decoration gates use this hex set instead of `forest_density_ratio`.
## Not gameplay forest, not a production biome (see `PlainsForestScript` and `main.gd`). Empty everywhere else — default hash gate unchanged.
var forest_decoration_override: Dictionary = {}
## **Headless / isolated debug:** count of **back** forest draw calls (**symbols** / **asset** / **procedural**) this **`MapView._draw`**; **`TerrainForegroundView`** reads it after **`MapView`** draws.
var debug_plains_back_forest_draw_calls: int = 0
## **Headless / debug:** HILLS overlay **`draw_colored_polygon`** calls this **`MapView._draw`** (decal only; base terrain unchanged).
var debug_hills_overlay_draws: int = 0
## **Pipeline debug:** back-forest **symbol** scatter draw count this frame (**MapView** only).
var debug_plains_back_symbol_draws: int = 0
## **Pipeline debug:** back-forest **asset** patch draw count this frame.
var debug_plains_back_asset_draws: int = 0
## **Pipeline debug:** back-forest **procedural** draw count this frame.
var debug_plains_back_procedural_draws: int = 0

var _plains_terrain_tex: Texture2D
var _grassland_terrain_tex: Texture2D
var _plains_hills_overlay_textures: Array[Texture2D] = []
var _grassland_hills_overlay_textures: Array[Texture2D] = []
var _water_terrain_tex: Texture2D
var _hills_overlay_plains_missing_logged: bool = false
var _hills_overlay_grassland_missing_logged: bool = false
var _forest_tree_symbols: Array[Texture2D] = []  # Cached tree symbol textures (building blocks for forest decoration).
var _forest_symbol_scatter_unavailable_logged: bool = false

const _TREE_SYMBOL_COUNT: int = 20
const _HILLS_TEX_MOD_MIN: float = 0.75
const _HILLS_TEX_MOD_MAX: float = 1.25

static func _terrain_to_color(terrain: int) -> Color:
	# Phase 4.1 — readable prototype palette (parchment land vs calm water). Not final art.
	if terrain == HexMapScript.Terrain.PLAINS:
		return Color(0.74, 0.67, 0.52)
	if terrain == HexMapScript.Terrain.WATER:
		return Color(0.28, 0.46, 0.62)
	if terrain == HexMapScript.Terrain.GRASSLAND:
		return Color(0.55, 0.70, 0.42)
	return Color(1.0, 0.0, 1.0)


static func _texture_for_land(terrain: int, plains: Texture2D, grassland: Texture2D, water: Texture2D) -> Texture2D:
	if terrain == HexMapScript.Terrain.WATER:
		return water
	if terrain == HexMapScript.Terrain.PLAINS:
		return plains
	if terrain == HexMapScript.Terrain.GRASSLAND:
		return grassland
	return null


## Base **HILLS** overlay opacity for this terrain (**PLAINS** / **GRASSLAND** only in practice). Other terrains → **0.0**.
static func _hills_overlay_base_opacity_for_terrain(
	terrain: int, plains_hills_opacity: float, grassland_hills_opacity: float
) -> float:
	if terrain == HexMapScript.Terrain.PLAINS:
		return plains_hills_opacity
	if terrain == HexMapScript.Terrain.GRASSLAND:
		return grassland_hills_opacity
	return 0.0


## Effective overlay tuning after optional **`debug_force_hills_overlay_extreme`** (same clamps as draw path). **x** = scale, **y** = uv_zoom, **z** = opacity.
static func _hills_overlay_effective_tuning(
	debug_force_extreme: bool,
	scale: float,
	uv_zoom: float,
	opacity: float
) -> Vector3:
	var es: float = scale
	var ez: float = uv_zoom
	var eo: float = opacity
	if debug_force_extreme:
		es = 1.0
		ez = 2.0
		eo = 1.0
	return Vector3(clampf(es, 0.1, 1.0), clampf(ez, 0.5, 2.0), clampf(eo, 0.0, 1.0))


## Tint + alpha for **HILLS** overlay draw only. **WATER** and unknown terrain → transparent.
static func _hills_overlay_tint_channels(
	terrain: int,
	plains_hills_mod: Color,
	grassland_hills_mod: Color,
	opacity: float
) -> Color:
	var op: float = clampf(opacity, 0.0, 1.0)
	if terrain == HexMapScript.Terrain.WATER:
		return Color(1.0, 1.0, 1.0, 0.0)
	var raw: Color = Color.WHITE
	if terrain == HexMapScript.Terrain.PLAINS:
		raw = plains_hills_mod
	elif terrain == HexMapScript.Terrain.GRASSLAND:
		raw = grassland_hills_mod
	else:
		return Color(1.0, 1.0, 1.0, 0.0)
	return Color(
		clampf(raw.r, _HILLS_TEX_MOD_MIN, _HILLS_TEX_MOD_MAX),
		clampf(raw.g, _HILLS_TEX_MOD_MIN, _HILLS_TEX_MOD_MAX),
		clampf(raw.b, _HILLS_TEX_MOD_MIN, _HILLS_TEX_MOD_MAX),
		clampf(raw.a * op, 0.0, 1.0)
	)


## True when **HILLS** overlay should draw on land (presentation-only).
static func _hills_overlay_eligible(terrain: int, landform: int) -> bool:
	if landform != HexMapScript.Landform.HILLS:
		return false
	return terrain == HexMapScript.Terrain.PLAINS or terrain == HexMapScript.Terrain.GRASSLAND


## Deterministic **HILLS** overlay variant **0..variant_count-1** from axial coords (no RNG). **terrain** salts the hash so PLAINS vs GRASSLAND families differ. Safe when **`variant_count <= 0`** (returns **0**).
static func _hills_overlay_variant_index_for_coord(coord, terrain: int, variant_count: int) -> int:
	if variant_count <= 0:
		return 0
	var q: int = int(coord.q)
	var r: int = int(coord.r)
	var salt: int = 0x48494C53 + terrain * 1022222933
	var h: int = MapView._terrain_detail_hash(q, r, salt)
	return h % variant_count


## **True** when **`texs`** has at least one non-null **Texture2D**.
static func _hills_overlay_family_has_texture(texs: Array) -> bool:
	var i: int = 0
	while i < texs.size():
		if texs[i] != null:
			return true
		i += 1
	return false


## First texture in the family for **terrain** (convenience / tests). **`plains_texs`** / **`grass_texs`** are **Array** of **Texture2D**.
static func _hills_overlay_texture_for_terrain(
	terrain: int, plains_texs: Array, grass_texs: Array
) -> Texture2D:
	if terrain == HexMapScript.Terrain.PLAINS:
		if plains_texs.size() < 1:
			return null
		return plains_texs[0] as Texture2D
	if terrain == HexMapScript.Terrain.GRASSLAND:
		if grass_texs.size() < 1:
			return null
		return grass_texs[0] as Texture2D
	return null


static func _hills_overlay_will_draw(
	terrain: int,
	landform: int,
	plains_texs: Array,
	grass_texs: Array
) -> bool:
	if not MapView._hills_overlay_eligible(terrain, landform):
		return false
	if terrain == HexMapScript.Terrain.PLAINS:
		return MapView._hills_overlay_family_has_texture(plains_texs)
	if terrain == HexMapScript.Terrain.GRASSLAND:
		return MapView._hills_overlay_family_has_texture(grass_texs)
	return false


static func _hex_overlay_polygon_world(world_center: Vector2, scale: float) -> PackedVector2Array:
	var t: float = clampf(scale, 0.0, 1.0)
	var layout_tmp = HexLayoutScript.new()
	var corners: PackedVector2Array = layout_tmp.hex_corners(world_center)
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(6)
	var i: int = 0
	while i < 6:
		out[i] = world_center.lerp(corners[i], t)
		i += 1
	return out


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


## Hex-local UVs in the 0..1 square; corners may be full **HexLayout** hex or inner scaled polygon — **`extent_scale`** scales the AABB denominator (1.0 = default full hex). **`uv_zoom`**: 1.0 = unchanged; > 1.0 pulls UVs toward 0.5 (zoom into texture center).
static func _hex_local_corner_uvs(
	corners_world: PackedVector2Array, world_center: Vector2, extent_scale: float = 1.0, uv_zoom: float = 1.0
) -> PackedVector2Array:
	var n = corners_world.size()
	var uvs = PackedVector2Array()
	uvs.resize(n)
	if n == 0:
		return uvs
	var es: float = maxf(extent_scale, 0.0001)
	var inv_w: float = 1.0 / (sqrt(3.0) * HexLayoutScript.SIZE * es)
	var inv_h: float = 1.0 / (2.0 * HexLayoutScript.SIZE * es)
	var uz: float = maxf(uv_zoom, 0.001)
	var i = 0
	while i < n:
		var d: Vector2 = corners_world[i] - world_center
		var uv: Vector2 = Vector2(d.x * inv_w + 0.5, d.y * inv_h + 0.5)
		uv = Vector2(0.5, 0.5) + (uv - Vector2(0.5, 0.5)) / uz
		uvs[i] = uv
		i += 1
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


## Load **Texture2D** only if **`path`** exists (no warning when missing — for optional numbered overlays).
static func _try_load_terrain_tex_if_exists(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		return null
	if res is Texture2D:
		return res as Texture2D
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
	if terrain == HexMapScript.Terrain.PLAINS or terrain == HexMapScript.Terrain.GRASSLAND:
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
			"landform": a_map.landform_at(coord),
		}
		out.append(entry)
		i = i + 1
	return out

func _load_hills_overlay_family(stem: String, legacy_path: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var vi: int = 1
	while vi <= 4:
		var numbered: String = "res://assets/prototype/terrain/%s_%d.png" % [stem, vi]
		var tnum: Texture2D = MapView._try_load_terrain_tex_if_exists(numbered)
		if tnum != null:
			out.append(tnum)
		vi += 1
	if out.is_empty():
		var leg: Texture2D = MapView._try_load_terrain_tex_if_exists(legacy_path)
		if leg != null:
			out.append(leg)
	return out


func _ready() -> void:
	# **`map`** / **`layout`** are wired by **`main.gd`** after **`_ready`** (local or cloud). Do not
	# install **`make_tiny_test_map()`** here — cloud bootstrap must not paint local fallback terrain.
	# Headless tests that need a map set **`map`** / **`layout`** on **`MapView`** explicitly.
	_plains_terrain_tex = MapView._try_load_terrain_tex(_PLAINS_TERRAIN_TEX_PATH)
	_grassland_terrain_tex = MapView._try_load_terrain_tex(_GRASSLAND_TERRAIN_TEX_PATH)
	_plains_hills_overlay_textures = _load_hills_overlay_family(
		_PLAINS_HILLS_OVERLAY_STEM, _PLAINS_HILLS_OVERLAY_LEGACY_PATH
	)
	_grassland_hills_overlay_textures = _load_hills_overlay_family(
		_GRASSLAND_HILLS_OVERLAY_STEM, _GRASSLAND_HILLS_OVERLAY_LEGACY_PATH
	)
	if _plains_hills_overlay_textures.is_empty():
		if not _hills_overlay_plains_missing_logged:
			push_warning(
				(
					"MapView: no plains hills overlay textures (expected optional plains_hills_overlay_1..4.png or plains_hills_overlay.png)"
				)
			)
			_hills_overlay_plains_missing_logged = true
	if _grassland_hills_overlay_textures.is_empty():
		if not _hills_overlay_grassland_missing_logged:
			push_warning(
				(
					"MapView: no grassland hills overlay textures (expected optional grassland_hills_overlay_1..4.png or grassland_hills_overlay.png)"
				)
			)
			_hills_overlay_grassland_missing_logged = true
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


## **Skip MapView back-forest** when **`TerrainForegroundView`** is wired (it owns forest presentation) or debug suppression applies.
func _mapview_skip_back_forest_overlay() -> bool:
	return terrain_foreground_view != null and is_instance_valid(terrain_foreground_view)


func _projected_corners(proj, corners: PackedVector2Array) -> PackedVector2Array:
	var out = PackedVector2Array()
	out.resize(corners.size())
	var i = 0
	while i < corners.size():
		out[i] = proj.to_presentation(corners[i])
		i += 1
	return out


func _draw_closed_polyline(pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var line: PackedVector2Array = pts.duplicate()
	line.append(pts[0])
	draw_polyline(line, col, width, true)


func _draw_debug_cross_pres(center_pres: Vector2, col: Color, arm: float, width: float) -> void:
	draw_line(center_pres + Vector2(-arm, 0.0), center_pres + Vector2(arm, 0.0), col, width, true)
	draw_line(center_pres + Vector2(0.0, -arm), center_pres + Vector2(0.0, arm), col, width, true)


func _hills_overlay_texture_for_hex(coord, terrain: int) -> Texture2D:
	if terrain != HexMapScript.Terrain.PLAINS and terrain != HexMapScript.Terrain.GRASSLAND:
		return null
	var texs: Array[Texture2D] = (
		_plains_hills_overlay_textures
		if terrain == HexMapScript.Terrain.PLAINS
		else _grassland_hills_overlay_textures
	)
	var n: int = texs.size()
	if n == 0:
		return null
	var idx: int = MapView._hills_overlay_variant_index_for_coord(coord, terrain, n)
	return texs[idx]


func _draw_hills_overlay(proj, world_center: Vector2, terrain: int, coord) -> void:
	var ov_tex: Texture2D = _hills_overlay_texture_for_hex(coord, terrain)
	if ov_tex == null:
		return
	var base_opacity: float = MapView._hills_overlay_base_opacity_for_terrain(
		terrain, plains_hills_overlay_opacity, grassland_hills_overlay_opacity
	)
	var eff: Vector3 = MapView._hills_overlay_effective_tuning(
		debug_force_hills_overlay_extreme, hills_overlay_scale, hills_overlay_uv_zoom, base_opacity
	)
	var sc: float = eff.x
	var poly_world: PackedVector2Array = MapView._hex_overlay_polygon_world(world_center, sc)
	var poly_pres: PackedVector2Array = _projected_corners(proj, poly_world)
	var uvs: PackedVector2Array = MapView._hex_local_corner_uvs(poly_world, world_center, sc, eff.y)
	var tint: Color = MapView._hills_overlay_tint_channels(
		terrain, plains_hills_terrain_modulate, grassland_hills_terrain_modulate, eff.z
	)
	draw_colored_polygon(poly_pres, tint, uvs, ov_tex)
	debug_hills_overlay_draws += 1
	if debug_draw_hills_overlay_bounds:
		var hex_full_world: PackedVector2Array = MapView._hex_overlay_polygon_world(world_center, 1.0)
		var hex_full_pres: PackedVector2Array = _projected_corners(proj, hex_full_world)
		var center_pres: Vector2 = proj.to_presentation(world_center)
		_draw_closed_polyline(hex_full_pres, Color(1.0, 0.95, 0.0, 1.0), 4.0)
		_draw_closed_polyline(poly_pres, Color(1.0, 0.0, 1.0, 1.0), 4.5)
		_draw_debug_cross_pres(center_pres, Color(0.15, 1.0, 0.25, 1.0), 14.0, 3.5)


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
	debug_hills_overlay_draws = 0
	var items = compute_draw_items(map, layout)
	var dbg_perf_plains_back_suppressed: int = 0
	var audit: bool = debug_map_presentation_audit
	var aud_water: int = 0
	var aud_tex: int = 0
	var aud_plains_flat: int = 0
	var aud_plains_hills: int = 0
	var aud_grass_flat: int = 0
	var aud_grass_hills: int = 0
	var aud_forest_decor: int = 0
	var tfv_suppress: bool = (
		_forest_grid_map_back_suppressed()
		or _mapview_skip_back_forest_overlay()
	)
	var j = 0
	while j < items.size():
		var item = items[j]
		var corners = item["corners"]
		var col = item["color"]
		var terrain: int = int(item["terrain"])
		var landform: int = int(item.get("landform", HexMapScript.Landform.FLAT))
		var corners_draw = _projected_corners(camera, corners)
		var tex: Texture2D = MapView._texture_for_land(terrain, _plains_terrain_tex, _grassland_terrain_tex, _water_terrain_tex)
		if tex != null:
			if audit:
				aud_tex += 1
				if terrain == HexMapScript.Terrain.WATER:
					aud_water += 1
				elif terrain == HexMapScript.Terrain.PLAINS:
					if landform == HexMapScript.Landform.HILLS:
						aud_plains_hills += 1
					else:
						aud_plains_flat += 1
				elif terrain == HexMapScript.Terrain.GRASSLAND:
					if landform == HexMapScript.Landform.HILLS:
						aud_grass_hills += 1
					else:
						aud_grass_flat += 1
			var uvs: PackedVector2Array = MapView._world_anchored_corner_uvs(corners, terrain_texture_world_scale)
			draw_colored_polygon(corners_draw, Color.WHITE, uvs, tex)
		else:
			draw_colored_polygon(corners_draw, col)
		var coord = item["coord"]
		_draw_terrain_detail_overlay(camera, item["world"] as Vector2, terrain, coord.q, coord.r)
		if MapView._hills_overlay_will_draw(
			terrain, landform, _plains_hills_overlay_textures, _grassland_hills_overlay_textures
		):
			_draw_hills_overlay(camera, item["world"] as Vector2, terrain, coord)
		if terrain == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated_with_override(
				coord.q, coord.r, forest_density_ratio, forest_decoration_override
			):
				if audit:
					aud_forest_decor += 1
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
	if audit:
		var eff_plains: Vector3 = MapView._hills_overlay_effective_tuning(
			debug_force_hills_overlay_extreme,
			hills_overlay_scale,
			hills_overlay_uv_zoom,
			plains_hills_overlay_opacity
		)
		var eff_grass: Vector3 = MapView._hills_overlay_effective_tuning(
			debug_force_hills_overlay_extreme,
			hills_overlay_scale,
			hills_overlay_uv_zoom,
			grassland_hills_overlay_opacity
		)
		print(
			(
				"[EOM_MAP_PRESENTATION_AUDIT] map_cells=%d draw_items=%d textured_hex=%d water_tex=%d plains_flat=%d plains_hills=%d grass_flat=%d grass_hills=%d hills_overlay_scale=%.2f plains_hills_overlay_opacity=%.2f grassland_hills_overlay_opacity=%.2f hills_overlay_uv_zoom=%.2f debug_force_hills_overlay_extreme=%s effective_scale=%.2f effective_uv_zoom=%.2f effective_opacity_plains=%.2f effective_opacity_grassland=%.2f plains_hills_overlay_variants_loaded=%d grassland_hills_overlay_variants_loaded=%d hills_overlay_draws=%d forest_decor_hex=%d map_back_sym=%d map_back_asset=%d map_back_proc=%d tfv_grid_sym_prev=%d units_on_canvas_prev=%d cities_on_canvas_prev=%d | counts_after_mapview_other_layers_are_previous_frame"
			)
			% [
				map.size(),
				items.size(),
				aud_tex,
				aud_water,
				aud_plains_flat,
				aud_plains_hills,
				aud_grass_flat,
				aud_grass_hills,
				hills_overlay_scale,
				plains_hills_overlay_opacity,
				grassland_hills_overlay_opacity,
				hills_overlay_uv_zoom,
				debug_force_hills_overlay_extreme,
				eff_plains.x,
				eff_plains.y,
				eff_plains.z,
				eff_grass.z,
				_plains_hills_overlay_textures.size(),
				_grassland_hills_overlay_textures.size(),
				debug_hills_overlay_draws,
				aud_forest_decor,
				debug_plains_back_symbol_draws,
				debug_plains_back_asset_draws,
				debug_plains_back_procedural_draws,
				TerrainForegroundViewScript.debug_pipeline_tfv_grid_symbols,
				UnitsViewScript.debug_last_units_drawn_on_own_canvas,
				CitiesViewScript.debug_last_city_markers_drawn_on_own_canvas,
			]
		)
	if debug_mapview_forest_pipeline_log:
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
					"[EOM_DEBUG_FOREST_GRID] MapView: skipped back-forest on %d decorated PLAINS hexes (TFV wired and/or debug suppression); debug_plains_back_forest_draw_calls=%d"
				)
				% [dbg_perf_plains_back_suppressed, debug_plains_back_forest_draw_calls]
			)
