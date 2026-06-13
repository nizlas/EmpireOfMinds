# Headless: godot --headless --path game -s res://domain/tests/test_science_availability.gd
# Phase 5.1.12b — available_for follows ProgressDefinitions tree order; locked/completed lists alphabetical.
extends SceneTree

const ProgressStateScript = preload("res://domain/progress_state.gd")
const ScienceAvailabilityScript = preload("res://domain/science_availability.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var empty_done = ScienceAvailabilityScript.completed_for(null, 0)
	var empty_avail = ScienceAvailabilityScript.available_for(null, 0)
	var empty_locked = ScienceAvailabilityScript.locked_for(null, 0)
	_check(empty_done.is_empty(), "null state completed empty")
	_check(empty_avail.is_empty(), "null state available empty")
	_check(empty_locked.is_empty(), "null state locked empty")
	_check(
		not ScienceAvailabilityScript.is_available(null, 0, "foraging_systems"),
		"null state not available"
	)

	var def = ProgressStateScript.with_default_unlocks_for_players([0])
	var start_avail = ScienceAvailabilityScript.available_for(def, 0)
	var exp_start: Array[String] = [
		"foraging_systems",
		"stone_tools",
		"controlled_fire",
		"oral_surveying",
	]
	_check(start_avail.size() == 4, "four starting sciences available")
	_check(start_avail == exp_start, "starting list tree order")

	_check(
		ScienceAvailabilityScript.is_available(def, 0, "foraging_systems"),
		"foraging available default"
	)
	_check(not ScienceAvailabilityScript.is_available(def, 0, "animal_tracking"), "animal locked")
	_check(
		not ScienceAvailabilityScript.is_available(def, 0, "seasonal_calendars"),
		"seasonal locked default"
	)

	var locked0 = ScienceAvailabilityScript.locked_for(def, 0)
	_check(locked0.size() == 15, "fifteen locked at start")

	var ps_f = def.with_progress_id_completed(0, "foraging_systems")
	_check(
		ScienceAvailabilityScript.is_available(ps_f, 0, "textile_work"),
		"textile after foraging"
	)
	_check(
		not ScienceAvailabilityScript.is_available(ps_f, 0, "animal_tracking"),
		"animal still needs oral"
	)
	_check(
		not ScienceAvailabilityScript.is_available(ps_f, 0, "seasonal_calendars"),
		"seasonal needs controlled_fire too"
	)

	var ps_fo = ps_f.with_progress_id_completed(0, "oral_surveying")
	_check(
		ScienceAvailabilityScript.is_available(ps_fo, 0, "animal_tracking"),
		"animal after foraging oral"
	)

	var ps_fc = def.with_progress_id_completed(0, "foraging_systems").with_progress_id_completed(
		0,
		"controlled_fire"
	)
	_check(
		ScienceAvailabilityScript.is_available(ps_fc, 0, "seasonal_calendars"),
		"seasonal after foraging fire"
	)

	var ps_done_textile = ps_f.with_progress_id_completed(0, "textile_work")
	_check(
		not ScienceAvailabilityScript.is_available(ps_done_textile, 0, "textile_work"),
		"completed not available"
	)
	var c_done = ScienceAvailabilityScript.completed_for(ps_done_textile, 0)
	_check(c_done.size() == 2, "completed two sciences")
	_check(c_done[0] == "foraging_systems" and c_done[1] == "textile_work", "completed alpha order")

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
