# Headless: tech-tree preview overlay wiring + segment paths.
extends SceneTree

const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")
const NodeLayoutScript = preload("res://presentation/tech_tree_node_layout.gd")

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
	_test_scaled_texture_imports_use_mipmaps()
	_check(ResourceLoader.exists(TechTreeOverlayScript.TECH_ITEM_PATH), "tech_item exists")
	_check(ResourceLoader.exists(TechTreeOverlayScript.STONE_TOOLS_PATH), "stone_tools exists")
	_check(load(TechTreeOverlayScript.TECH_ITEM_PATH) is Texture2D, "tech_item loads as texture")
	_check(load(TechTreeOverlayScript.STONE_TOOLS_PATH) is Texture2D, "stone_tools loads as texture")
	var icon_paths: Array[String] = ContentScript.all_icon_paths()
	var i: int = 0
	while i < icon_paths.size():
		var path: String = icon_paths[i]
		_check(ResourceLoader.exists(path), "prototype icon exists: %s" % path)
		_check(load(path) is Texture2D, "prototype icon loads as texture: %s" % path)
		i += 1


func _test_scaled_texture_imports_use_mipmaps() -> void:
	var paths: Array[String] = [
		TechTreeOverlayScript.TECH_ITEM_PATH + ".import",
	]
	var i: int = 0
	while i < TechTreeOverlayScript.SEGMENT_PATHS.size():
		paths.append(TechTreeOverlayScript.SEGMENT_PATHS[i] + ".import")
		i += 1
	var pi: int = 0
	while pi < paths.size():
		var import_path: String = paths[pi]
		_check(FileAccess.file_exists(import_path), "import exists: %s" % import_path)
		if FileAccess.file_exists(import_path):
			var text: String = FileAccess.get_file_as_string(import_path)
			_check(
				text.contains("mipmaps/generate=true"),
				"import mipmaps enabled: %s" % import_path,
			)
		pi += 1


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
		"prototype tech items created for canonical grid",
	)
	_check(TechTreeOverlayScript.items_per_segment(0) == 11, "segment 1 spans columns 1-3")
	_check(TechTreeOverlayScript.items_per_segment(1) == 6, "segment 2 spans columns 4-6")
	_check(TechTreeOverlayScript.items_per_segment(2) == 4, "segment 3 spans columns 7-9")
	_check(TechTreeOverlayScript.tech_item_count() == 21, "prototype tree renders twenty-one tech items")
	_check(
		TechTreeOverlayScript.prototype_segment_spec_count() == 3,
		"prototype covers all three background segments",
	)
	_check(NodeLayoutScript.edge_references_valid_titles(), "dependency edges reference layout nodes")
	_check(ContentScript.exoplanet_placement() == Vector3i(9, 2, 0), "Exoplanet Expedition at C9,R2")
	var viewport_h: float = overlay.get_viewport_rect().size.y
	var content_scale: float = TechTreeOverlayScript.content_scale(viewport_h)
	_check(
		absf(content_scale - TechTreeOverlayScript.TECH_TREE_CONTENT_SCALE_MULTIPLIER) < 0.01,
		"content scale is constant 1.5x for parchment and tech items",
	)
	_check(overlay._dependency_lines != null, "dependency line layer exists")
	if overlay._dependency_lines != null:
		_check(
			overlay._dependency_lines.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"dependency lines ignore mouse",
		)
		_check(
			overlay._dependency_lines.get_index() < overlay._tech_items[0].get_index(),
			"dependency lines sit behind tech item cards",
		)
		_check(overlay._dependency_lines.polylines.size() > 0, "dependency polylines built on layout")
	var seg_widths: Array = overlay._segment_display_widths
	var seen_titles: Dictionary = {}
	var gi: int = 0
	while gi < overlay._tech_items.size():
		var placement: Vector3i = overlay._tech_item_placements[gi]
		var column: int = placement.x
		var row: int = placement.y
		var item: TextureRect = overlay._tech_items[gi]
		_check(item != null, "tech item %d exists" % gi)
		_check(item.get_parent() == overlay._scroll_content, "tech item %d under scroll content" % gi)
		_check(item.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tech item %d ignores mouse" % gi)
		_check(item.z_index == 2, "tech item %d renders above dependency lines" % gi)
		var expected_pos: Vector2 = TechTreeOverlayScript.tech_item_position_for_grid_node(
			column,
			row,
			seg_widths,
			viewport_h,
		)
		_check(
			item.position.is_equal_approx(expected_pos),
			"tech item %d at column=%d row=%d" % [gi, column, row],
		)
		var layout: Dictionary = NodeLayoutScript.layout_for_title(
			str(ContentScript.tech_by_id(overlay._tech_item_ids[gi]).get("title", ""))
		)
		_check(int(layout.get("column", -1)) == column, "placement column matches layout for item %d" % gi)
		_check(int(layout.get("row", -1)) == row, "placement row matches layout for item %d" % gi)
		var expected_content: Dictionary = ContentScript.content_for_grid(column, row)
		var title_label: Label = item.get_node_or_null("TechTitleLabel") as Label
		_check(title_label != null, "tech item %d has title label" % gi)
		if title_label != null:
			var title_text: String = title_label.text
			_check(title_text == str(expected_content.get("title", "")), "tech item %d title text" % gi)
			_check(not seen_titles.has(title_text), "unique rendered title: %s" % title_text)
			seen_titles[title_text] = true
			_check(
				NodeLayoutScript.NODE_LAYOUT_BY_TITLE.has(title_text),
				"rendered title in canonical layout: %s" % title_text,
			)
		var body: Label = item.get_node_or_null("TechBodyLabel") as Label
		if body != null:
			_check(
				body.text == ContentScript.body_text_from_content(expected_content),
				"tech item %d body text" % gi,
			)
		var icon: TextureRect = item.get_node_or_null("TechIcon") as TextureRect
		if icon != null:
			var expected_icon: Texture2D = load(str(expected_content["icon_path"])) as Texture2D
			_check(icon.texture == expected_icon, "tech item %d icon matches content path" % gi)
		gi += 1
	_check(seen_titles.size() == 21, "no duplicate tech items rendered")
	var layout_titles: Array = NodeLayoutScript.NODE_LAYOUT_BY_TITLE.keys()
	var ti: int = 0
	while ti < layout_titles.size():
		var layout_title: String = str(layout_titles[ti])
		var node_layout: Dictionary = NodeLayoutScript.layout_for_title(layout_title)
		var placement: Vector3i = Vector3i(
			int(node_layout["column"]),
			int(node_layout["row"]),
			0,
		)
		_check(
			_tech_item_at_placement(overlay, placement) != null,
			"canonical node rendered: %s" % layout_title,
		)
		ti += 1
	var stone_item: TextureRect = _tech_item_at_placement(overlay, ContentScript.stone_tools_placement())
	_check(stone_item != null, "Stone Tools at C1,R3")
	var exo_content: Dictionary = ContentScript.tech_by_id(ContentScript.EXOPLANET_EXPEDITION_ID)
	_check(bool(exo_content.get("end_science", false)), "exoplanet marked end_science")
	var exo_item: TextureRect = _tech_item_at_placement(overlay, ContentScript.exoplanet_placement())
	_check(exo_item != null, "Exoplanet Expedition renders at C9,R2")
	var col1_items: Array[TextureRect] = []
	var c1: int = 1
	while c1 <= 4:
		var c1_item: TextureRect = _tech_item_at_placement(overlay, Vector3i(1, c1, 0))
		if c1_item != null:
			col1_items.append(c1_item)
		c1 += 1
	var row_i: int = 0
	while row_i < col1_items.size() - 1:
		var top_item: TextureRect = col1_items[row_i]
		var bottom_item: TextureRect = col1_items[row_i + 1]
		_check(
			absf(
				bottom_item.position.y
					- top_item.position.y
					- (
						TechTreeOverlayScript.COLUMN_LAYOUT_4[1]
						- TechTreeOverlayScript.COLUMN_LAYOUT_4[0]
					) * content_scale
			) < 1.0,
			"column 1 row step preserved between row %d and %d" % [row_i + 1, row_i + 2],
		)
		row_i += 1
	overlay.queue_free()


func _tech_item_at_placement(overlay: TechTreeOverlayScript, placement: Vector3i) -> TextureRect:
	var i: int = 0
	while i < overlay._tech_item_placements.size():
		if overlay._tech_item_placements[i] == placement:
			return overlay._tech_items[i]
		i += 1
	return null


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
