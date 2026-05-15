# Headless: godot --headless --path game -s res://presentation/tests/test_main_hud_city_panel.gd
extends SceneTree

var _total = 0
var _any_fail = false


func _init() -> void:
	var packed = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var root = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas node exists")
	_check(hud is CanvasLayer, "HudCanvas is CanvasLayer")
	_check((hud as CanvasLayer).layer >= 10, "HudCanvas uses a raised layer for HUD input order")
	var panel = hud.get_node_or_null("CityProductionPanel")
	_check(panel != null, "CityProductionPanel parented under HudCanvas")
	var ctl = panel as Control
	_check(ctl != null, "CityProductionPanel is Control")
	_check(is_equal_approx(ctl.anchor_left, 1.0), "panel anchor_left pins to right")
	_check(is_equal_approx(ctl.anchor_right, 1.0), "panel anchor_right pins to right")
	_check(is_equal_approx(ctl.anchor_top, 1.0), "panel anchor_top pins to bottom band (city hub)")
	_check(is_equal_approx(ctl.anchor_bottom, 1.0), "panel anchor_bottom pins to bottom band (city hub)")
	_check(ctl.offset_right > ctl.offset_left, "panel has positive width (margins from right edge)")
	var turn_status = hud.get_node_or_null("TurnStatusPanel")
	_check(turn_status != null, "TurnStatusPanel parented under HudCanvas")
	var ts_ctl = turn_status as Control
	_check(ts_ctl != null, "TurnStatusPanel is Control")
	_check(ts_ctl.visible, "TurnStatusPanel visible by default")
	_check(is_equal_approx(ts_ctl.anchor_left, 1.0), "turn status anchor_left pins to right")
	_check(is_equal_approx(ts_ctl.anchor_right, 1.0), "turn status anchor_right pins to right")
	_check(is_equal_approx(ts_ctl.anchor_top, 1.0), "turn status anchor_top pins to bottom band")
	_check(is_equal_approx(ts_ctl.anchor_bottom, 1.0), "turn status anchor_bottom pins to bottom band")
	_check(ts_ctl.offset_bottom <= ctl.offset_top, "turn status sits above city hub (no overlap)")
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
