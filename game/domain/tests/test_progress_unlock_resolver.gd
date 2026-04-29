# Headless: godot --headless --path game -s res://domain/tests/test_progress_unlock_resolver.gd
extends SceneTree

const ProgressUnlockResolverScript = preload("res://domain/progress_unlock_resolver.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var r_null = ProgressUnlockResolverScript.complete_progress(null, 0, "foraging_systems")
	_check(not r_null["ok"], "null ok false")
	_check(r_null["reason"] == "progress_state_null", "null reason")
	_check(r_null["progress_state"] == null, "null state ref")
	_check((r_null["unlocked_targets"] as Array).size() == 0, "null no unlocks")

	var empty_st = ProgressStateScript.new({})
	var r_unk = ProgressUnlockResolverScript.complete_progress(empty_st, 0, "no_such_progress")
	_check(not r_unk["ok"], "unknown ok false")
	_check(r_unk["reason"] == "unknown_progress_id", "unknown reason")
	_check(r_unk["progress_state"] == empty_st, "unknown same ref")
	_check((r_unk["unlocked_targets"] as Array).size() == 0, "unknown no unlocks")

	var inp = ProgressStateScript.new({})
	var r1 = ProgressUnlockResolverScript.complete_progress(inp, 0, "foraging_systems")
	_check(r1["ok"], "foraging ok")
	_check(str(r1["reason"]) == "", "foraging empty reason")
	var ps1 = r1["progress_state"]
	_check(ps1.has_completed_progress(0, "foraging_systems"), "foraging completed")
	_check(ps1.has_unlocked_target(0, "building", "scout_camp"), "scout_camp")
	_check(ps1.has_unlocked_target(0, "specialist", "forager"), "forager")
	_check(ps1.has_unlocked_target(0, "modifier", "forest_food_bonus"), "forest bonus")
	_check(ps1.has_unlocked_target(0, "modifier", "outside_borders_healing"), "healing")
	_check(not ps1.has_unlocked_target(0, "science", "survival_knowledge"), "no survival")
	_check(not ps1.has_unlocked_target(0, "science", "woodland_logistics"), "no woodland")
	var nu = r1["unlocked_targets"] as Array
	_check(nu.size() == 4, "four new unlocks")
	_check(str((nu[0] as Dictionary)["target_type"]) == "building", "ord0 type")
	_check(str((nu[0] as Dictionary)["target_id"]) == "scout_camp", "ord0 id")
	_check(str((nu[1] as Dictionary)["target_type"]) == "specialist", "ord1 type")
	_check(str((nu[1] as Dictionary)["target_id"]) == "forager", "ord1 id")
	_check(str((nu[2] as Dictionary)["target_type"]) == "modifier", "ord2 type")
	_check(str((nu[2] as Dictionary)["target_id"]) == "forest_food_bonus", "ord2 id")
	_check(str((nu[3] as Dictionary)["target_type"]) == "modifier", "ord3 type")
	_check(str((nu[3] as Dictionary)["target_id"]) == "outside_borders_healing", "ord3 id")

	_check(not inp.has_completed_progress(0, "foraging_systems"), "input no completion")
	_check(inp.unlocked_targets_for(0).size() == 0, "input no unlocks")

	_check(not ps1.has_completed_progress(1, "foraging_systems"), "p1 no completion")
	_check(ps1.unlocked_targets_for(1).size() == 0, "p1 no unlocks")

	var r_idem = ProgressUnlockResolverScript.complete_progress(ps1, 0, "foraging_systems")
	_check(r_idem["ok"], "idem ok")
	_check(str(r_idem["reason"]) == "", "idem reason")
	_check((r_idem["unlocked_targets"] as Array).size() == 0, "idem no delta")
	_check(r_idem["progress_state"] == ps1, "idem same ref")
	_check(ps1.equals(r_idem["progress_state"]), "idem equals")

	var st_seq = ProgressStateScript.new({})
	var rf = ProgressUnlockResolverScript.complete_progress(st_seq, 0, "foraging_systems")
	var psf = rf["progress_state"]
	var rs = ProgressUnlockResolverScript.complete_progress(psf, 0, "stone_tools")
	_check(rs["ok"], "stone ok")
	var pss = rs["progress_state"]
	var cids = pss.completed_progress_ids_for(0)
	_check(
		cids.size() == 2 and str(cids[0]) == "foraging_systems" and str(cids[1]) == "stone_tools",
		"completed sorted"
	)
	_check(pss.has_unlocked_target(0, "unit", "worker"), "stone worker")
	_check(pss.has_unlocked_target(0, "tile_improvement", "quarry"), "quarry")
	_check(pss.has_unlocked_target(0, "unit_upgrade", "basic_melee_equipment"), "melee")
	_check(pss.has_unlocked_target(0, "modifier", "stone_production_bonus"), "stone bonus")
	var delta2 = rs["unlocked_targets"] as Array
	_check(delta2.size() == 4, "second delta size")
	_check(str((delta2[0] as Dictionary)["target_id"]) == "worker", "d2 w")
	_check(str((delta2[1] as Dictionary)["target_id"]) == "quarry", "d2 q")
	_check(str((delta2[2] as Dictionary)["target_id"]) == "basic_melee_equipment", "d2 m")
	_check(str((delta2[3] as Dictionary)["target_id"]) == "stone_production_bonus", "d2 b")

	var seed = ProgressStateScript.with_default_unlocks_for_players([0, 1])
	var rg = ProgressUnlockResolverScript.complete_progress(seed, 0, "foraging_systems")
	_check(rg["ok"], "seed foraging ok")
	var psg = rg["progress_state"]
	_check(
		psg.has_unlocked_target(0, "city_project", "produce_unit:warrior"),
		"warrior preserved"
	)
	var dug = rg["unlocked_targets"] as Array
	var di = 0
	while di < dug.size():
		var dr = dug[di] as Dictionary
		var skip = not (
			str(dr["target_type"]) == "city_project"
			and str(dr["target_id"]) == "produce_unit:warrior"
		)
		_check(skip, "delta no warrior")
		di = di + 1

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
