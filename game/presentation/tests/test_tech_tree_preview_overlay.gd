# Headless: tech-tree preview overlay wiring + segment paths.
extends SceneTree

const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_segment_paths_exist()
	_test_prototype_asset_paths_exist()
	_test_main_scene_wiring()
	await _test_overlay_open_close()
	await _test_tech_item_layout()
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


func _test_segment_paths_exist() -> void:
	_check(TechTreeOverlayScript.SEGMENT_PATHS.size() == 3, "three segment paths")
	var i: int = 0
	while i < TechTreeOverlayScript.SEGMENT_PATHS.size():
		var path: String = TechTreeOverlayScript.SEGMENT_PATHS[i]
		_check(ResourceLoader.exists(path), "segment exists: %s" % path)
		i += 1


func _test_prototype_asset_paths_exist() -> void:
	_check(ResourceLoader.exists(TechTreeOverlayScript.TECH_ITEM_PATH), "tech_item exists")
	_check(ResourceLoader.exists(TechTreeOverlayScript.STONE_TOOLS_PATH), "stone_tools exists")
	_check(load(TechTreeOverlayScript.TECH_ITEM_PATH) is Texture2D, "tech_item loads as texture")
	_check(load(TechTreeOverlayScript.STONE_TOOLS_PATH) is Texture2D, "stone_tools loads as texture")


func _test_main_scene_wiring() -> void:
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas exists")
	var btn = hud.get_node_or_null("TechTreeButton") if hud != null else null
	_check(btn is Button, "TechTreeButton exists")
	if btn is Button:
		_check((btn as Button).text == "Tech Tree", "Tech Tree button label")
	var overlay = hud.get_node_or_null("TechTreePreviewOverlay") if hud != null else null
	_check(overlay != null, "TechTreePreviewOverlay exists")
	if overlay != null:
		_check(not overlay.visible, "overlay hidden by default")
	root.free()


func _test_overlay_open_close() -> void:
	var hud := CanvasLayer.new()
	var strip := Control.new()
	strip.name = "PlayerContactStrip"
	strip.visible = true
	hud.add_child(strip)
	var sci := Control.new()
	sci.name = "SciencePanel"
	sci.visible = true
	hud.add_child(sci)
	var overlay: Control = TechTreeOverlayScript.new()
	hud.add_child(overlay)
	get_root().add_child(hud)
	for _i in 2:
		await process_frame
	overlay.open_overlay()
	_check(overlay.visible, "open_overlay shows overlay")
	_check(not strip.visible, "open_overlay hides PlayerContactStrip")
	_check(not sci.visible, "open_overlay hides SciencePanel")
	overlay.close_overlay()
	_check(not overlay.visible, "close_overlay hides overlay")
	var rows: Array = []
	_collect_hbox_segment_row(overlay, rows)
	var row: HBoxContainer = rows[0] if rows.size() > 0 else null
	_check(row != null, "segment row exists")
	if row != null:
		_check(row.get_child_count() == 3, "three segment TextureRects")
		_check(
			int(row.get_theme_constant("separation", "HBoxContainer")) == 0,
			"segment HBox separation is zero",
		)
		var c: int = 0
		while c < row.get_child_count():
			var seg := row.get_child(c) as TextureRect
			_check(seg is TextureRect, "segment child is TextureRect")
			if seg != null:
				_check(
					seg.mouse_filter == Control.MOUSE_FILTER_IGNORE,
					"segment ignores mouse so wheel reaches scroll",
				)
			c += 1
	overlay.open_overlay()
	for _i in 2:
		await process_frame
	if overlay is TechTreeOverlayScript:
		_check((overlay as TechTreeOverlayScript).segment_row_separation() == 0, "overlay reports zero separation")
	var before: int = overlay._scroll.scroll_horizontal if overlay._scroll != null else 0
	overlay.apply_horizontal_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	var after_down: int = overlay._scroll.scroll_horizontal if overlay._scroll != null else 0
	_check(after_down > before, "wheel down increases scroll_horizontal")
	overlay.apply_horizontal_wheel(MOUSE_BUTTON_WHEEL_UP)
	var after_up: int = overlay._scroll.scroll_horizontal if overlay._scroll != null else 0
	_check(after_up < after_down, "wheel up decreases scroll_horizontal")
	_check(
		TechTreeOverlayScript.horizontal_wheel_delta(MOUSE_BUTTON_WHEEL_DOWN)
			== TechTreeOverlayScript.WHEEL_SCROLL_STEP_PX,
		"wheel down delta step",
	)
	hud.queue_free()


func _test_tech_item_layout() -> void:
	var overlay: TechTreeOverlayScript = TechTreeOverlayScript.new()
	get_root().add_child(overlay)
	for _i in 2:
		await process_frame
	overlay.open_overlay()
	_check(
		overlay._tech_items.size() == TechTreeOverlayScript.tech_item_count(),
		"prototype tech items created for each segment page",
	)
	_check(TechTreeOverlayScript.items_per_segment() == 9, "segment item count is 4 + 2 + 3")
	_check(
		TechTreeOverlayScript.tech_item_count() == 27,
		"three segment pages duplicate the nine-item prototype grid",
	)
	_check(
		TechTreeOverlayScript.prototype_segment_spec_count() == 3,
		"prototype covers all three background segments",
	)
	_check(TechTreeOverlayScript.COLUMN_X_STEP == 390.0, "accepted column x step preserved")
	var viewport_h: float = overlay.get_viewport_rect().size.y
	var content_scale: float = TechTreeOverlayScript.content_scale(viewport_h)
	_check(
		absf(content_scale - TechTreeOverlayScript.TECH_TREE_CONTENT_SCALE_MULTIPLIER) < 0.01,
		"content scale is constant 1.5x for parchment and tech items",
	)
	var expected_seg_h: int = TechTreeOverlayScript.scaled_segment_display_height(viewport_h)
	var expected_ref_seg_h: float = (
		TechTreeOverlayScript.LAYOUT_REFERENCE_VIEWPORT_HEIGHT
		* TechTreeOverlayScript.ROW_HEIGHT_VIEWPORT_FRACTION
		* TechTreeOverlayScript.TECH_TREE_CONTENT_SCALE_MULTIPLIER
	)
	_check(
		absf(float(expected_seg_h) - expected_ref_seg_h) < 1.0,
		"segment height fixed at layout reference viewport, not live resize",
	)
	var first_seg := overlay._segment_row.get_child(0) as TextureRect
	if first_seg != null:
		_check(
			absf(first_seg.size.y - float(expected_seg_h)) < 1.0,
			"segment height uses shared content scale",
		)
	var expected_item: Vector2 = TechTreeOverlayScript.scaled_texture_size(
		overlay._tech_item_tex,
		TechTreeOverlayScript.tech_item_display_height(viewport_h),
	)
	var min_x_seg0: float = INF
	var column_first_item_index: Array[int] = [-1, -1, -1]
	var seg_widths: Array = overlay._segment_display_widths
	var gi: int = 0
	while gi < overlay._tech_items.size():
		var placement: Vector3i = overlay._tech_item_placements[gi]
		var item_segment: int = placement.x
		var item_col: int = placement.y
		var item_row: int = placement.z
		var item_count: int = TechTreeOverlayScript.prototype_column_spec_count(item_col)
		var center_grid: bool = overlay._segment_center_grid_for_index(item_segment)
		var mirror_grid: bool = overlay._segment_mirror_grid_for_index(item_segment)
		var item: TextureRect = overlay._tech_items[gi]
		_check(item != null, "tech item %d exists" % gi)
		_check(item.texture != null, "tech item %d texture loaded" % gi)
		_check(item.get_parent() == overlay._scroll_content, "tech item %d under scroll content" % gi)
		_check(item.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tech item %d ignores mouse" % gi)
		var expected_pos: Vector2 = TechTreeOverlayScript.tech_item_position(
			item_segment,
			item_col,
			item_row,
			seg_widths,
			item_count,
			center_grid,
			mirror_grid,
			viewport_h,
		)
		_check(
			item.position.is_equal_approx(expected_pos),
			"tech item %d at column=%d row=%d" % [gi, item_col, item_row],
		)
		var layout: Array = TechTreeOverlayScript.column_layout(item_count)
		_check(
			absf(item.position.y - float(layout[item_row]) * content_scale) < 0.5,
			"tech item %d uses column layout for count=%d" % [gi, item_count],
		)
		if item_segment == 0 and column_first_item_index[item_col] < 0:
			column_first_item_index[item_col] = gi
		if item_segment == 0:
			min_x_seg0 = minf(min_x_seg0, item.position.x)
		_check(
			absf(item.size.x - expected_item.x) < 1.0 and absf(item.size.y - expected_item.y) < 1.0,
			"tech item %d size from aspect ratio" % gi,
		)
		var icon: TextureRect = item.get_node_or_null("TechIcon") as TextureRect
		_check(icon != null, "tech item %d has icon" % gi)
		if icon != null:
			_check(icon.texture != null, "tech item %d icon texture loaded" % gi)
			_check(icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tech item %d icon ignores mouse" % gi)
			_check(
				absf(icon.size.y - item.size.y * TechTreeOverlayScript.STONE_ICON_HEIGHT_RATIO) < 1.0,
				"tech item %d icon height is one third of item height" % gi,
			)
		var title: Label = item.get_node_or_null("TechTitleLabel") as Label
		_check(title != null, "tech item %d has title label" % gi)
		if title != null:
			_check(title.text == TechTreeOverlayScript.TECH_TITLE_TEXT, "tech item %d title text" % gi)
			_check(title.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tech item %d title ignores mouse" % gi)
		var body: Label = item.get_node_or_null("TechBodyLabel") as Label
		_check(body != null, "tech item %d has body label" % gi)
		if body != null:
			_check(body.text == TechTreeOverlayScript.TECH_BODY_TEXT, "tech item %d body text" % gi)
			_check(body.text.contains("Basic stoneworking"), "tech item %d body has stoneworking line" % gi)
			_check(body.text.contains("Worker enablement"), "tech item %d body has worker line" % gi)
			_check(body.text.contains("Quarry / mine precursor"), "tech item %d body has quarry line" % gi)
			_check(
				body.text.contains("Production from hills & stone"),
				"tech item %d body has production line" % gi,
			)
			_check(body.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tech item %d body ignores mouse" % gi)
		gi += 1
	_check(TechTreeOverlayScript.prototype_column_spec_count(0) == 4, "column 1 has four items")
	_check(TechTreeOverlayScript.prototype_column_spec_count(1) == 2, "column 2 has two items")
	_check(TechTreeOverlayScript.prototype_column_spec_count(2) == 3, "column 3 has three items")
	var col0_row: int = 0
	while col0_row < TechTreeOverlayScript.COLUMN_LAYOUT_4.size():
		_check(
			absf(
				overlay._tech_items[col0_row].position.y
					- TechTreeOverlayScript.COLUMN_LAYOUT_4[col0_row] * content_scale
			) < 0.5,
			"column 1 row %d uses COLUMN_LAYOUT_4" % col0_row,
		)
		col0_row += 1
	var layout_2: Array = TechTreeOverlayScript.column_layout(2)
	var layout_3: Array = TechTreeOverlayScript.column_layout(3)
	var y0: float = TechTreeOverlayScript.COLUMN_LAYOUT_4[0]
	var y1: float = TechTreeOverlayScript.COLUMN_LAYOUT_4[1]
	var y2: float = TechTreeOverlayScript.COLUMN_LAYOUT_4[2]
	var y3: float = TechTreeOverlayScript.COLUMN_LAYOUT_4[3]
	_check(absf(float(layout_2[0]) - (y0 + y1) * 0.5) < 0.5, "2-item first y midway between y0 and y1")
	_check(absf(float(layout_2[1]) - (y2 + y3) * 0.5) < 0.5, "2-item second y midway between y2 and y3")
	_check(
		absf(float(layout_3[0]) - (y0 + float(layout_2[0])) * 0.5) < 0.5,
		"3-item first y between y0 and 2-item first y",
	)
	_check(absf(float(layout_3[1]) - (y0 + y3) * 0.5) < 0.5, "3-item second y at span center")
	_check(
		absf(float(layout_3[2]) - (float(layout_2[1]) + y3) * 0.5) < 0.5,
		"3-item third y between 2-item second y and y3",
	)
	var col1_row: int = 0
	while col1_row < layout_2.size():
		var col1_item: TextureRect = overlay._tech_items[4 + col1_row]
		_check(
			absf(
				col1_item.position.y - float(layout_2[col1_row]) * content_scale
			) < 0.5,
			"column 2 row %d uses derived 2-item layout" % col1_row,
		)
		col1_row += 1
	var col2_row: int = 0
	while col2_row < layout_3.size():
		var col2_item: TextureRect = overlay._tech_items[6 + col2_row]
		_check(
			absf(
				col2_item.position.y - float(layout_3[col2_row]) * content_scale
			) < 0.5,
			"column 3 row %d uses derived 3-item layout" % col2_row,
		)
		col2_row += 1
	var base_left_x: float = TechTreeOverlayScript.tech_item_base_position(
		0, 0, 0, seg_widths, false, viewport_h,
	).x
	_check(
		min_x_seg0
			>= base_left_x + TechTreeOverlayScript.TECH_ITEM_GROUP_OFFSET.x * content_scale - 0.5,
		"segment 1 tech items shifted right by group offset",
	)
	_check(
		min_x_seg0 > base_left_x + 50.0 * content_scale,
		"segment 1 tech items moved right away from old left edge",
	)
	if seg_widths.size() >= 2:
		var seg1_left: float = float(seg_widths[0])
		var seg1_right: float = seg1_left + float(seg_widths[1])
		var seg1_grid_w: float = TechTreeOverlayScript.grid_content_width_scaled(viewport_h)
		var seg1_center_offset: float = maxf((float(seg_widths[1]) - seg1_grid_w) * 0.5, 0.0)
		var seg1_item0: TextureRect = overlay._tech_items[9]
		var seg1_col2_item: TextureRect = overlay._tech_items[15]
		var seg1_grid_left: float = seg1_item0.position.x
		var seg1_grid_right: float = seg1_col2_item.position.x + seg1_col2_item.size.x
		_check(
			absf(
				seg1_grid_left
					- (
						seg1_left
						+ seg1_center_offset
					)
			) < 1.5,
			"segment 2 grid left edge is centered on background 2",
		)
		_check(
			seg1_grid_left >= seg1_left - 0.5,
			"segment 2 items start inside background 2",
		)
		_check(
			seg1_grid_right <= seg1_right + 1.0,
			"segment 2 grid fits inside background 2 width",
		)
		var seg1_grid_mid: float = (seg1_grid_left + seg1_grid_right) * 0.5
		var seg1_page_mid: float = (seg1_left + seg1_right) * 0.5
		_check(
			absf(seg1_grid_mid - seg1_page_mid) < 2.0,
			"segment 2 grid is centered on background 2",
		)
	if seg_widths.size() >= 3:
		var seg2_left: float = float(seg_widths[0]) + float(seg_widths[1])
		var seg2_right: float = seg2_left + float(seg_widths[2])
		var seg2_design_w: float = TechTreeOverlayScript.segment_design_width_from_display(
			float(seg_widths[2]),
			viewport_h,
		)
		var seg2_col0: TextureRect = overlay._tech_items[18]
		var seg2_col2: TextureRect = overlay._tech_items[24]
		var mirror_inset: float = TechTreeOverlayScript.mirror_right_inset_design_for_segment(2)
		var reduce_frac: float = TechTreeOverlayScript.mirror_left_margin_reduce_fraction_for_segment(
			2,
		)
		var seg2_local_col0: Vector2 = TechTreeOverlayScript.segment_local_grid_position_resolved(
			0,
			0,
			2,
			seg_widths,
			true,
			4,
			viewport_h,
		)
		_check(
			absf(
				seg2_col0.position.x
					- (
						seg2_left
						+ seg2_local_col0.x * content_scale
					)
			) < 1.5,
			"segment 3 col 0 uses tuned mirrored grid position",
		)
		_check(
			seg2_col0.position.x > seg2_col2.position.x,
			"segment 3 mirrors column order horizontally",
		)
		_check(
			seg2_col0.position.x >= seg2_left - 0.5,
			"segment 3 mirrored grid stays inside background 3",
		)
		_check(
			seg2_col2.position.x + seg2_col2.size.x <= seg2_right + 1.0,
			"segment 3 mirrored grid right edge stays inside background 3",
		)
		_check(mirror_inset > 0.0, "segment 3 mirror uses right-border inset")
		_check(
			absf(reduce_frac - 1.0 / 3.0) < 0.001,
			"segment 3 reduces mirrored left-column margin by one third",
		)
		var left_col: int = TechTreeOverlayScript.leftmost_mirrored_column_index()
		var pure_left_local: Vector2 = TechTreeOverlayScript.mirror_local_grid_position(
			TechTreeOverlayScript.segment_local_grid_position(left_col, 0),
			seg2_design_w,
			mirror_inset,
		)
		var pure_left_margin_scaled: float = pure_left_local.x * content_scale
		var actual_left_margin: float = seg2_col2.position.x - seg2_left
		_check(
			absf(actual_left_margin - pure_left_margin_scaled * (1.0 - reduce_frac)) < 2.0,
			"segment 3 left-column margin is one-third smaller than pure mirror",
		)
		var sym_shift: float = TechTreeOverlayScript.grid_x_offset_design_for_segment(
			0,
			seg_widths,
			viewport_h,
		)
		_check(sym_shift > 0.0, "segment 1 shifts right using symmetric mirror tune from segment 3")
		_check(
			absf(sym_shift - TechTreeOverlayScript.mirror_left_margin_shift_design(
				seg2_design_w,
				mirror_inset,
				reduce_frac,
			)) < 0.01,
			"segment 1 shift matches segment 3 mirror left-margin reduction",
		)
		var seg0_unshifted_margin: float = (
			TechTreeOverlayScript.segment_local_grid_position(0, 0).x * content_scale
		)
		var seg0_left_margin: float = overlay._tech_items[0].position.x
		_check(
			absf(seg0_left_margin - seg0_unshifted_margin - sym_shift * content_scale) < 2.0,
			"segment 1 grid shifts right by symmetric mirror-tune amount",
		)
	var col: int = 0
	while col < TechTreeOverlayScript.TECH_COLUMN_COUNT - 1:
		var left_item: TextureRect = overlay._tech_items[column_first_item_index[col]]
		var right_item: TextureRect = overlay._tech_items[column_first_item_index[col + 1]]
		var h_gap: float = right_item.position.x - (left_item.position.x + left_item.size.x)
		_check(h_gap > 1.0, "positive horizontal gap between column %d and %d" % [col, col + 1])
		_check(
			absf(
				right_item.position.x
					- left_item.position.x
					- TechTreeOverlayScript.COLUMN_X_STEP * content_scale
			) < 1.0,
			"column step preserved between column %d and %d" % [col, col + 1],
		)
		col += 1
	var row: int = 0
	while row < TechTreeOverlayScript.COLUMN_LAYOUT_4.size() - 1:
		var top_item: TextureRect = overlay._tech_items[row]
		var bottom_item: TextureRect = overlay._tech_items[row + 1]
		var v_gap: float = bottom_item.position.y - (top_item.position.y + top_item.size.y)
		_check(v_gap > 1.0, "positive vertical gap between row %d and %d in column 1" % [row, row + 1])
		_check(
			absf(
				bottom_item.position.y
					- top_item.position.y
					- (
						TechTreeOverlayScript.COLUMN_LAYOUT_4[1]
						- TechTreeOverlayScript.COLUMN_LAYOUT_4[0]
					) * content_scale
			) < 1.0,
			"4-item row step preserved between row %d and %d" % [row, row + 1],
		)
		row += 1
	overlay.queue_free()


func _collect_hbox_segment_row(node: Node, out: Array) -> void:
	if node is HBoxContainer and _has_scroll_container_ancestor(node):
		out.append(node)
	var i: int = 0
	while i < node.get_child_count():
		_collect_hbox_segment_row(node.get_child(i), out)
		i += 1


func _has_scroll_container_ancestor(node: Node) -> bool:
	var p: Node = node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
