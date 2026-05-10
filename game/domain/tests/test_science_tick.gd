# Headless: godot --headless --path game -s res://domain/tests/test_science_tick.gd
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")
const ScienceTickScript = preload("res://domain/science_tick.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ActionLogScript = preload("res://domain/action_log.gd")
const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const ProgressUnlockResolverScript = preload("res://domain/progress_unlock_resolver.gd")

var _total = 0
var _any_fail = false


func _tiny_one_city_scenario(lightning = null):
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var city = CityScript.new(3, 0, HexCoordScript.new(1, -1), null)
	return ScenarioScript.new(m, u, [city], 10, 20, lightning)


func _init() -> void:
	# Auto-target: first alphabetically among start sciences is controlled_fire.
	var scen0 = _tiny_one_city_scenario(null)
	var gs0 = GameStateScript.new(scen0)
	var pack0 = ScienceTickScript.apply_for_player(gs0.progress_state, gs0.scenario, 0)
	_check((pack0["events"] as Array).size() == 1, "one science_progress")
	var e0 = (pack0["events"] as Array)[0] as Dictionary
	_check(str(e0["action_type"]) == "science_progress", "event type")
	_check(str(e0["progress_id"]) == "controlled_fire", "auto first is controlled_fire")
	_check(int(e0["delta"]) == 1 and int(e0["total"]) == 1, "one city yield")
	_check(int(e0["cost"]) == ProgressDefinitionsScript.cost("controlled_fire"), "cost from definitions")

	gs0.progress_state = pack0["progress_state"]
	var cp = gs0.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(cp["accepted"], "manual complete for idempotent setup")
	var pack_idem = ScienceTickScript.apply_for_player(gs0.progress_state, gs0.scenario, 0)
	_check((pack_idem["events"] as Array).size() == 1, "progress toward next auto target")
	var e1 = (pack_idem["events"] as Array)[0] as Dictionary
	_check(str(e1["progress_id"]) == "foraging_systems", "after CF first available is foraging_systems")
	_check(int(e1["total"]) == 1, "fresh bucket for foraging_systems")

	# Six yields complete controlled_fire from zero (auto-target stays CF until done)
	var scen1 = _tiny_one_city_scenario(null)
	var gs1 = GameStateScript.new(scen1)
	var ps = gs1.progress_state
	var completed = false
	var last_completed_ut: Array = []
	var rounds = 0
	while rounds < 6:
		var pk = ScienceTickScript.apply_for_player(ps, gs1.scenario, 0)
		ps = pk["progress_state"]
		var evs = pk["events"] as Array
		var ei = 0
		while ei < evs.size():
			if str((evs[ei] as Dictionary).get("action_type", "")) == "science_completed":
				completed = true
				var ec = evs[ei] as Dictionary
				_check(str(ec["progress_id"]) == "controlled_fire", "completed id CF")
				_check(int(ec["cost"]) == ProgressDefinitionsScript.cost("controlled_fire"), "completed cost")
				last_completed_ut = ec.get("unlocked_targets", []) as Array
			ei = ei + 1
		rounds = rounds + 1
	_check(completed, "six ticks complete science")
	_check(ps.has_completed_progress(0, "controlled_fire"), "resolver completed")
	_check(
		ps.has_unlocked_target(0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"settler was baseline before tick loop"
	)
	_check(ps.has_unlocked_target(0, "building", "hearth"), "cf completion adds hearth")
	_check(ps.has_unlocked_target(0, "action", "camp_clearing"), "cf adds camp_clearing")
	_check(ps.has_unlocked_target(0, "modifier", "controlled_fire_practice"), "cf adds practice modifier")
	var saw_settler_in_completed = false
	var uix = 0
	while uix < last_completed_ut.size():
		var ur = last_completed_ut[uix] as Dictionary
		if (
			str(ur.get("target_type", "")) == "city_project"
			and str(ur.get("target_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER
		):
			saw_settler_in_completed = true
		uix = uix + 1
	_check(not saw_settler_in_completed, "science_completed delta has no settler city_project")

	# Explicit current research: stone_tools receives yield
	var def = ProgressStateScript.with_default_unlocks_for_players([0])
	var ps_st = def.with_current_research(0, "stone_tools")
	var scen_st = _tiny_one_city_scenario(null)
	var pk_st = ScienceTickScript.apply_for_player(ps_st, scen_st, 0)
	var ev_st = (pk_st["events"] as Array)[0] as Dictionary
	_check(str(ev_st["progress_id"]) == "stone_tools", "explicit target stone_tools")
	_check(int(ev_st["cost"]) == ProgressDefinitionsScript.cost("stone_tools"), "stone cost on event")

	# Locked explicit target falls back to auto (controlled_fire)
	var ps_bad = def.with_current_research(0, "animal_tracking")
	var pk_fb = ScienceTickScript.apply_for_player(ps_bad, scen_st, 0)
	var ev_fb = (pk_fb["events"] as Array)[0] as Dictionary
	_check(str(ev_fb["progress_id"]) == "controlled_fire", "fallback when explicit locked")

	# Stale explicit (completed) falls back
	var res_cf = ProgressUnlockResolverScript.complete_progress(def, 0, "controlled_fire")
	_check(bool(res_cf["ok"]), "resolver complete CF for stale test")
	var ps_stale = res_cf["progress_state"].with_current_research(0, "controlled_fire")
	var pk_stale = ScienceTickScript.apply_for_player(ps_stale, scen_st, 0)
	var ev_sl = (pk_stale["events"] as Array)[0] as Dictionary
	_check(str(ev_sl["progress_id"]) == "foraging_systems", "stale explicit falls back like auto after CF")

	# Lightning bonus always controlled_fire even when current research is stone_tools
	var tree_hex = HexCoordScript.new(1, 0)
	var scen2 = _tiny_one_city_scenario(tree_hex)
	var gs2 = GameStateScript.new(scen2)
	gs2.progress_state = gs2.progress_state.with_current_research(0, "stone_tools")
	var obs1 = ScienceTickScript.add_observation_bonus_if_eligible(
		gs2.progress_state,
		gs2.scenario,
		0,
		gs2.log
	)
	_check((obs1["events"] as Array).size() == 0, "no bonus without move in log")
	var log2 = ActionLogScript.new()
	log2.append({
		"schema_version": MoveUnitScript.SCHEMA_VERSION,
		"action_type": MoveUnitScript.ACTION_TYPE,
		"actor_id": 0,
		"unit_id": 1,
		"from": [0, 0],
		"to": [1, 0],
		"result": "accepted",
	})
	var obs2 = ScienceTickScript.add_observation_bonus_if_eligible(
		gs2.progress_state,
		gs2.scenario,
		0,
		log2
	)
	var evb = obs2["events"] as Array
	_check(evb.size() >= 2, "bonus + progress events")
	var ev_bonus = evb[0] as Dictionary
	var ev_prog = evb[1] as Dictionary
	_check(str(ev_bonus["action_type"]) == "science_bonus", "first is science_bonus")
	_check(str(ev_bonus["progress_id"]) == "controlled_fire", "bonus always CF")
	_check(str(ev_prog["progress_id"]) == "controlled_fire", "bonus progress toward CF")
	_check(int(ev_bonus["cost"]) == ProgressDefinitionsScript.cost("controlled_fire"), "bonus cost")
	_check(int(ev_bonus["total"]) == int(ev_prog.get("total", -1)), "bonus total matches progress row")
	var ps2 = obs2["progress_state"]
	var obs3 = ScienceTickScript.add_observation_bonus_if_eligible(ps2, gs2.scenario, 0, log2)
	_check((obs3["events"] as Array).size() == 0, "one-time bonus")

	var scen_done = _tiny_one_city_scenario(tree_hex)
	var gs_done = GameStateScript.new(scen_done)
	var cp_done = gs_done.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(cp_done["accepted"], "complete controlled_fire for no-bonus test")
	var log_done = ActionLogScript.new()
	log_done.append({
		"schema_version": MoveUnitScript.SCHEMA_VERSION,
		"action_type": MoveUnitScript.ACTION_TYPE,
		"actor_id": 0,
		"unit_id": 1,
		"from": [0, 0],
		"to": [1, 0],
		"result": "accepted",
	})
	var obs_done = ScienceTickScript.add_observation_bonus_if_eligible(
		gs_done.progress_state,
		gs_done.scenario,
		0,
		log_done
	)
	_check((obs_done["events"] as Array).size() == 0, "no science_bonus when science already completed")

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
