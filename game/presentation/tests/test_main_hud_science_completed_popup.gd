# Headless: godot --headless --path game -s res://presentation/tests/test_main_hud_science_completed_popup.gd
extends SceneTree

const ScienceCompletedPopupScript = preload("res://presentation/science_completed_popup.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var packed = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var root = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas node exists")
	var pop = hud.get_node_or_null("ScienceCompletedPopup")
	_check(pop != null, "ScienceCompletedPopup under HudCanvas")
	var ctl = pop as Control
	_check(ctl != null, "ScienceCompletedPopup is Control")
	_check(ctl.get_script() == ScienceCompletedPopupScript, "ScienceCompletedPopup script resource")
	_check(not ctl.visible, "ScienceCompletedPopup starts hidden in scene")
	if _any_fail:
		if root != null:
			root.free()
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		if root != null:
			root.free()
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
