extends SceneTree

const WExp = preload("res://presentation/warrior_3d_unit_experiment.gd")
const WView = preload("res://presentation/warrior_3d_unit_markers_view.gd")

var _total: int = 0
var _any_fail: bool = false

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment(WExp.ENV_FLAG, "1")
	OS.set_environment(WExp.ANIM_AUDIT_ENV, "1")
	var wview := WView.new()
	_check(wview._is_animation_audit_active(), "audit env enables audit mode")
	wview.animation_audit_mode = false
	_check(wview._is_animation_audit_active(), "audit env alone enables audit mode")
	var host := Node.new()
	root.add_child(host)
	host.add_child(wview)
	await process_frame
	wview._load_warrior_scene()
	wview._prime_animation_audit_catalog_from_scene()
	_check(wview._audit_clip_names.size() == 8, "audit catalog lists eight GLB clips")
	_check(wview._audit_clip_names.has("Dead"), "audit catalog includes Dead as Godot reports it")
	_check(wview._audit_clip_names.has("Left_Slash"), "audit catalog includes Left_Slash as Godot reports it")
	var slot := wview._create_slot()
	host.add_child(slot)
	await process_frame
	wview._ensure_slot_animation(slot, wview._audit_clip_names[0])
	var ap: AnimationPlayer = slot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ap != null, "audit slot has AnimationPlayer")
	if ap != null:
		_check(
			ap.assigned_animation == wview._audit_clip_names[0],
			"audit applies first get_animation_list() entry verbatim",
		)
	wview.free()
	host.free()
	OS.unset_environment(WExp.ANIM_AUDIT_ENV)
	OS.unset_environment(WExp.ENV_FLAG)
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
