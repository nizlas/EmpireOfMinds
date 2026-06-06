# Prototype: horizontal scroll preview of tech-tree background segments (presentation only).
class_name TechTreePreviewOverlay
extends Control

const SEGMENT_PATHS: Array[String] = [
	"res://assets/prototype/tech_tree/tech_tree_bg_1.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_2.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_3.png",
]
const TECH_ITEM_PATH: String = "res://assets/prototype/tech_tree/tech_item.png"
const STONE_TOOLS_PATH: String = "res://assets/prototype/tech_tree/stone_tools.png"
const TECH_COLUMN_COUNT: int = 3
## Accepted horizontal column spacing (do not change without visual re-tune).
const COLUMN_X_START: float = 180.0
const COLUMN_X_STEP: float = 390.0
## Horizontal nudge within the parchment content area.
const TECH_ITEM_GROUP_OFFSET: Vector2 = Vector2(85.0, 18.0)
## 4-item column is the source of truth; 2/3-item layouts derive from y0..y3.
const COLUMN_LAYOUT_4: Array[float] = [148.0, 378.0, 608.0, 838.0]
const PROTOTYPE_COLUMN_SPECS: Array = [
	{"count": 4},
	{"count": 2},
	{"count": 3},
]
const TECH_ITEM_DISPLAY_HEIGHT: float = 190.0
const STONE_ICON_HEIGHT_RATIO: float = 1.0 / 3.0
const STONE_ICON_X_FRAC: float = 0.08
const STONE_ICON_Y_FRAC: float = 0.32
const TECH_TITLE_TEXT: String = "Stone Tools"
const TECH_BODY_TEXT: String = (
	"• Basic stoneworking\n"
	+ "• Worker enablement\n"
	+ "• Quarry / mine precursor\n"
	+ "• Production from hills & stone"
)
const TITLE_Y_FRAC: float = 0.107
const TITLE_W_FRAC: float = 0.62
const TITLE_H_FRAC: float = 0.13
const BODY_X_FRAC: float = 0.34
const BODY_Y_FRAC: float = 0.28
const BODY_W_FRAC: float = 0.58
const BODY_H_FRAC: float = 0.60
const TITLE_FONT_HEIGHT_RATIO: float = 0.074
const BODY_FONT_HEIGHT_RATIO: float = 0.069
const TITLE_FONT_COLOR: Color = Color(0.95, 0.9, 0.72)
const BODY_FONT_COLOR: Color = Color(0.2, 0.14, 0.08)
const WHEEL_SCROLL_STEP_PX: int = 120
const ROW_HEIGHT_VIEWPORT_FRACTION: float = 0.82
## HudCanvas siblings hidden while preview is open (Science / seat chips bleed through a dim plate).
const _HUD_HIDE_NAMES: Array[String] = ["PlayerContactStrip", "SciencePanel"]

var _scroll: ScrollContainer
var _scroll_content: Control
var _segment_row: HBoxContainer
var _tech_item_tex: Texture2D
var _stone_icon_tex: Texture2D
var _tech_items: Array[TextureRect] = []
var _tech_item_placements: Array[Vector2i] = []


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


static func scaled_texture_size(tex: Texture2D, display_height: float) -> Vector2:
	if tex == null or display_height <= 0.0:
		return Vector2.ZERO
	var th: float = float(tex.get_height())
	if th <= 0.0:
		return Vector2.ZERO
	var tw: float = float(tex.get_width())
	var w: float = tw * display_height / th
	return Vector2(w, display_height)


static func stone_icon_layout(item_size: Vector2) -> Dictionary:
	var icon_h: float = item_size.y * STONE_ICON_HEIGHT_RATIO
	return {
		"height": icon_h,
		"x": item_size.x * STONE_ICON_X_FRAC,
		"y": item_size.y * STONE_ICON_Y_FRAC,
	}


static func tech_title_label_layout(item_size: Vector2) -> Dictionary:
	return {
		"x": item_size.x * (1.0 - TITLE_W_FRAC) * 0.5,
		"y": item_size.y * TITLE_Y_FRAC,
		"width": item_size.x * TITLE_W_FRAC,
		"height": item_size.y * TITLE_H_FRAC,
		"font_size": maxi(int(round(item_size.y * TITLE_FONT_HEIGHT_RATIO)), 8),
	}


static func tech_body_label_layout(item_size: Vector2) -> Dictionary:
	return {
		"x": item_size.x * BODY_X_FRAC,
		"y": item_size.y * BODY_Y_FRAC,
		"width": item_size.x * BODY_W_FRAC,
		"height": item_size.y * BODY_H_FRAC,
		"font_size": maxi(int(round(item_size.y * BODY_FONT_HEIGHT_RATIO)), 7),
	}


static func column_layout(count: int) -> Array:
	return _get_column_layout(count)


static func _four_column_y(index: int) -> float:
	return float(COLUMN_LAYOUT_4[index])


static func _derive_column_layout_2() -> Array[float]:
	var y0: float = _four_column_y(0)
	var y1: float = _four_column_y(1)
	var y2: float = _four_column_y(2)
	var y3: float = _four_column_y(3)
	return [(y0 + y1) * 0.5, (y2 + y3) * 0.5]


static func _derive_column_layout_3() -> Array[float]:
	var y0: float = _four_column_y(0)
	var y3: float = _four_column_y(3)
	var layout_2: Array = _derive_column_layout_2()
	var two_first_y: float = float(layout_2[0])
	var two_second_y: float = float(layout_2[1])
	return [
		(y0 + two_first_y) * 0.5,
		(y0 + y3) * 0.5,
		(two_second_y + y3) * 0.5,
	]


static func _get_column_layout(count: int) -> Array:
	match count:
		2:
			return _derive_column_layout_2()
		3:
			return _derive_column_layout_3()
		4:
			return COLUMN_LAYOUT_4
	return COLUMN_LAYOUT_4


static func prototype_column_spec_count(col: int) -> int:
	return int(PROTOTYPE_COLUMN_SPECS[col]["count"])


static func tech_item_base_position(col: int, row_in_column: int) -> Vector2:
	var layout: Array = _get_column_layout(prototype_column_spec_count(col))
	return Vector2(
		COLUMN_X_START + float(col) * COLUMN_X_STEP,
		float(layout[row_in_column]),
	)


static func column_x_position(col: int) -> float:
	return COLUMN_X_START + float(col) * COLUMN_X_STEP + TECH_ITEM_GROUP_OFFSET.x


static func tech_item_position(col: int, row_in_column: int, item_count: int = -1) -> Vector2:
	var count: int = item_count if item_count >= 0 else prototype_column_spec_count(col)
	var layout: Array = _get_column_layout(count)
	return Vector2(
		COLUMN_X_START + float(col) * COLUMN_X_STEP + TECH_ITEM_GROUP_OFFSET.x,
		float(layout[row_in_column]),
	)


static func tech_item_count() -> int:
	var total: int = 0
	var i: int = 0
	while i < PROTOTYPE_COLUMN_SPECS.size():
		total += int(PROTOTYPE_COLUMN_SPECS[i]["count"])
		i += 1
	return total


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
	_scroll_content = Control.new()
	_scroll_content.name = "ScrollContent"
	_scroll_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_scroll_content)
	_segment_row = HBoxContainer.new()
	_segment_row.name = "SegmentRow"
	_segment_row.add_theme_constant_override("separation", 0)
	_segment_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_content.add_child(_segment_row)
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
	_tech_item_tex = load(TECH_ITEM_PATH) as Texture2D
	_stone_icon_tex = load(STONE_TOOLS_PATH) as Texture2D
	_build_tech_columns()
	_rebuild_segment_sizes()


func _build_tech_columns() -> void:
	_tech_items.clear()
	_tech_item_placements.clear()
	var item_index: int = 0
	var col: int = 0
	while col < TECH_COLUMN_COUNT:
		var item_count: int = prototype_column_spec_count(col)
		var row_in_column: int = 0
		while row_in_column < item_count:
			var pos: Vector2 = tech_item_position(col, row_in_column, item_count)
			var item: TextureRect = _create_tech_item_at(pos, _stone_icon_tex, item_index)
			_scroll_content.add_child(item)
			_tech_items.append(item)
			_tech_item_placements.append(Vector2i(col, row_in_column))
			item_index += 1
			row_in_column += 1
		col += 1


func _create_tech_item_at(pos: Vector2, icon_texture: Texture2D, item_index: int = -1) -> TextureRect:
	return _create_tech_item_at_with_icon(pos, icon_texture, item_index)


func _create_tech_item_at_with_icon(
	pos: Vector2,
	icon_texture: Texture2D,
	item_index: int = -1,
) -> TextureRect:
	var item := TextureRect.new()
	item.name = "TechItem_%d" % item_index if item_index >= 0 else "TechItem"
	item.stretch_mode = TextureRect.STRETCH_SCALE
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.texture = _tech_item_tex
	item.position = pos
	if icon_texture != null:
		_attach_icon(item, icon_texture)
	_attach_tech_labels(item)
	return item


func _attach_icon(item: TextureRect, icon_texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "TechIcon"
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = icon_texture
	item.add_child(icon)
	return icon


func _attach_tech_labels(item: TextureRect) -> void:
	var title := Label.new()
	title.name = "TechTitleLabel"
	title.text = TECH_TITLE_TEXT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	item.add_child(title)
	var body := Label.new()
	body.name = "TechBodyLabel"
	body.text = TECH_BODY_TEXT
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_child(body)


func _segment_display_height() -> int:
	var vh: float = get_viewport_rect().size.y
	if vh < 1.0:
		vh = 720.0
	return maxi(int(vh * ROW_HEIGHT_VIEWPORT_FRACTION), 120)


func _rebuild_segment_sizes() -> void:
	if _segment_row == null:
		return
	var display_h: int = _segment_display_height()
	var total_w: int = 0
	var i: int = 0
	while i < _segment_row.get_child_count():
		var seg := _segment_row.get_child(i) as TextureRect
		if seg != null and seg.texture != null:
			var scaled: Vector2 = scaled_texture_size(seg.texture, float(display_h))
			var scaled_w: int = int(round(scaled.x))
			seg.custom_minimum_size = Vector2(scaled_w, display_h)
			seg.size = Vector2(scaled_w, display_h)
			total_w += scaled_w
		i += 1
	if _scroll_content != null:
		_scroll_content.custom_minimum_size = Vector2(total_w, display_h)
		_scroll_content.size = Vector2(total_w, display_h)
	_layout_tech_items()


func _layout_tech_items() -> void:
	if _tech_item_tex == null:
		return
	var item_size: Vector2 = scaled_texture_size(_tech_item_tex, TECH_ITEM_DISPLAY_HEIGHT)
	var i: int = 0
	while i < _tech_items.size():
		var placement: Vector2i = _tech_item_placements[i]
		var col: int = placement.x
		var row_in_column: int = placement.y
		var item: TextureRect = _tech_items[i]
		item.custom_minimum_size = item_size
		item.size = item_size
		item.position = tech_item_position(col, row_in_column)
		var icon: TextureRect = item.get_node_or_null("TechIcon") as TextureRect
		if icon != null:
			_layout_icon_on_item(item, icon)
		_layout_labels_on_item(item)
		i += 1


func _layout_icon_on_item(item: TextureRect, icon: TextureRect) -> void:
	if icon.texture == null:
		return
	var item_size: Vector2 = item.size
	var icon_layout: Dictionary = stone_icon_layout(item_size)
	var icon_h: float = float(icon_layout["height"])
	var icon_size: Vector2 = scaled_texture_size(icon.texture, icon_h)
	icon.custom_minimum_size = icon_size
	icon.size = icon_size
	icon.position = Vector2(float(icon_layout["x"]), float(icon_layout["y"]))


func _layout_labels_on_item(item: TextureRect) -> void:
	var title: Label = item.get_node_or_null("TechTitleLabel") as Label
	if title != null:
		_layout_title_label_on_item(item, title)
	var body: Label = item.get_node_or_null("TechBodyLabel") as Label
	if body != null:
		_layout_body_label_on_item(item, body)


func _layout_title_label_on_item(item: TextureRect, title: Label) -> void:
	var layout: Dictionary = tech_title_label_layout(item.size)
	title.position = Vector2(float(layout["x"]), float(layout["y"]))
	title.size = Vector2(float(layout["width"]), float(layout["height"]))
	title.add_theme_color_override("font_color", TITLE_FONT_COLOR)
	title.add_theme_font_size_override("font_size", int(layout["font_size"]))


func _layout_body_label_on_item(item: TextureRect, body: Label) -> void:
	var layout: Dictionary = tech_body_label_layout(item.size)
	body.position = Vector2(float(layout["x"]), float(layout["y"]))
	body.size = Vector2(float(layout["width"]), float(layout["height"]))
	body.add_theme_color_override("font_color", BODY_FONT_COLOR)
	body.add_theme_font_size_override("font_size", int(layout["font_size"]))


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
