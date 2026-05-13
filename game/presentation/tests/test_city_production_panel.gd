# Headless: godot --headless --path game -s res://presentation/tests/test_city_production_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_guard_panel_source_has_no_forbidden_imports()
	var sel = SelectionStateScript.new()

	var vm0 = CityProductionPanelScript.compute_view_model(null, sel)
	_check(not bool(vm0.get("visible", true)), "null game_state hides")
	_check(not bool(vm0.get("show_yields", true)), "null game_state no yields")
	_check((vm0.get("yields", {}) as Dictionary).is_empty(), "null game_state yields empty")

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
	_check(str(vm_idle.get("header_title", "")) == "Capital", "header uses founded city name")
	_check(bool(vm_idle.get("show_yields", false)), "yields visible for founded capital")
	var y_idle = vm_idle.get("yields", {}) as Dictionary
	_check(int(y_idle.get("food", -1)) == 2, "tiny plains capital food 2")
	_check(int(y_idle.get("production", -1)) == 1, "tiny plains capital production 1")
	_check(int(y_idle.get("science", -1)) == 1, "palace science 1")
	_check(int(y_idle.get("coin", -1)) == 1, "palace coin 1")
	_check(str(vm_idle.get("yields_line", "")).begins_with("Yields:"), "yields line prefix")
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
	_check(
		bool(vm_wp.get("show_yields", false)),
		"yields still computed for opponent city view"
	)

	# Phase 5.1.16e — CityYields via compute_view_model (prototype terrain fixtures).
	var sel_y = SelectionStateScript.new()
	var m_pr = HexMapScript.make_prototype_play_map()
	var u_pr = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var c_cap_g = CityScript.new(1, 0, HexCoordScript.new(1, 0), null, "GrassCap", true, ["palace"])
	var sc_g = ScenarioScript.new(m_pr, u_pr, [c_cap_g], 80, 90, null)
	var gs_g = GameStateScript.new(sc_g)
	sel_y.select_city(1)
	var vm_g = CityProductionPanelScript.compute_view_model(gs_g, sel_y)
	var yg = vm_g.get("yields", {}) as Dictionary
	_check(int(yg.get("food", -1)) == 2, "grassland flat capital food 2")
	_check(int(yg.get("production", -1)) == 1, "grassland flat production 1")
	_check(int(yg.get("science", -1)) == 1, "capital palace science 1")
	_check(int(yg.get("coin", -1)) == 1, "capital palace coin 1")

	var c_plain_nc = CityScript.new(2, 0, HexCoordScript.new(2, 0), null, "B", false, [])
	var sc_nc = ScenarioScript.new(m_pr, u_pr, [c_cap_g, c_plain_nc], 80, 91, null)
	var gs_nc = GameStateScript.new(sc_nc)
	sel_y.clear()
	sel_y.select_city(2)
	var vm_nc = CityProductionPanelScript.compute_view_model(gs_nc, sel_y)
	var yn = vm_nc.get("yields", {}) as Dictionary
	_check(int(yn.get("food", -1)) == 2, "grassland flat non-capital food 2")
	_check(int(yn.get("production", -1)) == 1, "grassland flat non-capital production 1")
	_check(int(yn.get("science", -1)) == 0, "no palace no science yield")
	_check(int(yn.get("coin", -1)) == 0, "no palace no coin yield")

	var c_hill_cap = CityScript.new(
		1,
		0,
		HexCoordScript.new(7, -7),
		null,
		"HillCap",
		true,
		["palace"]
	)
	var sc_h = ScenarioScript.new(m_pr, u_pr, [c_hill_cap], 81, 92, null)
	var gs_h = GameStateScript.new(sc_h)
	sel_y.clear()
	sel_y.select_city(1)
	var vm_h = CityProductionPanelScript.compute_view_model(gs_h, sel_y)
	var yh = vm_h.get("yields", {}) as Dictionary
	_check(int(yh.get("production", -1)) == 2, "plains hills capital production 2")
	_check(int(yh.get("science", -1)) == 1 and int(yh.get("coin", -1)) == 1, "hill capital palace sci coin")

	var c_wp = CityScript.new(5, 0, HexCoordScript.new(1, -1), null, "", true, ["palace"])
	var c_np = CityScript.new(6, 0, HexCoordScript.new(0, -1), null, "", false, [])
	var m_t = HexMapScript.make_tiny_test_map()
	var sc_pal = ScenarioScript.new(m_t, u_pr, [c_wp, c_np], 82, 93, null)
	var gs_pal = GameStateScript.new(sc_pal)
	sel_y.clear()
	sel_y.select_city(5)
	var y_wp = (CityProductionPanelScript.compute_view_model(gs_pal, sel_y).get("yields", {}) as Dictionary)
	sel_y.clear()
	sel_y.select_city(6)
	var y_np = (CityProductionPanelScript.compute_view_model(gs_pal, sel_y).get("yields", {}) as Dictionary)
	_check(int(y_wp.get("production", -1)) == 1, "capital palace production 1 on plains flat")
	_check(int(y_np.get("production", -1)) == 1, "non-capital same production without palace")
	_check(
		int(y_wp.get("science", -1)) == 1 and int(y_np.get("science", -1)) == 0,
		"palace adds science not production bump"
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
