extends SceneTree

const Remap = preload("res://presentation/warrior_3d_animation_remap.gd")

var _total: int = 0
var _any_fail: bool = false

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(
		Remap.glb_clip_for_visual("Dead", true) == "Left_Slash",
		"audit remap Dead visual to Left_Slash GLB key",
	)
	_check(
		Remap.glb_clip_for_visual("Left_Slash", true) == "Dead",
		"audit remap Left_Slash visual to Dead GLB key",
	)
	_check(
		Remap.glb_clip_for_visual("Idle_3", true) == "Combat_Stance",
		"audit remap Idle_3 visual to Combat_Stance GLB key",
	)
	_check(
		Remap.glb_clip_for_visual("Idle_3", false) == "Idle_3",
		"remap off passes names through unchanged",
	)
	_check(
		Remap.glb_clip_for_visual("Idle_3", true, "settler") == "Idle_3",
		"settler uses semantic Idle_3 clip name directly",
	)
	_check(
		Remap.glb_clip_for_visual("Walking", true, "settler") == "Walking",
		"settler uses semantic Walking clip name directly",
	)
	if _any_fail:
		quit(1)
	else:
		print("PASS %d/%d" % [_total, _total])
		quit()


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)
