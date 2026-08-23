# Headless A1 gate: Godot import-time humanoid retarget (NOT the failed custom baker).
# Does not claim visual PASS — print "automated gate passed; F6 required".
# godot --headless --path game -s res://presentation/tests/test_uthana_a1_walking_retarget.gd
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const FailedCustom = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_retarget.gd"
)
const Playback = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)

## Profile humanoid: +X is anatomical contraction for hinges (knees).
const KNEE_PLUS_X_MIN := 0.08
const KNEE_OFFAXIS_MAX := 0.55
const HAND_SWING_MIN := 0.12
const LENGTH_ERR_MAX := 0.08
const GROUND_TOL := Native.GROUND_CONTACT_TOLERANCE

var _total := 0
var _any_fail := false
var _metrics: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_check(
		FailedCustom.A1_STATUS.begins_with("FAILED"),
		"custom retargeter marked FAILED (not acceptance)"
	)
	_check(
		Native.RETARGET_METHOD == "godot_import_humanoid_retarget",
		"acceptance method is Godot import humanoid retarget"
	)
	_check(ResourceLoader.exists(Native.ORIG_MESHY_GLB), "original Meshy GLB exists")
	_check(ResourceLoader.exists(Native.ORIG_UTHANA_GLB), "original Uthana GLB exists")
	_check(ResourceLoader.exists(Native.MESHY_SOURCE_GLB), "A1 isolated Meshy source exists")
	_check(ResourceLoader.exists(Native.UTHANA_TARGET_GLB), "A1 isolated Uthana target exists")
	_check(is_equal_approx(Native.PREVIEW_MODEL_YAW, 0.0), "preview yaw is 0")

	var host := Node.new()
	root.add_child(host)

	var extracted: Dictionary = Native.extract_and_save_walking_library()
	_check(bool(extracted.get("ok", false)), "extract native Walking library (%s)" % extracted)
	Native.write_notes(extracted)
	await process_frame

	var lib: AnimationLibrary = load(Native.WALKING_LIBRARY_PATH) as AnimationLibrary
	_check(lib != null and lib.has_animation(Native.WALKING_CLIP), "Walking library+clip")
	var walk: Animation = lib.get_animation(Native.WALKING_CLIP)
	_check(walk != null and walk.length > 0.1, "Walking duration non-zero")
	var multi_keys := 0
	var reflected := 0
	for ti in walk.get_track_count():
		if walk.track_get_key_count(ti) > 1:
			multi_keys += 1
		if walk.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			for ki in mini(walk.track_get_key_count(ti), 8):
				var q: Quaternion = walk.track_get_key_value(ti, ki)
				if Basis(q).determinant() <= 0.0:
					reflected += 1
	_check(multi_keys >= 8, "Walking has multi-key tracks (multi=%d)" % multi_keys)
	_check(reflected == 0, "rotation keys have positive determinants")
	_metrics["walk_tracks"] = walk.get_track_count()
	_metrics["multi_keys"] = multi_keys

	var uthana: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate() as Node3D
	host.add_child(uthana)
	await process_frame
	var sk: Skeleton3D = Native.find_skeleton(uthana)
	_check(sk != null and sk.get_bone_count() == 52, "target has 52 bones")
	_check(sk.name == Native.GENERAL_SKELETON_NAME, "skeleton renamed GeneralSkeleton")
	_check(sk.is_unique_name_in_owner(), "skeleton unique_name_in_owner")
	var fingers: PackedStringArray = Native.list_finger_bones(sk)
	_check(fingers.size() == 30, "30 finger bones present (%d)" % fingers.size())
	_check(sk.find_bone("Hips") >= 0, "canonical Hips present")
	_check(sk.find_bone("LeftLowerLeg") >= 0, "canonical LeftLowerLeg present")
	_check(sk.find_bone("mixamorig_Hips") < 0, "mixamo mapped bones renamed away")

	var fwd: Vector3 = Native.measure_forward_xz(sk)
	_check(fwd.z > 0.5, "Uthana rest forward is +Z (got %s)" % fwd)

	var meshes: Array = uthana.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() == 1, "exactly one Uthana mesh")
	var mi: MeshInstance3D = meshes[0] as MeshInstance3D
	_check(mi.skin != null, "skin binding present")

	# Rest pose valid before playback.
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var rest_ok := true
	for bi in sk.get_bone_count():
		if not sk.get_bone_global_pose(bi).basis.determinant() > 0.0:
			rest_ok = false
			break
	_check(rest_ok, "rest pose has no reflected bone bases")

	var player := AnimationPlayer.new()
	uthana.add_child(player)
	player.add_animation_library("uthana_a1", lib)
	var clip_id := "uthana_a1/" + Native.WALKING_CLIP

	var finger_rests: Dictionary = {}
	for fname in fingers:
		finger_rests[fname] = sk.get_bone_pose(sk.find_bone(fname))
	var rest_lengths: Dictionary = _chain_lengths(sk)

	# Source for phase / geometry comparison (same native import).
	var meshy: Node3D = (load(Native.MESHY_SOURCE_GLB) as PackedScene).instantiate() as Node3D
	host.add_child(meshy)
	await process_frame
	var msk: Skeleton3D = Native.find_skeleton(meshy)
	var maplayer: AnimationPlayer = Native.find_animation_player(meshy)
	_check(msk != null and maplayer != null and maplayer.has_animation("Walking"), "source Walking player")

	player.play(clip_id)
	maplayer.play("Walking")

	var hand_l := sk.find_bone("LeftHand")
	var hand_l_min_z := INF
	var hand_l_max_z := -INF
	var hand_l_min_x := INF
	var hand_l_max_x := -INF
	var knee_x_max := -INF
	var knee_x_min := INF
	var knee_off_max := 0.0
	var length_errs := 0.0
	var geom_sign_agree := 0
	var geom_samples := 0
	var foot_dot_sum := 0.0
	var stride_agree := 0
	var stride_samples := 0

	var lo := sk.find_bone("LeftLowerLeg")
	var rest_knee_q: Quaternion = sk.get_bone_rest(lo).basis.get_rotation_quaternion()

	for _i in 24:
		await process_frame
		var t: float = walk.length * float(_i) / 23.0
		player.seek(t, true)
		maplayer.seek(t, true)
		sk.force_update_all_bone_transforms()
		msk.force_update_all_bone_transforms()

		var hl: Vector3 = sk.get_bone_global_pose(hand_l).origin
		hand_l_min_z = minf(hand_l_min_z, hl.z)
		hand_l_max_z = maxf(hand_l_max_z, hl.z)
		hand_l_min_x = minf(hand_l_min_x, hl.x)
		hand_l_max_x = maxf(hand_l_max_x, hl.x)

		var knee_local: Dictionary = _knee_local_delta(sk, rest_knee_q, true)
		knee_x_max = maxf(knee_x_max, float(knee_local["x"]))
		knee_x_min = minf(knee_x_min, float(knee_local["x"]))
		knee_off_max = maxf(knee_off_max, float(knee_local["off"]))

		var tg: float = _knee_bend_signed_xz(sk, true)
		var sg: float = _knee_bend_signed_xz(msk, true)
		if absf(tg) > 0.002 and absf(sg) > 0.002:
			geom_samples += 1
			if tg * sg > 0.0:
				geom_sign_agree += 1

		foot_dot_sum += _foot_forward_dot_plus_z(sk, true)
		foot_dot_sum += _foot_forward_dot_plus_z(sk, false)

		var t_lead := _leading_foot_z(sk)
		var s_lead := _leading_foot_z(msk)
		if t_lead != 0 and s_lead != 0:
			stride_samples += 1
			if t_lead == s_lead:
				stride_agree += 1

		length_errs = maxf(length_errs, _max_chain_length_error(sk, rest_lengths))

	var hand_swing: float = maxf(hand_l_max_z - hand_l_min_z, hand_l_max_x - hand_l_min_x)
	_metrics["hand_swing"] = hand_swing
	_metrics["knee_x_min"] = knee_x_min
	_metrics["knee_x_max"] = knee_x_max
	_metrics["knee_off_max"] = knee_off_max
	_metrics["geom_agree"] = float(geom_sign_agree) / float(maxi(geom_samples, 1))
	_metrics["stride_agree"] = float(stride_agree) / float(maxi(stride_samples, 1))
	_metrics["foot_dot_avg"] = foot_dot_sum / 48.0
	_metrics["length_err"] = length_errs

	# Canonical anatomical +X flexion (profile contraction axis). Prefer positive peak.
	_check(
		knee_x_max >= KNEE_PLUS_X_MIN or absf(knee_x_min) >= KNEE_PLUS_X_MIN,
		(
			"knee flexion primarily on local +/-X (min=%.4f max=%.4f need |peak|>=%.2f)"
			% [knee_x_min, knee_x_max, KNEE_PLUS_X_MIN]
		)
	)
	# If both signs present, require the larger-magnitude peak to dominate off-axis.
	var peak_x: float = knee_x_max if absf(knee_x_max) >= absf(knee_x_min) else knee_x_min
	_check(
		absf(peak_x) >= knee_off_max * 0.55 or knee_off_max <= KNEE_OFFAXIS_MAX,
		(
			"knee off-axis within tolerance (peak_x=%.4f off_max=%.4f tol=%.2f)"
			% [peak_x, knee_off_max, KNEE_OFFAXIS_MAX]
		)
	)
	_check(
		geom_samples >= 4 and float(geom_sign_agree) / float(geom_samples) >= 0.6,
		(
			"hip-knee-ankle bend direction agrees with source (agree=%.2f n=%d)"
			% [float(geom_sign_agree) / float(maxi(geom_samples, 1)), geom_samples]
		)
	)
	_check(
		_metrics["foot_dot_avg"] > 0.25,
		"feet point consistently with +Z forward (avg_dot=%.3f)" % _metrics["foot_dot_avg"]
	)
	_check(
		stride_samples >= 4 and float(stride_agree) / float(stride_samples) >= 0.6,
		(
			"stride phase / leading foot matches source (agree=%.2f n=%d)"
			% [float(stride_agree) / float(maxi(stride_samples, 1)), stride_samples]
		)
	)
	_check(hand_swing > HAND_SWING_MIN, "hand/arm swing present (range=%.4f)" % hand_swing)
	_check(length_errs < LENGTH_ERR_MAX, "bone chain lengths stable (max_err=%.4f)" % length_errs)

	var finger_drift := 0
	for fname in fingers:
		if not sk.get_bone_pose(sk.find_bone(fname)).is_equal_approx(finger_rests[fname]):
			finger_drift += 1
	_check(finger_drift == 0, "fingers unanimated / rest preserved (%d drifted)" % finger_drift)

	# Preview acceptance scene
	var preview_path := (
		"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_walking_preview.tscn"
	)
	_check(ResourceLoader.exists(preview_path), "preview scene exists")
	var preview: Node = (load(preview_path) as PackedScene).instantiate()
	root.add_child(preview)
	for _j in 30:
		await process_frame
	_check(preview.get_node_or_null("ForwardArrow_PlusZ") != null, "preview has +Z forward marker")
	var uthana_node = preview.find_child("UthanaWarrior", true, false)
	var char_meshes := 0
	if uthana_node != null:
		char_meshes = uthana_node.find_children("*", "MeshInstance3D", true, false).size()
	_check(char_meshes == 1, "preview character mesh count == 1")
	_check(
		uthana_node.get_node_or_null("NativeRetargetAnimationPlayer") != null,
		"preview uses NativeRetargetAnimationPlayer"
	)
	_check(
		uthana_node.get_node_or_null("RetargetedAnimationPlayer") == null,
		"preview does not use custom RetargetedAnimationPlayer"
	)

	var model_root: Node3D = preview.get_node_or_null("ModelRoot") as Node3D
	_check(model_root != null, "preview ModelRoot present")
	var pskel: Skeleton3D = Native.find_skeleton(uthana_node)
	var pplayer: AnimationPlayer = (
		uthana_node.get_node_or_null("NativeRetargetAnimationPlayer") as AnimationPlayer
	)
	var clip_prev: String = preview.preview_clip_id()
	if clip_prev.is_empty():
		clip_prev = "uthana_a1_preview/" + Native.WALKING_CLIP
	var contact: Dictionary = preview.ground_contact()
	_check(bool(contact.get("ok", false)), "preview sole ground contact ok")
	_check(
		str(contact.get("method", "")) == "skinned_foot_vertices",
		"ground lift uses skinned foot vertices"
	)
	_check(
		float(contact.get("bone_minus_sole", 0.0)) > 0.001,
		(
			"skinned sole is below bone origins (delta=%.5f)"
			% float(contact.get("bone_minus_sole", 0.0))
		)
	)
	_check(int(contact.get("vertex_count", 0)) >= 50, "enough foot/sole vertices selected")

	var applied_lift: float = model_root.position.y
	var hips_span_at_ground: float = float(contact.get("hips_span", -1.0))
	# Ungrounded: temporarily clear lift and re-measure skinned soles.
	model_root.position.y = 0.0
	await process_frame
	if pskel != null:
		pskel.force_update_all_bone_transforms()
	var ungrounded: Dictionary = Native.sample_sole_ground_contact(
		uthana_node, pskel, pplayer, clip_prev, 33
	)
	_check(
		float(ungrounded.get("lowest_sole_y", 0.0)) < -0.02,
		"ungrounded soles below Y=0 (lowest=%.4f)" % float(ungrounded.get("lowest_sole_y", 0.0))
	)
	var auto_lift: float = float(ungrounded.get("ground_offset_y", 0.0))
	var hips_span_ungrounded: float = float(ungrounded.get("hips_span", -2.0))
	model_root.position.y = auto_lift
	await process_frame
	if pskel != null:
		pskel.force_update_all_bone_transforms()
	var grounded: Dictionary = Native.sample_sole_ground_contact(
		uthana_node, pskel, pplayer, clip_prev, 33
	)
	const SOLE_EPS := 0.002
	_check(
		absf(float(grounded.get("lowest_sole_y", 1.0))) <= SOLE_EPS,
		(
			"grounded lowest sole near Y=0 (lowest=%.5f lift=%.4f)"
			% [float(grounded.get("lowest_sole_y", 1.0)), auto_lift]
		)
	)
	var under := 0
	for yv in grounded.get("per_sample_min_y", []):
		if float(yv) < -SOLE_EPS:
			under += 1
	_check(under == 0, "no sampled sole vertex below ground (%d under)" % under)
	_check(
		absf(hips_span_ungrounded - float(grounded.get("hips_span", 0.0))) < 0.001,
		(
			"hips-Y span unchanged by lift (%.6f -> %.6f)"
			% [hips_span_ungrounded, float(grounded.get("hips_span", 0.0))]
		)
	)
	_check(
		is_equal_approx(applied_lift, auto_lift),
		"preview applied automatic sole ground offset (%.4f)" % applied_lift
	)
	# Constant lift: ModelRoot.y must not change while playing.
	var y0: float = model_root.position.y
	for _fr in 20:
		await process_frame
	_check(
		is_equal_approx(model_root.position.y, y0),
		"ground offset constant during playback (%.4f)" % model_root.position.y
	)
	_metrics["ground_lift"] = auto_lift
	_metrics["grounded_lowest_sole"] = float(grounded.get("lowest_sole_y", 0.0))
	_metrics["bone_minus_sole"] = float(contact.get("bone_minus_sole", 0.0))
	_metrics["hips_span"] = hips_span_at_ground
	_metrics["sole_verts"] = int(contact.get("vertex_count", 0))

	# --- Preview loop / speed / sync / no-A2 ---------------------------------
	_check(
		str(preview.canonical_library_path()) == Native.WALKING_LIBRARY_PATH,
		"preview sources a1_native_walking.res"
	)
	_check(
		Playback.canonical_library_untouched(),
		"canonical a1_native_walking.res remains non-looping"
	)
	var pb: Node = preview.preview_playback()
	_check(pb != null, "preview playback controller present")
	_check(
		String(preview.preview_clip_id()).begins_with("uthana_a1_preview/"),
		"preview plays looping duplicate library (not mutating canonical)"
	)
	var loop_anim: Animation = pplayer.get_animation(preview.preview_clip_id())
	_check(
		loop_anim != null and loop_anim.loop_mode == Animation.LOOP_LINEAR,
		"preview Walking uses LOOP_LINEAR"
	)
	# Advance past one clip length; looping must keep playing and wrap time.
	var len_w: float = loop_anim.length
	pplayer.play(preview.preview_clip_id())
	pplayer.seek(len_w * 0.95, true)
	pb.set_playback_speed(1.0)
	pb.set_paused(false)
	var wrapped := false
	var still_playing := false
	for _k in 40:
		await process_frame
		if pplayer.current_animation_position < len_w * 0.5:
			wrapped = true
		if pplayer.is_playing() or pplayer.current_animation == preview.preview_clip_id():
			still_playing = true
	_check(wrapped and still_playing, "Walking actually repeats after clip end")
	_check(
		preview.get_node_or_null("FootInspectionCamera") != null,
		"foot inspection camera present"
	)
	pb.toggle_foot_view()
	_check(pb.is_foot_view(), "F toggles foot view on")
	pb.toggle_foot_view()
	_check(not pb.is_foot_view(), "F toggles foot view off")

	# Side-by-side sync + shared speed/pause
	var sbs_path := (
		"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_side_by_side_diagnostic.tscn"
	)
	_check(ResourceLoader.exists(sbs_path), "side-by-side diagnostic scene exists")
	var sbs: Node = (load(sbs_path) as PackedScene).instantiate()
	root.add_child(sbs)
	for _j2 in 50:
		await process_frame
	_check(
		str(sbs.canonical_library_path()) == Native.WALKING_LIBRARY_PATH,
		"side-by-side sources a1_native_walking.res"
	)
	var sbs_pb: Node = sbs.preview_playback()
	_check(sbs_pb != null and sbs_pb.player_count() == 2, "side-by-side has 2 synced players")
	sbs_pb.set_playback_speed(0.5)
	sbs_pb.set_paused(false)
	sbs_pb.seek_all(0.2, true)
	await process_frame
	await process_frame
	_check(
		is_equal_approx(sbs_pb.playback_speed(), 0.5),
		"speed 0.5 applied"
	)
	_check(
		is_equal_approx(sbs.source_player().speed_scale, sbs.target_player().speed_scale),
		"speed scale equal on both AnimationPlayers"
	)
	_check(sbs_pb.max_position_delta() < 0.002, "side-by-side time-synced after seek")

	sbs_pb.set_playback_speed(0.25)
	await process_frame
	_check(
		is_equal_approx(sbs.source_player().speed_scale, 0.25)
		and is_equal_approx(sbs.target_player().speed_scale, 0.25),
		"0.25x affects both players equally"
	)

	sbs_pb.seek_all(0.4, true)
	sbs_pb.set_paused(true)
	await process_frame
	await process_frame
	var pause_t0: float = sbs.source_player().current_animation_position
	var pause_t1: float = sbs.target_player().current_animation_position
	await process_frame
	await process_frame
	_check(sbs_pb.is_playback_paused(), "pause engaged")
	_check(
		absf(pause_t0 - pause_t1) < 0.002,
		"pause stops both at same time (src=%.4f tgt=%.4f)" % [pause_t0, pause_t1]
	)
	_check(
		absf(sbs.source_player().current_animation_position - pause_t0) < 0.002
		and absf(sbs.target_player().current_animation_position - pause_t1) < 0.002,
		"paused positions stay frozen"
	)

	# No A2 equipment / grip systems / manual warrior offset constants.
	_check(
		preview.find_child("Equipment", true, false) == null
		and sbs.find_child("Equipment", true, false) == null,
		"no Equipment nodes in A1 previews"
	)
	_check(
		not ResourceLoader.exists(
			"res://assets/prototype/3d/units/generated_warrior/uthana_a1/a2_club_socket.gd"
		),
		"no A2 club socket resource under uthana_a1"
	)
	_check(
		preview.find_child("*grip*", true, false) == null
		and preview.find_child("*socket*", true, false) == null,
		"no grip/socket nodes in acceptance preview"
	)
	_check(
		not ("GROUND_SAFETY" in FileAccess.get_file_as_string(
			"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_skinned_sole_ground.gd"
		)),
		"no manual safety-margin constant in sole grounder"
	)

	print("A1_METHOD=", Native.RETARGET_METHOD)
	print("A1_METRICS=", _metrics)
	print("A1_VISUAL_CLAIM=automated grounding gate passed; final foot-level F6 validation still required")

	sbs.queue_free()
	preview.queue_free()
	host.queue_free()
	_finish()


func _knee_local_delta(sk: Skeleton3D, rest_q: Quaternion, left: bool) -> Dictionary:
	var lo := sk.find_bone("LeftLowerLeg" if left else "RightLowerLeg")
	var pose_q: Quaternion = sk.get_bone_pose_rotation(lo)
	var d: Quaternion = rest_q.inverse() * pose_q
	var e: Vector3 = d.get_euler()
	return {"x": e.x, "off": maxf(absf(e.y), absf(e.z))}


func _knee_bend_signed_xz(sk: Skeleton3D, left: bool) -> float:
	## Signed bend of thigh->shin in the sagittal-ish plane (cross.x of left chain).
	var up := sk.find_bone("LeftUpperLeg" if left else "RightUpperLeg")
	var lo := sk.find_bone("LeftLowerLeg" if left else "RightLowerLeg")
	var ft := sk.find_bone("LeftFoot" if left else "RightFoot")
	var hip: Vector3 = sk.get_bone_global_pose(up).origin
	var knee: Vector3 = sk.get_bone_global_pose(lo).origin
	var ankle: Vector3 = sk.get_bone_global_pose(ft).origin
	var thigh: Vector3 = (knee - hip).normalized()
	var shin: Vector3 = (ankle - knee).normalized()
	return thigh.cross(shin).x


func _foot_forward_dot_plus_z(sk: Skeleton3D, left: bool) -> float:
	## After Overwrite Axis, foot bone +Z is the profile forward axis.
	var foot := sk.find_bone("LeftFoot" if left else "RightFoot")
	if foot < 0:
		return 0.0
	var forward: Vector3 = sk.get_bone_global_pose(foot).basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-10:
		return 0.0
	return forward.normalized().dot(Vector3(0.0, 0.0, 1.0))


func _leading_foot_z(sk: Skeleton3D) -> int:
	var lf := sk.find_bone("LeftFoot")
	var rf := sk.find_bone("RightFoot")
	if lf < 0 or rf < 0:
		return 0
	var lz: float = sk.get_bone_global_pose(lf).origin.z
	var rz: float = sk.get_bone_global_pose(rf).origin.z
	if absf(lz - rz) < 0.01:
		return 0
	return 1 if lz > rz else -1


func _chain_lengths(sk: Skeleton3D) -> Dictionary:
	var pairs := [
		["LeftUpperLeg", "LeftLowerLeg"],
		["LeftLowerLeg", "LeftFoot"],
		["RightUpperLeg", "RightLowerLeg"],
		["RightLowerLeg", "RightFoot"],
		["LeftUpperArm", "LeftLowerArm"],
		["LeftLowerArm", "LeftHand"],
		["RightUpperArm", "RightLowerArm"],
		["RightLowerArm", "RightHand"],
	]
	var out := {}
	for p in pairs:
		var a: int = sk.find_bone(p[0])
		var b: int = sk.find_bone(p[1])
		out[str(p[0]) + ":" + str(p[1])] = sk.get_bone_global_rest(a).origin.distance_to(
			sk.get_bone_global_rest(b).origin
		)
	return out


func _max_chain_length_error(sk: Skeleton3D, rest_lengths: Dictionary) -> float:
	var max_err := 0.0
	for key in rest_lengths.keys():
		var parts: PackedStringArray = str(key).split(":")
		var a: int = sk.find_bone(parts[0])
		var b: int = sk.find_bone(parts[1])
		var cur: float = sk.get_bone_global_pose(a).origin.distance_to(
			sk.get_bone_global_pose(b).origin
		)
		max_err = maxf(max_err, absf(cur - float(rest_lengths[key])))
	return max_err


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print(
		"test_uthana_a1_walking_retarget: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	if not _any_fail:
		print("A1 automated grounding gate passed; final foot-level F6 validation still required.")
	quit(1 if _any_fail else 0)
