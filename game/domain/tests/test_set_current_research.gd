# Headless: godot --headless --path game -s res://domain/tests/test_set_current_research.gd
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")
const SetCurrentResearchScript = preload("res://domain/actions/set_current_research.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const ScienceTickScript = preload("res://domain/science_tick.gd")

var _total = 0
var _any_fail = false


func _one_city_scenario():
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var city = CityScript.new(3, 0, HexCoordScript.new(1, -1), null)
	return ScenarioScript.new(m, u, [city], 10, 20, null)


func _init() -> void:
	var m = SetCurrentResearchScript.make(3, "stone_tools")
	_check(m["action_type"] == SetCurrentResearchScript.ACTION_TYPE, "make type")
	_check(m["schema_version"] == SetCurrentResearchScript.SCHEMA_VERSION, "make schema")
	_check(m["actor_id"] == 3 and m["science_id"] == "stone_tools", "make fields")

	var ps = ProgressStateScript.with_default_unlocks_for_players([0])
	var ok_st = SetCurrentResearchScript.validate(ps, SetCurrentResearchScript.make(0, "stone_tools"))
	_check(ok_st["ok"], "accept start science stone_tools")

	var locked = SetCurrentResearchScript.validate(ps, SetCurrentResearchScript.make(0, "animal_tracking"))
	_check(
		not locked["ok"] and str(locked["reason"]) == "prerequisites_not_met",
		"reject locked animal_tracking"
	)

	var ps_done = ps.with_progress_id_completed(0, "stone_tools")
	var done_again = SetCurrentResearchScript.validate(
		ps_done,
		SetCurrentResearchScript.make(0, "stone_tools")
	)
	_check(
		not done_again["ok"] and str(done_again["reason"]) == "already_completed",
		"reject completed"
	)

	var unk = SetCurrentResearchScript.validate(ps, SetCurrentResearchScript.make(0, "not_a_real_id"))
	_check(not unk["ok"] and str(unk["reason"]) == "unknown_science", "unknown science")

	var clr = SetCurrentResearchScript.validate(
		ps.with_current_research(0, "stone_tools"),
		SetCurrentResearchScript.make(0, "")
	)
	_check(clr["ok"], "clear with empty science_id")

	var scen = _one_city_scenario()
	var gs = GameStateScript.new(scen)
	var r_set = gs.try_apply(SetCurrentResearchScript.make(0, "stone_tools"))
	_check(r_set["accepted"], "try_apply set accepted")
	_check(gs.progress_state.current_research_for(0) == "stone_tools", "state stores target")
	var li = gs.log.size() - 1
	var ent = gs.log.get_entry(li) as Dictionary
	_check(str(ent.get("action_type", "")) == "set_current_research", "log action type")
	_check(str(ent.get("science_id", "")) == "stone_tools", "log science_id")

	var r_et = gs.try_apply(EndTurnScript.make(0))
	_check(r_et["accepted"], "end turn after set")
	var saw_stone = false
	var lj = 0
	while lj < gs.log.size():
		var e = gs.log.get_entry(lj) as Dictionary
		if str(e.get("action_type", "")) == "science_progress":
			if str(e.get("progress_id", "")) == "stone_tools" and int(e.get("actor_id", -1)) == 0:
				saw_stone = true
		lj = lj + 1
	_check(saw_stone, "end turn science_progress toward stone_tools")

	var gs2 = GameStateScript.new(scen)
	gs2.try_apply(SetCurrentResearchScript.make(0, "stone_tools"))
	var tick_only = ScienceTickScript.apply_for_player(gs2.progress_state, gs2.scenario, 0)
	var te = (tick_only["events"] as Array)[0] as Dictionary
	_check(str(te.get("progress_id", "")) == "stone_tools", "direct tick honors explicit target")

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
