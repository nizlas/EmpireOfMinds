# Headless: godot --headless --path game -s res://presentation/tests/test_main_hud_discovery_action_panel.gd
extends SceneTree

const LTScript = preload("res://presentation/lightning_tree_view.gd")
const DPScript = preload("res://presentation/discovery_action_panel.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var packed = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var root = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas")
	var disc = hud.get_node_or_null("DiscoveryActionPanel")
	_check(disc != null, "DiscoveryActionPanel under HudCanvas")
	var dctl = disc as Control
	_check(dctl != null, "DiscoveryActionPanel is Control")
	_check(disc is PanelContainer, "DiscoveryActionPanel is PanelContainer")
	_check(disc.get_script() == DPScript, "DiscoveryActionPanel script")
	_check(not disc.visible, "starts hidden")

	var lt = root.get_node_or_null("LightningTreeView")
	_check(lt != null, "LightningTreeView under Main")
	_check(lt is Node2D, "LightningTreeView is Node2D")
	_check(lt.get_script() == LTScript, "LightningTreeView script")

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
