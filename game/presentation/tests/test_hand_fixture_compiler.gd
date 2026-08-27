# A2.10: automatic hand-fixture compilation.
#
# Proves the generic compiler derives the thumb surface evidence from a
# rigged mesh + injected skeleton family alone, agrees with the accepted
# A2.7 hand-authored oracle on the right hand, produces a deterministic
# versioned artifact, and fails closed by name on every malformed input.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Oracle = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)
const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Policy = preload("res://presentation/equipment/power_grip_1h_policy.gd")
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)
const Calibration = preload("res://presentation/equipment/power_grip_1h_calibration.gd")
const CompilerCalibration = preload(
	"res://presentation/equipment/hand_fixture_compiler_calibration.gd"
)
const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const Authority = preload(
	"res://presentation/equipment/hand_fixture_certification_authority.gd"
)

## The compiler must not name or reach any specific unit, provider or bone.
const FORBIDDEN_IN_COMPILER := [
	"uthana", "Uthana", "mixamorig", "mixamo_52", "wooden_club", "res://assets/",
	"brightness", "saturation", "albedo", "5486", "3302", "blender",
]

var _total := 0
var _any_fail := false
var _art_right: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_compiler_has_no_unit_or_texture_dependency()
	var ctx: Dictionary = await _spawn()
	_test_compiles_both_sides(ctx)
	_test_right_matches_oracle(ctx)
	_test_left_is_independently_derived(ctx)
	_test_artifact_and_determinism(ctx)
	await _test_artifact_verification_negatives(ctx)
	await _test_skeleton_negatives(ctx)
	_test_anatomical_direction_negatives(ctx)
	await _test_tampered_patch_negatives(ctx)
	print("test_hand_fixture_compiler: %d checks, %s" % [_total, "FAIL" if _any_fail else "OK"])
	quit(1 if _any_fail else 0)


func _spawn() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	host.add_child(model)
	var character: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(character)
	await process_frame
	var skel: Skeleton3D = Skinning.find_skeleton(character)
	skel.force_update_all_bone_transforms()
	return {
		"host": host,
		"character": character,
		"skeleton": skel,
		"mesh": Skinning.find_skinned_mesh(character),
	}


## The compiler is generic core: it may not mention a unit, a provider, a
## bone-name convention or any texture/brightness signal.
func _test_compiler_has_no_unit_or_texture_dependency() -> void:
	for path in [
		"res://presentation/equipment/hand_fixture_compiler.gd",
		"res://presentation/equipment/compiled_hand_fixture.gd",
	]:
		var f := FileAccess.open(path, FileAccess.READ)
		_check(f != null, "readable %s" % path.get_file())
		if f == null:
			continue
		var src: String = f.get_as_text()
		for token in FORBIDDEN_IN_COMPILER:
			# The prose comment explaining what is NOT used is allowed to
			# name the rejected signals; code must not sample them.
			var code_only := ""
			for line in src.split("\n"):
				var s := str(line).strip_edges()
				if s.begins_with("#"):
					continue
				code_only += s + "\n"
			_check(
				not code_only.contains(str(token)),
				"%s code has no '%s'" % [path.get_file(), token]
			)


func _test_compiles_both_sides(ctx: Dictionary) -> void:
	var art: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
	)
	_art_right = art
	_check(str(art.get("compiler_version", "")) == "hand_fixture_compiler_v3", "compiler version")
	_check(str(art.get("schema", "")) == "hand_fixture_evidence_v3", "artifact schema")
	_check(str(art.get("family_id", "")) == "mixamo_52_humanoid", "injected family recorded")
	_check(str(art.get("family_version", "")) == str(Family.FAMILY_VERSION), "family version")
	_check(
		str(art.get("family_bone_map_digest", "")).length() == 32,
		"resolved bone map digest recorded"
	)
	_check(
		str(art.get("calibration_id", "")) == str(CompilerCalibration.CALIBRATION_ID)
		and str(art.get("calibration_version", ""))
			== str(CompilerCalibration.CALIBRATION_VERSION),
		"CALIBRATING compiler profile recorded in the artifact"
	)
	_check(
		str(art.get("acceptance_scope", "")) == "compiler_surface_evidence_only",
		"a compiler PASS declares itself as evidence only, not acceptance"
	)
	_check(
		str(art.get("source_geometry_sha256", "")).length() == 64,
		"source geometry sha256 recorded"
	)
	_check(
		str(art.get("source_rig_sha256", "")).length() == 64,
		"source rig/deformation sha256 recorded"
	)
	# The RIGHT hand -- the accepted A2.7 reference -- must compile.
	var right: Dictionary = (art["sides"] as Dictionary)["right"]
	_check(
		bool(right.get("compiled", false)),
		"right compiled (%s %s)" % [right.get("error_class", ""), right.get("detail", "")]
	)
	# The LEFT hand must be CLASSIFIED, not guessed: its volar pad has no
	# stable geometric separation on this mesh, so picking a "best" pad
	# candidate anyway is exactly the manual judgement being removed.
	var left: Dictionary = (art["sides"] as Dictionary)["left"]
	_check(
		not bool(left.get("compiled", false)),
		"left is not silently compiled from ambiguous geometry"
	)
	_check(
		str(left.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"left fails closed as PAD_PATCH_AMBIGUOUS (%s)" % str(left.get("error_class", ""))
	)
	print("A2_10_LEFT_CLASSIFIED %s: %s" % [left.get("error_class", ""), left.get("detail", "")])
	_check(not bool(art.get("ok", true)), "artifact reports that not every side certified")
	for side in ["right"]:
		var d: Dictionary = (art["sides"] as Dictionary)[side]
		var ev: Dictionary = d["evidence"]
		_check(
			(ev["classification_signals"] as Array).has("skin_weight_dominance")
			and (ev["classification_signals"] as Array).has("topology")
			and (ev["classification_signals"] as Array).has("anatomical_direction"),
			"%s classification carried by weights/topology/anatomy" % side
		)
		_check(
			(ev["texture_signals_used"] as Array).is_empty(),
			"%s used no texture/brightness signal" % side
		)
		_check(int(ev["components"]) >= 1, "%s found surface components (%d)" % [side, ev["components"]])
		var conf: Dictionary = d["confidence"]
		for k in ["component", "nail", "pad", "opposition", "bone_weight", "overall"]:
			_check(conf.has(k), "%s confidence has %s" % [side, k])
		_check(float(conf["overall"]) >= 0.35, "%s overall confidence %.4f" % [side, conf["overall"]])
		print("A2_10_%s_CONFIDENCE %s" % [side.to_upper(), str(conf)])
		print("A2_10_%s_EVIDENCE tip=%d cand=%d comps=%d qualified=%d nail_margin=%.4f pad_margin=%.4f" % [
			side.to_upper(), ev["thumb_tip_triangles"], ev["candidate_triangles"],
			ev["components"], ev["qualified_components"], ev["nail_margin"], ev["pad_margin"],
		])


## The decisive oracle comparison: on the accepted right hand the compiler
## must find the SAME anatomical plates the A2.7 audit authored by hand.
func _test_right_matches_oracle(ctx: Dictionary) -> void:
	var d: Dictionary = (_art_right["sides"] as Dictionary)["right"]
	if not bool(d.get("compiled", false)):
		_check(false, "right side compiled for oracle comparison")
		return
	var oracle: Dictionary = Oracle.right_surface()
	var o_nail := _keys(oracle["nail_tris"])
	var o_pad := _keys(oracle["pad_tris"])
	var c_nail := _keys(d["nail_tris"])
	var c_pad := _keys(d["pad_tris"])
	_check(c_nail == o_nail, "right NAIL triangle set equals the A2.7 oracle (%d vs %d)" % [
		(d["nail_tris"] as Array).size(), (oracle["nail_tris"] as Array).size()
	])
	_check(c_pad == o_pad, "right PAD triangle set equals the A2.7 oracle (%d vs %d)" % [
		(d["pad_tris"] as Array).size(), (oracle["pad_tris"] as Array).size()
	])
	var on: Vector3 = oracle["nail_normal_local"]
	var op: Vector3 = oracle["pad_normal_local"]
	var cn: Vector3 = d["nail_normal_local"]
	var cp: Vector3 = d["pad_normal_local"]
	_check(cn.dot(on) > 0.999, "right nail rest normal matches oracle (dot %.6f)" % cn.dot(on))
	_check(cp.dot(op) > 0.999, "right pad rest normal matches oracle (dot %.6f)" % cp.dot(op))
	_check(
		absf(float(d["rest_nail_pad_dot"]) - float(oracle["rest_nail_pad_dot"])) < 0.02,
		"right rest nail.pad dot %.5f vs oracle %.5f"
			% [d["rest_nail_pad_dot"], oracle["rest_nail_pad_dot"]]
	)
	var pm: Vector3 = d["pad_marker_local"]
	var opm: Vector3 = oracle["pad_marker_local"]
	_check(
		pm.distance_to(opm) < 0.004,
		"right pad marker within a millimetre of oracle (%.6f)" % pm.distance_to(opm)
	)
	# Winding must be rest-anchored, stored, and identical to the oracle.
	for rec in (d["nail_tris"] as Array) + (d["pad_tris"] as Array):
		_check(
			absf(float((rec as Dictionary)["flip"]) - Oracle.PATCH_WINDING_FLIP) < 1e-9,
			"compiled winding flip matches the rest-anchored oracle convention"
		)
		break
	print("A2_10_RIGHT_ORACLE nail=%s pad=%s nail_dot=%.6f pad_dot=%.6f marker_d=%.6f" % [
		str(c_nail == o_nail), str(c_pad == o_pad), cn.dot(on), cp.dot(op), pm.distance_to(opm)
	])


## The left hand must be derived from the left hand alone, and its failure
## must be a real classification of the left geometry -- never a copy of the
## right hand, and never the right hand's answer relabelled.
func _test_left_is_independently_derived(ctx: Dictionary) -> void:
	var single: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["left"], Skinning
	)
	var l: Dictionary = (single["sides"] as Dictionary)["left"]
	_check(
		not bool(l.get("compiled", false)),
		"left alone reaches the same classified outcome"
	)
	_check(
		str(l.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"left classification is independent of whether the right was compiled"
	)
	# The left frame is derived from left bones: its own radial direction
	# must point the opposite way in world space from the right hand's.
	var lf: Dictionary = HandProfile.derive_frame(
		ctx["skeleton"], Family, Family.bone_map("left"), "left", false
	)
	var rf: Dictionary = HandProfile.derive_frame(
		ctx["skeleton"], Family, Family.bone_map("right"), "right", false
	)
	_check(bool(lf.get("ok", false)) and bool(rf.get("ok", false)), "both frames derive")
	var lr: Vector3 = lf["radial"]
	var rr: Vector3 = rf["radial"]
	_check(
		float(lf.get("det", 0.0)) > 0.99 and float(rf.get("det", 0.0)) > 0.99,
		"both hand bases are det +1 on both sides"
	)
	# Each frame is built from its own hand's bones: the two palms sit on
	# opposite sides of the body and the volar normals are mirrored, so
	# neither frame can be the other one relabelled.
	var lc: Vector3 = lf["palm_centre"]
	var rc: Vector3 = rf["palm_centre"]
	_check(lc.distance_to(rc) > 0.05, "palm centres are distinct (%.4f)" % lc.distance_to(rc))
	# Chirality is carried by the det +1 basis, not by a sign convention:
	# in an A-pose both palms face the same way, so the anti-copy evidence
	# is that each frame resolves its own hand's bones.
	_check(
		not (lf["volar"] as Vector3).is_equal_approx(rf["volar"] as Vector3)
		or not lc.is_equal_approx(rc),
		"the two frames are not the same frame (radial dot %.4f)" % lr.dot(rr)
	)
	# The left compile path resolved LEFT bones, never the right ones.
	var lt3: int = ctx["skeleton"].find_bone(
		str((Family.bone_map("left")["thumb"] as Array)[2])
	)
	var rt3: int = ctx["skeleton"].find_bone(
		str((Family.bone_map("right")["thumb"] as Array)[2])
	)
	_check(lt3 >= 0 and rt3 >= 0 and lt3 != rt3, "left and right distal thumbs are distinct bones")
	# The authored left reference does NOT follow the right hand's
	# anatomical convention: its nail plate faces ulnar rather than radial.
	# Reporting that divergence is the point; masking it would hide left T2
	# evidence.
	var authored_left: Dictionary = Oracle.left_surface(
		ctx["character"], ctx["skeleton"], Family.bone_map("left")
	)
	_check(
		bool(authored_left.get("compiled", false)),
		"authored left reference still compiles through the injected bone map"
	)
	# The authored reference must no longer carry a bone-naming convention.
	var of := FileAccess.open(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd",
		FileAccess.READ
	)
	_check(of != null, "authored fixture readable")
	if of != null:
		_check(
			not of.get_as_text().contains("mixamorig"),
			"authored fixture has no hardcoded mixamorig_* bone names left"
		)
	var an: Vector3 = authored_left["nail_normal_local"]
	var t3: int = ctx["skeleton"].find_bone(str((Family.bone_map("left")["thumb"] as Array)[2]))
	var t3_inv: Basis = (
		ctx["skeleton"].global_transform.basis
		* ctx["skeleton"].get_bone_global_pose(t3).basis
	).inverse()
	var radial_t3: Vector3 = (t3_inv * lr).normalized()
	var authored_radial_dot: float = an.dot(radial_t3)
	print("A2_10_LEFT_AUTHORED_DIVERGENCE authored_nail.radial=%.4f" % authored_radial_dot)
	_check(
		authored_radial_dot < 0.0,
		"authored left nail faces ULNAR, i.e. not the right hand's convention (%.4f)"
			% authored_radial_dot
	)


func _test_artifact_and_determinism(ctx: Dictionary) -> void:
	var again: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
	)
	_check(
		str(again.get("content_hash", "")) == str(_art_right.get("content_hash", "")),
		"recompiling the same mesh gives the same content hash"
	)
	_check(str(_art_right.get("content_hash", "")).length() == 64, "content hash is a sha256")
	_check(
		Compiler.content_hash(_art_right) == str(_art_right["content_hash"]),
		"content hash covers the artifact payload"
	)
	# Mutating any compiled value must change the hash.
	var tampered: Dictionary = _art_right.duplicate(true)
	((tampered["sides"] as Dictionary)["right"] as Dictionary)["rest_nail_pad_dot"] = 0.5
	_check(
		Compiler.content_hash(tampered) != str(_art_right["content_hash"]),
		"tampering with compiled data invalidates the content hash"
	)
	# Live source identities must match what the artifact claims — both of
	# them, because geometry alone cannot vouch for bone-local markers.
	_check(
		Compiler.geometry_identity(ctx["mesh"]) == str(_art_right["source_geometry_sha256"]),
		"artifact geometry identity matches the live mesh"
	)
	_check(
		Compiler.rig_identity(ctx["mesh"], ctx["skeleton"])
			== str(_art_right["source_rig_sha256"]),
		"artifact rig identity matches the live rig"
	)
	_check(
		str(_art_right["source_geometry_sha256"]) != str(_art_right["source_rig_sha256"]),
		"geometry and rig identity are distinct hashes, not one value under two names"
	)


func _test_artifact_verification_negatives(ctx: Dictionary) -> void:
	await process_frame
	# Pose calibration is interaction-policy data, injected separately from
	# the compiled surface evidence. It must stay numerically identical to
	# the accepted A2.7 reference, so the two cannot drift apart.
	var calib: Dictionary = Calibration.payload()
	_check(
		Calibration.CANON_THUMB_ANAT == Oracle.CANON_THUMB_ANAT,
		"profile calibration pins the A2.7 right thumb column"
	)
	_check(
		Calibration.CANON_THUMB_ANAT_LEFT == Oracle.CANON_THUMB_ANAT_LEFT,
		"profile calibration pins the A2.8 left thumb column"
	)
	_check(
		Calibration.CANON_FLEX_DEG == Oracle.CANON_FLEX_DEG,
		"profile calibration pins the authored finger flexion"
	)
	_check(
		Calibration.CANON_THUMB_ANAT != Oracle.REJECTED_A26_THUMB_ANAT,
		"profile calibration is not the rejected A2.6 tau = -90 pose"
	)
	# A2.12: the runtime loader accepts CERTIFICATES, not compiled evidence.
	# The compiler's own output is deliberately not loadable.
	_check(
		str(CompiledFixture.from_certified_artifact(
			_art_right, calib, "u", _expect()
		).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"compiled evidence is not a runtime fixture (compiler PASS is not a licence)"
	)
	# The REAL acceptance chain, run here on the real asset (A2.13a): there is
	# no way for this test to claim a step ran.
	var certified: Dictionary = await _certify(["right"])
	_check(
		bool(certified.get("ok", false)),
		"the real acceptance chain certifies the asset (%s at %s)"
			% [str(certified.get("error_class", "")), str(certified.get("stage", ""))]
	)
	if not bool(certified.get("ok", false)):
		return
	var cert: Dictionary = certified.get("certification", {})
	_check(
		str((cert.get("evidence", {}) as Dictionary).get("content_hash", ""))
			== str(_art_right.get("content_hash", "")),
		"the chain compiled byte-identical evidence to this process's own compile"
	)
	var good: Dictionary = CompiledFixture.from_certified_artifact(
		cert, calib, "compiled_unit", _expect(), ["right"]
	)
	_check(bool(good.get("ok", false)), "valid certificate loads (%s)" % str(good.get("error_class", "")))
	# Another rig.
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, calib, "compiled_unit", _expect({"rig_sha256": "0".repeat(64)})
		).get("error_class", "")) == "FIXTURE_RIG_HASH_MISMATCH",
		"a certificate for another rig fails FIXTURE_RIG_HASH_MISMATCH"
	)
	# Another geometry.
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, calib, "compiled_unit", _expect({"geometry_sha256": "0".repeat(64)})
		).get("error_class", "")) == "FIXTURE_GEOMETRY_HASH_MISMATCH",
		"a certificate for another geometry fails FIXTURE_GEOMETRY_HASH_MISMATCH"
	)
	# Another family, and another family VERSION of the same family.
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, calib, "compiled_unit", _expect({"family_id": "some_other_family_v2"})
		).get("error_class", "")) == "FIXTURE_FAMILY_MISMATCH",
		"a certificate from another family fails FIXTURE_FAMILY_MISMATCH"
	)
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, calib, "compiled_unit", _expect({"family_version": "999"})
		).get("error_class", "")) == "FIXTURE_FAMILY_VERSION_MISMATCH",
		"a certificate from another family VERSION fails FIXTURE_FAMILY_VERSION_MISMATCH"
	)
	# Empty expectations must not be a way to switch a check off; each is
	# itself a refusal.
	for omitted in [
		["rig_sha256", "FIXTURE_MESH_IDENTITY_REQUIRED"],
		["geometry_sha256", "FIXTURE_MESH_IDENTITY_REQUIRED"],
		["family_id", "FIXTURE_FAMILY_MISMATCH"],
		["family_version", "FIXTURE_FAMILY_VERSION_MISMATCH"],
	]:
		var blank: Dictionary = _expect()
		blank[str(omitted[0])] = ""
		_check(
			str(CompiledFixture.from_certified_artifact(cert, calib, "u", blank)
				.get("error_class", "")) == str(omitted[1]),
			"an empty expected %s is a refusal, not a skipped check" % omitted[0]
		)
	# Unsupported evidence schema, inside an otherwise valid certificate.
	_check(
		str(CompiledFixture.from_certified_artifact(
			_forge(cert, {"schema": "hand_fixture_evidence_v99"}), calib, "u", _expect()
		).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"a certificate that is not this certification schema is refused"
	)
	# Evidence from an older compiler must not slip past the loader, even in a
	# correctly re-hashed and re-certified envelope.
	var old_evidence: Dictionary = _art_right.duplicate(true)
	old_evidence["compiler_version"] = "hand_fixture_compiler_v1"
	old_evidence["content_hash"] = Compiler.content_hash(old_evidence)
	_check(
		str(CompiledFixture.from_certified_artifact(
			_reseal(cert, old_evidence), calib, "u", _expect()
		).get("error_class", "")) == "FIXTURE_SCHEMA_UNSUPPORTED",
		"correctly re-certified evidence from an older compiler is still refused"
	)
	# Silently edited payload.
	var edited: Dictionary = _art_right.duplicate(true)
	((edited["sides"] as Dictionary)["right"] as Dictionary)["rest_nail_pad_dot"] = 0.9
	_check(
		not bool(CompiledFixture.from_certified_artifact(
			_swap_evidence(cert, edited), calib, "u", _expect()
		).get("ok", false)),
		"edited evidence inside a certificate is rejected by the content hash"
	)
	# Diagnostics are inside the identity too: editing confidence invalidates.
	var edited_conf: Dictionary = _art_right.duplicate(true)
	(((edited_conf["sides"] as Dictionary)["right"] as Dictionary)["confidence"]
		as Dictionary)["overall"] = 0.99
	_check(
		not bool(CompiledFixture.from_certified_artifact(
			_swap_evidence(cert, edited_conf), calib, "u", _expect()
		).get("ok", false)),
		"editing the acceptance confidence invalidates the content hash"
	)
	# Missing calibration must fail closed, never default.
	_check(
		str(CompiledFixture.from_certified_artifact(cert, {}, "u", _expect())
			.get("error_class", "")) == "FIXTURE_SCHEMA_UNSUPPORTED",
		"missing pose calibration fails closed instead of defaulting"
	)
	# Stale live rig check.
	var fx = good["fixture"]
	_check(
		bool(fx.verify_against_rig(ctx["mesh"], ctx["skeleton"]).get("ok", false)),
		"live rig verify ok"
	)
	var other_mi := MeshInstance3D.new()
	other_mi.mesh = BoxMesh.new()
	_check(
		str(fx.verify_against_rig(other_mi, ctx["skeleton"]).get("error_class", ""))
			== "FIXTURE_GEOMETRY_HASH_MISMATCH",
		"a different live mesh fails FIXTURE_GEOMETRY_HASH_MISMATCH"
	)
	_check(
		str(fx.verify_against_rig(ctx["mesh"], null).get("error_class", ""))
			== "FIXTURE_LIVE_RIG_MISSING",
		"verification without a live skeleton fails closed"
	)
	other_mi.free()
	# The compiled fixture satisfies the generic profile contract.
	var compiled_profile: Dictionary = HandProfile.compile(
		ctx["skeleton"], ctx["character"], "right", fx, Family, Skinning
	)
	_check(
		bool(compiled_profile.get("ok", false)),
		"generic profile compiles against the COMPILED fixture (%s)"
			% str(compiled_profile.get("failures", []))
	)
	_check(
		str(compiled_profile.get("fixture_schema", "")) == "hand_fixture_evidence_v3",
		"profile records the compiled artifact schema"
	)


## Skeletons the compiler must classify rather than crash on.
func _test_skeleton_negatives(ctx: Dictionary) -> void:
	# No fingers at all (a Meshy-style fingerless rig).
	var fingerless := Skeleton3D.new()
	fingerless.add_bone("Hips")
	fingerless.add_bone("RightHand")
	root.add_child(fingerless)
	var r1: Dictionary = Compiler.compile(ctx["character"], fingerless, Family, ["right"], Skinning)
	var s1: Dictionary = (r1["sides"] as Dictionary)["right"]
	_check(
		str(s1.get("error_class", "")) == "HAND_SKELETON_INCOMPLETE",
		"fingerless rig classified HAND_SKELETON_INCOMPLETE (%s)" % str(s1.get("error_class", ""))
	)
	_check(not bool(r1.get("ok", true)), "fingerless artifact not ok")
	# Fingers but no thumb chain.
	var no_thumb := Skeleton3D.new()
	var names: Array = ["RightHand"]
	var bm: Dictionary = Family.bone_map("right")
	for digit in ["index", "middle", "ring", "pinky"]:
		for bn in (bm[digit] as Array):
			names.append(str(bn))
	for n in names:
		no_thumb.add_bone(str(n))
	root.add_child(no_thumb)
	var r2: Dictionary = Compiler.compile(ctx["character"], no_thumb, Family, ["right"], Skinning)
	_check(
		str(((r2["sides"] as Dictionary)["right"] as Dictionary).get("error_class", ""))
			== "HAND_SKELETON_INCOMPLETE",
		"missing thumb chain classified HAND_SKELETON_INCOMPLETE"
	)
	# No family injected at all.
	_check(
		str(Compiler.compile(ctx["character"], ctx["skeleton"], null, ["right"], Skinning)
			.get("error_class", "")) == "FIXTURE_FAMILY_MISMATCH",
		"missing family fails FIXTURE_FAMILY_MISMATCH"
	)
	# A family whose bone names do not exist on this skeleton.
	var r3: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], WrongFamily, ["right"], Skinning
	)
	_check(
		str(((r3["sides"] as Dictionary)["right"] as Dictionary).get("error_class", ""))
			== "HAND_SKELETON_INCOMPLETE",
		"wrong family profile classified HAND_SKELETON_INCOMPLETE"
	)
	# No skeleton.
	_check(
		str(Compiler.compile(ctx["character"], null, Family, ["right"], Skinning)
			.get("error_class", "")) == "HAND_SKELETON_INCOMPLETE",
		"missing skeleton fails HAND_SKELETON_INCOMPLETE"
	)
	# No skinned mesh.
	var bare := Node3D.new()
	root.add_child(bare)
	_check(
		str(Compiler.compile(bare, ctx["skeleton"], Family, ["right"], Skinning)
			.get("error_class", "")) == "THUMB_SURFACE_CANDIDATES_MISSING",
		"missing skinned mesh fails THUMB_SURFACE_CANDIDATES_MISSING"
	)
	fingerless.queue_free()
	no_thumb.queue_free()
	bare.queue_free()
	await process_frame


## Negatives that attack the ANATOMICAL derivation rather than the schema.
## Every case perturbs an injected input on the real rig, so the compiler is
## forced to reach a real geometric conclusion instead of a lookup.
func _test_anatomical_direction_negatives(ctx: Dictionary) -> void:
	# Radial and ulnar swapped: the index side is now derived as the pinky
	# side, so the dorsal-radial nail bisector points at the wrong flank.
	var swapped: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], SwappedRadialFamily, ["right"], Skinning
	)
	var sw: Dictionary = (swapped["sides"] as Dictionary)["right"]
	_check(
		not bool(sw.get("compiled", false)),
		"radial/ulnar swapped does not silently compile"
	)
	print("A2_10_NEG_RADIAL_SWAP %s: %s" % [sw.get("error_class", ""), sw.get("detail", "")])
	_check(
		str(sw.get("error_class", "")) in [
			"NAIL_PATCH_AMBIGUOUS", "NAIL_PAD_NOT_OPPOSED", "FIXTURE_CONFIDENCE_TOO_LOW",
			"THUMB_SURFACE_CANDIDATES_MISSING", "HAND_VOLAR_AMBIGUOUS",
			"HAND_CHIRALITY_AMBIGUOUS",
		],
		"radial/ulnar swap is classified by name (%s)" % str(sw.get("error_class", ""))
	)
	# The thumb chain mapped onto bones that carry no thumb-tip skin: the
	# bone-weight evidence must be missing rather than approximated.
	var offbone: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], OffThumbFamily, ["right"], Skinning
	)
	var ob: Dictionary = (offbone["sides"] as Dictionary)["right"]
	_check(
		not bool(ob.get("compiled", false)),
		"a thumb chain with no distal skin does not compile"
	)
	print("A2_10_NEG_LOW_DOMINANCE %s" % ob.get("error_class", ""))
	_check(
		str(ob.get("error_class", "")) in [
			"PATCH_BONE_WEIGHT_INSUFFICIENT", "THUMB_SURFACE_CANDIDATES_MISSING",
			"FIXTURE_CONFIDENCE_TOO_LOW", "HAND_SKELETON_INCOMPLETE",
		],
		"insufficient bone dominance is classified by name (%s)" % str(ob.get("error_class", ""))
	)
	# Volar derived from the wrong hand's thumb column must be caught by the
	# skinned-flesh dual-check instead of inverting the pad.
	var crossed: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], CrossedThumbFamily, ["right"], Skinning
	)
	var cr: Dictionary = (crossed["sides"] as Dictionary)["right"]
	_check(
		not bool(cr.get("compiled", false)),
		"a volar direction taken from the other hand does not compile"
	)
	print("A2_10_NEG_VOLAR %s" % cr.get("error_class", ""))
	_check(
		str(cr.get("error_class", "")) in [
			"HAND_VOLAR_AMBIGUOUS", "HAND_FRAME_UNDERIVABLE", "HAND_CHIRALITY_AMBIGUOUS",
			"NAIL_PATCH_AMBIGUOUS", "PAD_PATCH_AMBIGUOUS", "NAIL_PAD_NOT_OPPOSED",
			"THUMB_SURFACE_CANDIDATES_MISSING", "HAND_SKELETON_INCOMPLETE",
		],
		"a crossed-side thumb column is classified by name (%s)" % str(cr.get("error_class", ""))
	)
	# A Meshy-style fingerless production rig: ~24 bones, no digits at all.
	var meshy := Skeleton3D.new()
	for n in [
		"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
		"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
		"HeadTop_End", "Root",
	]:
		meshy.add_bone(str(n))
	root.add_child(meshy)
	_check(meshy.get_bone_count() == 24, "meshy-style rig has 24 bones")
	var mr: Dictionary = Compiler.compile(ctx["character"], meshy, Family, ["right", "left"], Skinning)
	for side in ["right", "left"]:
		_check(
			str(((mr["sides"] as Dictionary)[side] as Dictionary).get("error_class", ""))
				== "HAND_SKELETON_INCOMPLETE",
			"fingerless 24-bone rig %s is CLASSIFIED, not crashed or passed" % side
		)
	_check(not bool(mr.get("ok", true)), "fingerless 24-bone rig is never accepted")
	meshy.queue_free()
	# Deterministic candidate order: the serialized patches must be
	# byte-identical between runs, not merely the same set.
	var a: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right"], Skinning
	)
	var b: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right"], Skinning
	)
	_check(
		str(((a["sides"] as Dictionary)["right"] as Dictionary)["nail_tris"])
			== str(((b["sides"] as Dictionary)["right"] as Dictionary)["nail_tris"]),
		"compiled patch order is deterministic, not traversal-dependent"
	)


## Negatives that attack the COMPILED EVIDENCE: a tampered artifact must be
## caught by the engine's bind sanity and surface ground truth, so a
## compiler PASS can never launder a bad grip.
func _test_tampered_patch_negatives(ctx: Dictionary) -> void:
	var calib: Dictionary = Calibration.payload()
	var right: Dictionary = (_art_right["sides"] as Dictionary)["right"]
	# 1. Inverted winding on every patch triangle.
	var flipped: Dictionary = _art_right.duplicate(true)
	var fr: Dictionary = (flipped["sides"] as Dictionary)["right"]
	for key in ["nail_tris", "pad_tris"]:
		for rec in (fr[key] as Array):
			(rec as Dictionary)["flip"] = -float((rec as Dictionary)["flip"])
	flipped["content_hash"] = Compiler.content_hash(flipped)
	await _check_assembler_refuses(
		ctx, flipped, calib, "inverted patch winding", "GRIP_PATCH_BIND_FAILED", "thumb_true_nail_patch_missing"
	)
	# 2. Nail and pad swapped: both patches are real, well-bound, dominant
	#    triangles, so only the anatomical meaning is wrong. The nail must
	#    never be accepted as the handle contact patch.
	var swapped: Dictionary = _art_right.duplicate(true)
	var sr: Dictionary = (swapped["sides"] as Dictionary)["right"]
	var keep_nail = (sr["nail_tris"] as Array).duplicate(true)
	sr["nail_tris"] = (sr["pad_tris"] as Array).duplicate(true)
	sr["pad_tris"] = keep_nail
	var kn: Vector3 = sr["nail_normal_local"]
	sr["nail_normal_local"] = sr["pad_normal_local"]
	sr["pad_normal_local"] = kn
	swapped["content_hash"] = Compiler.content_hash(swapped)
	await _check_assembler_refuses(
		ctx, swapped, calib, "nail and pad swapped", "THUMB_OPPOSITION_GATE_FAILED", "thumb_opposition_gate_failed"
	)
	# 3. Both plates declared on the same side: the pad relabelled as the
	#    nail, which is what a brightness-only nail guess produces when the
	#    nail texture is weak, as it is on this reference.
	var same: Dictionary = _art_right.duplicate(true)
	var sm: Dictionary = (same["sides"] as Dictionary)["right"]
	sm["nail_tris"] = (sm["pad_tris"] as Array).duplicate(true)
	sm["nail_normal_local"] = sm["pad_normal_local"]
	sm["rest_nail_pad_dot"] = 1.0
	same["content_hash"] = Compiler.content_hash(same)
	await _check_assembler_refuses(
		ctx, same, calib, "nail and pad on the same side", "THUMB_OPPOSITION_GATE_FAILED", "thumb_opposition_gate_failed"
	)
	# 4. An artifact whose right side actually holds the OTHER hand's data.
	var other_hand: Dictionary = _art_right.duplicate(true)
	var authored_left: Dictionary = Oracle.left_surface(
		ctx["character"], ctx["skeleton"], Family.bone_map("left")
	)
	var oh: Dictionary = (other_hand["sides"] as Dictionary)["right"]
	oh["nail_tris"] = authored_left["nail_tris"]
	oh["pad_tris"] = authored_left["pad_tris"]
	oh["nail_normal_local"] = authored_left["nail_normal_local"]
	oh["pad_normal_local"] = authored_left["pad_normal_local"]
	oh["rest_nail_pad_dot"] = authored_left["rest_nail_pad_dot"]
	other_hand["content_hash"] = Compiler.content_hash(other_hand)
	await _check_assembler_refuses(
		ctx, other_hand, calib, "the other hand's patches", "GRIP_PATCH_BIND_FAILED", "thumb_true_nail_patch_missing"
	)
	# 5. Triangle indices that are not skin-bound to the distal thumb.
	var unbound: Dictionary = _art_right.duplicate(true)
	var ur: Dictionary = (unbound["sides"] as Dictionary)["right"]
	ur["nail_tris"] = [{"si": 0, "i": [0, 1, 2], "uvc": Vector2(0.5, 0.5), "flip": -1.0}]
	unbound["content_hash"] = Compiler.content_hash(unbound)
	await _check_assembler_refuses(
		ctx, unbound, calib, "patch triangles outside the distal thumb", "GRIP_PATCH_BIND_FAILED", "thumb_true_nail_patch_missing"
	)
	# The untampered compiled evidence still assembles through the very same
	# probe, so the negatives above are not passing for an unrelated reason and
	# the probe itself is not simply broken.
	var clean: Dictionary = await _assemble_fails(ctx, _art_right, calib)
	_check(
		str(clean["stage"]) == "assembler",
		"the control run reaches the assembler too (stage %s)" % str(clean["stage"])
	)
	_check(
		not bool(clean["refused"]),
		"the untampered compiled evidence still assembles successfully (%s)"
			% str(clean.get("error_class", ""))
	)
	_check(
		(right["nail_tris"] as Array).size() == 4 and (right["pad_tris"] as Array).size() == 10,
		"reference compiled patch counts unchanged after the negatives"
	)


## Assemble the real rig with the compiled SURFACE evidence for the right hand
## replaced by `artifact`'s, and report WHICH STAGE the run reached.
##
## A2.13a — WHY THIS NO LONGER MINTS A CERTIFICATE FOR TAMPERED EVIDENCE. The
## old helper certified the tampered artifact itself and returned `true` — "the
## grip was refused" — as soon as certification OR loading refused it. A test
## about the ASSEMBLER could therefore go green without the assembler ever
## being called, and after A2.13a certification refuses tampered evidence
## outright, which would have made every negative below vacuously true.
##
## The probe is now built so that the assembler is the only thing that CAN
## refuse it: a real certificate for the real asset is minted by the real
## authority, loaded through the real runtime loader, and only then is the
## in-memory surface evidence swapped. Identity, contract, certificate and live
## rig binding are all genuine and unchanged, so `stage` is `assembler` unless
## something is wrong with the probe itself — which the callers assert.
func _assemble_fails(ctx: Dictionary, artifact: Dictionary, calib: Dictionary) -> Dictionary:
	var certified: Dictionary = await _certify(["right"])
	if not bool(certified.get("ok", false)):
		return {
			"stage": "certification",
			"refused": true,
			"error_class": str(certified.get("error_class", "")),
		}
	var loaded: Dictionary = CompiledFixture.from_certified_artifact(
		certified["certification"],
		calib,
		"tamper_probe",
		_expect(),
		["right"]
	)
	if not bool(loaded.get("ok", false)):
		return {
			"stage": "certificate_load",
			"refused": true,
			"error_class": str(loaded.get("error_class", "")),
		}
	var fixture = loaded["fixture"]
	# The one thing under test: what the fixture reports as the compiled thumb
	# surface for the right hand.
	(fixture.artifact["sides"] as Dictionary)["right"] = (
		(artifact.get("sides", {}) as Dictionary).get("right", {}) as Dictionary
	).duplicate(true)
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	host.add_child(model)
	var character: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(character)
	await process_frame
	var deps: Dictionary = Composition.dependencies()
	deps["fixture"] = fixture
	var asm: Node = Assembler.new()
	asm.configure_dependencies(deps)
	host.add_child(asm)
	var res: Dictionary = asm.assemble(character, "right")
	var binding: Dictionary = asm.mesh_binding()
	var out := {
		# The assembler was reached only if it got as far as binding the
		# fixture to the live rig; anything earlier is a broken probe.
		"stage": "assembler" if bool(binding.get("verified", false)) else "rig_binding",
		"refused": not bool(res.get("ok", false)),
		"error_class": _grip_error_class(res),
		"reason": str(res.get("reason", "")),
	}
	host.queue_free()
	await process_frame
	return out


## Assert that the ASSEMBLER — not certification, not the loader — refused this
## surface evidence, with the named class. A run that never reached the
## assembler is a failure of the test, not a pass.
func _check_assembler_refuses(
	ctx: Dictionary,
	artifact: Dictionary,
	calib: Dictionary,
	label: String,
	expected: String,
	expected_reason: String
) -> void:
	var out: Dictionary = await _assemble_fails(ctx, artifact, calib)
	_check(
		str(out["stage"]) == "assembler",
		"%s: the probe reached the assembler (stage %s / %s)"
			% [label, out["stage"], str(out.get("error_class", ""))]
	)
	_check(bool(out["refused"]), "%s: the assembler refused it" % label)
	_check(
		str(out.get("error_class", "")) == expected,
		"%s: refused as %s (got %s)" % [label, expected, str(out.get("error_class", ""))]
	)
	_check(
		str(out.get("reason", "")) == expected_reason,
		"%s: for the named reason %s (got %s)"
			% [label, expected_reason, str(out.get("reason", ""))]
	)


## The class that names WHY the grip was refused: the engine's own class when
## the grip modifier rejected the surface, the assembler's otherwise.
func _grip_error_class(result: Dictionary) -> String:
	var grip: Dictionary = result.get("grip", {})
	var nested: String = str(grip.get("error_class", ""))
	if not nested.is_empty():
		return nested
	var ec: String = str(result.get("error_class", ""))
	if ec == "HAND_PROFILE_FAILED":
		var failures: Array = result.get("failures", [])
		if not failures.is_empty():
			return str(failures[0])
	return ec


## The index and pinky roles exchanged: radial is derived toward the pinky.
class SwappedRadialFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := "swapped_radial_v0"
	const FAMILY_VERSION := "1"
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func bone_map(side: String) -> Dictionary:
		var m: Dictionary = Real.bone_map(side).duplicate(true)
		var i = m["index"]
		m["index"] = m["pinky"]
		m["pinky"] = i
		return m


## The thumb chain mapped onto bones that carry no thumb-tip skin.
class OffThumbFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := "off_thumb_v0"
	const FAMILY_VERSION := "1"
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func bone_map(side: String) -> Dictionary:
		var m: Dictionary = Real.bone_map(side).duplicate(true)
		var thumb: Array = (m["thumb"] as Array).duplicate()
		thumb[2] = str(m["hand"])
		m["thumb"] = thumb
		return m


## The thumb column taken from the opposite hand, so the derived volar side
## disagrees with the skinned palm flesh.
class CrossedThumbFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := "crossed_thumb_v0"
	const FAMILY_VERSION := "1"
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func bone_map(side: String) -> Dictionary:
		var m: Dictionary = Real.bone_map(side).duplicate(true)
		var other: String = "left" if side == "right" else "right"
		m["thumb"] = (Real.bone_map(other)["thumb"] as Array).duplicate()
		return m


## A family with the right shape but names that exist on no skeleton.
class WrongFamily:
	const FAMILY_ID := "wrong_family_v0"
	const FAMILY_VERSION := "1"
	const MCP_HINGE_LOCAL := Vector3(1.0, 0.0, 0.0)
	const DISTAL_TIP_FRACTION := 0.9

	static func resolved_height_landmarks(_skeleton: Skeleton3D) -> Dictionary:
		return {
			"ok": false,
			"error_class": "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
			"detail": "this family names landmarks that exist on no skeleton",
			"unresolved": ["head_top", "floor_contact"],
			"roles": {},
		}

	static func bone_map(side: String) -> Dictionary:
		var s := "L" if side == "left" else "R"
		return {
			"hand": "%s_wrist" % s,
			"thumb": ["%s_th1" % s, "%s_th2" % s, "%s_th3" % s],
			"index": ["%s_in1" % s, "%s_in2" % s, "%s_in3" % s],
			"middle": ["%s_mi1" % s, "%s_mi2" % s, "%s_mi3" % s],
			"ring": ["%s_ri1" % s, "%s_ri2" % s, "%s_ri3" % s],
			"pinky": ["%s_pi1" % s, "%s_pi2" % s, "%s_pi3" % s],
		}


## The caller-supplied expectations, which the production path derives from the
## real asset. `overrides` sabotages exactly one of them at a time.
func _expect(overrides: Dictionary = {}) -> Dictionary:
	var out := {
		"geometry_sha256": str(_art_right.get("source_geometry_sha256", "")),
		"rig_sha256": str(_art_right.get("source_rig_sha256", "")),
		"family_id": "mixamo_52_humanoid",
		"family_version": str(Real.FAMILY_VERSION),
	}
	for k in overrides.keys():
		out[str(k)] = overrides[k]
	return out


## Mint a real certificate by running the REAL acceptance chain on the REAL
## asset, through the certification authority's own API (A2.13a). There is no
## parameter for a chain, a gate result or a verdict, so this test cannot assert
## that anything ran — it has to actually run.
##
## Cached: the chain compiles, writes, re-reads and assembles the asset, and the
## negatives below need one certificate, not twenty.
var _cached_cert: Dictionary = {}


func _certify(required: Array) -> Dictionary:
	if not _cached_cert.is_empty():
		return _cached_cert
	_cached_cert = await Authority.new().run({
		"host": root,
		"tree": self,
		"glb": Native.UTHANA_TARGET_GLB,
		"staging_path": "user://a213_compiler_probe_evidence.tres",
		"sides": ["right", "left"],
		"required_sides": required,
		"policy_id": str(Policy.POLICY_ID),
		"weapon_path": Composition.CLUB_GLB_PATH,
		"family_id": "mixamo_52_humanoid",
		"asset_id": "compiler_probe",
	})
	await process_frame
	return _cached_cert


## A certificate with envelope fields overridden and its hash recomputed: a
## forgery the certification hash alone cannot catch.
func _forge(cert: Dictionary, overrides: Dictionary) -> Dictionary:
	var out: Dictionary = cert.duplicate(true)
	for k in overrides.keys():
		out[str(k)] = overrides[k]
	out.erase("certification_hash")
	out["certification_hash"] = Certification.certification_hash(out)
	return out


## Evidence swapped in WITHOUT updating the certificate's content hash: the
## classic "edit the payload and hope nobody re-hashes" attempt.
func _swap_evidence(cert: Dictionary, evidence: Dictionary) -> Dictionary:
	return _forge(cert, {"evidence": Compiler.canonicalize(evidence)})


## Evidence swapped in AND the certificate fully re-sealed around it, so the
## envelope is internally consistent and only a real contract check can refuse it.
func _reseal(cert: Dictionary, evidence: Dictionary) -> Dictionary:
	# A2.13a: the acceptance report repeats the identities it observed and
	# `verify` requires them to equal the envelope's, so a forgery that only
	# rewrites the envelope is caught by the binding rather than by the contract
	# check under test. Re-point the report too, and re-digest it, so this stays
	# a test of the compiler-version contract.
	var report: Dictionary = (cert.get("acceptance_report", {}) as Dictionary).duplicate(true)
	report["fixture_content_hash"] = str(evidence.get("content_hash", ""))
	report["source_rig_sha256"] = str(evidence.get("source_rig_sha256", ""))
	report["source_geometry_sha256"] = str(evidence.get("source_geometry_sha256", ""))
	var steps: Dictionary = report.get("steps", {})
	if steps.has("fixture_compilation"):
		((steps["fixture_compilation"] as Dictionary)["observed"]
			as Dictionary)["content_hash"] = str(evidence.get("content_hash", ""))
	return _forge(cert, {
		"evidence": Compiler.canonicalize(evidence),
		"fixture_content_hash": str(evidence.get("content_hash", "")),
		"source_rig_sha256": str(evidence.get("source_rig_sha256", "")),
		"source_geometry_sha256": str(evidence.get("source_geometry_sha256", "")),
		"acceptance_report": report,
		"acceptance_report_digest": Certification.acceptance_report_digest(report),
	})


func _keys(tris: Array) -> Array:
	var out: Array = []
	for t in tris:
		var ids: Array = []
		for i in ((t as Dictionary)["i"] as Array):
			ids.append(int(i))
		ids.sort()
		out.append(str(ids))
	out.sort()
	return out


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)
