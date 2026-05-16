# Local Combat 0.1b — temporary comic **CLASH** burst at melee midpoint (presentation-only).
# Triggered after accepted **attack_unit** from **SelectionController**; no gameplay/domain effect.
class_name CombatClashBurstView
extends Node2D

const TEXTURE_PATH: String = "res://assets/prototype/ui/combat_clash_burst.png"
const DURATION_SEC: float = 1.0
const FADE_START_SEC: float = 0.75
## Width vs hex-hex separation in presentation space (covers both unit sprites).
const _COVER_WIDTH_VS_SEP: float = 3.4
const _MIN_WIDTH_PX: float = 240.0

var layout
var camera

var _tex: Texture2D
var _active: bool = false
var _elapsed: float = 0.0
var _alpha: float = 1.0
var _mid_world: Vector2 = Vector2.ZERO
var _corner_a_world: Vector2 = Vector2.ZERO
var _corner_b_world: Vector2 = Vector2.ZERO


static func texture_chroma_flat_magenta(src: Texture2D) -> Texture2D:
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return src
	var dupe: Image = img.duplicate()
	var w: int = dupe.get_width()
	var h: int = dupe.get_height()
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			var c: Color = dupe.get_pixel(x, y)
			if c.a < 0.02:
				x = x + 1
				continue
			if c.r > 0.82 and c.g < 0.22 and c.b > 0.82:
				dupe.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			x = x + 1
		y = y + 1
	return ImageTexture.create_from_image(dupe)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var raw: Texture2D = load(TEXTURE_PATH) as Texture2D
	if raw == null:
		var img := Image.new()
		if img.load(TEXTURE_PATH) == OK:
			raw = ImageTexture.create_from_image(img)
	if raw != null:
		_tex = texture_chroma_flat_magenta(raw)
	set_process(false)
	queue_redraw()


## Axial hex centers from combat tiles (pre- or post-apply; positions are unchanged on the map).
func show_burst_hex_centers(attacker_q: int, attacker_r: int, defender_q: int, defender_r: int) -> void:
	if layout == null or camera == null or _tex == null:
		return
	var wa: Vector2 = layout.hex_to_world(attacker_q, attacker_r)
	var wb: Vector2 = layout.hex_to_world(defender_q, defender_r)
	_mid_world = (wa + wb) * 0.5
	_corner_a_world = wa
	_corner_b_world = wb
	_elapsed = 0.0
	_alpha = 1.0
	_active = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed = _elapsed + delta
	if _elapsed >= DURATION_SEC:
		_active = false
		set_process(false)
		queue_redraw()
		return
	_alpha = 1.0
	if _elapsed > FADE_START_SEC:
		var fade_len: float = DURATION_SEC - FADE_START_SEC
		if fade_len > 0.0001:
			_alpha = 1.0 - ((_elapsed - FADE_START_SEC) / fade_len)
		else:
			_alpha = 0.0
	_alpha = clampf(_alpha, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if not _active or _tex == null or layout == null or camera == null:
		return
	var pres_mid: Vector2 = camera.to_presentation(_mid_world)
	var pa: Vector2 = camera.to_presentation(_corner_a_world)
	var pb: Vector2 = camera.to_presentation(_corner_b_world)
	var sep: float = pa.distance_to(pb)
	var pscale: float = camera.perspective_scale_at(_mid_world)
	var base_w: float = maxf(sep * _COVER_WIDTH_VS_SEP, _MIN_WIDTH_PX * camera.zoom * pscale)
	var tsz: Vector2 = _tex.get_size()
	if tsz.y < 0.001:
		return
	var base_h: float = base_w * tsz.y / tsz.x
	var rect := Rect2(pres_mid - Vector2(base_w * 0.5, base_h * 0.5), Vector2(base_w, base_h))
	var col := Color(1.0, 1.0, 1.0, _alpha)
	draw_texture_rect(_tex, rect, false, col)
