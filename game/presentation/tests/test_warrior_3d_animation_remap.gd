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
		Remap.glb_clip_for_visual("Idle_3", true, "settler") == "Hit_Reaction_1",
		"settler Idle_3 visual maps to Hit_Reaction_1 GLB key",
	)
	_check(
		Remap.glb_clip_for_visual("Walking", true, "settler") == "Running",
		"settler Walking visual maps to Running GLB key (F9-audit walk clip)",
	)
	_check(
		Remap.glb_clip_for_visual("Dead", true, "settler") == "walking_2",
		"settler Dead visual maps to walking_2 GLB key",
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
