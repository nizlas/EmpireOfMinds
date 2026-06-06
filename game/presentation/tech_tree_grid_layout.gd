# Tech tree parchment grid: slot catalog, design coords, segment layout (presentation only).
# Future tech JSON maps tech_id -> slot_id; positions resolve through this registry.
class_name TechTreeGridLayout
extends RefCounted

const CATALOG_VERSION: int = 1
const SEGMENT_COUNT: int = 3
const COLUMN_COUNT: int = 3
const COLUMN_ROW_COUNT_OPTIONS: Array[int] = [1, 2, 3, 4]

const COLUMN_X_START: float = 180.0
const COLUMN_X_STEP: float = 390.0
const TECH_ITEM_GROUP_OFFSET: Vector2 = Vector2(85.0, 18.0)
## 4-row column is source of truth; 1/2/3-row Y positions derive from y0..y3.
const COLUMN_LAYOUT_4: Array[float] = [148.0, 378.0, 608.0, 838.0]

const TECH_ITEM_DISPLAY_HEIGHT: float = 190.0
const TECH_ITEM_WIDTH_PER_HEIGHT: float = 1448.0 / 1086.0
const TECH_TREE_CONTENT_SCALE_MULTIPLIER: float = 1.5
const ROW_HEIGHT_VIEWPORT_FRACTION: float = 0.82
const LAYOUT_REFERENCE_VIEWPORT_HEIGHT: float = 1500.0
const PARCHMENT_TEXTURE_HEIGHT: float = 1086.0
## Native texture widths (height 1086) for reference catalog scroll offsets.
const SEGMENT_TEXTURE_WIDTHS: Array[float] = [1357.0, 1262.0, 1361.0]

const SEGMENT_SPECS: Array = [
	{
		"segment_index": 0,
		"background_label": "bg_1",
		"center_grid": false,
		"mirror_grid": false,
		"symmetric_mirror_shift_from_segment": 2,
	},
	{
		"segment_index": 1,
		"background_label": "bg_2",
		"center_grid": true,
		"mirror_grid": false,
	},
	{
		"segment_index": 2,
		"background_label": "bg_3",
		"center_grid": false,
		"mirror_grid": true,
		"mirror_right_inset_design": 35.0,
		"mirror_left_margin_reduce_fraction": 1.0 / 3.0,
	},
]


static func content_scale(_viewport_height: float = -1.0) -> float:
	return TECH_TREE_CONTENT_SCALE_MULTIPLIER


static func column_layout_y_by_count() -> Dictionary:
	return {
		"1": column_layout(1),
		"2": column_layout(2),
		"3": column_layout(3),
		"4": column_layout(4),
	}


static func column_layout(count: int) -> Array:
	return _get_column_layout(count)


static func slot_id(segment_index: int, col: int, row_in_column: int, column_item_count: int) -> String:
	return "bg%d_c%d_r%d_n%d" % [
		segment_index + 1,
		col,
		row_in_column,
		column_item_count,
	]


static func segment_slot_for_index(segment_index: int) -> int:
	var slot: int = 0
	while slot < segment_spec_count():
		if segment_index_for_slot(slot) == segment_index:
			return slot
		slot += 1
	return -1


static func segment_layout_mode_for_index(segment_index: int) -> String:
	var slot: int = segment_slot_for_index(segment_index)
	if slot < 0:
		return "left"
	if segment_center_grid(slot):
		return "center"
	if segment_mirror_grid(slot):
		return "mirror"
	return "left"


static func segment_spec_count() -> int:
	return SEGMENT_SPECS.size()


static func segment_index_for_slot(segment_slot: int) -> int:
	return int(SEGMENT_SPECS[segment_slot]["segment_index"])


static func segment_background_label(segment_slot: int) -> String:
	return str(SEGMENT_SPECS[segment_slot]["background_label"])


static func segment_center_grid(segment_slot: int) -> bool:
	return bool(SEGMENT_SPECS[segment_slot]["center_grid"])


static func segment_mirror_grid(segment_slot: int) -> bool:
	return bool(SEGMENT_SPECS[segment_slot]["mirror_grid"])


static func segment_mirror_right_inset_design(segment_slot: int) -> float:
	var spec: Dictionary = SEGMENT_SPECS[segment_slot]
	return float(spec.get("mirror_right_inset_design", 0.0))


static func mirror_right_inset_design_for_segment(segment_index: int) -> float:
	var slot: int = segment_slot_for_index(segment_index)
	if slot < 0:
		return 0.0
	return segment_mirror_right_inset_design(slot)


static func segment_mirror_left_margin_reduce_fraction(segment_slot: int) -> float:
	var spec: Dictionary = SEGMENT_SPECS[segment_slot]
	return float(spec.get("mirror_left_margin_reduce_fraction", 0.0))


static func mirror_left_margin_reduce_fraction_for_segment(segment_index: int) -> float:
	var slot: int = segment_slot_for_index(segment_index)
	if slot < 0:
		return 0.0
	return segment_mirror_left_margin_reduce_fraction(slot)


static func leftmost_mirrored_column_index() -> int:
	return COLUMN_COUNT - 1


static func reference_parchment_display_height() -> float:
	return (
		LAYOUT_REFERENCE_VIEWPORT_HEIGHT
		* ROW_HEIGHT_VIEWPORT_FRACTION
		* content_scale()
	)


static func reference_segment_display_widths() -> Array[float]:
	var display_h: float = reference_parchment_display_height()
	var widths: Array[float] = []
	var i: int = 0
	while i < SEGMENT_TEXTURE_WIDTHS.size():
		var tex_w: float = float(SEGMENT_TEXTURE_WIDTHS[i])
		widths.append(tex_w * display_h / PARCHMENT_TEXTURE_HEIGHT)
		i += 1
	return widths


static func tech_item_width_design() -> float:
	return TECH_ITEM_DISPLAY_HEIGHT * TECH_ITEM_WIDTH_PER_HEIGHT


static func segment_design_width_from_display(
	segment_display_width: float,
	_viewport_height: float = -1.0,
) -> float:
	return segment_display_width / content_scale(_viewport_height)


static func segment_grid_min_local_x() -> float:
	return COLUMN_X_START + TECH_ITEM_GROUP_OFFSET.x


static func grid_content_width_design() -> float:
	var item_w: float = tech_item_width_design()
	var left: float = segment_grid_min_local_x()
	var right_edge: float = (
		COLUMN_X_START
		+ float(COLUMN_COUNT - 1) * COLUMN_X_STEP
		+ TECH_ITEM_GROUP_OFFSET.x
		+ item_w
	)
	return right_edge - left


static func grid_content_width_scaled(_viewport_height: float = -1.0) -> float:
	return grid_content_width_design() * content_scale(_viewport_height)


static func segment_local_grid_position(
	col: int,
	row_in_column: int,
	column_item_count: int,
) -> Vector2:
	var layout: Array = _get_column_layout(column_item_count)
	return Vector2(
		COLUMN_X_START + float(col) * COLUMN_X_STEP + TECH_ITEM_GROUP_OFFSET.x,
		float(layout[row_in_column]),
	)


static func mirror_local_grid_position(
	local: Vector2,
	segment_design_width: float,
	right_inset_design: float = 0.0,
) -> Vector2:
	var effective_w: float = segment_design_width - right_inset_design
	return Vector2(
		effective_w - local.x - tech_item_width_design(),
		local.y,
	)


static func mirror_left_margin_shift_design(
	segment_design_width: float,
	right_inset_design: float,
	reduce_fraction: float,
) -> float:
	if reduce_fraction <= 0.0:
		return 0.0
	var left_col: int = leftmost_mirrored_column_index()
	var leftmost_local: Vector2 = segment_local_grid_position(left_col, 0, 4)
	var leftmost_mirrored: Vector2 = mirror_local_grid_position(
		leftmost_local,
		segment_design_width,
		right_inset_design,
	)
	return leftmost_mirrored.x * reduce_fraction


static func segment_grid_x_offset_design(
	segment_slot: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> float:
	var spec: Dictionary = SEGMENT_SPECS[segment_slot]
	if spec.has("symmetric_mirror_shift_from_segment"):
		var ref_segment_index: int = int(spec["symmetric_mirror_shift_from_segment"])
		if ref_segment_index < segment_display_widths.size():
			var ref_design_w: float = segment_design_width_from_display(
				float(segment_display_widths[ref_segment_index]),
				viewport_height,
			)
			var ref_inset: float = mirror_right_inset_design_for_segment(ref_segment_index)
			var ref_reduce: float = mirror_left_margin_reduce_fraction_for_segment(
				ref_segment_index,
			)
			return mirror_left_margin_shift_design(ref_design_w, ref_inset, ref_reduce)
	return float(spec.get("grid_x_offset_design", 0.0))


static func grid_x_offset_design_for_segment(
	segment_index: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> float:
	var slot: int = segment_slot_for_index(segment_index)
	if slot < 0:
		return 0.0
	return segment_grid_x_offset_design(slot, segment_display_widths, viewport_height)


static func segment_local_grid_position_resolved(
	col: int,
	row_in_column: int,
	segment_index: int,
	segment_display_widths: Array,
	mirror_grid: bool,
	column_item_count: int,
	viewport_height: float = -1.0,
) -> Vector2:
	var local: Vector2 = segment_local_grid_position(col, row_in_column, column_item_count)
	var resolved: Vector2 = local
	if segment_index < segment_display_widths.size():
		var seg_design_w: float = segment_design_width_from_display(
			float(segment_display_widths[segment_index]),
			viewport_height,
		)
		var right_inset: float = mirror_right_inset_design_for_segment(segment_index)
		var reduce_fraction: float = mirror_left_margin_reduce_fraction_for_segment(
			segment_index,
		)
		if mirror_grid:
			var mirrored: Vector2 = mirror_local_grid_position(local, seg_design_w, right_inset)
			var shift: float = mirror_left_margin_shift_design(
				seg_design_w,
				right_inset,
				reduce_fraction,
			)
			resolved = Vector2(mirrored.x - shift, mirrored.y)
		elif reduce_fraction > 0.0:
			var shift: float = mirror_left_margin_shift_design(
				seg_design_w,
				right_inset,
				reduce_fraction,
			)
			resolved = Vector2(local.x - shift, local.y)
	var x_offset: float = grid_x_offset_design_for_segment(
		segment_index,
		segment_display_widths,
		viewport_height,
	)
	return Vector2(resolved.x + x_offset, resolved.y)


static func segment_scroll_offset_x(
	segment_index: int,
	segment_display_widths: Array,
	center_grid: bool,
	viewport_height: float = -1.0,
) -> float:
	var offset: float = 0.0
	var i: int = 0
	while i < segment_index:
		if i < segment_display_widths.size():
			offset += float(segment_display_widths[i])
		i += 1
	if center_grid and segment_index < segment_display_widths.size():
		var seg_w: float = float(segment_display_widths[segment_index])
		var grid_w: float = grid_content_width_scaled(viewport_height)
		var min_local_scaled: float = segment_grid_min_local_x() * content_scale(viewport_height)
		offset += maxf((seg_w - grid_w) * 0.5, 0.0) - min_local_scaled
	return offset


static func tech_item_base_position(
	col: int,
	row_in_column: int,
	column_item_count: int,
	segment_index: int = 0,
	segment_display_widths: Array = [],
	center_grid: bool = false,
	viewport_height: float = -1.0,
) -> Vector2:
	var layout: Array = _get_column_layout(column_item_count)
	var local: Vector2 = Vector2(
		COLUMN_X_START + float(col) * COLUMN_X_STEP,
		float(layout[row_in_column]),
	)
	local.x += grid_x_offset_design_for_segment(
		segment_index,
		segment_display_widths,
		viewport_height,
	)
	var seg_offset: float = segment_scroll_offset_x(
		segment_index,
		segment_display_widths,
		center_grid,
		viewport_height,
	)
	return Vector2(seg_offset, 0.0) + local * content_scale(viewport_height)


static func column_x_position(
	col: int,
	column_item_count: int,
	segment_index: int = 0,
	segment_display_widths: Array = [],
	center_grid: bool = false,
	viewport_height: float = -1.0,
) -> float:
	var seg_offset: float = segment_scroll_offset_x(
		segment_index,
		segment_display_widths,
		center_grid,
		viewport_height,
	)
	var x_offset: float = grid_x_offset_design_for_segment(
		segment_index,
		segment_display_widths,
		viewport_height,
	)
	return seg_offset + (
		COLUMN_X_START + float(col) * COLUMN_X_STEP + TECH_ITEM_GROUP_OFFSET.x + x_offset
	) * content_scale(viewport_height)


static func tech_item_position(
	segment_index: int,
	col: int,
	row_in_column: int,
	segment_display_widths: Array,
	column_item_count: int,
	center_grid: bool = false,
	mirror_grid: bool = false,
	viewport_height: float = -1.0,
) -> Vector2:
	var seg_offset: float = segment_scroll_offset_x(
		segment_index,
		segment_display_widths,
		center_grid,
		viewport_height,
	)
	var local: Vector2 = segment_local_grid_position_resolved(
		col,
		row_in_column,
		segment_index,
		segment_display_widths,
		mirror_grid,
		column_item_count,
		viewport_height,
	)
	return Vector2(seg_offset, 0.0) + local * content_scale(viewport_height)


static func slot_entry(
	segment_index: int,
	col: int,
	row_in_column: int,
	column_item_count: int,
	segment_display_widths: Array,
	viewport_height: float = -1.0,
) -> Dictionary:
	var slot: int = segment_slot_for_index(segment_index)
	var center_grid: bool = segment_center_grid(slot) if slot >= 0 else false
	var mirror_grid: bool = segment_mirror_grid(slot) if slot >= 0 else false
	var design_local: Vector2 = segment_local_grid_position_resolved(
		col,
		row_in_column,
		segment_index,
		segment_display_widths,
		mirror_grid,
		column_item_count,
		viewport_height,
	)
	var scroll_design: Vector2 = Vector2(
		segment_scroll_offset_x(
			segment_index,
			segment_display_widths,
			center_grid,
			viewport_height,
		),
		0.0,
	) + design_local
	var display_scroll: Vector2 = tech_item_position(
		segment_index,
		col,
		row_in_column,
		segment_display_widths,
		column_item_count,
		center_grid,
		mirror_grid,
		viewport_height,
	)
	return {
		"slot_id": slot_id(segment_index, col, row_in_column, column_item_count),
		"segment_index": segment_index,
		"background_label": segment_background_label(slot) if slot >= 0 else "",
		"layout_mode": segment_layout_mode_for_index(segment_index),
		"column_index": col,
		"row_in_column": row_in_column,
		"column_item_count": column_item_count,
		"design_local": {"x": design_local.x, "y": design_local.y},
		"design_scroll": {"x": scroll_design.x, "y": scroll_design.y},
		"display_scroll": {"x": display_scroll.x, "y": display_scroll.y},
	}


static func all_slot_entries(segment_display_widths: Array = []) -> Array[Dictionary]:
	var widths: Array = segment_display_widths
	if widths.is_empty():
		widths = reference_segment_display_widths()
	var out: Array[Dictionary] = []
	var segment_index: int = 0
	while segment_index < SEGMENT_COUNT:
		var col: int = 0
		while col < COLUMN_COUNT:
			var column_item_count: int = 0
			while column_item_count < COLUMN_ROW_COUNT_OPTIONS.size():
				var count: int = COLUMN_ROW_COUNT_OPTIONS[column_item_count]
				var row: int = 0
				while row < count:
					out.append(
						slot_entry(segment_index, col, row, count, widths),
					)
					row += 1
				column_item_count += 1
			col += 1
		segment_index += 1
	return out


static func export_slot_catalog_dictionary(segment_display_widths: Array = []) -> Dictionary:
	return {
		"version": CATALOG_VERSION,
		"content_scale": TECH_TREE_CONTENT_SCALE_MULTIPLIER,
		"tech_item_display_height_design": TECH_ITEM_DISPLAY_HEIGHT,
		"column_x_start": COLUMN_X_START,
		"column_x_step": COLUMN_X_STEP,
		"tech_item_group_offset": {
			"x": TECH_ITEM_GROUP_OFFSET.x,
			"y": TECH_ITEM_GROUP_OFFSET.y,
		},
		"column_row_count_options": COLUMN_ROW_COUNT_OPTIONS.duplicate(),
		"column_layout_y": column_layout_y_by_count(),
		"segment_specs": SEGMENT_SPECS.duplicate(true),
		"reference_parchment_display_height": reference_parchment_display_height(),
		"reference_segment_display_widths": reference_segment_display_widths(),
		"slots": all_slot_entries(segment_display_widths),
	}


static func export_slot_catalog_json(segment_display_widths: Array = []) -> String:
	return JSON.stringify(export_slot_catalog_dictionary(segment_display_widths), "\t")


static func find_slot_entry(slot_id_value: String, segment_display_widths: Array = []) -> Dictionary:
	var target: String = str(slot_id_value).strip_edges()
	if target.is_empty():
		return {}
	var entries: Array[Dictionary] = all_slot_entries(segment_display_widths)
	var i: int = 0
	while i < entries.size():
		var entry: Dictionary = entries[i]
		if str(entry.get("slot_id", "")) == target:
			return entry
		i += 1
	return {}


static func map_config_to_placements(
	config: Dictionary,
	segment_display_widths: Array = [],
) -> Array[Dictionary]:
	var items: Array = config.get("items", []) as Array
	var out: Array[Dictionary] = []
	var widths: Array = segment_display_widths
	if widths.is_empty():
		widths = reference_segment_display_widths()
	var i: int = 0
	while i < items.size():
		var row: Dictionary = items[i] as Dictionary
		var tech_id: String = str(row.get("tech_id", "")).strip_edges()
		var sid: String = str(row.get("slot_id", "")).strip_edges()
		var slot: Dictionary = find_slot_entry(sid, widths)
		if tech_id.is_empty() or slot.is_empty():
			i += 1
			continue
		var placement: Dictionary = slot.duplicate(true)
		placement["tech_id"] = tech_id
		out.append(placement)
		i += 1
	return out


static func _four_column_y(index: int) -> float:
	return float(COLUMN_LAYOUT_4[index])


static func _derive_column_layout_1() -> Array[float]:
	return [(_four_column_y(0) + _four_column_y(3)) * 0.5]


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
		1:
			return _derive_column_layout_1()
		2:
			return _derive_column_layout_2()
		3:
			return _derive_column_layout_3()
		4:
			return COLUMN_LAYOUT_4
	return COLUMN_LAYOUT_4
