# Prototype landmark: draws scarred tree stump PNG at scenario.lightning_tree_hex (presentation-only).
# Phase 5.1.8b — z-ordered above TerrainForegroundView forest pass so the marker is not fully occluded.
# See docs/RENDERING.md
class_name LightningTreeView
extends Node2D

const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const _ASSET_PATH: String = "res://assets/prototype/terrain/scarred_tree_stump.png"
## Display height as a fraction of projected pointy-top hex height (2 * HexLayout.SIZE * perspective_scale).
const STUMP_HEIGHT_HEX_FRAC: float = 0.50
## Pivot in normalized rect space: horizontal center, anchor toward lower trunk (match settler-style markers).
const STUMP_PIVOT_X: float = 0.5
const STUMP_PIVOT_Y: float = 0.86

## Bright screen magenta (#ff00ff class): high red and blue, low green. No global near-black key (would erase bark/shadow).
const _MAG_R_MIN: float = 0.82
const _MAG_B_MIN: float = 0.82
const _MAG_G_MAX: float = 0.22
const _KEY_MIN_ALPHA: float = 0.02

## If chroma leaves fewer opaque pixels than this, use an unkeyed copy of the asset (prototype fallback).
const _MIN_OPAQUE_PIXELS_AFTER_KEY: int = 80

static var _cached_keyed_texture: Texture2D
static var _warned_chroma_fallback: bool = false

## If true, draws an extra ring around the tree hex (debug only).
@export var show_lightning_tree_debug_marker: bool = false

## If true when texture load fails, draws a [member _FALLBACK_MARKER_COLOR] diamond at the hex.
@export var draw_fallback_shape_when_texture_missing: bool = true

## If set, [member scenario] is ignored and the active map cell is read from [GameState.scenario] each draw.
var game_state
var scenario
var layout
var camera

const _FALLBACK_MARKER_COLOR: Color = Color(0.55, 0.32, 0.12, 0.92)
const _DEBUG_RING_COLOR: Color = Color(0.95, 0.85, 0.15, 0.55)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func _matches_bright_magenta_screen_rgb(c: Color) -> bool:
	if c.a < _KEY_MIN_ALPHA:
		return false
	return c.r >= _MAG_R_MIN and c.b >= _MAG_B_MIN and c.g <= _MAG_G_MAX


static func count_opaque_pixels(img: Image, min_alpha: float = 0.05) -> int:
	if img == null:
		return 0
	var fmt = img.get_format()
	if fmt != Image.FORMAT_RGBA8:
		return 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var n: int = 0
	var yy: int = 0
	while yy < h:
		var xx: int = 0
		while xx < w:
			if img.get_pixel(xx, yy).a >= min_alpha:
				n += 1
			xx += 1
		yy += 1
	return n


static func apply_magenta_key_to_rgba8_image(img: Image) -> void:
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var yy: int = 0
	while yy < h:
		var xx: int = 0
		while xx < w:
			var c: Color = img.get_pixel(xx, yy)
			if _matches_bright_magenta_screen_rgb(c):
				img.set_pixel(xx, yy, Color(c.r, c.g, c.b, 0.0))
			xx += 1
		yy += 1


static func _texture_from_rgba_image(src: Image) -> Texture2D:
	var d = src.duplicate()
	if d.get_format() != Image.FORMAT_RGBA8:
		d.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(d)


## Chroma-keys conservative magenta only; caches result. Falls back to unkeyed image if key would erase the art.
static func load_keyed_stump_texture() -> Texture2D:
	if _cached_keyed_texture != null:
		return _cached_keyed_texture
	var img := Image.new()
	if img.load(_ASSET_PATH) != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var keyed: Image = img.duplicate()
	apply_magenta_key_to_rgba8_image(keyed)
	var opaque_after: int = count_opaque_pixels(keyed, 0.05)
	if opaque_after >= _MIN_OPAQUE_PIXELS_AFTER_KEY:
		_cached_keyed_texture = ImageTexture.create_from_image(keyed)
		return _cached_keyed_texture
	var opaque_raw: int = count_opaque_pixels(img, 0.05)
	if opaque_raw < _MIN_OPAQUE_PIXELS_AFTER_KEY:
		return null
	if not _warned_chroma_fallback:
		_warned_chroma_fallback = true
		push_warning(
			"LightningTreeView: stump chroma key left too few opaque pixels (%d vs %d unkeyed); using unkeyed texture (prototype)."
			% [opaque_after, opaque_raw]
		)
	_cached_keyed_texture = _texture_from_rgba_image(img)
	return _cached_keyed_texture


static func debug_clear_stump_texture_cache() -> void:
	_cached_keyed_texture = null
	_warned_chroma_fallback = false


## Test helper: deterministic presentation-space anchor (pivot point) for the stump on (q,r).
static func presentation_pivot_for_hex(a_layout, a_camera, q: int, r: int) -> Vector2:
	if a_layout == null or a_camera == null:
		return Vector2.ZERO
	var world_center: Vector2 = a_layout.hex_to_world(q, r)
	return a_camera.to_presentation(world_center)


static func stump_draw_rect_for_hex(
	a_layout,
	a_camera,
	q: int,
	r: int,
	tex: Texture2D
) -> Rect2:
	if a_layout == null or a_camera == null or tex == null:
		return Rect2()
	var world_center: Vector2 = a_layout.hex_to_world(q, r)
	var pres_center: Vector2 = a_camera.to_presentation(world_center)
	var scale: float = a_camera.perspective_scale_at(world_center)
	var hex_height: float = 2.0 * HexLayoutScript.SIZE * scale
	var draw_h: float = hex_height * STUMP_HEIGHT_HEX_FRAC
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	if th <= 0.001:
		return Rect2()
	var draw_w: float = draw_h * (tw / th)
	var x0: float = pres_center.x - draw_w * STUMP_PIVOT_X
	var y0: float = pres_center.y - draw_h * STUMP_PIVOT_Y
	return Rect2(x0, y0, draw_w, draw_h)


static func _fallback_marker_radius_px(a_layout, a_camera, q: int, r: int) -> float:
	if a_layout == null or a_camera == null:
		return 12.0
	var world_center: Vector2 = a_layout.hex_to_world(q, r)
	var scale: float = a_camera.perspective_scale_at(world_center)
	return clampf(HexLayoutScript.SIZE * scale * 0.28, 10.0, 56.0)


func _active_scenario():
	if game_state != null:
		return game_state.scenario
	return scenario


func _draw_fallback_at_hex(hc) -> void:
	var pres = presentation_pivot_for_hex(layout, camera, hc.q, hc.r)
	var rad = _fallback_marker_radius_px(layout, camera, hc.q, hc.r)
	var poly = PackedVector2Array()
	poly.append(pres + Vector2(0, -rad))
	poly.append(pres + Vector2(rad, 0))
	poly.append(pres + Vector2(0, rad))
	poly.append(pres + Vector2(-rad, 0))
	draw_colored_polygon(poly, _FALLBACK_MARKER_COLOR)


func _draw_debug_ring_at_hex(hc) -> void:
	var pres = presentation_pivot_for_hex(layout, camera, hc.q, hc.r)
	var rad = _fallback_marker_radius_px(layout, camera, hc.q, hc.r) * 1.15
	draw_arc(pres, rad, 0.0, TAU, 32, _DEBUG_RING_COLOR, 3.0, true)


func _draw() -> void:
	var scen = _active_scenario()
	if scen == null or layout == null or camera == null:
		return
	var hc = scen.lightning_tree_hex
	if hc == null:
		return
	var drew_texture: bool = false
	var tex: Texture2D = load_keyed_stump_texture()
	if tex != null:
		var rect: Rect2 = stump_draw_rect_for_hex(layout, camera, hc.q, hc.r, tex)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			draw_texture_rect(tex, rect, false)
			drew_texture = true
	if not drew_texture and draw_fallback_shape_when_texture_missing:
		_draw_fallback_at_hex(hc)
	if show_lightning_tree_debug_marker:
		_draw_debug_ring_at_hex(hc)
