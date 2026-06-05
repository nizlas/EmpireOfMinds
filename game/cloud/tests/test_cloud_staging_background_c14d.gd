# C14d-visual: cloud staging full-screen background texture and layering.
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudStagingScript = preload("res://cloud/cloud_staging.gd")
const STAGING_SCENE: String = "res://cloud/cloud_staging.tscn"

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_script_constants()
	await _test_staging_scene_background_layers()
	_test_staging_controls_still_present()
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


func _test_script_constants() -> void:
	_check(
		CloudStagingScript.STAGING_BACKGROUND_TEXTURE_PATH
			== "res://assets/prototype/ui/backgrounds/staging_background.png",
		"background texture path constant",
	)
	_check(
		ResourceLoader.exists(CloudStagingScript.STAGING_BACKGROUND_TEXTURE_PATH),
		"background texture resource exists",
	)


func _test_staging_scene_background_layers() -> void:
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000",
		"m_bg_test",
		"ht_bg",
		"",
		-1,
		"Bg Test",
	)
	var packed: PackedScene = load(STAGING_SCENE) as PackedScene
	_check(packed != null, "load cloud_staging.tscn")
	if packed == null:
		return
	var staging: Control = packed.instantiate() as Control
	get_root().add_child(staging)
	for _i in 3:
		await process_frame
	var bg: TextureRect = staging.get_node_or_null(
		CloudStagingScript.STAGING_BACKGROUND_NODE_NAME
	) as TextureRect
	_check(bg != null, "StagingBackground node exists")
	if bg == null:
		staging.queue_free()
		return
	_check(bg.texture != null, "background has texture")
	if bg.texture != null:
		_check(
			str(bg.texture.resource_path).ends_with("staging_background.png"),
			"background uses staging_background.png",
		)
	_check(
		bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"background stretch keep-aspect-covered",
	)
	_check(bg.mouse_filter == Control.MOUSE_FILTER_IGNORE, "background ignores mouse")
	_check(bg.anchor_left == 0.0 and bg.anchor_top == 0.0, "background anchor top-left")
	_check(bg.anchor_right == 1.0 and bg.anchor_bottom == 1.0, "background anchor bottom-right")
	_check(
		staging.get_node_or_null("StagingBackgroundDim") == null,
		"no dim overlay on staging background",
	)
	var ui_root: Control = staging.get_node_or_null(CloudStagingScript.STAGING_UI_ROOT_NODE_NAME) as Control
	_check(ui_root != null, "StagingUiRoot exists")
	if ui_root != null and bg != null:
		_check(bg.get_index() < ui_root.get_index(), "background drawn behind ui root")
		var third: float = CloudStagingScript.STAGING_UI_WIDTH_FRACTION
		var col_left: float = (1.0 - third) * 0.5
		var col_right: float = col_left + third
		_check(absf(ui_root.anchor_left - col_left) < 0.001, "ui column centered horizontally")
		_check(absf(ui_root.anchor_right - col_right) < 0.001, "ui column one-third width")
	staging.queue_free()


func _test_staging_controls_still_present() -> void:
	BootIntentScript.set_cloud_staging("http://127.0.0.1:8000", "m_ctrl", "ht_x", "", -1, "Ctrl")
	var staging: Control = (load(STAGING_SCENE) as PackedScene).instantiate() as Control
	get_root().add_child(staging)
	for _i in 3:
		await process_frame
	var back: Button = _find_button_named(staging, "Back")
	_check(back != null, "Back button exists")
	var refresh: Button = _find_button_named(staging, "Refresh")
	_check(refresh != null, "Refresh button exists")
	var claim_count: int = _count_buttons_named(staging, "Claim")
	_check(claim_count >= 2, "at least two Claim buttons for slot cards")
	var ready_count: int = _count_buttons_named(staging, "Ready")
	_check(ready_count >= 2, "at least two Ready buttons")
	staging.queue_free()


func _find_button_named(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	var i: int = 0
	while i < root.get_child_count():
		var found: Button = _find_button_named(root.get_child(i), text)
		if found != null:
			return found
		i += 1
	return null


func _count_buttons_named(root: Node, text: String) -> int:
	var n: int = 0
	if root is Button and (root as Button).text == text:
		n += 1
	var i: int = 0
	while i < root.get_child_count():
		n += _count_buttons_named(root.get_child(i), text)
		i += 1
	return n
