# Headless: godot --headless --path game -s res://domain/tests/test_hearth_build_flow.gd
# First gameplay-enforced science reward: controlled_fire unlocks build:hearth (+1 production).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
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


func _has_building_completed_for_city(gs, city_id: int) -> bool:
	var i = 0
	while i < gs.log.size():
		var e = gs.log.get_entry(i) as Dictionary
		if (
			str(e.get("action_type", "")) == ProductionDeliveryScript.EVENT_TYPE_BUILDING_COMPLETED
			and int(e.get("city_id", -1)) == city_id
		):
			return true
		i = i + 1
	return false


func _init() -> void:
	var pm = HexMapScript.make_prototype_play_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 1, HexCoordScript.new(0, -1), "settler"),
	]
	var gs = GameStateScript.new(ScenarioScript.new(pm, us))
	var city_id = gs.scenario.peek_next_city_id()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital")

	_check(
		gs.progress_state.has_unlocked_target(
			0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER
		),
		"settler baseline turn 1"
	)
	_check(
		not gs.progress_state.has_unlocked_target(0, "building", CityProjectDefinitionsScript.BUILDING_ID_HEARTH),
		"hearth building unlock only after CF"
	)

	var L0 = LegalActionsScript.for_current_player(gs)
	_check(_has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR), "warrior legal")
	_check(_has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER), "settler legal")
	_check(not _has_sp(L0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH), "hearth not legal before CF")

	var r_gate = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH)
	)
	_check(not r_gate["accepted"] and r_gate["reason"] == "project_not_unlocked", "try_apply gates hearth")

	var r_cf = gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(r_cf["accepted"], "complete controlled_fire")
	_check(
		gs.progress_state.has_unlocked_target(0, "building", CityProjectDefinitionsScript.BUILDING_ID_HEARTH),
		"cf unlocks building/hearth"
	)
	_check(
		gs.progress_state.has_unlocked_target(
			0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER
		),
		"settler baseline unchanged after CF"
	)

	var L1 = LegalActionsScript.for_current_player(gs)
	_check(_has_sp(L1, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH), "hearth legal after CF")

	var y_before: Dictionary = CityYieldsScript.city_total_yield(
		gs.scenario, gs.scenario.city_by_id(city_id)
	)
	var prod_before: int = CityYieldsScript.get_yield(y_before, "production")

	var r_sp = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH)
	)
	_check(r_sp["accepted"], "start hearth build")
	var cy_proj = gs.scenario.city_by_id(city_id).current_project as Dictionary
	_check(str(cy_proj.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_BUILD_HEARTH, "project id")
	_check(int(cy_proj.get("cost", -1)) == 2, "hearth cost 2")

	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end p0 tick")
	var pp = gs.scenario.city_by_id(city_id).current_project as Dictionary
	_check(bool(pp.get("ready", false)), "hearth ready after one tick")
	_check(gs.try_apply(EndTurnScript.make(1))["accepted"], "end p1 deliver hearth")

	var cy_done = gs.scenario.city_by_id(city_id)
	_check(cy_done.current_project == null, "project cleared after delivery")
	_check(
		CityProjectDefinitionsScript.city_has_building(cy_done, CityProjectDefinitionsScript.BUILDING_ID_HEARTH),
		"city has hearth building"
	)
	_check(_has_building_completed_for_city(gs, city_id), "building_completed logged")

	var y_after: Dictionary = CityYieldsScript.city_total_yield(gs.scenario, cy_done)
	_check(
		CityYieldsScript.get_yield(y_after, "production") == prod_before + 1,
		"hearth adds +1 production"
	)

	var r_repeat = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH)
	)
	_check(not r_repeat["accepted"] and r_repeat["reason"] == "building_already_present", "not repeatable")

	var L2 = LegalActionsScript.for_current_player(gs)
	_check(not _has_sp(L2, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH), "hearth omitted when built")

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
