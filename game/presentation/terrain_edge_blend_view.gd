# **Phase 5.1.17k** — Presentation-only **PLAINS ↔ GRASSLAND** edge softening (**no** water, **no** woods, **no** forest-hosting layer coupling).
# Reads **`HexMap`** / **`HexLayout`** / **`MapCamera`** only. See **[RENDERING.md](../../docs/RENDERING.md)**.
class_name TerrainEdgeBlendView
extends Node2D

const HexMapScript = preload("res://domain/hex_map.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

## **Rollback (v0):** semi-transparent **PLAINS↔GRASSLAND** ribbons (`draw_colored_polygon`) caused **hex-aligned banding** on painterly terrain — **off** until a seam-free approach ships. **`compute_blend_items`** remains for tests / future use.
@export var draw_edge_blend: bool = false
## Half-width of the blend straddle (each side of the shared edge), as a fraction of **`HexLayout.SIZE`** (scaled by **`perspective_scale_at`** in **`_draw`**).
@export_range(0.02, 0.35) var band_width_ratio: float = 0.12
## Alpha for the blended fill (lerp of terrain fallbacks).
@export_range(0.05, 0.6) var blend_alpha: float = 0.22
## When **true**, **`band_width_ratio`** is scaled by a deterministic factor per edge (still stable pan/zoom).
@export var enable_band_jitter: bool = false


var map = null
var layout = null
var camera = null


static func _cell_lex_less(a, b) -> bool:
	if a == null or b == null:
		return false
	if int(a.q) != int(b.q):
		return int(a.q) < int(b.q)
	return int(a.r) < int(b.r)


## Local prototype palette (aligned with **`MapView._terrain_to_color`** fallbacks). Presentation-only.
static func _terrain_fallback_rgb(terrain: int) -> Color:
	if terrain == HexMapScript.Terrain.PLAINS:
		return Color(0.74, 0.67, 0.52)
	if terrain == HexMapScript.Terrain.WATER:
		return Color(0.28, 0.46, 0.62)
	if terrain == HexMapScript.Terrain.GRASSLAND:
		return Color(0.55, 0.70, 0.42)
	return Color(1.0, 0.0, 1.0)


static func _is_plains_grassland_pair(t0: int, t1: int) -> bool:
	return (
		(t0 == HexMapScript.Terrain.PLAINS and t1 == HexMapScript.Terrain.GRASSLAND)
		or (t0 == HexMapScript.Terrain.GRASSLAND and t1 == HexMapScript.Terrain.PLAINS)
	)


static func _edge_jitter_mul(aq: int, ar: int, bq: int, br: int) -> float:
	var h: int = (int(aq) * 92837111) ^ (int(ar) * 689287499) ^ (int(bq) * 283923481) ^ (int(br) * 982451653)
	h = (h & 0x7fffffff) % 100001
	return 0.92 + (float(h) / 100000.0) * 0.16


## **Pure:** canonical **PLAINS–GRASSLAND** edges only; **deterministic** sort (**aq, ar, bq, br**).
static func compute_blend_items(p_map) -> Array:
	var out: Array = []
	if p_map == null:
		return out
	var raw: Array = p_map.coords()
	var cells: Array = []
	var wi: int = 0
	while wi < raw.size():
		var hc = raw[wi]
		wi += 1
		if hc != null:
			cells.append(hc)
	cells.sort_custom(func(a, b): return _cell_lex_less(a, b))
	var ci: int = 0
	while ci < cells.size():
		var cell = cells[ci]
		ci += 1
		var di: int = 0
		while di < 6:
			var nbr = cell.neighbor(di)
			di += 1
			if not p_map.has(nbr):
				continue
			if not _cell_lex_less(cell, nbr):
				continue
			var ta: int = int(p_map.terrain_at(cell))
			var tb: int = int(p_map.terrain_at(nbr))
			if not _is_plains_grassland_pair(ta, tb):
				continue
			out.append(
				{
					"aq": int(cell.q),
					"ar": int(cell.r),
					"bq": int(nbr.q),
					"br": int(nbr.r),
					"terrain_a": ta,
					"terrain_b": tb,
				}
			)
	out.sort_custom(
		func(x: Dictionary, y: Dictionary) -> bool:
			if int(x["aq"]) != int(y["aq"]):
				return int(x["aq"]) < int(y["aq"])
			if int(x["ar"]) != int(y["ar"]):
				return int(x["ar"]) < int(y["ar"])
			if int(x["bq"]) != int(y["bq"]):
				return int(x["bq"]) < int(y["bq"])
			return int(x["br"]) < int(y["br"])
	)
	return out


func _draw() -> void:
	if not draw_edge_blend:
		return
	if map == null or layout == null or camera == null:
		return
	var items: Array = compute_blend_items(map)
	var ii: int = 0
	while ii < items.size():
		var ent = items[ii]
		ii += 1
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ent as Dictionary
		var aq: int = int(d["aq"])
		var ar: int = int(d["ar"])
		var bq: int = int(d["bq"])
		var br: int = int(d["br"])
		var ta: int = int(d["terrain_a"])
		var tb: int = int(d["terrain_b"])
		var c0: Vector2 = layout.hex_to_world(aq, ar)
		var c1: Vector2 = layout.hex_to_world(bq, br)
		var mid: Vector2 = (c0 + c1) * 0.5
		var n_raw: Vector2 = c1 - c0
		if n_raw.length_squared() < 0.0001:
			continue
		var n_unit: Vector2 = n_raw.normalized()
		var edge_along: Vector2 = Vector2(-n_unit.y, n_unit.x)
		var half_edge: float = HexLayoutScript.SIZE * 0.5
		var p0w: Vector2 = mid - edge_along * half_edge
		var p1w: Vector2 = mid + edge_along * half_edge
		var pscale: float = camera.perspective_scale_at(mid)
		var band_mul: float = 1.0
		if enable_band_jitter:
			band_mul = _edge_jitter_mul(aq, ar, bq, br)
		var band: float = float(band_width_ratio) * HexLayoutScript.SIZE * pscale * band_mul
		var q0: Vector2 = camera.to_presentation(p0w + n_unit * band)
		var q1: Vector2 = camera.to_presentation(p1w + n_unit * band)
		var q2: Vector2 = camera.to_presentation(p1w - n_unit * band)
		var q3: Vector2 = camera.to_presentation(p0w - n_unit * band)
		var poly: PackedVector2Array = PackedVector2Array([q0, q1, q2, q3])
		var col_a: Color = _terrain_fallback_rgb(ta)
		var col_b: Color = _terrain_fallback_rgb(tb)
		var mix: Color = col_a.lerp(col_b, 0.5)
		mix.a = float(blend_alpha)
		draw_colored_polygon(poly, mix)
