# Headless: City View unit display adapter (presentation only).
extends SceneTree

const UnitDisplayScript = preload("res://presentation/city_view_unit_display.gd")
const OverlayScript = preload("res://presentation/city_view_prototype_overlay.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_new_game_available_units()
	_test_without_city_selection_fallback()
	_test_after_stone_tools_no_worker()
	_test_matches_legal_actions()
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


func _blob_has_non_baseline_unit(rows: Array[Dictionary]) -> bool:
	var blocked: PackedStringArray = PackedStringArray([
		"unit_worker",
		"unit_slinger",
		"unit_tracker_scout",
		"unit_cart_support",
	])
	var i: int = 0
	while i < rows.size():
		var row_id: String = str(rows[i].get("id", ""))
		var name: String = str(rows[i].get("name", ""))
		if blocked.has(row_id):
			return true
		if name.find("Slinger") >= 0 or name.find("Tracker") >= 0 or name.find("Cart") >= 0:
			return true
		i += 1
	return false


func _test_new_game_available_units() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var city_id: int = int(setup["city_id"])

	var available: Array[Dictionary] = UnitDisplayScript.available_unit_rows(gs, sel)
	var available_ids: Array[String] = _row_ids(available)
	_check(available_ids.size() == 2, "new game available units are exactly two")
	_check(available_ids[0] == "unit_warrior", "warrior first in legal project order")
	_check(available_ids[1] == "unit_settler", "settler second in legal project order")
	_check(not _blob_has_non_baseline_unit(available), "available excludes worker tracker cart slinger")


func _test_without_city_selection_fallback() -> void:
	var setup: Dictionary = _make_founded_capital(false)
	var gs = setup["gs"]
	var sel = setup["sel"]
	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "available units without city selection uses owner city fallback")
	_check(available_ids.has("unit_warrior"), "fallback includes Warrior")
	_check(available_ids.has("unit_settler"), "fallback includes Settler")


func _test_after_stone_tools_no_worker() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "complete stone_tools")

	var available_ids: Array[String] = _row_ids(UnitDisplayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "still only two available units after stone_tools")
	_check(available_ids.has("unit_warrior"), "warrior still available after stone_tools")
	_check(available_ids.has("unit_settler"), "settler still available after stone_tools")
	_check(not available_ids.has("unit_worker"), "Worker not available without production project")


func _test_matches_legal_actions() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var city_id: int = int(setup["city_id"])
	var available: Array[Dictionary] = UnitDisplayScript.available_unit_rows(gs, sel)

	_check(
		OverlayScript.available_unit_rows(gs, sel).size() == available.size(),
		"overlay wrapper matches adapter",
	)

	var legal_projects: PackedStringArray = PackedStringArray()
	var legal: Array = LegalActionsScript.for_current_player(gs)
	var li: int = 0
	while li < legal.size():
		var action: Dictionary = legal[li] as Dictionary
		if (
			str(action.get("action_type", "")) == SetCityProductionScript.ACTION_TYPE
			and int(action.get("city_id", -1)) == city_id
			and str(action.get("project_id", "")).begins_with("produce_unit:")
		):
			legal_projects.append(str(action.get("project_id", "")))
		li += 1
	legal_projects.sort()
	var row_projects: PackedStringArray = PackedStringArray()
	var pi: int = 0
	while pi < available.size():
		row_projects.append(str(available[pi].get("project_id", "")))
		pi += 1
	row_projects.sort()
	_check(row_projects == legal_projects, "available project ids match LegalActions exactly")


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
