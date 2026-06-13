# Headless: godot --headless --path game -s res://domain/tests/test_pottery_workshop_build_flow.gd
# Second gameplay-enforced science reward: pottery_craft unlocks build:pottery_workshop (+1 food).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")

var _total = 0
var _any_fail = false


func _has_sp(L: Array, city_id: int, project_id: String) -> bool:
	var i = 0
	while i < L.size():
		var e = L[i] as Dictionary
		if (
			e.get("action_type", "") == SetCityProductionScript.ACTION_TYPE
			and int(e.get("city_id", -1)) == city_id
			and str(e.get("project_id", "")) == project_id
		):
			return true
		i = i + 1
	return false


func _deliver_current_project(gs) -> void:
	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end p0 tick")
	_check(gs.try_apply(EndTurnScript.make(1))["accepted"], "end p1 deliver")


func _init() -> void:
	var pm = HexMapScript.make_prototype_play_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 1, HexCoordScript.new(0, -1), "settler"),
	]
	var gs = GameStateScript.new(ScenarioScript.new(pm, us))
	var city_id = gs.scenario.peek_next_city_id()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital")

	var L0 = LegalActionsScript.for_current_player(gs)
	_check(_has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR), "warrior baseline")
	_check(_has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER), "settler baseline")
	_check(
		not _has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP),
		"pottery workshop not legal at start"
	)

	var r_gate0 = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP)
	)
	_check(not r_gate0["accepted"] and r_gate0["reason"] == "project_not_unlocked", "gate before pottery_craft")

	var r_pc_req = gs.try_apply(CompleteProgressScript.make(0, "pottery_craft"))
	_check(not r_pc_req["accepted"] and r_pc_req["reason"] == "prerequisites_not_met", "pottery_craft needs CF first")

	_check(gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"], "complete controlled_fire")
	var L_cf = LegalActionsScript.for_current_player(gs)
	_check(_has_sp(L_cf, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH), "hearth legal after CF")
	_check(
		not _has_sp(L_cf, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP),
		"pottery workshop still locked after CF only"
	)

	_check(gs.try_apply(CompleteProgressScript.make(0, "pottery_craft"))["accepted"], "complete pottery_craft")
	_check(
		gs.progress_state.has_unlocked_target(
			0, "building", CityProjectDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP
		),
		"pottery_craft unlocks building/pottery_workshop"
	)

	var L_pc = LegalActionsScript.for_current_player(gs)
	_check(
		_has_sp(L_pc, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP),
		"pottery workshop legal after pottery_craft"
	)

	var y_before: Dictionary = CityYieldsScript.city_total_yield(
		gs.scenario, gs.scenario.city_by_id(city_id)
	)
	var food_before: int = CityYieldsScript.get_yield(y_before, "food")

	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP)
		)["accepted"],
		"start pottery workshop build"
	)
	var pw_proj = gs.scenario.city_by_id(city_id).current_project as Dictionary
	_check(int(pw_proj.get("cost", -1)) == 2, "pottery workshop cost 2")
	_deliver_current_project(gs)

	var cy_pw = gs.scenario.city_by_id(city_id)
	_check(
		CityProjectDefinitionsScript.city_has_building(
			cy_pw, CityProjectDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP
		),
		"pottery_workshop in building_ids"
	)
	var y_pw: Dictionary = CityYieldsScript.city_total_yield(gs.scenario, cy_pw)
	_check(CityYieldsScript.get_yield(y_pw, "food") == food_before + 1, "pottery workshop +1 food")

	var r_repeat = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP)
	)
	_check(not r_repeat["accepted"] and r_repeat["reason"] == "building_already_present", "not repeatable")

	# Hearth path still works on the same city (reuses generic build_building delivery).
	var prod_before_hearth: int = CityYieldsScript.get_yield(y_pw, "production")
	_check(
		_has_sp(LegalActionsScript.for_current_player(gs), city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH),
		"hearth still legal alongside pottery workshop"
	)
	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH)
		)["accepted"],
		"start hearth after pottery workshop"
	)
	_deliver_current_project(gs)
	var cy_both = gs.scenario.city_by_id(city_id)
	_check(
		CityProjectDefinitionsScript.city_has_building(cy_both, CityProjectDefinitionsScript.BUILDING_ID_HEARTH),
		"hearth still deliverable"
	)
	var y_both: Dictionary = CityYieldsScript.city_total_yield(gs.scenario, cy_both)
	_check(
		CityYieldsScript.get_yield(y_both, "production") == prod_before_hearth + 1,
		"hearth still +1 production"
	)
	_check(CityYieldsScript.get_yield(y_both, "food") == food_before + 1, "pottery food retained")

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
