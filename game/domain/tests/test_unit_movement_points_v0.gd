# Headless: Phase **5.2.5** — per-turn movement points (flat cost **1**).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	_check(MoveUnitScript.MOVEMENT_COST_PER_STEP == 1, "flat movement cost constant")
	var gs = GameStateScript.make_tiny_test_state()
	var u1a = gs.scenario.unit_by_id(1)
	var u2a = gs.scenario.unit_by_id(2)
	_check(
		u1a.max_movement == 2 and u1a.remaining_movement == 2,
		"settler starts full MP",
	)
	_check(
		u2a.max_movement == 2 and u2a.remaining_movement == 2,
		"warrior starts full MP",
	)
	_check(
		gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))["accepted"],
		"first move accepted",
	)
	_check(gs.scenario.unit_by_id(1).remaining_movement == 1, "MP after one step")
	_check(
		gs.try_apply(MoveUnitScript.make(0, 1, 1, -1, 0, 0))["accepted"],
		"second move accepted",
	)
	_check(gs.scenario.unit_by_id(1).remaining_movement == 0, "MP zero")
	var bad = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(not bad["accepted"] and bad["reason"] == "movement_exhausted", "third move rejected")
	var dests_exhausted = MovementRulesScript.legal_destinations(gs.scenario, 1)
	_check(dests_exhausted.size() == 0, "no legal move destinations for exhausted unit 1")
	var dests_warrior = MovementRulesScript.legal_destinations(gs.scenario, 2)
	_check(dests_warrior.size() >= 1, "warrior still has legal move destinations")
	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "P0 end turn")
	_check(gs.turn_state.current_player_id() == 1, "now P1")
	_check(
		gs.scenario.unit_by_id(1).remaining_movement == 0,
		"P0 settler still exhausted mid-P1 turn",
	)
	_check(
		gs.scenario.unit_by_id(3).remaining_movement == 2,
		"P1 units refreshed at turn start",
	)
	_check(gs.try_apply(EndTurnScript.make(1))["accepted"], "P1 end turn")
	_check(gs.turn_state.current_player_id() == 0, "back to P0")
	_check(
		gs.scenario.unit_by_id(1).remaining_movement == 2,
		"P0 units refreshed after full cycle",
	)
	var vis_n = 0
	for c in gs.scenario.map.coords():
		if gs.visibility_state.is_explored(0, c):
			vis_n += 1
	_check(vis_n >= 1, "visibility state still populated after moves")
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
