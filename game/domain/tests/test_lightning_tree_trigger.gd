# Headless: godot --headless --path game -s res://domain/tests/test_lightning_tree_trigger.gd
# Phase 5.1.8a: optional scenario.lightning_tree_hex survives domain Scenario rebuilds.
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var tree = HexCoordScript.new(1, -1)
	var base = ScenarioScript.make_tiny_test_scenario()
	var scen0 = ScenarioScript.new(
		base.map,
		base.units(),
		base.cities(),
		base.peek_next_unit_id(),
		base.peek_next_city_id(),
		tree,
	)
	var gs = GameStateScript.new(scen0)
	_check(
		gs.scenario.lightning_tree_hex != null and gs.scenario.lightning_tree_hex.equals(tree),
		"initial tree",
	)

	_check(gs.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))["accepted"], "move")
	_check(gs.scenario.lightning_tree_hex.equals(tree), "tree after move")

	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found")
	_check(gs.scenario.lightning_tree_hex.equals(tree), "tree after found")

	_check(
		gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR))[
			"accepted"
		],
		"set production",
	)
	_check(gs.scenario.lightning_tree_hex.equals(tree), "tree after set_city_production")

	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end turn")
	_check(gs.scenario.lightning_tree_hex.equals(tree), "tree after end_turn tick/delivery path")

	var proto = ScenarioScript.make_prototype_play_scenario()
	_check(proto.lightning_tree_hex != null, "prototype has tree")
	_check(proto.map.has(proto.lightning_tree_hex), "tree on prototype map")
	_check(proto.lightning_tree_hex.q == 3 and proto.lightning_tree_hex.r == 0, "deterministic prototype coord")

	var m = HexMapScript.make_tiny_test_map()
	var tiny_default = ScenarioScript.new(m, [], [])
	_check(tiny_default.lightning_tree_hex == null, "explicit null tree")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
