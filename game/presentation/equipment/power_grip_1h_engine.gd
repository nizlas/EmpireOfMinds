# Generic power_grip_1h engine (A2.9 ownership inversion of the accepted
# A2.7 implementation): canonical authored power-grip pose + bounded radius
# refinement (audit Section 6 hybrid). Never free CCD: the correctness layer
# is the socket frame mapping + the canonical pose; refinement only adjusts
# flexion within ±15 deg from measured pad gaps and degrades to the canonical
# pose on failure. Post-animation, deterministic, reversible.
#
# The engine owns MECHANISMS and the power_grip_1h_v1 gate bands only. All
# skeleton-family and per-asset data (bone chains, canonical pose numbers,
# verified surface patches, tip bones) arrive through an injected
# HumanoidHandProfile — or, for the legacy A2 compatibility shell, through
# the overridable `_fallback_*` seams. The generic engine itself fails
# closed without a profile; it never names a bone, a mesh triangle or an
# asset path.
extends SkeletonModifier3D

const GripShape = preload("res://presentation/equipment/melee_grip_shape.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")

const GRIP_ID := "power_grip_v1"

const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]
const ALL_DIGITS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]

## Bind-sanity tolerances for the compiled patches.
const PATCH_UV_TOL := 0.002
const PATCH_REST_NORMAL_MIN_DOT := 0.98

## R1 winding gates (A2.2, kept).
const THUMB_WINDING_MIN_DEG := 60.0
const FINGER_WINDING_MIN_DEG := 45.0
## R4 approach gates (A2.2, kept).
const THUMB_APPROACH_AXIAL_FRAC_MAX := 0.60
const THUMB_APPROACH_RADIAL_MAX_RADII := 0.15
## R3 contact gates (kept; the axial-lying discriminator moves to 0.70 in
## A2.3: it exists to reject the A2.1 thumb LYING along the shaft (0.93),
## while the correct anatomical counter-winding chain measures 0.55-0.63
## end-to-end because its pad sits distally at the index-side station.
## Per-joint anatomy is now owned by R5-R9, so 0.70 still cleanly separates
## the defect (0.93) from correct poses without doing anatomy's job.
const THUMB_AXIAL_DOT_MAX := 0.70
const THUMB_TRANSVERSE_RATIO_MIN := 1.2
const THUMB_GAP_MAX_RADII := 0.35
const THUMB_PEN_MAX_RADII := 0.20
const THUMB_CHAIN_MIN_GAP_RADII := -0.25
const THUMB_VOLAR_CLEARANCE_MIN_HAND := -0.15
## R5/R6 anatomical flexion and chain-consistency tolerances (A2_2 audit
## Section 10): no hyperextension beyond a small tolerance, no S-chain.
const THUMB_BEND_HYPEREXT_TOL_DEG := -10.0
## R7 direction classification, along-station normalized (ring = 0,
## index = 1, from the LIVE skinned finger pad stations).
const DIR_INDEX_MIN := 0.75
const DIR_INDEX_MIDDLE_MIN := 0.4
const GRIP_ZONE_DISTAL_MARGIN_R := 0.8
const GRIP_ZONE_PROXIMAL_MARGIN_R := 0.6
const TOWARD_WRIST_LONG_DOT := -0.5
## R8 joint roles: MCP/IP may not compensate via lateral swing.
const MCP_IP_LATERAL_MAX_DEG := 30.0
## R9 rig-relative anatomical joint limits (measured frames, audit §10).
## A2.5: the CMC budget covers the coupled OPPOSITION PRONATION of a real
## thumb (~90 deg at full opposition) — the required pronation measured
## -90 deg on this rig, so the limit is 100 deg. The broken A2.2 pose is
## still rejected by the full contract (MCP hyperextension, pinky
## direction, lateral swing) and by the A2.5 nail gates; MCP/IP twist
## stays tightly bounded — pronation belongs to the CMC only.
const CMC_TWIST_MAX_DEG := 100.0
const MCP_IP_TWIST_MAX_DEG := 25.0
## R10 (A2.7 rewrite): distal surface-orientation gates against the
## VERIFIED plates. The compiled-normal projections in the wrap gate are a
## cheap rigid approximation; the authoritative acceptance is the GEOMETRIC
## gate below (deformed skinned triangles). Thresholds are derived from the
## audit's reachable-candidate set: the plate is curved with an inherent
## distal tilt, so aggregate out ~=0.75-0.87 is the anatomical ceiling and
## the A2.6 defect measured out +0.61 / axial 0.66 — the separators sit
## between defect and calibrated pose.
const NAIL_OUT_MIN := 0.3
const NAIL_AXIAL_MAX := 0.72
const PAD_IN_MIN := 0.25
const DISTAL_ROLL_MAX_DEG := 60.0
## A2.7 ground-truth gate thresholds, measured on DEFORMED skinned patch
## triangles (rest-anchored winding, per-triangle radials, area-weighted).
## Separators sit between the measured A2.6 defect (geom out +0.61 /
## axial 0.66) and the visually approved A2.7 calibrated pose (geom out
## +0.93 / axial 0.24 / roll +1 deg / pad_in +0.30).
const NAIL_GEOM_OUT_MIN := 0.72
const NAIL_GEOM_AX_MAX := 0.45
const PAD_GEOM_IN_MIN := 0.25
## The pad plate must be the contact side: its minimum surface gap stays
## below this bound while the nail plate stays clear of the surface by the
## margin (relative to the pad) — the nail must never be the closest
## surface to the shaft.
const PAD_CONTACT_GAP_MAX_R := 0.35
const NAIL_CONTACT_MARGIN_R := 0.05
## Deformed nail/pad relation may not drift arbitrarily from the compiled
## rest relation (skinning tolerance; a real quarter-turn shows up here).
const GEOM_NAIL_PAD_DOT_TOL := 0.45
const DISTAL_PHYS_ROLL_MAX_DEG := 65.0
## A2.6 distributed-contour contact gates, measured on the SKINNED volar
## thumb patches (Thumb1/CMC flesh, Thumb2/middle, Thumb3/distal) against
## the live shaft surface, all in grip radii. The contact corridor is the
## interpolation between the achieved neighbour contacts (CMC min gap and
## the distal pad gap); the middle patch may keep a natural crease above
## it but not an isolated visible gap. Thresholds sit between the measured
## A2.5 defect (mid excess 0.34r, T2 median 0.49r) and the calibrated
## A2.6 pose (0.21r / 0.33r).
## A2.7 recalibration: the volar-flesh classifier now uses the VERIFIED
## pad-plate normal (audit §4), which is ~56 deg away from the mislabeled
## A2.5 reference; the patches therefore select different (honest) skin
## and the old absolute radii are not comparable. The bands below are
## re-anchored on the visually approved A2.7 pose (mid excess 0.97r, T2
## median 1.23r, bulge 0.68r, kink 0.69r, max jump 24 deg) with margin
## covering the 0.9x-radius robustness case (all r-normalized values grow
## ~11% when the solver radius shrinks while the flesh does not);
## the structural protections (patch presence, distributed contact,
## penetration bound, monotonic winding, discontinuity) are unchanged.
const CONTOUR_NEAR_CONTACT_MAX_R := 0.30
const CONTOUR_MID_EXCESS_MAX_R := 1.25
const CONTOUR_MID_MED_MAX_R := 1.55
const CONTOUR_BULGE_MAX_R := 0.90
const CONTOUR_MID_PEN_MIN_R := -0.30
const CONTOUR_KINK_OUT_MAX_R := 0.90
const CONTOUR_JUMP_MAX_DEG := 100.0
const CONTOUR_BACKTRACK_TOL_DEG := 10.0
const CONTOUR_MIN_PATCH_VERTS := 2
## The T2 volar flesh in an honest frame crosses the shaft tangentially
## (it faces the palm/index side, not the shaft centre) — only a nearly
## fully outward-facing middle segment (flipped thumb) is rejected.
const CONTOUR_T2_FACE_MIN := -0.85
const MCP_FLEX_MAX_DEG := 70.0
const IP_FLEX_MAX_DEG := 90.0
## Axis-derivation sensitivity: the empirical flexion-axis validation must
## see at least this much bend response, else fail closed.
const THUMB_AXIS_MIN_BEND_RESPONSE_DEG := 3.0

## Surface-sample contact threshold for encirclement, in grip radii (same
## value as the pad gap gate in the A2 test suite).
const CONTACT_GAP_RADII := 0.35

## Bounded refinement: flex delta from canonical, clamped, capped iterations.
const REFINE_DELTA_MAX := 0.2618  # 15 deg
const REFINE_ITERS := 10
const REFINE_WEIGHTS: Array[float] = [1.0, 0.7, 0.4]
## Thumb refinement is CMC-dominant: adduction sinks the whole chain toward
## thinner shafts, while IP-heavy refinement would wrap the pad further
## around the circumference and break opposition.
const THUMB_REFINE_WEIGHTS: Array[float] = [1.0, 0.25, 0.1]
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
## Measured CMC swing direction (+/-1) that closes the thumb pad toward
## the shaft under extra sigma; 0 = not yet probed for this binding.
var _thumb_cmc_sign := 0.0
## A2.3 anatomical thumb joint frames (rest-derived, empirically validated
## flexion axes per joint). Empty until derived; on failure the class is in
## _thumb_axis_failure and the thumb fails closed (no fallback pose).
var _thumb_frames: Array = []
var _thumb_axis_failure := ""
var _thumb_axis_flipped: Array = [false, false, false]
var _right_hand_idx: int = -1
var _right_forearm_idx: int = -1
var _modification_count: int = 0
var _last_diagnostics: Dictionary = {}
## A2.6 cached skinned volar-vertex refs per thumb joint patch (0=CMC,
## 1=Thumb2/middle, 2=Thumb3/distal), classified once at rest.
var _contour_refs: Dictionary = {}
var _last_contour: Dictionary = {}
var _last_contour_gate: Dictionary = {}
## A2.7 verified patch triangle refs, bind-sanity-checked at configure
## ({"nail": [...], "pad": [...]}, each {si, i, bpv, flip}).
var _patch_refs: Dictionary = {}
var _patch_bind_failure := ""
var _last_surface: Dictionary = {}
var _last_surface_gate: Dictionary = {}
## Calibration/test-only override of the canonical anatomical thumb pose
## (same keys as the profile's thumb_anat). Empty in production; lets probes
## and negative regressions drive broken/candidate poses through the REAL
## production pose path instead of a duplicated one.
var thumb_anat_override: Dictionary = {}
## Compiled HumanoidHandProfile (REQUIRED for the generic engine). The A2
## compatibility shell may instead serve legacy right-hand data through the
## `_fallback_*` seams below.
var _hand_profile = null
var _active_surface: Dictionary = {}
var _bound_frame: Dictionary = {}
var _tip_bones: Dictionary = {}
var _fb_surface_cache = null


# --- Injected-data seams (A2.9). The generic engine returns empty data and
# therefore fails closed without a profile; the A2 compatibility shell
# overrides these with the legacy right-hand fixture. Never asset data here.
func _fallback_surface() -> Dictionary:
	return {}


func _fallback_thumb_anat() -> Dictionary:
	return {}


func _fallback_finger_flex() -> Dictionary:
	return {}


func _fallback_bind_spec() -> Dictionary:
	return {}


func _fallback_tip_bones() -> Dictionary:
	return {}


func _fallback_live_frame(_skel: Skeleton3D) -> Dictionary:
	return {}


## Historical superseded-constant reference for the legacy false-positive
## diagnostic (never gated). Generic path: served by the fixture surface.
func _superseded_reference() -> Dictionary:
	var n: Vector3 = _surf("superseded_nail_normal_local", Vector3.ZERO)
	var p: Vector3 = _surf("superseded_pad_normal_local", Vector3.ZERO)
	if n.length_squared() < 1e-9 or p.length_squared() < 1e-9:
		return {}
	return {"nail": n, "pad": p}


func set_hand_profile(profile) -> void:
	_hand_profile = profile
	_active_surface = {}
	if profile != null and "surface" in profile:
		_active_surface = profile.surface


func _fb_surface() -> Dictionary:
	if _fb_surface_cache == null:
		_fb_surface_cache = _fallback_surface()
	return _fb_surface_cache


func _surf(key: String, fallback):
	if _active_surface.has(key):
		return _active_surface[key]
	var fb: Dictionary = _fb_surface()
	if fb.has(key):
		return fb[key]
	return fallback


func _nail_tris() -> Array:
	return _surf("nail_tris", [])


func _pad_tris() -> Array:
	return _surf("pad_tris", [])


func _nail_normal_local() -> Vector3:
	return _surf("nail_normal_local", Vector3.ZERO)


func _pad_normal_local() -> Vector3:
	return _surf("pad_normal_local", Vector3.ZERO)


func _rest_nail_pad_dot() -> float:
	return float(_surf("rest_nail_pad_dot", 0.0))


func _pad_marker_local() -> Vector3:
	return _surf("pad_marker_local", Vector3.ZERO)


func _canon_flex_deg() -> Dictionary:
	if _hand_profile != null and "finger_flex" in _hand_profile:
		var from_profile: Dictionary = _hand_profile.finger_flex
		if not from_profile.is_empty():
			return from_profile
	return _fallback_finger_flex()


## frame: pose-mode volar-verified hand grip frame (from the injected
## profile, or from the compatibility shell's legacy frame source).
func configure(
	character: Node, club: Node3D, shape: Dictionary, frame: Dictionary
) -> Dictionary:
	_character = character
	_club = club
	_shape = shape.duplicate(true)
	_fb_surface_cache = null
	if _hand_profile == null and _fallback_bind_spec().is_empty():
		return {
			"ok": false,
			"reason": "hand_profile_required",
			"error_class": "ENGINE_PROFILE_REQUIRED",
		}
	var skel := _resolve_skeleton()
	if skel == null:
		return {"ok": false, "reason": "no_skeleton"}
	if not bool(_shape.get("ok", false)):
		return {"ok": false, "reason": "bad_shape"}
	if not bool(frame.get("ok", false)):
		return {"ok": false, "reason": "bad_hand_frame"}
	var flex_table: Dictionary = _canon_flex_deg()
	for finger in FINGERS:
		if not flex_table.has(finger):
			return {
				"ok": false,
				"reason": "finger_flex_profile_missing",
				"error_class": "ENGINE_FLEX_PROFILE_MISSING",
			}
	_bound_frame = frame.duplicate(true)
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
	# A2.3: the thumb is posed in per-joint ANATOMICAL frames derived and
	# empirically validated at first solve (audit A2_2 root cause: MCP and
	# IP have OPPOSITE local-X flexion conventions on this rig, so no
	# single sign can be anatomical). Fail-closed on ambiguity.
	_thumb_frames = []
	_thumb_axis_failure = ""
	_thumb_axis_flipped = [false, false, false]
	_chain_lengths = (frame["chain_length"] as Dictionary).duplicate()
	_chain_lengths["thumb"] = _chain_lengths.get("index", 0.02)

	_tip_bones = {}
	if _hand_profile != null:
		for digit in ALL_DIGITS:
			var ch: Array = _hand_profile.bones[digit]
			_tip_bones[digit] = str(ch[2])
	else:
		_tip_bones = _fallback_tip_bones()
	var pads: Dictionary = Skinning.bind_pad_locals(character, skel, volar, _tip_bones)
	if not bool(pads.get("ok", false)):
		return {"ok": false, "reason": "pad_bind_failed", "pads": pads}
	_pad_locals = pads["pads"]
	# A2.5: the generic hand-volar-biased thumb marker sits on the SIDE of
	# the distal phalanx (the hand volar axis is nearly orthogonal to the
	# thumb's own pad/nail axis). Re-bind it onto the texture-verified pad
	# plate centroid so contact, approach and frames measure the true pulp.
	_pad_locals["thumb"] = _pad_marker_local()
	_thumb_cmc_sign = 0.0
	_contour_refs = {}
	_last_contour = {}
	_last_contour_gate = {}
	# A2.7: bind-sanity the compiled texture/topology-verified nail and pad
	# patches against the live mesh (indices, weights, UVs, rest normals,
	# winding). Fail closed — the ground-truth gate is meaningless without
	# verified patch identity.
	_patch_refs = {}
	_patch_bind_failure = ""
	_last_surface = {}
	_last_surface_gate = {}
	if not _bind_patches(character, skel):
		return {
			"ok": false,
			"reason": _patch_bind_failure,
			"error_class": "GRIP_PATCH_BIND_FAILED",
		}
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


func last_contour() -> Dictionary:
	return _last_contour.duplicate(true)


func last_contour_gate() -> Dictionary:
	return _last_contour_gate.duplicate(true)


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


func _live_hand_frame(skel: Skeleton3D) -> Dictionary:
	if _hand_profile != null and _hand_profile.has_method("compute_frame"):
		return _hand_profile.compute_frame(skel, false)
	return _fallback_live_frame(skel)


func _pad_world(skel: Skeleton3D, digit: String, pad_local: Vector3) -> Vector3:
	return Skinning.pad_world(skel, digit, pad_local, _tip_bones)


func _canon_thumb_anat() -> Dictionary:
	if not thumb_anat_override.is_empty():
		return thumb_anat_override
	if _hand_profile != null and "thumb_anat" in _hand_profile:
		var from_profile: Dictionary = _hand_profile.thumb_anat
		if not from_profile.is_empty():
			return from_profile
	return _fallback_thumb_anat()


func _bind_bones(skel: Skeleton3D) -> bool:
	_chain_indices.clear()
	_rest_rotations.clear()
	_left_probe_indices.clear()
	var chains: Dictionary = {}
	var owner_hand := ""
	var owner_fore := ""
	var owner_fore_alt := ""
	var opposite: Array = []
	if _hand_profile != null:
		for finger in ALL_DIGITS:
			chains[finger] = _hand_profile.bones[finger]
		owner_hand = str(_hand_profile.bones["hand"])
		owner_fore = str(_hand_profile.bones["forearm"])
		owner_fore_alt = str(_hand_profile.bones.get("forearm_alt", ""))
		opposite = [
			str(_hand_profile.bones["opposite_hand"]),
			str(_hand_profile.bones["opposite_index_mcp"]),
			str(_hand_profile.bones["opposite_thumb_cmc"]),
		]
	else:
		var spec: Dictionary = _fallback_bind_spec()
		if spec.is_empty():
			return false
		chains = spec.get("chains", {})
		owner_hand = str(spec.get("owner_hand", ""))
		owner_fore = str(spec.get("owner_forearm", ""))
		owner_fore_alt = str(spec.get("owner_forearm_alt", ""))
		opposite = spec.get("opposite_probes", [])
	_right_hand_idx = skel.find_bone(owner_hand)
	_right_forearm_idx = skel.find_bone(owner_fore_alt)
	if _right_forearm_idx < 0:
		_right_forearm_idx = skel.find_bone(owner_fore)
	for finger in ALL_DIGITS:
		var idxs: Array[int] = []
		for bname in chains[finger]:
			var i: int = skel.find_bone(str(bname))
			if i < 0:
				return false
			idxs.append(i)
			_rest_rotations[i] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_chain_indices[finger] = idxs
	for bname in opposite:
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
	var canon: Array = _canon_flex_deg()[finger]
	for ji in 3:
		var bone_i: int = int(chain[ji])
		var angle: float = deg_to_rad(float(canon[ji])) + delta * REFINE_WEIGHTS[ji]
		angle = maxf(angle, 0.0)
		var flex := Quaternion(Vector3.RIGHT, s * angle)
		skel.set_bone_pose_rotation(
			bone_i, (_rest_rotations[bone_i] as Quaternion) * flex
		)


## A2.3 anatomical thumb pose application. delta refines MCP/IP flexion
## (positive = more flexion about the VALIDATED anatomical axes, clamped to
## the R9 ranges so refinement can never hyperextend or over-flex);
## cmc_delta adds bounded extra CMC swing (sigma) so the whole chain can
## sink toward thinner shafts. Never free CCD.
func _set_thumb_pose(
	skel: Skeleton3D, delta: float, cmc_delta: float = 0.0
) -> void:
	if _thumb_frames.is_empty():
		return
	var anat: Dictionary = _canon_thumb_anat()
	var chain: Array = _chain_indices["thumb"]
	var fr0: Dictionary = _thumb_frames[0]
	var swing_axis: Vector3 = (
		(fr0["f_l"] as Vector3) * cos(deg_to_rad(float(anat["phi"])))
		+ (fr0["a_l"] as Vector3) * sin(deg_to_rad(float(anat["phi"])))
	).normalized()
	var sigma: float = deg_to_rad(float(anat["sigma"])) + cmc_delta
	var q0: Quaternion = (
		Quaternion(swing_axis, sigma)
		* Quaternion(fr0["t_l"], deg_to_rad(float(anat["tau"])))
	)
	skel.set_bone_pose_rotation(
		int(chain[0]), (_rest_rotations[int(chain[0])] as Quaternion) * q0
	)
	var flex_mcp: float = clampf(
		deg_to_rad(float(anat["flex_mcp"])) + delta * THUMB_REFINE_WEIGHTS[1],
		0.0,
		deg_to_rad(MCP_FLEX_MAX_DEG)
	)
	var fr1: Dictionary = _thumb_frames[1]
	skel.set_bone_pose_rotation(
		int(chain[1]),
		(_rest_rotations[int(chain[1])] as Quaternion)
		* Quaternion(fr1["f_l"], flex_mcp)
	)
	var flex_ip: float = clampf(
		deg_to_rad(float(anat["flex_ip"])) + delta * THUMB_REFINE_WEIGHTS[2],
		0.0,
		deg_to_rad(IP_FLEX_MAX_DEG)
	)
	var fr2: Dictionary = _thumb_frames[2]
	skel.set_bone_pose_rotation(
		int(chain[2]),
		(_rest_rotations[int(chain[2])] as Quaternion)
		* Quaternion(fr2["f_l"], flex_ip)
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
	var gap0: float = _signed_gap(_pad_world(skel, digit, pad_local))
	# One-time finite-difference probe of the CMC closing direction: IP
	# flexion alone orbits the pad and cannot reach thinner shafts.
	if digit == "thumb" and _thumb_cmc_sign == 0.0:
		_set_thumb_pose(skel, 0.0, 0.05)
		skel.force_update_all_bone_transforms()
		var g_plus: float = _signed_gap(_pad_world(skel, digit, pad_local))
		_set_thumb_pose(skel, 0.0, 0.0)
		skel.force_update_all_bone_transforms()
		_thumb_cmc_sign = -1.0 if g_plus > gap0 else 1.0
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
		_apply_digit_pose(skel, digit, delta)
		skel.force_update_all_bone_transforms()
		gap = _signed_gap(_pad_world(skel, digit, pad_local))
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
		_apply_digit_pose(skel, digit, best_delta)
		skel.force_update_all_bone_transforms()
		gap = _signed_gap(_pad_world(skel, digit, pad_local))
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


func _apply_digit_pose(skel: Skeleton3D, digit: String, delta: float) -> void:
	if digit == "thumb":
		_set_thumb_pose(skel, delta, _thumb_cmc_sign * delta * THUMB_REFINE_WEIGHTS[0])
	else:
		_set_finger_pose(skel, digit, delta)


func _axis_frame() -> Dictionary:
	if _club == null or not is_instance_valid(_club):
		return {}
	var parent: Node3D = _club.get_parent() as Node3D
	var xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	return {
		"o": xf.origin,
		"d": xf.basis.y.normalized(),
		"e1": xf.basis.x.normalized(),
		"e2": xf.basis.z.normalized(),
	}


func _point_angle_deg(p: Vector3, axis: Dictionary) -> float:
	var w: Vector3 = p - (axis["o"] as Vector3)
	var d: Vector3 = axis["d"]
	var rad: Vector3 = w - d * w.dot(d)
	return rad_to_deg(atan2(rad.dot(axis["e2"] as Vector3), rad.dot(axis["e1"] as Vector3)))


## Continuous signed angular sweep (deg) of a digit's polyline
## (joints + skinned pad) around the shaft axis. Positive = CCW in the
## right-handed section frame; only sign RELATIONS are gated, so the
## contract is rotation/scale/pose invariant and chirality-consistent.
func _sweep_digit(skel: Skeleton3D, digit: String, axis: Dictionary) -> float:
	var pts: Array[Vector3] = []
	for bi in _chain_indices[digit]:
		pts.append(skel.global_transform * skel.get_bone_global_pose(int(bi)).origin)
	pts.append(_pad_world(skel, digit, _pad_locals.get(digit, Vector3.ZERO) as Vector3))
	var sweep := 0.0
	for i in pts.size() - 1:
		sweep += rad_to_deg(angle_difference(
			deg_to_rad(_point_angle_deg(pts[i], axis)),
			deg_to_rad(_point_angle_deg(pts[i + 1], axis))
		))
	return sweep


## A2.3: derives and empirically validates the per-joint anatomical thumb
## frames at the rest pose, then verifies the compiled canonical pose winds
## opposite the fingers. Fail-closed on any ambiguity — no fallback pose
## (audit A2_2 root cause: MCP/IP have opposite local-X conventions, so
## imported axes are never trusted as anatomy).
func _derive_thumb_anatomy(skel: Skeleton3D) -> void:
	var axis: Dictionary = _axis_frame()
	if axis.is_empty():
		_thumb_axis_failure = "thumb_axis_no_shaft_frame"
		return
	# Chirality: all four fingers must wind the same way, strongly.
	var sweeps: Array[float] = []
	for finger in FINGERS:
		sweeps.append(_sweep_digit(skel, finger, axis))
	sweeps.sort()
	var wf: float = (sweeps[1] + sweeps[2]) * 0.5
	if absf(wf) < FINGER_WINDING_MIN_DEG or signf(sweeps[0]) != signf(sweeps[3]):
		_thumb_axis_failure = "finger_winding_ambiguous"
		return
	var chain: Array = _chain_indices["thumb"]
	# Rest frames: twist axis = rest segment direction; flesh side = the
	# COMPILED, texture-verified pad-plate normal (A2.5) projected
	# perpendicular to the segment. The old pad-marker perpendicular offset
	# pointed to the SIDE of the phalanx and rolled the frames ~95 deg,
	# which turned the nail toward the shaft.
	for bi in chain:
		skel.reset_bone_pose(int(bi))
	skel.force_update_all_bone_transforms()
	var pts := _thumb_points(skel)
	# Compiled distal surface normals in rest world + bind-time sanity.
	var t3_rest_basis: Basis = (
		skel.global_transform.basis * skel.get_bone_global_pose(int(chain[2])).basis
	)
	var pad_rest_w: Vector3 = (t3_rest_basis * _pad_normal_local()).normalized()
	# A2.7 sanity: the compiled plate relation must match the audited rest
	# relation (the true plates are near-perpendicular, NOT opposed — the
	# old "must be opposed" check was itself derived from the mislabeled
	# A2.5 patch), and the verified patches must have bound cleanly.
	if absf(_nail_normal_local().dot(_pad_normal_local()) - _rest_nail_pad_dot()) > 0.15:
		_thumb_axis_failure = "thumb_distal_frame_invalid"
		return
	if not _patch_bind_failure.is_empty():
		_thumb_axis_failure = _patch_bind_failure
		return
	_thumb_frames = []
	for ji in 3:
		var t_hat: Vector3 = (pts[ji + 1] - pts[ji]).normalized()
		var v_flesh: Vector3 = pad_rest_w - t_hat * pad_rest_w.dot(t_hat)
		if v_flesh.length_squared() < 1e-14:
			_thumb_frames = []
			_thumb_axis_failure = "thumb_flesh_side_degenerate"
			return
		v_flesh = v_flesh.normalized()
		var f_hat: Vector3 = t_hat.cross(v_flesh).normalized()
		var a_hat: Vector3 = t_hat.cross(f_hat)
		var bi: int = int(chain[ji])
		# Bone-local axes via the bone's CURRENT global pose basis (thumb at
		# rest, wrist wherever Walking put it) — this is the exact space the
		# applied rotations act in, so the compiled axes stay valid at every
		# Walking time (using the global REST basis here would bake in the
		# wrist's pose at derivation time and drift with the animation).
		var pose_world: Basis = (
			skel.global_transform.basis * skel.get_bone_global_pose(bi).basis
		)
		_thumb_frames.append({
			"t_w": t_hat, "f_w": f_hat, "a_w": a_hat, "flesh_w": v_flesh,
			"t_l": (pose_world.inverse() * t_hat).normalized(),
			"f_l": (pose_world.inverse() * f_hat).normalized(),
			"a_l": (pose_world.inverse() * a_hat).normalized(),
			# Bone-local flesh side, for pose-independent volar-vertex
			# classification (A2.6 contour patches).
			"flesh_l": (pose_world.inverse() * v_flesh).normalized(),
		})
	# Empirical validation: +15 deg about each constructed flexion axis
	# must bend the joint toward the flesh (MCP/IP) or move the pad
	# flesh-ward (CMC). A flipped axis is corrected and recorded; a weak
	# response fails closed.
	for ji in [1, 2]:
		var bend_plus: float = _rest_bend_after_flex(skel, ji, 15.0)
		var bend_minus: float = _rest_bend_after_flex(skel, ji, -15.0)
		if absf(bend_plus - bend_minus) < THUMB_AXIS_MIN_BEND_RESPONSE_DEG:
			_thumb_frames = []
			_thumb_axis_failure = "thumb_flexion_axis_underivable"
			return
		if bend_plus < bend_minus:
			_flip_thumb_frame(ji)
	for bi in chain:
		skel.reset_bone_pose(int(bi))
	skel.force_update_all_bone_transforms()
	var pad0: Vector3 = _thumb_points(skel)[3]
	var fr0: Dictionary = _thumb_frames[0]
	skel.set_bone_pose_rotation(
		int(chain[0]),
		(_rest_rotations[int(chain[0])] as Quaternion)
		* Quaternion(fr0["f_l"], deg_to_rad(15.0))
	)
	skel.force_update_all_bone_transforms()
	var dp: Vector3 = _thumb_points(skel)[3] - pad0
	if absf(dp.dot(fr0["flesh_w"])) < 1e-9:
		_thumb_frames = []
		_thumb_axis_failure = "thumb_flexion_axis_underivable"
		return
	if dp.dot(fr0["flesh_w"]) < 0.0:
		_flip_thumb_frame(0)
	for bi in chain:
		skel.reset_bone_pose(int(bi))
	skel.force_update_all_bone_transforms()
	# Verify: the compiled canonical pose must wind opposite the fingers
	# with margin — otherwise the profile is invalid for this rig.
	_set_thumb_pose(skel, 0.0)
	skel.force_update_all_bone_transforms()
	var w_canon: float = _sweep_digit(skel, "thumb", axis)
	if signf(w_canon) == signf(wf) or absf(w_canon) < THUMB_WINDING_MIN_DEG:
		_thumb_frames = []
		_thumb_axis_failure = "thumb_canonical_not_counter_winding"
		return


func _flip_thumb_frame(ji: int) -> void:
	var fr: Dictionary = _thumb_frames[ji]
	fr["f_l"] = -(fr["f_l"] as Vector3)
	fr["f_w"] = -(fr["f_w"] as Vector3)
	fr["a_l"] = -(fr["a_l"] as Vector3)
	fr["a_w"] = -(fr["a_w"] as Vector3)
	_thumb_frames[ji] = fr
	_thumb_axis_flipped[ji] = true


func _thumb_points(skel: Skeleton3D) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for bi in _chain_indices["thumb"]:
		pts.append(skel.global_transform * skel.get_bone_global_pose(int(bi)).origin)
	pts.append(_pad_world(skel, "thumb", _pad_locals.get("thumb", Vector3.ZERO) as Vector3))
	return pts


## Flesh-ward bend at joint ji after rotating only that joint by ang about
## its constructed flexion axis, from rest (C2 method from the audit).
func _rest_bend_after_flex(skel: Skeleton3D, ji: int, ang: float) -> float:
	var chain: Array = _chain_indices["thumb"]
	for bi in chain:
		skel.reset_bone_pose(int(bi))
	var fr: Dictionary = _thumb_frames[ji]
	_sk_set_rot(skel, int(chain[ji]), Quaternion(fr["f_l"], deg_to_rad(ang)))
	skel.force_update_all_bone_transforms()
	var pts := _thumb_points(skel)
	var s0: Vector3 = (pts[ji] - pts[ji - 1]).normalized()
	var s1: Vector3 = (pts[ji + 1] - pts[ji]).normalized()
	var u: Vector3 = pts[3] - pts[ji]
	var v_flesh: Vector3 = (u - s0 * u.dot(s0)).normalized()
	var f_ref: Vector3 = s0.cross(v_flesh).normalized()
	return rad_to_deg(atan2((s0.cross(s1)).dot(f_ref), s0.dot(s1)))


func _sk_set_rot(skel: Skeleton3D, bone_i: int, q_rel: Quaternion) -> void:
	skel.set_bone_pose_rotation(
		bone_i, (_rest_rotations[bone_i] as Quaternion) * q_rel
	)


func thumb_axis_failure() -> String:
	return _thumb_axis_failure


func thumb_frames_ready() -> bool:
	return not _thumb_frames.is_empty()


func thumb_axis_flipped() -> Array:
	return _thumb_axis_flipped.duplicate()


func _append_contact_angle(
	angs: Array[float],
	p: Vector3,
	tol: float,
	o: Vector3,
	d_axis: Vector3,
	e1: Vector3,
	e2: Vector3
) -> void:
	if _signed_gap(p) > tol:
		return
	var w: Vector3 = p - o
	var rad: Vector3 = w - d_axis * w.dot(d_axis)
	if rad.length_squared() <= 1e-14:
		return
	var rd: Vector3 = rad.normalized()
	angs.append(fposmod(rad_to_deg(atan2(rd.dot(e2), rd.dot(e1))), 360.0))


## Geometry of the achieved thumb chain vs the shaft, measured on the live
## skinned pose. All lengths also reported relative to the grip radius.
func _measure_thumb_wrap(
	skel: Skeleton3D,
	o: Vector3,
	d_axis: Vector3,
	e1: Vector3,
	e2: Vector3,
	finger_mean_radial: Vector3,
	r_mean: float,
	hframe: Dictionary = {}
) -> Dictionary:
	var chain_idx: Array = _chain_indices["thumb"]
	var pts: Array[Vector3] = []
	for ji in 3:
		pts.append(
			skel.global_transform * skel.get_bone_global_pose(int(chain_idx[ji])).origin
		)
	var pad: Vector3 = _pad_world(
		skel, "thumb", _pad_locals.get("thumb", Vector3.ZERO) as Vector3
	)
	pts.append(pad)

	var chain: Vector3 = pad - pts[0]
	var axial: float = chain.dot(d_axis)
	var transverse: float = (chain - d_axis * axial).length()
	var abs_dot: float = 0.0
	if chain.length_squared() > 1e-14:
		abs_dot = absf(chain.normalized().dot(d_axis))

	var w0: Vector3 = pts[0] - o
	var rad0: Vector3 = w0 - d_axis * w0.dot(d_axis)
	var wp: Vector3 = pad - o
	var radp: Vector3 = wp - d_axis * wp.dot(d_axis)
	var wrap_deg := 0.0
	if rad0.length_squared() > 1e-14 and radp.length_squared() > 1e-14:
		wrap_deg = rad_to_deg(angle_difference(
			atan2(rad0.dot(e2), rad0.dot(e1)),
			atan2(radp.dot(e2), radp.dot(e1))
		))

	# Through-shaft detection: minimum signed gap sampled along the chain
	# polyline (joints + pad).
	var chain_min_gap := INF
	for si in 3:
		for k in 5:
			var p: Vector3 = pts[si].lerp(pts[si + 1], float(k) / 4.0)
			chain_min_gap = minf(chain_min_gap, _signed_gap(p))

	var radial_dot := 0.0
	if radp.length_squared() > 1e-14 and finger_mean_radial.length_squared() > 1e-12:
		radial_dot = radp.normalized().dot(finger_mean_radial)

	# Through-palm detection: chain points must stay volar of the bone palm
	# plane (normalized by hand length; the CMC base naturally sits near it).
	var volar_clearance_hand := INF
	var frame: Dictionary = hframe
	if not bool(frame.get("ok", false)):
		frame = _live_hand_frame(skel)
	if bool(frame.get("ok", false)):
		var palm_c: Vector3 = frame["palm_centre"]
		var volar: Vector3 = frame["volar"]
		var hand_len: float = maxf(float(frame["hand_length"]), 1e-9)
		for p in pts:
			volar_clearance_hand = minf(
				volar_clearance_hand, (p - palm_c).dot(volar) / hand_len
			)

	# --- A2.2 R1/R2/R4 metrics: signed windings, meeting sector, approach ---
	var axis := {"o": o, "d": d_axis, "e1": e1, "e2": e2}
	var w_thumb: float = _sweep_digit(skel, "thumb", axis)
	var finger_sweeps := {}
	var sw_list: Array[float] = []
	for finger in FINGERS:
		var wsw: float = _sweep_digit(skel, finger, axis)
		finger_sweeps[finger] = wsw
		sw_list.append(wsw)
	sw_list.sort()
	var wf_median: float = (sw_list[1] + sw_list[2]) * 0.5
	var opposite: bool = (
		w_thumb != 0.0 and wf_median != 0.0 and signf(w_thumb) != signf(wf_median)
	)
	var sign_t: float = signf(w_thumb)
	# Meeting sector (R2): |circular distance| between the thumb pad angle
	# and the mean finger-pad direction. Only meaningful together with R1
	# (opposite winding fixes the approach orientation); the along-winding
	# arrival is reported as a diagnostic.
	var meeting := 999.0
	var arrival := 999.0
	var fmean_ang := 0.0
	var pad_ang := 0.0
	if radp.length_squared() > 1e-14 and finger_mean_radial.length_squared() > 1e-12:
		fmean_ang = rad_to_deg(atan2(
			finger_mean_radial.dot(e2), finger_mean_radial.dot(e1)
		))
		pad_ang = rad_to_deg(atan2(
			radp.normalized().dot(e2), radp.normalized().dot(e1)
		))
		meeting = absf(rad_to_deg(angle_difference(
			deg_to_rad(pad_ang), deg_to_rad(fmean_ang)
		)))
		arrival = fposmod(sign_t * (pad_ang - fmean_ang), 360.0)
	# Approach (R4): final segment IP joint -> pad, decomposed at the pad
	# into radial (positive = outward, away from the surface), tangential
	# along the thumb's own winding direction (tangent_ccw = r_hat x D,
	# scaled by sign(W_thumb)), and the axial fraction of the segment.
	var seg: Vector3 = pad - pts[2]
	var seg_len: float = maxf(seg.length(), 1e-9)
	var app_radial := 0.0
	var app_tan_w := 0.0
	if radp.length_squared() > 1e-14:
		var r_hat: Vector3 = radp.normalized()
		app_radial = seg.dot(r_hat)
		app_tan_w = seg.dot(r_hat.cross(d_axis) * sign_t)

	var out := {
		"axial_dot_abs": abs_dot,
		"axial_disp": axial,
		"transverse_disp": transverse,
		"transverse_over_axial": transverse / maxf(absf(axial), 1e-9),
		"wrap_deg": wrap_deg,
		"chain_min_gap": chain_min_gap,
		"chain_min_gap_radii": chain_min_gap / maxf(r_mean, 1e-9),
		"radial_dot_vs_fingers": radial_dot,
		"volar_clearance_hand": volar_clearance_hand,
		"winding_thumb_deg": w_thumb,
		"winding_finger_median_deg": wf_median,
		"winding_fingers_deg": finger_sweeps,
		"opposite_winding": opposite,
		"meeting_angle_deg": meeting,
		"arrival_along_winding_deg": arrival,
		"finger_pad_mean_angle_deg": fmean_ang,
		"thumb_pad_angle_deg": pad_ang,
		"approach_radial_radii": app_radial / maxf(r_mean, 1e-9),
		"approach_tangential_winding_radii": app_tan_w / maxf(r_mean, 1e-9),
		"approach_axial_fraction": absf(seg.dot(d_axis)) / seg_len,
	}
	# --- A2.3 anatomical metrics: swing-twist per joint vs the validated
	# rest frames, wrap-consistent segment bends, direction classification.
	if not _thumb_frames.is_empty():
		var t_chain_idx: Array = _chain_indices["thumb"]
		var joint_names := ["cmc", "mcp", "ip"]
		for ji in 3:
			var st := _joint_swing_twist(skel, int(t_chain_idx[ji]), _thumb_frames[ji])
			out["%s_flex_deg" % joint_names[ji]] = st["flex"]
			out["%s_abd_deg" % joint_names[ji]] = st["abd"]
			out["%s_twist_deg" % joint_names[ji]] = st["twist"]
		# R6: consecutive segment-pair rotations about the shaft axis must
		# follow the thumb's own winding direction (consistent forward
		# wrap, no dorsal S-kink) — measured in ONE common plane (the
		# section plane), per the audit's sharpened definition.
		var sgn_t: float = signf(w_thumb) if w_thumb != 0.0 else 1.0
		var bends: Array[float] = []
		for i in 2:
			var s0: Vector3 = (pts[i + 1] - pts[i]).normalized()
			var s1: Vector3 = (pts[i + 2] - pts[i + 1]).normalized()
			bends.append(sgn_t * rad_to_deg(atan2(
				(s0.cross(s1)).dot(d_axis), s0.dot(s1)
			)))
		out["wrap_bend_mcp_deg"] = bends[0]
		out["wrap_bend_ip_deg"] = bends[1]
		# R7: direction classification from the along-station of the pad,
		# normalized between the LIVE ring (0) and index (1) pad stations.
		var st_ring: float = INF
		var st_index: float = INF
		var st_middle: float = INF
		var st_pinky: float = INF
		var finger_pads := {}
		for finger in FINGERS:
			var fpad: Vector3 = _pad_world(
				skel, finger, _pad_locals.get(finger, Vector3.ZERO) as Vector3
			)
			finger_pads[finger] = fpad
			var st_along: float = (fpad - o).dot(d_axis)
			match finger:
				"ring": st_ring = st_along
				"index": st_index = st_along
				"middle": st_middle = st_along
				"pinky": st_pinky = st_along
		var pad_along: float = (pad - o).dot(d_axis)
		var along_n: float = (pad_along - st_ring) / maxf(st_index - st_ring, 1e-9)
		# Direction is judged on the WHOLE chain (base -> pad): a fully
		# flexed distal phalanx naturally points back proximally in a real
		# bar grip, so the distal segment alone must never classify the
		# thumb as wrist-directed (it stays available as a diagnostic).
		var chain_dir: Vector3 = (pad - pts[0]).normalized()
		var distal_dir: Vector3 = (pad - pts[2]).normalized()
		var cls := "AMBIGUOUS"
		if bool(frame.get("ok", false)):
			var longi: Vector3 = frame["longitudinal"]
			var across_h: Vector3 = frame["across"]
			if chain_dir.dot(longi) < TOWARD_WRIST_LONG_DOT:
				cls = "TOWARD_WRIST"
			elif along_n >= DIR_INDEX_MIN:
				cls = "TOWARD_INDEX"
			elif along_n >= DIR_INDEX_MIDDLE_MIN:
				cls = "INDEX_MIDDLE"
			elif along_n >= 0.0:
				cls = "TOWARD_RING"
			else:
				cls = "TOWARD_PINKY"
			out["chain_across_dot"] = chain_dir.dot(across_h)
			out["chain_long_dot"] = chain_dir.dot(longi)
			out["distal_across_dot"] = distal_dir.dot(across_h)
			out["distal_long_dot"] = distal_dir.dot(longi)
		out["direction_class"] = cls
		# A2.5 distal surface orientation from the COMPILED nail/pad plate
		# normals transformed by the achieved Thumb3 pose: the nail must
		# face radially outward (not along the shaft), the pad must face
		# the shaft, and the distal roll about the phalanx axis is bounded.
		var t3b: Basis = (
			skel.global_transform.basis
			* skel.get_bone_global_pose(int(t_chain_idx[2])).basis
		)
		var nail_w2: Vector3 = (t3b * _nail_normal_local()).normalized()
		var pad_w2: Vector3 = (t3b * _pad_normal_local()).normalized()
		var tipc: Vector3 = (pts[2] + pad) * 0.5
		var wt2: Vector3 = tipc - o
		var rad2: Vector3 = wt2 - d_axis * wt2.dot(d_axis)
		if rad2.length_squared() > 1e-14:
			var r_hat2: Vector3 = rad2.normalized()
			out["nail_out_dot"] = nail_w2.dot(r_hat2)
			out["nail_axis_dot"] = absf(nail_w2.dot(d_axis))
			out["pad_in_dot"] = pad_w2.dot(-r_hat2)
			out["nail_pad_dot"] = nail_w2.dot(pad_w2)
			out["rest_nail_pad_dot"] = _rest_nail_pad_dot()
			var t_dist: Vector3 = (pad - pts[2]).normalized()
			var a_ref: Vector3 = (-r_hat2 - t_dist * (-r_hat2).dot(t_dist)).normalized()
			var b_v: Vector3 = (pad_w2 - t_dist * pad_w2.dot(t_dist)).normalized()
			out["distal_roll_deg"] = rad_to_deg(atan2(
				(a_ref.cross(b_v)).dot(t_dist), a_ref.dot(b_v)
			))
		out["pad_along_r"] = pad_along / maxf(r_mean, 1e-9)
		out["pad_along_n"] = along_n
		out["station_index_r"] = st_index / maxf(r_mean, 1e-9)
		out["station_pinky_r"] = st_pinky / maxf(r_mean, 1e-9)
		out["grip_zone_ok"] = (
			pad_along <= st_index + GRIP_ZONE_DISTAL_MARGIN_R * r_mean
			and pad_along >= st_pinky - GRIP_ZONE_PROXIMAL_MARGIN_R * r_mean
		)
		# Diagnostics only (NO finger-contact requirement): bone-level
		# distances from the thumb pad to each finger pad.
		var fdists := {}
		for finger in FINGERS:
			fdists[finger] = pad.distance_to(finger_pads[finger]) / maxf(r_mean, 1e-9)
		out["thumb_to_finger_pads_r"] = fdists
	if not _thumb_axis_failure.is_empty():
		out["sign_failure"] = _thumb_axis_failure
	return out


## Swing-twist of the joint's pose rotation (relative to rest) against its
## validated anatomical rest frame: twist about the segment axis, swing
## split into flexion (about f, positive = toward flesh) and abduction.
func _joint_swing_twist(skel: Skeleton3D, bone_i: int, fr: Dictionary) -> Dictionary:
	var q_rel: Quaternion = (
		(_rest_rotations[bone_i] as Quaternion).inverse()
		* skel.get_bone_pose_rotation(bone_i)
	).normalized()
	var t_l: Vector3 = fr["t_l"]
	var f_l: Vector3 = fr["f_l"]
	var a_l: Vector3 = fr["a_l"]
	var qv := Vector3(q_rel.x, q_rel.y, q_rel.z)
	var proj: Vector3 = t_l * qv.dot(t_l)
	var q_twist := Quaternion(proj.x, proj.y, proj.z, q_rel.w).normalized()
	var q_swing: Quaternion = (q_rel * q_twist.inverse()).normalized()
	var twist_deg: float = rad_to_deg(2.0 * atan2(proj.dot(t_l), q_twist.w))
	var swing_angle: float = q_swing.get_angle()
	var swing_axis: Vector3 = q_swing.get_axis() if swing_angle > 1e-6 else Vector3.ZERO
	return {
		"twist": twist_deg,
		"flex": rad_to_deg(swing_angle * swing_axis.dot(f_l)),
		"abd": rad_to_deg(swing_angle * swing_axis.dot(a_l)),
	}


## Re-measures thumb geometry from the CURRENT skeleton pose (no re-solve);
## used by tests to gate externally authored/broken thumb poses.
func measure_thumb_now() -> Dictionary:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return {}
	skel.force_update_all_bone_transforms()
	var parent: Node3D = _club.get_parent() as Node3D
	var axis_xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var o: Vector3 = axis_xf.origin
	var d_axis: Vector3 = axis_xf.basis.y.normalized()
	var e1: Vector3 = axis_xf.basis.x.normalized()
	var e2: Vector3 = axis_xf.basis.z.normalized()
	var r_mean: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-6)
	var finger_mean := Vector3.ZERO
	for finger in FINGERS:
		var pad: Vector3 = _pad_world(
			skel, finger, _pad_locals.get(finger, Vector3.ZERO) as Vector3
		)
		var w: Vector3 = pad - o
		var radial: Vector3 = w - d_axis * w.dot(d_axis)
		if radial.length_squared() > 1e-14:
			finger_mean += radial.normalized()
	if finger_mean.length_squared() > 1e-12:
		finger_mean = finger_mean.normalized()
	var metrics: Dictionary = _measure_thumb_wrap(
		skel, o, d_axis, e1, e2, finger_mean, r_mean
	)
	var thumb_pad: Vector3 = _pad_world(
		skel, "thumb", _pad_locals.get("thumb", Vector3.ZERO) as Vector3
	)
	metrics["gap_final_signed"] = _signed_gap(thumb_pad)
	return metrics


## A2.2 fail-closed thumb OPPOSITION gate (audit Section 8, R1-R4).
## R1 counter-winding, R2 meeting sector, R3 contact, R4 approach.
## DEGRADED TO DIAGNOSTICS (reported but never gated): the diametric
## radial_dot_vs_fingers, the scalar opposition_dot, the unsigned wrap_deg
## magnitude, and encirclement coverage — the audit showed all four are
## winding-blind and the first two actively reject the correct pose.
static func evaluate_thumb_wrap(metrics: Dictionary, r_mean: float) -> Dictionary:
	var failures: Array[String] = []
	if metrics.is_empty():
		return {"pass": false, "failures": ["thumb_metrics_missing"]}
	var sign_failure: String = str(metrics.get("sign_failure", ""))
	if not sign_failure.is_empty():
		return {"pass": false, "failures": [sign_failure]}
	var r: float = maxf(r_mean, 1e-9)

	# R1: counter-winding relation (sign relation: chirality/rotation/scale
	# invariant).
	var wt: float = float(metrics.get("winding_thumb_deg", 0.0))
	var wf: float = float(metrics.get("winding_finger_median_deg", 0.0))
	if absf(wf) < FINGER_WINDING_MIN_DEG:
		failures.append("finger_winding_ambiguous")
	for f in metrics.get("winding_fingers_deg", {}).values():
		if absf(float(f)) < FINGER_WINDING_MIN_DEG:
			failures.append("finger_winding_too_small")
			break
	if wt == 0.0 or signf(wt) == signf(wf):
		failures.append("same_winding_as_fingers")
	if absf(wt) < THUMB_WINDING_MIN_DEG:
		failures.append("thumb_winding_too_small")

	# R7 (replaces the disproven aggregate-sector R2, which was blind to the
	# along-axis and approved pinky-directed poses): the thumb must be
	# directed toward the index / index-middle side, within the hand's grip
	# zone. The index reference is DIRECTIONAL only — no physical
	# thumb-to-finger contact is required (a correct power grip may hold
	# the shaft with the thumb while the fingers counter from the other
	# side). meeting_angle_deg stays as a diagnostic.
	var cls: String = str(metrics.get("direction_class", "AMBIGUOUS"))
	match cls:
		"TOWARD_INDEX", "INDEX_MIDDLE":
			pass
		"TOWARD_RING":
			failures.append("thumb_direction_toward_ring")
		"TOWARD_PINKY":
			failures.append("thumb_direction_toward_pinky")
		"TOWARD_WRIST":
			failures.append("thumb_direction_toward_wrist")
		_:
			failures.append("thumb_direction_ambiguous")
	if not bool(metrics.get("grip_zone_ok", false)):
		failures.append("thumb_outside_grip_zone")

	# R5: anatomical per-joint flexion (measured swing-twist against the
	# validated frames) — no hyperextension beyond tolerance, no over-flex.
	var mcp_flex: float = float(metrics.get("mcp_flex_deg", 0.0))
	var ip_flex: float = float(metrics.get("ip_flex_deg", 0.0))
	if mcp_flex < THUMB_BEND_HYPEREXT_TOL_DEG:
		failures.append("thumb_mcp_hyperextension")
	if mcp_flex > MCP_FLEX_MAX_DEG + 5.0:
		failures.append("thumb_mcp_flexion_excess")
	if ip_flex < THUMB_BEND_HYPEREXT_TOL_DEG:
		failures.append("thumb_ip_hyperextension")
	if ip_flex > IP_FLEX_MAX_DEG + 5.0:
		failures.append("thumb_ip_flexion_excess")

	# R6: consistent chain curvature — an S-chain is one joint clearly
	# flexing forward while the other bends backward, measured in the
	# ANATOMICAL flexion values (the shaft-plane projection turned out to
	# be the wrong plane for a chain that crosses the shaft obliquely; the
	# section-plane bends stay available as diagnostics only).
	if (
		(mcp_flex > 15.0 and ip_flex < -5.0)
		or (mcp_flex < -5.0 and ip_flex > 15.0)
	):
		failures.append("thumb_s_curve")

	# R8: joint roles — MCP/IP may not compensate via lateral swing.
	if absf(float(metrics.get("mcp_abd_deg", 0.0))) > MCP_IP_LATERAL_MAX_DEG:
		failures.append("thumb_mcp_lateral_swing")
	if absf(float(metrics.get("ip_abd_deg", 0.0))) > MCP_IP_LATERAL_MAX_DEG:
		failures.append("thumb_ip_lateral_swing")

	# R9: rig-relative anatomical joint limits (the A2.2 pose's CMC twist
	# +86.8 deg must fail here; limits are never widened to admit it).
	if absf(float(metrics.get("cmc_twist_deg", 0.0))) > CMC_TWIST_MAX_DEG:
		failures.append("thumb_cmc_twist_excess")
	if absf(float(metrics.get("mcp_twist_deg", 0.0))) > MCP_IP_TWIST_MAX_DEG:
		failures.append("thumb_mcp_twist_excess")
	if absf(float(metrics.get("ip_twist_deg", 0.0))) > MCP_IP_TWIST_MAX_DEG:
		failures.append("thumb_ip_twist_excess")

	# R3: real contact, no through-shaft/palm passage, no backward bend,
	# no axial lying (thresholds unchanged from A2.1).
	if float(metrics.get("axial_dot_abs", 1.0)) > THUMB_AXIAL_DOT_MAX:
		failures.append("thumb_chain_parallel_to_shaft")
	if float(metrics.get("transverse_over_axial", 0.0)) < THUMB_TRANSVERSE_RATIO_MIN:
		failures.append("thumb_axial_travel_dominates")
	var gap_signed: float = float(metrics.get("gap_final_signed", INF))
	if maxf(gap_signed, 0.0) > THUMB_GAP_MAX_RADII * r:
		failures.append("thumb_pad_not_on_surface")
	if maxf(-gap_signed, 0.0) > THUMB_PEN_MAX_RADII * r:
		failures.append("thumb_pad_penetrates_shaft")
	if float(metrics.get("chain_min_gap_radii", -INF)) < THUMB_CHAIN_MIN_GAP_RADII:
		failures.append("thumb_chain_through_shaft")
	if float(metrics.get("volar_clearance_hand", -INF)) < THUMB_VOLAR_CLEARANCE_MIN_HAND:
		failures.append("thumb_chain_through_palm")
	if metrics.has("flex_deg"):
		for fx in metrics["flex_deg"]:
			if float(fx) < -1e-3:
				failures.append("thumb_ip_backward_bend")

	# R4: the final segment must close toward the contact, not drift
	# axially along the shaft or move radially away from the surface.
	if float(metrics.get("approach_axial_fraction", 1.0)) > THUMB_APPROACH_AXIAL_FRAC_MAX:
		failures.append("thumb_approach_axial")
	if float(metrics.get("approach_radial_radii", 99.0)) > THUMB_APPROACH_RADIAL_MAX_RADII:
		failures.append("thumb_approach_radially_outward")

	# R10 (A2.5): distal surface orientation against the compiled,
	# texture-verified nail/pad plate normals. The nail must face radially
	# outward (never along the shaft, never inward), the pad must be the
	# contact side, the plates stay opposed, and the distal roll about the
	# phalanx axis is bounded. Coordinate-invariant — no camera involved.
	if metrics.has("nail_out_dot"):
		if float(metrics.get("nail_out_dot", -9.0)) < NAIL_OUT_MIN:
			failures.append("thumb_nail_faces_inward")
		if float(metrics.get("nail_axis_dot", 9.0)) > NAIL_AXIAL_MAX:
			failures.append("thumb_nail_axial_to_shaft")
		if float(metrics.get("pad_in_dot", -9.0)) < PAD_IN_MIN:
			failures.append("thumb_pad_faces_outward")
		if (
			absf(float(metrics.get("nail_pad_dot", 9.0)) - float(metrics.get("rest_nail_pad_dot", 0.0)))
			> 0.15
		):
			failures.append("thumb_surface_orientation_inconsistent")
		if absf(float(metrics.get("distal_roll_deg", 999.0))) > DISTAL_ROLL_MAX_DEG:
			failures.append("thumb_distal_roll_excess")
	return {"pass": failures.is_empty(), "failures": failures}


## A2.4 DIAGNOSTIC (not an acceptance gate): skinned thumb-tip isolation in
## the projection along the shaft axis. For each high-weight Thumb3 tip
## vertex, the excess of its radial extent over the outer envelope of all
## OTHER thumb flesh within +/-20 deg of its angle (bare shaft surface = 1r
## when no flesh is nearby). A smooth tapering thumb measures near 0; an
## isolated tip lobe sticks out above its angular neighbourhood. Kept
## diagnostic because the defect has a documented low-poly skinning
## component with no sharp pose-side separation — the A2 test asserts the
## RELATIVE regression (A2.4 pose measures lower than the A2.3 pose).
func measure_tip_isolation(character: Node) -> Dictionary:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return {}
	if not _chain_indices.has("thumb"):
		return {}
	var mi: MeshInstance3D = Skinning.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		return {}
	skel.force_update_all_bone_transforms()
	var parent: Node3D = _club.get_parent() as Node3D
	var xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var o: Vector3 = xf.origin
	var d: Vector3 = xf.basis.y.normalized()
	var e1: Vector3 = xf.basis.x.normalized()
	var e2: Vector3 = xf.basis.z.normalized()
	var r: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-9)
	var bind_to_skel: PackedInt32Array = Skinning.bind_to_skeleton_map(mi, skel)
	var thumb_bones := {}
	for bi_v in _chain_indices["thumb"]:
		thumb_bones[int(bi_v)] = skel.get_bone_name(int(bi_v))
	var tip_bone: int = int((_chain_indices["thumb"] as Array)[2])
	var tips: Array = []
	var others: Array = []
	var max_tip_gap := -INF
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var bpv: int = Skinning.bones_per_vertex(bones, verts.size())
		for vi in verts.size():
			var best_w := 0.0
			var best_bone := -1
			for k in bpv:
				var wgt: float = float(weights[vi * bpv + k])
				if wgt > best_w:
					best_w = wgt
					best_bone = bind_to_skel[bones[vi * bpv + k]]
			if best_w <= 0.4 or not thumb_bones.has(best_bone):
				continue
			var p: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, si, vi, bpv, bind_to_skel
			)
			var w: Vector3 = p - o
			var rad: Vector3 = w - d * w.dot(d)
			var ang: float = rad_to_deg(atan2(rad.dot(e2), rad.dot(e1)))
			var radial_r: float = rad.length() / r
			if best_bone == tip_bone and best_w >= 0.9:
				tips.append([ang, radial_r])
				max_tip_gap = maxf(max_tip_gap, _signed_gap(p) / r)
			else:
				others.append([ang, radial_r])
	var worst := 0.0
	for tip in tips:
		var envelope := 1.0
		for ov in others:
			if absf(rad_to_deg(angle_difference(
				deg_to_rad(float((tip as Array)[0])), deg_to_rad(float((ov as Array)[0]))
			))) <= 20.0:
				envelope = maxf(envelope, float((ov as Array)[1]))
		worst = maxf(worst, float((tip as Array)[1]) - envelope)
	return {
		"isolation_excess_r": worst,
		"max_tip_gap_r": max_tip_gap,
		"tip_vert_count": tips.size(),
	}


## A2.6: classify the skinned VOLAR vertices of each thumb phalanx once.
## Membership is bone-rigid (a dominant-weight vertex never changes side
## relative to its own bone), so classification runs with the thumb reset
## to rest — against each joint's bone-local flesh direction rotated into
## the current pose — and the cached refs stay valid at every Walking time.
func _collect_contour_refs(
	mi: MeshInstance3D, skel: Skeleton3D, bind_to_skel: PackedInt32Array
) -> void:
	_contour_refs = {0: [], 1: [], 2: []}
	var chain: Array = _chain_indices["thumb"]
	var bone_to_ji := {}
	for ji in 3:
		bone_to_ji[int(chain[ji])] = ji
	var saved: Array = []
	for bi in chain:
		saved.append(skel.get_bone_pose_rotation(int(bi)))
		skel.reset_bone_pose(int(bi))
	skel.force_update_all_bone_transforms()
	var joints: Array[Vector3] = _thumb_points(skel)
	var flesh_now: Array[Vector3] = []
	for ji in 3:
		var pose_world: Basis = (
			skel.global_transform.basis
			* skel.get_bone_global_pose(int(chain[ji])).basis
		)
		flesh_now.append(
			(pose_world * ((_thumb_frames[ji] as Dictionary)["flesh_l"] as Vector3))
			.normalized()
		)
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var bpv: int = Skinning.bones_per_vertex(bones, verts.size())
		for vi in verts.size():
			var best_w := 0.0
			var best_bone := -1
			for k in bpv:
				var wgt: float = float(weights[vi * bpv + k])
				if wgt > best_w:
					best_w = wgt
					best_bone = bind_to_skel[bones[vi * bpv + k]]
			if best_w <= 0.25 or not bone_to_ji.has(best_bone):
				continue
			var ji: int = bone_to_ji[best_bone]
			var p: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, si, vi, bpv, bind_to_skel
			)
			var seg: Vector3 = (joints[ji + 1] - joints[ji]).normalized()
			var u: Vector3 = p - joints[ji]
			var perp: Vector3 = u - seg * u.dot(seg)
			if perp.length_squared() < 1e-14:
				continue
			if perp.normalized().dot(flesh_now[ji]) >= 0.0:
				(_contour_refs[ji] as Array).append([si, vi, bpv])
	for i in chain.size():
		skel.set_bone_pose_rotation(int(chain[i]), saved[i])
	skel.force_update_all_bone_transforms()


## A2.6 skinned thumb contour vs the live shaft surface (coordinate
## invariant: everything is measured in the shaft frame, in grip radii).
## One-shot mesh scan — call after equip/apply, never per frame.
func measure_thumb_contour(character: Node) -> Dictionary:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return {}
	if _thumb_frames.is_empty():
		return {}
	var mi: MeshInstance3D = Skinning.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		return {}
	skel.force_update_all_bone_transforms()
	var skin: Skin = mi.skin
	var bind_to_skel := PackedInt32Array()
	bind_to_skel.resize(skin.get_bind_count())
	for bi in skin.get_bind_count():
		var bone_i: int = skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skel.find_bone(String(skin.get_bind_name(bi)))
		bind_to_skel[bi] = bone_i
	if _contour_refs.is_empty():
		_collect_contour_refs(mi, skel, bind_to_skel)
	var parent: Node3D = _club.get_parent() as Node3D
	var xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var o: Vector3 = xf.origin
	var d: Vector3 = xf.basis.y.normalized()
	var e1: Vector3 = xf.basis.x.normalized()
	var e2: Vector3 = xf.basis.z.normalized()
	var r: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-9)

	var names := ["cmc", "t2", "t3"]
	var patches := {}
	for ji in 3:
		var gaps: Array[float] = []
		var sx := 0.0
		var sy := 0.0
		var min_gap := INF
		var min_p := Vector3.ZERO
		var centroid := Vector3.ZERO
		for ref in _contour_refs[ji]:
			var p: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, int((ref as Array)[0]), int((ref as Array)[1]),
				int((ref as Array)[2]), bind_to_skel
			)
			var g: float = _signed_gap(p) / r
			gaps.append(g)
			centroid += p
			var w: Vector3 = p - o
			var rad: Vector3 = w - d * w.dot(d)
			if rad.length_squared() > 1e-14:
				var ang: float = atan2(rad.dot(e2), rad.dot(e1))
				sx += cos(ang)
				sy += sin(ang)
			if g < min_gap:
				min_gap = g
				min_p = p
		gaps.sort()
		patches[names[ji]] = {
			"n": gaps.size(),
			"min_r": min_gap if gaps.size() > 0 else INF,
			"med_r": gaps[gaps.size() / 2] if gaps.size() > 0 else INF,
			"ang_deg": rad_to_deg(atan2(sy, sx)),
			"min_p": min_p,
			"centroid": centroid / maxf(float(gaps.size()), 1.0),
		}
	var pad_p: Vector3 = _pad_world(
		skel, "thumb", _pad_locals.get("thumb", Vector3.ZERO) as Vector3
	)
	var pad_gap: float = _signed_gap(pad_p) / r
	var wpad: Vector3 = pad_p - o
	var rad_pad: Vector3 = wpad - d * wpad.dot(d)
	var pad_ang: float = rad_to_deg(atan2(rad_pad.dot(e2), rad_pad.dot(e1)))

	# Contact corridor between the achieved neighbour contacts; the middle
	# patch may sit a natural crease above it, never an isolated gap.
	var cmc: Dictionary = patches["cmc"]
	var t2: Dictionary = patches["t2"]
	var t3: Dictionary = patches["t3"]
	var corridor: float = maxf(
		(maxf(float(cmc["min_r"]), 0.0) + maxf(pad_gap, 0.0)) * 0.5, 0.0
	)
	var mid_excess: float = float(t2["med_r"]) - corridor
	var bulge: float = (
		float(t2["med_r"]) - (float(cmc["med_r"]) + float(t3["med_r"])) * 0.5
	)

	# Angular progression CMC -> T2 -> T3 -> pad around the shaft, signed
	# with the achieved thumb winding sense.
	var wind_sign: float = signf(float(
		_last_diagnostics.get("thumb_wrap", {}).get("winding_thumb_deg", 1.0)
	))
	if wind_sign == 0.0:
		wind_sign = 1.0
	var stations: Array[float] = [
		float(cmc["ang_deg"]), float(t2["ang_deg"]), float(t3["ang_deg"]), pad_ang,
	]
	var steps: Array[float] = []
	var max_jump := 0.0
	var monotonic := true
	for i in stations.size() - 1:
		var step: float = rad_to_deg(angle_difference(
			deg_to_rad(stations[i]), deg_to_rad(stations[i + 1])
		))
		steps.append(step)
		max_jump = maxf(max_jump, absf(step))
		if step * wind_sign < -CONTOUR_BACKTRACK_TOL_DEG:
			monotonic = false

	# Outward curvature kink: signed radial offset of the T2 centroid above
	# the chord between the CMC and T3 centroids (positive = bulging away
	# from the shaft axis), in grip radii.
	var radial_extent := func(p: Vector3) -> float:
		var w2: Vector3 = p - o
		return (w2 - d * w2.dot(d)).length() / r
	var kink_out: float = (
		float(radial_extent.call(t2["centroid"]))
		- (
			float(radial_extent.call(cmc["centroid"]))
			+ float(radial_extent.call(t3["centroid"]))
		) * 0.5
	)

	# The T2 volar flesh must face the shaft, not radially away from it.
	var chain: Array = _chain_indices["thumb"]
	var seg_mid: Vector3 = (
		skel.global_transform * skel.get_bone_global_pose(int(chain[1])).origin
		+ skel.global_transform * skel.get_bone_global_pose(int(chain[2])).origin
	) * 0.5
	var wm: Vector3 = seg_mid - o
	var toward_axis: Vector3 = -(wm - d * wm.dot(d))
	var t2_face_dot := 0.0
	if toward_axis.length_squared() > 1e-14:
		t2_face_dot = (
			((t2["centroid"] as Vector3) - seg_mid).normalized()
			.dot(toward_axis.normalized())
		)

	var out := {
		"ok": true,
		"pad_gap_r": pad_gap,
		"pad_ang_deg": pad_ang,
		"patches": patches,
		"corridor_r": corridor,
		"mid_excess_r": mid_excess,
		"bulge_r": bulge,
		"kink_out_r": kink_out,
		"steps_deg": steps,
		"max_jump_deg": max_jump,
		"monotonic_ok": monotonic,
		"winding_sign": wind_sign,
		"t2_face_dot": t2_face_dot,
	}
	return out


## A2.6 fail-closed distributed-contour gate. Pure function of the contour
## metrics so tests can also feed analytic defect cases. Does NOT replace
## the distal-pad gates (R3) — it adds the distributed-contact contract.
static func evaluate_thumb_contour(contour: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if contour.is_empty() or not bool(contour.get("ok", false)):
		return {"pass": false, "failures": ["thumb_contour_metrics_missing"]}
	var patches: Dictionary = contour.get("patches", {})
	var min_all := INF
	for key in ["cmc", "t2", "t3"]:
		var patch: Dictionary = patches.get(key, {})
		if int(patch.get("n", 0)) < CONTOUR_MIN_PATCH_VERTS:
			failures.append("thumb_contour_patch_missing")
			return {"pass": false, "failures": failures}
		min_all = minf(min_all, float(patch.get("min_r", INF)))
	# 3) at least one further achieved volar contact / near-contact beyond
	# the distal pad.
	if min_all > CONTOUR_NEAR_CONTACT_MAX_R:
		failures.append("thumb_contact_only_at_distal_pad")
	# 4) no isolated middle gap above the contact corridor.
	if float(contour.get("mid_excess_r", 99.0)) > CONTOUR_MID_EXCESS_MAX_R:
		failures.append("thumb_middle_surface_gap_excess")
	# The middle surface may not stand radially proud of both neighbours,
	# nor exceed the absolute rig-relative middle-median band.
	if (
		float(contour.get("bulge_r", 99.0)) > CONTOUR_BULGE_MAX_R
		or float((patches.get("t2", {}) as Dictionary).get("med_r", 99.0))
			> CONTOUR_MID_MED_MAX_R
	):
		failures.append("thumb_middle_radial_bulge")
	# No mid-chain penetration beyond skin-compression tolerance.
	if (
		float((patches.get("t2", {}) as Dictionary).get("min_r", 0.0))
			< CONTOUR_MID_PEN_MIN_R
		or float((patches.get("cmc", {}) as Dictionary).get("min_r", 0.0))
			< CONTOUR_MID_PEN_MIN_R
	):
		failures.append("thumb_middle_penetration_excess")
	# 6) smooth curve: no local outward kink at the middle.
	if float(contour.get("kink_out_r", 99.0)) > CONTOUR_KINK_OUT_MAX_R:
		failures.append("thumb_curvature_kink_outward")
	# 5) monotone, correctly signed wrap progression.
	if float(contour.get("max_jump_deg", 999.0)) > CONTOUR_JUMP_MAX_DEG:
		failures.append("thumb_contact_contour_discontinuous")
	if not bool(contour.get("monotonic_ok", false)):
		failures.append("thumb_surface_winding_nonmonotonic")
	# The middle volar flesh may cross tangentially but not face fully out.
	if float(contour.get("t2_face_dot", -9.0)) < CONTOUR_T2_FACE_MIN:
		failures.append("thumb_middle_pad_faces_outward")
	return {"pass": failures.is_empty(), "failures": failures}


## Nearest point on the shaft's elliptical grip surface (for debug draw).
func shaft_surface_point(world_p: Vector3) -> Vector3:
	if _club == null or not is_instance_valid(_club):
		return world_p
	var parent: Node3D = _club.get_parent() as Node3D
	var xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var local: Vector3 = xf.affine_inverse() * world_p
	var rx: float = maxf(float(_shape.get("radius_x", 0.01)), 1e-9)
	var rz: float = maxf(float(_shape.get("radius_z", 0.01)), 1e-9)
	var ang: float = atan2(local.z / rz, local.x / rx)
	return xf * Vector3(rx * cos(ang), local.y, rz * sin(ang))


## Measure + gate + store, one call for attach/preview/tests.
func run_contour_gate(character: Node) -> Dictionary:
	_last_contour = measure_thumb_contour(character)
	_last_contour_gate = evaluate_thumb_contour(_last_contour)
	return _last_contour_gate.duplicate(true)


# ---------------------------------------------------------------------------
# A2.7 ground-truth nail/pad surface measurement (audit
# A2_6_NAIL_SURFACE_GROUND_TRUTH_AUDIT.md §12). The acceptance ground truth
# is the DEFORMED skinned geometry of the verified patch triangles at the
# achieved final pose — never a compiled normal, never an auto-flipped cross
# product, never a single shared radial.
# ---------------------------------------------------------------------------

var _patch_mi: MeshInstance3D = null
var _patch_bind_map := PackedInt32Array()


## Bind-sanity for the compiled patches. Thumb joints are temporarily reset
## so the rest-normal comparison is pose-independent (patch vertices are
## Thumb2/Thumb3-dominated; the wrist moves them rigidly with the hand).
func _bind_patches(character: Node, skel: Skeleton3D) -> bool:
	var mi: MeshInstance3D = Skinning.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		_patch_bind_failure = "thumb_true_nail_patch_missing"
		return false
	_patch_mi = mi
	_patch_bind_map = PackedInt32Array()
	_patch_bind_map.resize(mi.skin.get_bind_count())
	for bi in mi.skin.get_bind_count():
		var bone_i: int = mi.skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skel.find_bone(String(mi.skin.get_bind_name(bi)))
		_patch_bind_map[bi] = bone_i
	var chain: Array = _chain_indices["thumb"]
	var t2: int = int(chain[1])
	var t3: int = int(chain[2])
	# Rest-pose comparison space: thumb joints at rest.
	var saved: Array = []
	for bi in chain:
		saved.append(skel.get_bone_pose_rotation(int(bi)))
		skel.reset_bone_pose(int(bi))
	skel.force_update_all_bone_transforms()
	var t3_world_inv: Basis = (
		skel.global_transform.basis * skel.get_bone_global_pose(t3).basis
	).inverse()
	var ok := true
	var out_refs := {}
	for pair in [["nail", _nail_tris()], ["pad", _pad_tris()]]:
		var patch: String = pair[0]
		var refs: Array = []
		var n_local_agg := Vector3.ZERO
		for tri_v in (pair[1] as Array):
			var tri: Dictionary = tri_v
			var si: int = int(tri["si"])
			if si >= mi.mesh.get_surface_count():
				ok = false
				break
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var bpv: int = Skinning.bones_per_vertex(bones, verts.size())
			var idx: Array = tri["i"]
			var uv_acc := Vector2.ZERO
			var n_t3 := 0
			var bad := false
			for ii in idx:
				var vi: int = int(ii)
				if vi >= verts.size():
					bad = true
					break
				uv_acc += uvs[vi]
				var bw := 0.0
				var bb := -1
				for k in bpv:
					var w: float = float(weights[vi * bpv + k])
					if w > bw:
						bw = w
						bb = _patch_bind_map[bones[vi * bpv + k]]
				if bb == t3:
					n_t3 += 1
				elif bb != t2:
					bad = true
					break
			if bad or n_t3 < 2:
				ok = false
				break
			# UV identity must match the compiled patch exactly.
			if (uv_acc / 3.0).distance_to(tri["uvc"] as Vector2) > PATCH_UV_TOL:
				ok = false
				break
			# Winding: the compiled flip factor must map the authored cross
			# product onto the imported rendered normals at rest.
			var p0: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, si, int(idx[0]), bpv, _patch_bind_map
			)
			var p1: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, si, int(idx[1]), bpv, _patch_bind_map
			)
			var p2: Vector3 = Skinning.skinned_vertex_world(
				mi, skel, si, int(idx[2]), bpv, _patch_bind_map
			)
			var ng: Vector3 = (p1 - p0).cross(p2 - p0)
			var area: float = ng.length() * 0.5
			ng = ng.normalized() * float(tri["flip"])
			var nv := Vector3.ZERO
			for ii in idx:
				var vi2: int = int(ii)
				var bw2 := 0.0
				var bb2 := -1
				for k in bpv:
					var w2: float = float(weights[vi2 * bpv + k])
					if w2 > bw2:
						bw2 = w2
						bb2 = _patch_bind_map[bones[vi2 * bpv + k]]
				nv += (
					skel.global_transform.basis
					* skel.get_bone_global_pose(bb2).basis
					* skel.get_bone_global_rest(bb2).basis.inverse()
				) * norms[vi2]
			if ng.dot(nv.normalized()) < 0.0:
				ok = false
				break
			n_local_agg += (t3_world_inv * ng) * area
			refs.append({"si": si, "i": idx.duplicate(), "bpv": bpv, "flip": float(tri["flip"])})
		if not ok:
			break
		# Aggregate rest normal must match the compiled profile normal.
		var expected: Vector3 = (
			_nail_normal_local() if patch == "nail" else _pad_normal_local()
		)
		if n_local_agg.normalized().dot(expected) < PATCH_REST_NORMAL_MIN_DOT:
			ok = false
			break
		out_refs[patch] = refs
	for i in chain.size():
		skel.set_bone_pose_rotation(int(chain[i]), saved[i])
	skel.force_update_all_bone_transforms()
	if not ok:
		_patch_bind_failure = "thumb_patch_frame_mismatch"
		if not out_refs.has("nail"):
			_patch_bind_failure = "thumb_true_nail_patch_missing"
		elif not out_refs.has("pad"):
			_patch_bind_failure = "thumb_true_pad_patch_missing"
		return false
	_patch_refs = out_refs
	return true


## Deterministic stamp of the pose the surface measurement belongs to:
## thumb chain pose rotations + the club's final attachment transform.
## The gate rejects measurements whose stamp no longer matches the live
## pose (thumb_measurement_pose_stale).
func pose_stamp() -> String:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return ""
	var parts := PackedStringArray()
	for bi in _chain_indices.get("thumb", []):
		var q: Quaternion = skel.get_bone_pose_rotation(int(bi))
		parts.append("%.5f,%.5f,%.5f,%.5f" % [q.x, q.y, q.z, q.w])
	var parent: Node3D = _club.get_parent() as Node3D
	var xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	parts.append(str(xf.origin.snappedf(0.0001)) + str(xf.basis.y.snappedf(0.0001)))
	return ",".join(parts)


## CPU-skins the verified patch triangles at the CURRENT achieved pose and
## measures the deformed geometric normals against per-triangle radials in
## the final shaft frame. Area-weighted; winding from the rest-anchored
## compiled flip factors (never re-flipped toward any expectation).
func measure_thumb_surface_truth() -> Dictionary:
	var out := {"ok": false}
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		out["reason"] = "no_skeleton_or_club"
		return out
	if _patch_refs.is_empty() or _patch_mi == null or not is_instance_valid(_patch_mi):
		out["reason"] = "patches_unbound"
		return out
	skel.force_update_all_bone_transforms()
	var parent: Node3D = _club.get_parent() as Node3D
	var axis_xf: Transform3D = (
		parent.global_transform if parent != null else _club.global_transform
	)
	var o: Vector3 = axis_xf.origin
	var d_axis: Vector3 = axis_xf.basis.y.normalized()
	var r_mean: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-6)
	var patches := {}
	for patch in ["nail", "pad"]:
		var invert: bool = patch == "pad"
		var wsum := 0.0
		var out_sum := 0.0
		var ax_sum := 0.0
		var n_mean := Vector3.ZERO
		var c_mean := Vector3.ZERO
		var douts: Array[float] = []
		var min_gap := INF
		for ref_v in (_patch_refs[patch] as Array):
			var ref: Dictionary = ref_v
			var si: int = int(ref["si"])
			var bpv: int = int(ref["bpv"])
			var idx: Array = ref["i"]
			var p0: Vector3 = Skinning.skinned_vertex_world(
				_patch_mi, skel, si, int(idx[0]), bpv, _patch_bind_map
			)
			var p1: Vector3 = Skinning.skinned_vertex_world(
				_patch_mi, skel, si, int(idx[1]), bpv, _patch_bind_map
			)
			var p2: Vector3 = Skinning.skinned_vertex_world(
				_patch_mi, skel, si, int(idx[2]), bpv, _patch_bind_map
			)
			var ng: Vector3 = (p1 - p0).cross(p2 - p0)
			var area: float = maxf(ng.length() * 0.5, 1e-12)
			ng = ng.normalized() * float(ref["flip"])
			var c: Vector3 = (p0 + p1 + p2) / 3.0
			var w: Vector3 = c - o
			var radial: Vector3 = c - (o + d_axis * w.dot(d_axis))
			if radial.length_squared() < 1e-14:
				continue
			var r_hat: Vector3 = radial.normalized()
			var d_out: float = ng.dot(-r_hat if invert else r_hat)
			douts.append(d_out)
			wsum += area
			out_sum += d_out * area
			ax_sum += absf(ng.dot(d_axis)) * area
			n_mean += ng * area
			c_mean += c * area
			min_gap = minf(min_gap, _signed_gap(c) / r_mean)
		if wsum <= 0.0 or douts.is_empty():
			out["reason"] = "patch_degenerate_%s" % patch
			return out
		douts.sort()
		var n_agg: Vector3 = (n_mean / wsum).normalized()
		var c_agg: Vector3 = c_mean / wsum
		var w_agg: Vector3 = c_agg - o
		var rad_agg: Vector3 = c_agg - (o + d_axis * w_agg.dot(d_axis))
		var out_agg := 0.0
		if rad_agg.length_squared() > 1e-14:
			out_agg = n_agg.dot(
				-rad_agg.normalized() if invert else rad_agg.normalized()
			)
		patches[patch] = {
			"n_agg": n_agg,
			"c_agg": c_agg,
			"out_agg": out_agg,
			"ax_agg": absf(n_agg.dot(d_axis)),
			"out_w": out_sum / wsum,
			"ax_w": ax_sum / wsum,
			"out_min": douts[0],
			"out_med": douts[douts.size() / 2],
			"out_max": douts[douts.size() - 1],
			"min_gap_r": min_gap,
			"tris": douts.size(),
		}
	var nail: Dictionary = patches["nail"]
	var pad: Dictionary = patches["pad"]
	out["ok"] = true
	out["nail"] = nail
	out["pad"] = pad
	out["expected_nail_tris"] = _nail_tris().size()
	out["expected_pad_tris"] = _pad_tris().size()
	out["rest_nail_pad_dot"] = _rest_nail_pad_dot()
	out["nail_out_geom"] = float(nail["out_agg"])
	out["nail_axis_geom"] = float(nail["ax_agg"])
	out["pad_in_geom"] = float(pad["out_agg"])
	out["nail_pad_geom_dot"] = (nail["n_agg"] as Vector3).dot(pad["n_agg"] as Vector3)
	out["closest_patch"] = (
		"nail" if float(nail["min_gap_r"]) < float(pad["min_gap_r"]) else "pad"
	)
	# Physical distal roll: the deformed nail plate vs the RIGID Thumb3
	# expectation, measured about the achieved distal segment — extreme
	# skin twist or a rolled distal frame shows up here.
	var t3: int = int((_chain_indices["thumb"] as Array)[2])
	var t3_basis: Basis = skel.global_transform.basis * skel.get_bone_global_pose(t3).basis
	var rigid_nail: Vector3 = (t3_basis * _nail_normal_local()).normalized()
	var seg: Vector3 = t3_basis.y.normalized()
	var a_ref: Vector3 = rigid_nail - seg * rigid_nail.dot(seg)
	var b_v: Vector3 = (nail["n_agg"] as Vector3) - seg * (nail["n_agg"] as Vector3).dot(seg)
	if a_ref.length_squared() > 1e-12 and b_v.length_squared() > 1e-12:
		a_ref = a_ref.normalized()
		b_v = b_v.normalized()
		out["distal_phys_roll_deg"] = rad_to_deg(
			atan2((a_ref.cross(b_v)).dot(seg), a_ref.dot(b_v))
		)
	else:
		out["distal_phys_roll_deg"] = 0.0
	# Legacy diagnostics: what the historical superseded constants would
	# claim at this pose (the false-positive path, never gated). Served by
	# the fixture/shell; absent when the asset carries no superseded refs.
	var sup: Dictionary = _superseded_reference()
	if not sup.is_empty():
		var legacy_nail: Vector3 = (t3_basis * (sup["nail"] as Vector3)).normalized()
		var legacy_pad: Vector3 = (t3_basis * (sup["pad"] as Vector3)).normalized()
		var wc: Vector3 = (nail["c_agg"] as Vector3) - o
		var rad_c: Vector3 = (nail["c_agg"] as Vector3) - (o + d_axis * wc.dot(d_axis))
		if rad_c.length_squared() > 1e-14:
			out["legacy_nail_out"] = legacy_nail.dot(rad_c.normalized())
			out["legacy_pad_in"] = legacy_pad.dot(-rad_c.normalized())
	out["pose_stamp"] = pose_stamp()
	return out


## Fail-closed ground-truth gate over a surface measurement. The caller
## provides the CURRENT pose stamp so stale measurements can never pass.
static func evaluate_thumb_surface_truth(
	surface: Dictionary, current_stamp: String
) -> Dictionary:
	var failures: Array[String] = []
	if surface.is_empty() or not bool(surface.get("ok", false)):
		var reason: String = str(surface.get("reason", ""))
		if reason.contains("pad"):
			return {"pass": false, "failures": ["thumb_true_pad_patch_missing"]}
		return {"pass": false, "failures": ["thumb_true_nail_patch_missing"]}
	var nail: Dictionary = surface.get("nail", {})
	var pad: Dictionary = surface.get("pad", {})
	var expect_nail: int = int(surface.get("expected_nail_tris", 1))
	var expect_pad: int = int(surface.get("expected_pad_tris", 1))
	if int(nail.get("tris", 0)) < expect_nail:
		failures.append("thumb_true_nail_patch_missing")
	if int(pad.get("tris", 0)) < expect_pad:
		failures.append("thumb_true_pad_patch_missing")
	if str(surface.get("pose_stamp", "")) != current_stamp or current_stamp.is_empty():
		failures.append("thumb_measurement_pose_stale")
	if float(surface.get("nail_out_geom", -9.0)) < NAIL_GEOM_OUT_MIN:
		failures.append("thumb_nail_geom_faces_inward")
	if float(surface.get("nail_axis_geom", 9.0)) > NAIL_GEOM_AX_MAX:
		failures.append("thumb_nail_geom_axial_to_shaft")
	if float(surface.get("pad_in_geom", -9.0)) < PAD_GEOM_IN_MIN:
		failures.append("thumb_pad_geom_faces_outward")
	var nail_gap: float = float(nail.get("min_gap_r", INF))
	var pad_gap: float = float(pad.get("min_gap_r", INF))
	if nail_gap < pad_gap + NAIL_CONTACT_MARGIN_R:
		failures.append("thumb_nail_is_contact_surface")
	if pad_gap > PAD_CONTACT_GAP_MAX_R:
		failures.append("thumb_pad_not_contact_surface")
	if (
		absf(float(surface.get("nail_pad_geom_dot", 9.0)) - float(surface.get("rest_nail_pad_dot", 0.0)))
		> GEOM_NAIL_PAD_DOT_TOL
	):
		failures.append("thumb_patch_frame_mismatch")
	if absf(float(surface.get("distal_phys_roll_deg", 999.0))) > DISTAL_PHYS_ROLL_MAX_DEG:
		failures.append("thumb_distal_physical_roll_excess")
	return {"pass": failures.is_empty(), "failures": failures}


## Measures the CURRENT achieved pose and evaluates the ground-truth gate
## against it (same final pose the preview renders). Stores both for HUD.
func run_surface_truth_gate() -> Dictionary:
	_last_surface = measure_thumb_surface_truth()
	_last_surface_gate = evaluate_thumb_surface_truth(_last_surface, pose_stamp())
	return _last_surface_gate.duplicate(true)


func last_surface() -> Dictionary:
	return _last_surface.duplicate(true)


func last_surface_gate() -> Dictionary:
	return _last_surface_gate.duplicate(true)


## World-space triangle vertices of the verified skinned patches at the
## CURRENT pose, for the preview debug layer (D). Pure read-out; the gate
## never uses this path.
func surface_debug_triangles() -> Dictionary:
	var out := {}
	var skel := _resolve_skeleton()
	if (
		skel == null or _patch_refs.is_empty() or _patch_mi == null
		or not is_instance_valid(_patch_mi)
	):
		return out
	for patch in ["nail", "pad"]:
		var tris: Array = []
		for ref_v in (_patch_refs.get(patch, []) as Array):
			var ref: Dictionary = ref_v
			var pts: Array[Vector3] = []
			for ii in (ref["i"] as Array):
				pts.append(Skinning.skinned_vertex_world(
					_patch_mi, skel, int(ref["si"]), int(ii),
					int(ref["bpv"]), _patch_bind_map
				))
			tris.append(pts)
		out[patch] = tris
	return out


func _solve() -> void:
	var skel := _resolve_skeleton()
	if skel == null or _club == null or not is_instance_valid(_club):
		return
	_clear_to_rest()
	# Canonical authored pose first (the correctness layer).
	for finger in FINGERS:
		_set_finger_pose(skel, finger, 0.0)
	skel.force_update_all_bone_transforms()
	# Winding-derived thumb sign (audit root cause B): measured against the
	# canonical finger pose the first time, fail-closed thereafter.
	if _thumb_frames.is_empty() and _thumb_axis_failure.is_empty():
		_derive_thumb_anatomy(skel)
		# Derivation poses the thumb; restore canonical fingers afterwards.
		for finger in FINGERS:
			_set_finger_pose(skel, finger, 0.0)
		skel.force_update_all_bone_transforms()
	_set_thumb_pose(skel, 0.0)
	skel.force_update_all_bone_transforms()

	var r_mean: float = maxf(float(_shape.get("radius_mean", 0.01)), 1e-6)
	var diag := {}
	for digit in ALL_DIGITS:
		if digit == "thumb" and _thumb_frames.is_empty():
			# Sign underivable: thumb stays at rest; gate fails closed.
			diag[digit] = {
				"gap_initial_signed": INF,
				"gap_final_signed": INF,
				"refine_delta": 0.0,
				"iterations": 0,
				"joint_limit_hit": false,
				"classification": "sign_underivable",
			}
			continue
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
		var pad: Vector3 = _pad_world(
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

	var hframe: Dictionary = _live_hand_frame(skel)

	# Encirclement v2: arc actually covered by grip contacts. The original
	# pads-only metric under-reported real encirclement (5 points ignore the
	# finger middle phalanges wrapping the far side and the palm pressing the
	# volar side) and only reached 194 deg via the DEFECTIVE axial thumb.
	# Samples: pads (surface points, plain contact threshold) + chain joints
	# and segment midpoints (bone centres, threshold widened by the measured
	# per-rig flesh offset = median distal-joint gap minus pad gap) + the
	# palm patch derived from the achieved volar offset. Threshold for the
	# coverage gate itself is unchanged (>= 180 deg).
	var flesh_samples: Array[float] = []
	var joint_world := {}
	for digit in ALL_DIGITS:
		var pw: Array[Vector3] = []
		for bi in _chain_indices[digit]:
			pw.append(skel.global_transform * skel.get_bone_global_pose(int(bi)).origin)
		joint_world[digit] = pw
		flesh_samples.append(maxf(
			_signed_gap(pw[2]) - float((diag[digit] as Dictionary)["gap_final_signed"]),
			0.0
		))
	flesh_samples.sort()
	var flesh: float = flesh_samples[flesh_samples.size() / 2]
	var surface_tol: float = CONTACT_GAP_RADII * r_mean
	var bone_tol: float = surface_tol + flesh

	var contact_angs: Array[float] = []
	for digit in ALL_DIGITS:
		var fdd: Dictionary = diag[digit]
		var pad_p: Vector3 = fdd["pad_final"]
		var pw: Array[Vector3] = joint_world[digit]
		var samples: Array[Vector3] = [pw[0], pw[1], pw[2], pad_p]
		for si in 3:
			samples.append((samples[si] + samples[si + 1]) * 0.5)
		for p in samples:
			var tol: float = surface_tol if p == pad_p else bone_tol
			_append_contact_angle(contact_angs, p, tol, o, d_axis, e1, e2)
	if bool(hframe.get("ok", false)):
		var u: Vector3 = (hframe["palm_centre"] as Vector3) - o
		var hrad: Vector3 = u - d_axis * u.dot(d_axis)
		var h: float = hrad.length()
		if h > 1e-9:
			var cos_half: float = (h - bone_tol) / maxf(r_mean, 1e-9)
			if cos_half < 1.0:
				var half: float = rad_to_deg(acos(clampf(cos_half, -1.0, 1.0)))
				var centre: float = rad_to_deg(
					atan2(hrad.normalized().dot(e2), hrad.normalized().dot(e1))
				)
				for frac in [-1.0, -0.5, 0.0, 0.5, 1.0]:
					contact_angs.append(fposmod(centre + half * float(frac), 360.0))
	contact_angs.sort()
	var coverage := 0.0
	if contact_angs.size() >= 2:
		var max_gap := 0.0
		for i in contact_angs.size():
			var b: float = (
				contact_angs[(i + 1) % contact_angs.size()]
				+ (360.0 if i + 1 >= contact_angs.size() else 0.0)
			)
			max_gap = maxf(max_gap, b - contact_angs[i])
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
	diag["coverage_flesh_radii"] = flesh / maxf(r_mean, 1e-9)
	diag["coverage_sample_count"] = contact_angs.size()
	diag["opposition_dot"] = opposition
	diag["ordering_ok"] = ordering_ok

	# A2.1: real thumb-wrap geometry (the scalar opposition dot above is NOT
	# sufficient — a thumb lying along the shaft can still score -1.0).
	var fm := Vector3.ZERO
	if finger_mean.length_squared() > 1e-12:
		fm = finger_mean.normalized()
	var wrap_metrics: Dictionary = _measure_thumb_wrap(
		skel, o, d_axis, e1, e2, fm, r_mean, hframe
	)
	var td: Dictionary = diag["thumb"]
	# Applied MCP/IP flexion about the VALIDATED anatomical axes (canonical
	# + weighted refine delta, clamped to [0, max] by construction) — the
	# R5 gate reads the MEASURED swing-twist values, these are diagnostics.
	var t_delta: float = float(td.get("refine_delta", 0.0))
	var anat_now: Dictionary = _canon_thumb_anat()
	wrap_metrics["flex_deg"] = [
		clampf(
			float(anat_now["flex_mcp"])
			+ rad_to_deg(t_delta * THUMB_REFINE_WEIGHTS[1]),
			0.0, MCP_FLEX_MAX_DEG
		),
		clampf(
			float(anat_now["flex_ip"])
			+ rad_to_deg(t_delta * THUMB_REFINE_WEIGHTS[2]),
			0.0, IP_FLEX_MAX_DEG
		),
	]
	wrap_metrics["gap_final_signed"] = float(td.get("gap_final_signed", 0.0))
	wrap_metrics["classification"] = str(td.get("classification", ""))
	diag["thumb_wrap"] = wrap_metrics
	diag["thumb_wrap_gate"] = evaluate_thumb_wrap(wrap_metrics, r_mean)
	_last_diagnostics = diag
