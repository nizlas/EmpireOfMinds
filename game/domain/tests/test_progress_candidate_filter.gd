# Headless: godot --headless --path game -s res://domain/tests/test_progress_candidate_filter.gd
extends SceneTree

const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")
const ProgressDetectorScript = preload("res://domain/progress_detector.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total = 0
var _any_fail = false


func _gs_tiny_with_tree(tree: HexCoordScript):
	var base = ScenarioScript.make_tiny_test_scenario()
	var scen = ScenarioScript.new(
		base.map,
		base.units(),
		base.cities(),
		base.peek_next_unit_id(),
		base.peek_next_city_id(),
		tree,
	)
	return GameStateScript.new(scen)


func _actions_array_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var i = 0
	while i < a.size():
		if not _action_dict_equal(a[i] as Dictionary, b[i] as Dictionary):
			return false
		i = i + 1
	return true


func _action_dict_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("schema_version", -1)) == int(b.get("schema_version", -2))
		and str(a.get("action_type", "")) == str(b.get("action_type", ""))
		and int(a.get("actor_id", -999)) == int(b.get("actor_id", -998))
		and str(a.get("progress_id", "")) == str(b.get("progress_id", ""))
	)


func _init() -> void:
	var tree_hex = HexCoordScript.new(1, -1)

	# 1. No tree on scenario
	var gs1 = GameStateScript.make_tiny_test_state()
	_check(ProgressCandidateFilterScript.for_current_player(gs1).size() == 0, "1 empty filter")

	# 2. Tree but no observation; P0 current
	var gs2 = _gs_tiny_with_tree(tree_hex)
	var f2 = ProgressCandidateFilterScript.for_current_player(gs2)
	_check(f2.size() == 0, "2 no move yet -> empty")

	# 3. P0 observes; one candidate
	gs2.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var f3 = ProgressCandidateFilterScript.for_current_player(gs2)
	_check(f3.size() == 1, "3 one for current")
	_check(int((f3[0] as Dictionary)["actor_id"]) == 0, "3 actor 0")
	_check(str((f3[0] as Dictionary)["progress_id"]) == "controlled_fire", "3 progress_id")
	var v3 = CompleteProgressScript.validate(gs2.progress_state, f3[0])
	_check(v3["ok"], "3 validate")

	# 4. P0 observed, EndTurn -> P1 current; filter empty until P1 observes
	var gs4 = _gs_tiny_with_tree(tree_hex)
	gs4.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	gs4.try_apply(EndTurnScript.make(0))
	_check(gs4.turn_state.current_player_id() == 1, "4 P1 current")
	var det4 = ProgressDetectorScript.suggested_complete_progress_actions(gs4)
	_check(det4.size() == 1, "4 detector still one for P0 only")
	_check(int((det4[0] as Dictionary)["actor_id"]) == 0, "4 detector P0")
	var f4 = ProgressCandidateFilterScript.for_current_player(gs4)
	_check(f4.size() == 0, "4 filter empty for P1 until P1 observes")

	# 5. P1 observes — candidate for P1 only (fresh state; P0 must not sit on tree hex)
	var gs5 = _gs_tiny_with_tree(tree_hex)
	_check(gs5.try_apply(EndTurnScript.make(0))["accepted"], "5 end for P1 current")
	_check(gs5.turn_state.current_player_id() == 1, "5 P1 current")
	var m5 = gs5.try_apply(MoveUnitScript.make(1, 3, 0, -1, 1, -1))
	_check(m5["accepted"], "5 P1 onto tree")
	var f5 = ProgressCandidateFilterScript.for_current_player(gs5)
	_check(f5.size() == 1, "5 one for P1")
	_check(int((f5[0] as Dictionary)["actor_id"]) == 1, "5 actor 1")

	# 6. Already completed for current player
	var gs6 = _gs_tiny_with_tree(tree_hex)
	gs6.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	gs6.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	var f6 = ProgressCandidateFilterScript.for_current_player(gs6)
	_check(f6.size() == 0, "6 empty after complete")

	# 7. Defensive null
	_check(ProgressCandidateFilterScript.for_current_player(null).size() == 0, "7 null gs")
	var gs7 = _gs_tiny_with_tree(tree_hex)
	var ts7 = gs7.turn_state
	gs7.turn_state = null
	_check(ProgressCandidateFilterScript.for_current_player(gs7).size() == 0, "7 null turn")
	gs7.turn_state = ts7

	# 8. Idempotency — filter does not mutate game_state
	var gs8 = _gs_tiny_with_tree(tree_hex)
	gs8.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var ps8 = gs8.progress_state
	var log8 = gs8.log.size()
	var ts8 = gs8.turn_state
	var a8 = ProgressCandidateFilterScript.for_current_player(gs8)
	var b8 = ProgressCandidateFilterScript.for_current_player(gs8)
	_check(ps8.equals(gs8.progress_state), "8 progress unchanged")
	_check(gs8.log.size() == log8, "8 log size")
	_check(gs8.turn_state.equals(ts8), "8 turn unchanged")
	_check(_actions_array_equal(a8, b8), "8 same output")

	# 9. Engine noise in log; observation still yields one
	var gs9 = _gs_tiny_with_tree(tree_hex)
	gs9.log.append({"action_type": "production_progress", "result": "accepted"})
	_check(ProgressCandidateFilterScript.for_current_player(gs9).size() == 0, "9 engine only")
	gs9.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	gs9.log.append({"action_type": "unit_produced", "result": "accepted"})
	var f9 = ProgressCandidateFilterScript.for_current_player(gs9)
	_check(f9.size() == 1, "9 one with noise")

	# 10. try_apply first filtered candidate — then filter empty
	var gs10 = _gs_tiny_with_tree(tree_hex)
	gs10.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var c10 = ProgressCandidateFilterScript.for_current_player(gs10)
	_check(c10.size() == 1, "10 one before apply")
	var r10 = gs10.try_apply(c10[0])
	_check(r10["accepted"], "10 try_apply accepted")
	var f10 = ProgressCandidateFilterScript.for_current_player(gs10)
	_check(f10.size() == 0, "10 empty after complete")

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
