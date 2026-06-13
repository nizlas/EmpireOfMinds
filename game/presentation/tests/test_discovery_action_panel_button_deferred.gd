# Headless: godot --headless --path game -s res://presentation/tests/test_discovery_action_panel_button_deferred.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const DiscoveryActionPanelScript = preload("res://presentation/discovery_action_panel.gd")

var _total = 0
var _any_fail = false

var _panel
var _gs
var _pop
var _n0: int


class PopupRecorder extends Node:
	var idx: int = -1

	func maybe_show_for_log_index(i: int) -> void:
		idx = i


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var m = ScenarioScript.make_tiny_test_scenario().map
	var us: Array = [UnitScript.new(2, 0, HexCoordScript.new(0, 0), "warrior")]
	var scen = ScenarioScript.new(m, us, [], -1, -1, HexCoordScript.new(1, 0))
	_gs = GameStateScript.new(scen)
	_check(_gs.try_apply(MoveUnitScript.make(0, 2, 0, 0, 1, 0))["accepted"], "setup move")

	_panel = DiscoveryActionPanelScript.new()
	_pop = PopupRecorder.new()
	get_root().add_child(_panel)
	get_root().add_child(_pop)
	_panel.game_state = _gs
	_panel.discovery_popup = _pop
	_panel.refresh()
	_n0 = _gs.log.size()
	_panel._on_complete_pressed()
	_check(_gs.log.size() == _n0, "panel does not apply when controlled_fire is filtered")
	_check(_pop.idx < 0, "no discovery popup from filtered panel")
	call_deferred("_after_idle")


func _after_idle() -> void:
	_check(not _panel.visible, "panel stays non-interactive when hidden")
	_check(
		not bool(DiscoveryActionPanelScript.compute_view_model(_gs).get("visible", true)),
		"view model stays hidden"
	)
	if _panel != null:
		_panel.queue_free()
	if _pop != null:
		_pop.queue_free()
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
