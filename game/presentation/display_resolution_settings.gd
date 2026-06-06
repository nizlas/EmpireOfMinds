# Presentation-only display mode: 4K dev window vs smaller Full HD window.
# Design viewport stays 3200x1920 (project.godot); window stretch scales UI uniformly.
class_name DisplayResolutionSettings
extends RefCounted

const SETTINGS_VERSION: int = 1
const DEFAULT_SETTINGS_PATH: String = "user://display_resolution.json"
const MODE_DEV_4K: String = "dev_4k"
const MODE_FULL_HD: String = "full_hd"
const DESIGN_VIEWPORT: Vector2i = Vector2i(3200, 1920)
const DEV_4K_WINDOW: Vector2i = Vector2i(3200, 1920)
const FULL_HD_WINDOW: Vector2i = Vector2i(1920, 1152)


static func default_mode() -> String:
	return MODE_DEV_4K


static func normalize_mode(raw: String) -> String:
	var mode: String = str(raw).strip_edges()
	if mode == MODE_FULL_HD:
		return MODE_FULL_HD
	return MODE_DEV_4K


static func toggle_mode(mode: String) -> String:
	return MODE_FULL_HD if normalize_mode(mode) == MODE_DEV_4K else MODE_DEV_4K


static func window_size_for_mode(mode: String) -> Vector2i:
	if normalize_mode(mode) == MODE_FULL_HD:
		return FULL_HD_WINDOW
	return DEV_4K_WINDOW


static func is_embedded_in_editor() -> bool:
	return Engine.is_embedded_in_editor()


static func content_scale_factor_for_mode(mode: String, embedded_in_editor: bool) -> float:
	if not embedded_in_editor:
		return 1.0
	var size: Vector2i = window_size_for_mode(mode)
	return float(size.x) / float(DESIGN_VIEWPORT.x)


static func mode_menu_button_text(mode: String) -> String:
	if normalize_mode(mode) == MODE_FULL_HD:
		return "Display: Full HD (%d×%d) — click for 4K Dev" % [
			FULL_HD_WINDOW.x,
			FULL_HD_WINDOW.y,
		]
	return "Display: 4K Dev (%d×%d) — click for Full HD" % [
		DEV_4K_WINDOW.x,
		DEV_4K_WINDOW.y,
	]


static func apply_status_message(mode: String, embedded_in_editor: bool) -> String:
	var size: Vector2i = window_size_for_mode(mode)
	if embedded_in_editor:
		return (
			(
				"Display: %s (preview scale in embedded editor). "
				+ "For real window resize, run standalone (F5 with embed off) or export."
			)
			% mode_label(mode)
		)
	return "Display: %s — window %d×%d." % [mode_label(mode), size.x, size.y]


static func mode_label(mode: String) -> String:
	if normalize_mode(mode) == MODE_FULL_HD:
		return "Full HD"
	return "4K Dev"


static func empty_settings() -> Dictionary:
	return {"version": SETTINGS_VERSION, "mode": default_mode()}


static func load_settings(path: String = DEFAULT_SETTINGS_PATH) -> Dictionary:
	var p: String = str(path).strip_edges()
	if p.is_empty():
		p = DEFAULT_SETTINGS_PATH
	if not FileAccess.file_exists(p):
		return empty_settings()
	var txt: String = FileAccess.get_file_as_string(p)
	if txt.is_empty():
		return empty_settings()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return empty_settings()
	var data = j.data
	if typeof(data) != TYPE_DICTIONARY:
		return empty_settings()
	return {
		"version": int(data.get("version", SETTINGS_VERSION)),
		"mode": normalize_mode(str(data.get("mode", default_mode()))),
	}


static func save_settings(mode: String, path: String = DEFAULT_SETTINGS_PATH) -> void:
	var p: String = str(path).strip_edges()
	if p.is_empty():
		p = DEFAULT_SETTINGS_PATH
	var payload: Dictionary = {
		"version": SETTINGS_VERSION,
		"mode": normalize_mode(mode),
	}
	var file := FileAccess.open(p, FileAccess.WRITE)
	if file == null:
		push_warning("DisplayResolutionSettings: could not write %s" % p)
		return
	file.store_string(JSON.stringify(payload, "\t"))


static func load_saved_mode(path: String = DEFAULT_SETTINGS_PATH) -> String:
	return normalize_mode(str(load_settings(path).get("mode", default_mode())))


static func should_apply_window_size() -> bool:
	return DisplayServer.get_name() != "headless"


static func apply_mode_to_window(mode: String, window: Window) -> Dictionary:
	var normalized: String = normalize_mode(mode)
	var result: Dictionary = {
		"mode": normalized,
		"embedded": false,
		"applied": false,
		"window_size": window_size_for_mode(normalized),
	}
	if not should_apply_window_size() or window == null:
		return result
	var embedded: bool = is_embedded_in_editor()
	result["embedded"] = embedded
	result["applied"] = true
	window.content_scale_factor = content_scale_factor_for_mode(normalized, embedded)
	if embedded:
		return result
	var size: Vector2i = window_size_for_mode(normalized)
	var wid: int = window.get_window_id()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, wid)
	DisplayServer.window_set_size(size, wid)
	window.set_deferred("size", size)
	var screen_idx: int = DisplayServer.window_get_current_screen()
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_idx)
	var pos: Vector2i = Vector2i(
		maxi((screen_size.x - size.x) / 2, 0),
		maxi((screen_size.y - size.y) / 2, 0),
	)
	DisplayServer.window_set_position(pos, screen_idx)
	return result


static func bootstrap_at_start(window: Window, path: String = DEFAULT_SETTINGS_PATH) -> String:
	var mode: String = load_saved_mode(path)
	apply_mode_to_window(mode, window)
	return mode


static func save_and_apply_mode(
	mode: String,
	window: Window,
	path: String = DEFAULT_SETTINGS_PATH,
) -> Dictionary:
	var normalized: String = normalize_mode(mode)
	save_settings(normalized, path)
	return apply_mode_to_window(normalized, window)
