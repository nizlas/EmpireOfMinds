# Headless: godot --headless --path game -s res://domain/tests/test_progress_detector.gd
extends SceneTree

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


func _assert_candidate(c: Dictionary) -> void:
	_check(str(c.get("action_type", "")) == CompleteProgressScript.ACTION_TYPE, "candidate action_type")
	_check(str(c.get("progress_id", "")) == "controlled_fire", "candidate progress_id")
	_check(int(c.get("schema_version", -1)) == CompleteProgressScript.SCHEMA_VERSION, "candidate schema")


func _init() -> void:
	# 1. Tiny map: no lightning_tree_hex on scenario
	var gs1 = GameStateScript.make_tiny_test_state()
	_check(gs1.scenario.lightning_tree_hex == null, "1 tiny has null tree")
	var s1 = ProgressDetectorScript.suggested_complete_progress_actions(gs1)
	_check(s1.size() == 0, "1 no tree -> no candidates")

	# 2. Tree set, no qualifying move_unit yet
	var tree_hex = HexCoordScript.new(1, -1)
	var gs2 = _gs_tiny_with_tree(tree_hex)
	var s2 = ProgressDetectorScript.suggested_complete_progress_actions(gs2)
	_check(s2.size() == 0, "2 tree only -> no candidates")

	# 3. Tree set, found_city only (Phase 5.1.8a no longer uses found_city for gate)
	gs2.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var s2b = ProgressDetectorScript.suggested_complete_progress_actions(gs2)
	_check(s2b.size() == 0, "3 found city only -> no candidates")

	# 4. Tree set, unrelated move (to (0,1); tree at (1,-1))
	var gs4 = _gs_tiny_with_tree(tree_hex)
	var m4 = gs4.try_apply(MoveUnitScript.make(0, 2, 1, 0, 0, 1))
	_check(m4["accepted"], "4 unrelated move applies")
	var s4 = ProgressDetectorScript.suggested_complete_progress_actions(gs4)
	_check(s4.size() == 0, "4 unrelated move -> no candidate")

	# 5. Move onto tree hex
	var gs5 = _gs_tiny_with_tree(tree_hex)
	var m5 = gs5.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	_check(m5["accepted"], "5 move onto tree applies")
	var s5 = ProgressDetectorScript.suggested_complete_progress_actions(gs5)
	_check(s5.size() == 1, "5 one candidate after onto tree")
	_assert_candidate(s5[0] as Dictionary)
	_check(int((s5[0] as Dictionary)["actor_id"]) == 0, "5 actor 0")
	var v5 = CompleteProgressScript.validate(gs5.progress_state, s5[0])
	_check(v5["ok"], "5 validate ok")

	# 6. Move adjacent to tree (tree at (0,-1); landing (1,-1) is neighbor)
	var adj_tree = HexCoordScript.new(0, -1)
	var gs6 = _gs_tiny_with_tree(adj_tree)
	var m6 = gs6.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	_check(m6["accepted"], "6 adjacent move applies")
	var s6 = ProgressDetectorScript.suggested_complete_progress_actions(gs6)
	_check(s6.size() == 1, "6 adjacent landing -> candidate")

	# 7. Already completed controlled_fire
	var gs7 = _gs_tiny_with_tree(tree_hex)
	gs7.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	gs7.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	var s7 = ProgressDetectorScript.suggested_complete_progress_actions(gs7)
	_check(s7.size() == 0, "7 no suggestion after complete")

	# 8. Actor isolation: P0 found + no tree move; P1 moves onto tree — only P1 candidate
	var gs8 = _gs_tiny_with_tree(tree_hex)
	gs8.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var s8a = ProgressDetectorScript.suggested_complete_progress_actions(gs8)
	_check(s8a.size() == 0, "8a P0 not observed")
	_check(
		gs8.try_apply(EndTurnScript.make(0))["accepted"],
		"8 end P0 turn for P1 move",
	)
	var m8b = gs8.try_apply(MoveUnitScript.make(1, 3, 0, -1, 1, -1))
	_check(m8b["accepted"], "8b P1 onto tree")
	var s8b = ProgressDetectorScript.suggested_complete_progress_actions(gs8)
	_check(s8b.size() == 1, "8b one candidate P1 only")
	_check(int((s8b[0] as Dictionary)["actor_id"]) == 1, "8b actor 1")

	# 9. Rejected move_unit does not count
	var gs9 = _gs_tiny_with_tree(tree_hex)
	var prior = gs9.log.size()
	var r_bad = gs9.try_apply(MoveUnitScript.make(0, 2, 1, 0, 5, 5))
	_check(not r_bad["accepted"], "9 rejected move")
	_check(gs9.log.size() == prior, "9 log unchanged")
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs9).size() == 0, "9 no candidate")

	# 10. Determinism: same output twice
	var gs10 = _gs_tiny_with_tree(tree_hex)
	gs10.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var s10a = ProgressDetectorScript.suggested_complete_progress_actions(gs10)
	var s10b = ProgressDetectorScript.suggested_complete_progress_actions(gs10)
	_check(_actions_array_equal(s10a, s10b), "10 determinism")

	# 11. Defensive null / bad shells
	_check(ProgressDetectorScript.suggested_complete_progress_actions(null).size() == 0, "11 null gs")
	var gs11 = _gs_tiny_with_tree(tree_hex)
	gs11.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var ps_snap = gs11.progress_state
	gs11.progress_state = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs11).size() == 0, "11 null progress")
	gs11.progress_state = ps_snap
	var log_snap = gs11.log
	gs11.log = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs11).size() == 0, "11 null log")
	gs11.log = log_snap
	gs11.turn_state = null
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs11).size() == 0, "11 null turn")

	# 12. Idempotency — detector does not mutate game_state
	var gs12 = _gs_tiny_with_tree(tree_hex)
	gs12.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	var ps12 = gs12.progress_state
	var log12 = gs12.log.size()
	var ts12 = gs12.turn_state
	var out12a = ProgressDetectorScript.suggested_complete_progress_actions(gs12)
	var out12b = ProgressDetectorScript.suggested_complete_progress_actions(gs12)
	_check(ps12.equals(gs12.progress_state), "12 progress unchanged")
	_check(gs12.log.size() == log12, "12 log size unchanged")
	_check(gs12.turn_state.equals(ts12), "12 turn unchanged")
	_check(_actions_array_equal(out12a, out12b), "12 same output twice")

	# 13. Engine-like log entries ignored; still one when move qualifies
	var gs13 = _gs_tiny_with_tree(tree_hex)
	gs13.log.append({"action_type": "production_progress", "result": "accepted"})
	_check(ProgressDetectorScript.suggested_complete_progress_actions(gs13).size() == 0, "13 engine only")
	gs13.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))
	gs13.log.append({"action_type": "unit_produced", "result": "accepted"})
	var s13 = ProgressDetectorScript.suggested_complete_progress_actions(gs13)
	_check(s13.size() == 1, "13 one with engine noise")

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
