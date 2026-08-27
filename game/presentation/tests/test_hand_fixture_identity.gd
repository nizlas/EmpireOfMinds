# A2.11/A2.12: fixture identity and mandatory rig binding.
#
# Four identity levels, kept apart on purpose:
#   1a. source GEOMETRY identity - the static mesh streams
#   1b. source RIG identity      - the whole deformation contract: skin binds,
#       bone rests, hierarchy. This is what actually binds a fixture, because
#       every compiled marker lives in bone-local space.
#   2.  fixture content identity - the canonical payload's own hash
#   3.  acceptance result        - bind sanity + grip ground truth
# A valid content hash therefore proves NOTHING about whether the artifact
# belongs to the rig in front of it, or whether the grip is any good.
#
# Level 4 (the certification envelope that binds 1-3 together) and the trust
# boundary around it live in `test_hand_fixture_certification.gd`.
#
# Everything here runs the real production paths: the real compiler, the real
# composition root, the real assembler, and for the cross-process checks the
# real canonical headless ingestion step in a SEPARATE Godot process.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const Policy = preload("res://presentation/equipment/power_grip_1h_policy.gd")
const CompilerCalibration = preload(
	"res://presentation/equipment/hand_fixture_compiler_calibration.gd"
)
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const Calibration = preload("res://presentation/equipment/power_grip_1h_calibration.gd")
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)
const Oracle = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)

const CERTIFY_SCRIPT := "res://presentation/equipment/tools/certify_hand_fixture_headless.gd"
const CLUB_GLB := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const REPORT_MARKER := "HAND_FIXTURE_INGEST "
## Raw Mixamo naming (mixamorig_RightHand), i.e. the other import
## representation of the same skeleton family.
const A0_RAW_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0/generated_warrior_3d_uthana_rigged.glb"
)

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var hash_in_test: String = await _test_identity_is_context_independent()
	await _test_identity_matches_a_separate_godot_process(hash_in_test)
	await _test_real_payload_change_changes_identity()
	await _test_live_path_requires_and_enforces_mesh_binding()
	await _test_rejected_artifact_cannot_load_as_accepted()
	await _test_import_representations_resolve_to_one_family()
	print("test_hand_fixture_identity: %d checks, %s" % [_total, "FAIL" if _any_fail else "OK"])
	quit(1 if _any_fail else 0)


## The scaling/scene contexts that used to produce different hashes for the
## same mesh. Compilation is pinned to skeleton space and the rest pose, so
## none of these may change the fixture's identity.
func _test_identity_is_context_independent() -> String:
	var contexts: Array = [
		{"label": "unscaled", "scale": Vector3.ONE, "pos": Vector3.ZERO, "yaw": 0.0},
		{
			"label": "preview_scale_0_30",
			"scale": Vector3.ONE * Native.PREVIEW_MODEL_SCALE,
			"pos": Vector3.ZERO,
			"yaw": 0.0,
		},
		{"label": "scaled_2_5", "scale": Vector3.ONE * 2.5, "pos": Vector3.ZERO, "yaw": 0.0},
		{
			"label": "placed_and_rotated",
			"scale": Vector3.ONE * 0.75,
			"pos": Vector3(12.0, -3.0, 7.5),
			"yaw": 1.1,
		},
	]
	var hashes: Array = []
	var posed_hash := ""
	for ctx_spec in contexts:
		var ctx: Dictionary = await _spawn(
			ctx_spec["scale"], ctx_spec["pos"], float(ctx_spec["yaw"])
		)
		# The same side set the canonical ingestion chain compiles, so the
		# comparison is over identical semantic data.
		var art: Dictionary = Compiler.compile(
			ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
		)
		var r: Dictionary = (art["sides"] as Dictionary)["right"]
		_check(
			bool(r.get("compiled", false)),
			"%s: right compiles (%s)" % [ctx_spec["label"], r.get("error_class", "")]
		)
		_check(
			str(((art["sides"] as Dictionary)["left"] as Dictionary).get("error_class", ""))
				== "PAD_PATCH_AMBIGUOUS",
			"%s: left stays classified" % ctx_spec["label"]
		)
		hashes.append(str(art.get("content_hash", "")))
		print("A2_11_CONTEXT_HASH %s %s" % [ctx_spec["label"], art.get("content_hash", "")])
		if posed_hash.is_empty():
			# An incoming animation pose must not leak into identity either:
			# the compiler pins the rest pose and restores what it found.
			var skel: Skeleton3D = ctx["skeleton"]
			var wrist: int = skel.find_bone(str(Family.bone_map("right")["hand"]))
			skel.set_bone_pose_rotation(
				wrist, Quaternion(Vector3(0.0, 1.0, 0.0), deg_to_rad(25.0))
			)
			skel.force_update_all_bone_transforms()
			var posed: Dictionary = Compiler.compile(
				ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
			)
			posed_hash = str(posed.get("content_hash", ""))
		(ctx["host"] as Node).queue_free()
		await process_frame
	for i in range(1, hashes.size()):
		_check(
			str(hashes[i]) == str(hashes[0]),
			"context %d hashes identically to the unscaled compile" % i
		)
	_check(
		posed_hash == str(hashes[0]),
		"a posed wrist does not change identity (compile pose is pinned to rest)"
	)
	_check(str(hashes[0]).length() == 64, "content hash is a sha256")
	return str(hashes[0])


## The determinism claim that a same-process recompile cannot make: a fresh
## Godot process running the canonical ingestion step must reach the same
## semantic identity.
func _test_identity_matches_a_separate_godot_process(hash_in_test: String) -> void:
	var out: Array = []
	var argv: PackedStringArray = PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"-s",
		CERTIFY_SCRIPT,
		"--",
		"--glb=%s" % Native.UTHANA_TARGET_GLB,
		"--out=user://a2_11_crossprocess_fixture.tres",
		"--policy=power_grip_1h_v1",
		"--weapon=%s" % CLUB_GLB,
		"--sides=right,left",
		"--required=right",
	])
	var code: int = OS.execute(OS.get_executable_path(), argv, out, true)
	var text: String = "" if out.is_empty() else str(out[0])
	var report: Dictionary = _parse_report(text)
	_check(not report.is_empty(), "the separate Godot process emitted a machine report")
	_check(code == 0, "a separate-process ACCEPTED ingestion exits 0 (got %d)" % code)
	_check(
		bool(report.get("accepted", false)),
		"the separate process accepted the whole chain (%s)" % report.get("error_class", "")
	)
	_check(
		str(report.get("content_hash", "")) == hash_in_test,
		"cross-process content hash matches the test context (%s vs %s)"
			% [str(report.get("content_hash", "")).substr(0, 10), hash_in_test.substr(0, 10)]
	)
	# The whole chain ran, not just the compiler. Read against the acceptance
	# chain the certification authority defines, so the two cannot drift: a new
	# required step is automatically required here too.
	for step in Certification.REQUIRED_CHAIN:
		_check(
			(report.get("chain", []) as Array).has(step),
			"cross-process chain ran '%s'" % step
		)
	_check(
		(report.get("chain", []) as Array) == Certification.REQUIRED_CHAIN,
		"...and ran exactly that chain, in order (%s)" % str(report.get("chain", []))
	)
	# Certification is the CONSEQUENCE of the chain, not a link in it, so it is
	# evidenced by the certificate itself rather than by a name in the array.
	_check(bool(report.get("certified", false)), "cross-process minted a certificate")
	_check(
		str(report.get("acceptance_authority_id", "")) == Certification.AUTHORITY_ID,
		"...from the canonical certification authority"
	)
	# INSTRUMENTED across the process boundary: the gates were really invoked.
	var calls: Dictionary = report.get("gate_calls", {})
	for gate in ["compile", "artifact_reload", "rig_identity_of_asset", "assemble", "mint"]:
		_check(int(calls.get(gate, 0)) == 1, "cross-process invoked '%s' exactly once" % gate)
	_check(
		str((report.get("grip_ground_truth", {}) as Dictionary).get("closest_patch", "")) == "pad",
		"cross-process grip ground truth reports the PAD as the contact patch"
	)
	_check(
		bool((report.get("assembler", {}) as Dictionary).get("ok", false)),
		"cross-process acceptance came through the real assembler"
	)
	# Same mesh, same family, same compiler: the left classification must be
	# reproduced too, not silently resolved differently.
	var left: Dictionary = (report.get("sides", {}) as Dictionary).get("left", {})
	_check(
		str(left.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"cross-process left stays classified PAD_PATCH_AMBIGUOUS"
	)


## Quantisation must not swallow a real geometric or policy change.
func _test_real_payload_change_changes_identity() -> void:
	var ctx: Dictionary = await _spawn(Vector3.ONE, Vector3.ZERO, 0.0)
	var base: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right"], Skinning
	)
	var base_hash: String = str(base["content_hash"])
	# A different CALIBRATING threshold owner is a different fixture identity.
	var with_other_calibration: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right"], Skinning, OtherCalibration
	)
	_check(
		str(with_other_calibration.get("content_hash", "")) != base_hash,
		"changing the calibration profile changes the fixture identity"
	)
	# An edited bone map changes the resolved digest even without a version bump.
	var with_edited_map: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], EditedMapFamily, ["right"], Skinning
	)
	_check(
		str(with_edited_map.get("family_bone_map_digest", ""))
			!= str(base.get("family_bone_map_digest", "")),
		"an unversioned bone-map edit still changes the hashed bone-map digest"
	)
	# A geometric difference far below any gate tolerance, but above the
	# declared identity quantum, must still change the hash.
	var moved: Dictionary = base.duplicate(true)
	var side: Dictionary = (moved["sides"] as Dictionary)["right"]
	var marker: Vector3 = side["pad_marker_local"]
	side["pad_marker_local"] = marker + Vector3(Compiler.IDENTITY_QUANTUM * 4.0, 0.0, 0.0)
	_check(
		Compiler.content_hash(moved) != base_hash,
		"a marker moved by 4 identity quanta changes the content hash"
	)
	# And a difference far BELOW the quantum is absorbed, by declaration.
	var jittered: Dictionary = base.duplicate(true)
	var jside: Dictionary = (jittered["sides"] as Dictionary)["right"]
	jside["rest_nail_pad_dot"] = (
		float(jside["rest_nail_pad_dot"]) + Compiler.IDENTITY_QUANTUM * 0.01
	)
	_check(
		Compiler.content_hash(jittered) == base_hash,
		"float noise below the declared quantum does not change identity"
	)
	# The stored representation IS the canonical one: re-canonicalising the
	# stored payload changes nothing, so runtime never runs on other numbers.
	_check(
		str(Compiler.canonicalize(base)) == str(base),
		"the stored artifact is already canonical (hashed == stored == used)"
	)
	(ctx["host"] as Node).queue_free()
	await process_frame


## B2: the live path must bind the fixture to the RIG it actually poses.
func _test_live_path_requires_and_enforces_mesh_binding() -> void:
	# The production composition derives both expected identities from this
	# unit's own rigged asset, not from the artifact it is about to check.
	var expected: Dictionary = Composition.expected_source_rig()
	_check(bool(expected.get("ok", false)), "composition derives its source rig identity")
	_check(
		str(expected.get("geometry_sha256", "")) != str(expected.get("rig_sha256", "")),
		"geometry identity and rig identity are genuinely different hashes"
	)
	var fx: Dictionary = Composition.compiled_fixture(["right"])
	_check(bool(fx.get("ok", false)), "production fixture loads (%s)" % fx.get("error_class", ""))
	if not bool(fx.get("ok", false)):
		return
	var fixture = fx["fixture"]
	_check(
		str(fixture.expected_rig_sha256) == str(expected["rig_sha256"])
		and str(fixture.expected_geometry_sha256) == str(expected["geometry_sha256"]),
		"the production fixture is bound to the asset-derived identities"
	)
	_check(
		str(fixture.expected_family_version) == str(Family.FAMILY_VERSION),
		"the production fixture carries an expected family VERSION, not only an id"
	)
	var comp_src := FileAccess.open(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd",
		FileAccess.READ
	)
	_check(comp_src != null, "composition source readable")
	if comp_src != null:
		var text: String = comp_src.get_as_text()
		_check(
			not text.contains(str(expected["rig_sha256"]).substr(0, 16))
			and not text.contains(str(expected["geometry_sha256"]).substr(0, 16)),
			"the composition carries no manually duplicated Uthana identity hash"
		)
	# Good path: the assembler verifies the live rig and says so.
	var ctx: Dictionary = await _spawn(
		Vector3.ONE * Native.PREVIEW_MODEL_SCALE, Vector3.ZERO, 0.0
	)
	var good: Dictionary = await _assemble(ctx, fixture)
	_check(bool(good["result"].get("ok", false)), "the bound fixture assembles")
	var binding: Dictionary = good["binding"]
	_check(
		bool(binding.get("verified", false))
		and str(binding.get("binding", "")) == "certified_bound",
		"the production assembler actually ran verify_against_rig"
	)
	_check(
		str(binding.get("rig_sha256", "")) == str(expected["rig_sha256"]),
		"the verified rig is the one the grip engine poses"
	)
	_check(
		str(binding.get("family_version", "")) == str(Family.FAMILY_VERSION),
		"the binding records the family version it was verified against"
	)
	# Sabotage: a VALID, correctly re-certified fixture that claims another rig.
	var loaded: Dictionary = Certification.load_certified(Composition.FIXTURE_ARTIFACT_PATH)
	_check(bool(loaded.get("ok", false)), "reference certificate loads for the sabotage")
	# Forge BOTH the embedded evidence and the envelope, and re-hash both, so
	# the certificate is fully self-consistent: every structural check passes
	# and only a real identity comparison against the live rig can catch it.
	var forged_evidence: Dictionary = (
		(loaded["certification"] as Dictionary)["evidence"] as Dictionary
	).duplicate(true)
	forged_evidence["source_rig_sha256"] = "A".repeat(64)
	forged_evidence["content_hash"] = Compiler.content_hash(forged_evidence)
	var forged: Dictionary = _recertify(loaded["certification"], {
		"evidence": Compiler.canonicalize(forged_evidence),
		"fixture_content_hash": str(forged_evidence["content_hash"]),
		"source_rig_sha256": "A".repeat(64),
	})
	_check(
		bool(Certification.verify(forged).get("ok", false)),
		"the forged certificate survives every structural check (%s)"
			% str(Certification.verify(forged).get("error_class", ""))
	)
	_check(
		Certification.certification_hash(forged) == str(forged["certification_hash"]),
		"the forged certificate is internally self-consistent"
	)
	# Through the production expectations: rejected before anything loads.
	var via_composition: Dictionary = CompiledFixture.from_certified_artifact(
		forged, Calibration.payload(), Composition.ASSET_ID, _expect(expected), ["right"]
	)
	_check(
		str(via_composition.get("error_class", "")) == "FIXTURE_RIG_HASH_MISMATCH",
		"a self-consistent certificate for another rig fails FIXTURE_RIG_HASH_MISMATCH (%s)"
			% str(via_composition.get("error_class", ""))
	)
	# And when the caller is fooled into expecting the forged identity too, the
	# assembler still refuses, because it re-derives the identity from the LIVE
	# rig rather than trusting either the artifact or the caller.
	var fooled: Dictionary = _expect(expected)
	fooled["rig_sha256"] = "A".repeat(64)
	var forged_fx: Dictionary = CompiledFixture.from_certified_artifact(
		forged, Calibration.payload(), "forged", fooled, ["right"]
	)
	_check(bool(forged_fx.get("ok", false)), "the forged fixture loads when self-consistent")
	if bool(forged_fx.get("ok", false)):
		var sab: Dictionary = await _assemble(ctx, forged_fx["fixture"])
		var res: Dictionary = sab["result"]
		_check(
			str(res.get("error_class", "")) == "FIXTURE_RIG_HASH_MISMATCH",
			"the live path rejects the forged certificate as FIXTURE_RIG_HASH_MISMATCH (%s)"
				% str(res.get("error_class", ""))
		)
		_check(
			str(res.get("reason", "")) == "fixture_mesh_binding_failed",
			"rig identity is checked BEFORE geometric bind sanity (%s)"
				% str(res.get("reason", ""))
		)
		_check(
			not str(res.get("reason", "")).contains("patch"),
			"the rejection never reaches thumb_patch_frame_mismatch"
		)
	# Missing expected identities fail closed rather than skipping the check.
	for omitted in ["rig_sha256", "geometry_sha256"]:
		var blank: Dictionary = _expect(expected)
		blank[omitted] = ""
		_check(
			str(CompiledFixture.from_certified_artifact(
				loaded["certification"], Calibration.payload(), "u", blank, ["right"]
			).get("error_class", "")) == "FIXTURE_MESH_IDENTITY_REQUIRED",
			"an empty expected %s cannot disable the binding" % omitted
		)
	# A missing artifact fails closed with no fallback fixture at all.
	_check(
		str(Certification.load_certified("res://presentation/tests/no_such.tres")
			.get("error_class", "")) == "FIXTURE_ARTIFACT_MISSING",
		"a missing certificate fails FIXTURE_ARTIFACT_MISSING"
	)
	var no_fixture: Dictionary = await _assemble(ctx, null)
	_check(
		str(no_fixture["result"].get("error_class", "")) == "FIXTURE_REQUIRED",
		"no fixture means FIXTURE_REQUIRED, never a default or authored fallback"
	)
	# The authored oracle must not be reachable as a production fallback.
	var deps: Dictionary = Composition.dependencies(["right"])
	_check(
		str(deps["fixture"].fixture_verification_contract())
			== CompiledFixture.CONTRACT_CERTIFIED_RUNTIME,
		"the composition only ever injects a certified-contract fixture"
	)
	_check(
		str(Oracle.fixture_verification_contract())
			== CompiledFixture.CONTRACT_TEST_ONLY_REFERENCE,
		"the authored fixture declares itself test-only"
	)
	(ctx["host"] as Node).queue_free()
	await process_frame


## A classified side is diagnostic data, never a loadable fixture.
func _test_rejected_artifact_cannot_load_as_accepted() -> void:
	var ctx: Dictionary = await _spawn(Vector3.ONE, Vector3.ZERO, 0.0)
	var art: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
	)
	_check(not bool(art.get("ok", true)), "the reference artifact still carries a classified side")
	# The certification owner refuses to certify a side the compiler classified,
	# so a rejected hand can never reach the runtime loader at all. Note that
	# NO chain results are supplied here (A2.13a): the classified side is
	# refused on the evidence itself, before any step evidence is even read.
	var as_left: Dictionary = Certification.mint_from_observed_chain(
		art, _resolved(art, ["left"]), {}
	)
	_check(
		str(as_left.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"the rejected left side cannot be certified (%s)" % str(as_left.get("error_class", ""))
	)
	# A whole-artifact rejection (no side compiled at all) is equally unusable.
	var fingerless := Skeleton3D.new()
	fingerless.add_bone("RightHand")
	root.add_child(fingerless)
	var bad: Dictionary = Compiler.compile(
		ctx["character"], fingerless, Family, ["right"], Skinning
	)
	_check(
		str(((bad["sides"] as Dictionary)["right"] as Dictionary).get("error_class", ""))
			== "HAND_SKELETON_INCOMPLETE",
		"an incomplete hand is classified HAND_SKELETON_INCOMPLETE"
	)
	_check(
		str(Certification.mint_from_observed_chain(bad, _resolved(bad, ["right"]), {})
			.get("error_class", "")) == "HAND_SKELETON_INCOMPLETE",
		"a rejected artifact cannot be certified as an accepted fixture"
	)
	fingerless.queue_free()
	(ctx["host"] as Node).queue_free()
	await process_frame


## The caller-side expectations the production path supplies independently.
func _expect(source: Dictionary) -> Dictionary:
	return {
		"geometry_sha256": str(source.get("geometry_sha256", "")),
		"rig_sha256": str(source.get("rig_sha256", "")),
		"family_id": str(Family.FAMILY_ID),
		"family_version": str(Family.FAMILY_VERSION),
	}


## The identities the certification authority would have RESOLVED for this
## evidence. Supplying them is not the same as supplying a verdict: minting
## still needs one observed result per chain step, and none is given here.
func _resolved(evidence: Dictionary, sides: Array) -> Dictionary:
	return {
		"required_sides": sides,
		"certified_side": str(sides[0]),
		"geometry_sha256": str(evidence.get("source_geometry_sha256", "")),
		"rig_sha256": str(evidence.get("source_rig_sha256", "")),
		"family_id": str(Family.FAMILY_ID),
		"family_version": str(Family.FAMILY_VERSION),
		"policy_id": str(Policy.POLICY_ID),
		"policy_version": str(Policy.POLICY_VERSION),
		"policy_calibration_id": str(Calibration.CALIBRATION_ID),
		"policy_calibration_version": str(Calibration.CALIBRATION_VERSION),
	}


## A certificate with fields overridden and everything re-hashed, i.e. sabotage
## that is internally self-consistent and cannot be caught by the hash alone.
##
## A2.13a: the acceptance report repeats the identities the chain observed and
## `verify` requires them to equal the envelope's, so the report and the
## `rig_binding` step's own observation are re-pointed too. That is deliberate:
## this test exists to show what happens when a forgery IS fully consistent, and
## the answer must be that live re-verification against the real rig catches it.
func _recertify(cert: Dictionary, overrides: Dictionary) -> Dictionary:
	var forged: Dictionary = cert.duplicate(true)
	for k in overrides.keys():
		forged[str(k)] = overrides[k]
	var report: Dictionary = (forged.get("acceptance_report", {}) as Dictionary).duplicate(true)
	for f in Certification.REPORT_BOUND_FIELDS:
		if forged.has(f):
			report[str(f)] = str(forged[f])
	var steps: Dictionary = report.get("steps", {})
	if steps.has("rig_binding"):
		var observed: Dictionary = (steps["rig_binding"] as Dictionary)["observed"]
		observed["geometry_sha256"] = str(forged.get("source_geometry_sha256", ""))
		observed["rig_sha256"] = str(forged.get("source_rig_sha256", ""))
	if steps.has("fixture_compilation"):
		((steps["fixture_compilation"] as Dictionary)["observed"]
			as Dictionary)["content_hash"] = str(forged.get("fixture_content_hash", ""))
	forged["acceptance_report"] = report
	forged["acceptance_report_digest"] = Certification.acceptance_report_digest(report)
	forged.erase("certification_hash")
	forged["certification_hash"] = Certification.certification_hash(forged)
	return forged


## Both import representations of the same rig resolve to one family, and a
## truly fingerless rig still fails closed.
func _test_import_representations_resolve_to_one_family() -> void:
	var retargeted: Dictionary = await _spawn(Vector3.ONE, Vector3.ZERO, 0.0)
	var retargeted_skel: Skeleton3D = retargeted["skeleton"]
	_check(
		Family.import_representation(retargeted_skel, "right") == "godot_humanoid_retarget",
		"the a1 import is recognised as the Godot-humanoid representation"
	)
	(retargeted["host"] as Node).queue_free()
	await process_frame
	_check(ResourceLoader.exists(A0_RAW_GLB), "the raw Mixamo-named rig exists")
	var host := Node3D.new()
	root.add_child(host)
	var raw: Node3D = (load(A0_RAW_GLB) as PackedScene).instantiate()
	host.add_child(raw)
	await process_frame
	var skel: Skeleton3D = Skinning.find_skeleton(raw)
	skel.force_update_all_bone_transforms()
	_check(
		Family.import_representation(skel, "right") == "raw_mixamo",
		"the a0 import is recognised as the raw Mixamo representation"
	)
	var bm: Dictionary = HandProfile.family_bone_map(Family, skel, "right")
	_check(
		skel.find_bone(str(bm["hand"])) >= 0,
		"the hand bone resolves through the family's own alias data (%s)" % str(bm["hand"])
	)
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		for bn in (bm[digit] as Array):
			_check(skel.find_bone(str(bn)) >= 0, "a0 %s bone resolves (%s)" % [digit, bn])
	# The compiler no longer stops at "hand bone" on this rig: it reaches a
	# truthful later compiler result instead of a false family mismatch.
	var art: Dictionary = Compiler.compile(raw, skel, Family, ["right"], Skinning)
	var r: Dictionary = (art["sides"] as Dictionary)["right"]
	var ec: String = str(r.get("error_class", ""))
	_check(
		ec != "HAND_SKELETON_INCOMPLETE" or not str(r.get("detail", "")).contains("hand bone"),
		"a0 is no longer misclassified on the hand bone (%s %s)" % [ec, r.get("detail", "")]
	)
	print("A2_11_A0_COMPILE compiled=%s %s: %s" % [
		str(r.get("compiled", false)), ec, r.get("detail", "")
	])
	# A genuinely fingerless rig must still be refused.
	var stump := Skeleton3D.new()
	stump.add_bone("mixamorig_RightHand")
	root.add_child(stump)
	var stump_art: Dictionary = Compiler.compile(raw, stump, Family, ["right"], Skinning)
	_check(
		str(((stump_art["sides"] as Dictionary)["right"] as Dictionary).get("error_class", ""))
			== "HAND_SKELETON_INCOMPLETE",
		"a rig with a hand but no fingers is still classified HAND_SKELETON_INCOMPLETE"
	)
	stump.queue_free()
	host.queue_free()
	await process_frame


func _spawn(scale: Vector3, pos: Vector3, yaw: float) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var model := Node3D.new()
	model.scale = scale
	model.position = pos
	model.rotation = Vector3(0.0, yaw, 0.0)
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


## Assemble through the REAL assembler with the real composition dependencies,
## overriding only the fixture under test.
func _assemble(ctx: Dictionary, fixture) -> Dictionary:
	var deps: Dictionary = Composition.dependencies(["right"])
	deps["fixture"] = fixture
	var asm: Node = Assembler.new()
	asm.configure_dependencies(deps)
	(ctx["host"] as Node).add_child(asm)
	var result: Dictionary = asm.assemble(ctx["character"], "right")
	var binding: Dictionary = asm.mesh_binding()
	asm.queue_free()
	await process_frame
	return {"result": result, "binding": binding}


func _parse_report(text: String) -> Dictionary:
	var found := {}
	for line in text.split("\n"):
		var s := str(line)
		var at := s.find(REPORT_MARKER)
		if at < 0:
			continue
		var parsed = JSON.parse_string(s.substr(at + REPORT_MARKER.length()).strip_edges())
		if parsed is Dictionary:
			found = parsed
	return found


## A second, deliberately different CALIBRATING threshold owner.
class OtherCalibration:
	const CALIBRATION_ID := "hand_fixture_compiler_calibration_probe"
	const CALIBRATION_VERSION := "99"
	const MIN_CLASSIFICATION_MARGIN := 0.07


## Same convention, one bone name spelled differently: the resolved bone-map
## digest must notice even though no version was bumped.
class EditedMapFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := Real.FAMILY_ID
	const FAMILY_VERSION := Real.FAMILY_VERSION
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func bone_map(side: String) -> Dictionary:
		var m: Dictionary = Real.bone_map(side).duplicate(true)
		m["forearm_alt"] = "%s_edited_marker" % side
		return m


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)
