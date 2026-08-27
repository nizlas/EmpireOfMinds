# Generic CPU-skinning / mesh-geometry utility for the equipment pipeline.
# Renderer-compatible bind-matrix skinning, skinned pad sampling and
# humanoid height measurement. No asset, family or preview knowledge:
# bone names always arrive as parameters (A2.9 ownership inversion).
extends RefCounted

## Vertex counts as a pad sample only if the tip-bone weight meets this.
const PAD_WEIGHT_MIN := 0.40


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var found: Array = root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


static func find_skinned_mesh(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi != null and mi.mesh != null and mi.skin != null:
			return mi
	if not meshes.is_empty():
		return meshes[0] as MeshInstance3D
	return null


static func bones_per_vertex(bones: PackedInt32Array, vert_count: int) -> int:
	if vert_count <= 0 or bones.is_empty():
		return 4
	var n: int = int(bones.size() / vert_count)
	if n == 8:
		return 8
	return 4


static func bind_to_skeleton_map(mi: MeshInstance3D, skeleton: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	if mi == null or mi.skin == null or skeleton == null:
		return out
	out.resize(mi.skin.get_bind_count())
	for bi in mi.skin.get_bind_count():
		var bone_i: int = mi.skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(mi.skin.get_bind_name(bi)))
		out[bi] = bone_i
	return out


## Skinned vertex in the SKELETON's own space, i.e. before any ancestor
## transform. Identical arithmetic to `skinned_vertex_world` minus the final
## `to_global`, so a caller that must be independent of how the character
## happens to be scaled or placed in a scene can work in this space and get
## bit-identical numbers in every context. Used by the fixture compiler for
## the geometry that ends up in a hashed artifact.
static func skinned_vertex_local(
	mesh_instance: MeshInstance3D,
	skeleton: Skeleton3D,
	surface: int,
	vertex_index: int,
	bpv: int,
	bind_to_skel: PackedInt32Array
) -> Vector3:
	return _skinned_vertex(
		mesh_instance, skeleton, surface, vertex_index, bpv, bind_to_skel
	)


static func skinned_vertex_world(
	mesh_instance: MeshInstance3D,
	skeleton: Skeleton3D,
	surface: int,
	vertex_index: int,
	bpv: int,
	bind_to_skel: PackedInt32Array
) -> Vector3:
	return skeleton.to_global(
		_skinned_vertex(mesh_instance, skeleton, surface, vertex_index, bpv, bind_to_skel)
	)


static func _skinned_vertex(
	mesh_instance: MeshInstance3D,
	skeleton: Skeleton3D,
	surface: int,
	vertex_index: int,
	bpv: int,
	bind_to_skel: PackedInt32Array
) -> Vector3:
	var skin: Skin = mesh_instance.skin
	var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var local_v: Vector3 = verts[vertex_index]
	var acc := Vector3.ZERO
	var wsum := 0.0
	for j in bpv:
		var w: float = weights[vertex_index * bpv + j]
		if w <= 0.0:
			continue
		var bind_i: int = int(bones[vertex_index * bpv + j])
		if bind_i < 0 or bind_i >= skin.get_bind_count():
			continue
		var skel_bone: int = bind_to_skel[bind_i]
		if skel_bone < 0:
			continue
		var bone_xf: Transform3D = skeleton.get_bone_global_pose(skel_bone)
		var bind_xf: Transform3D = skin.get_bind_pose(bind_i)
		acc += (bone_xf * bind_xf * local_v) * w
		wsum += w
	if wsum <= 1e-8:
		acc = local_v
	else:
		acc /= wsum
	return acc


## Ortho world transform matching equipment bone-follow (scale stripped).
static func ortho_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var g: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)
	return Transform3D(g.basis.orthonormalized(), g.origin)


static func ortho_global_pose(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var g: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	return Transform3D(g.basis.orthonormalized(), g.origin)


## Bind-pose humanoid height in the same world-metric space used for
## equipped props (ortho bone-follow): head − lowest toe via global rest.
## Bone-name candidates are FAMILY data and must be injected.
## The ONE canonical space humanoid height is measured in: the skeleton's own
## global space, i.e. rest-pose bone origins with `skeleton.global_transform`
## applied. Declared explicitly because the number feeds weapon normalisation
## and the socket is built in the same space — measuring in bone-local or
## ancestor-free skeleton space would silently rescale every grip by whatever
## the import left on the armature node (a raw Mixamo armature carries 0.01).
## Rest pose, not the current pose, so an animation frame cannot change it.
const HEIGHT_MEASURE_SPACE := "skeleton_global_rest"

## Measure the humanoid from RESOLVED SEMANTIC LANDMARKS.
##
## `landmarks` is the injected skeleton family's own resolution
## (`resolved_height_landmarks`): `{"roles": {role: [bone names]}}` plus the
## role keys to read. This utility never names a bone, a rig prefix or an
## import representation — it only measures between roles that someone else
## already resolved.
##
## Fail-closed and truthful, which is the whole point of the A2.12 repair:
##   * landmarks missing or unresolvable -> `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED`
##   * landmarks resolved but the geometry between them is degenerate (zero or
##     inverted extent) -> `DEGENERATE_HEIGHT`
## The second class may never again absorb the first.
static func measure_humanoid_height_from_landmarks(
	skeleton: Skeleton3D, landmarks: Dictionary
) -> Dictionary:
	if skeleton == null:
		return _height_unresolved("no skeleton", [])
	if not bool(landmarks.get("ok", false)):
		return _height_unresolved(
			str(landmarks.get("detail", "landmarks were not resolved")),
			landmarks.get("unresolved", [])
		)
	var roles: Dictionary = landmarks.get("roles", {})
	var head_role: String = str(landmarks.get("head_role", ""))
	var floor_role: String = str(landmarks.get("floor_role", ""))
	if head_role.is_empty() or floor_role.is_empty():
		return _height_unresolved("landmark roles were not declared", [])
	var head_bones: Array = roles.get(head_role, [])
	var floor_bones: Array = roles.get(floor_role, [])
	if head_bones.is_empty():
		return _height_unresolved("no bone resolved for '%s'" % head_role, [head_role])
	if floor_bones.is_empty():
		return _height_unresolved("no bone resolved for '%s'" % floor_role, [floor_role])
	var head_i: int = skeleton.find_bone(str(head_bones[0]))
	if head_i < 0:
		return _height_unresolved(
			"'%s' resolved to '%s', which is not on this skeleton"
				% [head_role, head_bones[0]],
			[head_role]
		)
	var head_y: float = _rest_y(skeleton, head_i)
	var floor_y := INF
	var used_floor: Array[String] = []
	for bn in floor_bones:
		var fi: int = skeleton.find_bone(str(bn))
		if fi < 0:
			continue
		used_floor.append(str(bn))
		floor_y = minf(floor_y, _rest_y(skeleton, fi))
	if used_floor.is_empty():
		return _height_unresolved(
			"no '%s' bone is on this skeleton" % floor_role, [floor_role]
		)
	var height: float = head_y - floor_y
	# Landmarks resolved, so a non-positive extent is a real geometric fact
	# about the rig (or a landmark role pointing at the wrong end of it).
	if height < MIN_HUMANOID_HEIGHT:
		return {
			"ok": false,
			"error_class": "DEGENERATE_HEIGHT",
			"space": HEIGHT_MEASURE_SPACE,
			"detail": "resolved landmarks span %.9f in %s" % [height, HEIGHT_MEASURE_SPACE],
			"height": maxf(0.0, height),
			"head_bone": str(head_bones[0]),
			"floor_bones": used_floor,
			"head_y": head_y,
			"floor_y": floor_y,
		}
	return {
		"ok": true,
		"height": height,
		"space": HEIGHT_MEASURE_SPACE,
		"head_bone": str(head_bones[0]),
		"floor_bones": used_floor,
		"head_y": head_y,
		"floor_y": floor_y,
	}


## Below this the rig has no usable vertical extent between its landmarks.
const MIN_HUMANOID_HEIGHT := 1e-6


static func _rest_y(skeleton: Skeleton3D, bone_i: int) -> float:
	return (skeleton.global_transform * skeleton.get_bone_global_rest(bone_i)).origin.y


static func _height_unresolved(detail: String, unresolved) -> Dictionary:
	return {
		"ok": false,
		"error_class": "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
		"space": HEIGHT_MEASURE_SPACE,
		"detail": detail,
		"unresolved": unresolved,
		"height": 0.0,
	}


static func tip_bone_index(
	skeleton: Skeleton3D, finger: String, tip_bones: Dictionary
) -> int:
	if skeleton == null or tip_bones.is_empty() or not tip_bones.has(finger):
		return -1
	return skeleton.find_bone(str(tip_bones[finger]))


## Bind once: pad position in each distal bone's local space (volar-biased).
## `tip_bones` is REQUIRED per-family/per-side data — never a built-in name.
static func bind_pad_locals(
	character: Node, skeleton: Skeleton3D, palm_normal_world: Vector3,
	tip_bones: Dictionary
) -> Dictionary:
	var out := {"ok": false, "pads": {}, "vertex_counts": {}}
	if character == null or skeleton == null:
		out["reason"] = "missing"
		return out
	if tip_bones.is_empty():
		out["reason"] = "tip_bones_required"
		return out
	var mi: MeshInstance3D = find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		out["reason"] = "no_skinned_mesh"
		return out
	var bind_to_skel: PackedInt32Array = bind_to_skeleton_map(mi, skeleton)

	var tip_indices := {}
	for finger in tip_bones.keys():
		var ti: int = tip_bone_index(skeleton, str(finger), tip_bones)
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
		var bpv: int = bones_per_vertex(bones, verts.size())
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
				if w_tip < PAD_WEIGHT_MIN:
					continue
				var world_v: Vector3 = skinned_vertex_world(
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
	skeleton: Skeleton3D, finger: String, pad_local: Vector3, tip_bones: Dictionary
) -> Vector3:
	var tip_i: int = tip_bone_index(skeleton, finger, tip_bones)
	if tip_i < 0:
		return Vector3.ZERO
	var pose: Transform3D = skeleton.get_bone_global_pose(tip_i)
	return skeleton.to_global(pose * pad_local)
