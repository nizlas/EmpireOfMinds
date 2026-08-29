# Generic rest-pose static bake: an imported scene in, caller-independent
# static geometry out. No asset, family, unit or provider knowledge — every
# decision below is taken from the scene's own structure, so the same operation
# works for any imported model and no asset can be special-cased here.
#
# WHY THIS EXISTS. A provider that auto-rigs a humanoid needs an UNRIGGED mesh.
# Every local humanoid delivery is already skinned and animated, so the only way
# to obtain a static candidate without redesigning the mesh is to evaluate the
# existing skin at its own rest pose and keep the resulting surface. The
# evaluation must use the RENDERER's deformation semantics, not an approximation
# of them, which is why this runs inside Godot rather than in a Python glTF
# rewriter: the numbers below are the ones the engine would draw.
#
# THE SPACE THE OUTPUT LIVES IN. Vertices are returned in the space of the
# `base` node the caller nominates — normally an identity holder the asset was
# just instanced under. Everything between `base` and each vertex is baked
# exactly once:
#
#     out = base.global_transform⁻¹ · skeleton.global_transform
#             · bone_global_pose · bind_pose · v
#
# `base.global_transform⁻¹` is what makes the result independent of where the
# caller put the asset: place the holder at the origin, at a rotated ancestor,
# or under a non-unit scale and the baked numbers are identical. The asset's OWN
# internal root transform is inside the chain and therefore preserved — a
# delivery whose armature carries 0.01 stays at its authored size. This is not
# normalisation: nothing here rescales, re-centres or re-orients anything.
#
# WHAT IS DELIBERATELY NOT DONE. No decimation, no re-topology, no material
# rewriting, no axis conversion, no height normalisation, no re-centring. The
# bake is a deformation evaluation and a rig removal, nothing else.
extends RefCounted

const SCHEMA := "rest_pose_static_bake_v1"

## Positions blend affinely; a normal must be carried by the inverse transpose
## of the same blended basis or any non-uniform scale, shear or 90-degree rest
## permutation in the skin silently rotates it. Mirrors the equipment
## pipeline's `skinned_mesh_geometry.gd`, which established this contract.
const MIN_WEIGHT_SUM := 1e-8
const MIN_BASIS_DETERMINANT := 1e-20

# ----------------------------------------------------------------- inspection


## Structural facts about an instanced scene, before anything is modified.
## Output only: nothing here decides whether the bake may run.
static func inspect(root: Node) -> Dictionary:
	var skeletons: Array = root.find_children("*", "Skeleton3D", true, false)
	var players: Array = root.find_children("*", "AnimationPlayer", true, false)
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	var cameras: Array = root.find_children("*", "Camera3D", true, false)
	var lights: Array = root.find_children("*", "Light3D", true, false)
	var attachments: Array = root.find_children("*", "BoneAttachment3D", true, false)

	var skeleton_rows: Array = []
	for s in skeletons:
		var skel: Skeleton3D = s as Skeleton3D
		var bones: Array = []
		for bi in skel.get_bone_count():
			bones.append(
				{
					"index": bi,
					"name": skel.get_bone_name(bi),
					"parent": skel.get_bone_parent(bi),
					"rest": _transform_to_dict(skel.get_bone_rest(bi)),
				}
			)
		skeleton_rows.append(
			{
				"path": str(root.get_path_to(skel)),
				"bone_count": skel.get_bone_count(),
				"global_transform": _transform_to_dict(skel.global_transform),
				"bones": bones,
			}
		)

	var player_rows: Array = []
	for p in players:
		var ap: AnimationPlayer = p as AnimationPlayer
		player_rows.append(
			{
				"path": str(root.get_path_to(ap)),
				"animations": ap.get_animation_list(),
				"autoplay": ap.autoplay,
				"playing": ap.is_playing(),
				"active": ap.active,
			}
		)

	var mesh_rows: Array = []
	for m in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		mesh_rows.append(_describe_mesh_instance(root, mi))

	return {
		"schema": SCHEMA,
		"root_class": root.get_class(),
		"root_name": root.name,
		"root_transform": _transform_to_dict((root as Node3D).transform if root is Node3D else Transform3D()),
		"node_count": _count_nodes(root),
		"skeletons": skeleton_rows,
		"animation_players": player_rows,
		"mesh_instances": mesh_rows,
		"camera_count": cameras.size(),
		"light_count": lights.size(),
		"bone_attachment_count": attachments.size(),
	}


static func _describe_mesh_instance(root: Node, mi: MeshInstance3D) -> Dictionary:
	var surfaces: Array = []
	var triangles := 0
	var vertices := 0
	if mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var index_count: int = idx.size() if idx.size() > 0 else verts.size()
			var material: Material = mi.mesh.surface_get_material(s)
			var active: Material = mi.get_active_material(s)
			surfaces.append(
				{
					"surface": s,
					"primitive_type": mi.mesh.surface_get_primitive_type(s),
					"vertex_count": verts.size(),
					"index_count": index_count,
					"triangle_count": int(index_count / 3),
					"attributes": _attribute_names(arrays),
					"mesh_material_name": material.resource_name if material != null else "",
					"active_material_name": active.resource_name if active != null else "",
					"material_class": active.get_class() if active != null else "",
				}
			)
			triangles += int(index_count / 3)
			vertices += verts.size()
	return {
		"path": str(root.get_path_to(mi)),
		"name": mi.name,
		"visible": mi.visible,
		"visible_in_tree": mi.is_visible_in_tree(),
		"mesh_class": mi.mesh.get_class() if mi.mesh != null else "",
		"mesh_name": mi.mesh.resource_name if mi.mesh != null else "",
		"has_skin": mi.skin != null,
		"skin_bind_count": mi.skin.get_bind_count() if mi.skin != null else 0,
		"skeleton_path": str(mi.skeleton),
		"global_transform": _transform_to_dict(mi.global_transform),
		"surface_count": mi.mesh.get_surface_count() if mi.mesh != null else 0,
		"triangle_count": triangles,
		"vertex_count": vertices,
		"aabb": _aabb_to_dict(mi.get_aabb()),
		"surfaces": surfaces,
	}


static func _attribute_names(arrays: Array) -> Array:
	var named := {
		Mesh.ARRAY_VERTEX: "POSITION",
		Mesh.ARRAY_NORMAL: "NORMAL",
		Mesh.ARRAY_TANGENT: "TANGENT",
		Mesh.ARRAY_COLOR: "COLOR",
		Mesh.ARRAY_TEX_UV: "UV",
		Mesh.ARRAY_TEX_UV2: "UV2",
		Mesh.ARRAY_BONES: "BONES",
		Mesh.ARRAY_WEIGHTS: "WEIGHTS",
		Mesh.ARRAY_INDEX: "INDEX",
	}
	var out: Array = []
	for key in named.keys():
		var value = arrays[key]
		if value != null and _array_size(value) > 0:
			out.append(named[key])
	out.sort()
	return out


static func _array_size(value) -> int:
	match typeof(value):
		TYPE_PACKED_VECTOR3_ARRAY:
			return (value as PackedVector3Array).size()
		TYPE_PACKED_VECTOR2_ARRAY:
			return (value as PackedVector2Array).size()
		TYPE_PACKED_FLOAT32_ARRAY:
			return (value as PackedFloat32Array).size()
		TYPE_PACKED_INT32_ARRAY:
			return (value as PackedInt32Array).size()
		TYPE_PACKED_COLOR_ARRAY:
			return (value as PackedColorArray).size()
		_:
			return 0


# ----------------------------------------------------------------------- bake


## Evaluate every visible mesh at the skeleton's declared rest pose and return
## caller-independent static surfaces.
##
## `base` is the space the result is expressed in; `root` is the instanced
## asset. The scene is restored to the state it arrived in on EVERY return
## path, including classified failure, because the caller may keep using it —
## the comparison preview does exactly that.
static func bake(root: Node, base: Node3D) -> Dictionary:
	if root == null or base == null:
		return {"ok": false, "error_class": "BAKE_ARGS_MISSING", "detail": "root and base are required"}

	var saved_players: Array = _suspend_animation(root)
	var saved_poses: Array = _pin_rest_pose(root)
	var result: Dictionary = _bake_pinned(root, base)
	_restore_rest_pose(saved_poses)
	_resume_animation(saved_players)
	return result


## Hold a live scene at its declared rest pose, for DISPLAY rather than for a bake.
##
## The visual comparison needs one side to be the SOURCE as the engine deforms it,
## not a second bake — a comparison between two bakes could agree while both were
## wrong. Returns a token to hand back to `release_rest_pose`; the same suspend and
## pin the bake uses, so the two sides cannot drift apart.
static func hold_rest_pose(root: Node) -> Dictionary:
	if root == null:
		return {}
	return {"players": _suspend_animation(root), "poses": _pin_rest_pose(root)}


## Undo `hold_rest_pose`. Safe on an empty or already-released token.
static func release_rest_pose(token: Dictionary) -> void:
	if token.is_empty():
		return
	_restore_rest_pose(token.get("poses", []))
	_resume_animation(token.get("players", []))


## The bake itself, with the scene already pinned to rest. Split out so the
## restore above cannot be skipped by an early return in here.
static func _bake_pinned(root: Node, base: Node3D) -> Dictionary:
	var included: Array = []
	var excluded: Array = []

	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var reason: String = _exclusion_reason(mi)
		if not reason.is_empty():
			excluded.append({"path": str(root.get_path_to(mi)), "reason": reason})
			continue
		included.append(mi)

	if included.is_empty():
		return {
			"ok": false,
			"error_class": "BAKE_NO_VISIBLE_GEOMETRY",
			"detail": "the scene contains no visible MeshInstance3D with triangle surfaces",
			"excluded": excluded,
		}

	var surfaces: Array = []
	for mi in included:
		var skeleton: Skeleton3D = _skeleton_for(mi)
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				excluded.append(
					{
						"path": "%s#%d" % [str(root.get_path_to(mi)), s],
						"reason": "not_a_triangle_surface",
					}
				)
				continue
			var baked: Dictionary = _bake_surface(root, mi, skeleton, s, base)
			if not bool(baked.get("ok", false)):
				return baked
			surfaces.append(baked["surface"])

	if surfaces.is_empty():
		return {
			"ok": false,
			"error_class": "BAKE_NO_TRIANGLE_SURFACES",
			"detail": "no triangle surface survived selection",
			"excluded": excluded,
		}

	return {"ok": true, "schema": SCHEMA, "surfaces": surfaces, "excluded": excluded}


## Helper/rig/aux nodes are excluded by STRUCTURE, never by name: anything the
## renderer would not draw as character geometry is not character geometry.
static func _exclusion_reason(mi: MeshInstance3D) -> String:
	if mi.mesh == null:
		return "no_mesh"
	if mi.mesh.get_surface_count() <= 0:
		return "no_surfaces"
	if not mi.is_visible_in_tree():
		return "not_visible_in_tree"
	return ""


static func _skeleton_for(mi: MeshInstance3D) -> Skeleton3D:
	if mi.skin == null:
		return null
	var node: Node = mi.get_node_or_null(mi.skeleton)
	return node as Skeleton3D


static func _bake_surface(
	root: Node,
	mi: MeshInstance3D,
	skeleton: Skeleton3D,
	surface: int,
	base: Node3D
) -> Dictionary:
	var arrays: Array = mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return {
			"ok": false,
			"error_class": "BAKE_SURFACE_EMPTY",
			"detail": "%s surface %d has no vertices" % [str(root.get_path_to(mi)), surface],
		}
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()

	var skinned: bool = (
		skeleton != null
		and mi.skin != null
		and bones.size() > 0
		and weights.size() > 0
	)

	# The one transform that carries this surface from its authored space into
	# the caller-independent output space. For a skinned surface the per-vertex
	# skin is composed on the right; for a static one it is the whole story.
	#
	# Composed from the node chain BELOW `base` rather than as
	# `base.global_transform⁻¹ · node.global_transform`. The two are equal in
	# exact arithmetic, but the inverse form re-derives in float32 something the
	# scene graph already knows exactly, so a rotated or non-uniformly scaled
	# ancestor would perturb the last bits of every vertex and the output would
	# no longer be byte-stable across callers.
	var carrier: Transform3D = (
		relative_transform(base, skeleton) if skinned else relative_transform(base, mi)
	)

	var bind_to_skel := PackedInt32Array()
	var bpv := 0
	if skinned:
		bind_to_skel = _bind_to_skeleton_map(mi, skeleton)
		bpv = 8 if int(bones.size() / verts.size()) == 8 else 4

	var out_positions := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_tangents := PackedFloat32Array()
	out_positions.resize(verts.size())
	if normals.size() == verts.size():
		out_normals.resize(verts.size())
	if tangents.size() == verts.size() * 4:
		out_tangents.resize(verts.size() * 4)

	var reflected_vertices := 0
	for vi in verts.size():
		var local: Transform3D = Transform3D.IDENTITY
		if skinned:
			var blended: Dictionary = _blended_skin_transform(
				mi.skin, skeleton, bones, weights, bind_to_skel, bpv, vi
			)
			if not bool(blended.get("ok", false)):
				return {
					"ok": false,
					"error_class": "BAKE_DEGENERATE_SKIN",
					"detail": "vertex %d: %s" % [vi, str(blended.get("reason", ""))],
				}
			local = blended["transform"]
		var full: Transform3D = carrier * local
		out_positions[vi] = full * verts[vi]

		if out_normals.size() > 0 or out_tangents.size() > 0:
			var basis: Basis = full.basis
			var det: float = basis.determinant()
			if absf(det) <= MIN_BASIS_DETERMINANT:
				return {
					"ok": false,
					"error_class": "BAKE_DEGENERATE_BASIS",
					"detail": "vertex %d has a singular skinning basis" % vi,
				}
			if det < 0.0:
				reflected_vertices += 1
			if out_normals.size() > 0:
				var carried: Vector3 = (
					(basis.inverse().transposed() * normals[vi]) * signf(det)
				)
				out_normals[vi] = (
					carried.normalized() if carried.length_squared() > 1e-24 else normals[vi]
				)
			if out_tangents.size() > 0:
				# A tangent is a direction along the surface, so it rides the
				# basis directly; its handedness `w` flips only if the transform
				# reflects.
				var t := Vector3(
					tangents[vi * 4], tangents[vi * 4 + 1], tangents[vi * 4 + 2]
				)
				var carried_t: Vector3 = basis * t
				if carried_t.length_squared() > 1e-24:
					carried_t = carried_t.normalized()
				out_tangents[vi * 4] = carried_t.x
				out_tangents[vi * 4 + 1] = carried_t.y
				out_tangents[vi * 4 + 2] = carried_t.z
				out_tangents[vi * 4 + 3] = (
					tangents[vi * 4 + 3] if det > 0.0 else -tangents[vi * 4 + 3]
				)

	var material: Material = mi.get_active_material(surface)
	if material == null:
		material = mi.mesh.surface_get_material(surface)

	return {
		"ok": true,
		"surface": {
			"source_node_path": str(root.get_path_to(mi)),
			"source_mesh_name": mi.mesh.resource_name,
			"source_surface": surface,
			"was_skinned": skinned,
			"bones_per_vertex": bpv,
			"material_name": material.resource_name if material != null else "",
			"material_class": material.get_class() if material != null else "",
			"material": material,
			"reflected_vertices": reflected_vertices,
			"positions": out_positions,
			"normals": out_normals,
			"tangents": out_tangents,
			"uv": uv,
			"uv2": uv2,
			"colors": colors,
			"indices": indices,
		},
	}


## The transform of `target` expressed in `base`'s space, built from the local
## transforms between them. `base` itself contributes nothing, which is exactly
## why the result cannot depend on where `base` stands.
static func relative_transform(base: Node3D, target: Node3D) -> Transform3D:
	var chain: Array = []
	var node: Node = target
	while node != null and node != base:
		if node is Node3D:
			chain.append(node as Node3D)
		node = node.get_parent()
	if node != base:
		# Not a descendant: there is no honest relative transform to report.
		return Transform3D.IDENTITY
	var out := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		out = out * (chain[i] as Node3D).transform
	return out


static func _bind_to_skeleton_map(mi: MeshInstance3D, skeleton: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(mi.skin.get_bind_count())
	for bi in mi.skin.get_bind_count():
		var bone_i: int = mi.skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(mi.skin.get_bind_name(bi)))
		out[bi] = bone_i
	return out


## Linear blend skinning as one affine transform. Blending the MATRICES and
## then applying them is identical to blending the transformed positions, and
## it is the only form that can also carry a normal.
static func _blended_skin_transform(
	skin: Skin,
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	bind_to_skel: PackedInt32Array,
	bpv: int,
	vertex_index: int
) -> Dictionary:
	var acc_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var acc_origin := Vector3.ZERO
	var wsum := 0.0
	for j in bpv:
		var flat: int = vertex_index * bpv + j
		if flat >= weights.size() or flat >= bones.size():
			break
		var w: float = weights[flat]
		if w <= 0.0:
			continue
		var bind_i: int = int(bones[flat])
		if bind_i < 0 or bind_i >= skin.get_bind_count():
			continue
		var skel_bone: int = bind_to_skel[bind_i]
		if skel_bone < 0:
			continue
		var m: Transform3D = skeleton.get_bone_global_pose(skel_bone) * skin.get_bind_pose(bind_i)
		acc_basis = Basis(
			acc_basis.x + m.basis.x * w,
			acc_basis.y + m.basis.y * w,
			acc_basis.z + m.basis.z * w
		)
		acc_origin += m.origin * w
		wsum += w
	if wsum <= MIN_WEIGHT_SUM:
		# An unweighted vertex is not an error: it stays where the mesh put it.
		return {"ok": true, "transform": Transform3D.IDENTITY}
	var inv: float = 1.0 / wsum
	return {
		"ok": true,
		"transform": Transform3D(
			Basis(acc_basis.x * inv, acc_basis.y * inv, acc_basis.z * inv),
			acc_origin * inv
		),
	}


# ------------------------------------------------------- state save / restore


## Stop every animation before sampling. An animation left playing would put the
## skeleton somewhere between rest and a clip frame, and the bake would silently
## capture that frame instead of the rest pose.
static func _suspend_animation(root: Node) -> Array:
	var saved: Array = []
	for p in root.find_children("*", "AnimationPlayer", true, false):
		var ap: AnimationPlayer = p as AnimationPlayer
		var playing: bool = ap.is_playing()
		saved.append(
			{
				"player": ap,
				"active": ap.active,
				"animation": ap.current_animation,
				# Only meaningful while something is playing; asking otherwise is
				# an engine error, not a missing value.
				"position": ap.current_animation_position if playing else 0.0,
				"playing": playing,
				"speed": ap.speed_scale,
			}
		)
		ap.stop()
		ap.active = false
	return saved


static func _resume_animation(saved: Array) -> void:
	for entry in saved:
		var ap: AnimationPlayer = entry["player"]
		if ap == null or not is_instance_valid(ap):
			continue
		ap.active = bool(entry["active"])
		var animation: String = str(entry["animation"])
		if bool(entry["playing"]) and not animation.is_empty():
			ap.play(animation)
			ap.seek(float(entry["position"]), true)
		ap.speed_scale = float(entry["speed"])


## Pin every skeleton to its DECLARED rest pose, remembering the pose we found
## so the caller's scene survives the measurement unchanged.
static func _pin_rest_pose(root: Node) -> Array:
	var saved: Array = []
	for s in root.find_children("*", "Skeleton3D", true, false):
		var skel: Skeleton3D = s as Skeleton3D
		var poses: Array = []
		for bi in skel.get_bone_count():
			poses.append(
				{
					"position": skel.get_bone_pose_position(bi),
					"rotation": skel.get_bone_pose_rotation(bi),
					"scale": skel.get_bone_pose_scale(bi),
				}
			)
			skel.reset_bone_pose(bi)
		skel.force_update_all_bone_transforms()
		saved.append({"skeleton": skel, "poses": poses})
	return saved


static func _restore_rest_pose(saved: Array) -> void:
	for entry in saved:
		var skel: Skeleton3D = entry["skeleton"]
		if skel == null or not is_instance_valid(skel):
			continue
		var poses: Array = entry["poses"]
		for bi in mini(skel.get_bone_count(), poses.size()):
			var pose: Dictionary = poses[bi]
			skel.set_bone_pose_position(bi, pose["position"])
			skel.set_bone_pose_rotation(bi, pose["rotation"])
			skel.set_bone_pose_scale(bi, pose["scale"])
		skel.force_update_all_bone_transforms()


# ------------------------------------------------------------------ utilities


## Static ArrayMesh from baked surfaces, for in-engine comparison and preview.
## The same arrays that are serialised, so the preview cannot show something
## other than what was written.
static func to_array_mesh(surfaces: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for entry in surfaces:
		var surface: Dictionary = entry
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface["positions"]
		if (surface["normals"] as PackedVector3Array).size() > 0:
			arrays[Mesh.ARRAY_NORMAL] = surface["normals"]
		if (surface["tangents"] as PackedFloat32Array).size() > 0:
			arrays[Mesh.ARRAY_TANGENT] = surface["tangents"]
		if (surface["uv"] as PackedVector2Array).size() > 0:
			arrays[Mesh.ARRAY_TEX_UV] = surface["uv"]
		if (surface["uv2"] as PackedVector2Array).size() > 0:
			arrays[Mesh.ARRAY_TEX_UV2] = surface["uv2"]
		if (surface["colors"] as PackedColorArray).size() > 0:
			arrays[Mesh.ARRAY_COLOR] = surface["colors"]
		if (surface["indices"] as PackedInt32Array).size() > 0:
			arrays[Mesh.ARRAY_INDEX] = surface["indices"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var index: int = mesh.get_surface_count() - 1
		if surface.get("material") != null:
			mesh.surface_set_material(index, surface["material"])
	return mesh


static func measure(surfaces: Array) -> Dictionary:
	var triangles := 0
	var vertices := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var centroid := Vector3.ZERO
	var area := 0.0
	for entry in surfaces:
		var positions: PackedVector3Array = entry["positions"]
		var indices: PackedInt32Array = entry["indices"]
		vertices += positions.size()
		for v in positions:
			lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
			hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
			centroid += v
		var count: int = indices.size() if indices.size() > 0 else positions.size()
		triangles += int(count / 3)
		var t := 0
		while t + 2 < count:
			var a: Vector3 = positions[indices[t] if indices.size() > 0 else t]
			var b: Vector3 = positions[indices[t + 1] if indices.size() > 0 else t + 1]
			var c: Vector3 = positions[indices[t + 2] if indices.size() > 0 else t + 2]
			area += 0.5 * (b - a).cross(c - a).length()
			t += 3
	if vertices > 0:
		centroid /= float(vertices)
	return {
		"triangle_count": triangles,
		"vertex_count": vertices,
		"surface_count": surfaces.size(),
		"aabb_min": _vector_to_array(lo),
		"aabb_max": _vector_to_array(hi),
		"aabb_size": _vector_to_array(hi - lo),
		"height_y": hi.y - lo.y,
		"ground_min_y": lo.y,
		"centroid": _vector_to_array(centroid),
		"surface_area": area,
	}


static func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


static func _transform_to_dict(xf: Transform3D) -> Dictionary:
	return {
		"basis_x": _vector_to_array(xf.basis.x),
		"basis_y": _vector_to_array(xf.basis.y),
		"basis_z": _vector_to_array(xf.basis.z),
		"origin": _vector_to_array(xf.origin),
	}


static func _aabb_to_dict(box: AABB) -> Dictionary:
	return {
		"position": _vector_to_array(box.position),
		"size": _vector_to_array(box.size),
	}


static func _vector_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
