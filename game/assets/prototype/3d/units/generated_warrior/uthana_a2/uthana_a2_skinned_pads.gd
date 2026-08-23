# Skinned finger-pad centroids from distal bone skin weights (A2).
# Pads represent the volar contact side, not bone origins alone.
extends RefCounted

const SoleGround = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_skinned_sole_ground.gd"
)

const TIP_BONES: Dictionary = {
	"thumb": "mixamorig_RightHandThumb3",
	"index": "mixamorig_RightHandIndex3",
	"middle": "mixamorig_RightHandMiddle3",
	"ring": "mixamorig_RightHandRing3",
	"pinky": "mixamorig_RightHandPinky3",
}

const WEIGHT_MIN := 0.40


static func tip_bone_index(skeleton: Skeleton3D, finger: String) -> int:
	if skeleton == null or not TIP_BONES.has(finger):
		return -1
	return skeleton.find_bone(str(TIP_BONES[finger]))


## Bind once: pad position in each distal bone's local space (volar-biased).
static func bind_pad_locals(
	character: Node, skeleton: Skeleton3D, palm_normal_world: Vector3
) -> Dictionary:
	var out := {"ok": false, "pads": {}, "vertex_counts": {}}
	if character == null or skeleton == null:
		out["reason"] = "missing"
		return out
	var mi: MeshInstance3D = SoleGround.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		out["reason"] = "no_skinned_mesh"
		return out
	var skin: Skin = mi.skin
	var bind_to_skel: PackedInt32Array = PackedInt32Array()
	bind_to_skel.resize(skin.get_bind_count())
	for bi in skin.get_bind_count():
		var bone_i: int = skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(skin.get_bind_name(bi)))
		bind_to_skel[bi] = bone_i

	var tip_indices := {}
	for finger in TIP_BONES.keys():
		var ti: int = tip_bone_index(skeleton, str(finger))
		if ti < 0:
			out["reason"] = "missing_tip_%s" % finger
			return out
		tip_indices[finger] = ti

	skeleton.force_update_all_bone_transforms()
	var n_world: Vector3 = palm_normal_world.normalized()
	var sums_world := {}
	var weights_sum := {}
	for finger in tip_indices.keys():
		sums_world[finger] = Vector3.ZERO
		weights_sum[finger] = 0.0

	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_arr = arrays[Mesh.ARRAY_BONES]
		var weights_arr = arrays[Mesh.ARRAY_WEIGHTS]
		if bones_arr == null or weights_arr == null:
			continue
		var bones: PackedInt32Array = bones_arr as PackedInt32Array
		var weights: PackedFloat32Array = weights_arr as PackedFloat32Array
		var bpv: int = SoleGround._bones_per_vertex(bones, verts.size())
		for vi in verts.size():
			for finger in tip_indices.keys():
				var tip_i: int = int(tip_indices[finger])
				var w_tip := 0.0
				for j in bpv:
					var w: float = weights[vi * bpv + j]
					if w <= 0.0:
						continue
					var bind_i: int = int(bones[vi * bpv + j])
					if bind_i < 0 or bind_i >= bind_to_skel.size():
						continue
					if int(bind_to_skel[bind_i]) == tip_i:
						w_tip += w
				if w_tip < WEIGHT_MIN:
					continue
				var world_v: Vector3 = SoleGround.skinned_vertex_world(
					mi, skeleton, si, vi, bpv, bind_to_skel
				)
				var tip_world: Vector3 = skeleton.to_global(
					skeleton.get_bone_global_pose(tip_i).origin
				)
				# Prefer volar pad: vertices on the palm-flesh side of the tip bone.
				var side: float = (world_v - tip_world).dot(n_world)
				var volar_w: float = w_tip * (1.0 + clampf(side * 8.0, 0.0, 1.5))
				sums_world[finger] = sums_world[finger] + world_v * volar_w
				weights_sum[finger] = weights_sum[finger] + volar_w

	var pads_local := {}
	var counts := {}
	for finger in tip_indices.keys():
		var tip_i: int = int(tip_indices[finger])
		var pose: Transform3D = skeleton.get_bone_global_pose(tip_i)
		var world_pad: Vector3
		if float(weights_sum[finger]) > 1e-6:
			world_pad = sums_world[finger] / float(weights_sum[finger])
			counts[finger] = int(weights_sum[finger] * 10.0)
		else:
			# Fallback: slight volar offset from bone origin.
			world_pad = skeleton.to_global(pose.origin) + n_world * 0.004
			counts[finger] = 0
		var skel_pad: Vector3 = skeleton.global_transform.affine_inverse() * world_pad
		pads_local[finger] = pose.affine_inverse() * skel_pad

	out["ok"] = true
	out["pads"] = pads_local
	out["vertex_counts"] = counts
	out["mesh_path"] = str(mi.get_path())
	return out


static func pad_world(
	skeleton: Skeleton3D, finger: String, pad_local: Vector3
) -> Vector3:
	var tip_i: int = tip_bone_index(skeleton, finger)
	if tip_i < 0:
		return Vector3.ZERO
	var pose: Transform3D = skeleton.get_bone_global_pose(tip_i)
	return skeleton.to_global(pose * pad_local)
