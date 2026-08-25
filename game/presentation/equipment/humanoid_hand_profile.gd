# Compiled per-side hand description. Reusable infrastructure: future
# generated humanoids compile or load their own profile and fail closed
# when confidence is insufficient. Skeleton family, per-asset fixture and
# the CPU-skinning implementation are INJECTED (A2.9) — the generic profile
# never preloads a family convention or an asset script.
extends RefCounted

const DIGITS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const FINGER_ORDER: Array[String] = ["index", "middle", "ring", "pinky"]

const VOLAR_PROBE_RADIUS_FRAC := 0.5
const VOLAR_PROBE_MIN_VERTS := 24
const PALM_CENTRE_FRACTION := 0.5

var side: String = "right"
var family_id: String = ""
var asset_id: String = ""
var fixture_schema: String = ""
var bones: Dictionary = {}
var handedness: String = "right"
var chirality_ok: bool = false
var surface: Dictionary = {}
var thumb_anat: Dictionary = {}
var finger_flex: Dictionary = {}
var confidence: float = 0.0
var compile_failures: Array[String] = []
var _cache_key: String = ""
var _family = null
var _skinning = null


## `fixture` is required compiled per-asset data (surface patches, thumb
## anatomical numbers). Never fall back to another warrior's triangle IDs,
## a brightness heuristic, a copied right-hand quaternion, or a negated axis.
## `family` owns bone-name templates and hinge/tip conventions; `skinning`
## owns CPU skinning + mesh probing. All three fail closed when missing.
static func compile(
	skeleton: Skeleton3D,
	character: Node,
	side_in: String,
	fixture = null,
	family = null,
	skinning = null
) -> Dictionary:
	var profile := new()
	return profile._compile(skeleton, character, side_in, fixture, family, skinning)


func _compile(
	skeleton: Skeleton3D, character: Node, side_in: String, fixture, family, skinning
) -> Dictionary:
	side = "left" if side_in == "left" else "right"
	handedness = side
	compile_failures.clear()
	if family == null or not family.has_method("bone_map"):
		compile_failures.append("HAND_PROFILE_FAMILY_REQUIRED")
		return _result(false)
	if skinning == null or not skinning.has_method("skinned_vertex_world"):
		compile_failures.append("HAND_PROFILE_SKINNING_REQUIRED")
		return _result(false)
	if fixture == null or not fixture.has_method("surface_for_side"):
		compile_failures.append("HAND_PROFILE_FIXTURE_REQUIRED")
		return _result(false)
	_family = family
	_skinning = skinning
	family_id = str(family.FAMILY_ID)
	bones = family.bone_map(side)
	asset_id = str(fixture.ASSET_ID)
	fixture_schema = str(fixture.SCHEMA_VERSION)
	if skeleton == null:
		compile_failures.append("HAND_PROFILE_NO_SKELETON")
		return _result(false)
	var hand_i: int = skeleton.find_bone(str(bones["hand"]))
	if hand_i < 0:
		compile_failures.append("HAND_PROFILE_HAND_BONE_MISSING")
		return _result(false)
	for digit in DIGITS:
		for bname in (bones[digit] as Array):
			if skeleton.find_bone(str(bname)) < 0:
				compile_failures.append("HAND_PROFILE_CHAIN_MISSING")
				return _result(false)
	surface = fixture.surface_for_side(side, character, skeleton)
	thumb_anat = fixture.thumb_anat_for_side(side)
	if fixture.has_method("finger_flex"):
		finger_flex = fixture.finger_flex()
	if not bool(surface.get("compiled", false)):
		compile_failures.append(str(surface.get("error_class", "HAND_PROFILE_SURFACE_MISSING")))
		return _result(false)
	var frame: Dictionary = compute_frame(skeleton, false)
	if not bool(frame.get("ok", false)):
		compile_failures.append(str(frame.get("error_class", "HAND_PROFILE_FRAME_FAILED")))
		return _result(false)
	if float(frame.get("det", 0.0)) < 0.99:
		compile_failures.append("HAND_PROFILE_DET_NOT_POSITIVE")
		return _result(false)
	chirality_ok = true
	if character != null:
		var volar: Dictionary = verify_volar(skeleton, character, frame)
		if not bool(volar.get("ok", false)):
			compile_failures.append(str(volar.get("error_class", "HAND_PROFILE_VOLAR_FAILED")))
			return _result(false)
	confidence = 1.0 if compile_failures.is_empty() else 0.0
	_cache_key = "%s|%s|%s|%s" % [family_id, asset_id, fixture_schema, side]
	return _result(true)


func _result(ok: bool) -> Dictionary:
	return {
		"ok": ok,
		"profile": self,
		"side": side,
		"family_id": family_id,
		"asset_id": asset_id,
		"fixture_schema": fixture_schema,
		"bones": bones,
		"handedness": handedness,
		"chirality_ok": chirality_ok,
		"surface": surface,
		"thumb_anat": thumb_anat,
		"finger_flex": finger_flex,
		"confidence": confidence,
		"failures": compile_failures,
		"cache_key": _cache_key,
	}


## Anatomical palm frame from THIS side's bones. A = index − pinky so
## radial always means the thumb/index side of that hand. Never a copied
## right-hand quaternion and never a blind coordinate negation.
func compute_frame(skeleton: Skeleton3D, use_rest: bool) -> Dictionary:
	if skeleton == null:
		return {"ok": false, "error_class": "HAND_FRAME_NO_SKELETON"}
	var hand_i: int = skeleton.find_bone(str(bones["hand"]))
	if hand_i < 0:
		return {"ok": false, "error_class": "HAND_FRAME_HAND_BONE_MISSING"}
	if _family == null:
		return {"ok": false, "error_class": "HAND_PROFILE_FAMILY_REQUIRED"}
	var mcp := {}
	var hinge := {}
	var chain_length := {}
	for finger in FINGER_ORDER:
		var chain: Array = bones[finger]
		var mcp_i: int = skeleton.find_bone(str(chain[0]))
		var mid_i: int = skeleton.find_bone(str(chain[1]))
		var dst_i: int = skeleton.find_bone(str(chain[2]))
		if mcp_i < 0 or mid_i < 0 or dst_i < 0:
			return {"ok": false, "error_class": "HAND_FRAME_FINGER_CHAIN_MISSING", "finger": finger}
		var mcp_xf: Transform3D = _bone_xf(skeleton, mcp_i, use_rest)
		var mid_p: Vector3 = _bone_xf(skeleton, mid_i, use_rest).origin
		var dst_p: Vector3 = _bone_xf(skeleton, dst_i, use_rest).origin
		mcp[finger] = mcp_xf.origin
		hinge[finger] = (mcp_xf.basis * (_family.MCP_HINGE_LOCAL as Vector3)).normalized()
		var seg1: float = mcp_xf.origin.distance_to(mid_p)
		var seg2: float = mid_p.distance_to(dst_p)
		chain_length[finger] = seg1 + seg2 + seg2 * float(_family.DISTAL_TIP_FRACTION)
	var thumb_pts: Array[Vector3] = []
	for tb in (bones["thumb"] as Array):
		var ti: int = skeleton.find_bone(str(tb))
		if ti < 0:
			return {"ok": false, "error_class": "HAND_FRAME_THUMB_CHAIN_MISSING"}
		thumb_pts.append(_bone_xf(skeleton, ti, use_rest).origin)
	var thumb_ref: Vector3 = (thumb_pts[1] + thumb_pts[2]) * 0.5
	var hand_xf: Transform3D = _bone_xf(skeleton, hand_i, use_rest)
	var wrist: Vector3 = hand_xf.origin
	var knuckle := Vector3.ZERO
	for finger in FINGER_ORDER:
		knuckle += mcp[finger] as Vector3
	knuckle /= float(FINGER_ORDER.size())
	var longitudinal: Vector3 = knuckle - wrist
	if longitudinal.length_squared() < 1e-12:
		return {"ok": false, "error_class": "HAND_FRAME_DEGENERATE_LONGITUDINAL"}
	longitudinal = longitudinal.normalized()
	# Radial is always this hand's thumb/index side (index − pinky).
	# Volar is NOT assumed to be radial × L: on a left hand that product
	# points dorsal. Derive V from the thumb column (volar side of the
	# palm), then complete a right-handed triad. That is anatomical
	# derivation, not coordinate negation and not a mirrored det −1 frame.
	var radial: Vector3 = (mcp["index"] as Vector3) - (mcp["pinky"] as Vector3)
	var knuckle_breadth: float = radial.length()
	if knuckle_breadth < 1e-9:
		return {"ok": false, "error_class": "HAND_FRAME_DEGENERATE_BREADTH"}
	radial = (radial - longitudinal * radial.dot(longitudinal))
	if radial.length_squared() < 1e-12:
		return {"ok": false, "error_class": "HAND_FRAME_ACROSS_PARALLEL"}
	radial = radial.normalized()
	var v_trial: Vector3 = radial.cross(longitudinal).normalized()
	var palm_centre_early: Vector3 = wrist.lerp(knuckle, PALM_CENTRE_FRACTION)
	var thumb_along_trial: float = (thumb_ref - palm_centre_early).dot(v_trial)
	var volar: Vector3 = v_trial
	var across: Vector3 = radial
	if thumb_along_trial < 0.0:
		volar = -v_trial
		across = longitudinal.cross(volar).normalized()
	var basis := Basis(across, longitudinal, volar)
	var det: float = basis.determinant()
	if det < 0.99:
		return {"ok": false, "error_class": "HAND_FRAME_NOT_RIGHT_HANDED", "det": det}
	var palm_centre: Vector3 = wrist.lerp(knuckle, PALM_CENTRE_FRACTION)
	return {
		"ok": true,
		"use_rest": use_rest,
		"side": side,
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
		"dorsal": -volar,
		"radial": radial,
		"ulnar": -radial,
		"basis": basis,
		"det": det,
		"hand_length": wrist.distance_to(knuckle),
		"knuckle_breadth": knuckle_breadth,
	}


func verify_volar(skeleton: Skeleton3D, character: Node, frame: Dictionary) -> Dictionary:
	if not bool(frame.get("ok", false)):
		return {"ok": false, "error_class": "VOLAR_BAD_FRAME"}
	if bool(frame.get("use_rest", false)):
		return {"ok": false, "error_class": "VOLAR_REQUIRES_POSE_FRAME"}
	var palm_c: Vector3 = frame["palm_centre"]
	var volar: Vector3 = frame["volar"]
	var thumb_side: float = ((frame["thumb_ref"] as Vector3) - palm_c).dot(volar)
	var thumb_ok: bool = thumb_side > 0.0
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


func _skinned_palm_flesh_probe(
	skeleton: Skeleton3D, character: Node, frame: Dictionary
) -> Dictionary:
	if _skinning == null:
		return {"ok": false, "error_class": "HAND_PROFILE_SKINNING_REQUIRED"}
	var mi: MeshInstance3D = _skinning.find_skinned_mesh(character)
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
		var bones_i: PackedInt32Array = bones_arr as PackedInt32Array
		var bpv: int = _skinning.bones_per_vertex(bones_i, verts.size())
		for vi in verts.size():
			var world_v: Vector3 = _skinning.skinned_vertex_world(
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


static func _bone_xf(skeleton: Skeleton3D, idx: int, use_rest: bool) -> Transform3D:
	var g: Transform3D
	if use_rest:
		g = skeleton.global_transform * skeleton.get_bone_global_rest(idx)
	else:
		g = skeleton.global_transform * skeleton.get_bone_global_pose(idx)
	return Transform3D(g.basis.orthonormalized(), g.origin)
