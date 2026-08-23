# A2 power_grip_v1: canonical authored power-grip pose + bounded radius
# refinement (audit Section 6 hybrid). Never free CCD: the correctness layer
# is the socket frame mapping + the canonical pose; refinement only adjusts
# flexion within ±15 deg from measured pad gaps and degrades to the canonical
# pose on failure. Post-animation, deterministic, reversible.
class_name UthanaA2PowerGrip
extends SkeletonModifier3D

const Pads = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_skinned_pads.gd"
)
const GripShape = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_grip_shape.gd"
)

const GRIP_ID := "power_grip_v1"

const RIGHT_CHAINS: Dictionary = {
	"thumb": [
		"mixamorig_RightHandThumb1",
		"mixamorig_RightHandThumb2",
		"mixamorig_RightHandThumb3",
	],
	"index": [
		"mixamorig_RightHandIndex1",
		"mixamorig_RightHandIndex2",
		"mixamorig_RightHandIndex3",
	],
	"middle": [
		"mixamorig_RightHandMiddle1",
		"mixamorig_RightHandMiddle2",
		"mixamorig_RightHandMiddle3",
	],
	"ring": [
		"mixamorig_RightHandRing1",
		"mixamorig_RightHandRing2",
		"mixamorig_RightHandRing3",
	],
	"pinky": [
		"mixamorig_RightHandPinky1",
		"mixamorig_RightHandPinky2",
		"mixamorig_RightHandPinky3",
	],
}
const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]
const ALL_DIGITS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]

const LEFT_PROBE_BONES: Array[String] = [
	"LeftHand",
	"mixamorig_LeftHandIndex1",
	"mixamorig_LeftHandThumb1",
]

## Canonical authored power-grip flexion per chain joint (degrees, positive =
## closing toward the palm; the measured per-rig sign is applied at bind).
## Authored once for the EoM 52-bone skeleton profile.
const CANON_FLEX_DEG: Dictionary = {
	"index": [60.0, 71.0, 35.0],
	"middle": [63.0, 75.0, 37.0],
	"ring": [69.0, 81.0, 40.0],
	"pinky": [71.0, 83.0, 43.0],
}
## Canonical thumb pose (local euler, degrees; X scaled by the rig flexion
## sign, Y/Z authored in the measured Uthana local convention). Calibrated
## numerically so the thumb pad opposes the finger cluster across the shaft.
const CANON_THUMB_DEG: Array = [
	Vector3(10.0, 60.0, -45.0),
	Vector3(12.0, 0.0, 0.0),
	Vector3(12.0, 0.0, 0.0),
]

## Bounded refinement: flex delta from canonical, clamped, capped iterations.
const REFINE_DELTA_MAX := 0.2618  # 15 deg
const REFINE_ITERS := 10
const REFINE_WEIGHTS: Array[float] = [1.0, 0.7, 0.4]
const REFINE_STEP_MAX := 0.10
## Signed-gap comfort band in grip radii: close if above, open if below.
const GAP_BAND_HI_RADII := 0.20
const GAP_BAND_LO_RADII := -0.05

var grip_enabled: bool = true
var debug_selected_finger: String = "index"

var _bound := false
var _character: Node = null
var _club: Node3D = null
var _shape: Dictionary = {}
var _pad_locals: Dictionary = {}
var _chain_indices: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _flex_sign: Dictionary = {}
var _chain_lengths: Dictionary = {}
var _left_probe_indices: Array[int] = []
var _right_hand_idx: int = -1
var _right_forearm_idx: int = -1
var _modification_count: int = 0
var _last_diagnostics: Dictionary = {}


## frame: pose-mode hand grip frame (uthana_a2_hand_grip_frame.gd), already
## volar-verified by the attachment before this call.
func configure(
	character: Node, club: Node3D, shape: Dictionary, frame: Dictionary
) -> Dictionary:
	_character = character
	_club = club
	_shape = shape.duplicate(true)
	var skel := _resolve_skeleton()
	if skel == null:
		return {"ok": false, "reason": "no_skeleton"}
	if not bool(_shape.get("ok", false)):
		return {"ok": false, "reason": "bad_shape"}
	if not bool(frame.get("ok", false)):
		return {"ok": false, "reason": "bad_hand_frame"}
	if not _bind_bones(skel):
		return {"ok": false, "reason": "bind_bones_failed"}

	# Measured per-finger closing sign: rotating by s*angle about the bone
	# local X must arc the extended tip toward the volar side (+V) so the
	# finger curls around the shaft. s = sign((w x L).V).
	var longitudinal: Vector3 = frame["longitudinal"]
	var volar: Vector3 = frame["volar"]
	var hinges: Dictionary = frame["hinge"]
	for finger in FINGERS:
		var w: Vector3 = hinges[finger]
		var closing: float = (w.cross(longitudinal)).dot(volar)
		if absf(closing) < 0.2:
			return {
				"ok": false,
				"reason": "flexion_sign_ambiguous",
				"error_class": "GRIP_FLEXION_SIGN_AMBIGUOUS",
				"finger": finger,
				"closing": closing,
			}
		_flex_sign[finger] = 1.0 if closing > 0.0 else -1.0
	# Rig-level convention: the thumb shares the modeling flexion sign.
	_flex_sign["thumb"] = _flex_sign["index"]
	_chain_lengths = (frame["chain_length"] as Dictionary).duplicate()
	_chain_lengths["thumb"] = _chain_lengths.get("index", 0.02)

	var pads: Dictionary = Pads.bind_pad_locals(character, skel, volar)
	if not bool(pads.get("ok", false)):
		return {"ok": false, "reason": "pad_bind_failed", "pads": pads}
	_pad_locals = pads["pads"]
	_bound = true
	return {
		"ok": true,
		"grip_id": GRIP_ID,
		"flex_sign": _flex_sign.duplicate(),
		"pad_vertex_counts": pads.get("vertex_counts", {}),
		"shape": _shape,
	}


func set_club(club: Node3D) -> void:
	_club = club


func set_grip_enabled(enabled: bool) -> void:
	grip_enabled = enabled
	if not enabled:
		_clear_to_rest()
		_last_diagnostics = {}


func is_grip_enabled() -> bool:
	return grip_enabled


func modification_count() -> int:
	return _modification_count


func is_bound() -> bool:
	return _bound


func last_diagnostics() -> Dictionary:
	return _last_diagnostics.duplicate(true)


func finger_diagnostic(finger: String) -> Dictionary:
	return _last_diagnostics.get(finger, {})


func right_hand_bone_index() -> int:
	return _right_hand_idx


func right_forearm_bone_index() -> int:
	return _right_forearm_idx


func left_probe_indices() -> Array[int]:
	return _left_probe_indices.duplicate()


func bound_finger_names() -> PackedStringArray:
	var names := PackedStringArray()
	var skel := _resolve_skeleton()
	if skel == null:
		return names
	for finger in ALL_DIGITS:
		for bi in _chain_indices.get(finger, []):
			names.append(skel.get_bone_name(int(bi)))
	return names


func apply_now() -> void:
	_process_modification()


func _resolve_skeleton() -> Skeleton3D:
	var skel := get_skeleton()
	if skel != null:
		return skel
	return get_parent() as Skeleton3D


func _bind_bones(skel: Skeleton3D) -> bool:
	_chain_indices.clear()
	_rest_rotations.clear()
	_left_probe_indices.clear()
	_right_hand_idx = skel.find_bone("RightHand")
	_right_forearm_idx = skel.find_bone("RightLowerArm")
	if _right_forearm_idx < 0:
		_right_forearm_idx = skel.find_bone("RightForeArm")
	for finger in ALL_DIGITS:
		var idxs: Array[int] = []
		for bname in RIGHT_CHAINS[finger]:
			var i: int = skel.find_bone(str(bname))
			if i < 0:
				return false
			idxs.append(i)
			_rest_rotations[i] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_chain_indices[finger] = idxs
	for bname in LEFT_PROBE_BONES:
		var li: int = skel.find_bone(bname)
		if li >= 0:
			_left_probe_indices.append(li)
	return true


func _process_modification() -> void:
	_modification_count += 1
	if not _bound:
		return
	if not grip_enabled:
		_clear_to_rest()
		return
	_solve()


func _clear_to_rest() -> void:
	var skel := _resolve_skeleton()
	if skel == null:
		return
	for finger in _chain_indices.keys():
		for bi in _chain_indices[finger]:
			skel.reset_bone_pose(int(bi))


func _set_finger_pose(skel: Skeleton3D, finger: String, delta: float) -> void:
	var chain: Array = _chain_indices[finger]
	var s: float = float(_flex_sign[finger])
	var canon: Array = CANON_FLEX_DEG[finger]
	for ji in 3:
		var bone_i: int = int(chain[ji])
		var angle: float = deg_to_rad(float(canon[ji])) + delta * REFINE_WEIGHTS[ji]
		angle = maxf(angle, 0.0)
		var flex := Quaternion(Vector3.RIGHT, s * angle)
		skel.set_bone_pose_rotation(
			bone_i, (_rest_rotations[bone_i] as Quaternion) * flex
		)


func _set_thumb_pose(skel: Skeleton3D, delta: float) -> void:
	var chain: Array = _chain_indices["thumb"]
	var s: float = float(_flex_sign["thumb"])
	for ji in 3:
		var bone_i: int = int(chain[ji])
		var e: Vector3 = CANON_THUMB_DEG[ji]
		var flex_x: float = deg_to_rad(e.x)
		if ji > 0:
			flex_x = maxf(flex_x + delta * REFINE_WEIGHTS[ji], 0.0)
		var q := Quaternion.from_euler(
			Vector3(s * flex_x, deg_to_rad(e.y), deg_to_rad(e.z))
		)
		skel.set_bone_pose_rotation(
			bone_i, (_rest_rotations[bone_i] as Quaternion) * q
		)


func _signed_gap(world_p: Vector3) -> float:
	# Radii live in the socket/parent metric space (post-normalize).
	var parent: Node3D = _club.get_parent() as Node3D
	var local: Vector3
	if parent != null:
		local = parent.to_local(world_p)
	else:
		local = _club.global_transform.affine_inverse() * world_p
	return GripShape.signed_gap_local(
		local, float(_shape.get("radius_x", 0.01)), float(_shape.get("radius_z", 0.01))
	)


func _refine_digit(skel: Skeleton3D, digit: String, r_mean: float) -> Dictionary:
	var pad_local: Vector3 = _pad_locals.get(digit, Vector3.ZERO) as Vector3
	var chain_len: float = maxf(float(_chain_lengths.get(digit, 0.02)), 1e-5)
	var hi: float = r_mean * GAP_BAND_HI_RADII
	var lo: float = r_mean * GAP_BAND_LO_RADII
	var delta := 0.0
	var iters := 0
	var clamped := false
	skel.force_update_all_bone_transforms()
	var gap0: float = _signed_gap(Pads.pad_world(skel, digit, pad_local))
	var gap: float = gap0
	# Best-so-far tracking: a worsening step is reverted, never kept — the
	# refinement can only improve on the canonical pose or fall back to it.
	var best_delta := 0.0
	var best_viol: float = _band_violation(gap0, lo, hi)
	# Direction: nominally close on a positive gap, but if the first step
	# worsens contact (pad arcing around the shaft), retry once in the
	# opposite direction. Still bounded and deterministic — never free CCD.
	var direction := 1.0
	var direction_flipped := false
	for _it in REFINE_ITERS:
		iters += 1
		if _band_violation(gap, lo, hi) <= 0.0:
			break
		var step: float = clampf(gap / chain_len, -REFINE_STEP_MAX, REFINE_STEP_MAX)
		step *= direction
		var next_delta: float = clampf(delta + step, -REFINE_DELTA_MAX, REFINE_DELTA_MAX)
		if is_equal_approx(next_delta, delta):
			clamped = true
			break
		delta = next_delta
		if absf(delta) >= REFINE_DELTA_MAX - 1e-6:
			clamped = true
		if digit == "thumb":
			_set_thumb_pose(skel, delta)
		else:
			_set_finger_pose(skel, digit, delta)
		skel.force_update_all_bone_transforms()
		gap = _signed_gap(Pads.pad_world(skel, digit, pad_local))
		var viol: float = _band_violation(gap, lo, hi)
		if viol < best_viol - 1e-9:
			best_viol = viol
			best_delta = delta
		elif viol > best_viol + 1e-9:
			if direction_flipped:
				break
			direction_flipped = true
			direction = -direction
			delta = best_delta
	if not is_equal_approx(delta, best_delta):
		if digit == "thumb":
			_set_thumb_pose(skel, best_delta)
		else:
			_set_finger_pose(skel, digit, best_delta)
		skel.force_update_all_bone_transforms()
		gap = _signed_gap(Pads.pad_world(skel, digit, pad_local))
	var classification := "refined"
	if _band_violation(gap, lo, hi) > 0.0:
		classification = "canonical_clamped" if clamped else "unconverged"
	return {
		"gap_initial_signed": gap0,
		"gap_final_signed": gap,
		"refine_delta": best_delta,
		"iterations": iters,
		"joint_limit_hit": clamped,
		"classification": classification,
	}


static func _band_violation(gap: float, lo: float, hi: float) -> float:
	return maxf(maxf(gap - hi, lo - gap), 0.0)


func _solve() -> void:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return
	_clear_to_rest()
	# Canonical authored pose first (the correctness layer).
	for finger in FINGERS:
		_set_finger_pose(skel, finger, 0.0)
	_set_thumb_pose(skel, 0.0)
	skel.force_update_all_bone_transforms()

	var r_mean: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-6)
	var diag := {}
	for digit in ALL_DIGITS:
		diag[digit] = _refine_digit(skel, digit, r_mean)
	skel.force_update_all_bone_transforms()

	# Achieved-contact diagnostics against the live shaft frame.
	var parent: Node3D = _club.get_parent() as Node3D
	var axis_xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var o: Vector3 = axis_xf.origin
	var d_axis: Vector3 = axis_xf.basis.y.normalized()
	var e1: Vector3 = axis_xf.basis.x.normalized()
	var e2: Vector3 = axis_xf.basis.z.normalized()

	var angles := {}
	var alongs := {}
	var radial_dirs := {}
	for digit in ALL_DIGITS:
		var pad: Vector3 = Pads.pad_world(
			skel, digit, _pad_locals.get(digit, Vector3.ZERO) as Vector3
		)
		var w: Vector3 = pad - o
		var along: float = w.dot(d_axis)
		var radial: Vector3 = w - d_axis * along
		var fd: Dictionary = diag[digit]
		fd["pad_final"] = pad
		var gap_signed: float = float(fd["gap_final_signed"])
		fd["gap_final"] = maxf(0.0, gap_signed)
		fd["penetration_final"] = maxf(0.0, -gap_signed)
		fd["gap_initial"] = maxf(0.0, float(fd["gap_initial_signed"]))
		fd["along_axis"] = along
		alongs[digit] = along
		if radial.length_squared() > 1e-14:
			var rd: Vector3 = radial.normalized()
			radial_dirs[digit] = rd
			angles[digit] = rad_to_deg(atan2(rd.dot(e2), rd.dot(e1)))
		diag[digit] = fd

	# Encirclement: circular coverage of achieved contact directions.
	var sorted_angles: Array[float] = []
	for digit in ALL_DIGITS:
		if angles.has(digit):
			sorted_angles.append(fposmod(float(angles[digit]), 360.0))
	sorted_angles.sort()
	var coverage := 0.0
	if sorted_angles.size() >= 2:
		var max_gap := 0.0
		for i in sorted_angles.size():
			var a: float = sorted_angles[i]
			var b: float = (
				sorted_angles[(i + 1) % sorted_angles.size()]
				+ (360.0 if i + 1 >= sorted_angles.size() else 0.0)
			)
			max_gap = maxf(max_gap, b - a)
		coverage = 360.0 - max_gap

	# Thumb opposition vs the mean four-finger radial direction.
	var opposition := 0.0
	var finger_mean := Vector3.ZERO
	for finger in FINGERS:
		if radial_dirs.has(finger):
			finger_mean += radial_dirs[finger] as Vector3
	if finger_mean.length_squared() > 1e-12 and radial_dirs.has("thumb"):
		opposition = finger_mean.normalized().dot(
			(radial_dirs["thumb"] as Vector3).normalized()
		)

	# Contact ordering along the shaft (head_side=radial: index highest).
	var ordering_ok := true
	for i in FINGERS.size() - 1:
		if float(alongs.get(FINGERS[i], 0.0)) <= float(alongs.get(FINGERS[i + 1], 0.0)):
			ordering_ok = false

	diag["grip_id"] = GRIP_ID
	diag["axis_origin"] = o
	diag["axis_dir"] = d_axis
	diag["volar_dir"] = e2
	diag["contact_angles_deg"] = angles
	diag["coverage_deg"] = coverage
	diag["opposition_dot"] = opposition
	diag["ordering_ok"] = ordering_ok
	_last_diagnostics = diag
