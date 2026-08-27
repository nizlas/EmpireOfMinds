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
## A2.2: the old OPPOSITION_DOT_MAX (-0.3) acceptance gate is REMOVED —
## the audit proved the point-normal/diametric model winding-blind and
## hostile to the correct counter-winding pose. opposition_dot is reported
## as a diagnostic only; R1-R4 (winding relation, meeting sector, contact,
## approach) are the acceptance contract.

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
		"encirclement %.1f deg >= 180 (thumb-INDEPENDENT wrap diagnostic)" % coverage
	)
	# A2.2: opposition_dot and radial_dot are DIAGNOSTICS ONLY (audit: the
	# point-normal / diametric-sector model is winding-blind and rejects the
	# correct counter-winding pose, so it must not gate anything).
	print("DIAG opposition_dot=%+.3f (not gated; superseded by R1/R2)" % opposition)
	_check(bool(diag.get("ordering_ok", false)), "contacts strictly ordered index->pinky along D")
	_metrics["coverage_deg"] = coverage
	_metrics["opposition_dot_diag"] = opposition
	_metrics["contact_angles_deg"] = diag.get("contact_angles_deg", {})

	# Four-finger contact pinned to the accepted A2.1 values — this slice
	# may not move the fingers (strict numeric tolerance over float noise).
	var pinned_angles := {"index": 119.6, "middle": 135.7, "ring": 151.0, "pinky": 152.9}
	for f in pinned_angles:
		var got: float = float((diag.get("contact_angles_deg", {}) as Dictionary).get(f, 999.0))
		_check(
			absf(got - float(pinned_angles[f])) <= 2.0,
			"%s contact angle pinned (%.1f vs %.1f +/-2)" % [f, got, pinned_angles[f]]
		)
	_check(
		absf(dot_da - 0.9781) <= 0.005,
		"socket dot(D,A) pinned (%.4f vs 0.9781)" % dot_da
	)
	_check(
		absf(volar_off_r - 1.20) <= 0.02,
		"socket volar offset pinned (%.3fr vs 1.20r)" % volar_off_r
	)

	# --- A2.2 thumb opposition gates R1-R4 (audit Section 8) ----------------
	var tw: Dictionary = diag.get("thumb_wrap", {})
	var tw_gate: Dictionary = diag.get("thumb_wrap_gate", {})
	_check(not tw.is_empty(), "thumb opposition metrics reported")
	_check(
		bool(tw_gate.get("pass", false)),
		"thumb opposition gate R1-R9 PASS (%s)" % str(tw_gate.get("failures", []))
	)
	var wt: float = float(tw.get("winding_thumb_deg", 0.0))
	var wf_med: float = float(tw.get("winding_finger_median_deg", 0.0))
	_check(
		bool(tw.get("opposite_winding", false)),
		"R1: thumb winds OPPOSITE fingers (Wt %+.1f vs Wf med %+.1f)" % [wt, wf_med]
	)
	_check(absf(wt) >= 60.0, "R1: |thumb winding| %.1f >= 60 deg" % absf(wt))
	_check(absf(wf_med) >= 45.0, "R1: |finger median winding| %.1f >= 45 deg" % absf(wf_med))
	for f in tw.get("winding_fingers_deg", {}):
		var wfd: float = float((tw["winding_fingers_deg"] as Dictionary)[f])
		_check(absf(wfd) >= 45.0, "R1: |%s winding| %.1f >= 45 deg" % [f, absf(wfd)])
	var tw_dot: float = float(tw.get("axial_dot_abs", 9.0))
	var tw_ratio: float = float(tw.get("transverse_over_axial", 0.0))
	_check(tw_dot <= 0.70, "R3: chain not parallel to shaft (|dot|=%.3f <= 0.70)" % tw_dot)
	_check(tw_ratio >= 1.2, "R3: transverse dominates axial (%.2f >= 1.2)" % tw_ratio)
	_check(
		float(tw.get("chain_min_gap_radii", -9.0)) >= -0.25,
		"R3: chain not through shaft (min %.2fr >= -0.25r)"
		% float(tw.get("chain_min_gap_radii", -9.0))
	)
	_check(
		float(tw.get("volar_clearance_hand", -9.0)) >= -0.15,
		"R3: chain not through palm (clearance %.3f hand >= -0.15)"
		% float(tw.get("volar_clearance_hand", -9.0))
	)
	var app_axf: float = float(tw.get("approach_axial_fraction", 9.0))
	var app_rad: float = float(tw.get("approach_radial_radii", 9.0))
	_check(app_axf <= 0.60, "R4: approach not axial (fraction %.2f <= 0.60)" % app_axf)
	_check(app_rad <= 0.15, "R4: approach not radially outward (%.2fr <= 0.15r)" % app_rad)

	# --- A2.3 anatomical gates R5-R9 -----------------------------------------
	var cmc_twist: float = float(tw.get("cmc_twist_deg", 99.0))
	var mcp_flex: float = float(tw.get("mcp_flex_deg", -99.0))
	var ip_flex: float = float(tw.get("ip_flex_deg", -99.0))
	_check(
		mcp_flex >= -10.0 and mcp_flex <= 75.0,
		"R5: MCP anatomical flexion %.1f in [-10, 75]" % mcp_flex
	)
	_check(
		ip_flex >= -10.0 and ip_flex <= 95.0,
		"R5: IP anatomical flexion %.1f in [-10, 95]" % ip_flex
	)
	_check(
		not (
			(mcp_flex > 15.0 and ip_flex < -5.0)
			or (mcp_flex < -5.0 and ip_flex > 15.0)
		),
		"R6: consistent chain curvature, no S (MCP %+.1f / IP %+.1f)"
		% [mcp_flex, ip_flex]
	)
	var dir_cls: String = str(tw.get("direction_class", "?"))
	_check(
		dir_cls == "TOWARD_INDEX" or dir_cls == "INDEX_MIDDLE",
		"R7: thumb directed toward index side (%s, along_n=%.2f)"
		% [dir_cls, float(tw.get("pad_along_n", -9.0))]
	)
	_check(bool(tw.get("grip_zone_ok", false)), "R7: pad within the hand grip zone")
	_check(
		absf(float(tw.get("mcp_abd_deg", 99.0))) <= 30.0
		and absf(float(tw.get("ip_abd_deg", 99.0))) <= 30.0,
		"R8: MCP/IP no lateral compensation (abd %+.1f / %+.1f)"
		% [float(tw.get("mcp_abd_deg", 99.0)), float(tw.get("ip_abd_deg", 99.0))]
	)
	_check(
		absf(cmc_twist) <= 100.0,
		"R9: CMC twist %.1f <= 100 deg (opposition pronation budget)" % absf(cmc_twist)
	)
	_check(
		absf(float(tw.get("mcp_twist_deg", 99.0))) <= 25.0
		and absf(float(tw.get("ip_twist_deg", 99.0))) <= 25.0,
		"R9: MCP/IP twist within 25 deg (%.1f / %.1f)"
		% [absf(float(tw.get("mcp_twist_deg", 99.0))), absf(float(tw.get("ip_twist_deg", 99.0)))]
	)
	# No thumb-to-finger contact requirement: thumb holds the SHAFT while
	# the fingers counter from the other side. Prove the separation.
	var t2f: Dictionary = tw.get("thumb_to_finger_pads_r", {})
	_check(
		float(t2f.get("index", 0.0)) > 0.5,
		"no thumb-to-index contact required (pad distance %.2fr > 0.5r, gate PASS)"
		% float(t2f.get("index", 0.0))
	)
	_check(
		absf(float(tw.get("pad_along_r", 0.0)) - float(tw.get("station_index_r", 0.0))) > 0.2,
		"thumb pad at its own along-station (%.2fr vs index %.2fr)"
		% [float(tw.get("pad_along_r", 0.0)), float(tw.get("station_index_r", 0.0))]
	)

	# --- A2.5 distal orientation gates (nail out / pad in) ------------------
	var nail_out: float = float(tw.get("nail_out_dot", -9.0))
	var nail_axis: float = float(tw.get("nail_axis_dot", 9.0))
	var pad_in: float = float(tw.get("pad_in_dot", -9.0))
	_check(nail_out >= 0.3, "R10: nail faces outward (%.2f >= 0.3)" % nail_out)
	_check(nail_axis <= 0.6, "R10: nail not axial to shaft (%.2f <= 0.6)" % nail_axis)
	_check(pad_in >= 0.3, "R10: pad faces shaft (%.2f >= 0.3)" % pad_in)
	# A2.7: the TRUE plates are nearly perpendicular at rest (the audit's
	# T3_REST_NAIL_PAD_DOT), not opposed — the old "opposed" expectation was
	# an artifact of the mislabeled A2.5 surfaces.
	_check(
		absf(float(tw.get("nail_pad_dot", 9.0)) - grip.T3_REST_NAIL_PAD_DOT) <= 0.45,
		"R10: nail/pad relation matches the verified rest relation (%.2f vs %.2f +/-0.45)"
		% [float(tw.get("nail_pad_dot", 9.0)), grip.T3_REST_NAIL_PAD_DOT]
	)
	_check(
		absf(float(tw.get("distal_roll_deg", 999.0))) <= 60.0,
		"R10: distal roll within limit (%+.0f deg, |.| <= 60)"
		% float(tw.get("distal_roll_deg", 999.0))
	)
	# Tip isolation stays a DIAGNOSTIC (skinned, one-shot).
	var iso_new: Dictionary = grip.measure_tip_isolation(uthana)
	print(
		"DIAG tip isolation: %.3fr (max tip gap %.2fr, %d tip verts)"
		% [
			float(iso_new.get("isolation_excess_r", 9.0)),
			float(iso_new.get("max_tip_gap_r", 9.0)),
			int(iso_new.get("tip_vert_count", 0)),
		]
	)
	# Negative (spec A2.5 §9.1): the MEASURED A2.4 pose — every pre-A2.5
	# metric green, but the nail faced the shaft (nail_out -0.71, pad_in
	# -0.60, roll -126; measured by the calibration probe). The distal
	# orientation gate must reject it by name.
	var a24_m: Dictionary = (tw as Dictionary).duplicate(true)
	a24_m["nail_out_dot"] = -0.71
	a24_m["nail_axis_dot"] = 0.21
	a24_m["pad_in_dot"] = -0.60
	a24_m["nail_pad_dot"] = -0.75
	a24_m["distal_roll_deg"] = -126.0
	var a24_gate: Dictionary = grip.evaluate_thumb_wrap(a24_m, r_mean)
	var a24_fails: Array = a24_gate.get("failures", [])
	_check(
		not bool(a24_gate.get("pass", true))
		and a24_fails.has("thumb_nail_faces_inward")
		and a24_fails.has("thumb_pad_faces_outward")
		and a24_fails.has("thumb_distal_roll_excess"),
		"neg-a25a: measured A2.4 orientation REJECTED by nail gate (%s)" % str(a24_fails)
	)
	# Negatives: nail along +D / -D (analytic).
	for dsign in [1.0, -1.0]:
		var ax_m: Dictionary = (tw as Dictionary).duplicate(true)
		ax_m["nail_out_dot"] = 0.1
		ax_m["nail_axis_dot"] = 0.95
		var ax_gate: Dictionary = grip.evaluate_thumb_wrap(ax_m, r_mean)
		_check(
			not bool(ax_gate.get("pass", true))
			and (ax_gate.get("failures", []) as Array).has("thumb_nail_axial_to_shaft"),
			"neg-a25b: nail along %sD rejected (%s)"
			% ["+" if dsign > 0 else "-", str(ax_gate.get("failures", []))]
		)
	# Negative: correct nail direction but no shaft contact (analytic).
	var noc_m: Dictionary = (tw as Dictionary).duplicate(true)
	noc_m["gap_final_signed"] = 0.9 * r_mean
	var noc_gate: Dictionary = grip.evaluate_thumb_wrap(noc_m, r_mean)
	_check(
		not bool(noc_gate.get("pass", true))
		and (noc_gate.get("failures", []) as Array).has("thumb_pad_not_on_surface"),
		"neg-a25c: right nail direction without pad contact rejected (%s)"
		% str(noc_gate.get("failures", []))
	)
	# Negative: distal twist turning the nail toward the shaft (posed).
	var chain_t5: Array = grip._chain_indices["thumb"]
	var fr2_t5: Dictionary = grip._thumb_frames[2]
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	sk.set_bone_pose_rotation(
		int(chain_t5[2]),
		sk.get_bone_pose_rotation(int(chain_t5[2]))
		* Quaternion((fr2_t5["t_l"] as Vector3).normalized(), deg_to_rad(150.0))
	)
	sk.force_update_all_bone_transforms()
	var roll_m: Dictionary = grip.measure_thumb_now()
	var roll_gate: Dictionary = grip.evaluate_thumb_wrap(roll_m, r_mean)
	_check(
		not bool(roll_gate.get("pass", true))
		and (
			(roll_gate.get("failures", []) as Array).has("thumb_nail_faces_inward")
			or (roll_gate.get("failures", []) as Array).has("thumb_ip_twist_excess")
		),
		"neg-a25d: distal twist hiding the nail rejected (nail_out %.2f, %s)"
		% [
			float(roll_m.get("nail_out_dot", 9.0)),
			str(roll_gate.get("failures", [])),
		]
	)
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	print(
		"DIAG meeting=%.0f radial_dot=%+.2f |wrap|=%.0f t2f=%s cmc(sw twist)=%.0f/%.0f flipped=%s"
		% [
			float(tw.get("meeting_angle_deg", 0.0)),
			float(tw.get("radial_dot_vs_fingers", 0.0)),
			absf(float(tw.get("wrap_deg", 0.0))),
			str(t2f),
			float(tw.get("cmc_flex_deg", 0.0)),
			cmc_twist,
			str(grip.thumb_axis_flipped()),
		]
	)
	_metrics["thumb_wrap"] = tw

	# --- Negative regressions: 10 cases against the A2.2 opposition gate ----
	# A2.3 case numbering (spec §12). Cases 1/12/13 = the longitudinal club
	# defect, mirrored socket basis and non-transversal socket — already
	# gated by the socket-invariant negatives earlier in this test. Case 14
	# = the achieved A2.3 pose (the positive gates above). Cases 10/11 (pad
	# at its own along-station; no thumb-to-index contact) are asserted as
	# PASS conditions in the positive block above.
	var s_index: float = float(
		((equip.get("grip", {}) as Dictionary).get("flex_sign", {}) as Dictionary).get("index", 1.0)
	)
	# Case 2: A2.1 pose — same winding as the fingers, old metrics green.
	var shipped: Dictionary = _pose_thumb_and_eval(
		sk, grip, r_mean, s_index,
		[Vector3(-65.0, -16.0, 30.0), Vector3(61.2, 0.0, 0.0), Vector3(72.5, 0.0, 0.0)]
	)
	var sm: Dictionary = shipped["m"]
	var sfails: Array = (shipped["gate"] as Dictionary).get("failures", [])
	# A2.7 frame re-anchor shifts this legacy fixture's gap slightly (0.38r);
	# near-contact suffices for the fixture's purpose (same-winding defect).
	_check(
		maxf(float(sm.get("gap_final_signed", 9.0)), 0.0) <= 0.45 * r_mean
		and float(sm.get("radial_dot_vs_fingers", 9.0)) <= -0.25
		and absf(float(sm.get("wrap_deg", 0.0))) >= 45.0,
		"neg2 setup: A2.1 pose has ALL old metrics green (gap %.2fr rd %.2f |wrap| %.0f)"
		% [
			float(sm.get("gap_final_signed", 9.0)) / r_mean,
			float(sm.get("radial_dot_vs_fingers", 9.0)),
			absf(float(sm.get("wrap_deg", 0.0))),
		]
	)
	_check(
		not bool((shipped["gate"] as Dictionary).get("pass", true))
		and sfails.has("same_winding_as_fingers"),
		"neg2: A2.1 same-winding pose REJECTED (Wt %+.0f, %s)"
		% [float(sm.get("winding_thumb_deg", 0.0)), str(sfails)]
	)
	# Extra: pre-A2.1 axial thumb still rejected.
	var axial: Dictionary = _pose_thumb_and_eval(
		sk, grip, r_mean, s_index,
		[Vector3(10.0, 60.0, -45.0), Vector3(9.4, 0.0, 0.0), Vector3(10.5, 0.0, 0.0)]
	)
	var afails: Array = (axial["gate"] as Dictionary).get("failures", [])
	_check(
		not bool((axial["gate"] as Dictionary).get("pass", true))
		and afails.has("thumb_chain_parallel_to_shaft"),
		"neg-extra: old axial thumb REJECTED (%s)" % str(afails)
	)
	# Case 3+4: A2.2 pose — counter-winding bought with backward-knee MCP
	# and +87 deg CMC twist, directed at the pinky station. Old R1-R4 all
	# green; the anatomical gates must reject it by name.
	var a22: Dictionary = _pose_thumb_and_eval(
		sk, grip, r_mean, s_index,
		[Vector3(-60.0, 30.0, 80.0), Vector3(50.0, 0.0, 0.0), Vector3(70.0, 0.0, 0.0)]
	)
	var a22_m: Dictionary = a22["m"]
	var a22_fails: Array = (a22["gate"] as Dictionary).get("failures", [])
	_check(
		bool(a22_m.get("opposite_winding", false)),
		"neg3 setup: A2.2 pose has correct winding (%+.0f); old contact was a side-marker artifact (now %.2fr corrected)"
		% [
			float(a22_m.get("winding_thumb_deg", 0.0)),
			float(a22_m.get("gap_final_signed", 9.0)) / r_mean,
		]
	)
	_check(
		not bool((a22["gate"] as Dictionary).get("pass", true))
		and (
			a22_fails.has("thumb_direction_toward_pinky")
			or a22_fails.has("thumb_nail_axial_to_shaft")
			or a22_fails.has("thumb_ip_twist_excess")
		),
		"neg3: A2.2 pose REJECTED (measured with corrected frames: %s)"
		% str(a22_fails)
	)
	_check(
		(
			a22_fails.has("thumb_direction_toward_pinky")
			or a22_fails.has("thumb_direction_toward_ring")
		),
		"neg4: A2.2 pinky-directed pose fails R7 by name (%s)" % str(a22_fails)
	)
	# Case 5: opposite winding with hyperextended MCP (anatomical fixture).
	var hyper: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 55.0, 230.0, 30.0, -30.0, 80.0)
	_check(
		((hyper["gate"] as Dictionary).get("failures", []) as Array).has("thumb_mcp_hyperextension"),
		"neg5: hyperextended MCP rejected (%s)"
		% str((hyper["gate"] as Dictionary).get("failures", []))
	)
	# Case 6: extreme CMC twist BEYOND the opposition-pronation budget
	# (the budget itself is 100 deg — a real opposition needs ~90).
	var twisty: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 25.0, 10.0, -130.0, 0.0, 90.0)
	_check(
		((twisty["gate"] as Dictionary).get("failures", []) as Array).has("thumb_cmc_twist_excess"),
		"neg6: extreme CMC twist rejected (twist %.0f, %s)"
		% [
			float((twisty["m"] as Dictionary).get("cmc_twist_deg", 0.0)),
			str((twisty["gate"] as Dictionary).get("failures", [])),
		]
	)
	# Case 7: S-shaped chain (MCP forward, IP bent backward).
	var scurve: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 55.0, 230.0, 30.0, 50.0, -45.0)
	var sc_fails: Array = (scurve["gate"] as Dictionary).get("failures", [])
	_check(
		sc_fails.has("thumb_s_curve") and sc_fails.has("thumb_ip_hyperextension"),
		"neg7: S-shaped thumb chain rejected (%s)" % str(sc_fails)
	)
	# Case 8 (analytic): correct winding but directed at the wrist.
	var wrist_m: Dictionary = (tw as Dictionary).duplicate(true)
	wrist_m["direction_class"] = "TOWARD_WRIST"
	var wrist_gate: Dictionary = grip.evaluate_thumb_wrap(wrist_m, r_mean)
	_check(
		not bool(wrist_gate.get("pass", true))
		and (wrist_gate.get("failures", []) as Array).has("thumb_direction_toward_wrist"),
		"neg8: wrist-directed thumb rejected (%s)" % str(wrist_gate.get("failures", []))
	)
	# Case 9: thumb pad not touching the shaft. The fixture is picked
	# deterministically: the first pose in a fixed list whose pad gap
	# clearly exceeds the contact band (the shaft crosses the palm, so
	# most "away" swings still project inside the infinite cylinder).
	var nogap := {}
	for cand in [
		[60.0, 270.0, 0.0, 0.0, 0.0], [60.0, 180.0, 0.0, 0.0, 0.0],
		[40.0, 315.0, 0.0, 0.0, 0.0], [20.0, 90.0, 20.0, 0.0, 10.0],
	]:
		var c: Dictionary = _pose_thumb_anat_and_eval(
			sk, grip, r_mean,
			float(cand[0]), float(cand[1]), float(cand[2]), float(cand[3]), float(cand[4])
		)
		if float((c["m"] as Dictionary).get("gap_final_signed", 0.0)) > 0.5 * r_mean:
			nogap = c
			break
	_check(
		not nogap.is_empty()
		and ((nogap["gate"] as Dictionary).get("failures", []) as Array).has(
			"thumb_pad_not_on_surface"
		),
		"neg9: thumb without shaft contact rejected (gap %.2fr, %s)"
		% [
			float((nogap.get("m", {}) as Dictionary).get("gap_final_signed", 9.0)) / r_mean,
			str((nogap.get("gate", {}) as Dictionary).get("failures", [])),
		]
	)
	# A2.4 case: too-low IP flexion opens the grip (pad off the surface,
	# radially-outward tip) — must fail.
	var open_ip: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 20.0, 90.0, 20.0, 0.0, 45.0)
	var open_fails: Array = (open_ip["gate"] as Dictionary).get("failures", [])
	_check(
		not bool((open_ip["gate"] as Dictionary).get("pass", true))
		and (
			open_fails.has("thumb_pad_not_on_surface")
			or open_fails.has("thumb_approach_radially_outward")
		),
		"neg-a24a: low IP flexion opens the grip, rejected (%s)" % str(open_fails)
	)
	# A2.4 case: distal axial twist (nail side rolled toward the shaft) —
	# R9 must reject.
	var fr2_t: Dictionary = grip._thumb_frames[2]
	var chain_t: Array = grip._chain_indices["thumb"]
	_pose_thumb_anat_and_eval(sk, grip, r_mean, 15.0, 98.0, 23.0, 5.0, 80.0)
	sk.set_bone_pose_rotation(
		int(chain_t[2]),
		sk.get_bone_pose_rotation(int(chain_t[2]))
		* Quaternion((fr2_t["t_l"] as Vector3).normalized(), deg_to_rad(40.0))
	)
	sk.force_update_all_bone_transforms()
	var twist_m: Dictionary = grip.measure_thumb_now()
	var twist_gate: Dictionary = grip.evaluate_thumb_wrap(twist_m, r_mean)
	_check(
		not bool(twist_gate.get("pass", true))
		and (twist_gate.get("failures", []) as Array).has("thumb_ip_twist_excess"),
		"neg-a24b: distal nail-to-shaft twist rejected (ip twist %.0f, %s)"
		% [
			float(twist_m.get("ip_twist_deg", 0.0)),
			str(twist_gate.get("failures", [])),
		]
	)
	# Mirrored chirality (analytic): both windings flip, relation holds.
	var mirror_m: Dictionary = (tw as Dictionary).duplicate(true)
	mirror_m["winding_thumb_deg"] = -float(tw.get("winding_thumb_deg", 0.0))
	mirror_m["winding_finger_median_deg"] = -float(tw.get("winding_finger_median_deg", 0.0))
	var mirror_fingers := {}
	for f in tw.get("winding_fingers_deg", {}):
		mirror_fingers[f] = -float((tw["winding_fingers_deg"] as Dictionary)[f])
	mirror_m["winding_fingers_deg"] = mirror_fingers
	var mirror_gate: Dictionary = grip.evaluate_thumb_wrap(mirror_m, r_mean)
	_check(
		bool(mirror_gate.get("pass", false)),
		"neg-mirror: mirrored chirality keeps opposition relation PASS (%s)"
		% str(mirror_gate.get("failures", []))
	)
	# Restore the solver's own achieved pose.
	grip.apply_now()
	sk.force_update_all_bone_transforms()

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
	_check(
		bool((diag_b.get("thumb_wrap_gate", {}) as Dictionary).get("pass", false)),
		"thumb wrap gate survives Walking advances"
	)

	# --- A2.1 robustness: thumb gate across the Walking loop ----------------
	var clip_len: float = player.get_animation(clip_id).length
	for tt in [0.0, 0.35, clip_len * 0.5, clip_len - 0.02]:
		player.seek(float(tt), true)
		await process_frame
		sk.force_update_all_bone_transforms()
		attachment._process(0.016)
		grip.apply_now()
		var dgt: Dictionary = grip.last_diagnostics()
		var gate_t: Dictionary = dgt.get("thumb_wrap_gate", {})
		_check(
			bool(gate_t.get("pass", false)),
			"thumb wrap gate PASS at t=%.2f (%s)" % [tt, str(gate_t.get("failures", []))]
		)
		_check(
			float(dgt.get("coverage_deg", 0.0)) >= COVERAGE_MIN_DEG,
			"coverage >= 180 at t=%.2f" % tt
		)
		# A2.6: distributed skinned contour holds at every Walking time.
		var cg_t: Dictionary = grip.run_contour_gate(uthana)
		var ct_t: Dictionary = grip.last_contour()
		_check(
			bool(cg_t.get("pass", false)),
			"contour gate PASS at t=%.2f (mid %.2fr t2med %.2fr %s)"
			% [
				tt,
				float(ct_t.get("mid_excess_r", 9.0)),
				float((
					(ct_t.get("patches", {}) as Dictionary).get("t2", {}) as Dictionary
				).get("med_r", 9.0)),
				str(cg_t.get("failures", [])),
			]
		)

	# --- A2.1 robustness: nearby normalized grip radii -----------------------
	# The bounded solver must adapt around the actual radius (not a special
	# pose for one mesh point). Only the solver's radius model is perturbed;
	# the club's normalized scale is untouched.
	var club_node: Node3D = (
		attachment.club_socket().get_node("SocketOffset/WoodenClub") as Node3D
	)
	var real_shape: Dictionary = attachment.grip_shape()
	for scale_f in [0.9, 1.0, 1.1]:
		grip.set_grip_enabled(false)
		grip.apply_now()
		sk.force_update_all_bone_transforms()
		var shape2: Dictionary = real_shape.duplicate(true)
		shape2["radius_x"] = float(real_shape["radius_x"]) * float(scale_f)
		shape2["radius_z"] = float(real_shape["radius_z"]) * float(scale_f)
		shape2["radius_mean"] = float(real_shape["radius_mean"]) * float(scale_f)
		var cfg2: Dictionary = grip.configure(
			uthana, club_node, shape2, HandFrame.compute(sk, false)
		)
		_check(bool(cfg2.get("ok", false)), "reconfigure ok at radius %.2fx" % scale_f)
		grip.set_grip_enabled(true)
		grip.apply_now()
		sk.force_update_all_bone_transforms()
		var r2: float = float(shape2["radius_mean"])
		var dg2: Dictionary = grip.last_diagnostics()
		var g2: Dictionary = dg2.get("thumb_wrap_gate", {})
		var tw2: Dictionary = dg2.get("thumb_wrap", {})
		_check(
			bool(g2.get("pass", false)),
			"thumb wrap gate PASS at radius %.2fx (dot %.2f rd %.2f wrap %.0f %s)"
			% [
				scale_f,
				float(tw2.get("axial_dot_abs", 9.0)),
				float(tw2.get("radial_dot_vs_fingers", 9.0)),
				float(tw2.get("wrap_deg", 0.0)),
				str(g2.get("failures", [])),
			]
		)
		var td2: Dictionary = dg2.get("thumb", {})
		_check(
			float(td2.get("gap_final", 99.0)) <= GAP_MAX_RADII * r2
			and float(td2.get("penetration_final", 99.0)) <= PEN_MAX_RADII * r2,
			"thumb contact within band at radius %.2fx (gap %.2fr pen %.2fr)"
			% [
				scale_f,
				float(td2.get("gap_final", 99.0)) / r2,
				float(td2.get("penetration_final", 99.0)) / r2,
			]
		)
		# A2.6: distributed skinned contour holds across nearby radii.
		var cg_r: Dictionary = grip.run_contour_gate(uthana)
		var ct_r: Dictionary = grip.last_contour()
		_check(
			bool(cg_r.get("pass", false)),
			"contour gate PASS at radius %.2fx (mid %.2fr t2med %.2fr %s)"
			% [
				scale_f,
				float(ct_r.get("mid_excess_r", 9.0)),
				float((
					(ct_r.get("patches", {}) as Dictionary).get("t2", {}) as Dictionary
				).get("med_r", 9.0)),
				str(cg_r.get("failures", [])),
			]
		)
	# Restore the real shape and the solved pose.
	grip.set_grip_enabled(false)
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	var cfg_restore: Dictionary = grip.configure(
		uthana, club_node, real_shape, HandFrame.compute(sk, false)
	)
	_check(bool(cfg_restore.get("ok", false)), "restore real shape ok")
	grip.set_grip_enabled(true)
	grip.apply_now()
	sk.force_update_all_bone_transforms()

	# --- A2.6 distributed thumb contour contact -------------------------------
	player.seek(0.35, true)
	await process_frame
	sk.force_update_all_bone_transforms()
	attachment._process(0.016)
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	var cgate: Dictionary = grip.run_contour_gate(uthana)
	var contour: Dictionary = grip.last_contour()
	var cpatches: Dictionary = contour.get("patches", {})
	var c_cmc: Dictionary = cpatches.get("cmc", {})
	var c_t2: Dictionary = cpatches.get("t2", {})
	var c_t3: Dictionary = cpatches.get("t3", {})
	_check(
		bool(cgate.get("pass", false)),
		"A2.6 contour gate PASS (%s)" % str(cgate.get("failures", []))
	)
	_check(
		int(c_cmc.get("n", 0)) >= 2 and int(c_t2.get("n", 0)) >= 2
		and int(c_t3.get("n", 0)) >= 2,
		"contour patches populated (CMC %d / T2 %d / T3 %d verts)"
		% [int(c_cmc.get("n", 0)), int(c_t2.get("n", 0)), int(c_t3.get("n", 0))]
	)
	var c_min_all: float = minf(
		float(c_cmc.get("min_r", 9.0)),
		minf(float(c_t2.get("min_r", 9.0)), float(c_t3.get("min_r", 9.0)))
	)
	_check(
		c_min_all <= grip.CONTOUR_NEAR_CONTACT_MAX_R,
		"distributed volar contact beyond the distal pad (min %.2fr <= %.2fr)"
		% [c_min_all, grip.CONTOUR_NEAR_CONTACT_MAX_R]
	)
	_check(
		float(contour.get("mid_excess_r", 9.0)) <= grip.CONTOUR_MID_EXCESS_MAX_R,
		"no isolated middle gap above the corridor (%.2fr <= %.2fr)"
		% [float(contour.get("mid_excess_r", 9.0)), grip.CONTOUR_MID_EXCESS_MAX_R]
	)
	_check(
		float(c_t2.get("med_r", 9.0)) <= grip.CONTOUR_MID_MED_MAX_R
		and float(contour.get("bulge_r", 9.0)) <= grip.CONTOUR_BULGE_MAX_R,
		"no middle radial bulge (T2 med %.2fr, bulge %.2fr)"
		% [float(c_t2.get("med_r", 9.0)), float(contour.get("bulge_r", 9.0))]
	)
	_check(
		bool(contour.get("monotonic_ok", false))
		and float(contour.get("max_jump_deg", 999.0)) <= grip.CONTOUR_JUMP_MAX_DEG,
		"monotone signed contour progression (max jump %.0f deg)"
		% float(contour.get("max_jump_deg", 999.0))
	)
	_check(
		float(contour.get("kink_out_r", 9.0)) <= grip.CONTOUR_KINK_OUT_MAX_R,
		"no outward curvature kink (%.2fr <= %.2fr)"
		% [float(contour.get("kink_out_r", 9.0)), grip.CONTOUR_KINK_OUT_MAX_R]
	)
	# A2.7: under the verified (honest) volar reference the T2 flesh crosses
	# the shaft tangentially — only a nearly fully flipped middle fails.
	_check(
		float(contour.get("t2_face_dot", -9.0)) > grip.CONTOUR_T2_FACE_MIN,
		"middle volar flesh not flipped outward (dot %.2f > %.2f)"
		% [float(contour.get("t2_face_dot", -9.0)), grip.CONTOUR_T2_FACE_MIN]
	)
	# The accepted grip keeps a NATURAL crease (no zero-gap requirement).
	_check(
		float(c_t2.get("med_r", 9.0)) > 0.02,
		"natural joint crease accepted, not forced to zero (T2 med %.2fr > 0.02r)"
		% float(c_t2.get("med_r", 9.0))
	)
	print(
		"A2.6 CONTOUR pad=%.2fr CMC(%.2f/%.2f) T2(%.2f/%.2f) T3(%.2f/%.2f) mid=%.2fr bulge=%.2fr kink=%+.2fr"
		% [
			float(contour.get("pad_gap_r", 9.0)),
			float(c_cmc.get("min_r", 9.0)), float(c_cmc.get("med_r", 9.0)),
			float(c_t2.get("min_r", 9.0)), float(c_t2.get("med_r", 9.0)),
			float(c_t3.get("min_r", 9.0)), float(c_t3.get("med_r", 9.0)),
			float(contour.get("mid_excess_r", 9.0)),
			float(contour.get("bulge_r", 9.0)),
			float(contour.get("kink_out_r", 9.0)),
		]
	)

	# neg-a26a (A2.7 re-anchor): the EXACT A2.6 pose — reconstructed with the
	# SUPERSEDED (mislabeled) A2.5 frames + canonical 25/0/-90/0/90 — must be
	# REJECTED by the ground-truth surface gate while its historical
	# compiled-constant path still claims nail_out ~ +0.98 (false positive).
	var legacy: Dictionary = _legacy_a26_pose(sk, grip)
	var legacy_gate: Dictionary = grip.run_surface_truth_gate()
	var legacy_surface: Dictionary = grip.last_surface()
	var legacy_fails: Array = legacy_gate.get("failures", [])
	_check(
		bool(legacy.get("ok", false)),
		"neg-a26a setup: legacy A2.6 pose reconstructed via superseded frames"
	)
	_check(
		not bool(legacy_gate.get("pass", true))
		and (
			legacy_fails.has("thumb_nail_geom_faces_inward")
			or legacy_fails.has("thumb_nail_geom_axial_to_shaft")
		),
		"neg-a26a: EXACT A2.6 pose REJECTED by ground-truth gate (out %+.2f ax %.2f %s)"
		% [
			float(legacy_surface.get("nail_out_geom", -9.0)),
			float(legacy_surface.get("nail_axis_geom", 9.0)),
			str(legacy_fails),
		]
	)
	_check(
		float(legacy_surface.get("legacy_nail_out", -9.0)) >= 0.90,
		"neg-a26a: old compiled path still claims nail_out %+.2f >= 0.90 at the SAME pose — proven false positive"
		% float(legacy_surface.get("legacy_nail_out", -9.0))
	)
	# The reconstructed A2.6 pose must not be discarded by the CMC twist
	# budget (tau=-90 is inside the 100° R9 ceiling). Rejection must come
	# from ground-truth surface, not an earlier joint-angle gate.
	var wrap_legacy: Dictionary = grip.evaluate_thumb_wrap(grip.measure_thumb_now(), r_mean)
	_check(
		not (wrap_legacy.get("failures", []) as Array).has("thumb_cmc_twist_excess"),
		"neg-a26a: A2.6 pose is not rejected by the CMC twist budget (%s)"
		% str(wrap_legacy.get("failures", []))
	)
	var l_nail: Dictionary = legacy_surface.get("nail", {})
	var l_pad: Dictionary = legacy_surface.get("pad", {})
	_check(
		float(l_nail.get("min_gap_r", 9.0)) < 0.20
		or float(l_pad.get("min_gap_r", 9.0)) < -0.20
		or str(legacy_surface.get("closest_patch", "")) == "nail",
		"neg-a26a: true pad/nail contact relationship is wrong (nail %.2fr pad %.2fr closest=%s)"
		% [
			float(l_nail.get("min_gap_r", 9.0)),
			float(l_pad.get("min_gap_r", 9.0)),
			str(legacy_surface.get("closest_patch", "")),
		]
	)
	# The A2.7 pose must measurably IMPROVE the true nail orientation vs the
	# measured A2.6 defect (geom out +0.61 / axial 0.66, audit §5).
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	var st_now: Dictionary = grip.run_surface_truth_gate()
	var surf_now: Dictionary = grip.last_surface()
	_check(
		bool(st_now.get("pass", false))
		and float(surf_now.get("nail_out_geom", -9.0)) >= 0.61 + 0.10
		and float(surf_now.get("nail_axis_geom", 9.0)) <= 0.66 - 0.10,
		"A2.7 improves TRUE nail orientation vs measured A2.6 defect (out %+.2f >= 0.71, ax %.2f <= 0.56)"
		% [
			float(surf_now.get("nail_out_geom", -9.0)),
			float(surf_now.get("nail_axis_geom", 9.0)),
		]
	)
	# neg-a26b (analytic): contact ONLY at the distal pad.
	var only_pad: Dictionary = contour.duplicate(true)
	for pkey in ["cmc", "t2", "t3"]:
		((only_pad["patches"] as Dictionary)[pkey] as Dictionary)["min_r"] = 0.55
	var only_gate: Dictionary = grip.evaluate_thumb_contour(only_pad)
	_check(
		not bool(only_gate.get("pass", true))
		and (only_gate.get("failures", []) as Array).has("thumb_contact_only_at_distal_pad"),
		"neg-a26b: only-distal-pad contact rejected (%s)" % str(only_gate.get("failures", []))
	)
	# neg-a26c (analytic): large isolated Thumb2 gap (above A2.7 bands).
	var big_t2: Dictionary = contour.duplicate(true)
	((big_t2["patches"] as Dictionary)["t2"] as Dictionary)["med_r"] = 1.80
	big_t2["mid_excess_r"] = 1.50
	big_t2["bulge_r"] = 1.10
	var big_gate: Dictionary = grip.evaluate_thumb_contour(big_t2)
	_check(
		not bool(big_gate.get("pass", true))
		and (big_gate.get("failures", []) as Array).has("thumb_middle_surface_gap_excess")
		and (big_gate.get("failures", []) as Array).has("thumb_middle_radial_bulge"),
		"neg-a26c: large Thumb2 gap rejected (%s)" % str(big_gate.get("failures", []))
	)
	# neg-a26d (posed): Thumb2 near the shaft but the distal pad OPEN — the
	# combined contract fails via the R3 pad-contact gate.
	var open_pad: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 25.0, 0.0, -90.0, 10.0, 30.0)
	_check(
		not bool((open_pad["gate"] as Dictionary).get("pass", true))
		and ((open_pad["gate"] as Dictionary).get("failures", []) as Array).has(
			"thumb_pad_not_on_surface"
		),
		"neg-a26d: open distal pad rejected by the kept R3 gate (gap %.2fr %s)"
		% [
			float((open_pad["m"] as Dictionary).get("gap_final_signed", 9.0)) / r_mean,
			str((open_pad["gate"] as Dictionary).get("failures", [])),
		]
	)
	# neg-a26e (analytic): the middle joint penetrates the shaft.
	var mid_pen: Dictionary = contour.duplicate(true)
	((mid_pen["patches"] as Dictionary)["t2"] as Dictionary)["min_r"] = -0.55
	var pen_gate: Dictionary = grip.evaluate_thumb_contour(mid_pen)
	_check(
		not bool(pen_gate.get("pass", true))
		and (pen_gate.get("failures", []) as Array).has("thumb_middle_penetration_excess"),
		"neg-a26e: middle-joint shaft penetration rejected (%s)"
		% str(pen_gate.get("failures", []))
	)
	# neg-a26f (analytic): local outward curvature kink at the middle.
	var kinked: Dictionary = contour.duplicate(true)
	kinked["kink_out_r"] = 1.10
	var kink_gate: Dictionary = grip.evaluate_thumb_contour(kinked)
	_check(
		not bool(kink_gate.get("pass", true))
		and (kink_gate.get("failures", []) as Array).has("thumb_curvature_kink_outward"),
		"neg-a26f: outward curvature kink rejected (%s)" % str(kink_gate.get("failures", []))
	)
	# neg-a26g (analytic): non-monotone / discontinuous contour winding.
	var nonmono: Dictionary = contour.duplicate(true)
	nonmono["monotonic_ok"] = false
	nonmono["max_jump_deg"] = 140.0
	var mono_gate: Dictionary = grip.evaluate_thumb_contour(nonmono)
	_check(
		not bool(mono_gate.get("pass", true))
		and (mono_gate.get("failures", []) as Array).has("thumb_surface_winding_nonmonotonic")
		and (mono_gate.get("failures", []) as Array).has("thumb_contact_contour_discontinuous"),
		"neg-a26g: non-monotone contour rejected (%s)" % str(mono_gate.get("failures", []))
	)
	# neg-a26h (analytic): middle volar flesh rolled radially outward.
	var out_face: Dictionary = contour.duplicate(true)
	out_face["t2_face_dot"] = -0.95
	var face_gate: Dictionary = grip.evaluate_thumb_contour(out_face)
	_check(
		not bool(face_gate.get("pass", true))
		and (face_gate.get("failures", []) as Array).has("thumb_middle_pad_faces_outward"),
		"neg-a26h: middle flesh facing outward rejected (%s)" % str(face_gate.get("failures", []))
	)
	# neg-a26i: a smooth contour may NOT buy acceptance with the nail rolled
	# inward — the A2.5 R10 gates stay authoritative alongside the contour.
	var nail_in_m: Dictionary = (tw as Dictionary).duplicate(true)
	nail_in_m["nail_out_dot"] = -0.7
	nail_in_m["pad_in_dot"] = -0.5
	var nail_in_gate: Dictionary = grip.evaluate_thumb_wrap(nail_in_m, r_mean)
	_check(
		not bool(nail_in_gate.get("pass", true))
		and (nail_in_gate.get("failures", []) as Array).has("thumb_nail_faces_inward"),
		"neg-a26i: smooth contour with inward nail still rejected by R10 (%s)"
		% str(nail_in_gate.get("failures", []))
	)
	# neg-a26j: a smooth contour bought with anatomically impossible joints
	# stays rejected by the kept R9 budget.
	var impossible: Dictionary = _pose_thumb_anat_and_eval(sk, grip, r_mean, 25.0, 0.0, -130.0, 0.0, 90.0)
	_check(
		not bool((impossible["gate"] as Dictionary).get("pass", true))
		and ((impossible["gate"] as Dictionary).get("failures", []) as Array).has(
			"thumb_cmc_twist_excess"
		),
		"neg-a26j: anatomically impossible CMC pronation still rejected (%s)"
		% str((impossible["gate"] as Dictionary).get("failures", []))
	)
	# Restore the solved pose and its stored contour.
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	var cg_final: Dictionary = grip.run_contour_gate(uthana)
	_check(
		bool(cg_final.get("pass", false)),
		"contour gate PASS restored after negative fixtures (%s)"
		% str(cg_final.get("failures", []))
	)
	# --- A2.7 ground-truth surface gate (deformed skinned patches) ----------
	var sgate: Dictionary = grip.run_surface_truth_gate()
	var surf: Dictionary = grip.last_surface()
	var s_nail: Dictionary = surf.get("nail", {})
	var s_pad: Dictionary = surf.get("pad", {})
	_check(
		bool(sgate.get("pass", false)),
		"A2.7 ground-truth surface gate PASS (%s)" % str(sgate.get("failures", []))
	)
	_check(
		int(s_nail.get("tris", 0)) == grip.T3_NAIL_TRIS.size()
		and int(s_pad.get("tris", 0)) == grip.T3_PAD_TRIS.size(),
		"verified patches fully bound (nail %d/%d, pad %d/%d tris)"
		% [
			int(s_nail.get("tris", 0)), grip.T3_NAIL_TRIS.size(),
			int(s_pad.get("tris", 0)), grip.T3_PAD_TRIS.size(),
		]
	)
	_check(
		float(surf.get("nail_out_geom", -9.0)) >= grip.NAIL_GEOM_OUT_MIN,
		"NAIL_GEOM out %+.2f >= %.2f (deformed skinned ground truth)"
		% [float(surf.get("nail_out_geom", -9.0)), grip.NAIL_GEOM_OUT_MIN]
	)
	_check(
		float(surf.get("nail_axis_geom", 9.0)) <= grip.NAIL_GEOM_AX_MAX,
		"NAIL_GEOM axis %.2f <= %.2f" % [
			float(surf.get("nail_axis_geom", 9.0)), grip.NAIL_GEOM_AX_MAX,
		]
	)
	_check(
		float(surf.get("pad_in_geom", -9.0)) >= grip.PAD_GEOM_IN_MIN,
		"PAD_GEOM in %+.2f >= %.2f" % [
			float(surf.get("pad_in_geom", -9.0)), grip.PAD_GEOM_IN_MIN,
		]
	)
	_check(
		str(surf.get("closest_patch", "")) == "pad",
		"the PAD (never the nail) is the contact surface (closest=%s, nail %.2fr pad %.2fr)"
		% [
			str(surf.get("closest_patch", "")),
			float(s_nail.get("min_gap_r", 9.0)), float(s_pad.get("min_gap_r", 9.0)),
		]
	)
	_check(
		absf(float(surf.get("distal_phys_roll_deg", 999.0)))
			<= grip.DISTAL_PHYS_ROLL_MAX_DEG,
		"physical distal roll %+.0f deg within %.0f"
		% [
			float(surf.get("distal_phys_roll_deg", 999.0)),
			grip.DISTAL_PHYS_ROLL_MAX_DEG,
		]
	)
	_check(
		str(surf.get("pose_stamp", "")) == str(grip.pose_stamp()),
		"surface measurement is FRESH for the achieved pose"
	)
	print(
		"A2.7 GEOM nail out=%+.2f ax=%.2f gap=%+.2fr | pad in=%+.2f gap=%+.2fr | roll=%+.0f | legacy nail_out=%+.2f"
		% [
			float(surf.get("nail_out_geom", -9.0)),
			float(surf.get("nail_axis_geom", 9.0)),
			float(s_nail.get("min_gap_r", 9.0)),
			float(surf.get("pad_in_geom", -9.0)),
			float(s_pad.get("min_gap_r", 9.0)),
			float(surf.get("distal_phys_roll_deg", 999.0)),
			float(surf.get("legacy_nail_out", -9.0)),
		]
	)
	# Analytic negatives against the ground-truth gate, each by exact name.
	var stamp_now: String = grip.pose_stamp()
	var neg_specs: Array = [
		["nail_out_geom", -0.70, "thumb_nail_geom_faces_inward", "nail inward"],
		["nail_out_geom", 0.10, "thumb_nail_geom_faces_inward", "nail along +D (low out)"],
		["nail_axis_geom", 0.95, "thumb_nail_geom_axial_to_shaft", "nail axial +/-D"],
		["pad_in_geom", -0.50, "thumb_pad_geom_faces_outward", "pad outward"],
		[
			"nail_pad_geom_dot",
			0.90,
			"thumb_surface_geom_deformation_drift",
			"achieved nail/pad opposition collapsed under deformation",
		],
		["distal_phys_roll_deg", 120.0, "thumb_distal_physical_roll_excess", "extreme distal twist"],
	]
	for spec_v in neg_specs:
		var spec: Array = spec_v
		var mut: Dictionary = surf.duplicate(true)
		mut[spec[0]] = spec[1]
		var g2: Dictionary = grip.evaluate_thumb_surface_truth(mut, stamp_now)
		_check(
			not bool(g2.get("pass", true))
			and (g2.get("failures", []) as Array).has(str(spec[2])),
			"neg-a27 %s rejected by name (%s)" % [str(spec[3]), str(g2.get("failures", []))]
		)
	# neg-a27: nail as the actual contact surface.
	var nail_contact: Dictionary = surf.duplicate(true)
	(nail_contact["nail"] as Dictionary)["min_gap_r"] = -0.05
	(nail_contact["pad"] as Dictionary)["min_gap_r"] = 0.20
	var nc_gate: Dictionary = grip.evaluate_thumb_surface_truth(nail_contact, stamp_now)
	_check(
		not bool(nc_gate.get("pass", true))
		and (nc_gate.get("failures", []) as Array).has("thumb_nail_is_contact_surface"),
		"neg-a27 nail-as-contact-surface rejected (%s)" % str(nc_gate.get("failures", []))
	)
	# neg-a27: correct nail-out but no pad contact.
	var no_contact: Dictionary = surf.duplicate(true)
	(no_contact["pad"] as Dictionary)["min_gap_r"] = 0.90
	(no_contact["nail"] as Dictionary)["min_gap_r"] = 1.20
	var noc2: Dictionary = grip.evaluate_thumb_surface_truth(no_contact, stamp_now)
	_check(
		not bool(noc2.get("pass", true))
		and (noc2.get("failures", []) as Array).has("thumb_pad_not_contact_surface"),
		"neg-a27 correct nail-out without pad contact rejected (%s)" % str(noc2.get("failures", []))
	)
	# neg-a27: right patch + radial but STALE canonical pose.
	var stale_gate: Dictionary = grip.evaluate_thumb_surface_truth(surf, stamp_now + "x")
	_check(
		not bool(stale_gate.get("pass", true))
		and (stale_gate.get("failures", []) as Array).has("thumb_measurement_pose_stale"),
		"neg-a27 stale pose measurement rejected (%s)" % str(stale_gate.get("failures", []))
	)
	# neg-a27: missing verified patches fail closed by name.
	var no_nail: Dictionary = surf.duplicate(true)
	(no_nail["nail"] as Dictionary)["tris"] = 0
	var nn_gate: Dictionary = grip.evaluate_thumb_surface_truth(no_nail, stamp_now)
	_check(
		(nn_gate.get("failures", []) as Array).has("thumb_true_nail_patch_missing"),
		"neg-a27 missing nail patch fails closed (%s)" % str(nn_gate.get("failures", []))
	)
	var no_pad2: Dictionary = surf.duplicate(true)
	(no_pad2["pad"] as Dictionary)["tris"] = 0
	var np_gate: Dictionary = grip.evaluate_thumb_surface_truth(no_pad2, stamp_now)
	_check(
		(np_gate.get("failures", []) as Array).has("thumb_true_pad_patch_missing"),
		"neg-a27 missing pad patch fails closed (%s)" % str(np_gate.get("failures", []))
	)
	# neg-a27 (posed): a 150-deg distal segment twist creates "correct-ish"
	# nothing — the GEOMETRIC gate must reject the actually rendered skin.
	var chain_a27: Array = grip._chain_indices["thumb"]
	var fr2_a27: Dictionary = grip._thumb_frames[2]
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	sk.set_bone_pose_rotation(
		int(chain_a27[2]),
		sk.get_bone_pose_rotation(int(chain_a27[2]))
		* Quaternion((fr2_a27["t_l"] as Vector3).normalized(), deg_to_rad(150.0))
	)
	sk.force_update_all_bone_transforms()
	var a27_twist_gate: Dictionary = grip.run_surface_truth_gate()
	_check(
		not bool(a27_twist_gate.get("pass", true)),
		"neg-a27 extreme distal twist rejected by GEOMETRIC gate (%s)"
		% str(a27_twist_gate.get("failures", []))
	)
	# Restore and re-verify.
	grip.apply_now()
	sk.force_update_all_bone_transforms()
	var sg_final: Dictionary = grip.run_surface_truth_gate()
	_check(
		bool(sg_final.get("pass", false)),
		"ground-truth gate PASS restored after negative fixtures (%s)"
		% str(sg_final.get("failures", []))
	)
	_metrics["thumb_surface"] = {
		"nail_out_geom": surf.get("nail_out_geom", -9.0),
		"nail_axis_geom": surf.get("nail_axis_geom", 9.0),
		"pad_in_geom": surf.get("pad_in_geom", -9.0),
		"nail_gap_r": s_nail.get("min_gap_r", 9.0),
		"pad_gap_r": s_pad.get("min_gap_r", 9.0),
		"distal_phys_roll_deg": surf.get("distal_phys_roll_deg", 999.0),
	}

	_metrics["thumb_contour"] = {
		"pad_gap_r": contour.get("pad_gap_r", 9.0),
		"cmc_min_r": c_cmc.get("min_r", 9.0),
		"t2_min_r": c_t2.get("min_r", 9.0),
		"t2_med_r": c_t2.get("med_r", 9.0),
		"t3_min_r": c_t3.get("min_r", 9.0),
		"mid_excess_r": contour.get("mid_excess_r", 9.0),
		"bulge_r": contour.get("bulge_r", 9.0),
		"kink_out_r": contour.get("kink_out_r", 9.0),
	}

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


## Poses the thumb via the grip's VALIDATED anatomical frames (CMC swing
## sigma/phi + twist tau; MCP/IP flexion about the anatomical axes) —
## fixture for anatomical negative cases.
func _pose_thumb_anat_and_eval(
	sk: Skeleton3D, grip, r_mean: float,
	sigma: float, phi: float, tau: float, mcp_deg: float, ip_deg: float
) -> Dictionary:
	var frames: Array = grip._thumb_frames
	var chain: Array = grip._chain_indices["thumb"]
	var fr0: Dictionary = frames[0]
	var swing_axis: Vector3 = (
		(fr0["f_l"] as Vector3) * cos(deg_to_rad(phi))
		+ (fr0["a_l"] as Vector3) * sin(deg_to_rad(phi))
	).normalized()
	var q0: Quaternion = (
		Quaternion(swing_axis, deg_to_rad(sigma))
		* Quaternion(fr0["t_l"], deg_to_rad(tau))
	)
	sk.set_bone_pose_rotation(
		int(chain[0]), (grip._rest_rotations[int(chain[0])] as Quaternion) * q0
	)
	sk.set_bone_pose_rotation(
		int(chain[1]),
		(grip._rest_rotations[int(chain[1])] as Quaternion)
		* Quaternion((frames[1] as Dictionary)["f_l"], deg_to_rad(mcp_deg))
	)
	sk.set_bone_pose_rotation(
		int(chain[2]),
		(grip._rest_rotations[int(chain[2])] as Quaternion)
		* Quaternion((frames[2] as Dictionary)["f_l"], deg_to_rad(ip_deg))
	)
	sk.force_update_all_bone_transforms()
	var m: Dictionary = grip.measure_thumb_now()
	return {"m": m, "gate": grip.evaluate_thumb_wrap(m, r_mean)}


## Poses the thumb chain directly (negative-regression fixtures) and
## evaluates the CURRENT pose against the A2.2 opposition gate.
## Reconstructs the EXACT legacy A2.6 pose: thumb frames rebuilt from the
## SUPERSEDED (mislabeled) A2.5 pad constants, the same empirical flips as
## production, then the A2.6 canonical 25/0/-90/0/90 applied through the
## production pose path. Restores the verified frames before returning.
func _legacy_a26_pose(sk: Skeleton3D, grip) -> Dictionary:
	var chain: Array = grip._chain_indices["thumb"]
	var saved_frames: Array = grip._thumb_frames.duplicate(true)
	var saved_pad = grip._pad_locals["thumb"]
	grip._pad_locals["thumb"] = grip.SUPERSEDED_A25_PAD_MARKER_LOCAL
	for bi in chain:
		sk.reset_bone_pose(int(bi))
	sk.force_update_all_bone_transforms()
	var t3_basis: Basis = (
		sk.global_transform.basis
		* sk.get_bone_global_pose(int(chain[2])).basis
	)
	var old_pad_w: Vector3 = (
		t3_basis * grip.SUPERSEDED_A25_PAD_NORMAL_LOCAL
	).normalized()
	var pts: Array = grip._thumb_points(sk)
	var old_frames: Array = []
	for ji in 3:
		var t_hat: Vector3 = (
			(pts[ji + 1] as Vector3) - (pts[ji] as Vector3)
		).normalized()
		var v_flesh: Vector3 = (
			old_pad_w - t_hat * old_pad_w.dot(t_hat)
		).normalized()
		var f_hat: Vector3 = t_hat.cross(v_flesh).normalized()
		var a_hat: Vector3 = t_hat.cross(f_hat)
		var pose_world: Basis = (
			sk.global_transform.basis
			* sk.get_bone_global_pose(int(chain[ji])).basis
		)
		old_frames.append({
			"t_w": t_hat, "f_w": f_hat, "a_w": a_hat, "flesh_w": v_flesh,
			"t_l": (pose_world.inverse() * t_hat).normalized(),
			"f_l": (pose_world.inverse() * f_hat).normalized(),
			"a_l": (pose_world.inverse() * a_hat).normalized(),
			"flesh_l": (pose_world.inverse() * v_flesh).normalized(),
		})
	grip._thumb_frames = old_frames
	for ji in [1, 2]:
		var bp: float = grip._rest_bend_after_flex(sk, ji, 15.0)
		var bm: float = grip._rest_bend_after_flex(sk, ji, -15.0)
		if bp < bm:
			grip._flip_thumb_frame(ji)
	for bi in chain:
		sk.reset_bone_pose(int(bi))
	sk.force_update_all_bone_transforms()
	var pad0: Vector3 = grip._thumb_points(sk)[3]
	var fr0: Dictionary = grip._thumb_frames[0]
	sk.set_bone_pose_rotation(
		int(chain[0]),
		(grip._rest_rotations[int(chain[0])] as Quaternion)
		* Quaternion(fr0["f_l"], deg_to_rad(15.0))
	)
	sk.force_update_all_bone_transforms()
	var dp: Vector3 = (grip._thumb_points(sk)[3] as Vector3) - pad0
	if dp.dot(fr0["flesh_w"]) < 0.0:
		grip._flip_thumb_frame(0)
	for bi in chain:
		sk.reset_bone_pose(int(bi))
	grip.thumb_anat_override = {
		"sigma": 25.0, "phi": 0.0, "tau": -90.0,
		"flex_mcp": 0.0, "flex_ip": 90.0,
	}
	grip._set_thumb_pose(sk, 0.0, 0.0)
	sk.force_update_all_bone_transforms()
	# Restore the verified frames/marker + canonical pose source; the LEGACY
	# skeleton pose stays applied for the caller's measurement.
	grip._thumb_frames = saved_frames
	grip._pad_locals["thumb"] = saved_pad
	grip.thumb_anat_override = {}
	return {"ok": true}


func _pose_thumb_and_eval(
	sk: Skeleton3D, grip, r_mean: float, s: float, eulers: Array
) -> Dictionary:
	for ji in 3:
		var bi: int = sk.find_bone(str((grip.RIGHT_CHAINS["thumb"] as Array)[ji]))
		var e: Vector3 = eulers[ji]
		var q := Quaternion.from_euler(Vector3(
			s * deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)
		))
		sk.set_bone_pose_rotation(
			bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion() * q
		)
	sk.force_update_all_bone_transforms()
	var m: Dictionary = grip.measure_thumb_now()
	return {"m": m, "gate": grip.evaluate_thumb_wrap(m, r_mean)}


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
