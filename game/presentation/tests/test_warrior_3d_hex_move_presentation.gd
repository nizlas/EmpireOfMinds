# Headless: godot --headless --path game -s res://presentation/tests/test_warrior_3d_hex_move_presentation.gd
extends SceneTree

const Warrior3DUnitMarkersViewScript = preload(
	"res://presentation/warrior_3d_unit_markers_view.gd"
)
const Warrior3DWalkSyncScript = preload("res://presentation/warrior_3d_walk_sync.gd")
const Warrior3DUnitExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "")
	var view_off := Warrior3DUnitMarkersViewScript.new()
	view_off.begin_hex_move(1, "warrior", 0, 0, 1, 0)
	_check(
		not view_off.is_unit_hex_move_active(1),
		"hex move ignored when EMPIRE_USE_3D_MODELS off",
	)
	view_off.free()

	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "1")
	_check(
		Warrior3DAnimationRemapScript.glb_clip_for_visual("Walking", true) == "Idle_02",
		"Walking semantic remaps to Idle_02 GLB key",
	)
	_check(
		Warrior3DAnimationRemapScript.glb_clip_for_visual("Idle_3", true) == "Combat_Stance",
		"Idle_3 semantic remaps to Combat_Stance GLB key",
	)

	var view := Warrior3DUnitMarkersViewScript.new()
	_check(
		is_equal_approx(view.walk_start_blend_sec, 0.0),
		"walk start default is snap (no Idle->Walking blend)",
	)
	_check(
		Warrior3DUnitMarkersViewScript.WALK_START_BLEND_MAX_SEC <= 0.05,
		"walk start blend capped at 0.05s max",
	)
	_check(
		view.idle_end_blend_sec >= 0.20 and view.idle_end_blend_sec <= 0.35,
		"idle end blend in 0.20-0.35s range",
	)
	view.layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	view.camera = cam
	view.begin_hex_move(2, "warrior", 0, 0, 1, -1)
	_check(view.is_unit_hex_move_active(2), "hex move active for warrior when flag on")
	var move2: Dictionary = view._active_hex_moves[2]
	var expected_dur: float = Warrior3DWalkSyncScript.hex_move_duration_sec(
		Warrior3DUnitMarkersViewScript.HEX_MOVE_WALK_ANIM_SPEED,
		view.hex_stride_cycle_fraction,
		Warrior3DWalkSyncScript.FALLBACK_WALK_CLIP_LENGTH_SEC,
	)
	_check(
		is_equal_approx(float(move2["duration_sec"]), expected_dur),
		"hex move duration derived from walk clip length and stride fraction",
	)
	_check(
		expected_dur > 2.2,
		"walk-sync duration tuned between glide and backward drag",
	)
	view.begin_hex_move(3, "settler", 0, 0, 1, 0)
	if Warrior3DUnitExperimentScript.should_render_unit_as_3d("settler"):
		_check(view.is_unit_hex_move_active(3), "settler starts 3D hex move when flag on")
	else:
		_check(not view.is_unit_hex_move_active(3), "settler skips 3D move when asset missing")
	var from_world: Vector2 = view.layout.hex_to_world(0, 0)
	var to_world: Vector2 = view.layout.hex_to_world(1, -1)
	var pres_dir: Vector2 = cam.to_presentation(to_world) - cam.to_presentation(from_world)
	var expected_ne_yaw: float = (
		Warrior3DUnitMarkersViewScript.expected_travel_yaw_from_pres_dir(pres_dir)
	)
	_check(
		is_equal_approx(view._facing_yaw_by_unit_id[2], expected_ne_yaw),
		"NE facing yaw from presentation travel bearing",
	)
	var se_pres: Vector2 = (
		cam.to_presentation(view.layout.hex_to_world(0, 1))
		- cam.to_presentation(from_world)
	)
	var sw_pres: Vector2 = (
		cam.to_presentation(view.layout.hex_to_world(-1, 1))
		- cam.to_presentation(from_world)
	)
	var expected_se_yaw: float = (
		Warrior3DUnitMarkersViewScript.expected_travel_yaw_from_pres_dir(se_pres)
	)
	var expected_sw_yaw: float = (
		Warrior3DUnitMarkersViewScript.expected_travel_yaw_from_pres_dir(sw_pres)
	)
	_check(
		absf(fposmod(expected_se_yaw, 360.0) - 358.7) < 2.0,
		"SE travel yaw uses offset + map_bearing (forward, not backward)",
	)
	_check(
		absf(fposmod(expected_sw_yaw, 360.0) - 291.0) < 2.0,
		"SW travel yaw uses offset + map_bearing (forward, not backward)",
	)
	_check(
		not is_equal_approx(expected_se_yaw, expected_sw_yaw),
		"SE and SW model yaws are not collapsed to the same value",
	)
	view.begin_hex_move(4, "warrior", 0, 0, -1, 0)
	var west_pres_dir: Vector2 = (
		cam.to_presentation(view.layout.hex_to_world(-1, 0))
		- cam.to_presentation(from_world)
	)
	var expected_west_yaw: float = (
		Warrior3DUnitMarkersViewScript.expected_travel_yaw_from_pres_dir(west_pres_dir)
	)
	_check(
		is_equal_approx(float(view._facing_yaw_by_unit_id[4]), expected_west_yaw),
		"west facing yaw from presentation travel bearing (no mirror)",
	)
	view._active_hex_moves[4] = {
		"from_q": 0,
		"from_r": 0,
		"to_q": -1,
		"to_r": 0,
		"progress": 0.5,
		"anim_elapsed_sec": view._hex_move_stride_anim_sec(4) * 0.5,
	}
	var mid: Dictionary = view._presentation_anchor_for_unit(4, Vector2.ZERO, 1.0)
	var from_pres: Vector2 = cam.to_presentation(from_world)
	var to_pres: Vector2 = cam.to_presentation(view.layout.hex_to_world(-1, 0))
	var expected_mid: Vector2 = from_pres.lerp(to_pres, 0.5)
	_check(
		(mid["anchor"] as Vector2).is_equal_approx(expected_mid),
		"move anchor lerps in presentation space",
	)
	view.begin_hex_move(5, "warrior", 0, 0, 0, 1)
	var idle_rect: Rect2 = view._marker_display_rect(from_pres, 1.0, "warrior", -1)
	var move_rect: Rect2 = view._marker_display_rect(from_pres, 1.0, "warrior", 5)
	_check(
		move_rect.size.y > idle_rect.size.y,
		"hex move expands viewport bottom pad uniformly",
	)
	_check(
		move_rect.size.x > idle_rect.size.x,
		"hex move expands viewport width uniformly",
	)
	var idle_foot_x: float = idle_rect.position.x + idle_rect.size.x * 0.5
	var move_foot_x: float = move_rect.position.x + move_rect.size.x * 0.5
	_check(
		is_equal_approx(idle_foot_x, move_foot_x),
		"hex-move viewport pad keeps foot anchor centered on hex",
	)
	view._active_hex_moves[5]["progress"] = 0.5
	var se_depth: Vector2 = view.depth_sort_anchor_pres(5, from_pres, 1.0)
	var se_to_pres: Vector2 = cam.to_presentation(view.layout.hex_to_world(0, 1))
	var se_fwd: Vector2 = se_pres.normalized()
	_check(
		(se_depth - se_to_pres).dot(se_fwd) > 0.0,
		"screen-down depth sort leads past destination hex center",
	)
	_check(
		view.is_unit_screen_down_hex_move_active(5),
		"SE hex move flagged as screen-down travel",
	)
	_check(not view.is_unit_screen_down_hex_move_active(4), "west hex move is not screen-down")
	_check_settler_root_motion_cancel(view)
	view.free()

	_finish()


func _check_settler_root_motion_cancel(view) -> void:
	if not Warrior3DUnitExperimentScript.should_render_unit_as_3d("settler"):
		_check(true, "settler root-motion cancel skipped when settler asset missing")
		return
	view._load_unit_scenes()
	var slot: Node2D = view._create_slot("settler")
	_check(
		view._root_motion_anchor_for_slot(slot) != null,
		"settler slot wraps imported GLB in RootMotionAnchor",
	)
	_check(view.settler_neutralize_root_motion, "settler root-motion neutralization enabled by default")
	var scene: PackedScene = load(
		Warrior3DUnitExperimentScript.SETTLER_ANIMATED_GLB_PATH
	) as PackedScene
	var model: Node = scene.instantiate()
	root.add_child(model)
	var player: AnimationPlayer = _find_anim_player(model)
	var skel: Skeleton3D = _find_skeleton(model)
	_check(player != null and skel != null, "settler GLB exposes AnimationPlayer and Skeleton3D")
	if player == null or skel == null:
		model.queue_free()
		slot.queue_free()
		return
	var hips: int = skel.find_bone("Hips")
	var walk_clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(
		"Walking", true, "settler"
	)
	var walk_anim: Animation = player.get_animation(walk_clip)
	player.play(walk_clip)
	player.seek(walk_anim.length * 0.5, true)
	var pose_delta: Vector3 = skel.get_bone_pose_position(hips) - skel.get_bone_rest(hips).origin
	_check(
		absf(pose_delta.z) > 40.0,
		"settler Walking animates Hips forward in GLB space (root motion)",
	)
	var warrior_scene: PackedScene = load(
		Warrior3DUnitExperimentScript.WARRIOR_ANIMATED_GLB_PATH
	) as PackedScene
	var wmodel: Node = warrior_scene.instantiate()
	root.add_child(wmodel)
	var wplayer: AnimationPlayer = _find_anim_player(wmodel)
	var wskel: Skeleton3D = _find_skeleton(wmodel)
	var wwalk: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(
		"Walking", true, "warrior"
	)
	wplayer.play(wwalk)
	wplayer.seek(wplayer.get_animation(wwalk).length * 0.5, true)
	var wh: int = wskel.find_bone("Hips")
	var wdelta: Vector3 = wskel.get_bone_pose_position(wh) - wskel.get_bone_rest(wh).origin
	_check(
		absf(wdelta.z) < 15.0,
		"warrior Walking Hips stays near bind pose (no large root motion)",
	)
	model.queue_free()
	wmodel.queue_free()
	slot.queue_free()


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f: AnimationPlayer = _find_anim_player(c)
		if f != null:
			return f
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var f: Skeleton3D = _find_skeleton(c)
		if f != null:
			return f
	return null


func _check(ok: bool, label: String) -> void:
	_total += 1
	if not ok:
		_any_fail = true
		push_error("FAIL: %s" % label)
	else:
		print("ok: %s" % label)


func _finish() -> void:
	if _any_fail:
		push_error("test_warrior_3d_hex_move_presentation: %d checks, FAILURES" % _total)
		quit(1)
	print("test_warrior_3d_hex_move_presentation: %d checks, all ok" % _total)
	quit()


