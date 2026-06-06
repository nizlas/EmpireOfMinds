# Headless: display mode persistence and window size mapping.
extends SceneTree

const DisplaySettingsScript = preload("res://presentation/display_resolution_settings.gd")

const TEST_PATH: String = "user://test_eom_display_resolution.json"

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_mode_helpers()
	_test_save_load_roundtrip()
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


func _test_mode_helpers() -> void:
	_check(
		DisplaySettingsScript.default_mode() == DisplaySettingsScript.MODE_DEV_4K,
		"default mode is 4K dev",
	)
	_check(
		DisplaySettingsScript.normalize_mode("full_hd") == DisplaySettingsScript.MODE_FULL_HD,
		"normalize full hd",
	)
	_check(
		DisplaySettingsScript.normalize_mode("bogus") == DisplaySettingsScript.MODE_DEV_4K,
		"unknown mode falls back to 4K dev",
	)
	_check(
		DisplaySettingsScript.toggle_mode(DisplaySettingsScript.MODE_DEV_4K)
			== DisplaySettingsScript.MODE_FULL_HD,
		"toggle from 4K dev",
	)
	_check(
		DisplaySettingsScript.toggle_mode(DisplaySettingsScript.MODE_FULL_HD)
			== DisplaySettingsScript.MODE_DEV_4K,
		"toggle from full hd",
	)
	_check(
		DisplaySettingsScript.window_size_for_mode(DisplaySettingsScript.MODE_DEV_4K)
			== DisplaySettingsScript.DEV_4K_WINDOW,
		"4K dev window size",
	)
	_check(
		DisplaySettingsScript.window_size_for_mode(DisplaySettingsScript.MODE_FULL_HD)
			== DisplaySettingsScript.FULL_HD_WINDOW,
		"full hd window size",
	)
	_check(
		DisplaySettingsScript.DESIGN_VIEWPORT == Vector2i(3200, 1920),
		"design viewport documents 4K dev baseline",
	)
	_check(
		DisplaySettingsScript.FULL_HD_WINDOW.x
			== int(round(float(DisplaySettingsScript.DESIGN_VIEWPORT.x) * 0.6)),
		"full hd width is 60 percent of design width",
	)
	_check(
		DisplaySettingsScript.mode_menu_button_text(DisplaySettingsScript.MODE_DEV_4K).contains(
			"4K Dev"
		),
		"menu label mentions 4K dev",
	)
	_check(
		DisplaySettingsScript.mode_menu_button_text(DisplaySettingsScript.MODE_FULL_HD).contains(
			"Full HD"
		),
		"menu label mentions full hd",
	)
	_check(
		absf(
			DisplaySettingsScript.content_scale_factor_for_mode(
				DisplaySettingsScript.MODE_FULL_HD,
				true,
			)
			- 0.6
		) < 0.001,
		"embedded full hd uses 60 percent preview scale",
	)
	_check(
		DisplaySettingsScript.content_scale_factor_for_mode(
			DisplaySettingsScript.MODE_DEV_4K,
			false,
		) == 1.0,
		"standalone window keeps unity content scale factor",
	)
	_check(
		DisplaySettingsScript.apply_status_message(
			DisplaySettingsScript.MODE_FULL_HD,
			true,
		).contains("embedded editor"),
		"embedded status message explains editor preview",
	)


func _test_save_load_roundtrip() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	DisplaySettingsScript.save_settings(DisplaySettingsScript.MODE_FULL_HD, TEST_PATH)
	var loaded: Dictionary = DisplaySettingsScript.load_settings(TEST_PATH)
	_check(
		str(loaded.get("mode", "")) == DisplaySettingsScript.MODE_FULL_HD,
		"saved full hd mode loads back",
	)
	DisplaySettingsScript.save_settings("invalid-mode", TEST_PATH)
	loaded = DisplaySettingsScript.load_settings(TEST_PATH)
	_check(
		str(loaded.get("mode", "")) == DisplaySettingsScript.MODE_DEV_4K,
		"invalid saved mode normalizes to 4K dev",
	)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
