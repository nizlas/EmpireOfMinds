# Headless: godot --headless --path game -s res://domain/tests/test_progress_state_current_research.gd
extends SceneTree

const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var def = ProgressStateScript.with_default_unlocks_for_players([0])
	_check(def.current_research_for(0) == "", "default empty current research")

	var wcr = def.with_current_research(0, "stone_tools")
	_check(wcr.current_research_for(0) == "stone_tools", "with_current_research sets")
	_check(def.current_research_for(0) == "", "orig current research unchanged")

	var layered = def.with_current_research(0, "oral_surveying")
	var sp = layered.with_science_progress_added(0, "controlled_fire", 2)
	var pc = sp.with_progress_id_completed(0, "foraging_systems")
	var pu = pc.with_target_unlocked(0, "building", "hearth")
	_check(
		pu.current_research_for(0) == "oral_surveying",
		"science progress completion unlock preserve current research"
	)

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
