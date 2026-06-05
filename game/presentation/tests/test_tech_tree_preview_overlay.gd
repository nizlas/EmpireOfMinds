# Headless: tech-tree preview overlay wiring + segment paths.
extends SceneTree

const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_segment_paths_exist()
	_test_main_scene_wiring()
	await _test_overlay_open_close()
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


func _collect_hbox_segment_row(node: Node, out: Array) -> void:
	if node is HBoxContainer and node.get_parent() is ScrollContainer:
		out.append(node)
	var i: int = 0
	while i < node.get_child_count():
		_collect_hbox_segment_row(node.get_child(i), out)
		i += 1
