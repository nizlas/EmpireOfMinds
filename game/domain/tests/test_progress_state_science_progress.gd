# Headless: godot --headless --path game -s res://domain/tests/test_progress_state_science_progress.gd
extends SceneTree

const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var base = ProgressStateScript.with_default_unlocks_for_players([0])
	_check(base.science_progress_for(0, "controlled_fire") == 0, "default zero")

	var a = base.with_science_progress_added(0, "controlled_fire", 3)
	_check(a.science_progress_for(0, "controlled_fire") == 3, "add delta")
	_check(base.science_progress_for(0, "controlled_fire") == 0, "orig unchanged")

	_check(not a.has_observation_bonus_granted(0, "controlled_fire"), "flag off")
	var b = a.with_observation_bonus_granted(0, "controlled_fire")
	_check(b.has_observation_bonus_granted(0, "controlled_fire"), "flag on")
	_check(not a.has_observation_bonus_granted(0, "controlled_fire"), "orig flag off")

	var c = b.with_target_unlocked(0, "city_project", "produce_unit:settler")
	_check(c.has_observation_bonus_granted(0, "controlled_fire"), "unlock preserves obs flag")
	_check(c.science_progress_for(0, "controlled_fire") == 3, "unlock preserves science")

	var d = ProgressStateScript.new({})
	var e = d.with_science_progress_added(0, "controlled_fire", 1)
	_check(e.science_progress_for(0, "controlled_fire") == 1, "new owner science")

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
