# Headless: godot --headless --path game -s res://presentation/tests/test_discovery_action_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const UnitScript = preload("res://domain/unit.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const DiscoveryActionPanelScript = preload("res://presentation/discovery_action_panel.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hidden = DiscoveryActionPanelScript.compute_view_model(null)
	_check(not bool(hidden.get("visible", true)), "null game_state hidden")

	var gs_proto = GameStateScript.new(ScenarioScript.make_prototype_play_scenario())
	var vm0 = DiscoveryActionPanelScript.compute_view_model(gs_proto)
	_check(not bool(vm0.get("visible", true)), "prototype before tree observation hidden")

	var gs_move = _game_state_after_p0_moves_onto_tree()
	var vm1 = DiscoveryActionPanelScript.compute_view_model(gs_move)
	_check(not bool(vm1.get("visible", true)), "controlled_fire filtered after tree observe")

	# Debug CompleteProgress still works; panel stays hidden for controlled_fire-only games
	var ok_c = gs_move.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(ok_c["accepted"], "complete applies")
	var vm2 = DiscoveryActionPanelScript.compute_view_model(gs_move)
	_check(not bool(vm2.get("visible", true)), "after complete hidden")

	var gs_adj = _game_state_after_p0_moves_adjacent_to_tree()
	var vm3 = DiscoveryActionPanelScript.compute_view_model(gs_adj)
	_check(not bool(vm3.get("visible", true)), "adjacent filtered")

	_check(gs_adj.try_apply(EndTurnScript.make(0))["accepted"], "end turn P0")
	var vm_p1 = DiscoveryActionPanelScript.compute_view_model(gs_adj)
	_check(not bool(vm_p1.get("visible", true)), "P1 turn stays hidden")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _game_state_after_p0_moves_onto_tree() -> GameState:
	var m = HexMapScript.make_tiny_test_map()
	var us: Array = [UnitScript.new(2, 0, HexCoordScript.new(0, 0), "warrior")]
	var tree = HexCoordScript.new(1, 0)
	var scen = ScenarioScript.new(m, us, [], -1, -1, tree)
	var gs = GameStateScript.new(scen)
	_check(gs.try_apply(MoveUnitScript.make(0, 2, 0, 0, 1, 0))["accepted"], "move onto tree")
	return gs


func _game_state_after_p0_moves_adjacent_to_tree() -> GameState:
	var m = HexMapScript.make_tiny_test_map()
	var us: Array = [UnitScript.new(2, 0, HexCoordScript.new(0, 0), "warrior")]
	var tree = HexCoordScript.new(1, -1)
	var scen = ScenarioScript.new(m, us, [], -1, -1, tree)
	var gs = GameStateScript.new(scen)
	_check(gs.try_apply(MoveUnitScript.make(0, 2, 0, 0, 1, 0))["accepted"], "move adjacent NE")
	return gs


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
