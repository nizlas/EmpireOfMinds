# Phase **5.2.6** — turn-start scroll banner (presentation-only); dismissed on first user interaction.
class_name TurnStartBannerView
extends CanvasLayer

const BANNER_PATH: String = "res://assets/prototype/ui/turn_scroll_banner.png"
const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")

## Vertical offset of banner **center** above viewport center, as a fraction of viewport height (larger = higher).
const BANNER_CENTER_ABOVE_VIEWPORT_CENTER: float = 0.235
## Max drawn width as fraction of viewport width (smaller = smaller banner overall).
const BANNER_MAX_WIDTH_FRAC: float = 0.58
## **~0.115** ≈ **12%** smaller than the prior **0.13 × height** font scale.
const FONT_SCALE_VS_BANNER_HEIGHT: float = 0.105
const FONT_MIN_SIZE: int = 15

## Fractional insets from the drawn banner rect toward the inner parchment (left, top, right, bottom).
var parchment_inset: Vector4 = Vector4(0.11, 0.26, 0.11, 0.26)

var _game_state = null
var _visible_banner: bool = false
var _line: String = ""
var _banner_texture: Texture2D = null
var _painter: _BannerPainter = null


class _BannerPainter extends Control:
	var host

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if host != null:
			host._draw_banner_rect(self)


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_painter = _BannerPainter.new()
	_painter.host = self
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painter)


func set_game_state(gs) -> void:
	_game_state = gs


func is_visible_banner() -> bool:
	return _visible_banner


func dismiss() -> void:
	if not _visible_banner:
		return
	_visible_banner = false
	_line = ""
	if _painter != null:
		_painter.queue_redraw()


func show_for_current_player(gs) -> void:
	_game_state = gs
	if gs == null or gs.turn_state == null:
		return
	_ensure_texture()
	var pname: String = PlaytestPlayerDisplayScript.display_name_for_player_id(int(gs.turn_state.current_player_id()))
	_line = "Your turn, %s" % pname
	_visible_banner = true
	if _painter != null:
		_painter.queue_redraw()


## Called from **[Main](../main.gd)** **`_input`** (and similar) so dismissal runs before gameplay handlers; does **not** mark the event handled.
func on_user_interaction(event: InputEvent) -> void:
	if not _visible_banner:
		return
	if _should_dismiss_for_event(event):
		dismiss()


static func should_dismiss_for_event_static(event: InputEvent) -> bool:
	if event == null:
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return st.pressed
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		return (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
			or (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 \
			or (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
	return false


func _should_dismiss_for_event(event: InputEvent) -> bool:
	return should_dismiss_for_event_static(event)


func _ensure_texture() -> void:
	if _banner_texture != null:
		return
	var t = load(BANNER_PATH)
	if t is Texture2D:
		_banner_texture = t as Texture2D


func _draw_banner_rect(ciControl: Control) -> void:
	if not _visible_banner or _banner_texture == null:
		return
	var vp_size: Vector2 = ciControl.get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1152, 648)
	var tw: float = float(_banner_texture.get_width())
	var th: float = float(_banner_texture.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var max_w: float = vp_size.x * BANNER_MAX_WIDTH_FRAC
	var sc: float = minf(max_w / tw, 1.0)
	var w: float = tw * sc
	var h: float = th * sc
	var center := Vector2(
		vp_size.x * 0.5,
		vp_size.y * 0.5 - vp_size.y * BANNER_CENTER_ABOVE_VIEWPORT_CENTER
	)
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	ciControl.draw_texture_rect(_banner_texture, rect, false)
	var inner := Rect2(
		rect.position.x + rect.size.x * parchment_inset.x,
		rect.position.y + rect.size.y * parchment_inset.y,
		rect.size.x * (1.0 - parchment_inset.x - parchment_inset.z),
		rect.size.y * (1.0 - parchment_inset.y - parchment_inset.w)
	)
	var font: Font = ThemeDB.fallback_font
	var fs: int = maxi(FONT_MIN_SIZE, int(rect.size.y * FONT_SCALE_VS_BANNER_HEIGHT))
	var sz: Vector2 = font.get_string_size(_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var ascent: float = font.get_ascent(fs)
	var descent: float = font.get_descent(fs)
	## **`draw_string`** uses **baseline** Y; center the line’s **ascent/descent** span inside **inner**.
	var inner_mid_y: float = inner.position.y + inner.size.y * 0.5
	var baseline_y: float = inner_mid_y + (ascent - descent) * 0.5
	var text_pos := Vector2(inner.position.x + (inner.size.x - sz.x) * 0.5, baseline_y)
	ciControl.draw_string(font, text_pos, _line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.12, 0.09, 0.06))


## Headless: current banner line (empty when hidden).
func debug_banner_line() -> String:
	return _line
