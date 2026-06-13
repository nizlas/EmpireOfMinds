# Headless: godot --headless --path game -s res://domain/tests/test_storehouse_ledger_build_flow.gd
# Third gameplay-enforced science reward: counting_marks unlocks build:storehouse_ledger (+2 coin).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")
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


func _complete_counting_marks_prereqs(gs) -> void:
	_check(gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"], "prereq CF")
	_check(gs.try_apply(CompleteProgressScript.make(0, "oral_surveying"))["accepted"], "prereq oral")
	_check(gs.try_apply(CompleteProgressScript.make(0, "pottery_craft"))["accepted"], "prereq pottery")


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
		not _has_sp(
			LegalActionsScript.for_current_player(gs),
			city_id,
			SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER
		),
		"ledger not legal at start"
	)
	var r_gate0 = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER)
	)
	_check(not r_gate0["accepted"] and r_gate0["reason"] == "project_not_unlocked", "gate before counting_marks")

	_complete_counting_marks_prereqs(gs)
	var r_cm_req = gs.try_apply(CompleteProgressScript.make(0, "counting_marks"))
	_check(r_cm_req["accepted"], "complete counting_marks")
	_check(
		gs.progress_state.has_unlocked_target(
			0, "building", BuildingDefinitionsScript.BUILDING_ID_STOREHOUSE_LEDGER
		),
		"counting_marks unlocks building/storehouse_ledger"
	)

	var L_cm = LegalActionsScript.for_current_player(gs)
	_check(
		_has_sp(L_cm, city_id, SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER),
		"ledger legal after counting_marks"
	)

	var y_before: Dictionary = CityYieldsScript.city_total_yield(
		gs.scenario, gs.scenario.city_by_id(city_id)
	)
	var coin_before: int = CityYieldsScript.get_yield(y_before, "coin")

	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER)
		)["accepted"],
		"start ledger build"
	)
	var sl_proj = gs.scenario.city_by_id(city_id).current_project as Dictionary
	_check(int(sl_proj.get("cost", -1)) == 2, "ledger cost 2")
	_deliver_current_project(gs)

	var cy_sl = gs.scenario.city_by_id(city_id)
	_check(
		CityProjectDefinitionsScript.city_has_building(
			cy_sl, BuildingDefinitionsScript.BUILDING_ID_STOREHOUSE_LEDGER
		),
		"storehouse_ledger in building_ids"
	)
	var y_sl: Dictionary = CityYieldsScript.city_total_yield(gs.scenario, cy_sl)
	_check(CityYieldsScript.get_yield(y_sl, "coin") == coin_before + 2, "ledger +2 coin")

	var r_repeat = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER)
	)
	_check(not r_repeat["accepted"] and r_repeat["reason"] == "building_already_present", "not repeatable")

	var food_before_other: int = CityYieldsScript.get_yield(y_sl, "food")
	var prod_before_other: int = CityYieldsScript.get_yield(y_sl, "production")
	_check(
		_has_sp(L_cm, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH),
		"hearth still legal with ledger"
	)
	_check(
		_has_sp(L_cm, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP),
		"pottery still legal with ledger"
	)
	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP)
		)["accepted"],
		"start pottery after ledger"
	)
	_deliver_current_project(gs)
	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_BUILD_HEARTH)
		)["accepted"],
		"start hearth after pottery on ledger city"
	)
	_deliver_current_project(gs)

	var cy_all = gs.scenario.city_by_id(city_id)
	_check(
		CityProjectDefinitionsScript.city_has_building(
			cy_all, BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP
		),
		"pottery still builds"
	)
	_check(
		CityProjectDefinitionsScript.city_has_building(cy_all, BuildingDefinitionsScript.BUILDING_ID_HEARTH),
		"hearth still builds"
	)
	var y_all: Dictionary = CityYieldsScript.city_total_yield(gs.scenario, cy_all)
	_check(CityYieldsScript.get_yield(y_all, "food") == food_before_other + 1, "pottery +1 food retained path")
	_check(CityYieldsScript.get_yield(y_all, "production") == prod_before_other + 1, "hearth +1 production path")
	_check(CityYieldsScript.get_yield(y_all, "coin") == coin_before + 2, "ledger coin retained")

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
