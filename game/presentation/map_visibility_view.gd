# Phase 5.2.3 — parchment overlay on hexes **not** explored by **current_player_id** (local hotseat).
# Phase 5.2.4m — soft boundary feather on explored side of unexplored/explored edges (presentation-only).
# Continuous parchment: **world-anchored UVs** (same pattern as **MapView** terrain). Presentation-only.
class_name MapVisibilityView
extends Node2D

const MapViewScript = preload("res://presentation/map_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const PolygonDrawGuardScript = preload("res://presentation/polygon_draw_guard.gd")

const _PARCHMENT_TEX_PATH: String = (
	"res://assets/prototype/map_overlays/unexplored_parchment_overlay_prototype.png"
)
const _FALLBACK_FOG: Color = Color(0.18, 0.16, 0.12, 0.78)

var game_state = null
var layout = null
var camera = null
var _parchment_tex: Texture2D = null

@export var parchment_world_scale: float = 768.0  # default MapView.terrain_texture_world_scale * 1.5

## Phase **5.2.4m** — soft feather into explored tiles at unexplored/explored boundaries.
@export var unexplored_edge_feather_enabled: bool = true
@export var unexplored_edge_feather_width_px: float = 20.0
@export var unexplored_edge_feather_steps: int = 6
@export var unexplored_edge_feather_alpha_scale: float = 0.75
@export var unexplored_edge_feather_inner_overlap_px: float = 4.0
@export var unexplored_edge_feather_noise_px: float = 2.0
@export var unexplored_edge_feather_irregularity_enabled: bool = false

static var _invalid_parchment_poly_logged: Dictionary = {}


static func compute_overlay_items(gs, a_layout) -> Array:
	if (
		gs == null
		or a_layout == null
		or gs.turn_state == null
		or gs.visibility_state == null
		or gs.scenario == null
		or gs.scenario.map == null
	):
		return []
	var pid: int = PresentationVisibilityScript.effective_viewing_player_id(gs)
	var vis = gs.visibility_state
	var mp = gs.scenario.map
	var out: Array = []
	var coords: Array = mp.coords()
	var i: int = 0
	while i < coords.size():
		var c = coords[i]
		if not vis.is_explored(pid, c):
			out.append(c)
		i = i + 1
	return out


static func _edge_sort_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["uq"]) != int(b["uq"]):
		return int(a["uq"]) < int(b["uq"])
	if int(a["ur"]) != int(b["ur"]):
		return int(a["ur"]) < int(b["ur"])
	return int(a["direction_index"]) < int(b["direction_index"])


static func _shared_edge_world(uq: int, ur: int, eq: int, er: int, a_layout) -> Dictionary:
	var c_u: Vector2 = a_layout.hex_to_world(uq, ur)
	var c_e: Vector2 = a_layout.hex_to_world(eq, er)
	var mid: Vector2 = (c_u + c_e) * 0.5
	var n_raw: Vector2 = c_e - c_u
	if n_raw.length_squared() < 0.0001:
		return {}
	var outward: Vector2 = n_raw.normalized()
	var edge_along: Vector2 = Vector2(-outward.y, outward.x)
	var half_edge: float = HexLayoutScript.SIZE * 0.5
	return {
		"edge_p0": mid - edge_along * half_edge,
		"edge_p1": mid + edge_along * half_edge,
		"mid": mid,
		"outward": outward,
	}


## Pure: unexplored **U** with on-map explored neighbor **E** for the viewing player only.
static func compute_unexplored_boundary_edges_for_current_player(gs, a_layout) -> Array:
	if (
		gs == null
		or a_layout == null
		or gs.turn_state == null
		or gs.visibility_state == null
		or gs.scenario == null
		or gs.scenario.map == null
	):
		return []
	var pid: int = PresentationVisibilityScript.effective_viewing_player_id(gs)
	var vis = gs.visibility_state
	var mp = gs.scenario.map
	var out: Array = []
	var coords: Array = mp.coords()
	var ci: int = 0
	while ci < coords.size():
		var u = coords[ci]
		ci += 1
		if vis.is_explored(pid, u):
			continue
		var di: int = 0
		while di < 6:
			var e = u.neighbor(di)
			di += 1
			if not mp.has(e):
				continue
			if not vis.is_explored(pid, e):
				continue
			var geom = _shared_edge_world(int(u.q), int(u.r), int(e.q), int(e.r), a_layout)
			if geom.is_empty():
				continue
			var ent: Dictionary = {
				"uq": int(u.q),
				"ur": int(u.r),
				"eq": int(e.q),
				"er": int(e.r),
				"direction_index": di - 1,
			}
			ent.merge(geom)
			out.append(ent)
	out.sort_custom(_edge_sort_less)
	return out


static func _feather_hash(uq: int, ur: int, direction_index: int, step: int) -> int:
	var h: int = (
		(int(uq) * 92837111)
		^ (int(ur) * 689287499)
		^ (int(direction_index) * 283923481)
		^ (int(step) * 982451653)
	)
	return h & 0x7FFFFFFF


static func _irregularity_offset_px(uq: int, ur: int, direction_index: int, step: int, noise_px: float) -> float:
	var h: int = _feather_hash(uq, ur, direction_index, step)
	var t: float = float(h % 100001) / 100000.0
	return (t * 2.0 - 1.0) * noise_px


## Normalized **t** in **[0, 1]** from inner bound (**-overlap**) to outer bound (**+width**).
static func feather_span_t_at_outward_distance(
	d_outward: float,
	inner_overlap_world: float,
	width_world: float,
) -> float:
	var span: float = inner_overlap_world + width_world
	if span <= 0.0001:
		return 0.0
	return clampf((d_outward + inner_overlap_world) / span, 0.0, 1.0)


## Alpha along the feather span: full **peak** at/inside the unexplored side, smooth ease-out to **0** at **+width**.
static func feather_alpha_at_outward_distance(
	d_outward: float,
	width_world: float,
	peak_alpha: float,
	alpha_scale: float = 1.0,
) -> float:
	if peak_alpha <= 0.0:
		return 0.0
	if d_outward <= 0.0:
		return peak_alpha
	if width_world <= 0.0001:
		return 0.0
	var t: float = clampf(d_outward / width_world, 0.0, 1.0)
	var u: float = t * t * (3.0 - 2.0 * t)
	var fade: float = 1.0 - u
	return peak_alpha * lerpf(1.0, alpha_scale, t) * fade


## World-space strip distances for **step_index**; span is **[-inner_overlap, +width]** (presentation px → world).
static func feather_strip_distance_range_world(
	inner_overlap_px: float,
	width_px: float,
	perspective_scale: float,
	step_index: int,
	step_count: int,
) -> Dictionary:
	var pscale: float = maxf(perspective_scale, 0.0001)
	var inner_w: float = inner_overlap_px / pscale
	var outer_w: float = width_px / pscale
	var span: float = inner_w + outer_w
	var steps: int = maxi(step_count, 1)
	var idx: int = clampi(step_index, 0, steps - 1)
	var inner_d: float = -inner_w + (float(idx) / float(steps)) * span
	var outer_d: float = -inner_w + (float(idx + 1) / float(steps)) * span
	return {
		"inner_d": inner_d,
		"outer_d": outer_d,
		"d_min": -inner_w,
		"d_max": outer_w,
		"inner_overlap_world": inner_w,
		"width_world": outer_w,
	}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var res = ResourceLoader.load(_PARCHMENT_TEX_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	if res != null and res is Texture2D:
		_parchment_tex = res as Texture2D
	queue_redraw()


func _draw_parchment_hex(coord) -> void:
	var world_center: Vector2 = layout.hex_to_world(coord.q, coord.r)
	var corners_world: PackedVector2Array = layout.hex_corners(world_center)
	var corners_draw: PackedVector2Array = PackedVector2Array()
	corners_draw.resize(6)
	var ci: int = 0
	while ci < 6:
		corners_draw[ci] = camera.to_presentation(corners_world[ci])
		ci = ci + 1
	var uvs: PackedVector2Array = MapViewScript._world_anchored_corner_uvs(
		corners_world,
		parchment_world_scale,
	)
	var sanitized: Dictionary = PolygonDrawGuardScript.sanitize_polygon_with_uvs(corners_draw, uvs)
	var draw_pts: PackedVector2Array = sanitized["pts"] as PackedVector2Array
	var draw_uvs: PackedVector2Array = sanitized["uvs"] as PackedVector2Array
	var skip_reason: String = PolygonDrawGuardScript.polygon_skip_reason(draw_pts)
	if skip_reason != "":
		_log_invalid_parchment_polygon_throttled(coord, corners_draw, draw_pts, skip_reason)
		return
	if _parchment_tex != null:
		draw_colored_polygon(draw_pts, Color.WHITE, draw_uvs, _parchment_tex)
	else:
		draw_colored_polygon(draw_pts, _FALLBACK_FOG)


func _log_invalid_parchment_polygon_throttled(
	coord,
	raw_pts: PackedVector2Array,
	sanitized_pts: PackedVector2Array,
	reason: String,
) -> void:
	var key: String = "%d,%d:%s" % [int(coord.q), int(coord.r), reason]
	if _invalid_parchment_poly_logged.has(key):
		return
	_invalid_parchment_poly_logged[key] = true
	var zoom: float = -1.0
	var pan: Vector2 = Vector2.ZERO
	if camera != null:
		zoom = camera.zoom
		pan = camera.camera_world_offset
	push_warning(
		(
			"[MapVisibility] skip_parchment_hex hex=(%d,%d) reason=%s "
			+ "point_count=%d unique_count=%d area_sq=%.3f zoom=%.3f pan=%s"
		)
		% [
			int(coord.q),
			int(coord.r),
			reason,
			raw_pts.size(),
			PolygonDrawGuardScript.count_unique_polygon_points(sanitized_pts),
			PolygonDrawGuardScript.polygon_area_abs_sq(sanitized_pts),
			zoom,
			str(pan),
		]
	)


func _draw_feather_strip_quad(
	world_corners: PackedVector2Array,
	alpha_inner: float,
	alpha_outer: float,
	uq: int,
	ur: int,
	direction_index: int,
	step: int,
) -> void:
	var draw_pts: PackedVector2Array = PackedVector2Array()
	draw_pts.resize(4)
	var perp: Vector2 = Vector2(
		world_corners[1].y - world_corners[0].y,
		world_corners[0].x - world_corners[1].x,
	)
	if perp.length_squared() > 0.0001:
		perp = perp.normalized()
	else:
		perp = Vector2.ZERO
	var irr: float = 0.0
	if unexplored_edge_feather_irregularity_enabled and unexplored_edge_feather_noise_px > 0.0:
		irr = _irregularity_offset_px(uq, ur, direction_index, step, unexplored_edge_feather_noise_px)
	var wi: int = 0
	while wi < 4:
		var wpt: Vector2 = world_corners[wi]
		if perp != Vector2.ZERO:
			wpt = wpt + perp * irr
		draw_pts[wi] = camera.to_presentation(wpt)
		wi += 1
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(4)
	var corner_alphas: Array = [alpha_inner, alpha_inner, alpha_outer, alpha_outer]
	var ci: int = 0
	while ci < 4:
		var a: float = float(corner_alphas[ci])
		if _parchment_tex != null:
			colors[ci] = Color(1.0, 1.0, 1.0, a)
		else:
			var c: Color = _FALLBACK_FOG
			c.a = a
			colors[ci] = c
		ci += 1
	if _parchment_tex != null:
		var uvs: PackedVector2Array = MapViewScript._world_anchored_corner_uvs(
			world_corners,
			parchment_world_scale,
		)
		draw_polygon(draw_pts, colors, uvs, _parchment_tex)
	else:
		draw_polygon(draw_pts, colors)


func _draw_boundary_feather() -> void:
	if not unexplored_edge_feather_enabled:
		return
	var steps: int = maxi(unexplored_edge_feather_steps, 1)
	var peak_alpha: float = 1.0 if _parchment_tex != null else _FALLBACK_FOG.a
	var edges: Array = compute_unexplored_boundary_edges_for_current_player(game_state, layout)
	var ei: int = 0
	while ei < edges.size():
		var ent = edges[ei]
		ei += 1
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ent as Dictionary
		var uq: int = int(d["uq"])
		var ur: int = int(d["ur"])
		var dir_i: int = int(d["direction_index"])
		var p0w: Vector2 = d["edge_p0"]
		var p1w: Vector2 = d["edge_p1"]
		var outward: Vector2 = d["outward"]
		var mid: Vector2 = d["mid"]
		var pscale: float = camera.perspective_scale_at(mid)
		var range0: Dictionary = feather_strip_distance_range_world(
			unexplored_edge_feather_inner_overlap_px,
			unexplored_edge_feather_width_px,
			pscale,
			0,
			steps,
		)
		var width_world: float = float(range0["width_world"])
		var si: int = 0
		while si < steps:
			var span: Dictionary = feather_strip_distance_range_world(
				unexplored_edge_feather_inner_overlap_px,
				unexplored_edge_feather_width_px,
				pscale,
				si,
				steps,
			)
			var inner_d: float = float(span["inner_d"])
			var outer_d: float = float(span["outer_d"])
			var alpha_inner: float = feather_alpha_at_outward_distance(
				inner_d,
				width_world,
				peak_alpha,
				unexplored_edge_feather_alpha_scale,
			)
			var alpha_outer: float = feather_alpha_at_outward_distance(
				outer_d,
				width_world,
				peak_alpha,
				unexplored_edge_feather_alpha_scale,
			)
			var w0_in: Vector2 = p0w + outward * inner_d
			var w1_in: Vector2 = p1w + outward * inner_d
			var w0_out: Vector2 = p0w + outward * outer_d
			var w1_out: Vector2 = p1w + outward * outer_d
			var wc: PackedVector2Array = PackedVector2Array([w0_in, w1_in, w1_out, w0_out])
			_draw_feather_strip_quad(wc, alpha_inner, alpha_outer, uq, ur, dir_i, si)
			si += 1


func _draw() -> void:
	if game_state == null or layout == null or camera == null:
		return
	if game_state.scenario == null or game_state.scenario.map == null:
		return
	if game_state.turn_state == null or game_state.visibility_state == null:
		return
	var pid: int = PresentationVisibilityScript.effective_viewing_player_id(game_state)
	var vis = game_state.visibility_state
	var mp = game_state.scenario.map

	# Feather first (includes inner overlap into unexplored); solid fill covers the overlap.
	_draw_boundary_feather()

	var i: int = 0
	var coords: Array = mp.coords()
	while i < coords.size():
		var coord = coords[i]
		if vis.is_explored(pid, coord):
			i = i + 1
			continue
		_draw_parchment_hex(coord)
		i = i + 1
