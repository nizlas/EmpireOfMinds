# Prototype: horizontal scroll preview of tech-tree background segments (presentation only).
class_name TechTreePreviewOverlay
extends Control

const SEGMENT_PATHS: Array[String] = [
	"res://assets/prototype/tech_tree/tech_tree_bg_1.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_2.png",
	"res://assets/prototype/tech_tree/tech_tree_bg_3.png",
]
const GridLayoutScript = preload("res://presentation/tech_tree_grid_layout.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")
const NodeLayoutScript = preload("res://presentation/tech_tree_node_layout.gd")
const DependencyLinesScript = preload("res://presentation/tech_tree_dependency_lines.gd")
const BuildingRewardsScript = preload("res://presentation/tech_tree_building_rewards.gd")
const TECH_ITEM_PATH: String = "res://assets/prototype/tech_tree/tech_item.png"
const STONE_TOOLS_PATH: String = "res://assets/prototype/tech_tree/stone_tools.png"
const TECH_COLUMN_COUNT: int = GridLayoutScript.COLUMN_COUNT
const COLUMN_X_START: float = GridLayoutScript.COLUMN_X_START
const COLUMN_X_STEP: float = GridLayoutScript.COLUMN_X_STEP
const TECH_ITEM_GROUP_OFFSET: Vector2 = GridLayoutScript.TECH_ITEM_GROUP_OFFSET
const COLUMN_LAYOUT_4: Array[float] = GridLayoutScript.COLUMN_LAYOUT_4
## Segment 0 column counts kept for layout regression helpers / tests.
const PROTOTYPE_COLUMN_SPECS: Array = [
	{"count": 4},
	{"count": 2},
	{"count": 3},
]
const PROTOTYPE_SEGMENT_SPECS: Array = GridLayoutScript.SEGMENT_SPECS
const TECH_ITEM_DISPLAY_HEIGHT: float = GridLayoutScript.TECH_ITEM_DISPLAY_HEIGHT
const TECH_ITEM_WIDTH_PER_HEIGHT: float = GridLayoutScript.TECH_ITEM_WIDTH_PER_HEIGHT
const STONE_ICON_HEIGHT_RATIO: float = 1.0 / 3.0
const STONE_ICON_X_FRAC: float = 0.08
const STONE_ICON_Y_FRAC: float = 0.32
const TITLE_Y_FRAC: float = 0.097
const TITLE_W_FRAC: float = 0.62
const TITLE_H_FRAC: float = 0.13
const BODY_X_FRAC: float = 0.34
const BODY_Y_FRAC: float = 0.28
const BODY_W_FRAC: float = 0.58
const BODY_H_FRAC: float = 0.60
const REWARD_BOX_X_FRAC: float = 0.34
## Below title band (~0.097 + 0.13); was 0.21 and overlapped header with larger icons.
const REWARD_BOX_Y_FRAC: float = 0.265
const REWARD_BOX_W_FRAC: float = 0.58
const REWARD_BOX_H_FRAC: float = 0.12
const BODY_Y_FRAC_WITH_REWARDS: float = 0.40
const BODY_H_FRAC_WITH_REWARDS: float = 0.48
const TITLE_FONT_HEIGHT_RATIO: float = 0.068
const TITLE_FONT_HEIGHT_RATIO_COMPACT: float = 0.060
const COMPACT_TITLE_TEXTS: Array[String] = [
	"Mudbrick Construction",
	"Exoplanet Expedition",
]
const BODY_FONT_HEIGHT_RATIO: float = 0.060
const REWARD_NAME_FONT_HEIGHT_RATIO: float = 0.052
const REWARD_VALUE_FONT_HEIGHT_RATIO: float = 0.052
## Card-local yield icon height (fraction of tech item height); was 0.055 before compact-row fix.
const REWARD_ICON_HEIGHT_RATIO: float = 0.088
const REWARD_ROW_SEPARATION_PX: int = 4
const REWARD_NAME_ICON_GAP_PX: int = 4
const REWARD_VALUE_GAP_PX: int = 2
const TITLE_FONT_COLOR: Color = Color(0.95, 0.9, 0.72)
const BODY_FONT_COLOR: Color = Color(0.2, 0.14, 0.08)
const WHEEL_SCROLL_STEP_PX: int = 120
const ROW_HEIGHT_VIEWPORT_FRACTION: float = GridLayoutScript.ROW_HEIGHT_VIEWPORT_FRACTION
const TECH_TREE_CONTENT_SCALE_MULTIPLIER: float = GridLayoutScript.TECH_TREE_CONTENT_SCALE_MULTIPLIER
const LAYOUT_REFERENCE_VIEWPORT_HEIGHT: float = GridLayoutScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
## HudCanvas siblings hidden while preview is open (Science / seat chips bleed through a dim plate).
const _HUD_HIDE_NAMES: Array[String] = ["PlayerContactStrip", "SciencePanel"]

var _scroll: ScrollContainer
var _scroll_content: Control
var _segment_row: HBoxContainer
var _tech_item_tex: Texture2D
var _dependency_lines: Control
var _tech_items: Array[TextureRect] = []
## Canonical grid placement: x=column (1..9), y=row (1..4), z unused.
var _tech_item_placements: Array[Vector3i] = []
var _tech_item_ids: Array[String] = []
var _segment_display_widths: Array[float] = []


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


static func content_scale(viewport_height: float = -1.0) -> float:
	return GridLayoutScript.content_scale(viewport_height)


static func scale_design_vector(design: Vector2, viewport_height: float = -1.0) -> Vector2:
	return design * content_scale(viewport_height)


static func tech_item_display_height(viewport_height: float = -1.0) -> float:
	return TECH_ITEM_DISPLAY_HEIGHT * content_scale(viewport_height)


static func export_slot_catalog_dictionary(segment_display_widths: Array = []) -> Dictionary:
	return GridLayoutScript.export_slot_catalog_dictionary(segment_display_widths)


static func export_slot_catalog_json(segment_display_widths: Array = []) -> String:
	return GridLayoutScript.export_slot_catalog_json(segment_display_widths)


static func scaled_texture_size(tex: Texture2D, display_height: float) -> Vector2:
	if tex == null or display_height <= 0.0:
		return Vector2.ZERO
	var th: float = float(tex.get_height())
	if th <= 0.0:
		return Vector2.ZERO
	var tw: float = float(tex.get_width())
	var w: float = tw * display_height / th
	return Vector2(w, display_height)


static func configure_scaled_texture_filter(node: CanvasItem) -> void:
	## Matches **UnitsView** marker downscale: linear + mipmaps on icon **.import** files.
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func stone_icon_layout(item_size: Vector2) -> Dictionary:
	var icon_h: float = item_size.y * STONE_ICON_HEIGHT_RATIO
	return {
		"height": icon_h,
		"x": item_size.x * STONE_ICON_X_FRAC,
		"y": item_size.y * STONE_ICON_Y_FRAC,
	}


static func uses_compact_title_font(title_text: String) -> bool:
	return COMPACT_TITLE_TEXTS.has(title_text.strip_edges())


static func tech_title_font_size(item_size: Vector2, title_text: String = "") -> int:
	var ratio: float = TITLE_FONT_HEIGHT_RATIO
	if uses_compact_title_font(title_text):
		ratio = TITLE_FONT_HEIGHT_RATIO_COMPACT
	return maxi(int(round(item_size.y * ratio)), 8)


static func tech_title_label_layout(item_size: Vector2, title_text: String = "") -> Dictionary:
	return {
		"x": item_size.x * (1.0 - TITLE_W_FRAC) * 0.5,
		"y": item_size.y * TITLE_Y_FRAC - 2.0,
		"width": item_size.x * TITLE_W_FRAC,
		"height": item_size.y * TITLE_H_FRAC,
		"font_size": tech_title_font_size(item_size, title_text),
	}


static func tech_body_label_layout(item_size: Vector2, has_building_rewards: bool = false) -> Dictionary:
	var y_frac: float = BODY_Y_FRAC_WITH_REWARDS if has_building_rewards else BODY_Y_FRAC
	var h_frac: float = BODY_H_FRAC_WITH_REWARDS if has_building_rewards else BODY_H_FRAC
	return {
		"x": item_size.x * BODY_X_FRAC,
		"y": item_size.y * y_frac,
		"width": item_size.x * BODY_W_FRAC,
		"height": item_size.y * h_frac,
		"font_size": maxi(int(round(item_size.y * BODY_FONT_HEIGHT_RATIO)), 7),
	}


static func tech_reward_box_layout(item_size: Vector2) -> Dictionary:
	return {
		"x": item_size.x * REWARD_BOX_X_FRAC,
		"y": item_size.y * REWARD_BOX_Y_FRAC,
		"width": item_size.x * REWARD_BOX_W_FRAC,
		"height": item_size.y * REWARD_BOX_H_FRAC,
		"name_font_size": maxi(int(round(item_size.y * REWARD_NAME_FONT_HEIGHT_RATIO)), 7),
		"value_font_size": maxi(int(round(item_size.y * REWARD_VALUE_FONT_HEIGHT_RATIO)), 7),
		"icon_height": maxf(item_size.y * REWARD_ICON_HEIGHT_RATIO, 8.0),
	}


static func column_layout(count: int) -> Array:
	return GridLayoutScript.column_layout(count)


static func prototype_column_spec_count(_col: int, _segment_index: int = 0) -> int:
	return NodeLayoutScript.CANONICAL_ROW_COUNT


static func prototype_segment_spec_count() -> int:
	return GridLayoutScript.segment_spec_count()


static func prototype_segment_index(segment_slot: int) -> int:
	return GridLayoutScript.segment_index_for_slot(segment_slot)


static func prototype_segment_center_grid(segment_slot: int) -> bool:
	return GridLayoutScript.segment_center_grid(segment_slot)


static func prototype_segment_mirror_grid(segment_slot: int) -> bool:
	return GridLayoutScript.segment_mirror_grid(segment_slot)


static func mirror_right_inset_design_for_segment(segment_index: int) -> float:
	return GridLayoutScript.mirror_right_inset_design_for_segment(segment_index)


static func mirror_left_margin_reduce_fraction_for_segment(segment_index: int) -> float:
	return GridLayoutScript.mirror_left_margin_reduce_fraction_for_segment(segment_index)


static func leftmost_mirrored_column_index() -> int:
	return GridLayoutScript.leftmost_mirrored_column_index()


static func mirror_left_margin_shift_design(
	segment_design_width: float,
	right_inset_design: float,
	reduce_fraction: float,
) -> float:
	return GridLayoutScript.mirror_left_margin_shift_design(
		segment_design_width,
		right_inset_design,
		reduce_fraction,
	)


static func grid_x_offset_design_for_segment(
	segment_index: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> float:
	return GridLayoutScript.grid_x_offset_design_for_segment(
		segment_index,
		segment_display_widths,
		viewport_height,
	)


static func items_per_segment(segment_index: int = 0) -> int:
	var total: int = 0
	var nodes: Array[Dictionary] = ContentScript.prototype_nodes()
	var i: int = 0
	while i < nodes.size():
		var node: Dictionary = nodes[i]
		var column: int = int(node["column"])
		if NodeLayoutScript.segment_index_for_column(column) == segment_index:
			total += 1
		i += 1
	return total


static func grid_content_width_scaled(viewport_height: float = -1.0) -> float:
	return GridLayoutScript.grid_content_width_scaled(viewport_height)


static func segment_design_width_from_display(
	segment_display_width: float,
	viewport_height: float = -1.0,
) -> float:
	return GridLayoutScript.segment_design_width_from_display(
		segment_display_width,
		viewport_height,
	)


static func segment_local_grid_position(
	col: int,
	row_in_column: int,
	item_count: int = -1,
) -> Vector2:
	var count: int = (
		item_count
		if item_count >= 0
		else prototype_column_spec_count(col, 0)
	)
	return GridLayoutScript.segment_local_grid_position(col, row_in_column, count)


static func mirror_local_grid_position(
	local: Vector2,
	segment_design_width: float,
	right_inset_design: float = 0.0,
) -> Vector2:
	return GridLayoutScript.mirror_local_grid_position(
		local,
		segment_design_width,
		right_inset_design,
	)


static func segment_local_grid_position_resolved(
	col: int,
	row_in_column: int,
	segment_index: int,
	segment_display_widths: Array,
	mirror_grid: bool,
	item_count: int = -1,
	viewport_height: float = -1.0,
) -> Vector2:
	var count: int = (
		item_count
		if item_count >= 0
		else prototype_column_spec_count(col, segment_index)
	)
	return GridLayoutScript.segment_local_grid_position_resolved(
		col,
		row_in_column,
		segment_index,
		segment_display_widths,
		mirror_grid,
		count,
		viewport_height,
	)


static func tech_item_base_position(
	col: int,
	row_in_column: int,
	segment_index: int = 0,
	segment_display_widths: Array = [],
	center_grid: bool = false,
	viewport_height: float = -1.0,
) -> Vector2:
	return GridLayoutScript.tech_item_base_position(
		col,
		row_in_column,
		prototype_column_spec_count(col, segment_index),
		segment_index,
		segment_display_widths,
		center_grid,
		viewport_height,
	)


static func column_x_position(
	col: int,
	segment_index: int = 0,
	segment_display_widths: Array = [],
	center_grid: bool = false,
	viewport_height: float = -1.0,
) -> float:
	return GridLayoutScript.column_x_position(
		col,
		prototype_column_spec_count(col, segment_index),
		segment_index,
		segment_display_widths,
		center_grid,
		viewport_height,
	)


static func tech_item_position(
	segment_index: int,
	col: int,
	row_in_column: int,
	segment_display_widths: Array = [],
	item_count: int = -1,
	center_grid: bool = false,
	mirror_grid: bool = false,
	viewport_height: float = -1.0,
) -> Vector2:
	var count: int = (
		item_count
		if item_count >= 0
		else prototype_column_spec_count(col, segment_index)
	)
	return GridLayoutScript.tech_item_position(
		segment_index,
		col,
		row_in_column,
		segment_display_widths,
		count,
		center_grid,
		mirror_grid,
		viewport_height,
	)


static func tech_item_count() -> int:
	return ContentScript.total_item_count()


static func prototype_content_for_placement(
	_column: int,
	row: int,
	_unused: int = 0,
) -> Dictionary:
	return ContentScript.content_for_grid(_column, row)


static func tech_item_position_for_grid_node(
	column: int,
	row: int,
	segment_display_widths: Array = [],
	viewport_height: float = -1.0,
) -> Vector2:
	return NodeLayoutScript.tech_item_position_for_node(
		column,
		row,
		segment_display_widths,
		viewport_height,
	)


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
		configure_scaled_texture_filter(seg)
		_segment_row.add_child(seg)
		i += 1
	_dependency_lines = DependencyLinesScript.new()
	_dependency_lines.name = "DependencyLines"
	_dependency_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_content.add_child(_dependency_lines)
	_tech_item_tex = load(TECH_ITEM_PATH) as Texture2D
	_build_tech_nodes()
	_rebuild_segment_sizes()


func _build_tech_nodes() -> void:
	_tech_items.clear()
	_tech_item_placements.clear()
	_tech_item_ids.clear()
	var nodes: Array[Dictionary] = ContentScript.prototype_nodes()
	var item_index: int = 0
	var i: int = 0
	while i < nodes.size():
		var node: Dictionary = nodes[i]
		var tech_id: String = str(node["tech_id"])
		var column: int = int(node["column"])
		var row: int = int(node["row"])
		var content: Dictionary = node["content"] as Dictionary
		var pos: Vector2 = tech_item_position_for_grid_node(
			column,
			row,
			_segment_display_widths,
		)
		var icon_tex: Texture2D = load(str(content["icon_path"])) as Texture2D
		var item: TextureRect = _create_tech_item_at_with_content(
			pos,
			content,
			icon_tex,
			item_index,
		)
		item.z_index = 2
		_scroll_content.add_child(item)
		_tech_items.append(item)
		_tech_item_placements.append(Vector3i(column, row, 0))
		_tech_item_ids.append(tech_id)
		item_index += 1
		i += 1


func _create_tech_item_at_with_content(
	pos: Vector2,
	content: Dictionary,
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
	configure_scaled_texture_filter(item)
	if icon_texture != null:
		_attach_icon(item, icon_texture)
	_attach_tech_labels(item, content)
	return item


func _attach_icon(item: TextureRect, icon_texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "TechIcon"
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = icon_texture
	configure_scaled_texture_filter(icon)
	item.add_child(icon)
	return icon


func _attach_tech_labels(item: TextureRect, content: Dictionary) -> void:
	var title := Label.new()
	title.name = "TechTitleLabel"
	title.text = str(content.get("title", ""))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	item.add_child(title)
	var body := Label.new()
	body.name = "TechBodyLabel"
	body.text = ContentScript.body_text_from_content(content)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_child(body)
	_attach_building_rewards(item, content)


func _attach_building_rewards(item: TextureRect, content: Dictionary) -> void:
	var rewards: Array = content.get("building_rewards", [])
	if typeof(rewards) != TYPE_ARRAY or rewards.is_empty():
		return
	var box := Control.new()
	box.name = "TechBuildingRewards"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(box)
	var ri: int = 0
	while ri < rewards.size():
		var reward: Dictionary = rewards[ri] as Dictionary
		var row := Control.new()
		row.name = "BuildingRewardRow_%d" % ri
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var name_label := Label.new()
		name_label.name = "BuildingName"
		name_label.text = str(reward.get("display_name", ""))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		row.add_child(name_label)
		var effects: Array = reward.get("effects", [])
		var ei: int = 0
		while ei < effects.size():
			var effect: Dictionary = effects[ei] as Dictionary
			var effect_key: String = str(effect.get("key", ""))
			var effect_value: int = int(effect.get("value", 0))
			var icon_path: String = BuildingRewardsScript.icon_path_for_effect_key(effect_key)
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				var icon := TextureRect.new()
				icon.name = "EffectIcon_%d" % ei
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.texture = load(icon_path) as Texture2D
				configure_scaled_texture_filter(icon)
				row.add_child(icon)
			else:
				var glyph := Label.new()
				glyph.name = "EffectGlyph_%d" % ei
				glyph.text = BuildingRewardsScript.effect_fallback_glyph(effect_key)
				glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
				glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				row.add_child(glyph)
			var value_label := Label.new()
			value_label.name = "EffectValue_%d" % ei
			value_label.text = BuildingRewardsScript.effect_value_text(effect_value)
			value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(value_label)
			ei += 1
		ri += 1


static func scaled_segment_display_height(_viewport_height: float) -> int:
	return maxi(
		int(
			LAYOUT_REFERENCE_VIEWPORT_HEIGHT
			* ROW_HEIGHT_VIEWPORT_FRACTION
			* content_scale()
		),
		1,
	)


func _segment_display_height() -> int:
	return scaled_segment_display_height(get_viewport_rect().size.y)


func _rebuild_segment_sizes() -> void:
	if _segment_row == null:
		return
	var display_h: int = _segment_display_height()
	var total_w: int = 0
	_segment_display_widths.clear()
	var i: int = 0
	while i < _segment_row.get_child_count():
		var seg := _segment_row.get_child(i) as TextureRect
		if seg != null and seg.texture != null:
			var scaled: Vector2 = scaled_texture_size(seg.texture, float(display_h))
			var scaled_w: int = int(round(scaled.x))
			seg.custom_minimum_size = Vector2(scaled_w, display_h)
			seg.size = Vector2(scaled_w, display_h)
			_segment_display_widths.append(float(scaled_w))
			total_w += scaled_w
		i += 1
	if _scroll_content != null:
		_scroll_content.custom_minimum_size = Vector2(total_w, display_h)
		_scroll_content.size = Vector2(total_w, display_h)
	_layout_tech_items()
	_layout_dependency_lines()


func _layout_tech_items() -> void:
	if _tech_item_tex == null:
		return
	var viewport_h: float = get_viewport_rect().size.y
	var item_size: Vector2 = scaled_texture_size(
		_tech_item_tex,
		tech_item_display_height(viewport_h),
	)
	var i: int = 0
	while i < _tech_items.size():
		var placement: Vector3i = _tech_item_placements[i]
		var column: int = placement.x
		var row: int = placement.y
		var item: TextureRect = _tech_items[i]
		item.custom_minimum_size = item_size
		item.size = item_size
		item.position = tech_item_position_for_grid_node(
			column,
			row,
			_segment_display_widths,
			viewport_h,
		)
		var icon: TextureRect = item.get_node_or_null("TechIcon") as TextureRect
		if icon != null:
			_layout_icon_on_item(item, icon)
		_layout_labels_on_item(item)
		i += 1


func _layout_dependency_lines() -> void:
	if _dependency_lines == null:
		return
	var viewport_h: float = get_viewport_rect().size.y
	var rects_by_title: Dictionary = {}
	var i: int = 0
	while i < _tech_items.size():
		var item: TextureRect = _tech_items[i]
		var content: Dictionary = ContentScript.tech_by_id(_tech_item_ids[i])
		var title: String = str(content.get("title", ""))
		if not title.is_empty():
			rects_by_title[title] = Rect2(item.position, item.size)
		i += 1
	var polylines: Array = NodeLayoutScript.build_dependency_polylines(
		rects_by_title,
		_segment_display_widths,
		viewport_h,
	)
	_dependency_lines.position = Vector2.ZERO
	_dependency_lines.size = _scroll_content.size
	_dependency_lines.z_index = 1
	_dependency_lines.set_polylines(polylines)


func _segment_center_grid_for_index(segment_index: int) -> bool:
	return _segment_layout_flag_for_index(segment_index, "center_grid")


func _segment_mirror_grid_for_index(segment_index: int) -> bool:
	return _segment_layout_flag_for_index(segment_index, "mirror_grid")


func _segment_layout_flag_for_index(segment_index: int, flag_name: String) -> bool:
	var slot: int = 0
	while slot < prototype_segment_spec_count():
		if prototype_segment_index(slot) == segment_index:
			return bool(PROTOTYPE_SEGMENT_SPECS[slot][flag_name])
		slot += 1
	return false


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
	var rewards: Control = item.get_node_or_null("TechBuildingRewards") as Control
	if rewards != null:
		_layout_building_rewards_on_item(item, rewards)
	var body: Label = item.get_node_or_null("TechBodyLabel") as Label
	if body != null:
		_layout_body_label_on_item(item, body, rewards != null)


func _layout_title_label_on_item(item: TextureRect, title: Label) -> void:
	var layout: Dictionary = tech_title_label_layout(item.size, title.text)
	title.position = Vector2(float(layout["x"]), float(layout["y"]))
	title.size = Vector2(float(layout["width"]), float(layout["height"]))
	title.add_theme_color_override("font_color", TITLE_FONT_COLOR)
	title.add_theme_font_size_override("font_size", int(layout["font_size"]))


func _layout_body_label_on_item(item: TextureRect, body: Label, has_building_rewards: bool = false) -> void:
	var layout: Dictionary = tech_body_label_layout(item.size, has_building_rewards)
	body.position = Vector2(float(layout["x"]), float(layout["y"]))
	body.size = Vector2(float(layout["width"]), float(layout["height"]))
	body.add_theme_color_override("font_color", BODY_FONT_COLOR)
	body.add_theme_font_size_override("font_size", int(layout["font_size"]))


func _layout_building_rewards_on_item(item: TextureRect, rewards: Control) -> void:
	var layout: Dictionary = tech_reward_box_layout(item.size)
	rewards.position = Vector2(float(layout["x"]), float(layout["y"]))
	rewards.size = Vector2(float(layout["width"]), float(layout["height"]))
	var name_font: int = int(layout["name_font_size"])
	var value_font: int = int(layout["value_font_size"])
	var icon_h: float = float(layout["icon_height"])
	var box_w: float = float(layout["width"])
	var row_y: float = 0.0
	var child_i: int = 0
	while child_i < rewards.get_child_count():
		var child: Node = rewards.get_child(child_i)
		if child is Control and str(child.name).begins_with("BuildingRewardRow"):
			var row: Control = child as Control
			row.position = Vector2(0.0, row_y)
			row.size = Vector2(box_w, icon_h)
			_layout_building_reward_row_parts(
				row,
				icon_h,
				name_font,
				value_font,
			)
			row_y += icon_h + float(REWARD_ROW_SEPARATION_PX)
		child_i += 1


static func measured_reward_text_width(text: String, font_size: int) -> float:
	var sample: String = str(text)
	if sample.is_empty() or font_size <= 0:
		return 0.0
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return float(sample.length()) * float(font_size) * 0.52
	return font.get_string_size(
		sample,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
	).x


func _measure_reward_row_trailing_width(row: Control, icon_h: float, value_font: int) -> float:
	var total: float = float(REWARD_NAME_ICON_GAP_PX)
	var part_i: int = 0
	while part_i < row.get_child_count():
		var part: Node = row.get_child(part_i)
		if part is TextureRect and str(part.name).begins_with("EffectIcon"):
			var icon_node: TextureRect = part as TextureRect
			if icon_node.texture != null:
				var icon_size: Vector2 = scaled_texture_size(icon_node.texture, icon_h)
				total += icon_size.x + float(REWARD_VALUE_GAP_PX)
		elif part is Label and str(part.name).begins_with("EffectGlyph"):
			total += icon_h + float(REWARD_VALUE_GAP_PX)
		elif part is Label and str(part.name).begins_with("EffectValue"):
			var value_node: Label = part as Label
			total += measured_reward_text_width(value_node.text, value_font)
		part_i += 1
	return total


func _layout_building_reward_row_parts(
	row: Control,
	icon_h: float,
	name_font: int,
	value_font: int,
) -> void:
	var trailing_w: float = _measure_reward_row_trailing_width(row, icon_h, value_font)
	var max_name_w: float = maxf(row.size.x - trailing_w, 0.0)
	var cursor_x: float = 0.0
	var name_label: Label = row.get_node_or_null("BuildingName") as Label
	if name_label != null:
		var measured_name_w: float = measured_reward_text_width(name_label.text, name_font)
		var name_w: float = minf(measured_name_w, max_name_w)
		name_label.position = Vector2(0.0, 0.0)
		name_label.size = Vector2(name_w, icon_h)
		name_label.add_theme_color_override("font_color", BODY_FONT_COLOR)
		name_label.add_theme_font_size_override("font_size", name_font)
		cursor_x = name_w + float(REWARD_NAME_ICON_GAP_PX)
	var part_i: int = 0
	while part_i < row.get_child_count():
		var part: Node = row.get_child(part_i)
		if part is TextureRect and str(part.name).begins_with("EffectIcon"):
			var icon_node: TextureRect = part as TextureRect
			if icon_node.texture != null:
				var icon_size: Vector2 = scaled_texture_size(icon_node.texture, icon_h)
				icon_node.position = Vector2(cursor_x, (icon_h - icon_size.y) * 0.5)
				icon_node.size = icon_size
				icon_node.custom_minimum_size = icon_size
				cursor_x = icon_node.position.x + icon_size.x + float(REWARD_VALUE_GAP_PX)
		elif part is Label and str(part.name).begins_with("EffectGlyph"):
			var glyph_node: Label = part as Label
			glyph_node.position = Vector2(cursor_x, 0.0)
			glyph_node.size = Vector2(icon_h, icon_h)
			glyph_node.custom_minimum_size = Vector2(icon_h, icon_h)
			glyph_node.add_theme_color_override("font_color", BODY_FONT_COLOR)
			glyph_node.add_theme_font_size_override("font_size", value_font)
			cursor_x = glyph_node.position.x + icon_h + float(REWARD_VALUE_GAP_PX)
		elif part is Label and str(part.name).begins_with("EffectValue"):
			var value_node: Label = part as Label
			value_node.position = Vector2(cursor_x, 0.0)
			value_node.size = Vector2(maxf(row.size.x - cursor_x, 0.0), icon_h)
			value_node.add_theme_color_override("font_color", BODY_FONT_COLOR)
			value_node.add_theme_font_size_override("font_size", value_font)
		part_i += 1


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
