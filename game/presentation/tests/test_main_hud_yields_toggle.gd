# Headless: **HudCanvas** **Yields** **CheckButton** + **YieldOverlayToggle** sync with **TileYieldOverlayView**.
# Usage: godot --headless --path game -s res://presentation/tests/test_main_hud_yields_toggle.gd
extends SceneTree

const YieldOverlayToggleScript = preload("res://presentation/yield_overlay_toggle.gd")
const TileYieldOverlayScript = preload("res://presentation/tile_yield_overlay_view.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var packed = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var root = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas exists")
	var yt = hud.get_node_or_null("YieldsToggle")
	_check(yt != null, "YieldsToggle under HudCanvas")
	_check(yt is CheckButton, "YieldsToggle is CheckButton")
	_check(str((yt as CheckButton).text) == "Yields", "Yields label text")
	var overlay = root.get_node_or_null("TileYieldOverlayView")
	_check(overlay != null, "TileYieldOverlayView on Main")
	_check(overlay.get_script() == TileYieldOverlayScript, "TileYieldOverlayView script attached")
	_check(not overlay.visible, "overlay default OFF from scene")

	YieldOverlayToggleScript.toggle_from_keyboard(overlay, yt as CheckButton)
	_check(overlay.visible and (yt as CheckButton).button_pressed, "KEY sync path ON")
	YieldOverlayToggleScript.toggle_from_keyboard(overlay, yt as CheckButton)
	_check(not overlay.visible and not (yt as CheckButton).button_pressed, "KEY sync path OFF")

	var o2 = TileYieldOverlayScript.new()
	var c2 = CheckButton.new()
	o2.visible = false
	c2.button_pressed = false
	YieldOverlayToggleScript.apply_from_button(o2, true)
	_check(o2.visible and not c2.button_pressed, "apply_from_button affects overlay only")
	YieldOverlayToggleScript.apply_from_button(o2, false)
	_check(not o2.visible, "apply_from_button clears overlay")
	o2.free()
	c2.free()

	if root != null:
		root.free()

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
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
