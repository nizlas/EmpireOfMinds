# Headless: godot --headless --path game -s res://domain/tests/test_complete_progress_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")

var _total = 0
var _any_fail = false


func _row_match(d: Dictionary, tt: String, ti: String) -> bool:
	return str(d["target_type"]) == tt and str(d["target_id"]) == ti


func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(gs.log.size() == 0, "initial log empty")
	var act = CompleteProgressScript.make(0, "foraging_systems")
	var r1 = gs.try_apply(act)
	_check(r1["accepted"], "A accepted")
	_check(str(r1["reason"]) == "", "A empty reason")
	_check(r1["index"] == 0, "A index 0")
	_check(gs.log.size() == 1, "A log one")
	_check(gs.progress_state.has_completed_progress(0, "foraging_systems"), "A completed")
	_check(
		gs.progress_state.has_unlocked_target(0, "building", "scout_camp"),
		"A scout_camp"
	)
	_check(gs.progress_state.has_unlocked_target(0, "specialist", "forager"), "A forager")
	_check(
		gs.progress_state.has_unlocked_target(0, "modifier", "forest_food_bonus"),
		"A forest bonus"
	)
	_check(
		gs.progress_state.has_unlocked_target(0, "modifier", "outside_borders_healing"),
		"A healing"
	)
	_check(
		not gs.progress_state.has_unlocked_target(0, "science", "survival_knowledge"),
		"A no survival"
	)
	_check(
		not gs.progress_state.has_unlocked_target(0, "science", "woodland_logistics"),
		"A no woodland"
	)
	var e0 = gs.log.get_entry(0) as Dictionary
	_check(e0["action_type"] == CompleteProgressScript.ACTION_TYPE, "A log action type")
	_check(int(e0["actor_id"]) == 0, "A log actor")
	_check(str(e0["progress_id"]) == "foraging_systems", "A log progress_id")
	var ut = e0["unlocked_targets"] as Array
	_check(typeof(ut) == TYPE_ARRAY and ut.size() == 4, "A unlocks size")
	_check(_row_match(ut[0] as Dictionary, "building", "scout_camp"), "A ord0")
	_check(_row_match(ut[1] as Dictionary, "specialist", "forager"), "A ord1")
	_check(_row_match(ut[2] as Dictionary, "modifier", "forest_food_bonus"), "A ord2")
	_check(_row_match(ut[3] as Dictionary, "modifier", "outside_borders_healing"), "A ord3")
	_check(str(e0["result"]) == "accepted", "A log result")

	var prior_log = gs.log.size()
	var prior_ps = gs.progress_state
	var r_dup = gs.try_apply(CompleteProgressScript.make(0, "foraging_systems"))
	_check(not r_dup["accepted"], "B reject dup")
	_check(r_dup["reason"] == "progress_already_completed", "B reason")
	_check(r_dup["index"] == -1, "B index")
	_check(gs.log.size() == prior_log, "B log unchanged")
	_check(prior_ps.equals(gs.progress_state), "B progress_state unchanged")

	var gs2 = GameStateScript.make_tiny_test_state()
	var r_wrong = gs2.try_apply(CompleteProgressScript.make(1, "foraging_systems"))
	_check(not r_wrong["accepted"], "C not accepted")
	_check(r_wrong["reason"] == "not_current_player", "C reason")
	_check(r_wrong["index"] == -1, "C index")
	_check(gs2.log.size() == 0, "C log empty")
	_check(not gs2.progress_state.has_completed_progress(1, "foraging_systems"), "C p1 not done")

	var gs3 = GameStateScript.make_tiny_test_state()
	var r_bad = gs3.try_apply(CompleteProgressScript.make(0, "nope"))
	_check(not r_bad["accepted"], "D reject")
	_check(r_bad["reason"] == "unknown_progress_id", "D reason")
	_check(gs3.log.size() == 0, "D log empty")

	var gs4 = GameStateScript.make_tiny_test_state()
	var city_id = gs4.scenario.peek_next_city_id()
	var r_fc = gs4.try_apply(FoundCityScript.make(0, 1, 0, 0))
	_check(r_fc["accepted"], "E found city")
	var r_sp = gs4.try_apply(
		SetCityProductionScript.make(
			0,
			city_id,
			SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
		)
	)
	_check(r_sp["accepted"], "E set production warrior")

	var gs5 = GameStateScript.make_tiny_test_state()
	gs5.try_apply(CompleteProgressScript.make(0, "foraging_systems"))
	var entry_mut = gs5.log.get_entry(0) as Dictionary
	var ut_mut = entry_mut["unlocked_targets"] as Array
	(ut_mut[0] as Dictionary)["target_id"] = "CORRUPT"
	ut_mut.append({"target_type": "x", "target_id": "y"})
	var entry_again = gs5.log.get_entry(0) as Dictionary
	var ut_clean = entry_again["unlocked_targets"] as Array
	_check(str((ut_clean[0] as Dictionary)["target_id"]) == "scout_camp", "F row0 intact")
	_check(ut_clean.size() == 4, "F size intact")

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
