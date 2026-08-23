# A2 anatomical right-hand grip frame (audit Section 2).
# Right-handed basis: A (transverse, radial/index side +), L (wrist->knuckles),
# V = A x L (volar, out of the palm flesh). det(Basis(A, L, V)) = +1 by
# construction. The volar sign is never assumed: two independent checks
# (thumb-side + pose-consistent skinned-mesh centroid) must agree or the
# caller gets a classified STOP.
extends RefCounted

const PalmFrame = preload("res://presentation/world/one_handed_palm_frame.gd")
const SoleGround = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_skinned_sole_ground.gd"
)
const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const HAND_BONE := "RightHand"
const FINGER_ORDER: Array[String] = ["index", "middle", "ring", "pinky"]
const MCP_BONES: Dictionary = {
	"index": "mixamorig_RightHandIndex1",
	"middle": "mixamorig_RightHandMiddle1",
	"ring": "mixamorig_RightHandRing1",
	"pinky": "mixamorig_RightHandPinky1",
}
const MID_BONES: Dictionary = {
	"index": "mixamorig_RightHandIndex2",
	"middle": "mixamorig_RightHandMiddle2",
	"ring": "mixamorig_RightHandRing2",
	"pinky": "mixamorig_RightHandPinky2",
}
const DISTAL_BONES: Dictionary = {
	"index": "mixamorig_RightHandIndex3",
	"middle": "mixamorig_RightHandMiddle3",
	"ring": "mixamorig_RightHandRing3",
	"pinky": "mixamorig_RightHandPinky3",
}
const THUMB_BONES: Array[String] = [
	"mixamorig_RightHandThumb1",
	"mixamorig_RightHandThumb2",
	"mixamorig_RightHandThumb3",
]

## Distal segment beyond the last joint origin, as a fraction of the middle
## segment (no tip-end bone exists on this rig).
const DISTAL_TIP_FRACTION := 0.9
## Skinned volar probe: vertices within this fraction of hand_length of the
## palm centre participate in the flesh-centroid check.
const VOLAR_PROBE_RADIUS_FRAC := 0.5
const VOLAR_PROBE_MIN_VERTS := 24


static func _bone_xf(skeleton: Skeleton3D, idx: int, use_rest: bool) -> Transform3D:
	if use_rest:
		return PalmFrame.ortho_global_rest(skeleton, idx)
	return PalmFrame.ortho_global_pose(skeleton, idx)


## Build the frame from bone data alone (no volar verification here).
## use_rest = true reads global rest; false reads the live pose.
static func compute(skeleton: Skeleton3D, use_rest: bool) -> Dictionary:
	if skeleton == null:
		return {"ok": false, "error_class": "HAND_FRAME_NO_SKELETON"}
	var hand_i: int = skeleton.find_bone(HAND_BONE)
	if hand_i < 0:
		return {"ok": false, "error_class": "HAND_FRAME_HAND_BONE_MISSING"}

	var mcp := {}
	var hinge := {}
	var chain_length := {}
	for finger in FINGER_ORDER:
		var mcp_i: int = skeleton.find_bone(str(MCP_BONES[finger]))
		var mid_i: int = skeleton.find_bone(str(MID_BONES[finger]))
		var dst_i: int = skeleton.find_bone(str(DISTAL_BONES[finger]))
		if mcp_i < 0 or mid_i < 0 or dst_i < 0:
			return {
				"ok": false,
				"error_class": "HAND_FRAME_FINGER_CHAIN_MISSING",
				"finger": finger,
			}
		var mcp_xf: Transform3D = _bone_xf(skeleton, mcp_i, use_rest)
		var mid_p: Vector3 = _bone_xf(skeleton, mid_i, use_rest).origin
		var dst_p: Vector3 = _bone_xf(skeleton, dst_i, use_rest).origin
		mcp[finger] = mcp_xf.origin
		hinge[finger] = mcp_xf.basis.x.normalized()
		var seg1: float = mcp_xf.origin.distance_to(mid_p)
		var seg2: float = mid_p.distance_to(dst_p)
		chain_length[finger] = seg1 + seg2 + seg2 * DISTAL_TIP_FRACTION

	var thumb_pts: Array[Vector3] = []
	for tb in THUMB_BONES:
		var ti: int = skeleton.find_bone(tb)
		if ti < 0:
			return {"ok": false, "error_class": "HAND_FRAME_THUMB_CHAIN_MISSING"}
		thumb_pts.append(_bone_xf(skeleton, ti, use_rest).origin)
	# Thumb reference away from the wrist: mean of Thumb2/Thumb3 origins.
	var thumb_ref: Vector3 = (thumb_pts[1] + thumb_pts[2]) * 0.5

	var hand_xf: Transform3D = _bone_xf(skeleton, hand_i, use_rest)
	var wrist: Vector3 = hand_xf.origin
	var knuckle: Vector3 = Vector3.ZERO
	for finger in FINGER_ORDER:
		knuckle += mcp[finger] as Vector3
	knuckle /= float(FINGER_ORDER.size())

	var longitudinal: Vector3 = knuckle - wrist
	if longitudinal.length_squared() < 1e-12:
		return {"ok": false, "error_class": "HAND_FRAME_DEGENERATE_LONGITUDINAL"}
	longitudinal = longitudinal.normalized()

	# Right hand: radial (index) side positive => A = index - pinky.
	var across: Vector3 = (mcp["index"] as Vector3) - (mcp["pinky"] as Vector3)
	var knuckle_breadth: float = across.length()
	if knuckle_breadth < 1e-9:
		return {"ok": false, "error_class": "HAND_FRAME_DEGENERATE_BREADTH"}
	across = (across - longitudinal * across.dot(longitudinal))
	if across.length_squared() < 1e-12:
		return {"ok": false, "error_class": "HAND_FRAME_ACROSS_PARALLEL"}
	across = across.normalized()

	var volar: Vector3 = across.cross(longitudinal).normalized()
	var basis := Basis(across, longitudinal, volar)
	var det: float = basis.determinant()
	if det < 0.99:
		return {"ok": false, "error_class": "HAND_FRAME_NOT_RIGHT_HANDED", "det": det}

	var palm_centre: Vector3 = wrist.lerp(knuckle, Profile.PALM_CENTRE_FRACTION)
	return {
		"ok": true,
		"use_rest": use_rest,
		"hand_bone_index": hand_i,
		"hand_transform": hand_xf,
		"wrist": wrist,
		"knuckle_centre": knuckle,
		"palm_centre": palm_centre,
		"mcp": mcp,
		"hinge": hinge,
		"chain_length": chain_length,
		"thumb_ref": thumb_ref,
		"across": across,
		"longitudinal": longitudinal,
		"volar": volar,
		"basis": basis,
		"det": det,
		"hand_length": wrist.distance_to(knuckle),
		"knuckle_breadth": knuckle_breadth,
	}


## Dual independent volar verification (pose mode; LBS matches the live pose).
## Both checks must agree that +V is the flesh side, else classified STOP.
static func verify_volar(
	skeleton: Skeleton3D, character: Node, frame: Dictionary
) -> Dictionary:
	if not bool(frame.get("ok", false)):
		return {"ok": false, "error_class": "VOLAR_BAD_FRAME"}
	if bool(frame.get("use_rest", false)):
		return {"ok": false, "error_class": "VOLAR_REQUIRES_POSE_FRAME"}
	var palm_c: Vector3 = frame["palm_centre"]
	var volar: Vector3 = frame["volar"]

	# Check 1: the thumb column lies on the volar-radial side of the palm plane.
	var thumb_side: float = ((frame["thumb_ref"] as Vector3) - palm_c).dot(volar)
	var thumb_ok: bool = thumb_side > 0.0

	# Check 2: skinned palm-flesh extent asymmetry, same LBS transform as the
	# pose. The metacarpal bones sit dorsally in the hand, so the flesh
	# extends farther volar than dorsal of the bone palm plane. A plain
	# centroid sign is knife-edge (both skin sheets pull the mean to ~0 and
	# the sign flips with the animation pose); the quantile extent
	# difference is the pose-robust discriminator.
	var mesh_probe: Dictionary = _skinned_palm_flesh_probe(skeleton, character, frame)
	if not bool(mesh_probe.get("ok", false)):
		return {
			"ok": false,
			"error_class": mesh_probe.get("error_class", "VOLAR_MESH_PROBE_FAILED"),
			"thumb_side": thumb_side,
			"mesh_probe": mesh_probe,
		}
	var mesh_side: float = float(mesh_probe["extent_metric"])
	var mesh_ok: bool = mesh_side > 0.0

	if thumb_ok != mesh_ok:
		return {
			"ok": false,
			"error_class": "VOLAR_CHECKS_DISAGREE",
			"thumb_side": thumb_side,
			"mesh_side": mesh_side,
		}
	if not thumb_ok:
		return {
			"ok": false,
			"error_class": "VOLAR_SIGN_INVERTED",
			"thumb_side": thumb_side,
			"mesh_side": mesh_side,
		}
	return {
		"ok": true,
		"thumb_side": thumb_side,
		"mesh_side": mesh_side,
		"volar_extent": float(mesh_probe.get("volar_extent", 0.0)),
		"dorsal_extent": float(mesh_probe.get("dorsal_extent", 0.0)),
		"probe_vertex_count": int(mesh_probe.get("vertex_count", 0)),
		"probe_radius": float(mesh_probe.get("probe_radius", 0.0)),
	}


static func _skinned_palm_flesh_probe(
	skeleton: Skeleton3D, character: Node, frame: Dictionary
) -> Dictionary:
	var mi: MeshInstance3D = SoleGround.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		return {"ok": false, "error_class": "VOLAR_NO_SKINNED_MESH"}
	var skin: Skin = mi.skin
	var bind_to_skel := PackedInt32Array()
	bind_to_skel.resize(skin.get_bind_count())
	for bi in skin.get_bind_count():
		var bone_i: int = skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(skin.get_bind_name(bi)))
		bind_to_skel[bi] = bone_i

	var palm_c: Vector3 = frame["palm_centre"]
	var volar: Vector3 = frame["volar"]
	var probe_r: float = float(frame["hand_length"]) * VOLAR_PROBE_RADIUS_FRAC
	skeleton.force_update_all_bone_transforms()

	var sum := Vector3.ZERO
	var signed_dists := PackedFloat64Array()
	var count := 0
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_arr = arrays[Mesh.ARRAY_BONES]
		if bones_arr == null:
			continue
		var bones: PackedInt32Array = bones_arr as PackedInt32Array
		var bpv: int = SoleGround._bones_per_vertex(bones, verts.size())
		for vi in verts.size():
			var world_v: Vector3 = SoleGround.skinned_vertex_world(
				mi, skeleton, si, vi, bpv, bind_to_skel
			)
			if world_v.distance_to(palm_c) > probe_r:
				continue
			sum += world_v
			signed_dists.append((world_v - palm_c).dot(volar))
			count += 1
	if count < VOLAR_PROBE_MIN_VERTS:
		return {
			"ok": false,
			"error_class": "VOLAR_PROBE_UNDERSAMPLED",
			"vertex_count": count,
			"probe_radius": probe_r,
		}
	var centroid: Vector3 = sum / float(count)
	# Flesh-extent asymmetry along the volar candidate: the metacarpals lie
	# dorsally, so skin reaches farther on the volar side of the bone plane.
	# Robust quantiles (2%/98%) resist stray finger/forearm vertices caught
	# by the spherical probe.
	var sorted := signed_dists.duplicate()
	sorted.sort()
	var lo_i: int = clampi(int(floor(0.02 * float(count))), 0, count - 1)
	var hi_i: int = clampi(int(ceil(0.98 * float(count))) - 1, 0, count - 1)
	var dorsal_extent: float = maxf(-sorted[lo_i], 0.0)
	var volar_extent: float = maxf(sorted[hi_i], 0.0)
	return {
		"ok": true,
		"centroid": centroid,
		"along_volar": (centroid - palm_c).dot(volar),
		"volar_extent": volar_extent,
		"dorsal_extent": dorsal_extent,
		"extent_metric": volar_extent - dorsal_extent,
		"vertex_count": count,
		"probe_radius": probe_r,
	}
