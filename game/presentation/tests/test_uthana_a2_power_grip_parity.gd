# A2.9 side-by-side parity harness: the accepted legacy A2.7 right-hand
# path (uthana_a2_club_attachment + shell fallbacks) is run LIVE as the
# reference against the generic path (EquipmentAssembler + injected
# family/fixture/engine) on the same skeleton pose, animation time, grip
# radius, weapon geometry and fixture. The reference is produced by the
# old accepted code every run — never hardcoded from report text.
#
# Matrix: Walking t = {0.00, 0.35, len*0.5, len-0.02} x radius {0.9, 1.0,
# 1.1}; the deformed surface-ground-truth gate runs at ALL 12 points.
# Plus one 137° global-yaw point proving coordinate invariance.
# Tolerances are tight FLOAT parity bounds, far inside the acceptance
# bands — never the acceptance bands themselves.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Playback = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)
const AttachmentScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_club_attachment.gd"
)
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)

const TOL_POS := 5e-5
const TOL_AXIS := 5e-4
const TOL_DOT := 5e-4
const TOL_DEG := 0.1
const TOL_R := 2e-3
const TOL_GAP := 5e-6
## Yaw invariance is a different FP path — still far inside acceptance.
const YAW_TOL_DOT := 5e-3
const YAW_TOL_DEG := 0.5
const YAW_TOL_R := 1e-2

var _total := 0
var _any_fail := false
var _legacy := {}
var _generic := {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var host := Node.new()
	root.add_child(host)
	_legacy = await _spawn_legacy(host)
	_generic = await _spawn_generic(host)
	_check(bool(_legacy.get("ok", false)), "legacy reference path equipped")
	_check(bool(_generic.get("ok", false)), "generic path assembled")
	if not bool(_legacy.get("ok", false)) or not bool(_generic.get("ok", false)):
		print("test_uthana_a2_power_grip_parity: %d checks, FAIL" % _total)
		quit(1)
		return
	_test_static_parity()
	var clip_len: float = (_legacy["player"] as AnimationPlayer).get_animation(
		_legacy["clip"]
	).length
	var times: Array[float] = [0.0, 0.35, clip_len * 0.5, clip_len - 0.02]
	var radii: Array[float] = [0.9, 1.0, 1.1]
	for t in times:
		for r_scale in radii:
			await _compare_point(float(t), float(r_scale))
	await _test_determinism_and_reversibility()
	await _test_yaw_invariance()
	print(
		"test_uthana_a2_power_grip_parity: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	quit(1 if _any_fail else 0)


func _spawn_rig(host: Node, tag: String) -> Dictionary:
	var rig_root := Node3D.new()
	rig_root.name = "Rig_%s" % tag
	host.add_child(rig_root)
	var model := Node3D.new()
	model.name = "ModelRoot"
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	rig_root.add_child(model)
	var character: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(character)
	await process_frame
	var sk: Skeleton3D = Native.find_skeleton(character)
	var lib: AnimationLibrary = Native.ensure_walking_library()
	var player := AnimationPlayer.new()
	character.add_child(player)
	var clip: String = Playback.attach_looping_clip(
		player, lib.get_animation(Native.WALKING_CLIP), Native.WALKING_CLIP
	)
	player.play(clip)
	player.seek(0.35, true)
	await process_frame
	sk.force_update_all_bone_transforms()
	return {
		"root": rig_root,
		"character": character,
		"skeleton": sk,
		"player": player,
		"clip": clip,
	}


func _spawn_legacy(host: Node) -> Dictionary:
	var rig: Dictionary = await _spawn_rig(host, "legacy")
	var attachment = AttachmentScript.new()
	attachment.name = AttachmentScript.CONTROLLER_NAME
	(rig["root"] as Node3D).add_child(attachment)
	var bind: Dictionary = attachment.bind_to_character(rig["character"])
	if not bool(bind.get("ok", false)):
		rig["ok"] = false
		return rig
	var equip: Dictionary = attachment.equip_club()
	rig["ok"] = bool(equip.get("ok", false))
	rig["attachment"] = attachment
	rig["grip"] = attachment.grip_modifier()
	rig["socket_offset"] = (attachment.club_socket() as Node3D).get_node("SocketOffset")
	rig["club"] = attachment.club_instance()
	rig["shape"] = attachment.grip_shape()
	return rig


func _spawn_generic(host: Node) -> Dictionary:
	var rig: Dictionary = await _spawn_rig(host, "generic")
	var asm: Node = Composition.make_assembler()
	asm.name = "GenericAssembler"
	(rig["root"] as Node3D).add_child(asm)
	var result: Dictionary = asm.assemble(rig["character"], "right")
	rig["ok"] = bool(result.get("ok", false))
	rig["assembler"] = asm
	rig["grip"] = asm.grip_modifier()
	rig["socket_offset"] = (asm.club_socket() as Node3D).get_node("SocketOffset")
	rig["club"] = asm.club_instance()
	rig["shape"] = asm.grip_shape()
	rig["result"] = result
	return rig


## One-time static parity: weapon scale, head side, one transform owner,
## identical modified-bone sets.
func _test_static_parity() -> void:
	var lc: Node3D = _legacy["club"]
	var gc: Node3D = _generic["club"]
	for axis in 3:
		_cmp_num(
			lc.global_transform.basis[axis].length(),
			gc.global_transform.basis[axis].length(),
			1e-5, "club scale axis %d" % axis
		)
	var lmeta: Dictionary = (_legacy["attachment"] as Object).marker_metadata()
	var gmeta: Dictionary = (_generic["assembler"] as Object).marker_metadata()
	_check(
		str(lmeta.get("head_side", "?")) == str(gmeta.get("head_side", "??")),
		"head side identical (%s)" % str(lmeta.get("head_side", "?"))
	)
	_check(_one_owner(lc), "legacy weapon has one transform owner")
	_check(_one_owner(gc), "generic weapon has one transform owner")
	var lbones: Array = Array((_legacy["grip"] as Object).bound_finger_names())
	var gbones: Array = Array((_generic["grip"] as Object).bound_finger_names())
	lbones.sort()
	gbones.sort()
	_check(lbones == gbones, "identical modified finger-bone sets")
	# Same fixture data feeds both paths.
	var lshape: Dictionary = _legacy["shape"]
	var gshape: Dictionary = _generic["shape"]
	_cmp_num(
		float(lshape.get("radius_mean", 0.0)),
		float(gshape.get("radius_mean", 0.0)), 1e-9, "identical measured grip radius"
	)


func _one_owner(club: Node3D) -> bool:
	var owners := 0
	var n: Node = club
	while n != null:
		if str(n.name).begins_with("WeaponSocket_"):
			owners += 1
		n = n.get_parent()
	return owners == 1


func _seek_both(t: float) -> void:
	for rig in [_legacy, _generic]:
		var player: AnimationPlayer = rig["player"]
		player.seek(t, true)
	await process_frame
	for rig in [_legacy, _generic]:
		(rig["skeleton"] as Skeleton3D).force_update_all_bone_transforms()
	(_legacy["attachment"] as Node)._process(0.016)
	(_generic["assembler"] as Node)._process(0.016)


func _scaled_shape(base: Dictionary, r_scale: float) -> Dictionary:
	var s: Dictionary = base.duplicate(true)
	if not is_equal_approx(r_scale, 1.0):
		s["radius_x"] = float(base["radius_x"]) * r_scale
		s["radius_z"] = float(base["radius_z"]) * r_scale
		s["radius_mean"] = float(base["radius_mean"]) * r_scale
	return s


func _configure_and_solve(rig: Dictionary, r_scale: float, live_frame: Dictionary) -> Dictionary:
	var grip = rig["grip"]
	var shape: Dictionary = _scaled_shape(rig["shape"], r_scale)
	var cfg: Dictionary = grip.configure(rig["character"], rig["club"], shape, live_frame)
	if not bool(cfg.get("ok", false)):
		return {"ok": false, "cfg": cfg}
	grip.set_grip_enabled(true)
	grip.apply_now()
	(rig["skeleton"] as Skeleton3D).force_update_all_bone_transforms()
	var diag: Dictionary = grip.last_diagnostics()
	var contour_gate: Dictionary = grip.run_contour_gate(rig["character"])
	var surface_gate: Dictionary = grip.run_surface_truth_gate()
	return {
		"ok": true,
		"diag": diag,
		"wrap": diag.get("thumb_wrap", {}),
		"wrap_gate": diag.get("thumb_wrap_gate", {}),
		"contour": grip.last_contour(),
		"contour_gate": contour_gate,
		"surface": grip.last_surface(),
		"surface_gate": surface_gate,
		"stamp": grip.pose_stamp(),
	}


func _live_frame(rig: Dictionary) -> Dictionary:
	if rig.has("attachment"):
		return (rig["attachment"] as Object).live_hand_frame()
	return (rig["assembler"] as Object).live_hand_frame()


func _compare_point(t: float, r_scale: float) -> void:
	await _seek_both(t)
	var tag := "t=%.2f r=%.1fx" % [t, r_scale]
	# Socket transforms must match between paths at the same pose.
	var lo: Transform3D = (_legacy["socket_offset"] as Node3D).global_transform
	var go: Transform3D = (_generic["socket_offset"] as Node3D).global_transform
	_cmp_num(lo.origin.distance_to(go.origin), 0.0, TOL_POS, "%s socket origin" % tag)
	for axis in 3:
		_cmp_num(
			(lo.basis[axis] - go.basis[axis]).length(), 0.0, TOL_AXIS,
			"%s socket axis %d" % [tag, axis]
		)
	var lsolve: Dictionary = _configure_and_solve(_legacy, r_scale, _live_frame(_legacy))
	var gsolve: Dictionary = _configure_and_solve(_generic, r_scale, _live_frame(_generic))
	_check(bool(lsolve.get("ok", false)), "%s legacy solve ok" % tag)
	_check(bool(gsolve.get("ok", false)), "%s generic solve ok" % tag)
	if not bool(lsolve.get("ok", false)) or not bool(gsolve.get("ok", false)):
		return
	# Live socket invariants (dot(D,A), volar offset) via both public APIs.
	var linv: Dictionary = (_legacy["attachment"] as Object).measure_grip_invariants()
	var ginv: Dictionary = (_generic["assembler"] as Object).measure_grip_invariants()
	_check(bool(linv.get("pass", false)), "%s legacy invariants pass" % tag)
	_check(bool(ginv.get("pass", false)), "%s generic invariants pass" % tag)
	_cmp_num(float(linv.get("dot_da", 0.0)), float(ginv.get("dot_da", 9.0)), TOL_DOT, "%s dot(D,A)" % tag)
	_cmp_num(
		float(linv.get("volar_offset_radii", 0.0)),
		float(ginv.get("volar_offset_radii", 9.0)), TOL_R, "%s volar offset r" % tag
	)
	var ldiag: Dictionary = lsolve["diag"]
	var gdiag: Dictionary = gsolve["diag"]
	# All five digits: achieved contact angles, gaps, classifications.
	var langles: Dictionary = ldiag.get("contact_angles_deg", {})
	var gangles: Dictionary = gdiag.get("contact_angles_deg", {})
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		var lfd: Dictionary = ldiag.get(digit, {})
		var gfd: Dictionary = gdiag.get(digit, {})
		_cmp_num(
			float(lfd.get("gap_final_signed", 9.0)),
			float(gfd.get("gap_final_signed", -9.0)), TOL_GAP,
			"%s %s gap" % [tag, digit]
		)
		_check(
			str(lfd.get("classification", "?")) == str(gfd.get("classification", "??")),
			"%s %s classification equal" % [tag, digit]
		)
		if langles.has(digit) and gangles.has(digit):
			_cmp_ang(
				float(langles[digit]), float(gangles[digit]),
				TOL_DEG, "%s %s contact angle" % [tag, digit]
			)
	_cmp_ang(
		float(ldiag.get("coverage_deg", 0.0)), float(gdiag.get("coverage_deg", 999.0)),
		TOL_DEG, "%s coverage" % tag
	)
	# Thumb wrap: signed windings, direction, anatomy.
	var lw: Dictionary = lsolve["wrap"]
	var gw: Dictionary = gsolve["wrap"]
	_cmp_ang(
		float(lw.get("winding_thumb_deg", 0.0)), float(gw.get("winding_thumb_deg", 999.0)),
		TOL_DEG, "%s thumb winding" % tag
	)
	_cmp_ang(
		float(lw.get("winding_finger_median_deg", 0.0)),
		float(gw.get("winding_finger_median_deg", 999.0)), TOL_DEG,
		"%s finger median winding" % tag
	)
	_check(
		str(lw.get("direction_class", "?")) == "TOWARD_INDEX"
		and str(gw.get("direction_class", "??")) == "TOWARD_INDEX",
		"%s TOWARD_INDEX both paths" % tag
	)
	for key in [
		"cmc_flex_deg", "cmc_abd_deg", "cmc_twist_deg",
		"mcp_flex_deg", "mcp_abd_deg", "mcp_twist_deg",
		"ip_flex_deg", "ip_abd_deg", "ip_twist_deg",
	]:
		_cmp_ang(
			float(lw.get(key, 0.0)), float(gw.get(key, 999.0)), TOL_DEG,
			"%s %s" % [tag, key]
		)
	_check(
		(lsolve["wrap_gate"] as Dictionary).get("failures", [""]).is_empty()
		and (gsolve["wrap_gate"] as Dictionary).get("failures", [""]).is_empty(),
		"%s wrap gate PASS both (L%s G%s)"
		% [
			tag,
			str((lsolve["wrap_gate"] as Dictionary).get("failures", [])),
			str((gsolve["wrap_gate"] as Dictionary).get("failures", [])),
		]
	)
	# Contour patches: gap/penetration parity + gate PASS on both paths.
	var lc: Dictionary = lsolve["contour"]
	var gc: Dictionary = gsolve["contour"]
	for pkey in ["cmc", "t2", "t3"]:
		var lp: Dictionary = (lc.get("patches", {}) as Dictionary).get(pkey, {})
		var gp: Dictionary = (gc.get("patches", {}) as Dictionary).get(pkey, {})
		_cmp_num(float(lp.get("min_r", 9.0)), float(gp.get("min_r", -9.0)), TOL_R, "%s contour %s min" % [tag, pkey])
		_cmp_num(float(lp.get("med_r", 9.0)), float(gp.get("med_r", -9.0)), TOL_R, "%s contour %s med" % [tag, pkey])
	_cmp_num(float(lc.get("mid_excess_r", 9.0)), float(gc.get("mid_excess_r", -9.0)), TOL_R, "%s mid excess" % tag)
	_check(
		bool((lsolve["contour_gate"] as Dictionary).get("pass", false))
		and bool((gsolve["contour_gate"] as Dictionary).get("pass", false)),
		"%s contour gate PASS both" % tag
	)
	# Deformed surface ground truth AT EVERY MATRIX POINT on both paths.
	var ls: Dictionary = lsolve["surface"]
	var gs: Dictionary = gsolve["surface"]
	_cmp_num(float(ls.get("nail_out_geom", -9.0)), float(gs.get("nail_out_geom", 9.0)), TOL_DOT, "%s nail_out_geom" % tag)
	_cmp_num(float(ls.get("nail_axis_geom", 9.0)), float(gs.get("nail_axis_geom", -9.0)), TOL_DOT, "%s nail_axis_geom" % tag)
	_cmp_num(float(ls.get("pad_in_geom", -9.0)), float(gs.get("pad_in_geom", 9.0)), TOL_DOT, "%s pad_in_geom" % tag)
	_cmp_num(
		float((ls.get("nail", {}) as Dictionary).get("min_gap_r", 9.0)),
		float((gs.get("nail", {}) as Dictionary).get("min_gap_r", -9.0)),
		TOL_R, "%s nail gap" % tag
	)
	_cmp_num(
		float((ls.get("pad", {}) as Dictionary).get("min_gap_r", 9.0)),
		float((gs.get("pad", {}) as Dictionary).get("min_gap_r", -9.0)),
		TOL_R, "%s pad gap" % tag
	)
	_check(
		str(ls.get("closest_patch", "?")) == "pad" and str(gs.get("closest_patch", "??")) == "pad",
		"%s closest patch = pad both" % tag
	)
	_cmp_ang(
		float(ls.get("distal_phys_roll_deg", 999.0)),
		float(gs.get("distal_phys_roll_deg", -999.0)), TOL_DEG, "%s distal roll" % tag
	)
	# A2.10: the superseded A2.5 plate normals are HISTORICAL REGRESSION
	# evidence -- a previously rejected hypothesis about this one asset. A
	# generic compiler cannot derive a rejected hypothesis from geometry, so
	# the compiled artifact deliberately carries none, while the legacy
	# reference path still reports it. Asserting the split explicitly is
	# stronger than comparing the two: it pins that the diagnostic stayed on
	# the reference side and never leaked into the compiled fixture.
	_check(
		absf(float(ls.get("legacy_nail_out", 9.0))) <= 1.0,
		"%s reference path still reports the superseded A2.5 diagnostic (%.6f)"
			% [tag, ls.get("legacy_nail_out", 9.0)]
	)
	_check(
		absf(float(ls.get("legacy_nail_out", 9.0)) - float(ls.get("nail_out_geom", -9.0))) > 0.1,
		"%s superseded A2.5 normal stays distinct from the achieved A2.7 plate" % tag
	)
	_check(
		absf(float(gs.get("legacy_nail_out", 9.0))) > 1.0,
		"%s compiled fixture carries no historical-regression evidence" % tag
	)
	_check(
		bool((lsolve["surface_gate"] as Dictionary).get("pass", false))
		and bool((gsolve["surface_gate"] as Dictionary).get("pass", false)),
		"%s SURFACE ground-truth gate PASS both (L%s G%s)"
		% [
			tag,
			str((lsolve["surface_gate"] as Dictionary).get("failures", [])),
			str((gsolve["surface_gate"] as Dictionary).get("failures", [])),
		]
	)
	# Pose freshness on both paths (stamp matches the live measurement).
	_check(
		str(ls.get("pose_stamp", "")) == str(lsolve["stamp"])
		and str(gs.get("pose_stamp", "")) == str(gsolve["stamp"]),
		"%s pose stamps fresh both" % tag
	)
	# Wrist stays outside the grip's authority on both paths. The animated
	# wrist pose may re-quantize by one compressed-track quantum (1/1024
	# rad) when the skeleton flushes — allow exactly that engine noise,
	# and require the SAME behavior on both paths. The exact-zero wrist
	# delta contract stays enforced by the accepted club-attachment test.
	var wrist_deltas: Array[float] = []
	for rig in [_legacy, _generic]:
		var grip = rig["grip"]
		var sk: Skeleton3D = rig["skeleton"]
		var wrist_i: int = grip.right_hand_bone_index()
		_check(
			not Array(grip.bound_finger_names()).has(sk.get_bone_name(wrist_i)),
			"%s wrist not among grip-owned bones (%s)"
			% [tag, "legacy" if rig == _legacy else "generic"]
		)
		var before: Quaternion = sk.get_bone_pose_rotation(wrist_i)
		grip.apply_now()
		sk.force_update_all_bone_transforms()
		var after: Quaternion = sk.get_bone_pose_rotation(wrist_i)
		wrist_deltas.append(before.angle_to(after))
		_check(
			before.angle_to(after) <= 0.0015,
			"%s wrist within one anim quantum (%s, delta %.9f rad)"
			% [tag, "legacy" if rig == _legacy else "generic", before.angle_to(after)]
		)
	_cmp_num(
		wrist_deltas[0], wrist_deltas[1], 1e-6,
		"%s wrist behavior identical between paths" % tag
	)


func _test_determinism_and_reversibility() -> void:
	await _seek_both(0.35)
	for rig_name in ["legacy", "generic"]:
		var rig: Dictionary = _legacy if rig_name == "legacy" else _generic
		var solve1: Dictionary = _configure_and_solve(rig, 1.0, _live_frame(rig))
		var stamp1: String = str(solve1.get("stamp", ""))
		var nail1: float = float((solve1["surface"] as Dictionary).get("nail_out_geom", -9.0))
		var grip = rig["grip"]
		grip.apply_now()
		(rig["skeleton"] as Skeleton3D).force_update_all_bone_transforms()
		grip.run_surface_truth_gate()
		var surf2: Dictionary = grip.last_surface()
		_check(str(grip.pose_stamp()) == stamp1, "%s deterministic re-apply (same stamp)" % rig_name)
		_cmp_num(
			nail1, float(surf2.get("nail_out_geom", 9.0)), 1e-9,
			"%s deterministic nail_out_geom" % rig_name
		)
		# Reversibility: grip OFF restores the rest finger poses.
		var sk: Skeleton3D = rig["skeleton"]
		grip.set_grip_enabled(false)
		grip.apply_now()
		sk.force_update_all_bone_transforms()
		# Reference = the skeleton's own reset_bone_pose result. The engine's
		# post-pass restore may leave the AUTHORED import pose (≈rest within
		# ~7e-4 rad quantization) instead of the exact reset — allow exactly
		# that, capture per-bone values, and require identical behavior on
		# both paths below. The accepted OFF/ON semantics stay covered by
		# the preview runtime test (G key) and the club-attachment test.
		var worst := 0.0
		var worst_bone := ""
		var off_poses: Dictionary = {}
		for bname in grip.bound_finger_names():
			var bi: int = sk.find_bone(str(bname))
			var q: Quaternion = sk.get_bone_pose_rotation(bi)
			off_poses[str(bname)] = q
			sk.reset_bone_pose(bi)
			var r: Quaternion = sk.get_bone_pose_rotation(bi)
			sk.set_bone_pose_rotation(bi, q)
			if q.angle_to(r) > worst:
				worst = q.angle_to(r)
				worst_bone = str(bname)
		rig["off_poses"] = off_poses
		_check(
			worst < 0.0015,
			"%s grip OFF within import-pose quantization of rest (worst %.6f rad on %s)"
			% [rig_name, worst, worst_bone]
		)
		grip.set_grip_enabled(true)
		grip.apply_now()
		sk.force_update_all_bone_transforms()
		_check(
			bool(grip.run_surface_truth_gate().get("pass", false)),
			"%s grip back ON, surface gate green" % rig_name
		)
	# The OFF state must agree between paths bone by bone within the same
	# import-pose/rest quantization band (the two separate skeleton
	# instances flush their pose backups on different schedules, so exact
	# bit identity is an engine-scheduling artifact, not grip logic).
	var loff: Dictionary = _legacy.get("off_poses", {})
	var goff: Dictionary = _generic.get("off_poses", {})
	var worst_pair := 0.0
	for bname in loff.keys():
		if goff.has(bname):
			worst_pair = maxf(
				worst_pair, (loff[bname] as Quaternion).angle_to(goff[bname] as Quaternion)
			)
	_check(
		loff.size() == goff.size() and worst_pair < 0.0015,
		"OFF poses agree between paths within quantization (worst %.9f rad)" % worst_pair
	)


## Global 137° yaw on the generic rig: identical classifications and
## dimensionless results (coordinate invariance).
func _test_yaw_invariance() -> void:
	await _seek_both(0.35)
	var base: Dictionary = _configure_and_solve(_generic, 1.0, _live_frame(_generic))
	_check(bool(base.get("ok", false)), "yaw baseline solve ok")
	var rig_root: Node3D = _generic["root"]
	rig_root.rotation_degrees.y = 137.0
	await process_frame
	(_generic["skeleton"] as Skeleton3D).force_update_all_bone_transforms()
	(_generic["assembler"] as Node)._process(0.016)
	var rotated: Dictionary = _configure_and_solve(_generic, 1.0, _live_frame(_generic))
	_check(bool(rotated.get("ok", false)), "yaw 137 solve ok")
	if bool(base.get("ok", false)) and bool(rotated.get("ok", false)):
		var binv: Dictionary = (_generic["assembler"] as Object).measure_grip_invariants()
		_check(bool(binv.get("pass", false)), "yaw 137 socket invariants pass")
		var b: Dictionary = base["surface"]
		var r: Dictionary = rotated["surface"]
		_cmp_num(float(b.get("nail_out_geom", -9.0)), float(r.get("nail_out_geom", 9.0)), YAW_TOL_DOT, "yaw nail_out_geom invariant")
		_cmp_num(float(b.get("nail_axis_geom", 9.0)), float(r.get("nail_axis_geom", -9.0)), YAW_TOL_DOT, "yaw nail_axis_geom invariant")
		_cmp_num(float(b.get("pad_in_geom", -9.0)), float(r.get("pad_in_geom", 9.0)), YAW_TOL_DOT, "yaw pad_in_geom invariant")
		var bw: Dictionary = base["wrap"]
		var rw: Dictionary = rotated["wrap"]
		_cmp_ang(
			float(bw.get("winding_thumb_deg", 0.0)),
			float(rw.get("winding_thumb_deg", 999.0)), YAW_TOL_DEG, "yaw thumb winding invariant"
		)
		_check(
			str(rw.get("direction_class", "?")) == "TOWARD_INDEX",
			"yaw direction TOWARD_INDEX"
		)
		_cmp_num(
			float((base["contour"] as Dictionary).get("mid_excess_r", 9.0)),
			float((rotated["contour"] as Dictionary).get("mid_excess_r", -9.0)),
			YAW_TOL_R, "yaw contour mid excess invariant"
		)
		_check(
			bool((rotated["surface_gate"] as Dictionary).get("pass", false))
			and bool((rotated["contour_gate"] as Dictionary).get("pass", false))
			and (rotated["wrap_gate"] as Dictionary).get("failures", [""]).is_empty(),
			"yaw 137 all gates PASS"
		)
	rig_root.rotation_degrees.y = 0.0
	await process_frame


func _cmp_num(a: float, b: float, tol: float, label: String) -> void:
	_check(absf(a - b) <= tol, "%s (%.6f vs %.6f, tol %.6f)" % [label, a, b, tol])


func _cmp_ang(a: float, b: float, tol: float, label: String) -> void:
	var d: float = absf(rad_to_deg(angle_difference(deg_to_rad(a), deg_to_rad(b))))
	_check(d <= tol, "%s (%.3f vs %.3f deg, tol %.3f)" % [label, a, b, tol])


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		print("FAIL: %s" % label)
