# FAILED custom path (forensic only). Do NOT use for A1 acceptance preview/tests.
# Visual F6 FAIL: backwards gait + anatomically wrong knees despite automated false positives.
# Acceptance uses Godot import-time humanoid retarget: uthana_a1_native_import.gd
extends RefCounted

const A1_STATUS := "FAILED_CUSTOM_GLOBAL_HIERARCHICAL_REST_DELTA"
const MESHY_GLB := "res://assets/prototype/3d/units/generated_warrior/generated_warrior_3d.glb"
const UTHANA_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0/generated_warrior_3d_uthana_rigged.glb"
)
const A1_DIR := "res://assets/prototype/3d/units/generated_warrior/uthana_a1/"
const SOURCE_BONEMAP_PATH := A1_DIR + "meshy_source_bonemap.tres"
const TARGET_BONEMAP_PATH := A1_DIR + "uthana_target_bonemap.tres"
const WALKING_LIBRARY_PATH := A1_DIR + "meshy_walking_on_uthana.res"
const NOTES_PATH := A1_DIR + "A1_RETARGET_NOTES.md"

const WALKING_CLIP := "Walking"
## Preview scale matching WorldUnitsView MODEL_ROOT_SCALE (terrain S=1).
const PREVIEW_MODEL_SCALE := 0.30
## Meshy/Uthana authored facing is +Z. Preview camera looks from +Z → origin, so
## forward=+Z faces the camera. Production-world 180° yaw must NOT be applied here.
const PREVIEW_MODEL_YAW := 0.0
const RETARGET_METHOD := "global_hierarchical_rest_delta"
## After grounding, lowest toe/foot world Y over Walking must stay within this of 0.
const GROUND_CONTACT_TOLERANCE := 0.04
const FOOT_BONE_CANDIDATES: Array[String] = [
	"mixamorig_LeftToeBase",
	"mixamorig_RightToeBase",
	"mixamorig_LeftFoot",
	"mixamorig_RightFoot",
	"LeftToeBase",
	"RightToeBase",
	"LeftFoot",
	"RightFoot",
]

const MESHY_PROFILE_MAP: Dictionary = {
	"Hips": "Hips",
	"Spine": "Spine02",
	"Chest": "Spine01",
	"UpperChest": "Spine",
	"Neck": "neck",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg",
	"LeftLowerLeg": "LeftLeg",
	"LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg",
	"RightLowerLeg": "RightLeg",
	"RightFoot": "RightFoot",
	"RightToes": "RightToeBase",
}

const UTHANA_PROFILE_MAP: Dictionary = {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToes": "mixamorig_RightToeBase",
}

const REQUIRED_PROFILE_BONES: Array[String] = [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
]


static func build_bonemap(profile_to_skeleton: Dictionary) -> BoneMap:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_name in profile_to_skeleton.keys():
		bone_map.set_skeleton_bone_name(
			StringName(str(profile_name)), StringName(str(profile_to_skeleton[profile_name]))
		)
	return bone_map


static func make_source_bonemap() -> BoneMap:
	return build_bonemap(MESHY_PROFILE_MAP)


static func make_target_bonemap() -> BoneMap:
	return build_bonemap(UTHANA_PROFILE_MAP)


static func list_finger_bones(skeleton: Skeleton3D) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		var n: String = skeleton.get_bone_name(i)
		var low := n.to_lower()
		if (
			"thumb" in low
			or "index" in low
			or "middle" in low
			or "ring" in low
			or "pinky" in low
			or "little" in low
		):
			out.append(n)
	return out


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var found: Array = root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


static func find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var found: Array = root.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


static func bone_name_from_track_path(path: NodePath) -> String:
	var s := String(path)
	var idx := s.rfind(":")
	if idx < 0:
		return ""
	return s.substr(idx + 1)


static func _bone_order(skeleton: Skeleton3D) -> PackedInt32Array:
	var order: PackedInt32Array = PackedInt32Array()
	var pending: Array = []
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_parent(i) < 0:
			pending.append(i)
	while not pending.is_empty():
		var bi: int = int(pending.pop_front())
		order.append(bi)
		for j in skeleton.get_bone_count():
			if skeleton.get_bone_parent(j) == bi:
				pending.append(j)
	return order


static func _compute_global_rests(skeleton: Skeleton3D) -> Array:
	var globals: Array = []
	globals.resize(skeleton.get_bone_count())
	for bi in _bone_order(skeleton):
		var rest: Transform3D = skeleton.get_bone_rest(bi)
		var parent_i: int = skeleton.get_bone_parent(bi)
		if parent_i < 0:
			globals[bi] = rest
		else:
			globals[bi] = (globals[parent_i] as Transform3D) * rest
	return globals


static func _sample_source_locals(
	src_anim: Animation, src_skeleton: Skeleton3D, by_bone: Dictionary, t: float
) -> Array:
	var locals: Array = []
	locals.resize(src_skeleton.get_bone_count())
	for bi in src_skeleton.get_bone_count():
		locals[bi] = src_skeleton.get_bone_rest(bi)
	for bone_name in by_bone.keys():
		var bi2: int = src_skeleton.find_bone(str(bone_name))
		if bi2 < 0:
			continue
		var rest: Transform3D = src_skeleton.get_bone_rest(bi2)
		var tracks: Dictionary = by_bone[bone_name]
		var pos: Vector3 = rest.origin
		var quat: Quaternion = rest.basis.get_rotation_quaternion()
		var pos_ti: int = int(tracks["pos"])
		var rot_ti: int = int(tracks["rot"])
		if pos_ti >= 0:
			pos = src_anim.position_track_interpolate(pos_ti, t)
		if rot_ti >= 0:
			quat = src_anim.rotation_track_interpolate(rot_ti, t)
		locals[bi2] = Transform3D(Basis(quat).orthonormalized(), pos)
	return locals


static func _locals_to_globals(skeleton: Skeleton3D, locals: Array) -> Array:
	var globals: Array = []
	globals.resize(skeleton.get_bone_count())
	for bi in _bone_order(skeleton):
		var local_xf: Transform3D = locals[bi] as Transform3D
		var parent_i: int = skeleton.get_bone_parent(bi)
		if parent_i < 0:
			globals[bi] = local_xf
		else:
			globals[bi] = (globals[parent_i] as Transform3D) * local_xf
	return globals


static func _build_profile_pairs(src_map: BoneMap, tgt_map: BoneMap) -> Array:
	var pairs: Array = []
	for profile_name in MESHY_PROFILE_MAP.keys():
		var sn := StringName(str(profile_name))
		var src_bone: String = String(src_map.get_skeleton_bone_name(sn))
		var tgt_bone: String = String(tgt_map.get_skeleton_bone_name(sn))
		if src_bone.is_empty() or tgt_bone.is_empty():
			continue
		pairs.append({"profile": str(profile_name), "source": src_bone, "target": tgt_bone})
	return pairs


## Global hierarchical retarget:
## desired_tgt_global = tgt_global_rest * inv(src_global_rest) * src_global_anim
## then convert to parent-local tracks. Unmapped bones (fingers) get no tracks.
static func retarget_walking_animation(
	src_anim: Animation,
	src_skeleton: Skeleton3D,
	tgt_skeleton: Skeleton3D,
	src_map: BoneMap,
	tgt_map: BoneMap,
	tgt_track_prefix: String = "Armature/Skeleton3D"
) -> Dictionary:
	var result := {
		"ok": false,
		"animation": null,
		"mapped_bones": [],
		"skipped_source_bones": [],
		"missing_target": [],
		"track_count": 0,
		"method": RETARGET_METHOD,
		"det_ok": true,
		"reason": "",
	}
	if src_anim == null or src_skeleton == null or tgt_skeleton == null:
		result["reason"] = "missing_input"
		return result
	if src_map == null or tgt_map == null:
		result["reason"] = "missing_bonemap"
		return result

	var by_bone: Dictionary = {}
	for ti in src_anim.get_track_count():
		var bone: String = bone_name_from_track_path(src_anim.track_get_path(ti))
		if bone.is_empty():
			continue
		if not by_bone.has(bone):
			by_bone[bone] = {"pos": -1, "rot": -1}
		var entry: Dictionary = by_bone[bone]
		match src_anim.track_get_type(ti):
			Animation.TYPE_POSITION_3D:
				entry["pos"] = ti
			Animation.TYPE_ROTATION_3D:
				entry["rot"] = ti
		by_bone[bone] = entry

	var skipped: Array = []
	for bone_name in by_bone.keys():
		var profile_name: StringName = src_map.find_profile_bone_name(StringName(str(bone_name)))
		if String(profile_name).is_empty():
			skipped.append(str(bone_name))
	result["skipped_source_bones"] = skipped

	var pairs: Array = _build_profile_pairs(src_map, tgt_map)
	if pairs.is_empty():
		result["reason"] = "no_mapped_tracks"
		return result

	var src_to_tgt: Dictionary = {}  # src_bone_idx -> tgt_bone_idx
	var tgt_mapped: Dictionary = {}  # tgt_bone_idx -> true
	var mapped_meta: Array = []
	var missing: Array = []
	for pair in pairs:
		var s_name: String = str(pair["source"])
		var t_name: String = str(pair["target"])
		var si: int = src_skeleton.find_bone(s_name)
		var ti_bone: int = tgt_skeleton.find_bone(t_name)
		if si < 0 or ti_bone < 0:
			missing.append("%s→%s" % [s_name, t_name])
			continue
		src_to_tgt[si] = ti_bone
		tgt_mapped[ti_bone] = true
		mapped_meta.append(pair)
	result["missing_target"] = missing
	result["mapped_bones"] = mapped_meta
	if src_to_tgt.is_empty():
		result["reason"] = "no_mapped_tracks"
		return result

	var src_global_rest: Array = _compute_global_rests(src_skeleton)
	var tgt_global_rest: Array = _compute_global_rests(tgt_skeleton)
	var tgt_order: PackedInt32Array = _bone_order(tgt_skeleton)

	# Sample times: key union + uniform 30 Hz.
	var times: Dictionary = {}
	for bone_name2 in by_bone.keys():
		var tr: Dictionary = by_bone[bone_name2]
		for key in ["pos", "rot"]:
			var track_i: int = int(tr[key])
			if track_i < 0:
				continue
			for ki in src_anim.track_get_key_count(track_i):
				times[src_anim.track_get_key_time(track_i, ki)] = true
	var dt := 1.0 / 30.0
	var t_cursor := 0.0
	while t_cursor <= src_anim.length + 1e-6:
		times[minf(t_cursor, src_anim.length)] = true
		t_cursor += dt
	var time_list: Array = times.keys()
	time_list.sort()

	# Prepare output tracks for every mapped target bone.
	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = Animation.LOOP_LINEAR
	out.step = src_anim.step
	var pos_track_of: Dictionary = {}
	var rot_track_of: Dictionary = {}
	for ti_bone2 in tgt_mapped.keys():
		var bname: String = tgt_skeleton.get_bone_name(int(ti_bone2))
		var path := NodePath("%s:%s" % [tgt_track_prefix, bname])
		var pti: int = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pti, path)
		var rti: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rti, path)
		pos_track_of[int(ti_bone2)] = pti
		rot_track_of[int(ti_bone2)] = rti

	var det_ok := true
	for t_variant in time_list:
		var t: float = float(t_variant)
		var src_locals: Array = _sample_source_locals(src_anim, src_skeleton, by_bone, t)
		var src_globals: Array = _locals_to_globals(src_skeleton, src_locals)

		var desired_tgt: Array = []
		desired_tgt.resize(tgt_skeleton.get_bone_count())
		for bi in tgt_skeleton.get_bone_count():
			desired_tgt[bi] = null

		for src_i in src_to_tgt.keys():
			var tgt_i: int = int(src_to_tgt[src_i])
			var sgr: Transform3D = src_global_rest[int(src_i)]
			var sga: Transform3D = src_globals[int(src_i)]
			var tgr: Transform3D = tgt_global_rest[tgt_i]
			# Global rotation delta from source rest → apply on target rest basis.
			var r_delta: Basis = sgr.basis.inverse() * sga.basis
			var r_desired: Basis = (tgr.basis * r_delta).orthonormalized()
			if r_desired.determinant() <= 0.0:
				det_ok = false
				r_desired = Basis.looking_at(r_desired.z, Vector3.UP)
			var desired_origin: Vector3 = tgr.origin
			if tgt_skeleton.get_bone_name(tgt_i) == "mixamorig_Hips":
				# Hips keep translational delta (in-place bob / sway).
				var rel_xf: Transform3D = sgr.affine_inverse() * sga
				desired_origin = tgr.origin + rel_xf.origin
			desired_tgt[tgt_i] = Transform3D(r_desired, desired_origin)

		# Unmapped: follow parent with rest local (fingers stay posed relative to hand).
		for bi3 in tgt_order:
			if desired_tgt[bi3] != null:
				continue
			var parent_i: int = tgt_skeleton.get_bone_parent(bi3)
			var rest_l: Transform3D = tgt_skeleton.get_bone_rest(bi3)
			if parent_i < 0:
				desired_tgt[bi3] = Transform3D(
					(tgt_global_rest[bi3] as Transform3D).basis,
					(tgt_global_rest[bi3] as Transform3D).origin
				)
			else:
				desired_tgt[bi3] = (desired_tgt[parent_i] as Transform3D) * rest_l

		# Mapped bones: rebuild as parent_desired * Transform(local_rot, rest_origin)
		# so bone lengths stay exactly the target rest lengths.
		for bi4 in tgt_order:
			if not tgt_mapped.has(bi4):
				continue
			var parent_i4: int = tgt_skeleton.get_bone_parent(bi4)
			var rest_l4: Transform3D = tgt_skeleton.get_bone_rest(bi4)
			var desired_g: Transform3D = desired_tgt[bi4] as Transform3D
			var parent_g4: Transform3D = Transform3D.IDENTITY
			if parent_i4 >= 0:
				parent_g4 = desired_tgt[parent_i4] as Transform3D
			var local_basis: Basis = (
				parent_g4.basis.inverse() * desired_g.basis
			).orthonormalized()
			if local_basis.determinant() <= 0.0:
				det_ok = false
				local_basis = Basis.IDENTITY
			var local_origin: Vector3 = rest_l4.origin
			if tgt_skeleton.get_bone_name(bi4) == "mixamorig_Hips":
				local_origin = desired_g.origin  # hips parent is root
			var local_xf4 := Transform3D(local_basis, local_origin)
			desired_tgt[bi4] = parent_g4 * local_xf4

		# Extract parent-local poses for mapped bones and write keys.
		for tgt_i2 in tgt_mapped.keys():
			var ti2: int = int(tgt_i2)
			var parent_i2: int = tgt_skeleton.get_bone_parent(ti2)
			var parent_g: Transform3D = Transform3D.IDENTITY
			if parent_i2 >= 0:
				parent_g = desired_tgt[parent_i2] as Transform3D
			var local_xf: Transform3D = parent_g.affine_inverse() * (desired_tgt[ti2] as Transform3D)
			var basis_n: Basis = local_xf.basis.orthonormalized()
			if basis_n.determinant() <= 0.0:
				det_ok = false
				basis_n = Basis.IDENTITY
			out.position_track_insert_key(int(pos_track_of[ti2]), t, local_xf.origin)
			out.rotation_track_insert_key(
				int(rot_track_of[ti2]), t, basis_n.get_rotation_quaternion()
			)

	result["ok"] = true
	result["animation"] = out
	result["track_count"] = out.get_track_count()
	result["det_ok"] = det_ok
	return result


## Identity check: feeding source rests must reproduce target rests (mapped bones).
static func verify_identity_rest_retarget(
	src_skeleton: Skeleton3D, tgt_skeleton: Skeleton3D, src_map: BoneMap, tgt_map: BoneMap
) -> Dictionary:
	var anim := Animation.new()
	anim.length = 0.1
	# Empty tracks → sampler uses rests only.
	var ret: Dictionary = retarget_walking_animation(
		anim, src_skeleton, tgt_skeleton, src_map, tgt_map
	)
	var out := {
		"ok": false,
		"max_pos_err": INF,
		"max_rot_err": INF,
		"reason": "",
	}
	if not bool(ret.get("ok", false)):
		out["reason"] = str(ret.get("reason", "retarget_failed"))
		return out
	var out_anim: Animation = ret["animation"] as Animation
	var max_rot := 0.0
	var max_pos := 0.0
	for ti2 in out_anim.get_track_count():
		var bone2: String = bone_name_from_track_path(out_anim.track_get_path(ti2))
		var bi2: int = tgt_skeleton.find_bone(bone2)
		if bi2 < 0:
			continue
		var rest2: Transform3D = tgt_skeleton.get_bone_rest(bi2)
		if out_anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D:
			var p2: Vector3 = out_anim.position_track_interpolate(ti2, 0.0)
			max_pos = maxf(max_pos, p2.distance_to(rest2.origin))
		elif out_anim.track_get_type(ti2) == Animation.TYPE_ROTATION_3D:
			var q2: Quaternion = out_anim.rotation_track_interpolate(ti2, 0.0)
			var qrest2: Quaternion = rest2.basis.get_rotation_quaternion()
			max_rot = maxf(max_rot, q2.angle_to(qrest2))
	out["max_pos_err"] = max_pos
	out["max_rot_err"] = max_rot
	out["ok"] = max_pos < 1e-3 and max_rot < 1e-3
	if not out["ok"]:
		out["reason"] = "rest_mismatch"
	return out


static func measure_forward_xz(skeleton: Skeleton3D) -> Vector3:
	var hips := skeleton.find_bone("mixamorig_Hips")
	if hips < 0:
		hips = skeleton.find_bone("Hips")
	var ltoe := skeleton.find_bone("mixamorig_LeftToeBase")
	if ltoe < 0:
		ltoe = skeleton.find_bone("LeftToeBase")
	var rtoe := skeleton.find_bone("mixamorig_RightToeBase")
	if rtoe < 0:
		rtoe = skeleton.find_bone("RightToeBase")
	if hips < 0 or ltoe < 0 or rtoe < 0:
		return Vector3(0, 0, 1)
	var ho: Vector3 = skeleton.get_bone_global_rest(hips).origin
	var mid: Vector3 = (
		skeleton.get_bone_global_rest(ltoe).origin + skeleton.get_bone_global_rest(rtoe).origin
	) * 0.5
	var f := Vector3(mid.x - ho.x, 0.0, mid.z - ho.z)
	if f.length_squared() < 1e-8:
		return Vector3(0, 0, 1)
	return f.normalized()


static func build_derived_resources(host: Node) -> Dictionary:
	var report := {
		"ok": false,
		"walking_library_path": WALKING_LIBRARY_PATH,
		"source_bonemap_path": SOURCE_BONEMAP_PATH,
		"target_bonemap_path": TARGET_BONEMAP_PATH,
		"clip": WALKING_CLIP,
		"duration": 0.0,
		"mapped_bones": [],
		"skipped_source_bones": [],
		"finger_bones_preserved": [],
		"root_motion": {},
		"method": RETARGET_METHOD,
		"preview_yaw": PREVIEW_MODEL_YAW,
		"identity_rest": {},
		"reason": "",
	}
	if host == null or not host.is_inside_tree():
		report["reason"] = "host_not_in_tree"
		return report
	if not ResourceLoader.exists(MESHY_GLB) or not ResourceLoader.exists(UTHANA_GLB):
		report["reason"] = "glb_missing"
		return report

	var src_map: BoneMap = make_source_bonemap()
	var tgt_map: BoneMap = make_target_bonemap()
	var save_flags := ResourceSaver.FLAG_CHANGE_PATH
	if ResourceSaver.save(src_map, SOURCE_BONEMAP_PATH, save_flags) != OK:
		report["reason"] = "bonemap_save_failed"
		return report
	if ResourceSaver.save(tgt_map, TARGET_BONEMAP_PATH, save_flags) != OK:
		report["reason"] = "bonemap_save_failed"
		return report

	var meshy_root: Node3D = (load(MESHY_GLB) as PackedScene).instantiate() as Node3D
	var uthana_root: Node3D = (load(UTHANA_GLB) as PackedScene).instantiate() as Node3D
	host.add_child(meshy_root)
	host.add_child(uthana_root)

	var src_sk: Skeleton3D = find_skeleton(meshy_root)
	var tgt_sk: Skeleton3D = find_skeleton(uthana_root)
	var src_player: AnimationPlayer = find_animation_player(meshy_root)
	if src_sk == null or tgt_sk == null or src_player == null:
		meshy_root.queue_free()
		uthana_root.queue_free()
		report["reason"] = "skeleton_or_player_missing"
		return report
	if not src_player.has_animation(WALKING_CLIP):
		meshy_root.queue_free()
		uthana_root.queue_free()
		report["reason"] = "walking_clip_missing"
		return report

	var identity: Dictionary = verify_identity_rest_retarget(src_sk, tgt_sk, src_map, tgt_map)
	report["identity_rest"] = identity

	var src_anim: Animation = src_player.get_animation(WALKING_CLIP)
	report["root_motion"] = analyze_hips_root_motion(src_anim, src_sk)
	var retargeted: Dictionary = retarget_walking_animation(
		src_anim, src_sk, tgt_sk, src_map, tgt_map, "Armature/Skeleton3D"
	)
	report["mapped_bones"] = retargeted.get("mapped_bones", [])
	report["skipped_source_bones"] = retargeted.get("skipped_source_bones", [])
	report["finger_bones_preserved"] = Array(list_finger_bones(tgt_sk))

	if not bool(retargeted.get("ok", false)):
		meshy_root.queue_free()
		uthana_root.queue_free()
		report["reason"] = str(retargeted.get("reason", "retarget_failed"))
		return report
	if not bool(retargeted.get("det_ok", true)):
		meshy_root.queue_free()
		uthana_root.queue_free()
		report["reason"] = "reflected_basis"
		return report

	var out_anim: Animation = retargeted["animation"] as Animation
	report["duration"] = out_anim.length
	var lib := AnimationLibrary.new()
	lib.add_animation(WALKING_CLIP, out_anim)
	# Avoid "cyclic resource inclusion" when overwriting a library already in cache.
	if ResourceLoader.exists(WALKING_LIBRARY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WALKING_LIBRARY_PATH))
	if ResourceSaver.save(lib, WALKING_LIBRARY_PATH, save_flags) != OK:
		meshy_root.queue_free()
		uthana_root.queue_free()
		report["reason"] = "library_save_failed"
		return report

	meshy_root.queue_free()
	uthana_root.queue_free()
	_write_notes(report)
	report["ok"] = true
	return report


static func analyze_hips_root_motion(anim: Animation, _skeleton: Skeleton3D) -> Dictionary:
	var info := {
		"has_hips_position_track": false,
		"start": Vector3.ZERO,
		"end": Vector3.ZERO,
		"max_horizontal_excursion": 0.0,
		"effectively_in_place": true,
	}
	if anim == null:
		return info
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if bone_name_from_track_path(anim.track_get_path(ti)) != "Hips":
			continue
		info["has_hips_position_track"] = true
		var keys: int = anim.track_get_key_count(ti)
		if keys < 1:
			break
		var start_v: Vector3 = anim.track_get_key_value(ti, 0)
		var end_v: Vector3 = anim.track_get_key_value(ti, keys - 1)
		info["start"] = start_v
		info["end"] = end_v
		var max_ex := 0.0
		var origin_xz := Vector2(start_v.x, start_v.z)
		for ki in keys:
			var v: Vector3 = anim.track_get_key_value(ti, ki)
			max_ex = maxf(max_ex, Vector2(v.x, v.z).distance_to(origin_xz))
		info["max_horizontal_excursion"] = max_ex
		info["effectively_in_place"] = start_v.distance_to(end_v) < 0.5 and max_ex < 15.0
		break
	return info


## Load retargeted library, rebuilding when missing or `force_rebuild`.
static func ensure_walking_library(host: Node, force_rebuild: bool = false) -> AnimationLibrary:
	if force_rebuild or not ResourceLoader.exists(WALKING_LIBRARY_PATH):
		var report: Dictionary = build_derived_resources(host)
		if not bool(report.get("ok", false)):
			push_error("uthana_a1_retarget: build failed: %s" % report.get("reason", "?"))
			return null
	return ResourceLoader.load(
		WALKING_LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary


static func mapping_coverage_ok(src_map: BoneMap, tgt_map: BoneMap) -> Dictionary:
	var missing_src: Array = []
	var missing_tgt: Array = []
	for profile_name in REQUIRED_PROFILE_BONES:
		var sn: StringName = StringName(profile_name)
		if String(src_map.get_skeleton_bone_name(sn)).is_empty():
			missing_src.append(profile_name)
		if String(tgt_map.get_skeleton_bone_name(sn)).is_empty():
			missing_tgt.append(profile_name)
	return {
		"ok": missing_src.is_empty() and missing_tgt.is_empty(),
		"missing_source": missing_src,
		"missing_target": missing_tgt,
	}


static func left_right_mapping_ok(src_map: BoneMap, tgt_map: BoneMap) -> bool:
	for profile_name in MESHY_PROFILE_MAP.keys():
		var sn := StringName(str(profile_name))
		var src_b := String(src_map.get_skeleton_bone_name(sn))
		var tgt_b := String(tgt_map.get_skeleton_bone_name(sn))
		var pref := str(profile_name)
		if pref.begins_with("Left"):
			if not src_b.contains("Left") or not tgt_b.contains("Left"):
				return false
			if src_b.contains("Right") or tgt_b.contains("Right"):
				return false
		if pref.begins_with("Right"):
			if not src_b.contains("Right") or not tgt_b.contains("Right"):
				return false
			if src_b.contains("Left") or tgt_b.contains("Left"):
				return false
	return true


## Lowest world-space Y among foot/toe bones (skinned contact proxy).
static func measure_lowest_foot_y(skeleton: Skeleton3D) -> float:
	if skeleton == null:
		return 0.0
	var lowest := INF
	for bone_name in FOOT_BONE_CANDIDATES:
		var bi: int = skeleton.find_bone(bone_name)
		if bi < 0:
			continue
		var y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(bi)).origin.y
		lowest = minf(lowest, y)
	if lowest >= INF:
		return 0.0
	return lowest


## Sample Walking (or rest) and return diagnostics for ground placement.
## `lift_y` applied to model_root.position.y before measuring is optional (0 = ungrounded).
static func sample_ground_contact(
	skeleton: Skeleton3D,
	player: AnimationPlayer,
	clip_id: String,
	sample_count: int = 21
) -> Dictionary:
	var out := {
		"ok": false,
		"lowest_foot_y": 0.0,
		"highest_foot_min_y": 0.0,
		"foot_span": 0.0,
		"hips_y_min": 0.0,
		"hips_y_max": 0.0,
		"hips_span": 0.0,
		"constant_placement": false,
		"ground_offset_y": 0.0,
	}
	if skeleton == null:
		return out
	var hips_i: int = skeleton.find_bone("mixamorig_Hips")
	if hips_i < 0:
		hips_i = skeleton.find_bone("Hips")
	var foot_mins: Array = []
	var hips_ys: Array = []
	if player != null and not clip_id.is_empty() and player.has_animation(clip_id):
		var anim: Animation = player.get_animation(clip_id)
		var n: int = maxi(sample_count, 2)
		for i in n:
			var t: float = float(i) / float(n - 1) * anim.length
			player.seek(t, true)
			skeleton.force_update_all_bone_transforms()
			foot_mins.append(measure_lowest_foot_y(skeleton))
			if hips_i >= 0:
				hips_ys.append(
					(skeleton.global_transform * skeleton.get_bone_global_pose(hips_i)).origin.y
				)
	else:
		skeleton.force_update_all_bone_transforms()
		foot_mins.append(measure_lowest_foot_y(skeleton))
		if hips_i >= 0:
			hips_ys.append(
				(skeleton.global_transform * skeleton.get_bone_global_pose(hips_i)).origin.y
			)
	var low_f: float = float(foot_mins.min())
	var high_f: float = float(foot_mins.max())
	out["lowest_foot_y"] = low_f
	out["highest_foot_min_y"] = high_f
	out["foot_span"] = high_f - low_f
	if not hips_ys.is_empty():
		out["hips_y_min"] = float(hips_ys.min())
		out["hips_y_max"] = float(hips_ys.max())
		out["hips_span"] = float(hips_ys.max()) - float(hips_ys.min())
	# Constant placement if foot contact band is small vs character scale.
	out["constant_placement"] = out["foot_span"] < 0.05
	# Lift so the lowest sampled contact sits on Y=0; preserves hip bob.
	out["ground_offset_y"] = -low_f
	out["ok"] = true
	return out


static func _write_notes(report: Dictionary) -> void:
	var root_motion: Dictionary = report.get("root_motion", {})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# A1 Uthana retarget notes")
	lines.append("")
	lines.append("## Method")
	lines.append("- `%s`" % RETARGET_METHOD)
	lines.append(
		"- BoneMaps pair Meshy↔Uthana names through `SkeletonProfileHumanoid`."
	)
	lines.append(
		"- Animation uses **global rotation rest-deltas** with **target rest local "
		+ "translations** preserved (bone lengths stable). Hips also take translation delta."
	)
	lines.append(
		"- desired_basis = tgt_global_rest.basis * inv(src_global_rest.basis) * src_global_anim.basis; "
		+ "local.origin from target rest (except hips)."
	)
	lines.append(
		"- Replaces broken local `tgt_rest * inv(src_rest) * src_pose`, which failed across "
		+ "Meshy A-pose vs Uthana T-pose bone axes."
	)
	lines.append("")
	lines.append("## Paths")
	lines.append("- Meshy source (immutable): `%s`" % MESHY_GLB)
	lines.append("- Uthana target (immutable): `%s`" % UTHANA_GLB)
	lines.append("- Source BoneMap: `%s`" % SOURCE_BONEMAP_PATH)
	lines.append("- Target BoneMap: `%s`" % TARGET_BONEMAP_PATH)
	lines.append("- Retargeted library: `%s`" % WALKING_LIBRARY_PATH)
	lines.append("")
	lines.append("## Scale / orientation")
	lines.append("- Both armatures keep imported scale `0.01` (not rewritten).")
	lines.append("- Preview ModelRoot scale `%.2f`." % PREVIEW_MODEL_SCALE)
	lines.append(
		"- Preview ModelRoot yaw `%.1f` rad (no production 180° flip)." % PREVIEW_MODEL_YAW
	)
	lines.append("- Authored forward is +Z (toe direction); preview faces the camera.")
	lines.append("- Finger bones have no tracks and remain at Uthana rest for A2 grip.")
	lines.append(
		"- Preview ground: automatic `ModelRoot.position.y = -min(foot/toe Y over Walking)`; "
		+ "constant placement offset (not hips-scale retarget). GLBs untouched."
	)
	lines.append("")
	lines.append("## Walking root motion")
	lines.append("- Duration: `%.4f` s" % float(report.get("duration", 0.0)))
	lines.append("- Effectively in-place: `%s`" % str(root_motion.get("effectively_in_place", true)))
	lines.append(
		"- Max horizontal excursion: `%.4f`"
		% float(root_motion.get("max_horizontal_excursion", 0.0))
	)
	lines.append("")
	lines.append("## Launch")
	lines.append(
		"Open `res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_walking_preview.tscn` (F6)."
	)
	var f := FileAccess.open(NOTES_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
