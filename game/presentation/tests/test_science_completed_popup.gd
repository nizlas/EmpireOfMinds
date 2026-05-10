# Headless: godot --headless --path game -s res://presentation/tests/test_science_completed_popup.gd
extends SceneTree

const ScienceCompletedPopupScript = preload("res://presentation/science_completed_popup.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var h = ScienceCompletedPopupScript.compute_view_model(null)
	_check(not bool(h.get("visible", true)), "null hidden")

	var entry_good: Dictionary = {
		"action_type": "science_completed",
		"result": "accepted",
		"actor_id": 0,
		"progress_id": "controlled_fire",
		"unlocked_targets": [
			{"target_type": "building", "target_id": "hearth"},
			{"target_type": "action", "target_id": "camp_clearing"},
		],
	}
	var vm = ScienceCompletedPopupScript.compute_view_model(entry_good)
	_check(bool(vm.get("visible", false)), "visible without train rows")
	_check(str(vm.get("title", "")) == "Science completed", "title")
	_check(str(vm.get("heading", "")) == "Controlled Fire", "heading")
	var body_s = str(vm.get("body", ""))
	_check(body_s.find("preserve flame") >= 0, "body contains curated phrase")
	_check(body_s.find("Hearths warm") >= 0, "body mentions hearths")
	_check(body_s.find("Settler") < 0 and body_s.find("settler") < 0, "body no settler")
	var prac = str(vm.get("practical", ""))
	_check(prac.find("Hearth") >= 0 and prac.find("Camp Clearing") >= 0, "practical survival bundle")
	_check(prac.find("Settler") < 0 and prac.find("Train") < 0, "practical no train settler")
	var ub = str(vm.get("unlock_block", ""))
	_check(ub.is_empty(), "no train unlock block for metadata-only delta")

	var entry_other: Dictionary = {
		"action_type": "science_completed",
		"result": "accepted",
		"progress_id": "stone_tools",
		"unlocked_targets": [
			{"target_type": "city_project", "target_id": "produce_unit:warrior"},
		],
	}
	var vm2 = ScienceCompletedPopupScript.compute_view_model(entry_other)
	_check(bool(vm2.get("visible", false)), "fallback visible")
	_check(str(vm2.get("heading", "")) == "Stone Tools", "humanized heading")

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
