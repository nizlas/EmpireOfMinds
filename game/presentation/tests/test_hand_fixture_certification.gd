# A2.12: the trust boundary between compiled evidence and a runtime fixture.
#
# WHAT WENT WRONG BEFORE THIS SUITE EXISTED. Three defects had the same shape —
# a check that could be satisfied without being performed:
#
#   * a rig whose head bone was spelled `mixamorig_Head` measured 0.0 and was
#     rejected as `DEGENERATE_HEIGHT`, a false geometric claim;
#   * `source_mesh_sha256` covered the vertex streams only, so moving a bone
#     rest or a skin bind pose left the identity intact while every compiled
#     bone-local marker moved;
#   * a classified-REJECTED asset's staged artifact loaded successfully, bound
#     against its own mesh and was indistinguishable from an accepted fixture —
#     only its file location kept it out of the game;
#   * `family_version` sat in the payload but was never verified;
#   * verification was opt-in through `has_method`, so the hand-authored oracle
#     assembled with `verified: false`.
#
# Every test here runs the REAL family, the REAL identity functions, the REAL
# certification owner, the REAL runtime loader and the REAL assembler. The
# a0 full-chain check runs the REAL headless ingestion step in a SEPARATE Godot
# process. Fully offline: no provider, no network, no credentials.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const Authority = preload(
	"res://presentation/equipment/hand_fixture_certification_authority.gd"
)
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const Calibration = preload("res://presentation/equipment/power_grip_1h_calibration.gd")
const Policy = preload("res://presentation/equipment/power_grip_1h_policy.gd")
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)
const Oracle = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)

const CERTIFY_SCRIPT := "res://presentation/equipment/tools/certify_hand_fixture_headless.gd"
const CLUB_GLB := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const REPORT_MARKER := "HAND_FIXTURE_INGEST "
## The raw Mixamo delivery: the same humanoid under the other import
## representation, and the asset the height blocker was found on.
const A0_RAW_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0/generated_warrior_3d_uthana_rigged.glb"
)
## The height both representations must agree on, in the declared canonical
## space. Pinned: a change here means the measurement moved, not the rig.
const EXPECTED_HUMANOID_HEIGHT := 0.888740688562393
const HEIGHT_TOLERANCE := 1e-9
## Two deliveries of one humanoid are not bit-identical meshes: vertex positions
## differ in the last places after a 100x scale round-trip. This is the band
## inside which the two achieved approach metrics count as the same measurement.
const REPRESENTATION_GATE_TOLERANCE := 0.02

var _total := 0
var _any_fail := false
## Captured from the two subprocess ingestions so the equivalence check below
## compares what the REAL CLI actually reported for each representation.
var _a0_gate_metrics: Dictionary = {}
var _a0_surface: Dictionary = {}
var _a1_gate_metrics: Dictionary = {}
var _a1_surface: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_semantic_height_landmarks()
	await _test_degenerate_and_unresolved_are_different_facts()
	await _test_rig_identity_covers_the_whole_deformation_contract()
	await _test_evidence_is_never_a_runtime_fixture()
	await _test_certification_envelope_binds_the_whole_chain()
	await _test_certification_authority_owns_the_verdict()
	await _test_acceptance_metadata_cannot_be_manipulated()
	await _test_fixture_verification_is_mandatory()
	await _test_authored_oracle_is_test_only()
	await _test_raw_a0_full_chain()
	await _test_a1_full_chain_accepts_and_publishes()
	_test_two_representations_agree()
	print("test_hand_fixture_certification: %d checks, %s" % [
		_total, "FAIL" if _any_fail else "OK"
	])
	quit(1 if _any_fail else 0)


# ------------------------------------------------- semantic height landmarks


## THE BLOCKER. Both import representations of the same humanoid resolve their
## landmarks through the family's own alias table and measure the SAME height.
func _test_semantic_height_landmarks() -> void:
	var retarget: Dictionary = await _spawn(Native.UTHANA_TARGET_GLB, Vector3.ONE)
	var raw: Dictionary = await _spawn(A0_RAW_GLB, Vector3.ONE)
	var heights := {}
	for row in [["godot_retarget", retarget], ["raw_mixamo", raw]]:
		var label := str(row[0])
		var skeleton: Skeleton3D = (row[1] as Dictionary)["skeleton"]
		var landmarks: Dictionary = HandProfile.family_height_landmarks(Family, skeleton)
		_check(
			bool(landmarks.get("ok", false)),
			"%s: every semantic height landmark resolves (%s)"
				% [label, landmarks.get("detail", "")]
		)
		var roles: Dictionary = landmarks.get("roles", {})
		var head: Array = roles.get(Family.LANDMARK_HEAD_TOP, [])
		_check(not head.is_empty(), "%s: the head_top role resolves to a bone" % label)
		_check(
			skeleton.find_bone(str(head[0])) >= 0,
			"%s: head_top '%s' is a real bone on this rig" % [label, head[0] if head else ""]
		)
		var measured: Dictionary = Skinning.measure_humanoid_height_from_landmarks(
			skeleton, landmarks
		)
		_check(
			bool(measured.get("ok", false)),
			"%s: the humanoid measures (%s)" % [label, measured.get("error_class", "")]
		)
		_check(
			str(measured.get("space", "")) == Skinning.HEIGHT_MEASURE_SPACE,
			"%s: the measurement declares its canonical space" % label
		)
		heights[label] = float(measured.get("height", 0.0))
	# The raw rig's head bone is spelled differently — that is the whole point.
	var raw_landmarks: Dictionary = HandProfile.family_height_landmarks(
		Family, raw["skeleton"]
	)
	var retarget_landmarks: Dictionary = HandProfile.family_height_landmarks(
		Family, retarget["skeleton"]
	)
	var raw_head := str((raw_landmarks["roles"] as Dictionary)[Family.LANDMARK_HEAD_TOP][0])
	var ret_head := str(
		(retarget_landmarks["roles"] as Dictionary)[Family.LANDMARK_HEAD_TOP][0]
	)
	_check(
		raw_head != ret_head,
		"the two representations really do spell the head bone differently (%s vs %s)"
			% [raw_head, ret_head]
	)
	_check(
		raw_head.begins_with("mixamorig"),
		"the raw Mixamo head landmark resolves to the prefixed name (%s)" % raw_head
	)
	# ... and they must nevertheless measure the same humanoid identically.
	_check(
		absf(float(heights["raw_mixamo"]) - float(heights["godot_retarget"]))
			<= HEIGHT_TOLERANCE,
		"raw Mixamo and Godot-retarget measure the same height (%.12f vs %.12f)"
			% [heights["raw_mixamo"], heights["godot_retarget"]]
	)
	_check(
		absf(float(heights["raw_mixamo"]) - EXPECTED_HUMANOID_HEIGHT) <= HEIGHT_TOLERANCE,
		"the pinned humanoid height is unchanged (%.12f)" % heights["raw_mixamo"]
	)
	# No generic consumer may know a rig prefix: the family owns every alias.
	for path in [
		"res://presentation/equipment/skinned_mesh_geometry.gd",
		"res://presentation/equipment/equipment_assembler.gd",
		"res://presentation/equipment/humanoid_hand_profile.gd",
	]:
		var f := FileAccess.open(path, FileAccess.READ)
		_check(f != null, "%s readable" % path)
		if f != null:
			_check(
				not f.get_as_text().contains("mixamorig"),
				"%s names no rig prefix of its own" % path.get_file()
			)
	(retarget["host"] as Node).queue_free()
	(raw["host"] as Node).queue_free()
	await process_frame


## `DEGENERATE_HEIGHT` is a geometric claim and may only be made when the
## landmarks actually resolved. Anything else is a truthful "unresolved".
func _test_degenerate_and_unresolved_are_different_facts() -> void:
	# A rig with no landmark bones at all.
	var bare := Skeleton3D.new()
	bare.add_bone("SomeBone")
	root.add_child(bare)
	var bare_landmarks: Dictionary = HandProfile.family_height_landmarks(Family, bare)
	_check(
		str(bare_landmarks.get("error_class", "")) == "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
		"a rig with no landmark bones is UNRESOLVED, not degenerate (%s)"
			% str(bare_landmarks.get("error_class", ""))
	)
	_check(
		(bare_landmarks.get("unresolved", []) as Array).has(Family.LANDMARK_HEAD_TOP),
		"the unresolved head role is named in the rejection"
	)
	_check(
		str(Skinning.measure_humanoid_height_from_landmarks(bare, bare_landmarks)
			.get("error_class", "")) == "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
		"the measurement propagates the unresolved class rather than reporting 0.0"
	)
	# A rig with a head but no floor: still unresolved, and specifically so.
	var headless_floor := Skeleton3D.new()
	headless_floor.add_bone("Head")
	root.add_child(headless_floor)
	var floor_missing: Dictionary = HandProfile.family_height_landmarks(
		Family, headless_floor
	)
	_check(
		(floor_missing.get("unresolved", []) as Array) == [Family.LANDMARK_FLOOR_CONTACT],
		"a rig with a head and no floor names exactly the floor role (%s)"
			% str(floor_missing.get("unresolved", []))
	)
	# A rig whose landmarks DO resolve but whose geometry is genuinely flat.
	var flat := Skeleton3D.new()
	flat.add_bone("Head")
	flat.add_bone("LeftFoot")
	flat.set_bone_rest(0, Transform3D.IDENTITY)
	flat.set_bone_rest(1, Transform3D.IDENTITY)
	root.add_child(flat)
	flat.force_update_all_bone_transforms()
	var flat_landmarks: Dictionary = HandProfile.family_height_landmarks(Family, flat)
	_check(bool(flat_landmarks.get("ok", false)), "the flat rig's landmarks DO resolve")
	_check(
		str(Skinning.measure_humanoid_height_from_landmarks(flat, flat_landmarks)
			.get("error_class", "")) == "DEGENERATE_HEIGHT",
		"resolved landmarks with no vertical extent are DEGENERATE_HEIGHT"
	)
	# A landmark role pointing at the wrong end of the body: the head lands
	# below the floor, which is degenerate rather than silently negative.
	var inverted := Skeleton3D.new()
	inverted.add_bone("Head")
	inverted.add_bone("LeftFoot")
	inverted.set_bone_rest(0, Transform3D(Basis(), Vector3(0.0, -1.0, 0.0)))
	inverted.set_bone_rest(1, Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)))
	root.add_child(inverted)
	inverted.force_update_all_bone_transforms()
	var inverted_landmarks: Dictionary = HandProfile.family_height_landmarks(Family, inverted)
	_check(
		str(Skinning.measure_humanoid_height_from_landmarks(inverted, inverted_landmarks)
			.get("error_class", "")) == "DEGENERATE_HEIGHT",
		"a head landmark below the floor landmark is DEGENERATE_HEIGHT, never a negative height"
	)
	# A family that declares no landmarks at all fails closed rather than
	# defaulting to a name list of the utility's own.
	_check(
		str(HandProfile.family_height_landmarks(NoLandmarkFamily, flat)
			.get("error_class", "")) == "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
		"a family without semantic landmarks fails closed"
	)
	# An alias table that points at bones which exist on no skeleton.
	_check(
		str(HandProfile.family_height_landmarks(WrongAliasFamily, flat)
			.get("error_class", "")) == "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
		"landmark aliases that resolve to nothing are UNRESOLVED"
	)
	for n in [bare, headless_floor, flat, inverted]:
		n.queue_free()
	await process_frame


# ------------------------------------------------------- rig identity (level 1b)


## Geometry identity is blind to the rig; rig identity is not. Anything that
## changes how the mesh deforms must invalidate the fixture, and anything that
## is merely where or how the character currently stands must not.
func _test_rig_identity_covers_the_whole_deformation_contract() -> void:
	var ctx: Dictionary = await _spawn(Native.UTHANA_TARGET_GLB, Vector3.ONE)
	var mi: MeshInstance3D = ctx["mesh"]
	var skeleton: Skeleton3D = ctx["skeleton"]
	var geometry: String = Compiler.geometry_identity(mi)
	var rig: String = Compiler.rig_identity(mi, skeleton)
	_check(geometry.length() == 64 and rig.length() == 64, "both identities are SHA-256")
	_check(geometry != rig, "geometry identity and rig identity are not the same value")

	# --- INVARIANT under presentation: pose and placement ---
	var hand: int = skeleton.find_bone(
		str(HandProfile.family_bone_map(Family, skeleton, "right")["hand"])
	)
	skeleton.set_bone_pose_rotation(hand, Quaternion(Vector3.UP, deg_to_rad(35.0)))
	skeleton.force_update_all_bone_transforms()
	await process_frame
	_check(
		Compiler.rig_identity(mi, skeleton) == rig,
		"an ordinary runtime POSE does not invalidate the rig identity"
	)
	skeleton.reset_bone_poses()
	var host: Node3D = ctx["host"]
	host.scale = Vector3.ONE * 0.3
	host.position = Vector3(11.0, -4.0, 7.0)
	host.rotation = Vector3(0.0, deg_to_rad(140.0), 0.0)
	await process_frame
	skeleton.force_update_all_bone_transforms()
	_check(
		Compiler.rig_identity(mi, skeleton) == rig,
		"an ancestor transform (scale, placement, yaw) does not invalidate it"
	)
	host.scale = Vector3.ONE
	host.position = Vector3.ZERO
	host.rotation = Vector3.ZERO
	await process_frame

	# --- INVALIDATED by deformation: rest, hierarchy, bind pose, weights ---
	var original_rest: Transform3D = skeleton.get_bone_rest(hand)
	skeleton.set_bone_rest(hand, original_rest.translated_local(Vector3(0.0, 0.05, 0.0)))
	skeleton.force_update_all_bone_transforms()
	_check(
		Compiler.rig_identity(mi, skeleton) != rig,
		"a changed BONE REST invalidates the rig identity"
	)
	_check(
		Compiler.geometry_identity(mi) == geometry,
		"...and geometry identity alone is blind to it, which is why it is not enough"
	)
	skeleton.set_bone_rest(hand, original_rest)
	skeleton.force_update_all_bone_transforms()
	_check(Compiler.rig_identity(mi, skeleton) == rig, "restoring the rest restores identity")

	var original_parent: int = skeleton.get_bone_parent(hand)
	skeleton.set_bone_parent(hand, 0 if original_parent != 0 else 1)
	skeleton.force_update_all_bone_transforms()
	_check(
		Compiler.rig_identity(mi, skeleton) != rig,
		"a changed bone HIERARCHY invalidates the rig identity"
	)
	skeleton.set_bone_parent(hand, original_parent)
	skeleton.force_update_all_bone_transforms()

	var original_skin: Skin = mi.skin
	if original_skin != null and original_skin.get_bind_count() > 0:
		var edited_skin: Skin = original_skin.duplicate(true)
		edited_skin.set_bind_pose(
			0, edited_skin.get_bind_pose(0).translated_local(Vector3(0.0, 0.03, 0.0))
		)
		mi.skin = edited_skin
		await process_frame
		_check(
			Compiler.rig_identity(mi, skeleton) != rig,
			"a changed SKIN BIND POSE invalidates the rig identity"
		)
		_check(
			Compiler.geometry_identity(mi) == geometry,
			"...and geometry identity is blind to the bind pose too"
		)
		mi.skin = original_skin
		await process_frame
		_check(
			Compiler.rig_identity(mi, skeleton) == rig, "restoring the skin restores identity"
		)

	# Skin weights and bone indices live in the mesh arrays: a rebind that
	# keeps every vertex position must still invalidate the fixture, because
	# the compiled markers were measured through those weights.
	var reweighted := _mesh_with_shifted_weights(mi.mesh)
	if reweighted != null:
		var probe := MeshInstance3D.new()
		probe.mesh = reweighted
		probe.skin = mi.skin
		probe.skeleton = NodePath("..")
		skeleton.add_child(probe)
		await process_frame
		_check(
			Compiler.geometry_identity(probe) != geometry,
			"changed skin WEIGHTS / BONE INDICES change the identity"
		)
		_check(
			Compiler.rig_identity(probe, skeleton) != rig,
			"...and therefore invalidate the rig identity as well"
		)
		probe.queue_free()
	(ctx["host"] as Node).queue_free()
	await process_frame


## The same surface with the first vertex's skin weights redistributed onto
## another bone. Returns null when this mesh carries no skin streams.
func _mesh_with_shifted_weights(source: Mesh) -> ArrayMesh:
	if source == null or source.get_surface_count() == 0:
		return null
	var arrays: Array = source.surface_get_arrays(0)
	var bones = arrays[Mesh.ARRAY_BONES]
	if bones == null or (bones as PackedInt32Array).size() < 8:
		return null
	var edited: PackedInt32Array = (bones as PackedInt32Array).duplicate()
	edited[0] = (edited[0] + 1) % maxi(1, edited.size())
	arrays[Mesh.ARRAY_BONES] = edited
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# ------------------------------------------ compiled evidence vs runtime fixture


## A compiler PASS is not a licence, and a rejected asset's staged evidence is
## not a fixture that merely happens to sit in the wrong folder.
func _test_evidence_is_never_a_runtime_fixture() -> void:
	var ctx: Dictionary = await _spawn(Native.UTHANA_TARGET_GLB, Vector3.ONE)
	var evidence: Dictionary = Compiler.compile(
		ctx["character"], ctx["skeleton"], Family, ["right", "left"], Skinning
	)
	# The evidence is genuinely valid AND genuinely bound to the live rig, so
	# the refusals below cannot be passing for an unrelated reason.
	_check(
		Compiler.content_hash(evidence) == str(evidence["content_hash"]),
		"the staged evidence has a correct content hash"
	)
	_check(
		str(evidence["source_rig_sha256"])
			== Compiler.rig_identity(ctx["mesh"], ctx["skeleton"]),
		"the staged evidence has a correct live rig binding"
	)
	_check(
		bool((evidence["sides"] as Dictionary)["right"].get("compiled", false)),
		"the staged evidence carries a compiled right hand"
	)
	# ...and the runtime loader still refuses it, because it is not certified.
	_check(
		str(CompiledFixture.from_certified_artifact(
			evidence, Calibration.payload(), "u", _expect(evidence), ["right"]
		).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"valid, correctly bound evidence is NOT a runtime fixture"
	)
	# The same refusal survives being copied onto the path the game loads: the
	# boundary is the resource type and the envelope, never the file location.
	var staged_path := "user://a2_12_staged_evidence_on_published_path.tres"
	_check(
		bool(Compiler.save_artifact(evidence, staged_path).get("ok", false)),
		"the evidence writes to a staging file"
	)
	var as_certified: Dictionary = Certification.load_certified(staged_path)
	_check(
		str(as_certified.get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"a staged evidence file renamed onto the published path is refused (%s)"
			% str(as_certified.get("error_class", ""))
	)
	# The evidence resource is still readable AS EVIDENCE, so this is a
	# contract boundary rather than a broken file.
	_check(
		bool(Compiler.load_artifact(staged_path).get("ok", false)),
		"the same file is still valid compiled evidence for diagnostics"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(staged_path))
	(ctx["host"] as Node).queue_free()
	await process_frame


## Only the acceptance chain the CERTIFICATION AUTHORITY ran itself may mint a
## certificate, and the certificate names every identity the acceptance was
## true for.
##
## A2.13a: minting goes through `hand_fixture_certification_authority.gd`, in
## this process, on the real asset. There is no longer a parameter through
## which this test — or any caller — could assert that a step ran.
func _test_certification_envelope_binds_the_whole_chain() -> void:
	var run: Dictionary = await _certify(Native.UTHANA_TARGET_GLB, ["right"])
	_check(
		bool(run.get("ok", false)),
		"the real acceptance chain mints a certificate (%s / %s)"
			% [str(run.get("error_class", "")), str(run.get("stage", ""))]
	)
	if not bool(run.get("ok", false)):
		return
	var cert: Dictionary = run["certification"]
	var evidence: Dictionary = run["evidence"]
	# Everything the certificate must bind.
	for key in [
		"fixture_content_hash", "source_rig_sha256", "source_geometry_sha256",
		"family_id", "family_version", "compiler_version", "evidence_schema",
		"compiler_calibration_id", "compiler_calibration_version",
		"policy_id", "policy_version", "policy_calibration_id",
		"policy_calibration_version", "acceptance_schema", "acceptance_version",
		"acceptance_authority_id", "acceptance_report_digest", "certification_hash",
	]:
		_check(
			not str(cert.get(key, "")).is_empty(),
			"the certification envelope binds '%s'" % key
		)
	_check(
		str(cert["fixture_content_hash"]) == str(evidence["content_hash"]),
		"the certificate binds the exact evidence content hash"
	)
	_check(bool(Certification.verify(cert).get("ok", false)), "the minted certificate verifies")
	# The recorded chain is a RECORD of what ran: exactly the required chain.
	_check(
		(cert.get("chain", []) as Array) == Certification.REQUIRED_CHAIN,
		"the certificate records exactly the acceptance chain (%s)" % str(cert.get("chain", []))
	)
	# Every step carries its own observation, and the verdict is derived from
	# them rather than declared beside them.
	var report: Dictionary = cert["acceptance_report"]
	_check(
		str(report.get("authority_id", "")) == Certification.AUTHORITY_ID,
		"the acceptance report names the certification authority"
	)
	var steps: Dictionary = report.get("steps", {})
	for step in Certification.REQUIRED_CHAIN:
		_check(steps.has(step), "the report records a result for '%s'" % step)
		if steps.has(step):
			_check(
				not ((steps[step] as Dictionary).get("observed", {}) as Dictionary).is_empty(),
				"'%s' recorded what it observed, not just that it ran" % step
			)
	# The behavioural anchor: the achieved contact really was measured.
	var measured: Dictionary = (steps["assemble_and_measure"] as Dictionary)["observed"]
	_check(
		str(measured.get("closest_patch", "")) == "pad",
		"the recorded achieved contact is the volar pad (%s)"
			% str(measured.get("closest_patch", ""))
	)
	_check(
		bool(measured.get("mesh_binding_verified", false)),
		"the assembly step verified the fixture against the live rig"
	)
	# INSTRUMENTED: every required operation was really invoked, once.
	var calls: Dictionary = run["gate_calls"]
	for gate in ["import", "compile", "artifact_reload", "rig_identity_of_asset",
			"assemble", "surface_read", "mint"]:
		_check(int(calls.get(gate, 0)) >= 1, "the chain really invoked '%s'" % gate)
	_check(int(calls.get("assemble", 0)) == 1, "the assembler ran exactly once")
	# The published production certificate is a real one, on disk, and loads.
	var published: Dictionary = Certification.load_certified(
		Composition.FIXTURE_ARTIFACT_PATH
	)
	_check(
		bool(published.get("ok", false)),
		"the published production artifact is a certificate (%s)"
			% str(published.get("error_class", ""))
	)
	_check(
		str((published.get("certification", {}) as Dictionary).get("schema", ""))
			== Certification.CERTIFICATION_SCHEMA,
		"the published artifact carries the certification schema"
	)
	_check(
		str((published.get("certification", {}) as Dictionary).get("acceptance_schema", ""))
			== Certification.ACCEPTANCE_SCHEMA,
		"the published artifact was minted by the current acceptance authority"
	)


## THE A2.12 BLOCKER, closed. `certify()` used to accept the completed chain and
## the verdict from its caller, so `{"chain": REQUIRED_CHAIN, "acceptance_report":
## {"pass": true}}` minted a certificate that verified, loaded through the
## production loader and assembled as `certified_bound` with zero gates run.
##
## Each case below goes through a real public boundary — the authority's own
## API, `verify`, `save` + `load_certified`, or the runtime loader — and must be
## refused with a named class.
func _test_certification_authority_owns_the_verdict() -> void:
	# ---- 1. ZERO GATES. `mint_from_observed_chain` is the only minting path,
	#         and it has no chain/verdict parameter at all. Called with no
	#         observed results it refuses and names the steps that never ran.
	var real: Dictionary = await _certify(Native.UTHANA_TARGET_GLB, ["right"])
	_check(bool(real.get("ok", false)), "the positive baseline certificate exists")
	if not bool(real.get("ok", false)):
		return
	var cert: Dictionary = real["certification"]
	var evidence: Dictionary = real["evidence"]
	var resolved: Dictionary = real["resolved"]
	var zero: Dictionary = Certification.mint_from_observed_chain(evidence, resolved, {})
	_check(
		str(zero.get("error_class", "")) == "FIXTURE_NOT_CERTIFIED"
		and str(zero.get("detail", "")).contains("assemble_and_measure"),
		"a zero-gate mint is refused and names the steps that never ran (%s)"
			% str(zero.get("detail", ""))
	)
	_check(not zero.has("certification"), "...and produces no envelope of any kind")
	# Every single required step is individually load-bearing.
	for dropped in Certification.REQUIRED_CHAIN:
		var partial: Dictionary = (real["steps"] as Dictionary).duplicate(true)
		partial.erase(dropped)
		var missing: Dictionary = Certification.mint_from_observed_chain(
			evidence, resolved, partial
		)
		_check(
			str(missing.get("error_class", "")) == "FIXTURE_NOT_CERTIFIED"
			and str(missing.get("detail", "")).contains(str(dropped)),
			"a chain that never ran '%s' cannot be certified" % dropped
		)
	# A step that claims to have run but observed nothing is not a step.
	var hollow: Dictionary = (real["steps"] as Dictionary).duplicate(true)
	hollow["assemble_and_measure"] = {"ok": true, "error_class": "", "observed": {}}
	_check(
		str(Certification.mint_from_observed_chain(evidence, resolved, hollow)
			.get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"a step with no observation cannot have run"
	)
	# An observation borrowed from another rig is cross-checked, not trusted.
	var borrowed: Dictionary = (real["steps"] as Dictionary).duplicate(true)
	((borrowed["rig_binding"] as Dictionary)["observed"] as Dictionary)["rig_sha256"] = (
		"7".repeat(64)
	)
	_check(
		str(Certification.mint_from_observed_chain(evidence, resolved, borrowed)
			.get("error_class", "")) == "FIXTURE_RIG_HASH_MISMATCH",
		"an observation about another rig is refused at mint time"
	)
	# A failing achieved-geometry observation cannot be overridden.
	var bad_patch: Dictionary = (real["steps"] as Dictionary).duplicate(true)
	((bad_patch["assemble_and_measure"] as Dictionary)["observed"] as Dictionary
		)["closest_patch"] = "nail"
	_check(
		str(Certification.mint_from_observed_chain(evidence, resolved, bad_patch)
			.get("error_class", "")) == "THUMB_SURFACE_TRUTH_GATE_FAILED",
		"an achieved contact on the nail cannot be certified"
	)

	# ---- 2. CALLER CLAIMS ARE INERT AT THE AUTHORITY'S OWN BOUNDARY. The
	#         A2.12 exploit keys are passed here verbatim, on a side the
	#         compiler classifies. They change nothing: the authority ignores
	#         them and reports what it actually observed.
	var claimed: Dictionary = await _certify(
		Native.UTHANA_TARGET_GLB,
		["left"],
		{
			"chain": Certification.REQUIRED_CHAIN.duplicate(),
			"acceptance_report": {"pass": true},
			"pass": true,
			"certified": true,
			"steps": (real["steps"] as Dictionary).duplicate(true),
		}
	)
	_check(
		not bool(claimed.get("ok", false)),
		"a caller-asserted chain and PASS do not certify a classified side"
	)
	_check(
		str(claimed.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"...and the refusal is the real compiler classification (%s)"
			% str(claimed.get("error_class", ""))
	)
	_check(
		str(claimed.get("stage", "")) == "fixture_compilation",
		"...named at the step that actually refused (%s)" % str(claimed.get("stage", ""))
	)
	_check(
		not (claimed.get("chain", []) as Array).has("assemble_and_measure"),
		"...and the recorded chain stops where the run stopped"
	)

	# ---- 3. FORGED REPORTS, EVERY ONE CORRECTLY RE-HASHED. The digest proves
	#         integrity, never truth: `verify` re-derives the verdict from the
	#         recorded step results and re-binds the report to the envelope.
	for row in [
		["a bare caller-authored PASS report", {"pass": true}, "FIXTURE_NOT_CERTIFIED"],
		[
			"a report that names no authority",
			_report_without(cert, "authority_id"),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report for another asset's geometry",
			_report_patch(cert, {"source_geometry_sha256": "3".repeat(64)}),
			"FIXTURE_GEOMETRY_HASH_MISMATCH",
		],
		[
			"a report for another asset's rig",
			_report_patch(cert, {"source_rig_sha256": "4".repeat(64)}),
			"FIXTURE_RIG_HASH_MISMATCH",
		],
		[
			"a report naming a policy that does not exist",
			_report_patch(cert, {"policy_id": "free_hand_wave_v0"}),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report naming another family",
			_report_patch(cert, {"family_id": "some_other_family"}),
			"FIXTURE_FAMILY_MISMATCH",
		],
		[
			"a report naming another family version",
			_report_patch(cert, {"family_version": "9999"}),
			"FIXTURE_FAMILY_VERSION_MISMATCH",
		],
		[
			"a report naming another calibration version",
			_report_patch(cert, {"policy_calibration_version": "77"}),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report whose chain omits a step",
			_report_patch(cert, {"chain": ["import", "family_resolution"]}),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report whose chain duplicates a step",
			_report_patch(cert, {"chain": _duplicated_chain()}),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report missing an actual step result",
			_report_without_step(cert, "assemble_and_measure"),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report with an invented extra step",
			_report_extra_step(cert, "definitely_ran_honest"),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report whose gate FAILED but whose conclusion says PASS",
			_report_step_patch(cert, "rig_binding", {"ok": false}),
			"FIXTURE_NOT_CERTIFIED",
		],
		[
			"a report whose step carries both a pass and an error class",
			_report_step_patch(cert, "rig_binding", {"error_class": "FIXTURE_RIG_HASH_MISMATCH"}),
			"FIXTURE_RIG_HASH_MISMATCH",
		],
		[
			"a report whose achieved contact was the nail",
			_report_measured(cert, {"closest_patch": "nail"}),
			"THUMB_SURFACE_TRUTH_GATE_FAILED",
		],
		[
			"a report whose grip invariants did not pass",
			_report_measured(cert, {"invariants_pass": false}),
			"GRIP_GEOMETRY_FAILED",
		],
	]:
		var label := str(row[0])
		var forged: Dictionary = _reseal(cert, {"acceptance_report": row[1]})
		_check(
			Certification.certification_hash(forged) == str(forged["certification_hash"]),
			"%s is internally self-consistent" % label
		)
		_check(
			str(Certification.verify(forged).get("error_class", "")) == str(row[2]),
			"%s is refused %s (%s)"
				% [label, row[2], str(Certification.verify(forged).get("error_class", ""))]
		)
		# ...and the same forgery survives neither a file nor the runtime path.
		var path := "user://a213_forged_certificate.tres"
		_check(
			bool(Certification.save(forged, path).get("ok", false)),
			"%s can be written to disk (the file is not the boundary)" % label
		)
		_check(
			str(Certification.load_certified(path).get("error_class", "")) == str(row[2]),
			"%s is refused by the production loader too" % label
		)
		_check(
			str(CompiledFixture.from_certified_artifact(
				forged, Calibration.payload(), "forged", _expect(evidence), ["right"]
			).get("error_class", "")) == str(row[2]),
			"%s never becomes a runtime fixture" % label
		)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# ---- 4. THE BIND-SANITY BOOTSTRAP ENVELOPE. The chain needs a fixture
	#         before a certificate exists. That object is now marked by its
	#         acceptance SCHEMA rather than by a flag nobody read.
	var bootstrap: Dictionary = Certification.mint_provisional(
		evidence, resolved, (real["steps"] as Dictionary).duplicate(true)
	)
	_check(bool(bootstrap.get("ok", false)), "the chain can mint a bind-sanity bootstrap")
	var boot_cert: Dictionary = bootstrap["certification"]
	_check(
		str(boot_cert.get("acceptance_schema", ""))
			== Certification.ACCEPTANCE_SCHEMA_PROVISIONAL,
		"the bootstrap envelope declares its own acceptance schema"
	)
	_check(
		not bool(boot_cert.get("certified", true)),
		"...and does not record a certification"
	)
	_check(
		str(Certification.verify(boot_cert).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"an ordinary verification refuses the bootstrap envelope"
	)
	_check(
		bool(Certification.verify(boot_cert, true).get("ok", false)),
		"only an explicit bind-sanity caller may use it"
	)
	_check(
		str(Certification.save(boot_cert, "user://a213_bootstrap.tres")
			.get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"the bootstrap envelope cannot be written to disk at all"
	)
	_check(
		str(CompiledFixture.from_certified_artifact(
			boot_cert, Calibration.payload(), "boot", _expect(evidence), ["right"]
		).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"...and is not a runtime fixture without the explicit opt-in"
	)

	# ---- 5. THE POSE CALIBRATION the acceptance was measured under is bound.
	var retuned: Dictionary = Calibration.payload()
	retuned["calibration_version"] = "999"
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, retuned, "retuned", _expect(evidence), ["right"]
		).get("error_class", "")) == "FIXTURE_CALIBRATION_VERSION_MISMATCH",
		"a retuned calibration may not reuse an acceptance measured under another"
	)
	var other_policy: Dictionary = Calibration.payload()
	other_policy["policy_id"] = "some_other_grip_v1"
	_check(
		str(CompiledFixture.from_certified_artifact(
			cert, other_policy, "other", _expect(evidence), ["right"]
		).get("error_class", "")) == "FIXTURE_POLICY_MISMATCH",
		"a certificate accepted under one grip policy may not be used under another"
	)


## Acceptance status is part of the canonical identity, so editing it is
## detectable without re-running the chain.
func _test_acceptance_metadata_cannot_be_manipulated() -> void:
	var loaded: Dictionary = Certification.load_certified(Composition.FIXTURE_ARTIFACT_PATH)
	_check(bool(loaded.get("ok", false)), "the production certificate loads for sabotage")
	if not bool(loaded.get("ok", false)):
		return
	var cert: Dictionary = loaded["certification"]
	# 1. Edit a field and do NOT re-hash: caught by the certification hash.
	for field in ["certified", "policy_version", "family_version", "acceptance_version"]:
		var edited: Dictionary = cert.duplicate(true)
		edited[field] = "tampered" if field != "certified" else false
		_check(
			str(Certification.verify(edited).get("error_class", ""))
				== "FIXTURE_CERTIFICATION_HASH_MISMATCH"
			or str(Certification.verify(edited).get("error_class", ""))
				== "FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED",
			"editing '%s' without re-hashing is detected" % field
		)
	# 2. Swap the acceptance report for another one that says "pass", keeping
	#    the digest: the digest is over the report itself, so this fails.
	var swapped: Dictionary = cert.duplicate(true)
	swapped["acceptance_report"] = {"pass": true, "note": "a different run entirely"}
	swapped.erase("certification_hash")
	swapped["certification_hash"] = Certification.certification_hash(swapped)
	_check(
		str(Certification.verify(swapped).get("error_class", ""))
			== "FIXTURE_CERTIFICATION_HASH_MISMATCH",
		"a substituted acceptance report does not match its digest"
	)
	# 3. Re-hash everything honestly, but with a report that is not a pass:
	#    a fully self-consistent certificate that still may not load.
	var honest_fail: Dictionary = cert.duplicate(true)
	honest_fail["acceptance_report"] = {"pass": false, "reason": "gate failed"}
	honest_fail["acceptance_report_digest"] = Certification.acceptance_report_digest(
		honest_fail["acceptance_report"]
	)
	honest_fail.erase("certification_hash")
	honest_fail["certification_hash"] = Certification.certification_hash(honest_fail)
	_check(
		str(Certification.verify(honest_fail).get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"a self-consistent certificate whose report is not a pass is refused"
	)
	# 4. `certified = false`, honestly re-hashed: still not a fixture.
	var not_certified: Dictionary = cert.duplicate(true)
	not_certified["certified"] = false
	not_certified.erase("certification_hash")
	not_certified["certification_hash"] = Certification.certification_hash(not_certified)
	_check(
		str(Certification.verify(not_certified).get("error_class", ""))
			== "FIXTURE_NOT_CERTIFIED",
		"an honestly re-hashed 'certified: false' envelope is refused"
	)


# ------------------------------------------------- mandatory fixture verification


## Verification is a declared contract, not a method that happens to exist.
func _test_fixture_verification_is_mandatory() -> void:
	OS.set_environment(Assembler.REFERENCE_MODE_ENV, "")
	var ctx: Dictionary = await _spawn(
		Native.UTHANA_TARGET_GLB, Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	)
	# 1. No contract at all: the case that used to pass as `authored_unbound`.
	var no_contract: Dictionary = await _assemble(ctx, NoContractFixture)
	_check(
		str(no_contract["result"].get("error_class", "")) == "FIXTURE_BINDING_UNSUPPORTED",
		"a fixture with no verification contract fails FIXTURE_BINDING_UNSUPPORTED (%s)"
			% str(no_contract["result"].get("error_class", ""))
	)
	_check(
		not bool((no_contract["binding"] as Dictionary).get("verified", false)),
		"...and is never recorded as verified"
	)
	# 2. An unknown contract is refused rather than trusted.
	_check(
		str((await _assemble(ctx, UnknownContractFixture))["result"].get("error_class", ""))
			== "FIXTURE_BINDING_UNSUPPORTED",
		"an unrecognised contract is refused"
	)
	# 3. The certified contract without the ability to honour it.
	_check(
		str((await _assemble(ctx, LyingCertifiedFixture))["result"].get("error_class", ""))
			== "FIXTURE_VERIFICATION_REQUIRED",
		"claiming the certified contract without verify_against_rig is refused"
	)
	# 4. `verified: false` returned from an ok verification must fail closed.
	var unverified: Dictionary = await _assemble(ctx, UnverifiedFixture)
	_check(
		str(unverified["result"].get("error_class", "")) == "FIXTURE_VERIFICATION_REQUIRED",
		"an ok result that does not claim verification fails closed (%s)"
			% str(unverified["result"].get("error_class", ""))
	)
	_check(
		str(unverified["result"].get("reason", "")) == "fixture_mesh_binding_failed",
		"...before any pose or socket work"
	)
	# 5. The real production fixture, whose family version must agree with the
	#    family actually injected.
	var fx: Dictionary = Composition.compiled_fixture(["right"])
	_check(bool(fx.get("ok", false)), "production fixture loads for the family check")
	if bool(fx.get("ok", false)):
		var foreign: Dictionary = await _assemble(
			ctx, fx["fixture"], ForeignVersionFamily
		)
		_check(
			str(foreign["result"].get("error_class", ""))
				== "FIXTURE_FAMILY_VERSION_MISMATCH",
			"assembling with a foreign family VERSION is refused (%s)"
				% str(foreign["result"].get("error_class", ""))
		)
		var unversioned: Dictionary = await _assemble(
			ctx, fx["fixture"], UnversionedFamily
		)
		_check(
			str(unversioned["result"].get("error_class", ""))
				== "FIXTURE_FAMILY_VERSION_MISMATCH",
			"a family that declares no version cannot assemble a certified fixture"
		)
	# 6. The decisive one: a fixture that implements the verification method
	#    PERFECTLY, and would therefore have satisfied the old duck-typed
	#    opt-in, is still refused because it declares no contract. Dispatch is
	#    on the declared contract, never on which methods happen to exist.
	var duck: Dictionary = await _assemble(ctx, DuckTypedFixture)
	_check(
		str(duck["result"].get("error_class", "")) == "FIXTURE_BINDING_UNSUPPORTED",
		"a fixture that only LOOKS verifiable is refused for lack of a contract (%s)"
			% str(duck["result"].get("error_class", ""))
	)
	_check(
		not bool((duck["binding"] as Dictionary).get("verified", false)),
		"...and its self-reported verification is never adopted"
	)
	(ctx["host"] as Node).queue_free()
	await process_frame


## The hand-authored A2.7 oracle is a test fixture. It must be unreachable from
## a production assembly and from a normal preview.
func _test_authored_oracle_is_test_only() -> void:
	_check(
		str(Oracle.fixture_verification_contract())
			== CompiledFixture.CONTRACT_TEST_ONLY_REFERENCE,
		"the authored oracle declares the test-only contract"
	)
	var ctx: Dictionary = await _spawn(
		Native.UTHANA_TARGET_GLB, Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	)
	# Normal production assembly: the oracle is refused, with no fallback.
	OS.set_environment(Assembler.REFERENCE_MODE_ENV, "")
	var production: Dictionary = await _assemble(ctx, Oracle)
	_check(
		str(production["result"].get("error_class", "")) == "FIXTURE_NOT_CERTIFIED",
		"the authored oracle through the normal production assembler is refused (%s)"
			% str(production["result"].get("error_class", ""))
	)
	_check(
		not bool((production["binding"] as Dictionary).get("verified", false)),
		"...and never assembles with verified: false, which is what it used to do"
	)
	# Asking for reference mode is not enough on its own: the environment gate
	# means a shipped runtime cannot open it even if a caller tries.
	var forbidden: Dictionary = await _assemble(ctx, Oracle, Family, true)
	_check(
		str(forbidden["result"].get("error_class", ""))
			== "FIXTURE_REFERENCE_MODE_FORBIDDEN",
		"reference mode fails closed outside a test environment (%s)"
			% str(forbidden["result"].get("error_class", ""))
	)
	# Both gates open: the explicit test-only path works, and says so.
	OS.set_environment(Assembler.REFERENCE_MODE_ENV, Assembler.REFERENCE_MODE_ENV_VALUE)
	var reference: Dictionary = await _assemble(ctx, Oracle, Family, true)
	_check(
		bool(reference["result"].get("ok", false)),
		"the explicit test-only reference mode assembles the oracle (%s)"
			% str(reference["result"].get("error_class", ""))
	)
	var binding: Dictionary = reference["binding"]
	_check(
		str(binding.get("binding", "")) == "test_only_reference"
		and bool(binding.get("reference_mode", false)),
		"the reference assembly declares itself as such, never as a certified binding"
	)
	# The production composition never opens either gate.
	var deps: Dictionary = Composition.dependencies(["right"])
	_check(
		not bool(deps.get("reference_fixture_mode", false)),
		"the production composition does not request reference mode"
	)
	_check(
		str(deps["fixture"].fixture_verification_contract())
			== CompiledFixture.CONTRACT_CERTIFIED_RUNTIME,
		"the production composition injects a certified-contract fixture"
	)
	(ctx["host"] as Node).queue_free()
	await process_frame


# ------------------------------------------------------------- raw a0 full chain


## The real ingestion step on the raw Mixamo delivery, in a SEPARATE Godot
## process. A2.13b turns this from a pinned rejection into a pinned ACCEPTANCE:
## once the compiled thumb surface is derived in a canonical space, the raw
## delivery resolves the same anatomical patches as the retargeted one and
## clears the same unchanged gates.
func _test_raw_a0_full_chain() -> void:
	var certified_out := "user://a213b_a0_certified.tres"
	var run: Dictionary = _ingest(
		A0_RAW_GLB, "user://a2_12_a0_evidence.tres", certified_out
	)
	var code: int = int(run["code"])
	var report: Dictionary = run["report"]
	_check(not report.is_empty(), "the a0 ingestion produced a machine-readable report")
	if report.is_empty():
		return
	_check(code == 0, "raw a0 exits 0 (accepted), got %d — %s"
		% [code, str(report.get("error_class", ""))])
	_check(bool(report.get("accepted", false)), "raw a0 is accepted")
	_check(bool(report.get("certified", false)), "raw a0 minted a certificate")
	_check(
		str(report.get("import_representation", "")) == "raw_mixamo",
		"the raw delivery is recognised as the raw Mixamo representation"
	)
	_check(
		(report.get("chain", []) as Array) == Certification.REQUIRED_CHAIN,
		"raw a0 completed exactly the acceptance chain (%s)" % str(report.get("chain", []))
	)
	# The height blocker is gone, measured in a separate process.
	var height: Dictionary = report.get("humanoid_height", {})
	_check(bool(height.get("ok", false)), "raw a0's humanoid height resolves")
	_check(
		absf(float(height.get("height", 0.0)) - EXPECTED_HUMANOID_HEIGHT) <= HEIGHT_TOLERANCE,
		"raw a0 measures the pinned height in a separate process (%.12f)"
			% float(height.get("height", 0.0))
	)
	_check(
		str(height.get("head_bone", "")).begins_with("mixamorig"),
		"raw a0's head landmark resolved through the family alias (%s)"
			% str(height.get("head_bone", ""))
	)
	_check(
		str(report.get("error_class", "")) != "DEGENERATE_HEIGHT",
		"raw a0 is no longer rejected as DEGENERATE_HEIGHT"
	)
	_check(
		str(report.get("stage_failed", "")) != "humanoid_normalization",
		"raw a0 no longer fails at normalization"
	)
	# The rig binding really ran, and really verified.
	var binding: Dictionary = (report.get("assembler", {}) as Dictionary).get(
		"mesh_binding", {}
	)
	_check(
		bool(binding.get("verified", false))
		and str(binding.get("binding", "")) == "certified_bound",
		"raw a0's rig binding verified against the live rig"
	)
	# A2.13b: the raw delivery now clears the achieved-geometry gate it used to
	# fail. The A2.11/A2.12 restpose diagnosis was refuted in A2.13a (a0 and a1
	# reach the same anatomical joint pose to ~1.5 degrees despite a 90-degree
	# rest-basis difference and a 100x armature scale); the real cause was the
	# COMPILED SURFACE, whose winding was decided by comparing a skeleton-space
	# face normal against a mesh-space shading normal. With the surface derived
	# in one canonical space, a0 resolves the same patches as a1.
	_check(
		str(report.get("stage_failed", "")).is_empty(),
		"raw a0 fails no chain step (%s)" % str(report.get("stage_failed", ""))
	)
	_check(
		bool((report.get("assembler", {}) as Dictionary).get("ok", false)),
		"raw a0 assembles through the real assembler (%s)"
			% str((report.get("assembler", {}) as Dictionary).get("error_class", ""))
	)
	_check(
		bool((report.get("grip_ground_truth", {}) as Dictionary).get("pass", false)),
		"raw a0 passes the achieved-geometry ground-truth gate"
	)
	_check(
		str((report.get("grip_ground_truth", {}) as Dictionary).get("closest_patch", ""))
			== "pad",
		"raw a0's achieved contact is the volar pad, not the nail"
	)
	# The certificate it minted is a real, loadable one for THIS rig.
	var cert: Dictionary = Certification.load_certified(certified_out)
	_check(bool(cert.get("ok", false)),
		"raw a0's published certificate reloads in this process (%s)"
			% str(cert.get("error_class", "")))
	_check(
		not str(report.get("certification_hash", "")).is_empty(),
		"raw a0's report carries a certification hash"
	)
	_a0_gate_metrics = report.get("gate_metrics", {})
	_a0_surface = (report.get("sides", {}) as Dictionary).get("right", {})
	# The left hand keeps its own, unchanged classification.
	var sides: Dictionary = report.get("sides", {})
	_check(
		str((sides.get("left", {}) as Dictionary).get("error_class", ""))
			== "PAD_PATCH_AMBIGUOUS",
		"a0's left hand keeps PAD_PATCH_AMBIGUOUS (%s)"
			% str((sides.get("left", {}) as Dictionary).get("error_class", ""))
	)


## The SAME ingestion step, the SAME parsing, on the asset that passes. a0 and
## a1 are read through one helper on purpose: A2.12 parsed the two subprocess
## runs differently, so an a1 regression could not have been seen next to the a0
## rejection it is supposed to contrast with.
func _test_a1_full_chain_accepts_and_publishes() -> void:
	var certified_out := "user://a213_a1_certified.tres"
	var run: Dictionary = _ingest(
		Native.UTHANA_TARGET_GLB, "user://a213_a1_evidence.tres", certified_out
	)
	var code: int = int(run["code"])
	var report: Dictionary = run["report"]
	_check(not report.is_empty(), "the a1 ingestion produced a machine-readable report")
	if report.is_empty():
		return
	_check(code == 0, "a1 exits 0 (accepted), got %d — %s"
		% [code, str(report.get("error_class", ""))])
	_check(bool(report.get("accepted", false)), "a1 is accepted")
	_check(bool(report.get("certified", false)), "a1 minted a certificate")
	_check(
		(report.get("chain", []) as Array) == Certification.REQUIRED_CHAIN,
		"a1 completed exactly the acceptance chain (%s)" % str(report.get("chain", []))
	)
	_check(
		str(report.get("acceptance_schema", "")) == Certification.ACCEPTANCE_SCHEMA,
		"a1's certificate carries the current acceptance schema (%s)"
			% str(report.get("acceptance_schema", ""))
	)
	_check(
		str(report.get("acceptance_authority_id", "")) == Certification.AUTHORITY_ID,
		"a1's certificate names the certification authority"
	)
	_check(
		str((report.get("grip_ground_truth", {}) as Dictionary).get("closest_patch", ""))
			== "pad",
		"a1's achieved contact is the volar pad"
	)
	# INSTRUMENTED across the process boundary: the gates really were invoked.
	var calls: Dictionary = report.get("gate_calls", {})
	for gate in ["import", "compile", "artifact_reload", "rig_identity_of_asset",
			"assemble", "surface_read", "mint"]:
		_check(int(calls.get(gate, 0)) >= 1, "a1's chain invoked '%s' in the real step" % gate)
	# The published certificate is a real file, and it verifies from disk in
	# THIS process — a cross-process determinism check on the envelope hash.
	var loaded: Dictionary = Certification.load_certified(certified_out)
	_check(
		bool(loaded.get("ok", false)),
		"a1's published certificate verifies in another process (%s)"
			% str(loaded.get("error_class", ""))
	)
	_check(
		str((loaded.get("certification", {}) as Dictionary).get("certification_hash", ""))
			== str(report.get("certification_hash", "")),
		"the certificate on disk is the certificate the step reported"
	)
	# ...and it still has to pass LIVE runtime re-verification to be usable.
	if bool(loaded.get("ok", false)):
		var ctx: Dictionary = await _spawn(Native.UTHANA_TARGET_GLB, Vector3.ONE)
		var fx: Dictionary = CompiledFixture.from_certified_artifact(
			loaded["certification"],
			Calibration.payload(),
			"a213_published",
			_expect(loaded["evidence"]),
			["right"]
		)
		_check(
			bool(fx.get("ok", false)),
			"the published certificate becomes a runtime fixture (%s)"
				% str(fx.get("error_class", ""))
		)
		if bool(fx.get("ok", false)):
			var live: Dictionary = fx["fixture"].verify_against_rig(
				ctx["mesh"], ctx["skeleton"]
			)
			_check(
				bool(live.get("ok", false)) and bool(live.get("verified", false)),
				"...and re-verifies against the LIVE rig, which is the safety property"
			)
			var asm: Dictionary = await _assemble(ctx, fx["fixture"])
			_check(
				bool(asm["result"].get("ok", false)),
				"...and assembles through the real assembler (%s)"
					% str(asm["result"].get("error_class", ""))
			)
			_check(
				str((asm["binding"] as Dictionary).get("binding", "")) == "certified_bound",
				"...as a certified binding"
			)
		(ctx["host"] as Node).queue_free()
		await process_frame
	_a1_gate_metrics = report.get("gate_metrics", {})
	_a1_surface = (report.get("sides", {}) as Dictionary).get("right", {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(certified_out))


## THE SLICE'S CENTRAL CLAIM, measured across the two real CLI runs: two
## deliveries of one humanoid, one raw and one retargeted, 100x apart in
## armature scale and 90 degrees apart in hand rest basis, must resolve the SAME
## anatomical surface and therefore land on the same side of the same unchanged
## gates. Triangle indices may be renumbered by the export; the compiled surface
## may not differ.
func _test_two_representations_agree() -> void:
	if _a0_surface.is_empty() or _a1_surface.is_empty():
		_check(false, "both representations reported a right-hand surface")
		return
	for field in ["nail_tris", "pad_tris"]:
		_check(
			int(_a0_surface.get(field, -1)) == int(_a1_surface.get(field, -2)),
			"both representations resolve the same %s (%d vs %d)" % [
				field, int(_a0_surface.get(field, -1)), int(_a1_surface.get(field, -2))
			]
		)
	var a0a: Dictionary = _a0_gate_metrics.get("achieved", {})
	var a1a: Dictionary = _a1_gate_metrics.get("achieved", {})
	var limits: Dictionary = _a1_gate_metrics.get("limits", {})
	_check(not a0a.is_empty() and not a1a.is_empty(),
		"both runs reported achieved gate metrics")
	# Reported, then bounded. A pair that agrees to a few thousandths is the
	# evidence; the printed values are what the slice report quotes.
	for field in [
		"approach_axial_fraction", "approach_radial_radii", "winding_thumb_deg",
		"nail_out_dot", "pad_in_dot", "nail_pad_dot",
	]:
		var v0: float = float(a0a.get(field, NAN))
		var v1: float = float(a1a.get(field, NAN))
		print("A213B_GATE %s a0=%.6f a1=%.6f" % [field, v0, v1])
	for field in ["approach_axial_fraction", "approach_radial_radii"]:
		var gap: float = absf(float(a0a.get(field, 0.0)) - float(a1a.get(field, 1.0)))
		_check(
			gap <= REPRESENTATION_GATE_TOLERANCE,
			"the two representations agree on %s to %.6f (<= %.4f)"
				% [field, gap, REPRESENTATION_GATE_TOLERANCE]
		)
	# The R4 margin is thin on BOTH assets, and saying so is part of the result.
	var axial_limit: float = float(limits.get("THUMB_APPROACH_AXIAL_FRAC_MAX", 0.60))
	for pair in [["a0", a0a], ["a1", a1a]]:
		var m: Dictionary = pair[1]
		print("A213B_R4_MARGIN %s axial=%.6f limit=%.4f margin=%.6f radial=%.6f" % [
			str(pair[0]),
			float(m.get("approach_axial_fraction", NAN)),
			axial_limit,
			axial_limit - float(m.get("approach_axial_fraction", NAN)),
			float(m.get("approach_radial_radii", NAN)),
		])
		_check(
			float(m.get("approach_axial_fraction", 9.0)) <= axial_limit,
			"%s clears the UNCHANGED R4 axial limit (%.6f <= %.4f)"
				% [str(pair[0]), float(m.get("approach_axial_fraction", 9.0)), axial_limit]
		)


# ---------------------------------------------------------------------- helpers


func _spawn(glb: String, scale: Vector3) -> Dictionary:
	var host := Node3D.new()
	host.scale = scale
	root.add_child(host)
	var character: Node3D = (load(glb) as PackedScene).instantiate()
	host.add_child(character)
	await process_frame
	var skeleton: Skeleton3D = Skinning.find_skeleton(character)
	skeleton.force_update_all_bone_transforms()
	return {
		"host": host,
		"character": character,
		"skeleton": skeleton,
		"mesh": Skinning.find_skinned_mesh(character),
	}


## Assemble through the REAL assembler with the REAL composition dependencies,
## overriding only the fixture, the family and the reference-mode flag.
func _assemble(
	ctx: Dictionary, fixture, family = Family, reference_mode: bool = false
) -> Dictionary:
	var deps: Dictionary = Composition.dependencies(["right"])
	deps["fixture"] = fixture
	deps["family"] = family
	if reference_mode:
		deps["reference_fixture_mode"] = true
	var asm: Node = Assembler.new()
	asm.configure_dependencies(deps)
	(ctx["host"] as Node).add_child(asm)
	var result: Dictionary = asm.assemble(ctx["character"], "right")
	var binding: Dictionary = asm.mesh_binding()
	asm.queue_free()
	await process_frame
	return {"result": result, "binding": binding}


func _expect(evidence: Dictionary) -> Dictionary:
	return {
		"geometry_sha256": str(evidence.get("source_geometry_sha256", "")),
		"rig_sha256": str(evidence.get("source_rig_sha256", "")),
		"family_id": str(Family.FAMILY_ID),
		"family_version": str(Family.FAMILY_VERSION),
	}


## Run the REAL acceptance chain in this process, through the certification
## authority's own public API. `extra` is merged into the context to prove that
## caller-supplied claims are inert: the authority has no parameter for a chain,
## a verdict or a gate result, so anything of the sort is simply ignored.
func _certify(glb: String, required: Array, extra: Dictionary = {}) -> Dictionary:
	var context := {
		"host": root,
		"glb": glb,
		"staging_path": "user://a213_authority_staging.tres",
		"sides": ["right", "left"],
		"required_sides": required,
		"policy_id": str(Policy.POLICY_ID),
		"weapon_path": CLUB_GLB,
		"family_id": "mixamo_52_humanoid",
		"asset_id": "a213_authority_probe",
	}
	for k in extra.keys():
		context[str(k)] = extra[k]
	var outcome: Dictionary = await Authority.new().run(context)
	await process_frame
	return outcome


## A certificate with fields replaced, its report digest and its own hash both
## recomputed honestly. Sabotage that no hash check can catch.
func _reseal(cert: Dictionary, overrides: Dictionary) -> Dictionary:
	var forged: Dictionary = cert.duplicate(true)
	for k in overrides.keys():
		forged[str(k)] = overrides[k]
	forged["acceptance_report_digest"] = Certification.acceptance_report_digest(
		forged.get("acceptance_report", {})
	)
	forged.erase("certification_hash")
	forged["certification_hash"] = Certification.certification_hash(forged)
	return forged


func _report(cert: Dictionary) -> Dictionary:
	return (cert.get("acceptance_report", {}) as Dictionary).duplicate(true)


func _report_patch(cert: Dictionary, patch: Dictionary) -> Dictionary:
	var r: Dictionary = _report(cert)
	for k in patch.keys():
		r[str(k)] = patch[k]
	return r


func _report_without(cert: Dictionary, field: String) -> Dictionary:
	var r: Dictionary = _report(cert)
	r.erase(field)
	return r


func _report_without_step(cert: Dictionary, step: String) -> Dictionary:
	var r: Dictionary = _report(cert)
	(r["steps"] as Dictionary).erase(step)
	return r


func _report_extra_step(cert: Dictionary, step: String) -> Dictionary:
	var r: Dictionary = _report(cert)
	(r["steps"] as Dictionary)[step] = {
		"ok": true, "error_class": "", "observed": {"note": "invented"}
	}
	return r


func _report_step_patch(cert: Dictionary, step: String, patch: Dictionary) -> Dictionary:
	var r: Dictionary = _report(cert)
	var s: Dictionary = (r["steps"] as Dictionary)[step]
	for k in patch.keys():
		s[str(k)] = patch[k]
	return r


func _report_measured(cert: Dictionary, patch: Dictionary) -> Dictionary:
	var r: Dictionary = _report(cert)
	var observed: Dictionary = ((r["steps"] as Dictionary)["assemble_and_measure"]
		as Dictionary)["observed"]
	for k in patch.keys():
		observed[str(k)] = patch[k]
	return r


func _duplicated_chain() -> Array:
	var out: Array = Certification.REQUIRED_CHAIN.duplicate()
	out.remove_at(out.size() - 1)
	out.append(str(out[0]))
	return out


## Run the REAL headless ingestion step in a SEPARATE Godot process. One helper
## for every asset, so the accepted and the rejected run are read identically.
func _ingest(glb: String, out_path: String, certified_out: String) -> Dictionary:
	var out: Array = []
	var code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", CERTIFY_SCRIPT, "--",
			"--glb=%s" % glb,
			"--out=%s" % out_path,
			"--certified-out=%s" % certified_out,
			"--policy=power_grip_1h_v1",
			"--weapon=%s" % CLUB_GLB,
			"--sides=right,left",
			"--required=right",
		]),
		out,
		true
	)
	return {
		"code": code,
		"report": _parse_report("\n".join(PackedStringArray(out))),
		"stdout": "\n".join(PackedStringArray(out)),
	}


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


# -------------------------------------------------------------- test doubles


## The pre-A2.12 shape: a fixture that simply does not implement verification.
## It used to assemble as `authored_unbound`.
class NoContractFixture:
	const Real = preload(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
	)
	const SCHEMA_VERSION := "no_contract_v0"
	const ASSET_ID := "no_contract_v0"

	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return Real.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return Real.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return Real.finger_flex()


## Declares a contract nobody knows. Must be refused, not trusted.
class UnknownContractFixture:
	const Base = preload("res://presentation/tests/test_hand_fixture_certification.gd")

	static func fixture_verification_contract() -> String:
		return "something_invented_v9"

	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return NoContractFixture.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return NoContractFixture.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return NoContractFixture.finger_flex()


## Claims the certified contract but cannot honour it.
class LyingCertifiedFixture:
	static func fixture_verification_contract() -> String:
		return "certified_runtime_v1"

	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return NoContractFixture.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return NoContractFixture.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return NoContractFixture.finger_flex()


## Implements the verification method flawlessly but declares no contract: the
## exact shape that used to be waved through by `has_method`.
class DuckTypedFixture:
	static func verify_against_rig(_mi: MeshInstance3D, _sk: Skeleton3D) -> Dictionary:
		return {"ok": true, "verified": true, "geometry_sha256": "0".repeat(64)}

	static func certified_family() -> Dictionary:
		return {"family_id": "mixamo_52_humanoid", "family_version": "3"}

	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return NoContractFixture.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return NoContractFixture.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return NoContractFixture.finger_flex()


## Honours the contract and answers "ok, but not verified". Fail-closed.
class UnverifiedFixture:
	static func fixture_verification_contract() -> String:
		return "certified_runtime_v1"

	static func verify_against_rig(_mi: MeshInstance3D, _sk: Skeleton3D) -> Dictionary:
		return {"ok": true, "verified": false}

	static func certified_family() -> Dictionary:
		return {"family_id": "mixamo_52_humanoid", "family_version": "3"}

	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return NoContractFixture.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return NoContractFixture.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return NoContractFixture.finger_flex()


## The real family conventions under a bumped version: a certificate issued for
## another family version may not drive this rig.
class ForeignVersionFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := Real.FAMILY_ID
	const FAMILY_VERSION := "9999"
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func resolved_bone_map(skeleton: Skeleton3D, side: String) -> Dictionary:
		return Real.resolved_bone_map(skeleton, side)

	static func bone_map(side: String) -> Dictionary:
		return Real.bone_map(side)


## A family with no version at all: an empty expectation is a refusal.
class UnversionedFamily:
	const Real = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
	const FAMILY_ID := Real.FAMILY_ID
	const FAMILY_VERSION := ""
	const MCP_HINGE_LOCAL := Real.MCP_HINGE_LOCAL
	const DISTAL_TIP_FRACTION := Real.DISTAL_TIP_FRACTION

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return Real.resolved_height_landmarks(skeleton)

	static func resolved_bone_map(skeleton: Skeleton3D, side: String) -> Dictionary:
		return Real.resolved_bone_map(skeleton, side)

	static func bone_map(side: String) -> Dictionary:
		return Real.bone_map(side)


## A family that declares no semantic landmarks: height must fail closed
## rather than the generic utility inventing a name list of its own.
class NoLandmarkFamily:
	const FAMILY_ID := "no_landmarks_v0"
	const FAMILY_VERSION := "1"

	static func bone_map(_side: String) -> Dictionary:
		return {}


## Landmark aliases that resolve to bones on no skeleton.
class WrongAliasFamily:
	const FAMILY_ID := "wrong_alias_v0"
	const FAMILY_VERSION := "1"

	static func resolved_height_landmarks(_skeleton: Skeleton3D) -> Dictionary:
		return {
			"ok": false,
			"error_class": "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
			"detail": "aliases point at bones this rig does not have",
			"unresolved": ["head_top", "floor_contact"],
			"roles": {},
		}

	static func bone_map(_side: String) -> Dictionary:
		return {}


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)
