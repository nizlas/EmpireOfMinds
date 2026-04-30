# Headless: godot --headless --path game -s res://domain/tests/test_progress_candidate_filter.gd
extends SceneTree

const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")
const ProgressDetectorScript = preload("res://domain/progress_detector.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total = 0
var _any_fail = false


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
	# 1. Initial tiny state
	var gs1 = GameStateScript.make_tiny_test_state()
	var f1 = ProgressCandidateFilterScript.for_current_player(gs1)
	_check(f1.size() == 0, "1 empty filter")

	# 2. P0 founded, P0 current
	var gs2 = GameStateScript.make_tiny_test_state()
	gs2.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var f2 = ProgressCandidateFilterScript.for_current_player(gs2)
	_check(f2.size() == 1, "2 one for current")
	_check(int((f2[0] as Dictionary)["actor_id"]) == 0, "2 actor 0")
	_check(str((f2[0] as Dictionary)["progress_id"]) == "controlled_fire", "2 progress_id")
	var v2 = CompleteProgressScript.validate(gs2.progress_state, f2[0])
	_check(v2["ok"], "2 validate via try_apply path shape")

	# 3. P0 founded, EndTurn -> P1 current (detector still suggests P0; filter empty)
	var gs3 = GameStateScript.make_tiny_test_state()
	gs3.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs3.try_apply(EndTurnScript.make(0))
	_check(gs3.turn_state.current_player_id() == 1, "3 P1 current")
	var det_list = ProgressDetectorScript.suggested_complete_progress_actions(gs3)
	_check(det_list.size() == 1, "3 detector still one for P0")
	var f3 = ProgressCandidateFilterScript.for_current_player(gs3)
	_check(f3.size() == 0, "3 filter empty for non-current")

	# 4. Both founded, P1 current — one candidate for P1 only
	var gs4 = GameStateScript.make_tiny_test_state()
	gs4.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs4.try_apply(EndTurnScript.make(0))
	gs4.try_apply(FoundCityScript.make(1, 3, 0, -1))
	var f4 = ProgressCandidateFilterScript.for_current_player(gs4)
	_check(f4.size() == 1, "4 one for P1")
	_check(int((f4[0] as Dictionary)["actor_id"]) == 1, "4 actor 1")

	# 5. Already completed for current player
	var gs5 = GameStateScript.make_tiny_test_state()
	gs5.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs5.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	var f5 = ProgressCandidateFilterScript.for_current_player(gs5)
	_check(f5.size() == 0, "5 empty after complete")

	# 6. Defensive null
	_check(ProgressCandidateFilterScript.for_current_player(null).size() == 0, "6 null gs")
	var gs6 = GameStateScript.make_tiny_test_state()
	var ts6 = gs6.turn_state
	gs6.turn_state = null
	_check(ProgressCandidateFilterScript.for_current_player(gs6).size() == 0, "6 null turn")
	gs6.turn_state = ts6

	# 7. Idempotency — filter does not mutate game_state
	var gs7 = GameStateScript.make_tiny_test_state()
	gs7.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var ps7 = gs7.progress_state
	var log7 = gs7.log.size()
	var ts7 = gs7.turn_state
	var a7 = ProgressCandidateFilterScript.for_current_player(gs7)
	var b7 = ProgressCandidateFilterScript.for_current_player(gs7)
	_check(ps7.equals(gs7.progress_state), "7 progress unchanged")
	_check(gs7.log.size() == log7, "7 log size")
	_check(gs7.turn_state.equals(ts7), "7 turn unchanged")
	_check(_actions_array_equal(a7, b7), "7 same output")

	# 8. Engine entries do not add spurious filtered rows; with found still one when current matches
	var gs8 = GameStateScript.make_tiny_test_state()
	gs8.log.append({"action_type": "production_progress", "result": "accepted"})
	var f8a = ProgressCandidateFilterScript.for_current_player(gs8)
	_check(f8a.size() == 0, "8 engine only")
	gs8.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs8.log.append({"action_type": "unit_produced", "result": "accepted"})
	var f8b = ProgressCandidateFilterScript.for_current_player(gs8)
	_check(f8b.size() == 1, "8 one with noise")
	_check(int((f8b[0] as Dictionary)["actor_id"]) == 0, "8 actor 0")

	# 9. try_apply first filtered — then filter empty for current
	var gs9 = GameStateScript.make_tiny_test_state()
	gs9.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var c9 = ProgressCandidateFilterScript.for_current_player(gs9)
	_check(c9.size() == 1, "9 one before apply")
	var r9 = gs9.try_apply(c9[0])
	_check(r9["accepted"], "9 try_apply accepted")
	var f9 = ProgressCandidateFilterScript.for_current_player(gs9)
	_check(f9.size() == 0, "9 empty after complete")

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
