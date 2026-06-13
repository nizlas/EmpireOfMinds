# Headless: godot --headless --path game -s res://domain/tests/test_ancient_city_buildings_batch.gd
# Batch: five remaining Ancient gameplay-enforced science building rewards (registry-driven).
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

const BUILD_SPECS: Array = [
	{
		"science": "seasonal_calendars",
		"prereqs": ["foraging_systems", "controlled_fire"],
		"project": "build:storage_hall",
		"building": "storage_hall",
		"yield_key": "food",
		"delta": 1,
	},
	{
		"science": "textile_work",
		"prereqs": ["foraging_systems"],
		"project": "build:weaver_hut",
		"building": "weaver_hut",
		"yield_key": "coin",
		"delta": 2,
	},
	{
		"science": "mudbrick_construction",
		"prereqs": ["stone_tools", "controlled_fire", "timber_working"],
		"project": "build:mudbrick_housing",
		"building": "mudbrick_housing",
		"yield_key": "housing",
		"delta": 2,
	},
	{
		"science": "glyphic_records",
		"prereqs": ["controlled_fire", "oral_surveying", "pottery_craft", "counting_marks"],
		"project": "build:archive_hut",
		"building": "archive_hut",
		"yield_key": "science",
		"delta": 2,
	},
	{
		"science": "bronze_alloying",
		"prereqs": ["stone_tools", "basic_mining"],
		"project": "build:armory",
		"building": "armory",
		"yield_key": "production",
		"delta": 1,
	},
]

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


func _complete_prereqs(gs, prereqs: Array) -> void:
	var i = 0
	while i < prereqs.size():
		var pid: String = str(prereqs[i])
		_check(gs.try_apply(CompleteProgressScript.make(0, pid))["accepted"], "prereq %s" % pid)
		i = i + 1


func _fresh_capital() -> Dictionary:
	var pm = HexMapScript.make_prototype_play_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 1, HexCoordScript.new(0, -1), "settler"),
	]
	var gs = GameStateScript.new(ScenarioScript.new(pm, us))
	var city_id = gs.scenario.peek_next_city_id()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital")
	return {"gs": gs, "city_id": city_id}


func _yield_before(gs, city_id: int, key: String) -> int:
	var y: Dictionary = CityYieldsScript.city_total_yield(
		gs.scenario, gs.scenario.city_by_id(city_id)
	)
	if key == "housing":
		return CityYieldsScript.building_housing_total(gs.scenario.city_by_id(city_id))
	return CityYieldsScript.get_yield(y, key)


func _yield_after(gs, city_id: int, key: String) -> int:
	if key == "housing":
		var brk: Dictionary = CityYieldsScript.yield_breakdown_for_city(
			gs.scenario, gs.scenario.city_by_id(city_id)
		)
		return int(brk.get("housing", -1))
	var y: Dictionary = CityYieldsScript.city_total_yield(
		gs.scenario, gs.scenario.city_by_id(city_id)
	)
	return CityYieldsScript.get_yield(y, key)


func _test_build_spec(spec: Dictionary) -> void:
	var science: String = str(spec["science"])
	var project: String = str(spec["project"])
	var building: String = str(spec["building"])
	var yield_key: String = str(spec["yield_key"])
	var delta: int = int(spec["delta"])
	var prereqs: Array = spec["prereqs"] as Array

	var pack = _fresh_capital()
	var gs = pack["gs"]
	var city_id: int = int(pack["city_id"])

	_check(
		not _has_sp(LegalActionsScript.for_current_player(gs), city_id, project),
		"%s not legal before %s" % [project, science]
	)
	var r_gate = gs.try_apply(SetCityProductionScript.make(0, city_id, project))
	_check(not r_gate["accepted"] and r_gate["reason"] == "project_not_unlocked", "%s gated" % project)

	_complete_prereqs(gs, prereqs)
	var r_sci = gs.try_apply(CompleteProgressScript.make(0, science))
	_check(r_sci["accepted"], "complete %s" % science)
	_check(
		gs.progress_state.has_unlocked_target(0, "building", building),
		"%s unlocks building/%s" % [science, building]
	)

	var L = LegalActionsScript.for_current_player(gs)
	_check(_has_sp(L, city_id, project), "%s legal after %s" % [project, science])

	var before_val: int = _yield_before(gs, city_id, yield_key)
	_check(
		gs.try_apply(SetCityProductionScript.make(0, city_id, project))["accepted"],
		"start %s" % project
	)
	_check(int(gs.scenario.city_by_id(city_id).current_project.get("cost", -1)) == 2, "%s cost 2" % project)
	_deliver_current_project(gs)

	var cy = gs.scenario.city_by_id(city_id)
	_check(CityProjectDefinitionsScript.city_has_building(cy, building), "%s in building_ids" % building)
	_check(_yield_after(gs, city_id, yield_key) == before_val + delta, "%s %+d %s" % [building, delta, yield_key])

	if yield_key == "housing":
		_check(
			CityYieldsScript.get_yield(CityYieldsScript.city_total_yield(gs.scenario, cy), "housing") == 0,
			"housing not in gameplay total dict"
		)

	var r_repeat = gs.try_apply(SetCityProductionScript.make(0, city_id, project))
	_check(
		not r_repeat["accepted"] and r_repeat["reason"] == "building_already_present",
		"%s not repeatable" % building
	)


func _complete_all_ancient_building_sciences(gs) -> void:
	var all_prereqs: Array = [
		"foraging_systems",
		"stone_tools",
		"controlled_fire",
		"oral_surveying",
		"basic_mining",
		"timber_working",
		"pottery_craft",
		"counting_marks",
		"seasonal_calendars",
		"textile_work",
		"mudbrick_construction",
		"glyphic_records",
		"bronze_alloying",
	]
	_complete_prereqs(gs, all_prereqs)


func _init() -> void:
	var si = 0
	while si < BUILD_SPECS.size():
		_test_build_spec(BUILD_SPECS[si] as Dictionary)
		si = si + 1

	var pack = _fresh_capital()
	var gs = pack["gs"]
	var city_id: int = int(pack["city_id"])
	_complete_all_ancient_building_sciences(gs)

	var stack_projects: Array = [
		SetCityProductionScript.PROJECT_ID_BUILD_HEARTH,
		SetCityProductionScript.PROJECT_ID_BUILD_POTTERY_WORKSHOP,
		SetCityProductionScript.PROJECT_ID_BUILD_STOREHOUSE_LEDGER,
		SetCityProductionScript.PROJECT_ID_BUILD_STORAGE_HALL,
		SetCityProductionScript.PROJECT_ID_BUILD_WEAVER_HUT,
		SetCityProductionScript.PROJECT_ID_BUILD_MUDBRICK_HOUSING,
		SetCityProductionScript.PROJECT_ID_BUILD_ARCHIVE_HUT,
		SetCityProductionScript.PROJECT_ID_BUILD_ARMORY,
	]
	var pi = 0
	while pi < stack_projects.size():
		var pid: String = str(stack_projects[pi])
		_check(
			gs.try_apply(SetCityProductionScript.make(0, city_id, pid))["accepted"],
			"stack start %s" % pid
		)
		_deliver_current_project(gs)
		pi = pi + 1

	var cy = gs.scenario.city_by_id(city_id)
	_check(cy.building_ids.size() == 9, "stack palace plus eight buildings")
	var brk_stack: Dictionary = CityYieldsScript.yield_breakdown_for_city(gs.scenario, cy)
	var bld_stack: Dictionary = brk_stack["buildings"] as Dictionary
	_check(CityYieldsScript.get_yield(bld_stack, "food") == 2, "stack buildings +2 food")
	_check(CityYieldsScript.get_yield(bld_stack, "production") == 2, "stack buildings +2 production")
	_check(CityYieldsScript.get_yield(bld_stack, "coin") == 5, "stack palace+ledger+weaver +5 coin")
	_check(CityYieldsScript.get_yield(bld_stack, "science") == 3, "stack palace+archive +3 science")
	_check(int(brk_stack.get("housing", -1)) == 2, "stack +2 housing recorded")

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
