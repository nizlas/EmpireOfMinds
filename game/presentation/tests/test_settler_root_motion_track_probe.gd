extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Remap = preload("res://presentation/warrior_3d_animation_remap.gd")
const Probe = preload("res://presentation/settler_animation_root_motion_probe.gd")
const MarkersView = preload("res://presentation/warrior_3d_unit_markers_view.gd")
## Raw GLB key probed for built-in root_motion_track API (not runtime walk remap).
const PROBE_RAW_WALKING_GLB: String = "Walking"

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment(Experiment.SETTLER_BUILTIN_RM_ENV, "")
	_probe_track_catalog()
	_probe_glb_in_scene_tree()
	_probe_view_slot_builtin_configuration()
	_finish()


func _probe_track_catalog() -> void:
	var scene: PackedScene = load(Experiment.SETTLER_ANIMATED_GLB_PATH) as PackedScene
	_check(scene != null, "settler_animations.glb loads")
	if scene == null:
		return
	var model: Node = scene.instantiate()
	var player: AnimationPlayer = _find_anim_player(model)
	var skel: Skeleton3D = _find_skeleton(model)
	_check(player != null, "settler GLB exposes AnimationPlayer")
	_check(skel != null, "settler GLB exposes Skeleton3D")
	if player == null:
		model.free()
		return
	_check(
		Remap.glb_clip_for_visual(Probe.WALK_SEMANTIC_CLIP, true, "settler") == "Running",
		"settler walk semantic maps to Running GLB key at runtime",
	)
	var walk_anim: Animation = player.get_animation(PROBE_RAW_WALKING_GLB)
	_check(walk_anim != null, "raw Walking animation resource exists for RM probe")
	if walk_anim != null:
		Probe.print_animation_tracks(walk_anim, PROBE_RAW_WALKING_GLB)
	var hips_track: NodePath = Probe.resolve_hips_position_track_path(
		player, PROBE_RAW_WALKING_GLB
	)
	_check(not hips_track.is_empty(), "raw Walking Hips TYPE_POSITION_3D track path resolved")
	print("[Settler3D RM probe] resolved root_motion_track='%s'" % str(hips_track))
	model.free()


func _probe_glb_in_scene_tree() -> void:
	var scene: PackedScene = load(Experiment.SETTLER_ANIMATED_GLB_PATH) as PackedScene
	if scene == null:
		return
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	var anchor := Node3D.new()
	anchor.name = "RootMotionAnchor"
	model_root.add_child(anchor)
	var model: Node = scene.instantiate()
	anchor.add_child(model)
	root.add_child(model_root)
	var player: AnimationPlayer = _find_anim_player(model)
	var skel: Skeleton3D = _find_skeleton(model)
	if player == null or skel == null:
		model_root.queue_free()
		return
	var walk_anim: Animation = player.get_animation(PROBE_RAW_WALKING_GLB)
	var hips_track: NodePath = Probe.resolve_hips_position_track_path(
		player, PROBE_RAW_WALKING_GLB
	)
	player.active = true
	player.root_motion_track = NodePath("")
	player.play(PROBE_RAW_WALKING_GLB)
	player.seek(walk_anim.length * 0.5, true)
	player.advance(0.016)
	var without_xz: Vector2 = Probe.hips_pose_xz_delta(skel)
	print("[Settler3D RM probe] without_builtin t=0.50 hips_xz_delta=%s" % _fmt_v2(without_xz))
	_check(without_xz.length() > 40.0, "without builtin RM Hips bone pose xz drift is large")
	player.root_motion_track = hips_track
	player.play(PROBE_RAW_WALKING_GLB)
	player.seek(0.0, true)
	player.advance(0.016)
	var acc_before: Vector3 = player.get_root_motion_position_accumulator()
	var saw_nonzero_frame_delta: bool = false
	var elapsed_samples: Array[float] = [0.12, walk_anim.length * 0.5, walk_anim.length * 0.95]
	var si: int = 0
	while si < elapsed_samples.size():
		var elapsed: float = float(elapsed_samples[si])
		player.seek(fposmod(elapsed, walk_anim.length), true)
		player.advance(0.016)
		var frame_rm: Vector3 = player.get_root_motion_position()
		if frame_rm.length_squared() > 0.0001:
			saw_nonzero_frame_delta = true
		print(
			(
				"[Settler3D RM probe] builtin_seek elapsed=%.3f hips_xz_delta=%s "
				+ "get_root_motion_position=%s"
			)
			% [elapsed, _fmt_v2(Probe.hips_pose_xz_delta(skel)), _fmt_v3(frame_rm)]
		)
		si += 1
	var acc_after: Vector3 = player.get_root_motion_position_accumulator()
	var acc_growth: Vector3 = acc_after - acc_before
	print(
		(
			"[Settler3D RM probe] builtin accumulator growth=%s acc_before=%s acc_after=%s"
		)
		% [_fmt_v3(acc_growth), _fmt_v3(acc_before), _fmt_v3(acc_after)]
	)
	_check(
		saw_nonzero_frame_delta or acc_growth.length() > 0.5,
		"builtin RM exposes nonzero root motion via get_root_motion_position API",
	)
	model_root.queue_free()


func _probe_view_slot_builtin_configuration() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_FLAG_LEGACY, "")
	OS.set_environment(Experiment.SETTLER_BUILTIN_RM_ENV, "1")
	_check(
		Experiment.should_render_unit_as_3d("settler"),
		"settler 3D enabled for builtin slot probe",
	)
	var view: Node2D = MarkersView.new()
	view._load_unit_scenes()
	root.add_child(view)
	var slot: Node2D = view._create_slot("settler")
	view.add_child(slot)
	var player: AnimationPlayer = view._walk_animation_player_for_slot(slot)
	var walk_clip: String = Remap.glb_clip_for_visual(Probe.WALK_SEMANTIC_CLIP, true, "settler")
	_check(player != null, "builtin slot exposes AnimationPlayer")
	if player == null:
		view.queue_free()
		OS.set_environment(Experiment.SETTLER_BUILTIN_RM_ENV, "")
		return
	var expected_track: NodePath = Probe.resolve_hips_position_track_path(player, walk_clip)
	_check(
		player.root_motion_track == expected_track and not expected_track.is_empty(),
		"builtin slot sets player.root_motion_track to resolved Hips path",
	)
	_check(
		not view._uses_settler_root_motion_cancel("settler"),
		"builtin flag disables manual RootMotionAnchor cancel",
	)
	var anchor: Node3D = view._root_motion_anchor_for_slot(slot)
	_check(
		anchor != null and anchor.position.is_equal_approx(Vector3.ZERO),
		"builtin slot keeps RootMotionAnchor pinned to zero",
	)
	view.queue_free()
	OS.set_environment(Experiment.ENV_FLAG, "")
	OS.set_environment(Experiment.SETTLER_BUILTIN_RM_ENV, "")


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _check(ok: bool, label: String) -> void:
	_total += 1
	if ok:
		print("ok: %s" % label)
		return
	_any_fail = true
	var line := "FAIL: %s" % label
	print(line)
	push_error(line)


func _finish() -> void:
	if _any_fail:
		push_error("test_settler_root_motion_track_probe: %d checks, FAILURES" % _total)
		quit(1)
		return
	print("test_settler_root_motion_track_probe: %d checks, all ok" % _total)
	quit()


static func _fmt_v2(v: Vector2) -> String:
	return "(%.2f,%.2f)" % [v.x, v.y]


static func _fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
