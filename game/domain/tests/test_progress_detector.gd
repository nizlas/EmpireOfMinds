# Headless: godot --headless --path game -s res://domain/tests/test_progress_detector.gd
extends SceneTree

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


func _assert_candidate(c: Dictionary) -> void:
	_check(str(c.get("action_type", "")) == CompleteProgressScript.ACTION_TYPE, "candidate action_type")
	_check(str(c.get("progress_id", "")) == "controlled_fire", "candidate progress_id")
	_check(int(c.get("schema_version", -1)) == CompleteProgressScript.SCHEMA_VERSION, "candidate schema")


func _init() -> void:
	# 1. Initial tiny state
	var gs1 = GameStateScript.make_tiny_test_state()
	var s1 = ProgressDetectorScript.suggested_complete_progress_actions(gs1)
	_check(s1.size() == 0, "1 empty suggestions")

	# 2. After P0 accepted found_city
	var gs2 = GameStateScript.make_tiny_test_state()
	var r_fc = gs2.try_apply(FoundCityScript.make(0, 1, 0, 0))
	_check(r_fc["accepted"], "2 found accepted")
	var s2 = ProgressDetectorScript.suggested_complete_progress_actions(gs2)
	_check(s2.size() == 1, "2 one suggestion")
	_assert_candidate(s2[0] as Dictionary)
	_check(int((s2[0] as Dictionary)["actor_id"]) == 0, "2 actor 0")
	var v2 = CompleteProgressScript.validate(gs2.progress_state, s2[0])
	_check(v2["ok"], "2 validate ok")

	# 3. Already completed controlled_fire for P0
	var gs3 = GameStateScript.make_tiny_test_state()
	gs3.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var r_cp = gs3.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(r_cp["accepted"], "3 complete accepted")
	var s3 = ProgressDetectorScript.suggested_complete_progress_actions(gs3)
	_check(s3.size() == 0, "3 no suggestion after complete")

	# 4. P1 isolation and [0,1] order
	var gs4 = GameStateScript.make_tiny_test_state()
	gs4.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var s4a = ProgressDetectorScript.suggested_complete_progress_actions(gs4)
	_check(s4a.size() == 1, "4a one after P0 only")
	_check(int((s4a[0] as Dictionary)["actor_id"]) == 0, "4a P0 candidate")
	gs4.try_apply(EndTurnScript.make(0))
	var s4b = ProgressDetectorScript.suggested_complete_progress_actions(gs4)
	_check(s4b.size() == 1, "4b still one before P1 found")
	_check(int((s4b[0] as Dictionary)["actor_id"]) == 0, "4b still P0")
	var r_fc1 = gs4.try_apply(FoundCityScript.make(1, 3, 0, -1))
	_check(r_fc1["accepted"], "4 P1 found")
	var s4c = ProgressDetectorScript.suggested_complete_progress_actions(gs4)
	_check(s4c.size() == 2, "4c two candidates")
	_check(int((s4c[0] as Dictionary)["actor_id"]) == 0, "4c order P0")
	_check(int((s4c[1] as Dictionary)["actor_id"]) == 1, "4c order P1")

	# 5. Rejected found_city
	var gs5 = GameStateScript.make_tiny_test_state()
	var prior_sz = gs5.log.size()
	var r_bad = gs5.try_apply(FoundCityScript.make(0, 999, 0, 0))
	_check(not r_bad["accepted"], "5 rejected")
	_check(gs5.log.size() == prior_sz, "5 log unchanged")
	var s5 = ProgressDetectorScript.suggested_complete_progress_actions(gs5)
	_check(s5.size() == 0, "5 no suggestion")

	# 6. Determinism: repeated calls same order
	var gs6 = GameStateScript.make_tiny_test_state()
	gs6.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs6.try_apply(EndTurnScript.make(0))
	gs6.try_apply(FoundCityScript.make(1, 3, 0, -1))
	var s6a = ProgressDetectorScript.suggested_complete_progress_actions(gs6)
	var s6b = ProgressDetectorScript.suggested_complete_progress_actions(gs6)
	_check(_actions_array_equal(s6a, s6b), "6 determinism")

	# 7. Defensive null / bad shells
	_check(ProgressDetectorScript.suggested_complete_progress_actions(null).size() == 0, "7 null gs")
	var gs7 = GameStateScript.make_tiny_test_state()
	var ps_snap7 = gs7.progress_state
	gs7.progress_state = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs7).size() == 0, "7 null progress")
	gs7.progress_state = ps_snap7
	var log_snap7 = gs7.log
	gs7.log = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs7).size() == 0, "7 null log")
	gs7.log = log_snap7
	gs7.turn_state = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs7).size() == 0, "7 null turn")

	# 8. Idempotency / no mutation via detector
	var gs8 = GameStateScript.make_tiny_test_state()
	gs8.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var ps8 = gs8.progress_state
	var log8 = gs8.log.size()
	var ts8 = gs8.turn_state
	var out8a = ProgressDetectorScript.suggested_complete_progress_actions(gs8)
	var out8b = ProgressDetectorScript.suggested_complete_progress_actions(gs8)
	_check(ps8.equals(gs8.progress_state), "8 progress unchanged")
	_check(gs8.log.size() == log8, "8 log size unchanged")
	_check(gs8.turn_state.equals(ts8), "8 turn unchanged")
	_check(_actions_array_equal(out8a, out8b), "8 same output twice")

	# 9. Engine-like log entries ignored / do not add spurious candidates
	var gs9 = GameStateScript.make_tiny_test_state()
	gs9.log.append(
		{"action_type": "production_progress", "result": "accepted"}
	)
	var s9a = ProgressDetectorScript.suggested_complete_progress_actions(gs9)
	_check(s9a.size() == 0, "9 engine only no found")
	gs9.try_apply(FoundCityScript.make(0, 1, 0, 0))
	gs9.log.append({"action_type": "unit_produced", "result": "accepted"})
	var s9b = ProgressDetectorScript.suggested_complete_progress_actions(gs9)
	_check(s9b.size() == 1, "9 one with engine noise")
	_check(int((s9b[0] as Dictionary)["actor_id"]) == 0, "9 still P0")

	# 10. Candidate validates as CompleteProgress (explicit)
	var gs10 = GameStateScript.make_tiny_test_state()
	gs10.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var s10 = ProgressDetectorScript.suggested_complete_progress_actions(gs10)
	_check(s10.size() == 1, "10 one")
	var v10 = CompleteProgressScript.validate(gs10.progress_state, s10[0])
	_check(v10["ok"], "10 validate")

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
