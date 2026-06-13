# Headless: godot --headless --path game -s res://presentation/tests/test_science_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const SciencePanelScript = preload("res://presentation/science_panel.gd")
const SetCurrentResearchScript = preload("res://domain/actions/set_current_research.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")

var _total = 0
var _any_fail = false


func _has_row(rows: Array, id: String) -> bool:
	var i = 0
	while i < rows.size():
		if str((rows[i] as Dictionary).get("id", "")) == id:
			return true
		i = i + 1
	return false


func _row_by_id(rows: Array, id: String) -> Dictionary:
	var j = 0
	while j < rows.size():
		var d = rows[j] as Dictionary
		if str(d.get("id", "")) == id:
			return d
		j = j + 1
	return {}


func _check_label_array_eq(a: Array, b: Array, message: String) -> void:
	_check(a.size() == b.size(), "%s (size)" % message)
	var k = 0
	while k < a.size():
		_check(str(a[k]) == str(b[k]), "%s [%d]" % [message, k])
		k = k + 1


func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var vm0 = SciencePanelScript.compute_view_model(gs)
	_check(bool(vm0.get("visible", false)), "panel visible with game_state")
	_check(int(vm0.get("current_player_id", -2)) == 0, "p0")
	var rows0 = vm0.get("available_rows", []) as Array
	_check(_has_row(rows0, "controlled_fire"), "has controlled_fire")
	_check(_has_row(rows0, "foraging_systems"), "has foraging_systems")
	_check(_has_row(rows0, "oral_surveying"), "has oral_surveying")
	_check(_has_row(rows0, "stone_tools"), "has stone_tools")
	_check(rows0.size() == 4, "exactly four starters")
	_check(str(vm0.get("explicit_research_id", "x")) == "", "no explicit yet")
	_check(str(vm0.get("effective_research_id", "")) == "foraging_systems", "auto first tree order")
	_check(str(vm0.get("target_heading", "")).begins_with("Auto: "), "auto heading")
	_check(int(vm0.get("progress", -1)) == 0, "zero progress on effective")
	_check(int(vm0.get("cost", -1)) == 6, "cf cost")
	var locked0 = vm0.get("locked_rows", []) as Array
	_check(locked0.size() == 15, "fresh game locked count")
	_check(int(vm0.get("locked_more_count", -1)) == 9, "locked clip remainder 15-6")
	_check(str((locked0[0] as Dictionary).get("id", "")) == "agrarian_practice", "locked order alphabetical")
	var at0 = _row_by_id(locked0, "animal_tracking")
	_check(not at0.is_empty(), "animal_tracking locked row exists")
	_check(
		str(at0.get("display", "")) == "Animal Tracking — Requires: Foraging Systems, Oral Surveying",
		"animal_tracking display"
	)
	_check_label_array_eq(
		at0.get("missing_prerequisite_labels", []) as Array,
		["Foraging Systems", "Oral Surveying"] as Array,
		"animal_tracking missing labels"
	)
	var sc0 = _row_by_id(locked0, "seasonal_calendars")
	_check(
		str(sc0.get("display", "")) == "Seasonal Calendars — Requires: Foraging Systems, Controlled Fire",
		"seasonal_calendars display"
	)
	var fs_row = _row_by_id(rows0, "foraging_systems")
	_check(bool(fs_row.get("is_auto_current", false)), "foraging marked auto")
	_check(not bool(fs_row.get("is_explicit_current", true)), "foraging not explicit")

	gs.try_apply(SetCurrentResearchScript.make(0, "stone_tools"))
	var vm1 = SciencePanelScript.compute_view_model(gs)
	_check(str(vm1.get("explicit_research_id", "")) == "stone_tools", "explicit stone_tools")
	_check(str(vm1.get("effective_research_id", "")) == "stone_tools", "effective matches")
	_check(str(vm1.get("target_heading", "")).begins_with("Researching: "), "researching heading")
	var rows1 = vm1.get("available_rows", []) as Array
	var st_row = _row_by_id(rows1, "stone_tools")
	_check(bool(st_row.get("is_explicit_current", false)), "stone explicit mark")
	_check(not bool(st_row.get("is_auto_current", true)), "stone not auto when explicit")
	_check((vm1.get("locked_rows", []) as Array).size() == 15, "pinned research does not change locked count")

	gs.try_apply(CompleteProgressScript.make(0, "foraging_systems"))
	var vm2 = SciencePanelScript.compute_view_model(gs)
	var rows2 = vm2.get("available_rows", []) as Array
	_check(not _has_row(rows2, "foraging_systems"), "completed drops from available")
	_check(_has_row(rows2, "textile_work"), "textile unlocked by foraging")
	_check(_has_row(rows2, "stone_tools"), "stone still available")
	var locked2 = vm2.get("locked_rows", []) as Array
	_check(locked2.size() == 14, "one fewer locked after one science completed")
	_check(int(vm2.get("locked_more_count", -1)) == 8, "locked clip 14-6")
	_check(not _has_row(locked2, "foraging_systems"), "completed not in locked")
	var at2 = _row_by_id(locked2, "animal_tracking")
	_check_label_array_eq(
		at2.get("missing_prerequisite_labels", []) as Array,
		["Oral Surveying"] as Array,
		"animal_tracking only oral missing after foraging"
	)
	var sc2 = _row_by_id(locked2, "seasonal_calendars")
	_check(
		str(sc2.get("display", "")) == "Seasonal Calendars — Requires: Controlled Fire",
		"seasonal only controlled fire missing after foraging"
	)

	gs.try_apply(CompleteProgressScript.make(0, "oral_surveying"))
	var vm3 = SciencePanelScript.compute_view_model(gs)
	var rows3 = vm3.get("available_rows", []) as Array
	var locked3 = vm3.get("locked_rows", []) as Array
	_check(_has_row(rows3, "animal_tracking"), "animal_tracking moves to available")
	_check(not _has_row(locked3, "animal_tracking"), "animal_tracking leaves locked")

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
