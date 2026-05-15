# Phase 5.2.3 — parchment overlay on hexes **not** explored by **current_player_id** (local hotseat).
# Continuous parchment: **world-anchored UVs** (same pattern as **MapView** terrain). Presentation-only.
class_name MapVisibilityView
extends Node2D

const MapViewScript = preload("res://presentation/map_view.gd")

const _PARCHMENT_TEX_PATH: String = (
	"res://assets/prototype/map_overlays/unexplored_parchment_overlay_prototype.png"
)
const _FALLBACK_FOG: Color = Color(0.18, 0.16, 0.12, 0.78)

var game_state = null
var layout = null
var camera = null
var _parchment_tex: Texture2D = null

@export var parchment_world_scale: float = 768.0  # default MapView.terrain_texture_world_scale * 1.5


static func compute_overlay_items(gs, a_layout) -> Array:
	if gs == null or a_layout == null or gs.turn_state == null or gs.visibility_state == null or gs.scenario == null or gs.scenario.map == null:
		return []
	var pid: int = int(gs.turn_state.current_player_id())
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


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var res = ResourceLoader.load(_PARCHMENT_TEX_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	if res != null and res is Texture2D:
		_parchment_tex = res as Texture2D
	queue_redraw()


func _draw() -> void:
	if game_state == null or layout == null or camera == null:
		return
	if game_state.scenario == null or game_state.scenario.map == null:
		return
	if game_state.turn_state == null or game_state.visibility_state == null:
		return
	var pid: int = int(game_state.turn_state.current_player_id())
	var vis = game_state.visibility_state
	var mp = game_state.scenario.map
	var coords: Array = mp.coords()
	var i: int = 0
	while i < coords.size():
		var coord = coords[i]
		if vis.is_explored(pid, coord):
			i = i + 1
			continue
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
		if _parchment_tex != null:
			draw_colored_polygon(corners_draw, Color.WHITE, uvs, _parchment_tex)
		else:
			draw_colored_polygon(corners_draw, _FALLBACK_FOG)
		i = i + 1
