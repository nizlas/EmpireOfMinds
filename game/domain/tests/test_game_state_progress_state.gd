# Headless: godot --headless --path game -s res://domain/tests/test_game_state_progress_state.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var gs0 = GameStateScript.make_tiny_test_state()
	_check(gs0.progress_state != null, "tiny progress_state non-null")
	_check(
		gs0.progress_state.has_unlocked_target(0, "city_project", "produce_unit:warrior"),
		"tiny p0 default warrior"
	)
	_check(
		gs0.progress_state.has_unlocked_target(1, "city_project", "produce_unit:warrior"),
		"tiny p1 default warrior"
	)

	var gs_city = GameStateScript.make_tiny_test_state()
	var city_id = gs_city.scenario.peek_next_city_id()
	var r_fc = gs_city.try_apply(FoundCityScript.make(0, 1, 0, 0))
	_check(r_fc["accepted"], "found city for gate tests")
	_check(
		gs_city.scenario.city_by_id(city_id).owner_id == 0,
		"city owned p0"
	)

	var sp_ok = SetCityProductionScript.make(
		0,
		city_id,
		SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
	)
	var r_w = gs_city.try_apply(sp_ok)
	_check(r_w["accepted"], "warrior accepted with default progress")

	var sc_locked_base = GameStateScript.make_tiny_test_state()
	var r2 = sc_locked_base.try_apply(FoundCityScript.make(0, 1, 0, 0))
	_check(r2["accepted"], "found city for locked shell")
	var sc_after = sc_locked_base.scenario
	var gs_locked = GameStateScript.new(sc_after, ProgressStateScript.new({}))
	_check(gs_locked.log.size() == 0, "fresh log on new GameState")
	var sp_locked = SetCityProductionScript.make(
		0,
		city_id,
		SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
	)
	var scen_ref = gs_locked.scenario
	var r_bad = gs_locked.try_apply(sp_locked)
	_check(not r_bad["accepted"], "locked rejects warrior")
	_check(r_bad["reason"] == "project_not_unlocked", "reason unlock")
	_check(r_bad["index"] == -1, "index -1")
	_check(gs_locked.log.size() == 0, "log unchanged reject")
	_check(gs_locked.scenario == scen_ref, "scenario ref unchanged")
	_check(
		gs_locked.scenario.city_by_id(city_id).current_project == null,
		"city project still null"
	)

	var gs_proj = GameStateScript.make_tiny_test_state()
	gs_proj.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var cid2 = city_id
	_check(
		gs_proj.try_apply(
			SetCityProductionScript.make(
				0,
				cid2,
				SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
			)
		)["accepted"],
		"seed warrior project"
	)
	_check(gs_proj.scenario.city_by_id(cid2).current_project != null, "has project")
	var gs_clear = GameStateScript.new(gs_proj.scenario, ProgressStateScript.new({}))
	var r_none = gs_clear.try_apply(
		SetCityProductionScript.make(0, cid2, SetCityProductionScript.PROJECT_ID_NONE)
	)
	_check(r_none["accepted"], "PROJECT_ID_NONE never gated")

	var gs_v = GameStateScript.make_tiny_test_state()
	gs_v.try_apply(FoundCityScript.make(0, 1, 0, 0))
	var gs_v_empty = GameStateScript.new(gs_v.scenario, ProgressStateScript.new({}))
	var r_bad_proj = gs_v_empty.try_apply(
		SetCityProductionScript.make(0, city_id, "nexus_gate")
	)
	_check(not r_bad_proj["accepted"], "bad project rejected")
	_check(
		r_bad_proj["reason"] == "unsupported_project_id",
		"validate beats unlock gate"
	)

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
