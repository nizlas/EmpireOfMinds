# Headless: City View unit display adapter (presentation only).
extends SceneTree

const UnitDisplayScript = preload("res://presentation/city_view_unit_display.gd")
const OverlayScript = preload("res://presentation/city_view_prototype_overlay.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_no_city_founded_baseline_units()
	_test_new_game_available_units()
	_test_without_city_selection()
	_test_before_stone_tools_no_worker()
	_test_after_stone_tools_worker()
	_test_tracker_and_cart_unlock_gating()
	_test_slinger_never_appears()
	_test_ordering_after_progress_unlocks()
	_test_unit_stats_and_order()
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
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _make_founded_capital(select_city: bool = true) -> Dictionary:
	var gs = GameStateScript.make_tiny_test_state()
	var city_id: int = gs.scenario.peek_next_city_id()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital")
	var sel = SelectionStateScript.new()
	if select_city:
		sel.select_city(city_id)
	return {"gs": gs, "city_id": city_id, "sel": sel}


func _row_ids(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	var i: int = 0
	while i < rows.size():
		out.append(str(rows[i].get("id", "")))
		i += 1
	return out


func _test_no_city_founded_baseline_units() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var sel = SelectionStateScript.new()
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "no city founded: available units are not empty")
	_check(available_ids[0] == "unit_warrior", "no city: warrior first")
	_check(available_ids[1] == "unit_settler", "no city: settler second")


func _test_new_game_available_units() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "city founded: available units are exactly two")
	_check(available_ids[0] == "unit_warrior", "warrior first")
	_check(available_ids[1] == "unit_settler", "settler second")


func _test_without_city_selection() -> void:
	var setup: Dictionary = _make_founded_capital(false)
	var gs = setup["gs"]
	var sel = setup["sel"]
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "available units without city selection still lists baseline")
	_check(available_ids.has("unit_warrior"), "no selection includes Warrior")
	_check(available_ids.has("unit_settler"), "no selection includes Settler")


func _test_before_stone_tools_no_worker() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(not available_ids.has("unit_worker"), "Worker hidden before stone_tools")


func _test_after_stone_tools_worker() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "complete stone_tools")
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 3, "three available units after stone_tools")
	_check(available_ids[0] == "unit_warrior", "warrior remains first after stone_tools")
	_check(available_ids[1] == "unit_settler", "settler remains second after stone_tools")
	_check(available_ids[2] == "unit_worker", "worker third after stone_tools")
	_check(
		OverlayScript.available_unit_rows(gs, sel).size() == available_ids.size(),
		"overlay wrapper matches adapter after stone_tools",
	)


func _test_tracker_and_cart_unlock_gating() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var before_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(not before_ids.has("unit_tracker_scout"), "tracker hidden before unlock")
	_check(not before_ids.has("unit_cart_support"), "cart hidden before unlock")

	gs.progress_state = gs.progress_state.with_target_unlocked(0, "unit", "tracker")
	var tracker_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(tracker_ids.has("unit_tracker_scout"), "tracker appears after canonical unlock")
	_check(not tracker_ids.has("unit_cart_support"), "cart still hidden without unlock")

	gs.progress_state = gs.progress_state.with_target_unlocked(0, "unit", "cart")
	var cart_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(cart_ids.has("unit_cart_support"), "cart appears after canonical unlock")


func _test_slinger_never_appears() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "stone_tools for slinger check")
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(not available_ids.has("unit_slinger"), "Slinger never appears in Available Units")


func _test_ordering_after_progress_unlocks() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "stone_tools")
	_check(gs.try_apply(CompleteProgressScript.make(0, "foraging_systems"))["accepted"], "foraging")
	_check(gs.try_apply(CompleteProgressScript.make(0, "oral_surveying"))["accepted"], "oral")
	_check(gs.try_apply(CompleteProgressScript.make(0, "animal_tracking"))["accepted"], "animal_tracking")
	_check(gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"], "controlled_fire")
	_check(gs.try_apply(CompleteProgressScript.make(0, "timber_working"))["accepted"], "timber")
	_check(gs.try_apply(CompleteProgressScript.make(0, "wheelwrighting"))["accepted"], "wheelwrighting")

	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() >= 5, "baseline plus worker tracker cart listed")
	_check(available_ids[0] == "unit_warrior", "ordering warrior first")
	_check(available_ids[1] == "unit_settler", "ordering settler second")
	_check(available_ids[2] == "unit_worker", "ordering worker third (stone_tools)")
	_check(available_ids[3] == "unit_tracker_scout", "ordering tracker fourth (animal_tracking)")
	_check(available_ids[4] == "unit_cart_support", "ordering cart fifth (wheelwrighting)")


func _test_unit_stats_and_order() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var warrior_row: Dictionary = {}
	var available: Array[Dictionary] = UnitDisplayScript.available_unit_rows(gs, sel)
	var ri: int = 0
	while ri < available.size():
		if str(available[ri].get("id", "")) == "unit_warrior":
			warrior_row = available[ri]
		ri += 1
	_check(int(warrior_row.get("hp", 0)) == 100, "warrior hp from UnitDefinitions")
	_check(int(warrior_row.get("production_cost", 0)) == 40, "warrior cost from UnitDefinitions")
	_check(
		str(warrior_row.get("name", "")) == UnitDefinitionsScript.get_unit("unit_warrior").get("name", ""),
		"warrior display name from UnitDefinitions",
	)
	_check(UnitDisplayScript.format_unit_row_line(warrior_row) == "Warrior", "formatted line is display name only")
