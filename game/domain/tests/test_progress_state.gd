# Headless: godot --headless --path game -s res://domain/tests/test_progress_state.gd
extends SceneTree

const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var empty = ProgressStateScript.new({})
	_check(empty.owner_ids().size() == 0, "new({}) owner_ids empty")
	_check(not empty.has_unlocked_target(0, "city_project", "produce_unit:warrior"), "empty no unlock")

	var def01 = ProgressStateScript.with_default_unlocks_for_players([0, 1])
	var oids = def01.owner_ids()
	_check(oids.size() == 2 and int(oids[0]) == 0 and int(oids[1]) == 1, "default owners 0 1")
	_check(
		def01.has_unlocked_target(0, "city_project", "produce_unit:warrior"),
		"p0 warrior"
	)
	_check(
		def01.has_unlocked_target(1, "city_project", "produce_unit:warrior"),
		"p1 warrior"
	)
	_check(
		not def01.has_unlocked_target(0, "city_project", "produce_unit:settler"),
		"no settler"
	)
	_check(
		not def01.has_unlocked_target(2, "city_project", "produce_unit:warrior"),
		"unknown owner no warrior"
	)

	var ut0 = def01.unlocked_targets_for(0)
	_check(ut0.size() == 1, "one target p0")
	var inner0 = ut0[0] as Dictionary
	inner0["target_id"] = "mutated"
	var ut0b = def01.unlocked_targets_for(0)
	var inner0b = ut0b[0] as Dictionary
	_check(
		str(inner0b["target_id"]) == "produce_unit:warrior",
		"deep dup after outer mutate"
	)
	ut0b.append({"target_type": "x", "target_id": "y"})
	var ut0c = def01.unlocked_targets_for(0)
	_check(ut0c.size() == 1, "deep dup after array append")

	var base = ProgressStateScript.new({})
	var with1 = base.with_target_unlocked(0, "city_project", "produce_unit:settler")
	_check(not with1.equals(base), "with unlock new state")
	_check(not base.has_unlocked_target(0, "city_project", "produce_unit:settler"), "orig unchanged")
	_check(
		with1.has_unlocked_target(0, "city_project", "produce_unit:settler"),
		"new has settler"
	)

	var s0 = ProgressStateScript.with_default_unlocks_for_players([0])
	var s_dup = s0.with_target_unlocked(0, "city_project", "produce_unit:warrior")
	_check(s0.equals(s_dup), "re-unlock warrior idempotent")

	var out_order = ProgressStateScript.new(
		{
			1: {"unlocked_targets": []},
			0: {"unlocked_targets": []},
		}
	)
	var o2 = out_order.owner_ids()
	_check(
		o2.size() == 2 and int(o2[0]) == 0 and int(o2[1]) == 1,
		"owner_ids sorted from key order 1,0"
	)

	_check(not empty.equals(null), "equals null false")
	_check(not empty.equals("x"), "equals string false")
	var eq_a = ProgressStateScript.with_default_unlocks_for_players([0, 1])
	var eq_b = ProgressStateScript.with_default_unlocks_for_players([0, 1])
	_check(eq_a.equals(eq_b), "equiv equals true")
	var diff = ProgressStateScript.new({})
	_check(not eq_a.equals(diff), "diff equals false")

	var only_ut = ProgressStateScript.new({})
	_check(only_ut.completed_progress_ids_for(0).size() == 0, "new{} completed empty")
	_check(not only_ut.has_completed_progress(0, "foraging_systems"), "new{} not completed")

	var wpc = only_ut.with_progress_id_completed(0, "foraging_systems")
	_check(not wpc.equals(only_ut), "completion new state")
	_check(not only_ut.has_completed_progress(0, "foraging_systems"), "orig no completion after wpc")
	_check(wpc.has_completed_progress(0, "foraging_systems"), "wpc has foraging")

	var wpc2 = wpc.with_progress_id_completed(0, "foraging_systems")
	_check(wpc.equals(wpc2), "idem completion equals")

	var order_ab = ProgressStateScript.new({})
	var oa = order_ab.with_progress_id_completed(0, "stone_tools")
	var oab = oa.with_progress_id_completed(0, "foraging_systems")
	var ids_ab = oab.completed_progress_ids_for(0)
	_check(
		ids_ab.size() == 2
		and str(ids_ab[0]) == "foraging_systems"
		and str(ids_ab[1]) == "stone_tools",
		"completed ids sorted"
	)

	var cpd = wpc.completed_progress_ids_for(0)
	cpd.append("bogus")
	var cpd2 = wpc.completed_progress_ids_for(0)
	_check(cpd2.size() == 1 and str(cpd2[0]) == "foraging_systems", "completed deep dup")

	var ut_after = wpc.with_target_unlocked(0, "building", "x")
	_check(ut_after.has_completed_progress(0, "foraging_systems"), "unlock preserves completed")

	var same_unlocks = ProgressStateScript.new(
		{0: {"unlocked_targets": [{"target_type": "t", "target_id": "i"}], "completed_progress_ids": ["a"]}}
	)
	var same_unlocks_b = ProgressStateScript.new(
		{0: {"unlocked_targets": [{"target_type": "t", "target_id": "i"}], "completed_progress_ids": ["a"]}}
	)
	_check(same_unlocks.equals(same_unlocks_b), "equals matches both fields")

	var diff_cp = ProgressStateScript.new(
		{0: {"unlocked_targets": [{"target_type": "t", "target_id": "i"}], "completed_progress_ids": ["b"]}}
	)
	_check(not same_unlocks.equals(diff_cp), "equals false diff completed")

	var legacy = ProgressStateScript.new({0: {"unlocked_targets": []}})
	_check(legacy.completed_progress_ids_for(0).size() == 0, "legacy constructor completed empty")

	var messy = ProgressStateScript.new(
		{0: {"unlocked_targets": [], "completed_progress_ids": ["b", "a", "a"]}}
	)
	var mid = messy.completed_progress_ids_for(0)
	_check(mid.size() == 2 and str(mid[0]) == "a" and str(mid[1]) == "b", "completed normalized a b")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
