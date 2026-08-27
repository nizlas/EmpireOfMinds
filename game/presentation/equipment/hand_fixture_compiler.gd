# Generic, deterministic hand-fixture compiler (A2.10).
#
# Derives the per-unit thumb surface evidence the grip engine needs -- nail
# plate, volar pad, rest normals, winding, pad marker, bone-weight evidence
# -- directly from a rigged skinned mesh plus an INJECTED skeleton-family
# profile. No human picks triangles, surfaces, bones or sides.
#
# Explicitly NOT used as classification evidence: albedo, brightness,
# saturation or any texture sample. UV data is recorded as a stable
# identity/back-reference for the engine's bind sanity, never as the reason
# a patch is a nail or a pad. The classification is carried by skin-weight
# dominance, surface topology (connected components) and the hand's own
# anatomical dorsal/volar/radial directions.
#
# Anatomical rule (validated against the accepted A2.7 reference):
#   * the thumb tip is the T3/T2-weighted surface component that carries
#     BOTH an opposed dorsal-radial nail face and a volar pad face;
#   * nail  = normals along normalize(radial - volar), the dorsal-radial
#     bisector -- the nail faces off the back of the thumb and outward on
#     that hand's own index side;
#   * pad   = normals along volar -- the pad faces the palm/handle.
# Both directions come from the hand's own chirality, so the left hand is
# derived from the left hand. Nothing is mirrored or copied between sides.
#
# This compiler produces SURFACE evidence only. Canonical pose calibration
# (thumb anatomical angles, authored finger flexion) is interaction-policy
# data, is shared per profile rather than per unit, and is injected --
# deriving it from geometry is not in scope and must not be faked here.
#
# Canonical compilation context (A2.11). Fixture identity must not depend on
# where the character happens to sit in a scene, how it is scaled or which
# animation frame is current, so the compiler pins both:
#   * SPACE  — every point, direction and marker that enters the artifact is
#     derived in the SKELETON's own space, excluding all ancestor transforms;
#   * POSE   — the whole skeleton is reset to its rest pose for the duration
#     of the compile and restored afterwards.
# Those two are the root cause of the earlier context-dependent hash: the same
# rig evaluated under a 0.30 preview scale and under an unscaled headless load
# produced normals and markers that differed in the last float digits.
extends RefCounted

const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const DefaultSkinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const ArtifactResource = preload("res://presentation/equipment/hand_fixture_artifact.gd")
const DefaultCalibration = preload(
	"res://presentation/equipment/hand_fixture_compiler_calibration.gd"
)

const COMPILER_VERSION := "hand_fixture_compiler_v3"
## A2.12: the compiler's own output is named for what it is — compiled
## EVIDENCE, i.e. staging data. It is deliberately NOT the schema the runtime
## loader accepts; see `CERTIFICATION_SCHEMA`.
const ARTIFACT_SCHEMA := "hand_fixture_evidence_v3"
const SUPPORTED_SCHEMAS: Array[String] = [ARTIFACT_SCHEMA]
## What a compiler PASS means. Surface evidence for this mesh — NOT an
## accepted asset: bind sanity and the grip ground-truth gate are separate
## acceptance levels owned by the ingestion chain.
const ACCEPTANCE_SCOPE := "compiler_surface_evidence_only"

## A vertex counts as belonging to a thumb segment only when that segment
## is its DOMINANT bone and the dominant weight reaches this.
const MIN_BONE_DOMINANCE := 0.40
## A triangle joins the thumb-tip soup when all three vertices are dominant
## on the distal or middle thumb segment, at least this many on the distal.
const MIN_DISTAL_VERTS := 2
## Classification thresholds, dimensionless dot products.
const PAD_VOLAR_MIN := 0.45
const NAIL_BISECTOR_MIN := 0.35
## The two plates must not face the same way.
const NAIL_PAD_MAX_DOT := 0.50
## Degenerate triangles are ignored, never classified.
const MIN_TRIANGLE_AREA := 1e-14
## The patch-selection margin is CALIBRATING data measured on one rig, so it
## lives in `hand_fixture_compiler_calibration.gd` and is injectable. It is
## deliberately NOT a constant of this generic compiler.
## Two candidate components whose areas are within this ratio make the
## thumb-tip choice non-deterministic.
const COMPONENT_AREA_TIE_RATIO := 0.02
const MIN_STRUCTURE_CONFIDENCE := 0.35


## Compile one or both hands. `family` is the injected skeleton-family
## profile; every bone name is taken from the family's bone map, resolved
## against the live skeleton by the family itself. `calibration` is the
## versioned CALIBRATING threshold owner.
## Returns an artifact dictionary (see `_artifact`), never a GDScript file.
static func compile(
	character: Node,
	skeleton: Skeleton3D,
	family,
	sides: Array = ["right", "left"],
	skinning = null,
	calibration = null
) -> Dictionary:
	var skin = skinning if skinning != null else DefaultSkinning
	var calib = calibration if calibration != null else DefaultCalibration
	if family == null or not family.has_method("bone_map"):
		return _failed_artifact("FIXTURE_FAMILY_MISMATCH", "family profile required")
	if not _has_const(family, "FAMILY_VERSION"):
		return _failed_artifact(
			"FIXTURE_FAMILY_MISMATCH", "family declares no FAMILY_VERSION"
		)
	if skeleton == null:
		return _failed_artifact("HAND_SKELETON_INCOMPLETE", "no skeleton")
	var mi: MeshInstance3D = skin.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		return _failed_artifact("THUMB_SURFACE_CANDIDATES_MISSING", "no skinned mesh")
	# Canonical compile pose: whole-skeleton rest, restored afterwards. The
	# incoming animation frame must not be able to change fixture identity.
	var saved_pose: Array = _pin_rest_pose(skeleton)
	var per_side := {}
	var all_ok := true
	var bone_maps := {}
	for side_v in sides:
		var side: String = "left" if str(side_v) == "left" else "right"
		var bones: Dictionary = HandProfile.family_bone_map(family, skeleton, side)
		bone_maps[side] = bones
		var r: Dictionary = _compile_side(
			character, skeleton, mi, family, side, skin, bones, calib
		)
		per_side[side] = r
		if not bool(r.get("compiled", false)):
			all_ok = false
	_restore_pose(skeleton, saved_pose)
	return _artifact(mi, skeleton, family, per_side, all_ok, bone_maps, calib)


## Save every bone pose and reset the skeleton to rest.
static func _pin_rest_pose(skeleton: Skeleton3D) -> Array:
	var saved: Array = []
	for bi in skeleton.get_bone_count():
		saved.append([
			bi,
			skeleton.get_bone_pose_position(bi),
			skeleton.get_bone_pose_rotation(bi),
			skeleton.get_bone_pose_scale(bi),
		])
		skeleton.reset_bone_pose(bi)
	skeleton.force_update_all_bone_transforms()
	return saved


static func _restore_pose(skeleton: Skeleton3D, saved: Array) -> void:
	for rec in saved:
		var bi: int = int(rec[0])
		skeleton.set_bone_pose_position(bi, rec[1])
		skeleton.set_bone_pose_rotation(bi, rec[2])
		skeleton.set_bone_pose_scale(bi, rec[3])
	skeleton.force_update_all_bone_transforms()


static func _compile_side(
	character: Node,
	skeleton: Skeleton3D,
	mi: MeshInstance3D,
	family,
	side: String,
	skin,
	bones: Dictionary,
	calib
) -> Dictionary:
	# 1. complete finger and thumb chains
	var chain_check: Dictionary = _verify_chains(skeleton, bones)
	if not bool(chain_check.get("ok", false)):
		return _fail(side, str(chain_check["error_class"]), chain_check.get("detail", ""))
	var thumb: Array = bones["thumb"]
	var t2: int = skeleton.find_bone(str(thumb[1]))
	var t3: int = skeleton.find_bone(str(thumb[2]))
	# The mapped thumb must belong to THIS hand. A bone map that points at
	# the other limb's thumb still resolves every name, so without a spatial
	# coherence check the compiler would happily classify the other hand's
	# tip using this hand's anatomical directions.
	var span: Dictionary = _verify_thumb_belongs_to_hand(skeleton, bones, t3)
	if not bool(span.get("ok", false)):
		return _fail(side, "HAND_SKELETON_INCOMPLETE", str(span.get("detail", "")))
	# 2/3. chirality and a det +1 anatomical hand basis, derived from THIS
	# hand's own bones (radial = its own index minus pinky). The world frame
	# feeds the volar mesh dual-check (it samples world vertices); the
	# skeleton-space frame feeds everything that enters the artifact.
	var frame_world: Dictionary = HandProfile.derive_frame(
		skeleton, family, bones, side, false, HandProfile.SPACE_WORLD
	)
	var frame: Dictionary = HandProfile.derive_frame(
		skeleton, family, bones, side, false, HandProfile.SPACE_SKELETON
	)
	for f in [frame_world, frame]:
		if not bool(f.get("ok", false)):
			var ec := str(f.get("error_class", "HAND_FRAME_UNDERIVABLE"))
			if ec == "HAND_FRAME_NOT_RIGHT_HANDED":
				return _fail(side, "HAND_CHIRALITY_AMBIGUOUS", ec)
			return _fail(side, "HAND_FRAME_UNDERIVABLE", ec)
		if float(f.get("det", 0.0)) < 0.99:
			return _fail(side, "HAND_CHIRALITY_AMBIGUOUS", "det %.4f" % f.get("det", 0.0))
	# 4. volar side must agree between the thumb column and the skinned flesh
	var volar_check: Dictionary = _verify_volar(skeleton, character, frame_world, skin)
	if not bool(volar_check.get("ok", false)):
		return _fail(side, "HAND_VOLAR_AMBIGUOUS", str(volar_check.get("detail", "")))
	# The skeleton is already pinned to rest by `compile`, so the compiled
	# evidence is rest-anchored for the whole hand, not only the thumb chain.
	return _compile_thumb_surface(skeleton, mi, frame, t2, t3, side, skin, calib)


static func _compile_thumb_surface(
	skeleton: Skeleton3D,
	mi: MeshInstance3D,
	frame: Dictionary,
	t2: int,
	t3: int,
	side: String,
	skin,
	calib
) -> Dictionary:
	# Skeleton space throughout: no ancestor transform may reach the artifact.
	var t3_world: Transform3D = skeleton.get_bone_global_pose(t3)
	var t3_inv_basis: Basis = skeleton.get_bone_global_pose(t3).basis.inverse()
	var t2_world: Transform3D = skeleton.get_bone_global_pose(t2)
	# Anatomical directions expressed in the distal thumb's own local space.
	var volar_t3: Vector3 = (t3_inv_basis * (frame["volar"] as Vector3)).normalized()
	var radial_t3: Vector3 = (t3_inv_basis * (frame["radial"] as Vector3)).normalized()
	var nail_dir_t3: Vector3 = (radial_t3 - volar_t3).normalized()
	var thumb_axis_t3: Vector3 = (
		t3_inv_basis * (t3_world.origin - t2_world.origin)
	).normalized()
	var bind_map: PackedInt32Array = skin.bind_to_skeleton_map(mi, skeleton)
	# 5. gather candidate triangles by skin-weight dominance
	var soup: Dictionary = _gather_thumb_triangles(
		mi, skeleton, bind_map, t2, t3, t3_world, t3_inv_basis, skin
	)
	if soup.has("error_class"):
		return _fail(side, str(soup["error_class"]), str(soup.get("detail", "")))
	var tris: Array = soup["tris"]
	if tris.is_empty():
		return _fail(side, "THUMB_SURFACE_CANDIDATES_MISSING", "no thumb-tip triangles")
	for tri in tris:
		var n: Vector3 = tri["n_local"]
		tri["d_volar"] = n.dot(volar_t3)
		tri["d_nail"] = n.dot(nail_dir_t3)
		tri["d_radial"] = n.dot(radial_t3)
		tri["d_axis"] = n.dot(thumb_axis_t3)
	# 6/7. topological components; the thumb tip is the component that
	# carries BOTH an opposed nail face and a volar pad face.
	var components: Array = _connected_components(tris)
	var qualified: Array = []
	for comp in components:
		var has_nail := false
		var has_pad := false
		var area := 0.0
		for tri in comp:
			area += float(tri["area"])
			if float(tri["d_nail"]) >= NAIL_BISECTOR_MIN and float(tri["d_volar"]) < 0.0:
				has_nail = true
			if float(tri["d_volar"]) >= PAD_VOLAR_MIN:
				has_pad = true
		if has_nail and has_pad:
			qualified.append({"tris": comp, "area": area})
	if qualified.is_empty():
		var why := "no component carries both an opposed nail and a volar pad"
		return _fail(side, "THUMB_SURFACE_CANDIDATES_MISSING", why)
	qualified.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	if qualified.size() >= 2:
		var a0: float = float(qualified[0]["area"])
		var a1: float = float(qualified[1]["area"])
		if a0 > 0.0 and absf(a0 - a1) / a0 < COMPONENT_AREA_TIE_RATIO:
			return _fail(
				side,
				"THUMB_SURFACE_CANDIDATES_MISSING",
				"thumb-tip component ambiguous (areas %.9f vs %.9f)" % [a0, a1]
			)
	var tip: Array = qualified[0]["tris"]
	var component_confidence: float = 1.0
	if qualified.size() >= 2:
		component_confidence = clampf(
			1.0 - float(qualified[1]["area"]) / maxf(float(qualified[0]["area"]), 1e-12),
			0.0, 1.0
		)
	# 7. split the tip cap into the two opposed plates
	var nail_sel: Dictionary = _select_patch(tip, "d_nail", NAIL_BISECTOR_MIN, true, calib)
	if not bool(nail_sel.get("ok", false)):
		return _fail(side, "NAIL_PATCH_AMBIGUOUS", str(nail_sel.get("detail", "")))
	var pad_sel: Dictionary = _select_patch(tip, "d_volar", PAD_VOLAR_MIN, false, calib)
	if not bool(pad_sel.get("ok", false)):
		return _fail(side, "PAD_PATCH_AMBIGUOUS", str(pad_sel.get("detail", "")))
	var nail_tris: Array = nail_sel["tris"]
	var pad_tris: Array = pad_sel["tris"]
	# A triangle may never be claimed by both plates.
	var pad_keys := {}
	for tri in pad_tris:
		pad_keys[str(tri["key"])] = true
	for tri in nail_tris:
		if pad_keys.has(str(tri["key"])):
			return _fail(side, "NAIL_PAD_NOT_OPPOSED", "triangle in both plates")
	var nail_n: Vector3 = _aggregate_normal(nail_tris)
	var pad_n: Vector3 = _aggregate_normal(pad_tris)
	if nail_n.length_squared() < 1e-16 or pad_n.length_squared() < 1e-16:
		return _fail(side, "PATCH_WINDING_UNDERIVABLE", "degenerate aggregate normal")
	nail_n = nail_n.normalized()
	pad_n = pad_n.normalized()
	var rest_dot: float = nail_n.dot(pad_n)
	if rest_dot > NAIL_PAD_MAX_DOT:
		return _fail(
			side, "NAIL_PAD_NOT_OPPOSED", "nail.pad %.5f exceeds %.2f" % [rest_dot, NAIL_PAD_MAX_DOT]
		)
	# The nail must not be the surface that would contact a handle.
	if pad_n.dot(volar_t3) <= nail_n.dot(volar_t3):
		return _fail(side, "NAIL_PAD_NOT_OPPOSED", "nail is more volar than the pad")
	var confidence := {
		"component": component_confidence,
		"nail": float(nail_sel["confidence"]),
		"pad": float(pad_sel["confidence"]),
		# Distance from the opposition gate. Plates that face away from each
		# other at all (dot <= 0) are fully opposed for grip purposes; a
		# thumb nail and pad are close to perpendicular, not antiparallel.
		"opposition": clampf((NAIL_PAD_MAX_DOT - rest_dot) / NAIL_PAD_MAX_DOT, 0.0, 1.0),
		"bone_weight": float(soup["min_dominance"]),
	}
	var overall: float = 1.0
	for k in confidence.keys():
		overall = minf(overall, float(confidence[k]))
	confidence["overall"] = overall
	if overall < MIN_STRUCTURE_CONFIDENCE:
		return _fail(
			side,
			"FIXTURE_CONFIDENCE_TOO_LOW",
			"overall %.4f below %.2f: %s" % [overall, MIN_STRUCTURE_CONFIDENCE, str(confidence)]
		)
	return {
		"compiled": true,
		"side": side,
		"source": "%s_%s" % [COMPILER_VERSION, side],
		"nail_tris": _serialize_patch(nail_tris),
		"pad_tris": _serialize_patch(pad_tris),
		"nail_normal_local": nail_n,
		"pad_normal_local": pad_n,
		"rest_nail_pad_dot": rest_dot,
		"pad_marker_local": _aggregate_centroid(pad_tris),
		"nail_marker_local": _aggregate_centroid(nail_tris),
		"confidence": confidence,
		"evidence": {
			"thumb_tip_triangles": tip.size(),
			"candidate_triangles": tris.size(),
			"components": components.size(),
			"qualified_components": qualified.size(),
			"nail_margin": float(nail_sel["margin"]),
			"pad_margin": float(pad_sel["margin"]),
			"nail_best_rejected": float(nail_sel["best_rejected"]),
			"pad_best_rejected": float(pad_sel["best_rejected"]),
			"volar_t3": volar_t3,
			"radial_t3": radial_t3,
			"nail_dir_t3": nail_dir_t3,
			"thumb_axis_t3": thumb_axis_t3,
			"min_bone_dominance": float(soup["min_dominance"]),
			"winding_flips": soup["flip_histogram"],
			"classification_signals": ["skin_weight_dominance", "topology", "anatomical_direction"],
			"texture_signals_used": [],
		},
	}


## Triangles whose vertices are dominated by the distal/middle thumb bones.
## Rest normals are anchored here: the authored cross product is compared
## against the imported shading normals ONCE, at rest, and the resulting
## flip is stored. Deformed triangles are never auto-flipped later.
static func _gather_thumb_triangles(
	mi: MeshInstance3D,
	skeleton: Skeleton3D,
	bind_map: PackedInt32Array,
	t2: int,
	t3: int,
	t3_world: Transform3D,
	t3_inv_basis: Basis,
	skin
) -> Dictionary:
	var out: Array = []
	var min_dom := 1.0
	var flips := {"authored": 0, "flipped": 0}
	var t3_world_inv: Transform3D = t3_world.affine_inverse()
	var missing_streams := {}
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var bone_arr = arrays[Mesh.ARRAY_BONES]
		var wt = arrays[Mesh.ARRAY_WEIGHTS]
		var idx = arrays[Mesh.ARRAY_INDEX]
		# Each missing stream is reported as itself. A surface without UVs is
		# not a bone-weight problem and must not be misreported as one.
		for pair in [
			["normal", norms], ["uv", uvs], ["bones", bone_arr],
			["weights", wt], ["index", idx]
		]:
			if pair[1] == null:
				missing_streams[str(pair[0])] = int(missing_streams.get(str(pair[0]), 0)) + 1
		if norms == null or uvs == null or bone_arr == null or wt == null or idx == null:
			continue
		var bones_i: PackedInt32Array = bone_arr as PackedInt32Array
		var weights: PackedFloat32Array = wt as PackedFloat32Array
		var normals: PackedVector3Array = norms as PackedVector3Array
		var uv0: PackedVector2Array = uvs as PackedVector2Array
		var indices: PackedInt32Array = idx as PackedInt32Array
		var bpv: int = skin.bones_per_vertex(bones_i, verts.size())
		# Dominant bone per vertex (weights are never re-normalised here).
		var dom_bone := PackedInt32Array()
		var dom_w := PackedFloat32Array()
		dom_bone.resize(verts.size())
		dom_w.resize(verts.size())
		for vi in verts.size():
			var bw := 0.0
			var bb := -1
			for k in bpv:
				var w: float = weights[vi * bpv + k]
				if w > bw:
					bw = w
					var bind_i: int = bones_i[vi * bpv + k]
					bb = bind_map[bind_i] if bind_i < bind_map.size() else -1
			dom_bone[vi] = bb
			dom_w[vi] = bw
		var tri_count: int = int(indices.size() / 3)
		for t in tri_count:
			var a: int = indices[t * 3]
			var b: int = indices[t * 3 + 1]
			var c: int = indices[t * 3 + 2]
			var n_distal := 0
			var ok := true
			var weakest := 1.0
			for vi2 in [a, b, c]:
				var bb2: int = dom_bone[vi2]
				if bb2 == t3:
					n_distal += 1
				elif bb2 != t2:
					ok = false
					break
				weakest = minf(weakest, float(dom_w[vi2]))
			if not ok or n_distal < MIN_DISTAL_VERTS:
				continue
			if weakest < MIN_BONE_DOMINANCE:
				continue
			min_dom = minf(min_dom, weakest)
			var p0: Vector3 = skin.skinned_vertex_local(mi, skeleton, si, a, bpv, bind_map)
			var p1: Vector3 = skin.skinned_vertex_local(mi, skeleton, si, b, bpv, bind_map)
			var p2: Vector3 = skin.skinned_vertex_local(mi, skeleton, si, c, bpv, bind_map)
			var cross: Vector3 = (p1 - p0).cross(p2 - p0)
			var area: float = cross.length() * 0.5
			if area <= MIN_TRIANGLE_AREA:
				continue
			# Imported shading normal, skinned exactly as the engine does.
			var shade := Vector3.ZERO
			for vi3 in [a, b, c]:
				var bb3: int = dom_bone[vi3]
				shade += (
					skeleton.get_bone_global_pose(bb3).basis
					* skeleton.get_bone_global_rest(bb3).basis.inverse()
				) * normals[vi3]
			if shade.length_squared() < 1e-16:
				continue
			shade = shade.normalized()
			var authored: Vector3 = cross.normalized()
			var flip: float = 1.0 if authored.dot(shade) >= 0.0 else -1.0
			if flip > 0.0:
				flips["authored"] = int(flips["authored"]) + 1
			else:
				flips["flipped"] = int(flips["flipped"]) + 1
			out.append({
				"si": si,
				"i": [a, b, c],
				"key": _tri_key([a, b, c]),
				"area": area,
				"flip": flip,
				"uvc": (uv0[a] + uv0[b] + uv0[c]) / 3.0,
				"n_local": (t3_inv_basis * (authored * flip)).normalized(),
				"centroid_local": t3_world_inv * ((p0 + p1 + p2) / 3.0),
			})
	if out.is_empty():
		if not missing_streams.is_empty():
			return {
				"error_class": "MESH_STREAMS_INCOMPLETE",
				"detail": "surfaces missing required streams: %s" % str(missing_streams),
			}
		return {
			"error_class": "PATCH_BONE_WEIGHT_INSUFFICIENT",
			"detail": "no triangle reached dominance %.2f on the distal thumb" % MIN_BONE_DOMINANCE,
		}
	# Deterministic order, independent of mesh traversal.
	out.sort_custom(func(x, y): return str(x["key"]) < str(y["key"]))
	return {"tris": out, "min_dominance": min_dom, "flip_histogram": flips}


## Surface components sharing vertex indices. Purely topological.
static func _connected_components(tris: Array) -> Array:
	var vert_to_tris := {}
	for ti in tris.size():
		for v in (tris[ti]["i"] as Array):
			var key: int = int(v)
			if not vert_to_tris.has(key):
				vert_to_tris[key] = []
			(vert_to_tris[key] as Array).append(ti)
	var seen := {}
	var comps: Array = []
	for start in tris.size():
		if seen.has(start):
			continue
		var stack: Array = [start]
		var group: Array = []
		seen[start] = true
		while not stack.is_empty():
			var cur: int = int(stack.pop_back())
			group.append(tris[cur])
			for v in (tris[cur]["i"] as Array):
				for nb in (vert_to_tris[int(v)] as Array):
					if not seen.has(int(nb)):
						seen[int(nb)] = true
						stack.append(int(nb))
		group.sort_custom(func(x, y): return str(x["key"]) < str(y["key"]))
		comps.append(group)
	comps.sort_custom(func(x, y): return str((x[0] as Dictionary)["key"]) < str((y[0] as Dictionary)["key"]))
	return comps


## Select every triangle whose score clears the threshold, and require a
## real margin to the best rejected candidate so the choice is stable
## rather than a silent "closest wins".
static func _select_patch(
	tip: Array, score_key: String, threshold: float, require_dorsal: bool, calib
) -> Dictionary:
	var min_margin: float = float(calib.MIN_CLASSIFICATION_MARGIN)
	var chosen: Array = []
	var best_rejected := -2.0
	var worst_chosen := 2.0
	for tri in tip:
		var s: float = float(tri[score_key])
		var eligible: bool = s >= threshold
		if eligible and require_dorsal and float(tri["d_volar"]) >= 0.0:
			eligible = false
		if eligible:
			chosen.append(tri)
			worst_chosen = minf(worst_chosen, s)
		else:
			best_rejected = maxf(best_rejected, s)
	if chosen.is_empty():
		return {"ok": false, "detail": "no candidate cleared %.2f" % threshold}
	var margin: float = worst_chosen - best_rejected
	if margin < min_margin:
		return {
			"ok": false,
			"detail": "margin %.4f below %.2f (worst kept %.4f, best rejected %.4f)"
				% [margin, min_margin, worst_chosen, best_rejected],
		}
	chosen.sort_custom(func(x, y): return str(x["key"]) < str(y["key"]))
	return {
		"ok": true,
		"tris": chosen,
		"margin": margin,
		"best_rejected": best_rejected,
		"confidence": clampf(margin / (1.0 - threshold + 1e-6), 0.0, 1.0),
	}


static func _aggregate_normal(tris: Array) -> Vector3:
	var acc := Vector3.ZERO
	for tri in tris:
		acc += (tri["n_local"] as Vector3) * float(tri["area"])
	return acc


## True surface centroid of the patch: area-weighted, so a patch that is
## retriangulated into more small triangles does not drag the marker.
static func _aggregate_centroid(tris: Array) -> Vector3:
	var acc := Vector3.ZERO
	var w := 0.0
	for tri in tris:
		var a: float = float(tri["area"])
		acc += (tri["centroid_local"] as Vector3) * a
		w += a
	if w <= 0.0:
		return Vector3.ZERO
	return acc / w


## Engine-facing patch records: surface, vertex triple, UV centroid
## back-reference and the rest-anchored winding flip.
static func _serialize_patch(tris: Array) -> Array:
	var out: Array = []
	for tri in tris:
		out.append({
			"si": int(tri["si"]),
			"i": (tri["i"] as Array).duplicate(),
			"uvc": tri["uvc"],
			"flip": float(tri["flip"]),
		})
	return out


static func _verify_chains(skeleton: Skeleton3D, bones: Dictionary) -> Dictionary:
	if skeleton.find_bone(str(bones["hand"])) < 0:
		return {"ok": false, "error_class": "HAND_SKELETON_INCOMPLETE", "detail": "hand bone"}
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		if not bones.has(digit):
			return {
				"ok": false, "error_class": "FIXTURE_FAMILY_MISMATCH", "detail": "no %s" % digit
			}
		for bn in (bones[digit] as Array):
			if skeleton.find_bone(str(bn)) < 0:
				return {
					"ok": false,
					"error_class": "HAND_SKELETON_INCOMPLETE",
					"detail": "%s missing %s" % [digit, bn],
				}
	return {"ok": true}


## The distal thumb has to sit within a few hand spans of the wrist it is
## mapped to. The span is measured from this rig's own finger knuckles, so
## no absolute distance or unit scale is assumed.
const THUMB_REACH_HAND_SPANS := 4.0


static func _verify_thumb_belongs_to_hand(
	skeleton: Skeleton3D, bones: Dictionary, t3: int
) -> Dictionary:
	var hand_i: int = skeleton.find_bone(str(bones["hand"]))
	if hand_i < 0 or t3 < 0:
		return {"ok": false, "detail": "hand or distal thumb unresolved"}
	var hand_o: Vector3 = skeleton.get_bone_global_rest(hand_i).origin
	var span := 0.0
	for digit in ["index", "middle", "ring", "pinky"]:
		var mcp: int = skeleton.find_bone(str((bones[digit] as Array)[0]))
		if mcp < 0:
			return {"ok": false, "detail": "%s knuckle unresolved" % digit}
		span = maxf(span, hand_o.distance_to(skeleton.get_bone_global_rest(mcp).origin))
	if span <= 0.0:
		return {"ok": false, "detail": "hand span is degenerate"}
	var reach: float = hand_o.distance_to(skeleton.get_bone_global_rest(t3).origin)
	if reach > span * THUMB_REACH_HAND_SPANS:
		return {
			"ok": false,
			"detail": "mapped thumb is %.1f hand spans from this wrist" % (reach / span),
		}
	return {"ok": true, "hand_span": span, "thumb_reach": reach}


static func _verify_volar(
	skeleton: Skeleton3D, character: Node, frame: Dictionary, skin
) -> Dictionary:
	var thumb_side: float = (
		(frame["thumb_ref"] as Vector3) - (frame["palm_centre"] as Vector3)
	).dot(frame["volar"] as Vector3)
	var probe: Dictionary = HandProfile.skinned_palm_flesh_probe(
		skeleton, character, frame, skin
	)
	if not bool(probe.get("ok", false)):
		return {"ok": false, "detail": str(probe.get("error_class", "probe failed"))}
	var mesh_side: float = float(probe["extent_metric"])
	if (thumb_side > 0.0) != (mesh_side > 0.0):
		return {
			"ok": false,
			"detail": "thumb column %.6f disagrees with skinned flesh %.6f" % [thumb_side, mesh_side],
		}
	if thumb_side <= 0.0:
		return {"ok": false, "detail": "volar sign inverted"}
	return {"ok": true, "thumb_side": thumb_side, "mesh_side": mesh_side}


static func _tri_key(ids: Array) -> String:
	var s: Array = []
	for i in ids:
		s.append(int(i))
	s.sort()
	return "%08d_%08d_%08d" % [int(s[0]), int(s[1]), int(s[2])]


static func _fail(side: String, error_class: String, detail: String) -> Dictionary:
	return {
		"compiled": false,
		"side": side,
		"error_class": error_class,
		"detail": detail,
	}


static func _failed_artifact(error_class: String, detail: String) -> Dictionary:
	var art := {
		"ok": false,
		"acceptance_scope": ACCEPTANCE_SCOPE,
		"compiler_version": COMPILER_VERSION,
		"schema": ARTIFACT_SCHEMA,
		"error_class": error_class,
		"detail": detail,
		"sides": {},
	}
	art["content_hash"] = content_hash(art)
	return art


static func _artifact(
	mi: MeshInstance3D,
	skeleton: Skeleton3D,
	family,
	per_side: Dictionary,
	all_ok: bool,
	bone_maps: Dictionary,
	calib
) -> Dictionary:
	var art := {
		"ok": all_ok,
		# A compiler PASS is surface evidence, never an accepted asset.
		"acceptance_scope": ACCEPTANCE_SCOPE,
		"compiler_version": COMPILER_VERSION,
		"schema": ARTIFACT_SCHEMA,
		"compile_space": HandProfile.SPACE_SKELETON,
		"compile_pose": "skeleton_rest",
		"family_id": str(family.FAMILY_ID),
		"family_version": str(family.FAMILY_VERSION),
		# Binds identity to the bone map that was actually used, so an
		# unversioned edit of the family map still invalidates the artifact.
		"family_bone_map_digest": bone_map_digest(bone_maps),
		"calibration_id": str(calib.CALIBRATION_ID),
		"calibration_version": str(calib.CALIBRATION_VERSION),
		"min_classification_margin": float(calib.MIN_CLASSIFICATION_MARGIN),
		# Two DISTINCT source identities (A2.12). Geometry alone cannot vouch
		# for a fixture whose every marker lives in bone-local space.
		"source_geometry_sha256": geometry_identity(mi),
		"source_rig_sha256": rig_identity(mi, skeleton),
		"rig_identity_schema": RIG_IDENTITY_SCHEMA,
		"skeleton_bone_count": skeleton.get_bone_count(),
		"sides": per_side,
	}
	art = canonicalize(art)
	art["content_hash"] = content_hash(art)
	return art


## Digest of the resolved bone maps that produced this artifact.
static func bone_map_digest(bone_maps: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_canonical_text(bone_maps).to_utf8_buffer())
	return ctx.finish().hex_encode().to_upper().substr(0, 32)


static func _has_const(script_obj, name: String) -> bool:
	if script_obj == null:
		return false
	var s: Script = script_obj as Script
	if s == null:
		return false
	return s.get_script_constant_map().has(name)


## Write the artifact as serialized data. Never emits GDScript.
static func save_artifact(artifact: Dictionary, path: String) -> Dictionary:
	var res: Resource = ArtifactResource.new()
	res.payload = artifact.duplicate(true)
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_WRITE_FAILED", "godot_error": err}
	return {"ok": true, "path": path, "content_hash": str(artifact.get("content_hash", ""))}


## Load an artifact and re-verify its own content hash before anyone can
## consume it, so a hand-edited artifact cannot pass as compiled evidence.
static func load_artifact(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_MISSING", "path": path}
	var res: Resource = load(path)
	if res == null or not ("payload" in res):
		return {"ok": false, "error_class": "FIXTURE_SCHEMA_UNSUPPORTED", "path": path}
	var payload: Dictionary = res.payload
	if not str(payload.get("schema", "")) in SUPPORTED_SCHEMAS:
		return {
			"ok": false,
			"error_class": "FIXTURE_SCHEMA_UNSUPPORTED",
			"schema": str(payload.get("schema", "")),
		}
	if str(payload.get("compiler_version", "")) != COMPILER_VERSION:
		return {
			"ok": false,
			"error_class": "FIXTURE_SCHEMA_UNSUPPORTED",
			"detail": "artifact was produced by '%s'" % payload.get("compiler_version", ""),
		}
	if content_hash(payload) != str(payload.get("content_hash", "")):
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_HASH_MISMATCH", "path": path}
	return {"ok": true, "artifact": payload}


## GEOMETRY IDENTITY — identity level 1a. The static geometry the patches
## reference by index: vertex, normal, UV, bone-index and weight streams of
## every surface, plus the index buffer. Any mesh edit that could move a
## referenced triangle changes this hash.
##
## It is deliberately NOT sufficient to authorise a fixture: the compiled
## markers and normals live in BONE-LOCAL space, so they are also a function of
## the rig. See `rig_identity`.
static func geometry_identity(mi: MeshInstance3D) -> String:
	if mi == null or mi.mesh == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(mi.mesh.get_surface_count()))
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		ctx.update(var_to_bytes(si))
		for slot in [
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV,
			Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX
		]:
			var data = arrays[slot]
			if data == null:
				continue
			ctx.update(var_to_bytes(slot))
			ctx.update(var_to_bytes(data))
	return ctx.finish().hex_encode().to_upper()


const RIG_IDENTITY_SCHEMA := "source_rig_identity_v1"


## RIG / DEFORMATION IDENTITY — identity level 1b, and the one that actually
## binds a compiled fixture.
##
## The A2.11 identity hashed the mesh arrays only, so changing a bone rest or a
## skin bind pose left the identity untouched while every compiled marker moved:
## a stale artifact bound successfully. This hash therefore covers the whole
## deformation contract, in a canonical order that is independent of scene
## placement, node scale and the current pose:
##
##   * the geometry identity above (topology, positions, indices, normals, UVs,
##     bone indices, weights),
##   * the skin: bind count, per-bind bone index, bind NAME and bind POSE,
##   * the bind -> skeleton bone resolution actually used by CPU skinning,
##   * every bone's name, PARENT (hierarchy) and REST transform,
##   * the mesh -> skeleton relation (the skeleton path the mesh instance uses
##     and the mesh instance's own transform relative to the skeleton).
##
## Rest transforms and bind poses are pose-independent by construction, so a
## runtime animation frame or an ancestor transform cannot change this hash —
## only a genuine rig, skin or import change can.
static func rig_identity(mi: MeshInstance3D, skeleton: Skeleton3D) -> String:
	if mi == null or mi.mesh == null or skeleton == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(RIG_IDENTITY_SCHEMA.to_utf8_buffer())
	ctx.update(geometry_identity(mi).to_utf8_buffer())
	# --- skin: bind poses and bind naming ---
	var skin: Skin = mi.skin
	ctx.update(var_to_bytes(0 if skin == null else skin.get_bind_count()))
	if skin != null:
		for bi in skin.get_bind_count():
			ctx.update(var_to_bytes(bi))
			ctx.update(var_to_bytes(skin.get_bind_bone(bi)))
			ctx.update(String(skin.get_bind_name(bi)).to_utf8_buffer())
			ctx.update(var_to_bytes(_canonical_transform(skin.get_bind_pose(bi))))
	# --- the bind -> bone resolution CPU skinning actually uses ---
	ctx.update(var_to_bytes(DefaultSkinning.bind_to_skeleton_map(mi, skeleton)))
	# --- skeleton: names, hierarchy, rest ---
	ctx.update(var_to_bytes(skeleton.get_bone_count()))
	for b in skeleton.get_bone_count():
		ctx.update(var_to_bytes(b))
		ctx.update(skeleton.get_bone_name(b).to_utf8_buffer())
		ctx.update(var_to_bytes(skeleton.get_bone_parent(b)))
		ctx.update(var_to_bytes(_canonical_transform(skeleton.get_bone_rest(b))))
	# --- the imported mesh <-> skeleton relation ---
	# Derived from LOCAL transforms up each node's own ancestor chain, so the
	# identity is the same whether the asset is inside a live scene tree or was
	# just instantiated for hashing, and is unaffected by where the character
	# is placed, rotated or scaled in the world.
	ctx.update(str(mi.skeleton).to_utf8_buffer())
	ctx.update(
		var_to_bytes(
			_canonical_transform(
				_transform_in_asset(skeleton).affine_inverse() * _transform_in_asset(mi)
			)
		)
	)
	return ctx.finish().hex_encode().to_upper()


## A node's transform relative to the topmost Node3D of its own asset, from
## local transforms only. Never `global_transform`: that needs a live tree and
## would fold scene placement into an identity that must not depend on it.
static func _transform_in_asset(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != null:
		t = cursor.transform * t
		cursor = cursor.get_parent() as Node3D
	return t


## Transforms enter identity on the same quantised grid the payload uses, so
## float noise in an import cannot flip the hash while a real edit still does.
static func _canonical_transform(t: Transform3D) -> Transform3D:
	return Transform3D(
		canonicalize(t.basis.x), canonicalize(t.basis.y), canonicalize(t.basis.z),
		canonicalize(t.origin)
	)


## SOURCE IDENTITY OF AN ASSET ON DISK — level 1, derived from the real
## resource rather than from an artifact's own payload. This is what a
## composition root uses to state which rigged mesh its fixture is allowed to
## pose, so no caller ever hard-codes a hash of a specific warrior.
static func rig_identity_of_asset(scene_path: String, skinning = null) -> Dictionary:
	var skin = skinning if skinning != null else DefaultSkinning
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error_class": "FIXTURE_SOURCE_ASSET_MISSING", "path": scene_path}
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return {"ok": false, "error_class": "FIXTURE_SOURCE_ASSET_MISSING", "path": scene_path}
	var inst: Node = packed.instantiate()
	var mi: MeshInstance3D = skin.find_skinned_mesh(inst)
	var skeleton: Skeleton3D = skin.find_skeleton(inst)
	if mi == null or mi.mesh == null:
		inst.free()
		return {"ok": false, "error_class": "FIXTURE_SOURCE_MESH_MISSING", "path": scene_path}
	if skeleton == null:
		inst.free()
		return {"ok": false, "error_class": "FIXTURE_SOURCE_RIG_MISSING", "path": scene_path}
	skeleton.force_update_all_bone_transforms()
	var geo: String = geometry_identity(mi)
	var rig: String = rig_identity(mi, skeleton)
	inst.free()
	return {
		"ok": true,
		"geometry_sha256": geo,
		"rig_sha256": rig,
		"rig_identity_schema": RIG_IDENTITY_SCHEMA,
		"path": scene_path,
	}


## Fixture semantic/content identity — identity level 2 of four.
##
##   1. source identity — `source_geometry_sha256` (static geometry) and
##      `source_rig_sha256` (the whole deformation contract): the rigged mesh
##      that was compiled and that must later be the rigged mesh actually posed.
##   2. fixture content identity — THIS hash, over the canonical payload.
##   3. acceptance result — bind sanity plus grip ground truth for
##      mesh + fixture + policy, produced by the ingestion chain and never
##      stored inside the EVIDENCE payload as a licence to load.
##   4. certification identity — the certified runtime envelope's own hash,
##      which binds levels 1-3 together; see `certification_hash`.
##
## CANONICAL REPRESENTATION. Every float in the payload is snapped to
## `IDENTITY_QUANTUM` when the artifact is CREATED, so the stored numbers ARE
## the canonical numbers: runtime consumes exactly the representation that was
## hashed, never a rounded view of unrounded data. The hash then covers the
## WHOLE payload except `content_hash` itself and `source_asset` (a filesystem
## path, pure provenance): patches, winding flips, rest normals, markers, UV
## back-references, family id/version, resolved bone-map digest, calibration
## id/version, schema/compiler version, source mesh identity, per-side
## compiled flags and error classes, confidence and evidence.
##
## ERROR BUDGET. 1e-6 on a unit normal is 6e-5 degrees, on a marker in model
## units 1 µm: orders of magnitude below every gate tolerance in the grip
## pipeline (rest-normal dot 0.98+, marker agreement 4 mm), and far above the
## float32 resolution of the stored `.tres` values so re-reading a stored
## value snaps back to the same grid point. It is NOT the mechanism that makes
## the hash context-independent -- the canonical compile space and rest pose
## are -- so it never has to absorb a real geometric difference: a moved
## triangle, a flipped winding or a retriangulated patch all change the hash.
const IDENTITY_QUANTUM := 1e-6
## Excluded from the hash: the hash field itself and provenance.
const IDENTITY_EXCLUDED_KEYS: Array[String] = ["content_hash", "source_asset"]


static func content_hash(artifact: Dictionary) -> String:
	var hashable := {}
	for k in artifact.keys():
		if str(k) in IDENTITY_EXCLUDED_KEYS:
			continue
		hashable[str(k)] = artifact[k]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_canonical_text(canonicalize(hashable)).to_utf8_buffer())
	return ctx.finish().hex_encode().to_upper()


## Snap every float to the canonical grid, recursively. Idempotent, so
## re-canonicalising a stored artifact yields the stored numbers again.
static func canonicalize(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var out := {}
			for k in d.keys():
				out[k] = canonicalize(d[k])
			return out
		TYPE_ARRAY:
			var a: Array = value
			var arr: Array = []
			for it in a:
				arr.append(canonicalize(it))
			return arr
		TYPE_FLOAT:
			return snappedf(float(value), IDENTITY_QUANTUM)
		TYPE_VECTOR3:
			var v: Vector3 = value
			return Vector3(
				snappedf(v.x, IDENTITY_QUANTUM),
				snappedf(v.y, IDENTITY_QUANTUM),
				snappedf(v.z, IDENTITY_QUANTUM)
			)
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return Vector2(
				snappedf(v2.x, IDENTITY_QUANTUM), snappedf(v2.y, IDENTITY_QUANTUM)
			)
		_:
			return value


## The canonical serialisation any identity in this pipeline is hashed over.
## Public so the certification owner hashes its envelope with exactly the same
## rules as the fixture payload, rather than inventing a second convention.
static func canonical_text(value) -> String:
	return _canonical_text(value)


## Key-sorted, precision-pinned text so the same geometry always hashes the
## same regardless of dictionary insertion order.
static func _canonical_text(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = d.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts: Array[String] = []
			for k in keys:
				parts.append("%s=%s" % [str(k), _canonical_text(d[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var a2: Array = value
			var items: Array[String] = []
			for it in a2:
				items.append(_canonical_text(it))
			return "[%s]" % ",".join(items)
		TYPE_FLOAT:
			return "%.9f" % float(value)
		TYPE_VECTOR3:
			var v: Vector3 = value
			return "(%.9f,%.9f,%.9f)" % [v.x, v.y, v.z]
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return "(%.9f,%.9f)" % [v2.x, v2.y]
		_:
			return str(value)
