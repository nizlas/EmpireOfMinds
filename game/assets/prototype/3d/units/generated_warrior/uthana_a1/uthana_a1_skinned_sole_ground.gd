# Generic humanoid sole grounding: skinned foot/sole mesh vertices over an animation.
# Preview/diagnostic use — no warrior-specific constants, no animation mutation.
extends RefCounted

const FOOT_PROFILE_BONES: Array[String] = [
	"LeftFoot",
	"LeftToes",
	"RightFoot",
	"RightToes",
]
const FOOT_MIXAMO_BONES: Array[String] = [
	"mixamorig_LeftFoot",
	"mixamorig_LeftToeBase",
	"mixamorig_RightFoot",
	"mixamorig_RightToeBase",
]
## Vertex counts as foot/sole only if combined weight on foot bones meets this.
const FOOT_WEIGHT_MIN := 0.55
## And foot weight must beat any single non-foot influence by this margin.
const FOOT_DOMINANCE_EPS := 0.02


static func resolve_foot_bone_indices(skeleton: Skeleton3D) -> Dictionary:
	## Returns {bone_index: stable_label, ...} for Left/Right Foot/Toes.
	var out := {}
	var pairs := [
		["LeftFoot", "mixamorig_LeftFoot", "LeftFoot"],
		["LeftToes", "mixamorig_LeftToeBase", "LeftToes"],
		["RightFoot", "mixamorig_RightFoot", "RightFoot"],
		["RightToes", "mixamorig_RightToeBase", "RightToes"],
	]
	for p in pairs:
		var idx := skeleton.find_bone(p[0])
		if idx < 0:
			idx = skeleton.find_bone(p[1])
		if idx >= 0:
			out[idx] = p[2]
	return out


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


static func _bones_per_vertex(bones: PackedInt32Array, vert_count: int) -> int:
	if vert_count <= 0 or bones.is_empty():
		return 4
	var n: int = int(bones.size() / vert_count)
	if n == 8:
		return 8
	return 4


static func collect_foot_vertex_indices(
	mesh_instance: MeshInstance3D, skeleton: Skeleton3D
) -> Dictionary:
	## Build per-surface list of sole vertex indices via skin weights on foot bones.
	var foot_bones: Dictionary = resolve_foot_bone_indices(skeleton)
	if foot_bones.is_empty() or mesh_instance == null or mesh_instance.mesh == null:
		return {"ok": false, "reason": "missing_mesh_or_feet", "surfaces": []}
	var skin: Skin = mesh_instance.skin
	if skin == null:
		return {"ok": false, "reason": "no_skin", "surfaces": []}

	var bind_to_skel: PackedInt32Array = PackedInt32Array()
	bind_to_skel.resize(skin.get_bind_count())
	for bi in skin.get_bind_count():
		var bone_i: int = skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(skin.get_bind_name(bi)))
		bind_to_skel[bi] = bone_i

	var surfaces: Array = []
	var total_selected := 0
	for si in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_arr = arrays[Mesh.ARRAY_BONES]
		var weights_arr = arrays[Mesh.ARRAY_WEIGHTS]
		if bones_arr == null or weights_arr == null:
			continue
		var bones: PackedInt32Array = bones_arr as PackedInt32Array
		var weights: PackedFloat32Array = weights_arr as PackedFloat32Array
		if bones.is_empty() or weights.is_empty():
			continue
		var bpv: int = _bones_per_vertex(bones, verts.size())
		var selected: PackedInt32Array = PackedInt32Array()
		var dominant_labels: PackedStringArray = PackedStringArray()
		for vi in verts.size():
			var foot_w := 0.0
			var best_foot_w := 0.0
			var best_foot_label := ""
			var best_other_w := 0.0
			for j in bpv:
				var w: float = weights[vi * bpv + j]
				if w <= 0.0:
					continue
				var bind_i: int = int(bones[vi * bpv + j])
				if bind_i < 0 or bind_i >= bind_to_skel.size():
					continue
				var skel_bone: int = bind_to_skel[bind_i]
				if foot_bones.has(skel_bone):
					foot_w += w
					if w > best_foot_w:
						best_foot_w = w
						best_foot_label = str(foot_bones[skel_bone])
				else:
					best_other_w = maxf(best_other_w, w)
			if foot_w >= FOOT_WEIGHT_MIN and foot_w + FOOT_DOMINANCE_EPS >= best_other_w:
				selected.append(vi)
				dominant_labels.append(best_foot_label if not best_foot_label.is_empty() else "Foot")
				total_selected += 1
		surfaces.append(
			{
				"surface": si,
				"indices": selected,
				"labels": dominant_labels,
				"bpv": bpv,
				"bind_to_skel": bind_to_skel,
			}
		)
	return {
		"ok": total_selected > 0,
		"reason": "ok" if total_selected > 0 else "no_foot_vertices",
		"vertex_count": total_selected,
		"surfaces": surfaces,
		"foot_bones": foot_bones,
	}


static func skinned_vertex_world(
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
	# Mesh is typically parented under Skeleton3D; skeleton.to_global maps pose space → world.
	return skeleton.to_global(acc)


static func sample_bone_origin_min_y(
	skeleton: Skeleton3D, player: AnimationPlayer, clip_id: String, samples: int = 33
) -> Dictionary:
	var foot_bones: Dictionary = resolve_foot_bone_indices(skeleton)
	var lowest := INF
	var at_t := 0.0
	var label := ""
	var anim: Animation = player.get_animation(clip_id)
	player.play(clip_id)
	for si in samples:
		var t: float = (float(si) / float(maxi(samples - 1, 1))) * anim.length
		player.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		for bi in foot_bones.keys():
			var y: float = skeleton.to_global(skeleton.get_bone_global_pose(int(bi)).origin).y
			if y < lowest:
				lowest = y
				at_t = t
				label = str(foot_bones[bi])
	return {"lowest_y": lowest, "time": at_t, "label": label}


static func sample_skinned_sole_contact(
	root: Node,
	skeleton: Skeleton3D,
	player: AnimationPlayer,
	clip_id: String,
	samples: int = 33
) -> Dictionary:
	## Constant ModelRoot lift = -min skinned sole Y over Walking (world space).
	if skeleton == null or player == null or not player.has_animation(clip_id):
		return {"ok": false, "reason": "missing"}
	var mi: MeshInstance3D = find_skinned_mesh(root)
	if mi == null:
		return {"ok": false, "reason": "no_mesh"}
	var selection: Dictionary = collect_foot_vertex_indices(mi, skeleton)
	if not bool(selection.get("ok", false)):
		return {"ok": false, "reason": str(selection.get("reason", "select_failed")), "selection": selection}

	var bone_min: Dictionary = sample_bone_origin_min_y(skeleton, player, clip_id, samples)
	var anim: Animation = player.get_animation(clip_id)
	var hip_i: int = skeleton.find_bone("Hips")
	if hip_i < 0:
		hip_i = skeleton.find_bone("mixamorig_Hips")

	var lowest_sole := INF
	var highest_sole := -INF
	var sole_at_t := 0.0
	var sole_label := ""
	var sole_side := ""
	var hips_min := INF
	var hips_max := -INF
	var per_sample_min: Array = []

	player.play(clip_id)
	for si in samples:
		var t: float = (float(si) / float(maxi(samples - 1, 1))) * anim.length
		player.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		var frame_min := INF
		var frame_label := ""
		for surf in selection["surfaces"]:
			var indices: PackedInt32Array = surf["indices"]
			var labels: PackedStringArray = surf["labels"]
			var bpv: int = int(surf["bpv"])
			var bind_to_skel: PackedInt32Array = surf["bind_to_skel"]
			var surface_i: int = int(surf["surface"])
			for ii in indices.size():
				var world: Vector3 = skinned_vertex_world(
					mi, skeleton, surface_i, int(indices[ii]), bpv, bind_to_skel
				)
				if world.y < frame_min:
					frame_min = world.y
					frame_label = str(labels[ii])
				highest_sole = maxf(highest_sole, world.y)
		if frame_min < lowest_sole:
			lowest_sole = frame_min
			sole_at_t = t
			sole_label = frame_label
			sole_side = "Left" if frame_label.begins_with("Left") else "Right"
		per_sample_min.append(frame_min)
		if hip_i >= 0:
			var hy: float = skeleton.to_global(skeleton.get_bone_global_pose(hip_i).origin).y
			hips_min = minf(hips_min, hy)
			hips_max = maxf(hips_max, hy)

	var bone_lowest: float = float(bone_min.get("lowest_y", INF))
	var ground_offset_y: float = -lowest_sole
	return {
		"ok": true,
		"method": "skinned_foot_vertices",
		"ground_offset_y": ground_offset_y,
		"lowest_sole_y": lowest_sole,
		"highest_sole_y": highest_sole,
		"sole_span": highest_sole - lowest_sole,
		"lowest_sole_time": sole_at_t,
		"lowest_sole_label": sole_label,
		"lowest_sole_side": sole_side,
		"lowest_bone_y": bone_lowest,
		"lowest_bone_time": float(bone_min.get("time", 0.0)),
		"lowest_bone_label": str(bone_min.get("label", "")),
		"bone_minus_sole": bone_lowest - lowest_sole,
		"hips_span": hips_max - hips_min,
		"hips_min": hips_min,
		"hips_max": hips_max,
		"vertex_count": int(selection.get("vertex_count", 0)),
		"samples": samples,
		"per_sample_min_y": per_sample_min,
		"constant_placement": true,
		"selection": selection,
	}
