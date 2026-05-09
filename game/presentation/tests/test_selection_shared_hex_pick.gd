# Headless: **SelectionController.plan_shared_hex_pick** — city ↔ own-unit alternation on same hex.
# Usage: godot --headless --path game -s res://presentation/tests/test_selection_shared_hex_pick.gd
extends SceneTree

const SelectionControllerScript = preload("res://presentation/selection_controller.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	var NoneQ = SelectionControllerScript.SHARED_HEX_TRACK_NONE
	var p: Dictionary
	p = SelectionControllerScript.plan_shared_hex_pick(NoneQ, 0, 0, 3, -2, 100, [7, 11])
	_check(
		str(p["pick"]) == "city" and int(p["next_phase"]) == 1,
		"first visit: city then phase 1"
	)
	_check(int(p["next_track_q"]) == 3 and int(p["next_track_r"]) == -2, "track stores click hex")
	p = SelectionControllerScript.plan_shared_hex_pick(
		int(p["next_track_q"]),
		int(p["next_track_r"]),
		int(p["next_phase"]),
		3,
		-2,
		100,
		[7, 11]
	)
	_check(str(p["pick"]) == "unit" and int(p["unit_id"]) == 7, "second click: lowest own unit id")
	_check(int(p["next_phase"]) == 0, "after unit, next prefer city")
	p = SelectionControllerScript.plan_shared_hex_pick(
		int(p["next_track_q"]),
		int(p["next_track_r"]),
		int(p["next_phase"]),
		3,
		-2,
		100,
		[7, 11]
	)
	_check(str(p["pick"]) == "city", "third click: city again")
	_check(int(p["next_phase"]) == 1, "phase after city")
	# New hex resets to city first even if old phase was mid-cycle
	p = SelectionControllerScript.plan_shared_hex_pick(3, -2, 1, 9, 1, 200, [5])
	_check(
		str(p["pick"]) == "city" and int(p["city_id"]) == 200 and int(p["next_phase"]) == 1,
		"different hex resets to city-first"
	)
	_check(int(p["next_track_q"]) == 9 and int(p["next_track_r"]) == 1, "track moves to new hex")
	# Phase 1 with empty own list: stay on city (defensive)
	p = SelectionControllerScript.plan_shared_hex_pick(1, 1, 1, 1, 1, 50, [])
	_check(str(p["pick"]) == "city" and int(p["city_id"]) == 50, "empty own units at unit phase falls back to city")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d selection_shared_hex_pick" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
