# Bind-pose right-hand palm frame for one-handed weapons (WorldMap path).
# Finger-root bones preferred; otherwise estimates knuckle centre from the
# hand bone axes and the equipment-profile hand-length ratio.
extends RefCounted

const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

## Candidate names for first joints of index / middle / ring / little.
const INDEX_ROOT_CANDIDATES: Array[String] = [
	"mixamorig_RightHandIndex1",
	"RightHandIndex1",
	"RightIndex1",
	"IndexFinger1_R",
	"hand_r_index_1",
	"RightHandIndex",
]
const MIDDLE_ROOT_CANDIDATES: Array[String] = [
	"mixamorig_RightHandMiddle1",
	"RightHandMiddle1",
	"RightMiddle1",
	"MiddleFinger1_R",
	"hand_r_middle_1",
	"RightHandMiddle",
]
const RING_ROOT_CANDIDATES: Array[String] = [
	"mixamorig_RightHandRing1",
	"RightHandRing1",
	"RightRing1",
	"RingFinger1_R",
	"hand_r_ring_1",
	"RightHandRing",
]
const LITTLE_ROOT_CANDIDATES: Array[String] = [
	"mixamorig_RightHandPinky1",
	"RightHandPinky1",
	"RightHandLittle1",
	"RightPinky1",
	"RightLittle1",
	"PinkyFinger1_R",
	"hand_r_pinky_1",
	"RightHandPinky",
]


static func _first_bone(skeleton: Skeleton3D, candidates: Array[String]) -> String:
	if skeleton == null:
		return ""
	for name_variant in candidates:
		var bone_name: String = str(name_variant)
		if skeleton.find_bone(bone_name) >= 0:
			return bone_name
	return ""


static func discover_finger_roots(skeleton: Skeleton3D) -> Dictionary:
	return {
		"index": _first_bone(skeleton, INDEX_ROOT_CANDIDATES),
		"middle": _first_bone(skeleton, MIDDLE_ROOT_CANDIDATES),
		"ring": _first_bone(skeleton, RING_ROOT_CANDIDATES),
		"little": _first_bone(skeleton, LITTLE_ROOT_CANDIDATES),
	}


static func has_usable_finger_roots(roots: Dictionary) -> bool:
	var found := 0
	for key in ["index", "middle", "ring", "little"]:
		if not str(roots.get(key, "")).is_empty():
			found += 1
	# Need at least two roots to form knuckle centre + across-palm.
	return found >= 2


## Ortho world transform matching equipment bone-follow (scale stripped).
static func ortho_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var g: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)
	return Transform3D(g.basis.orthonormalized(), g.origin)


static func ortho_global_pose(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var g: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	return Transform3D(g.basis.orthonormalized(), g.origin)


## Bind-pose humanoid height in the same world-metric space used for equipped
## props (ortho bone-follow): head_end − lowest toe, via global rest origins.
static func measure_humanoid_height(skeleton: Skeleton3D) -> float:
	if skeleton == null:
		return 0.0
	var head_i: int = skeleton.find_bone("head_end")
	if head_i < 0:
		head_i = skeleton.find_bone("Head")
	if head_i < 0:
		return 0.0
	var ymin := INF
	for toe_name in [
		"LeftToes",
		"RightToes",
		"LeftToeBase",
		"RightToeBase",
		"mixamorig_LeftToeBase",
		"mixamorig_RightToeBase",
		"LeftFoot",
		"RightFoot",
	]:
		var ti: int = skeleton.find_bone(toe_name)
		if ti < 0:
			continue
		var y: float = (skeleton.global_transform * skeleton.get_bone_global_rest(ti)).origin.y
		ymin = minf(ymin, y)
	if ymin >= INF:
		return 0.0
	var ymax: float = (
		skeleton.global_transform * skeleton.get_bone_global_rest(head_i)
	).origin.y
	return maxf(0.0, ymax - ymin)


## Build palm frame in bind pose. Returns:
## ok, has_fingers, finger_roots, wrist, knuckle_centre, palm_centre,
## longitudinal, across, normal, palm_basis, palm_local (relative to ortho
## RightHand rest), humanoid_height, hand_bone, estimated
static func compute_right_palm_frame(
	skeleton: Skeleton3D, right_hand_bone: String
) -> Dictionary:
	if skeleton == null or right_hand_bone.is_empty():
		return {"ok": false, "reason": "missing_skeleton_or_hand"}
	var hand_i: int = skeleton.find_bone(right_hand_bone)
	if hand_i < 0:
		return {"ok": false, "reason": "hand_bone_missing"}
	var height: float = measure_humanoid_height(skeleton)
	if height < 1e-6:
		return {"ok": false, "reason": "degenerate_height"}

	var hand_ortho: Transform3D = ortho_global_rest(skeleton, hand_i)
	var wrist: Vector3 = hand_ortho.origin
	var roots: Dictionary = discover_finger_roots(skeleton)
	var has_fingers: bool = has_usable_finger_roots(roots)

	var knuckle: Vector3
	var longitudinal: Vector3
	var across: Vector3
	var estimated := false

	if has_fingers:
		var sum := Vector3.ZERO
		var count := 0
		var positions: Dictionary = {}
		for key in ["index", "middle", "ring", "little"]:
			var bname: String = str(roots.get(key, ""))
			if bname.is_empty():
				continue
			var bi: int = skeleton.find_bone(bname)
			var p: Vector3 = ortho_global_rest(skeleton, bi).origin
			positions[key] = p
			sum += p
			count += 1
		knuckle = sum / float(count)
		longitudinal = (knuckle - wrist).normalized()
		var little_p: Vector3 = positions.get(
			"little", positions.get("ring", knuckle)
		) as Vector3
		var index_p: Vector3 = positions.get(
			"index", positions.get("middle", knuckle)
		) as Vector3
		across = (index_p - little_p)
		if across.length_squared() < 1e-10:
			across = hand_ortho.basis.x
		else:
			across = across.normalized()
	else:
		estimated = true
		# Mixamo-style: hand local +Y points along the fingers in rest.
		longitudinal = hand_ortho.basis.y.normalized()
		var hand_len: float = height * Profile.ESTIMATED_HAND_LENGTH_RATIO
		knuckle = wrist + longitudinal * hand_len
		across = hand_ortho.basis.x.normalized()

	# Orthonormal palm basis: +Y longitudinal, +X across (ortho), +Z normal.
	across = (across - longitudinal * across.dot(longitudinal)).normalized()
	if across.length_squared() < 1e-10:
		across = longitudinal.cross(Vector3.UP)
		if across.length_squared() < 1e-10:
			across = longitudinal.cross(Vector3.RIGHT)
		across = across.normalized()
	var normal: Vector3 = longitudinal.cross(across).normalized()
	across = normal.cross(longitudinal).normalized()
	var palm_basis := Basis(across, longitudinal, normal)
	var palm_centre: Vector3 = wrist.lerp(knuckle, Profile.PALM_CENTRE_FRACTION)
	var palm_world := Transform3D(palm_basis, palm_centre)
	var palm_local: Transform3D = hand_ortho.affine_inverse() * palm_world

	return {
		"ok": true,
		"has_fingers": has_fingers,
		"estimated": estimated,
		"finger_roots": roots,
		"hand_bone": right_hand_bone,
		"wrist": wrist,
		"knuckle_centre": knuckle,
		"palm_centre": palm_centre,
		"longitudinal": longitudinal,
		"across": across,
		"normal": normal,
		"palm_basis": palm_basis,
		"palm_local": palm_local,
		"humanoid_height": height,
		"palm_centre_fraction": Profile.PALM_CENTRE_FRACTION,
		"estimated_hand_length_ratio": Profile.ESTIMATED_HAND_LENGTH_RATIO,
	}
