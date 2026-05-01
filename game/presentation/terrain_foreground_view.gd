# Procedural PLAINS-only forest foreground (Phase 4.6b–4.6d). Drawn above UnitsView; no input; no domain rules.
# Phase 4.6c/4.6d: optional unit-aware occluder is **additive** on top of terrain-owned foreground (never replaces it).
# See docs/RENDERING.md
extends Node2D

const HexMapScript = preload("res://domain/hex_map.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")

@export_range(0.0, 1.0) var forest_density_ratio: float = 0.25
@export_range(0.0, 1.0) var forest_front_opacity: float = 0.72
## Matches **UnitsView.unit_icon_height_ratio** for **`side`**; **main.gd** overwrites from **UnitsView** when wired.
@export_range(0.05, 1.2) var foreground_unit_reference_height_ratio: float = 0.70
## Presentation-space hub: **anchor_pres.y − side ×** this (feet / lower-leg overlap test).
@export_range(0.0, 0.45) var unit_occluder_y_ratio: float = 0.18
@export_range(0.1, 1.0) var unit_occluder_width_ratio: float = 0.45
@export_range(0.05, 0.55) var unit_occluder_height_ratio: float = 0.28
## Multiplies alphas for the larger unit-aware mass only (tune if occluder dominates).
@export_range(0.0, 1.5) var unit_occluder_opacity_scale: float = 0.88
## **4.6d:** If **true**, draw **extra** unit-anchored occluder on occupied decorated hexes (no city). Terrain-owned foreground always draws first.
@export var enable_unit_occlusion_test: bool = true
## One-shot: prints PLAINS / decorated counts and density (editor or F5 run); no per-frame spam.
@export var forest_debug_log_counts_once: bool = false

## Read-only **Scenario** for **units_at** / **cities_at** (presentation-only); **null** → general foreground only.
var scenario
var map
var layout
var camera
var _forest_counts_logged: bool = false

func _ready() -> void:
	queue_redraw()

func _draw_unit_forest_occluder(anchor_pres: Vector2, side: float, q: int, r: int) -> void:
	# Phase 4.6c: large mass anchored to unit marker size — overlaps lower legs/feet, not torso (tune Y/opacity).
	var op: float = forest_front_opacity * unit_occluder_opacity_scale
	var w: float = side * unit_occluder_width_ratio
	var h: float = side * unit_occluder_height_ratio
	var jx: float = float((PlainsForestScript.cell_mix(q, r, 2000) % 19) - 9) * 0.55
	var jy: float = float((PlainsForestScript.cell_mix(q, r, 2001) % 13) - 6) * 0.45
	var cx: float = anchor_pres.x + jx
	var cy: float = anchor_pres.y - side * unit_occluder_y_ratio + jy
	var base_r: float = maxf(w, h) * 0.26
	var n_circ: int = 4 + (PlainsForestScript.cell_mix(q, r, 2002) % 2)
	var i: int = 0
	while i < n_circ:
		var h2: int = PlainsForestScript.cell_mix(q, r, 2010 + i)
		var ox: float = (float(h2 % 41) - 20.0) / 20.0 * w * 0.42
		var oy: float = (float((h2 >> 6) % 31) - 15.0) / 15.0 * h * 0.38
		var pr: Vector2 = Vector2(cx + ox, cy + oy)
		var rad: float = base_r * (0.82 + float(i) * 0.07 + float((h2 >> 14) & 7) * 0.02)
		var ca: float = (0.14 + float((h2 >> 10) & 3) * 0.04) * op
		draw_circle(pr, rad, Color(0.22, 0.42, 0.22, clampf(ca, 0.0, 1.0)))
		i += 1
	var hp: int = PlainsForestScript.cell_mix(q, r, 2030)
	var mx: float = w * 0.48 + float((hp >> 4) & 7) * 1.1
	var my: float = h * 0.42 + float((hp >> 7) & 7) * 0.9
	var skew: float = deg_to_rad(float((hp >> 10) % 32) - 16.0)
	var ck: float = cos(skew)
	var sk: float = sin(skew)
	var tri: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy) + Vector2(-mx * ck + 0.2 * my * sk, -mx * sk - 0.2 * my * ck),
		Vector2(cx, cy) + Vector2(mx * ck * 0.88 + 0.28 * my * sk, mx * sk * 0.88 - 0.28 * my * ck),
		Vector2(cx, cy) + Vector2(0.15 * mx * ck - my * sk, 0.15 * mx * sk + my * ck),
	])
	var ta: float = (0.12 + float((hp >> 13) & 3) * 0.03) * op
	draw_colored_polygon(tri, Color(0.28, 0.40, 0.20, clampf(ta, 0.0, 1.0)))

func _draw_plains_forest_front(proj, world: Vector2, q: int, r: int) -> void:
	# Phase 4.6b-polish: 1–2 chunky front bushes (layered circles / quad), not many tiny strokes.
	var op: float = forest_front_opacity
	var size: float = HexLayoutScript.SIZE
	var n_bush: int = 1 + (PlainsForestScript.cell_mix(q, r, 910) % 2)
	var k: int = 0
	while k < n_bush:
		var h: int = PlainsForestScript.cell_mix(q, r, 950 + k * 23)
		# Lower/front but slightly lifted so clumps stay in play space (not off bottom of hex).
		var ang: float = deg_to_rad(68.0 + float(h % 55))
		var rad: float = size * (0.40 + float((h >> 7) % 18) / 100.0)
		var hub: Vector2 = world + Vector2(cos(ang), sin(ang)) * rad
		var hx: Vector2 = proj.to_presentation(hub)
		var hb: int = PlainsForestScript.cell_mix(q, r, 960 + k * 19)
		var j: int = 0
		while j < 3:
			var hj: int = PlainsForestScript.cell_mix(q, r, 970 + k * 7 + j)
			var dj: float = size * (0.05 + float((hj >> 6) % 14) / 100.0)
			var ja: float = deg_to_rad(float(hj % 80) - 40.0)
			var pj: Vector2 = proj.to_presentation(hub + Vector2(cos(ang + ja), sin(ang + ja)) * dj)
			var rj: float = 12.0 + float((hj >> 10) & 7) * 1.15
			var aj: float = (0.22 + float((hj >> 13) & 3) * 0.04) * op
			draw_circle(
				pj,
				rj,
				Color(0.26, 0.44, 0.22, clampf(aj, 0.0, 1.0))
			)
			j += 1
		var hq: int = PlainsForestScript.cell_mix(q, r, 980 + k)
		var mx: float = 13.0 + float((hq >> 4) & 7) * 1.1
		var my: float = 9.0 + float((hq >> 7) & 7) * 0.95
		var rk: float = deg_to_rad(float((hq >> 10) % 36) - 18.0)
		var ck: float = cos(rk)
		var sk: float = sin(rk)
		var ovl: PackedVector2Array = PackedVector2Array([
			hx + Vector2(-mx * ck + 0.25 * my * sk, -mx * sk - 0.25 * my * ck),
			hx + Vector2(mx * ck * 0.85 + 0.35 * my * sk, mx * sk * 0.85 - 0.35 * my * ck),
			hx + Vector2(0.5 * mx * ck - my * sk, 0.5 * mx * sk + my * ck),
		])
		var qa: float = (0.16 + float((hq >> 13) & 3) * 0.03) * op
		draw_colored_polygon(ovl, Color(0.30, 0.40, 0.20, clampf(qa, 0.0, 1.0)))
		k += 1

func _draw() -> void:
	if map == null or layout == null:
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	if forest_debug_log_counts_once and not _forest_counts_logged:
		_forest_counts_logged = true
		var plains_n: int = 0
		var dec_n: int = 0
		var cl = map.coords()
		var ii: int = 0
		while ii < cl.size():
			var c = cl[ii]
			if int(map.terrain_at(c)) == HexMapScript.Terrain.PLAINS:
				plains_n += 1
				if PlainsForestScript.is_plains_forest_decorated(c.q, c.r, forest_density_ratio):
					dec_n += 1
			ii += 1
		print(
			"TerrainForegroundView forest stats: PLAINS=%d decorated=%d density=%.3f front_opacity=%.3f"
			% [plains_n, dec_n, forest_density_ratio, forest_front_opacity]
		)
	var coord_list = map.coords()
	var idx: int = 0
	while idx < coord_list.size():
		var coord = coord_list[idx]
		var terrain: int = int(map.terrain_at(coord))
		if terrain == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated(coord.q, coord.r, forest_density_ratio):
				var world: Vector2 = layout.hex_to_world(coord.q, coord.r)
				# 4.6d: Hex / terrain-owned foreground is stable — always draw for decorated PLAINS.
				_draw_plains_forest_front(camera, world, coord.q, coord.r)
				if enable_unit_occlusion_test and scenario != null:
					if scenario.cities_at(coord).size() == 0 and scenario.units_at(coord).size() > 0:
						var anchor_pres: Vector2 = camera.to_presentation(world)
						var pscale: float = camera.perspective_scale_at(world)
						var hex_h: float = HexLayoutScript.SIZE * 2.0
						var side: float = hex_h * foreground_unit_reference_height_ratio * pscale
						_draw_unit_forest_occluder(anchor_pres, side, coord.q, coord.r)
		idx += 1
