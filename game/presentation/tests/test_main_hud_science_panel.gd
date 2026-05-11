# Headless: godot --headless --path game -s res://presentation/tests/test_main_hud_science_panel.gd
extends SceneTree

const SciencePanelScript = preload("res://presentation/science_panel.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var packed = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var root = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas")
	var sci = hud.get_node_or_null("SciencePanel")
	_check(sci != null, "SciencePanel under HudCanvas")
	var sctl = sci as Control
	_check(sctl != null, "SciencePanel is Control")
	_check(sctl.visible, "starts visible")
	_check(sci.get_script() == SciencePanelScript, "SciencePanel script")
	_check(hud.get_node_or_null("CityProductionPanel") != null, "CityProductionPanel still present")
	_check(hud.get_node_or_null("DiscoveryPopup") != null, "DiscoveryPopup still present")
	_check(hud.get_node_or_null("ScienceCompletedPopup") != null, "ScienceCompletedPopup still present")
	if _any_fail:
		root.free()
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		root.free()
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
