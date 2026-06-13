# One-off probe: print Niclas AnimationPlayer clip durations.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")

const CLIPS: Array[String] = ["Idle_3", "Flying_Fist_Kick", "Walking"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path: String = Experiment.NICLAS_GLB_PATH
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("failed to load %s" % path)
		quit(1)
		return
	var model: Node = packed.instantiate()
	var player: AnimationPlayer = UnitWorldScript._find_animation_player(model)
	if player == null:
		push_error("no AnimationPlayer on Niclas GLB")
		quit(1)
		return
	for clip_name in CLIPS:
		if not player.has_animation(clip_name):
			print("NICLAS_CLIP %s missing" % clip_name)
			continue
		var anim: Animation = player.get_animation(clip_name)
		var loop_label: String = "none"
		if anim.loop_mode == Animation.LOOP_LINEAR:
			loop_label = "linear"
		elif anim.loop_mode == Animation.LOOP_PINGPONG:
			loop_label = "pingpong"
		print(
			"NICLAS_CLIP %s length=%.6f loop=%s"
			% [clip_name, anim.length, loop_label]
		)
	model.free()
	quit(0)
