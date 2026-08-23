# Headless A2 power-grip gate (audit Section 7): hard anatomical frame
# invariants BEFORE finger solving, then achieved-contact + encirclement
# gates. Scalar distance decrease alone is NEVER a PASS criterion.
# godot --headless --path game -s res://presentation/tests/test_uthana_a2_club_attachment_grip.gd
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Playback = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)
const Melee1h = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_melee_1h_normalize.gd"
)
const GripShape = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_grip_shape.gd"
)
const HandFrame = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_hand_grip_frame.gd"
)
const AttachmentScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_club_attachment.gd"
)
const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const REL_XFORM_TOL := 1e-4
## Contact gates, dimensionless in grip radius (audit Section 7).
const GAP_MAX_RADII := 0.35
const PEN_MAX_RADII := 0.20
const COVERAGE_MIN_DEG := 180.0
const OPPOSITION_DOT_MAX := -0.3

var _total := 0
var _any_fail := false
var _metrics: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	_check(
		Melee1h.club_source_path() == "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb",
		"exact wooden_club asset path"
	)
	_check(ResourceLoader.exists(Melee1h.club_source_path()), "wooden_club.glb exists")

	var host := Node.new()
	root.add_child(host)

	# --- Normalize compiler + oriented grip frame -------------------------
	var club: Node3D = (load(Melee1h.club_source_path()) as PackedScene).instantiate()
	host.add_child(club)
	await process_frame
	var geom: Dictionary = Melee1h.inspect_geometry(club)
	_check(bool(geom.get("ok", false)), "club geometry ok")
	var analysis: Dictionary = Melee1h.analyze(club, 0.55 * Profile.TARGET_LENGTH_RATIO)
	_check(bool(analysis.get("ok", false)), "melee_1h analyze ok")
	_check(analysis.has("hypothesis_a") and analysis.has("hypothesis_b"), "both hypotheses scored")
	_check(
		float(analysis.get("marker_confidence", 0.0)) >= Melee1h.MIN_MARKER_CONFIDENCE,
		"marker confidence sufficient"
	)
	var meta_probe: Dictionary = Melee1h.build_marker_metadata(analysis, 0.55)
	_check(
		str(meta_probe.get("head_side", "")) == Profile.MELEE_1H_HEAD_SIDE,
		"explicit head_side=radial convention in metadata"
	)
	_check(meta_probe.has("grip_frame"), "oriented grip frame in metadata")
	Melee1h.apply_normalize(club, analysis)
	var shape: Dictionary = GripShape.derive_from_normalized_club(club)
	_check(bool(shape.get("ok", false)), "local grip shape derived (%s)" % shape.get("reason", ""))
	_check(float(shape.get("radius_x", 0.0)) > 0.0, "radius_x > 0")
	_check(float(shape.get("radius_z", 0.0)) > 0.0, "radius_z > 0")
	_check(str(shape.get("contact_model", "")) == "elliptical_cylinder", "elliptical contact model")
	_metrics["shape"] = {
		"radius_x": shape.get("radius_x", 0.0),
		"radius_z": shape.get("radius_z", 0.0),
		"radius_mean": shape.get("radius_mean", 0.0),
		"samples": shape.get("sample_count", 0),
	}
	club.queue_free()

	# --- Uthana setup -------------------------------------------------------
	var model_root := Node3D.new()
	model_root.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	host.add_child(model_root)
	var uthana: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model_root.add_child(uthana)
	await process_frame
	var sk: Skeleton3D = Native.find_skeleton(uthana)
	_check(sk != null and sk.get_bone_count() == 52, "Uthana 52 bones")

	var lib: AnimationLibrary = Native.ensure_walking_library()
	_check(lib != null and lib.has_animation(Native.WALKING_CLIP), "A1 Walking library")
	var player := AnimationPlayer.new()
	uthana.add_child(player)
	var clip_id: String = Playback.attach_looping_clip(
		player, lib.get_animation(Native.WALKING_CLIP), Native.WALKING_CLIP
	)
	player.play(clip_id)
	player.seek(0.35, true)
	await process_frame
	sk.force_update_all_bone_transforms()

	# --- Hand frame: right-handed + volar-verified --------------------------
	var frame: Dictionary = HandFrame.compute(sk, false)
	_check(bool(frame.get("ok", false)), "hand grip frame ok")
	_check(float(frame.get("det", 0.0)) > 0.99, "palm basis det = +1 (right-handed)")
	var a_axis: Vector3 = frame["across"]
	var l_axis: Vector3 = frame["longitudinal"]
	var v_axis: Vector3 = frame["volar"]
	_check(absf(a_axis.dot(l_axis)) < 1e-4, "A orthogonal to L")
	_check(v_axis.is_equal_approx(a_axis.cross(l_axis)), "V = A x L (volar convention)")

	var attachment = AttachmentScript.new()
	attachment.name = AttachmentScript.CONTROLLER_NAME
	host.add_child(attachment)
	var bind: Dictionary = attachment.bind_to_character(uthana)
	_check(bool(bind.get("ok", false)), "bind ok (%s)" % bind.get("error_class", ""))
	var volar: Dictionary = bind.get("volar", {})
	_check(bool(volar.get("ok", false)), "volar dual-verification agrees")
	_check(float(volar.get("thumb_side", 0.0)) > 0.0, "thumb-side check volar-positive")
	_check(
		float(volar.get("mesh_side", 0.0)) > 0.0,
		"skinned flesh extent asymmetry volar-positive"
	)
	_metrics["volar"] = {
		"thumb_side": volar.get("thumb_side", 0.0),
		"mesh_side": volar.get("mesh_side", 0.0),
		"probe_verts": volar.get("probe_vertex_count", 0),
	}

	var equip: Dictionary = attachment.equip_club()
	_check(
		bool(equip.get("ok", false)),
		"equip+power grip ok (%s %s)" % [equip.get("reason", ""), equip.get("error_class", "")]
	)
	if not bool(equip.get("ok", false)):
		print("EQUIP_DETAIL %s" % JSON.stringify(equip.get("invariants", equip)))
		_finish()
		return

	var r_mean: float = float(attachment.grip_shape().get("radius_mean", 0.01))

	# --- Hard anatomical preconditions (audit Section 7) --------------------
	var inv: Dictionary = attachment.measure_grip_invariants()
	_check(bool(inv.get("pass", false)), "hard invariants pass (%s)" % str(inv.get("failures", [])))
	_check(float(inv.get("det_frame", 0.0)) > 0.99, "det(palm_basis) = +1")
	_check(float(inv.get("det_socket", 0.0)) > 0.99, "det(socket) = +1")
	var dot_da: float = float(inv.get("dot_da", 0.0))
	var dot_dl: float = float(inv.get("dot_dl", 9.9))
	var dot_dv: float = float(inv.get("dot_dv", 9.9))
	_check(absf(dot_da) >= 0.90, "shaft transverse: |dot(D,A)|=%.4f >= 0.90" % absf(dot_da))
	_check(dot_da > 0.0, "head side radial: dot(D,A) > 0")
	_check(absf(dot_dl) <= 0.35, "not along fingers: |dot(D,L)|=%.4f <= 0.35" % absf(dot_dl))
	_check(absf(dot_dv) <= 0.25, "not through palm: |dot(D,V)|=%.4f <= 0.25" % absf(dot_dv))
	var volar_off_r: float = float(inv.get("volar_offset_radii", -9.9))
	_check(
		volar_off_r >= 0.4 and volar_off_r <= 2.2,
		"volar offset %.2fr in [0.4r, 2.2r]" % volar_off_r
	)
	_check(bool(inv.get("mcp_spread_over_breadth", 0.0) >= 0.6), "MCP spread >= 0.6 breadth")
	for finger in ["index", "middle", "ring", "pinky"]:
		var hd: float = float((inv.get("hinge_dots", {}) as Dictionary).get(finger, 0.0))
		_check(hd >= 0.80, "%s MCP hinge || shaft (%.3f)" % [finger, hd])
		var reach: float = float((inv.get("station_reach", {}) as Dictionary).get(finger, -1.0))
		_check(
			reach >= 0.35 and reach <= 0.95,
			"%s station reach %.2f in [0.35, 0.95] chain" % [finger, reach]
		)
	_metrics["invariants"] = {
		"dot_da": dot_da,
		"dot_dl": dot_dl,
		"dot_dv": dot_dv,
		"volar_offset_radii": volar_off_r,
		"mcp_spread_over_breadth": inv.get("mcp_spread_over_breadth", 0.0),
	}

	# --- Negative regressions: the gate must reject the old defects ---------
	var offset_node: Node3D = attachment.club_socket().get_node("SocketOffset") as Node3D
	var good_socket: Transform3D = offset_node.global_transform
	var mirrored := Transform3D(
		Basis(-good_socket.basis.x, good_socket.basis.y, good_socket.basis.z),
		good_socket.origin
	)
	var neg_mirror: Dictionary = AttachmentScript.evaluate_grip_invariants(frame, mirrored, r_mean)
	_check(
		not bool(neg_mirror.get("pass", true))
		and (neg_mirror.get("failures", []) as Array).has("socket_det"),
		"negative: mirrored socket (det -1) rejected"
	)
	var along_fingers := Transform3D(
		Basis(l_axis.cross(v_axis), l_axis, v_axis), good_socket.origin
	)
	var neg_along: Dictionary = AttachmentScript.evaluate_grip_invariants(
		frame, along_fingers, r_mean
	)
	var neg_fails: Array = neg_along.get("failures", [])
	_check(
		not bool(neg_along.get("pass", true))
		and neg_fails.has("shaft_not_transverse")
		and neg_fails.has("shaft_along_fingers"),
		"negative: old shaft-along-L defect rejected"
	)
	var dorsal := Transform3D(
		good_socket.basis, good_socket.origin - v_axis * (2.4 * r_mean)
	)
	var neg_dorsal: Dictionary = AttachmentScript.evaluate_grip_invariants(frame, dorsal, r_mean)
	_check(
		not bool(neg_dorsal.get("pass", true))
		and (neg_dorsal.get("failures", []) as Array).has("volar_offset_out_of_band"),
		"negative: dorsal-side offset defect rejected"
	)

	# --- Constant relative club<->hand across frames -------------------------
	var rel0: Transform3D
	for ti in [0.0, 0.25, 0.5, 0.75]:
		player.seek(float(ti), true)
		await process_frame
		sk.force_update_all_bone_transforms()
		attachment._process(0.016)
		var grip_mod = attachment.grip_modifier()
		if grip_mod:
			grip_mod.apply_now()
		var rel: Transform3D = attachment.relative_club_to_hand()
		_check(_xform_finite(rel), "t=%.2f club transform finite" % ti)
		if ti == 0.0:
			rel0 = rel
		else:
			_check(_xform_near(rel, rel0, REL_XFORM_TOL), "t=%.2f relative club<->hand constant" % ti)

	player.seek(0.35, true)
	await process_frame
	sk.force_update_all_bone_transforms()
	attachment._process(0.016)

	var grip = attachment.grip_modifier()
	_check(grip != null, "power grip present")
	_check(str(grip.GRIP_ID) == "power_grip_v1", "grip id power_grip_v1")
	grip.set_grip_enabled(true)
	grip.apply_now()
	sk.force_update_all_bone_transforms()

	# --- Achieved-contact gates (never solver targets) -----------------------
	var diag: Dictionary = grip.last_diagnostics()
	var finger_metrics := {}
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		var fd: Dictionary = diag.get(digit, {})
		_check(fd.has("gap_final") and fd.has("penetration_final"), "%s contact reported" % digit)
		var g1: float = float(fd.get("gap_final", 99.0))
		var p1: float = float(fd.get("penetration_final", 99.0))
		var iters: int = int(fd.get("iterations", 0))
		finger_metrics[digit] = {
			"gap_final": g1,
			"gap_radii": g1 / r_mean,
			"penetration": p1,
			"iterations": iters,
			"refine_delta": fd.get("refine_delta", 0.0),
			"classification": fd.get("classification", ""),
		}
		print(
			"DIGIT %s gap=%.4f (%.2fr) pen=%.4f (%.2fr) delta=%.3f iters=%d cls=%s"
			% [
				digit, g1, g1 / r_mean, p1, p1 / r_mean,
				float(fd.get("refine_delta", 0.0)), iters, fd.get("classification", "")
			]
		)
		_check(iters >= 1 and iters <= 12, "%s refinement iterations bounded" % digit)
		_check(
			absf(float(fd.get("refine_delta", 99.0))) <= 0.2619,
			"%s refinement within +/-15 deg" % digit
		)
		_check(is_finite(g1) and is_finite(p1), "%s contact values finite" % digit)
		_check(g1 <= GAP_MAX_RADII * r_mean, "%s pad gap %.2fr <= 0.35r" % [digit, g1 / r_mean])
		_check(p1 <= PEN_MAX_RADII * r_mean, "%s penetration %.2fr <= 0.20r" % [digit, p1 / r_mean])
	_metrics["fingers"] = finger_metrics

	var coverage: float = float(diag.get("coverage_deg", 0.0))
	var opposition: float = float(diag.get("opposition_dot", 1.0))
	_check(
		coverage >= COVERAGE_MIN_DEG,
		"encirclement: contact coverage %.1f deg >= 180" % coverage
	)
	_check(
		opposition <= OPPOSITION_DOT_MAX,
		"thumb opposes fingers (dot=%.3f <= -0.3)" % opposition
	)
	_check(bool(diag.get("ordering_ok", false)), "contacts strictly ordered index->pinky along D")
	_metrics["coverage_deg"] = coverage
	_metrics["opposition_dot"] = opposition
	_metrics["contact_angles_deg"] = diag.get("contact_angles_deg", {})

	# --- Wrist / forearm / left untouched ------------------------------------
	var wrist_i: int = grip.right_hand_bone_index()
	var forearm_i: int = grip.right_forearm_bone_index()
	var wrist_before: Transform3D = sk.get_bone_pose(wrist_i)
	var forearm_before: Transform3D = sk.get_bone_pose(forearm_i)
	var left_before: Dictionary = _capture(sk, grip.left_probe_indices())
	grip.apply_now()
	_check(sk.get_bone_pose(wrist_i).is_equal_approx(wrist_before), "RightHand delta 0")
	_check(sk.get_bone_pose(forearm_i).is_equal_approx(forearm_before), "RightForeArm delta 0")
	_check(_poses_eq(left_before, _capture(sk, grip.left_probe_indices())), "left-hand delta 0")

	# --- Stability over Walking + determinism + OFF restore ------------------
	for _i in 5:
		player.advance(0.04)
		await process_frame
		sk.force_update_all_bone_transforms()
		attachment._process(0.016)
		grip.apply_now()
	var inv_after: Dictionary = attachment.measure_grip_invariants()
	_check(
		bool(inv_after.get("pass", false)),
		"invariants hold after Walking advances (%s)" % str(inv_after.get("failures", []))
	)
	var diag_b: Dictionary = grip.last_diagnostics()
	_check(
		float((diag_b.get("index", {}) as Dictionary).get("gap_final", 99.0))
			<= GAP_MAX_RADII * r_mean,
		"grip survives Walking advances"
	)
	_check(
		float(diag_b.get("coverage_deg", 0.0)) >= COVERAGE_MIN_DEG,
		"encirclement survives Walking advances"
	)

	grip.set_grip_enabled(true)
	grip.apply_now()
	var fingers_on_a: Dictionary = _capture_fingers(sk, grip)
	grip.apply_now()
	var fingers_on_b: Dictionary = _capture_fingers(sk, grip)
	_check(_poses_eq(fingers_on_a, fingers_on_b), "deterministic / no accumulation")

	grip.set_grip_enabled(false)
	grip.apply_now()
	var fingers_off: Dictionary = _capture_fingers(sk, grip)
	_check(not _poses_eq(fingers_on_a, fingers_off), "grip OFF restores fingers")

	_check(Playback.canonical_library_untouched(), "a1_native_walking.res untouched")
	_check(attachment.get_node_or_null("ShieldSocket_L") == null, "no shield")
	_check(
		uthana.find_children("*", "SkeletonIK3D", true, false).is_empty(),
		"no SkeletonIK3D"
	)

	# Soft quality measures (reported, never gated alone).
	var mean_gap := 0.0
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		mean_gap += float(finger_metrics[digit]["gap_final"])
	mean_gap /= 5.0
	_metrics["soft"] = {"mean_gap_radii": mean_gap / r_mean}
	print("A2_METRICS %s" % JSON.stringify(_metrics))
	_finish()


func _capture_fingers(sk: Skeleton3D, grip) -> Dictionary:
	var d := {}
	for n in grip.bound_finger_names():
		var i: int = sk.find_bone(str(n))
		if i >= 0:
			d[i] = sk.get_bone_pose(i)
	return d


func _capture(sk: Skeleton3D, indices: Array) -> Dictionary:
	var d := {}
	for idx_v in indices:
		var i: int = int(idx_v)
		d[i] = sk.get_bone_pose(i)
	return d


func _poses_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or not (a[k] as Transform3D).is_equal_approx(b[k]):
			return false
	return true


func _xform_finite(t: Transform3D) -> bool:
	for i in 3:
		for j in 3:
			if not is_finite(t.basis[i][j]):
				return false
		if not is_finite(t.origin[i]):
			return false
	return absf(t.basis.determinant()) > 1e-8


func _xform_near(a: Transform3D, b: Transform3D, tol: float) -> bool:
	if a.origin.distance_to(b.origin) > tol:
		return false
	for i in 3:
		if a.basis[i].distance_to(b.basis[i]) > tol * 10.0:
			return false
	return true


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print(
		"test_uthana_a2_club_attachment_grip: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	if not _any_fail:
		print("A2 automated invariant+contact gate passed; user F6 grip inspection still required.")
	quit(1 if _any_fail else 0)
