# Headless: tech tree slot catalog, column layouts, JSON mapping (presentation only).
extends SceneTree

const GridScript = preload("res://presentation/tech_tree_grid_layout.gd")
const OverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_column_layouts()
	_test_slot_catalog_size_and_ids()
	_test_single_item_centered_y()
	_test_overlay_position_parity()
	_test_json_export_roundtrip()
	_test_map_config_to_placements()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_column_layouts() -> void:
	var y0: float = GridScript.COLUMN_LAYOUT_4[0]
	var y3: float = GridScript.COLUMN_LAYOUT_4[3]
	var layout_1: Array = GridScript.column_layout(1)
	var layout_2: Array = GridScript.column_layout(2)
	var layout_3: Array = GridScript.column_layout(3)
	_check(layout_1.size() == 1, "1-row layout has one y")
	_check(absf(float(layout_1[0]) - (y0 + y3) * 0.5) < 0.01, "1-row y centered between y0 and y3")
	_check(layout_2.size() == 2, "2-row layout has two y values")
	_check(layout_3.size() == 3, "3-row layout has three y values")
	_check(GridScript.column_layout(4) == GridScript.COLUMN_LAYOUT_4, "4-row layout is source of truth")


func _test_slot_catalog_size_and_ids() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var entries: Array[Dictionary] = GridScript.all_slot_entries(widths)
	_check(entries.size() == 90, "catalog has 90 slots (3 segments x 3 columns x 10 row variants)")
	var seen: Dictionary = {}
	var i: int = 0
	while i < entries.size():
		var entry: Dictionary = entries[i]
		var sid: String = str(entry.get("slot_id", ""))
		_check(not sid.is_empty(), "slot %d has slot_id" % i)
		_check(not seen.has(sid), "slot_id unique: %s" % sid)
		seen[sid] = true
		var segment_index: int = int(entry.get("segment_index", -1))
		var col: int = int(entry.get("column_index", -1))
		var row: int = int(entry.get("row_in_column", -1))
		var count: int = int(entry.get("column_item_count", -1))
		_check(
			sid == GridScript.slot_id(segment_index, col, row, count),
			"slot_id matches coordinates: %s" % sid,
		)
		_check(entry.has("design_local"), "slot has design_local")
		_check(entry.has("display_scroll"), "slot has display_scroll")
		i += 1


func _test_single_item_centered_y() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var entry: Dictionary = GridScript.find_slot_entry("bg1_c1_r0_n1", widths)
	_check(not entry.is_empty(), "find single-item slot bg1_c1_r0_n1")
	if entry.is_empty():
		return
	var expected_y: float = float(GridScript.column_layout(1)[0])
	var design_y: float = float(entry["design_local"]["y"])
	_check(absf(design_y - expected_y) < 0.01, "single-item design_local y uses centered layout")
	var display_y: float = float(entry["display_scroll"]["y"])
	_check(
		absf(display_y - expected_y * GridScript.content_scale()) < 0.5,
		"single-item display_scroll y scaled",
	)


func _test_overlay_position_parity() -> void:
	var widths: Array = GridScript.reference_segment_display_widths()
	var viewport_h: float = GridScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
	var segment_slot: int = 0
	while segment_slot < GridScript.segment_spec_count():
		var segment_index: int = GridScript.segment_index_for_slot(segment_slot)
		var center_grid: bool = GridScript.segment_center_grid(segment_slot)
		var mirror_grid: bool = GridScript.segment_mirror_grid(segment_slot)
		var col: int = 0
		while col < GridScript.COLUMN_COUNT:
			var count: int = OverlayScript.prototype_column_spec_count(col)
			var row: int = 0
			while row < count:
				var overlay_pos: Vector2 = OverlayScript.tech_item_position(
					segment_index,
					col,
					row,
					widths,
					count,
					center_grid,
					mirror_grid,
					viewport_h,
				)
				var grid_pos: Vector2 = GridScript.tech_item_position(
					segment_index,
					col,
					row,
					widths,
					count,
					center_grid,
					mirror_grid,
					viewport_h,
				)
				_check(
					overlay_pos.is_equal_approx(grid_pos),
					"overlay/grid parity seg=%d col=%d row=%d count=%d" % [
						segment_index,
						col,
						row,
						count,
					],
				)
				row += 1
			col += 1
		segment_slot += 1


func _test_json_export_roundtrip() -> void:
	var json_text: String = GridScript.export_slot_catalog_json()
	_check(not json_text.is_empty(), "export_slot_catalog_json non-empty")
	var parsed: Variant = JSON.parse_string(json_text)
	_check(parsed is Dictionary, "catalog JSON parses to dictionary")
	if not parsed is Dictionary:
		return
	var catalog: Dictionary = parsed
	_check(int(catalog.get("version", 0)) == GridScript.CATALOG_VERSION, "catalog version")
	_check(catalog.has("column_layout_y"), "catalog has column_layout_y")
	var layout_y: Dictionary = catalog["column_layout_y"]
	_check(str(layout_y.get("1", [])).length() > 0, "column_layout_y includes 1-row")
	var slots: Array = catalog.get("slots", [])
	_check(slots.size() == 90, "JSON catalog slot count")
	var overlay_json: String = OverlayScript.export_slot_catalog_json()
	_check(overlay_json == json_text, "overlay delegates catalog export")


func _test_map_config_to_placements() -> void:
	var config: Dictionary = {
		"items": [
			{"tech_id": "stone_tools", "slot_id": "bg1_c0_r0_n4"},
			{"tech_id": "mining", "slot_id": "bg2_c1_r0_n2"},
			{"tech_id": "writing", "slot_id": "bg3_c2_r1_n3"},
			{"tech_id": "ignored", "slot_id": ""},
		],
	}
	var placements: Array[Dictionary] = GridScript.map_config_to_placements(config)
	_check(placements.size() == 3, "map_config skips invalid rows")
	_check(str(placements[0].get("tech_id", "")) == "stone_tools", "first placement tech_id")
	_check(str(placements[0].get("slot_id", "")) == "bg1_c0_r0_n4", "first placement slot_id")
	_check(placements[0].has("display_scroll"), "placement includes display_scroll")
