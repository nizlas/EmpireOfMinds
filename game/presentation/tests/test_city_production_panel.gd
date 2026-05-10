# Headless: godot --headless --path game -s res://presentation/tests/test_city_production_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_guard_panel_source_has_no_forbidden_imports()
	var sel = SelectionStateScript.new()

	var vm0 = CityProductionPanelScript.compute_view_model(null, sel)
	_check(not bool(vm0.get("visible", true)), "null game_state hides")

	var gs_t = GameStateScript.make_tiny_test_state()
	var vm1 = CityProductionPanelScript.compute_view_model(gs_t, sel)
	_check(not bool(vm1.get("visible", true)), "no city selection hides")

	sel.select_city(999)
	var vm_miss = CityProductionPanelScript.compute_view_model(gs_t, sel)
	_check(not bool(vm_miss.get("visible", true)), "unknown city id hides")

	var gs2 = GameStateScript.make_tiny_test_state()
	var city_id = gs2.scenario.peek_next_city_id()
	_check(gs2.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found city for panel tests")
	_check(city_id == 1, "expected city id 1")
	sel.clear()
	sel.select_city(city_id)
	var vm_idle = CityProductionPanelScript.compute_view_model(gs2, sel)
	_check(bool(vm_idle.get("visible", false)), "idle city shows panel")
	var opts_idle = vm_idle.get("options", []) as Array
	_check(opts_idle.size() == 2, "warrior and settler baseline empty city")
	var a0i = (opts_idle[0] as Dictionary)["action"] as Dictionary
	var a1i = (opts_idle[1] as Dictionary)["action"] as Dictionary
	_check(str(a0i.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR, "first warrior")
	_check(str(a1i.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER, "second settler")

	_check(
		gs2.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"],
		"controlled_fire still completable"
	)
	var vm_two = CityProductionPanelScript.compute_view_model(gs2, sel)
	var opts_two = vm_two.get("options", []) as Array
	_check(opts_two.size() == 2, "still warrior and settler after CF")
	var ids_two: Array = []
	var ti = 0
	while ti < opts_two.size():
		var ax = (opts_two[ti] as Dictionary)["action"] as Dictionary
		ids_two.append(str(ax.get("project_id", "")))
		ti = ti + 1
	_check(
		ids_two[0] == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR,
		"stable sort warrior first"
	)
	_check(
		ids_two[1] == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER,
		"settler second"
	)

	_check(
		gs2.try_apply(SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR))[
			"accepted"
		],
		"set warrior production"
	)
	var vm_prog = CityProductionPanelScript.compute_view_model(gs2, sel)
	var st_busy = str(vm_prog.get("status", ""))
	_check(
		st_busy.find("Producing") >= 0 or st_busy.find("/") >= 0,
		"status shows production progress while building"
	)
	var opts_busy = vm_prog.get("options", []) as Array
	_check(opts_busy.is_empty(), "no new production choices while project active")

	_check(gs2.try_apply(EndTurnScript.make(0))["accepted"], "end turn P0 for wrong-player setup")
	sel.clear()
	sel.select_city(city_id)
	var vm_wp = CityProductionPanelScript.compute_view_model(gs2, sel)
	_check((vm_wp.get("options", []) as Array).is_empty(), "wrong player has no production buttons")
	_check(
		str(vm_wp.get("status", "")).find("Not your city") >= 0,
		"wrong player status explains ownership"
	)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _guard_panel_source_has_no_forbidden_imports() -> void:
	var path = "res://presentation/city_production_panel.gd"
	var f = FileAccess.open(path, FileAccess.READ)
	_check(f != null, "open city_production_panel.gd for import guard")
	var txt = f.get_as_text()
	_check(not txt.contains("city_project_definitions"), "panel must not reference city_project_definitions")
	_check(not txt.contains("effective_rules"), "panel must not reference effective_rules")


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
