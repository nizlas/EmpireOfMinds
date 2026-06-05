# Prototype: horizontal scroll preview of tech-tree background segments (presentation only).
class_name TechTreePreviewOverlay
extends Control

const SEGMENT_PATHS: Array[String] = [
	"res://assets/prototype/tech_tree/tech_tree_bg_1.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_2.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_3.png",
]
const WHEEL_SCROLL_STEP_PX: int = 120
const ROW_HEIGHT_VIEWPORT_FRACTION: float = 0.82
## HudCanvas siblings hidden while preview is open (Science / seat chips bleed through a dim plate).
const _HUD_HIDE_NAMES: Array[String] = ["PlayerContactStrip", "SciencePanel"]

var _scroll: ScrollContainer
var _segment_row: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func open_overlay() -> void:
	_set_distraction_hud_visible(false)
	_rebuild_segment_sizes()
	visible = true
	if _scroll != null:
		_scroll.scroll_horizontal = 0


func close_overlay() -> void:
	visible = false
	_restore_distraction_hud()


func _set_distraction_hud_visible(on: bool) -> void:
	var hud: Node = get_parent()
	if hud == null:
		return
	var i: int = 0
	while i < _HUD_HIDE_NAMES.size():
		var n: CanvasItem = hud.get_node_or_null(_HUD_HIDE_NAMES[i]) as CanvasItem
		if n != null:
			n.visible = on
		i += 1


func _restore_distraction_hud() -> void:
	var hud: Node = get_parent()
	if hud == null:
		return
	var strip = hud.get_node_or_null("PlayerContactStrip")
	if strip != null:
		if strip.has_method("refresh"):
			strip.refresh()
		else:
			strip.visible = true
	var sci = hud.get_node_or_null("SciencePanel")
	if sci != null:
		if sci.has_method("refresh"):
			sci.refresh()
		else:
			sci.visible = true


static func horizontal_wheel_delta(button_index: int) -> int:
	if button_index == MOUSE_BUTTON_WHEEL_UP:
		return -WHEEL_SCROLL_STEP_PX
	if button_index == MOUSE_BUTTON_WHEEL_DOWN:
		return WHEEL_SCROLL_STEP_PX
	return 0


func apply_horizontal_wheel(button_index: int) -> void:
	var delta: int = horizontal_wheel_delta(button_index)
	if delta == 0:
		return
	_apply_horizontal_wheel_delta(delta)


func segment_row_separation() -> int:
	if _segment_row == null:
		return -1
	return int(_segment_row.get_theme_constant("separation", "HBoxContainer"))


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var body := Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.gui_input.connect(_on_scroll_gui_input)
	body.add_child(_scroll)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close_overlay)
	body.add_child(close_btn)
	close_btn.set_anchor(SIDE_LEFT, 1.0)
	close_btn.set_anchor(SIDE_TOP, 0.0)
	close_btn.set_anchor(SIDE_RIGHT, 1.0)
	close_btn.set_anchor(SIDE_BOTTOM, 0.0)
	close_btn.offset_left = -96.0
	close_btn.offset_top = 0.0
	close_btn.offset_right = 0.0
	close_btn.offset_bottom = 36.0
	close_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_segment_row = HBoxContainer.new()
	_segment_row.add_theme_constant_override("separation", 0)
	_segment_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_segment_row)
	var i: int = 0
	while i < SEGMENT_PATHS.size():
		var seg := TextureRect.new()
		seg.name = "Segment%d" % (i + 1)
		seg.stretch_mode = TextureRect.STRETCH_SCALE
		seg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.texture = load(SEGMENT_PATHS[i]) as Texture2D
		_segment_row.add_child(seg)
		i += 1
	_rebuild_segment_sizes()


func _segment_display_height() -> int:
	var vh: float = get_viewport_rect().size.y
	if vh < 1.0:
		vh = 720.0
	return maxi(int(vh * ROW_HEIGHT_VIEWPORT_FRACTION), 120)


func _rebuild_segment_sizes() -> void:
	if _segment_row == null:
		return
	var display_h: int = _segment_display_height()
	var i: int = 0
	while i < _segment_row.get_child_count():
		var seg := _segment_row.get_child(i) as TextureRect
		if seg != null and seg.texture != null:
			var tex: Texture2D = seg.texture
			var tw: float = float(tex.get_width())
			var th: float = float(tex.get_height())
			var scaled_w: int = display_h
			if th > 0.0:
				scaled_w = int(round(tw * float(display_h) / th))
			seg.custom_minimum_size = Vector2(scaled_w, display_h)
			seg.size = Vector2(scaled_w, display_h)
		i += 1


func _wheel_hover_rect() -> Rect2:
	if _scroll == null:
		return Rect2()
	return _scroll.get_global_rect()


func _max_horizontal_scroll() -> int:
	if _scroll == null:
		return 0
	var bar: ScrollBar = _scroll.get_h_scroll_bar()
	if bar == null:
		return 0
	return maxi(0, int(bar.max_value))


func _apply_horizontal_wheel_delta(delta: int) -> void:
	if _scroll == null or delta == 0:
		return
	_scroll.scroll_horizontal = clampi(
		_scroll.scroll_horizontal + delta,
		0,
		_max_horizontal_scroll(),
	)


func _try_handle_wheel_event(event: InputEvent) -> bool:
	if _scroll == null or not visible:
		return false
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return false
	var delta: int = horizontal_wheel_delta(mb.button_index)
	if delta == 0:
		return false
	if not _wheel_hover_rect().has_point(mb.global_position):
		return false
	_apply_horizontal_wheel_delta(delta)
	return true


func _on_scroll_gui_input(event: InputEvent) -> void:
	if _try_handle_wheel_event(event):
		if _scroll != null:
			_scroll.accept_event()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _try_handle_wheel_event(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_ESCAPE:
			close_overlay()
			get_viewport().set_input_as_handled()
