# Headless: godot --headless --path game -s res://presentation/tests/test_city_production_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")
const CityViewStateScript = preload("res://presentation/city_view_state.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_guard_panel_source_has_no_forbidden_imports()
	var sel = SelectionStateScript.new()

	var vm0 = CityProductionPanelScript.compute_view_model(null, sel)
	_check(not bool(vm0.get("visible", true)), "null game_state hides")
	_check(not bool(vm0.get("show_yields", true)), "null game_state no yields")
	_check((vm0.get("yields", {}) as Dictionary).is_empty(), "null game_state yields empty")
	_check(str(vm0.get("breakdown_line", "x")).is_empty(), "null game_state no breakdown_line")

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
	_check(str(vm_idle.get("hub_brand", "")) == "City Hub", "vm hub_brand City Hub")
	_check(str(vm_idle.get("identity_line", "")).find("Capital") >= 0, "identity shows city name")
	_check(str(vm_idle.get("identity_line", "")).find("Pop ") >= 0, "identity shows Pop")
	_check(str(vm_idle.get("manage_citizens_button_text", "")).find("Manage Citizens") >= 0, "vm manage citizens label")
	_check(not bool(vm_idle.get("manage_citizens_disabled", true)), "vm manage citizens enabled own city")
	_check(str(vm_idle.get("close_button_text", "")) == "Close", "vm close label")
	_check(bool(vm_idle.get("show_yields", false)), "yields visible for founded capital")
	var y_idle = vm_idle.get("yields", {}) as Dictionary
	_check(int(y_idle.get("food", -1)) == 3, "tiny plains capital food includes one worked neighbor")
	_check(int(y_idle.get("production", -1)) == 2, "tiny plains capital production includes worked plains")
	_check(int(y_idle.get("science", -1)) == 1, "palace science 1")
	_check(int(y_idle.get("coin", -1)) == 1, "palace coin 1")
	_check(str(vm_idle.get("yields_line", "")).begins_with("Yields:"), "yields line prefix")
	var gl_idle = str(vm_idle.get("growth_line", ""))
	_check(gl_idle.begins_with("Growth:"), "growth_line prefix")
	_check(gl_idle.find("/ 15") >= 0, "growth threshold pop1")
	_check(gl_idle.find("(+1/turn)") >= 0, "tiny capital surplus +1 display")
	var br_idle = str(vm_idle.get("breakdown_line", ""))
	_check(br_idle.length() > 0, "founded capital has breakdown_line")
	_check(br_idle.find("Center") >= 0, "breakdown mentions Center")
	_check(br_idle.find("Buildings") >= 0, "breakdown mentions Buildings")
	_check(br_idle.find("Worked") >= 0, "breakdown mentions Worked")
	_check(br_idle.find("2F") >= 0, "breakdown center food matches city center floor")
	_check(br_idle.find("1S") >= 0 and br_idle.find("1C") >= 0, "breakdown palace science and coin")
	_check(br_idle.find("1P") >= 0, "breakdown includes production tokens")
	var opts_idle = vm_idle.get("options", []) as Array
	_check(opts_idle.size() == 2, "warrior and settler baseline empty city")
	var a0i = (opts_idle[0] as Dictionary)["action"] as Dictionary
	var a1i = (opts_idle[1] as Dictionary)["action"] as Dictionary
	_check(str(a0i.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR, "first warrior")
	_check(str(a1i.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER, "second settler")

	var cvs_plan_vm = CityViewStateScript.new()
	cvs_plan_vm.enter_planning()
	var vm_plan_own = CityProductionPanelScript.compute_view_model(gs2, sel, cvs_plan_vm)
	_check(bool(vm_plan_own.get("planning_active", false)), "vm planning_active when CityViewState planning")
	_check(str(vm_plan_own.get("planning_banner_text", "")).find("Planning") >= 0, "vm planning_banner_text")
	_check(bool(vm_plan_own.get("done_planning_visible", false)), "vm done_planning_visible")
	_check(bool(vm_plan_own.get("manage_citizens_disabled", false)), "vm manage disabled while planning")

	_check(
		gs2.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"],
		"controlled_fire still completable"
	)
	var vm_two = CityProductionPanelScript.compute_view_model(gs2, sel)
	var opts_two = vm_two.get("options", []) as Array
	_check(opts_two.size() == 3, "warrior settler hearth after CF")
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
		ids_two[2] == SetCityProductionScript.PROJECT_ID_BUILD_HEARTH,
		"hearth third after CF"
	)
	_check(
		str((opts_two[2] as Dictionary).get("label", "")).begins_with("Build "),
		"hearth option uses Build prefix"
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
	_check(str(vm_g.get("growth_line", "")).find("(+0/turn)") >= 0, "surplus<=0 shows +0/turn")
	_check(int(yg.get("production", -1)) == 1, "grassland flat production 1")
	_check(int(yg.get("science", -1)) == 1, "capital palace science 1")
	_check(int(yg.get("coin", -1)) == 1, "capital palace coin 1")

	var c_plain_nc = CityScript.new(2, 0, HexCoordScript.new(-1, 4), null, "B", false, [])
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
		HexCoordScript.new(8, -2),
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

	# 5.1.17g / **5.1.17i** — hub labels + **Manage Citizens** / **Done** / **Close** + **CityViewState**.
	var gs_hub = GameStateScript.make_tiny_test_state()
	_check(gs_hub.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "hub skeleton: found city")
	var sel_hub = SelectionStateScript.new()
	sel_hub.select_city(1)
	var scen_hub = gs_hub.scenario
	var n_hub_cities = gs_hub.scenario.cities().size()
	var hub_cvs = CityViewStateScript.new()
	var panel = CityProductionPanelScript.new()
	get_root().add_child(panel)
	panel.game_state = gs_hub
	panel.selection = sel_hub
	panel.city_view_state = hub_cvs
	panel.refresh()
	_check(panel.visible, "hub panel visible with city selection")
	_check(panel._title_label.text == "City Hub", "panel shows City Hub title")
	_check(panel._identity_label.text.find("Pop ") >= 0, "panel identity shows population")
	_check(not panel._manage_citizens_btn.disabled, "Manage Citizens enabled own city")
	_check(panel._manage_citizens_btn.text.find("Manage Citizens") >= 0, "Manage Citizens label")
	_check(not panel._done_planning_btn.visible, "Done hidden in NORMAL")
	_check(panel._close_btn.text == "Close", "Close button text")
	panel._on_manage_citizens_pressed()
	_check(hub_cvs.is_planning(), "Manage Citizens enters PLANNING")
	panel.refresh()
	_check(panel._planning_banner_label.visible, "planning banner visible")
	_check(str(panel._planning_banner_label.text).find("Planning") >= 0, "planning banner mentions Planning")
	_check(panel._manage_citizens_btn.disabled, "Manage Citizens disabled while planning")
	_check(panel._done_planning_btn.visible, "Done visible in PLANNING")
	panel._on_done_planning_pressed()
	_check(not hub_cvs.is_planning(), "Done exits PLANNING")
	_check(sel_hub.has_city(), "Done keeps city selected")
	panel.refresh()
	_check(not panel._planning_banner_label.visible, "banner hides after Done")
	panel._on_manage_citizens_pressed()
	_check(hub_cvs.is_planning(), "re-enter PLANNING for Close test")
	panel._on_hub_close_pressed()
	_check(not sel_hub.has_city(), "Close clears city selection")
	_check(not hub_cvs.is_planning(), "Close resets planning")
	_check(gs_hub.scenario == scen_hub, "Close does not replace scenario")
	_check(gs_hub.scenario.cities().size() == n_hub_cities, "Close does not add/remove cities")
	_check(not panel.visible, "panel hides after Close")
	panel.queue_free()

	var vm_plan = CityProductionPanelScript.compute_view_model(gs_hub, sel_hub, hub_cvs)
	_check(not bool(vm_plan.get("visible", true)), "no city selection hides even if cvs exists")

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
