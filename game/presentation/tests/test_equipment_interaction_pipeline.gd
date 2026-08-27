# A2.8 / A2.8b / A2.9 generic / bilateral equipment-interaction pipeline.
# Distinguishes algorithm, family compile, warrior fixture, right parity,
# left semantic mirroring, policy, assembly order, knowledge ownership and
# TRUE dependency injection (family/fixture/skinning/weapon/engine).
# Left full assemble remains a classified T2 blocker.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Playback = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const FIXTURE_PATH := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)
const Fixture = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const Policy = preload("res://presentation/equipment/grip_interaction_profile.gd")
const PowerGrip1hPolicy = preload("res://presentation/equipment/power_grip_1h_policy.gd")
const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const GripGeom = preload("res://presentation/equipment/equipment_grip_geometry.gd")
const Solver = preload("res://presentation/equipment/hand_grip_solver.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Engine1h = preload("res://presentation/equipment/power_grip_1h_engine.gd")


## Architecture-only injection stubs: same underlying Uthana/Mixamo data,
## different identity — proves the core consumes INJECTED dependencies.
## This is not visual multi-unit validation.
class StubFamily:
	const FAMILY_ID := "stub_family_v0"
	const MCP_HINGE_LOCAL := Vector3(1.0, 0.0, 0.0)
	const DISTAL_TIP_FRACTION := 0.9
	const RealFamily = preload("res://presentation/equipment/mixamo_52_hand_family.gd")

	static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
		return RealFamily.resolved_height_landmarks(skeleton)

	static func bone_map(side: String) -> Dictionary:
		return RealFamily.bone_map(side)


class StubFixture:
	const SCHEMA_VERSION := "stub_fixture_v0"
	const ASSET_ID := "stub_asset_v0"
	const RealFixture = preload(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
	)

	## A2.12: a test double is a TEST-ONLY reference fixture. It carries no
	## source-rig identity, so it can never satisfy the certified contract, and
	## the assembler only accepts it when this test explicitly opens reference
	## mode. Declaring the contract is what makes that refusal explicit instead
	## of the old silent "no verify method, therefore fine".
	static func fixture_verification_contract() -> String:
		return "test_only_reference_v1"


	static func surface_for_side(
		side: String, character: Node, skeleton: Skeleton3D, bone_map: Dictionary = {}
	) -> Dictionary:
		return RealFixture.surface_for_side(side, character, skeleton, bone_map)

	static func thumb_anat_for_side(side: String) -> Dictionary:
		return RealFixture.thumb_anat_for_side(side)

	static func finger_flex() -> Dictionary:
		return RealFixture.finger_flex()


## A2.9b: a FULLY SYNTHETIC fixture — no Uthana triangle IDs, no Uthana
## normals, no delegation to the real fixture. It exists to prove the core
## consumes fixture DATA it has never seen, and that fabricated surface
## evidence is rejected downstream by the surface-truth gate instead of
## being silently accepted. It is deliberately NOT a valid grip.
class SyntheticFixture:
	const SCHEMA_VERSION := "synthetic_fixture_v0"
	const ASSET_ID := "synthetic_unit_v0"
	const EXPECTED_FAMILY_ID := "synthetic_family_v0"

	## A2.12: a test double is a TEST-ONLY reference fixture. It carries no
	## source-rig identity, so it can never satisfy the certified contract, and
	## the assembler only accepts it when this test explicitly opens reference
	## mode. Declaring the contract is what makes that refusal explicit instead
	## of the old silent "no verify method, therefore fine".
	static func fixture_verification_contract() -> String:
		return "test_only_reference_v1"


	## Fabricated distal patches: low triangle indices that exist on any
	## reasonably dense mesh, with invented UVs and orthogonal plate normals.
	const SYNTH_NAIL_TRIS: Array[Dictionary] = [
		{"si": 0, "i": [0, 1, 2], "uvc": Vector2(0.1, 0.1), "flip": -1.0},
		{"si": 0, "i": [1, 2, 3], "uvc": Vector2(0.1, 0.2), "flip": -1.0},
	]
	const SYNTH_PAD_TRIS: Array[Dictionary] = [
		{"si": 0, "i": [4, 5, 6], "uvc": Vector2(0.2, 0.1), "flip": -1.0},
		{"si": 0, "i": [5, 6, 7], "uvc": Vector2(0.2, 0.2), "flip": -1.0},
	]

	static func surface_for_side(
		side: String, _character: Node, _skeleton: Skeleton3D, _bone_map: Dictionary = {}
	) -> Dictionary:
		return {
			"compiled": true,
			"source": "synthetic_v0_%s" % side,
			"nail_tris": SYNTH_NAIL_TRIS,
			"pad_tris": SYNTH_PAD_TRIS,
			"nail_normal_local": Vector3(1.0, 0.0, 0.0),
			"pad_normal_local": Vector3(0.0, 0.0, 1.0),
			"rest_nail_pad_dot": 0.0,
			"pad_marker_local": Vector3(0.01, 0.0, 0.0),
		}

	static func thumb_anat_for_side(_side: String) -> Dictionary:
		return {"sigma": 20.0, "phi": 0.0, "tau": -60.0, "flex_mcp": 10.0, "flex_ip": 80.0}

	static func finger_flex() -> Dictionary:
		return {
			"index": [60.0, 71.0, 35.0],
			"middle": [63.0, 75.0, 37.0],
			"ring": [69.0, 81.0, 40.0],
			"pinky": [71.0, 83.0, 43.0],
		}


var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	# A2.12: this suite drives the assembler with TEST DOUBLES, which declare
	# the test-only reference contract. Reference mode needs both an explicit
	# per-assembly opt-in and this environment gate, so the doubles are usable
	# here and unreachable from a shipped runtime or a normal preview.
	OS.set_environment(Assembler.REFERENCE_MODE_ENV, Assembler.REFERENCE_MODE_ENV_VALUE)
	_test_generic_owners()
	_test_generic_has_no_a2_assets()
	_test_fixture_evidence_ownership()
	_test_injection_negatives()
	var host := Node.new()
	root.add_child(host)
	var right_ctx: Dictionary = await _spawn_side(host, "right", 0.35)
	var left_ctx: Dictionary = await _spawn_side(host, "left", 0.35, true)
	await _test_compiled_fixture_is_the_production_path(host)
	_test_family_and_fixture(right_ctx, left_ctx)
	_test_right_parity(right_ctx)
	_test_left_semantics(left_ctx)
	_test_assembly_order(right_ctx)
	_test_negatives(right_ctx, left_ctx)
	_test_policy_reserved()
	_test_policy_ownership()
	await _test_injection_stub(host)
	await _test_synthetic_unit_injection(host)
	print(
		"test_equipment_interaction_pipeline: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	quit(1 if _any_fail else 0)


func _test_generic_owners() -> void:
	_check(Family.FAMILY_ID == "mixamo_52_humanoid", "family id")
	_check(Policy.is_implemented(Policy.POLICY_POWER_GRIP_1H), "power_grip_1h_v1 implemented")
	_check(not Policy.requires_secondary(Policy.POLICY_POWER_GRIP_1H), "1h needs no secondary IK")
	_check(Policy.requires_secondary("power_grip_2h_support_v1"), "2h support reserved as secondary")
	_check(not Policy.is_implemented("shield_grip_v1"), "shield not implemented")
	_check(Family.bone_map("left")["hand"] == "LeftHand", "left wrist bone")
	_check(Family.bone_map("right")["hand"] == "RightHand", "right wrist bone")
	_check(
		str(Family.bone_map("left")["thumb"][0]).contains("Left"),
		"left thumb chain is left-named"
	)


func _test_generic_has_no_a2_assets() -> void:
	# A2.9 forbidden-dependency contract: the generic CORE files may not
	# preload or reference Uthana/A1/A2 scripts, asset paths, preview scenes
	# or the demo club — checked on SCRIPT source, not only .glb/.tscn.
	var core := [
		"res://presentation/equipment/humanoid_hand_profile.gd",
		"res://presentation/equipment/equipment_grip_geometry.gd",
		"res://presentation/equipment/grip_interaction_profile.gd",
		"res://presentation/equipment/power_grip_1h_policy.gd",
		"res://presentation/equipment/hand_grip_solver.gd",
		"res://presentation/equipment/equipment_assembler.gd",
		"res://presentation/equipment/power_grip_1h_engine.gd",
		"res://presentation/equipment/skinned_mesh_geometry.gd",
		"res://presentation/equipment/melee_1h_normalize.gd",
		"res://presentation/equipment/melee_grip_shape.gd",
	]
	var forbidden := [
		"uthana_a1",
		"uthana_a2",
		"uthana_warrior_hand_fixture",
		"mixamo_52_hand_family",
		"wooden_club",
		"WoodenClub",
		"walking_preview",
		"res://assets/",
		"mixamorig",
		"T3_NAIL",
		"CANON_THUMB_ANAT",
		"SUPERSEDED_A25",
		"5486",
	]
	for path in core:
		var f := FileAccess.open(path, FileAccess.READ)
		_check(f != null, "readable %s" % path)
		if f == null:
			continue
		var src: String = f.get_as_text()
		for token in forbidden:
			_check(
				not src.contains(str(token)),
				"core %s has no '%s' dependency" % [path.get_file(), token]
			)
	# The generic equipment directory must not CONTAIN a unit fixture at
	# all: a path the core cannot reach cannot be silently defaulted to.
	_check(
		not ResourceLoader.exists("res://presentation/equipment/uthana_warrior_hand_fixture.gd"),
		"no unit fixture left inside the generic equipment directory"
	)
	var listed := DirAccess.get_files_at("res://presentation/equipment")
	var stray: Array[String] = []
	for fname in listed:
		var lower := str(fname).to_lower()
		if lower.begins_with("uthana") or lower.contains("warrior") or lower.contains("club"):
			stray.append(str(fname))
	_check(
		stray.is_empty(),
		"generic equipment directory holds no unit/asset-specific file (%s)" % str(stray)
	)
	# The family file is DATA (bone names allowed) but may not reach into
	# assets or previews either.
	var fam := FileAccess.open(
		"res://presentation/equipment/mixamo_52_hand_family.gd", FileAccess.READ
	)
	_check(fam != null, "readable family file")
	if fam != null:
		var fsrc: String = fam.get_as_text()
		for token in ["uthana_a1", "uthana_a2", "res://assets/", "walking_preview", "T3_NAIL", "5486"]:
			_check(
				not fsrc.contains(str(token)),
				"family file has no '%s' dependency" % token
			)


func _test_fixture_evidence_ownership() -> void:
	_check(Fixture.SCHEMA_VERSION == "uthana_hand_fixture_v1", "fixture schema versioned")
	_check(
		Fixture.GLB_SHA256.begins_with("ADFE53DB59FE21D9"),
		"fixture mesh identity pinned"
	)
	_check(
		absf(float(Fixture.REJECTED_A26_THUMB_ANAT["tau"]) + 90.0) < 0.01,
		"rejected A2.6 tau=-90 retained as evidence"
	)
	_check(
		absf(float(Fixture.ACCEPTED_A27_THUMB_ANAT["tau"]) + 60.0) < 0.01,
		"accepted A2.7 tau=-60 retained as evidence"
	)
	_check(
		Fixture.SUPERSEDED_A25_NAIL_NORMAL_LOCAL.distance_to(Fixture.RIGHT_NAIL_NORMAL_LOCAL) > 0.5,
		"superseded A2.5 nail constant kept distinct from A2.7 plate"
	)
	_check(Fixture.PATCH_WINDING_FLIP == -1.0, "rest-anchored winding flip retained")
	# A2.9b: the fixture is unit data that lives WITH the unit and does not
	# select its own skeleton family — the composition root does.
	_check(
		FIXTURE_PATH.begins_with("res://assets/prototype/3d/units/generated_warrior/")
		and ResourceLoader.exists(FIXTURE_PATH),
		"fixture lives with the unit, not in the generic core (%s)" % FIXTURE_PATH
	)
	_check(
		Fixture.EXPECTED_FAMILY_ID == "mixamo_52_humanoid",
		"fixture records the family it was compiled against as DATA"
	)
	var fx := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	_check(fx != null, "readable fixture file")
	if fx != null:
		var fxsrc: String = fx.get_as_text()
		_check(
			not fxsrc.contains("preload(\"res://presentation/equipment/mixamo_52_hand_family.gd\")"),
			"fixture does not preload/select a skeleton family"
		)
	_check(Fixture.PATCH_BIND_THUMB3_MIN == 2, "bind-weight patch sanity retained")
	var bare: Dictionary = HandProfile.compile(null, null, "right", null, Family, Skinning)
	_check(not bool(bare.get("ok", true)), "compile without fixture fail-closed")
	_check(
		(bare.get("failures", []) as Array).has("HAND_PROFILE_FIXTURE_REQUIRED"),
		"missing fixture is classified HAND_PROFILE_FIXTURE_REQUIRED"
	)
	var no_family: Dictionary = HandProfile.compile(null, null, "right", Fixture, null, Skinning)
	_check(
		(no_family.get("failures", []) as Array).has("HAND_PROFILE_FAMILY_REQUIRED"),
		"missing family is classified HAND_PROFILE_FAMILY_REQUIRED"
	)
	var no_skin: Dictionary = HandProfile.compile(null, null, "right", Fixture, Family, null)
	_check(
		(no_skin.get("failures", []) as Array).has("HAND_PROFILE_SKINNING_REQUIRED"),
		"missing skinning is classified HAND_PROFILE_SKINNING_REQUIRED"
	)


## `use_reference_fixture` injects the hand-authored A2.7 oracle instead of
## the compiled artifact. A2.10 keeps the oracle for reference/regression
## only: the left hand has no certified compiled fixture (its volar pad is
## PAD_PATCH_AMBIGUOUS on this mesh), so the left frame/semantics
## regressions still run against the authored reference while the production
## right-hand path runs entirely off the compiled artifact.
func _spawn_side(
	host: Node, side: String, t: float, use_reference_fixture: bool = false
) -> Dictionary:
	var root := Node3D.new()
	root.name = "Host_%s" % side
	host.add_child(root)
	var model := Node3D.new()
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	root.add_child(model)
	var uthana: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(uthana)
	await process_frame
	var sk: Skeleton3D = Native.find_skeleton(uthana)
	var lib: AnimationLibrary = Native.ensure_walking_library()
	var player := AnimationPlayer.new()
	uthana.add_child(player)
	var clip: String = Playback.attach_looping_clip(
		player, lib.get_animation(Native.WALKING_CLIP), Native.WALKING_CLIP
	)
	player.play(clip)
	player.seek(t, true)
	await process_frame
	sk.force_update_all_bone_transforms()
	var asm: Node
	if use_reference_fixture:
		var deps: Dictionary = Composition.dependencies()
		deps["fixture"] = Fixture
		deps["reference_fixture_mode"] = true
		asm = Assembler.new()
		asm.configure_dependencies(deps)
	else:
		asm = Composition.make_assembler()
	asm.name = "Asm_%s" % side
	root.add_child(asm)
	var result: Dictionary = asm.assemble(uthana, side)
	return {
		"side": side,
		"character": uthana,
		"skeleton": sk,
		"player": player,
		"clip": clip,
		"assembler": asm,
		"result": result,
	}


## A2.10: the Uthana production composition must resolve its fixture from
## the COMPILED artifact, and must never silently fall back to the authored
## oracle when the artifact is unusable.
func _test_compiled_fixture_is_the_production_path(host: Node) -> void:
	var deps: Dictionary = Composition.dependencies()
	var fx = deps.get("fixture", null)
	_check(fx != null, "composition resolved a fixture (%s)" % str(deps.get("fixture_error", "")))
	if fx == null:
		return
	_check(
		str(fx.SCHEMA_VERSION) == "hand_fixture_evidence_v4",
		"production fixture is a compiled artifact, not the authored script (%s)"
			% str(fx.SCHEMA_VERSION)
	)
	_check(
		str(fx.fixture_verification_contract()) == "certified_runtime_v1",
		"production fixture declares the certified runtime contract (%s)"
			% str(fx.fixture_verification_contract())
	)
	_check(
		fx.has_method("evidence_for_side"),
		"production fixture carries compiler evidence"
	)
	var art: Dictionary = fx.artifact
	_check(str(art.get("compiler_version", "")) == "hand_fixture_compiler_v4", "compiler version")
	_check(str(art.get("family_id", "")) == "mixamo_52_humanoid", "artifact family id")
	_check(str(art.get("source_geometry_sha256", "")).length() == 64, "artifact geometry sha256")
	_check(str(art.get("source_rig_sha256", "")).length() == 64, "artifact rig sha256")
	# The production fixture is BOUND: it carries the source identities the
	# composition derived from this unit's own rigged asset, and the assembler
	# re-verifies them against the rig it poses.
	_check(
		str(fx.expected_rig_sha256) == str(art.get("source_rig_sha256", "")),
		"production fixture declares the expected source rig identity"
	)
	_check(
		str(fx.expected_family_version) == str(Family.FAMILY_VERSION),
		"production fixture declares the expected family VERSION"
	)
	_check(
		(fx as Object).has_method("verify_against_rig"),
		"production fixture honours the rig binding the assembler calls"
	)
	var conf: Dictionary = fx.confidence_for_side("right")
	_check(float(conf.get("overall", 0.0)) >= 0.35, "right compiled confidence recorded")
	# The composition root must not preload the authored oracle at all.
	var cf := FileAccess.open(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd",
		FileAccess.READ
	)
	_check(cf != null, "composition readable")
	if cf != null:
		var src: String = cf.get_as_text()
		var code := ""
		for line in src.split("\n"):
			var s := str(line).strip_edges()
			if not s.begins_with("#"):
				code += s + "\n"
		_check(
			not code.contains("uthana_warrior_hand_fixture"),
			"production composition no longer loads the hand-authored fixture"
		)
	# The LEFT side has no certified compiled fixture: requiring it must fail
	# closed by the compiler's own classification, not be papered over.
	var left_req: Dictionary = Composition.compiled_fixture(["left"])
	_check(
		not bool(left_req.get("ok", false)),
		"requiring the uncertified left compiled fixture fails closed"
	)
	_check(
		str(left_req.get("error_class", "")) == "PAD_PATCH_AMBIGUOUS",
		"left compiled fixture is classified PAD_PATCH_AMBIGUOUS (%s)"
			% str(left_req.get("error_class", ""))
	)
	# A left assemble through the compiled artifact must therefore be
	# classified, never a silent success.
	var lasm: Node = Composition.make_assembler(["right"])
	host.add_child(lasm)
	var lroot := Node3D.new()
	host.add_child(lroot)
	var luthana: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	lroot.add_child(luthana)
	await process_frame
	var lres: Dictionary = lasm.assemble(luthana, "left")
	_check(not bool(lres.get("ok", true)), "left assemble through the artifact is not a pass")
	print("A2_10_LEFT_THROUGH_ARTIFACT %s" % str(lres.get("error_class", lres.get("error", ""))))


func _test_family_and_fixture(right_ctx: Dictionary, left_ctx: Dictionary) -> void:
	var rs: Dictionary = Fixture.right_surface()
	_check(bool(rs.get("compiled", false)), "right fixture compiled")
	_check((rs["nail_tris"] as Array).size() == 4, "right nail patch count")
	# Bone names are injected family data; the reference fixture has none.
	var ls: Dictionary = Fixture.compile_left_from_mesh(
		left_ctx["character"], left_ctx["skeleton"], Family.bone_map("left")
	)
	_check(bool(ls.get("compiled", false)), "left reference fixture compiled from mesh")
	_check(
		str(Fixture.compile_left_from_mesh(left_ctx["character"], left_ctx["skeleton"], {})
			.get("error_class", "")) != "LEFT_THUMB_BONES_MISSING",
		"reference fixture never guesses a bone name"
	)
	_check((ls["nail_tris"] as Array).size() == 8, "left nail patch counted independently")
	_check(
		not _same_tri_ids(rs["nail_tris"], ls["nail_tris"]),
		"left nail IDs are not a copy of the right"
	)
	var rp: Dictionary = HandProfile.compile(
		right_ctx["skeleton"], right_ctx["character"], "right", Fixture, Family, Skinning
	)
	var lp: Dictionary = HandProfile.compile(
		left_ctx["skeleton"], left_ctx["character"], "left", Fixture, Family, Skinning
	)
	var no_fix: Dictionary = HandProfile.compile(
		right_ctx["skeleton"], right_ctx["character"], "right", null, Family, Skinning
	)
	_check(not bool(no_fix.get("ok", true)), "live compile without fixture fail-closed")
	_check(
		(no_fix.get("failures", []) as Array).has("HAND_PROFILE_FIXTURE_REQUIRED"),
		"live missing fixture classified"
	)
	_check(bool(rp.get("ok", false)), "right profile compile")
	_check(bool(lp.get("ok", false)), "left profile compile")
	_check(float(rp.get("confidence", 0.0)) >= 1.0, "right confidence")
	_check(float(lp.get("confidence", 0.0)) >= 1.0, "left confidence")


func _test_right_parity(ctx: Dictionary) -> void:
	var r: Dictionary = ctx["result"]
	_check(bool(r.get("ok", false)), "right assemble ok (%s)" % r.get("error_class", ""))
	var inv: Dictionary = r.get("invariants", {})
	_check(bool(inv.get("pass", false)), "right invariants pass")
	# A2.10: record the achieved values reached through the COMPILED fixture,
	# so the accepted A2.7 grip is quoted as measured rather than asserted.
	var grip = ctx["assembler"].grip_modifier()
	if grip != null:
		var s: Dictionary = grip.last_surface()
		print(
			(
				"A2_10_ACHIEVED dot_da=%.6f volar_offset_radii=%.6f nail_out_geom=%.6f "
				+ "nail_axis_geom=%.6f pad_in_geom=%.6f closest=%s distal_roll=%.4f "
				+ "rest_nail_pad_dot=%.5f nail_tris=%d pad_tris=%d"
			) % [
				absf(float(inv.get("dot_da", 0.0))),
				float(inv.get("volar_offset_radii", 0.0)),
				float(s.get("nail_out_geom", -9.0)),
				float(s.get("nail_axis_geom", 9.0)),
				float(s.get("pad_in_geom", -9.0)),
				str(s.get("closest_patch", "?")),
				float(s.get("distal_phys_roll_deg", 999.0)),
				float(s.get("rest_nail_pad_dot", 9.0)),
				int((s.get("nail", {}) as Dictionary).get("tris", 0)),
				int((s.get("pad", {}) as Dictionary).get("tris", 0)),
			]
		)
	_check(absf(float(inv.get("dot_da", 0.0)) - 0.9781) <= 0.005, "right dot(D,A) pinned")
	_check(absf(float(inv.get("volar_offset_radii", 0.0)) - 1.20) <= 0.05, "right volar 1.2r")
	_check(str(r.get("side", "")) == "right", "right owner side")
	_check(
		(r.get("application_order", []) as Array).size() >= 7,
		"right application order recorded"
	)


func _test_left_semantics(ctx: Dictionary) -> void:
	var asm: Node = ctx["assembler"]
	var sk: Skeleton3D = ctx["skeleton"]
	var profile = asm.hand_profile()
	_check(profile != null, "left profile injected")
	if profile == null:
		return
	var frame: Dictionary = profile.compute_frame(sk, false)
	_check(bool(frame.get("ok", false)), "left frame ok")
	_check(float(frame.get("det", 0.0)) > 0.99, "left anatomical triad det +1")
	var volar: Dictionary = profile.verify_volar(sk, ctx["character"], frame)
	_check(bool(volar.get("ok", false)), "left volar dual-check")
	var radial: Vector3 = frame["radial"]
	var across: Vector3 = frame["across"]
	_check(radial.dot(across) < -0.5, "left radial is not the basis-X ulnar axis")
	var mcp: Dictionary = frame["mcp"]
	var idx_minus_pinky: Vector3 = (
		(mcp["index"] as Vector3) - (mcp["pinky"] as Vector3)
	).normalized()
	_check(radial.dot(idx_minus_pinky) > 0.7, "left radial = thumb/index side")
	var inv: Dictionary = ctx["result"].get("invariants", {})
	_check(bool(inv.get("pass", false)), "left socket invariants pass")
	_check(float(inv.get("dot_da", 0.0)) > 0.90, "left shaft transverse/radial")
	var grip_info: Dictionary = ctx["result"].get("grip", {})
	_check(
		(grip_info.get("thumb_wrap_failures", []) as Array).is_empty(),
		"left wrap semantic gates empty (%s)" % str(grip_info.get("thumb_wrap_failures", []))
	)
	# A2.13b: the INDEPENDENT anatomical validator now refuses this side, and it
	# refuses it EARLIER than the T2 contour gate that A2.8 recorded here. The
	# authored left reference surface places the nail plate on the dorsal-ULNAR
	# flank, opposite the dorsal-radial bisector this hand's own frame derives,
	# so it is not a thumbnail at all — the A2.8 left oracle was self-consistent
	# and anatomically wrong, which is exactly the class of surface this slice
	# exists to catch. The left side remains unsolved by design.
	var tw: Dictionary = grip_info.get("thumb_wrap", {})
	var anat: Dictionary = grip_info.get("surface_anatomy", {})
	_check(
		str(ctx["result"].get("error_class", "")) == "GRIP_SURFACE_ANATOMY_REJECTED",
		"left assemble fail-closes on independent surface anatomy (%s)"
			% str(ctx["result"].get("error_class", ""))
	)
	_check(
		str(ctx["result"].get("reason", "")) == "thumb_surface_anatomy_rejected",
		"...for the named bind reason (%s)" % str(ctx["result"].get("reason", ""))
	)
	var lclasses: Array = anat.get("failure_classes", [])
	print("A2_13B_LEFT_ANATOMY %s" % str(lclasses))
	for cls in ["NAIL_PATCH_NOT_DORSAL_RADIAL", "PAD_PATCH_NOT_VOLAR", "NAIL_PAD_SAME_SIDE"]:
		_check(
			lclasses.has(cls),
			"the left refusal names %s (%s)" % [cls, str(lclasses)]
		)
	# The verdict is derived from THIS hand's own frame, not from anything the
	# authored fixture declares about its own normals.
	_check(
		float((anat.get("metrics", {}) as Dictionary).get(
			"nail_position_dorsal_radial", 9.0
		)) < 0.0,
		"the left authored nail plate measures on the wrong flank of the digit"
	)
	# The wrap gates never ran, because the bind refused first. Asserting that
	# keeps this from silently becoming a "some gate said no" test.
	_check(
		tw.is_empty(),
		"the achieved-pose wrap gates were never reached on the refused left side"
	)


func _test_assembly_order(ctx: Dictionary) -> void:
	var order: Array = ctx["result"].get("application_order", [])
	_check(order.size() >= 6, "order present")
	if order.size() >= 6:
		_check(str(order[0]) == "body_animation_sampled", "order starts after animation")
		_check(str(order[2]) == "owner_hand_primary_grip", "owner attaches once")
		_check(str(order[3]) == "secondary_ik_skipped", "no two-hand IK in this slice")
		_check(str(order[4]) == "finger_interaction", "fingers after attach")
	var club: Node3D = ctx["assembler"].club_instance()
	_check(club != null, "one club instance")
	if club != null:
		var owners := 0
		var n: Node = club
		while n != null:
			if str(n.name).begins_with("WeaponSocket_"):
				owners += 1
			n = n.get_parent()
		_check(owners == 1, "weapon has exactly one transform owner")


func _test_negatives(right_ctx: Dictionary, left_ctx: Dictionary) -> void:
	var lsk: Skeleton3D = left_ctx["skeleton"]
	var rsk: Skeleton3D = right_ctx["skeleton"]
	var lp = left_ctx["assembler"].hand_profile()
	var rp = right_ctx["assembler"].hand_profile()
	_check(lp != null and rp != null, "both profiles for negatives")
	if lp == null or rp == null:
		return
	var lframe: Dictionary = lp.compute_frame(lsk, false)
	# Negative-determinant mirrored frame (radial, L, volar) on the left.
	var mirrored := Basis(lframe["radial"], lframe["longitudinal"], lframe["volar"])
	_check(mirrored.determinant() < 0.0, "raw left (radial,L,V) is det −1")
	_check(float(lframe.get("det", 0.0)) > 0.99, "compiled left frame refuses det −1")
	# Left radial/ulnar reversed would align radial with across (ulnar).
	_check(
		(lframe["radial"] as Vector3).dot(lframe["across"] as Vector3) < 0.0,
		"left radial is not reversed onto ulnar/across"
	)
	# Copied right-hand local quats onto the left thumb.
	var saved: Array = []
	for i in 3:
		var lb: int = lsk.find_bone(str(lp.bones["thumb"][i]))
		var rb: int = rsk.find_bone(str(rp.bones["thumb"][i]))
		saved.append([lb, lsk.get_bone_pose_rotation(lb)])
		lsk.set_bone_pose_rotation(lb, rsk.get_bone_pose_rotation(rb))
	lsk.force_update_all_bone_transforms()
	var g = left_ctx["assembler"].grip_modifier()
	if g != null:
		var copied: Dictionary = g.measure_thumb_now()
		var gate: Dictionary = g.evaluate_thumb_wrap(
			copied, float(left_ctx["result"].get("shape", {}).get("radius_mean", 0.01))
		)
		_check(
			not bool(gate.get("pass", true)),
			"copied right quats on left rejected (%s)" % str(gate.get("failures", []))
		)
		var toward_pinky := str(copied.get("direction_class", "")) == "TOWARD_PINKY"
		var same_wind := not bool(copied.get("opposite_winding", true))
		_check(
			toward_pinky or same_wind or not gate.get("failures", []).is_empty(),
			"copied-right pose is semantically invalid on the left"
		)
	for pair in saved:
		lsk.set_bone_pose_rotation(int(pair[0]), pair[1])
	lsk.force_update_all_bone_transforms()
	# Stale pre-animation measurement: a measurement stamp that does not
	# match the live pose must fail closed.
	if g != null:
		var surf: Dictionary = g.measure_thumb_surface_truth()
		var stale: Dictionary = g.evaluate_thumb_surface_truth(surf, "stale-pre-animation")
		_check(
			(stale.get("failures", []) as Array).has("thumb_measurement_pose_stale"),
			"stale pre-animation measurement rejected"
		)
	# Weapon with two transform owners.
	var extra := Node3D.new()
	extra.name = "WeaponSocket_X"
	var club: Node3D = left_ctx["assembler"].club_instance()
	if club != null and club.get_parent() != null:
		var parent: Node = club.get_parent()
		parent.add_child(extra)
		extra.add_child(club.duplicate())
		var owners := 0
		var n: Node = club
		while n != null:
			if str(n.name).begins_with("WeaponSocket_"):
				owners += 1
			n = n.get_parent()
		_check(owners == 1, "original club still has one owner")
		extra.queue_free()
	# Secondary policy fails closed.
	var blocked_asm: Node = Assembler.new()
	left_ctx["character"].get_parent().get_parent().add_child(blocked_asm)
	var blocked: Dictionary = blocked_asm.assemble(
		left_ctx["character"], "left", "power_grip_2h_support_v1"
	)
	_check(
		str(blocked.get("error_class", "")) == "SECONDARY_IK_NOT_IMPLEMENTED",
		"secondary IK reserved fail-closed"
	)


func _test_policy_reserved() -> void:
	for pid in Policy.RESERVED:
		_check(not Policy.is_implemented(pid), "reserved %s not implemented" % pid)
	for pid in ["shield_grip_v1", "bow_hold_v1", "bow_draw_hook_v1", "sling_grip_v1",
			"firearm_trigger_v1", "firearm_support_v1", "power_grip_2h_support_v1"]:
		_check(Policy.RESERVED.has(pid), "%s declared reserved" % pid)
		_check(Policy.resolve(pid) == null, "reserved %s resolves to no policy" % pid)


## A2.9b: the socket mapping and the hard preconditions are owned by the
## POLICY, not by the registry, the assembler or the solver. Adding a future
## policy must not require editing the central dispatch.
func _test_policy_ownership() -> void:
	_check(Policy.resolve(Policy.POLICY_POWER_GRIP_1H) == PowerGrip1hPolicy,
		"registry resolves power_grip_1h_v1 to its own policy script")
	_check(PowerGrip1hPolicy.POLICY_ID == "power_grip_1h_v1", "policy declares its own id")
	_check(not PowerGrip1hPolicy.REQUIRES_SECONDARY, "policy declares its secondary need")
	# Behavioural proof that the policy itself answers the invariant call.
	var bad: Dictionary = PowerGrip1hPolicy.evaluate_grip_invariants(
		{}, Transform3D.IDENTITY, 0.01
	)
	_check(
		not bool(bad.get("pass", true))
		and (bad.get("failures", []) as Array).has("hand_frame_invalid"),
		"policy owns the invariant evaluation and fails closed on a bad frame"
	)
	# The registry file must not carry any grip mechanism of its own.
	var f := FileAccess.open(
		"res://presentation/equipment/grip_interaction_profile.gd", FileAccess.READ
	)
	_check(f != null, "readable registry file")
	if f != null:
		var src: String = f.get_as_text()
		for token in ["KAPPA_DEG :=", "VOLAR_OFFSET_RADII :=", "DISTAL_SHIFT_HAND :=",
				"DOT_DA_MIN", "STATION_REACH_MIN", "func build_grip_socket_world",
				"func evaluate_grip_invariants"]:
			_check(
				not src.contains(str(token)),
				"registry owns no grip mechanism ('%s')" % token
			)
	# An injected policy the registry has never heard of resolves without
	# editing the registry; an unknown id still fails closed.
	_check(
		Policy.resolve("future_profile_v9", {"future_profile_v9": PowerGrip1hPolicy})
			== PowerGrip1hPolicy,
		"an INJECTED policy id resolves without editing the registry"
	)
	_check(Policy.resolve("future_profile_v9") == null, "unknown id fails closed by default")
	_check(
		Policy.requires_secondary("power_grip_2h_support_v1"),
		"reserved two-hand support still declared as needing a second owner"
	)


## A2.9: an UNCONFIGURED generic assembler must fail closed with named
## error classes for every missing injected dependency — no silent Uthana,
## Mixamo, club or engine defaults inside the core.
func _test_injection_negatives() -> void:
	var bare: Node = Assembler.new()
	root.add_child(bare)
	var no_family: Dictionary = bare.assemble(null, "right")
	_check(
		str(no_family.get("error_class", "")) == "FAMILY_REQUIRED",
		"unconfigured assembler fails FAMILY_REQUIRED (%s)" % str(no_family.get("error_class", ""))
	)
	bare.configure_dependencies({"family": Family})
	_check(
		str(bare.assemble(null, "right").get("error_class", "")) == "FIXTURE_REQUIRED",
		"missing fixture fails FIXTURE_REQUIRED"
	)
	bare.configure_dependencies({"family": Family, "fixture": Fixture})
	_check(
		str(bare.assemble(null, "right").get("error_class", "")) == "ENGINE_REQUIRED",
		"missing engine fails ENGINE_REQUIRED"
	)
	bare.configure_dependencies({
		"family": Family,
		"fixture": Fixture,
		"engines": {"power_grip_1h_v1": Engine1h},
	})
	_check(
		str(bare.assemble(null, "right").get("error_class", "")) == "WEAPON_SOURCE_REQUIRED",
		"missing weapon source fails WEAPON_SOURCE_REQUIRED"
	)
	# The generic engine itself refuses to run without an injected profile.
	var engine: SkeletonModifier3D = Engine1h.new()
	var cfg: Dictionary = engine.configure(null, null, {}, {})
	_check(
		str(cfg.get("error_class", "")) == "ENGINE_PROFILE_REQUIRED",
		"bare generic engine fails ENGINE_PROFILE_REQUIRED (%s)" % str(cfg.get("error_class", ""))
	)
	engine.free()
	# The solver refuses a null engine.
	var no_engine: Dictionary = Solver.attach(null, null, null, {}, {}, null, null)
	_check(
		str(no_engine.get("reason", "")) == "not_ready" or str(no_engine.get("error_class", "")) == "ENGINE_REQUIRED",
		"solver fails closed without inputs"
	)
	bare.queue_free()


## A2.9 synthetic injection stub: a minimal alternative family/fixture with
## distinct identities drives a FULL right assemble through the generic
## core. Architecture-only proof of true dependency injection — NOT visual
## multi-unit validation.
func _test_injection_stub(host: Node) -> void:
	var root3 := Node3D.new()
	root3.name = "Host_stub"
	host.add_child(root3)
	var model := Node3D.new()
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	root3.add_child(model)
	var uthana: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(uthana)
	await process_frame
	var sk: Skeleton3D = Skinning.find_skeleton(uthana)
	var lib: AnimationLibrary = Native.ensure_walking_library()
	var player := AnimationPlayer.new()
	uthana.add_child(player)
	var clip: String = Playback.attach_looping_clip(
		player, lib.get_animation(Native.WALKING_CLIP), Native.WALKING_CLIP
	)
	player.play(clip)
	player.seek(0.35, true)
	await process_frame
	sk.force_update_all_bone_transforms()
	var asm: Node = Assembler.new()
	asm.configure_dependencies({
		"family": StubFamily,
		"fixture": StubFixture,
		"reference_fixture_mode": true,
		"skinning": Skinning,
		"weapon_path": str(Composition.CLUB_GLB_PATH),
		"weapon_node_name": "StubWeapon",
		"engines": {"power_grip_1h_v1": Engine1h},
	})
	root3.add_child(asm)
	var result: Dictionary = asm.assemble(uthana, "right")
	_check(bool(result.get("ok", false)), "stub-injected assemble ok (%s)" % str(result.get("error_class", "")))
	var profile = asm.hand_profile()
	_check(profile != null and str(profile.family_id) == "stub_family_v0", "core consumed the INJECTED family identity")
	_check(profile != null and str(profile.asset_id) == "stub_asset_v0", "core consumed the INJECTED fixture identity")
	_check(
		profile != null and str(profile.fixture_schema) == "stub_fixture_v0",
		"core consumed the INJECTED fixture schema"
	)
	_check(
		asm.club_instance() != null and str(asm.club_instance().name) == "StubWeapon",
		"core consumed the INJECTED weapon node name"
	)


## A2.9b: inject a synthetic UNIT (own fixture data, own identity, own
## procedurally built weapon) into the unmodified generic core. The core
## must consume the injected data, must never fall back to the Uthana
## fixture or the demo club, and must reject the fabricated surface
## evidence with a CLASSIFIED error instead of a silent pass.
func _test_synthetic_unit_injection(host: Node) -> void:
	var root3 := Node3D.new()
	root3.name = "Host_synthetic"
	host.add_child(root3)
	var model := Node3D.new()
	model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	root3.add_child(model)
	var character: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	model.add_child(character)
	await process_frame
	var sk: Skeleton3D = Skinning.find_skeleton(character)
	sk.force_update_all_bone_transforms()
	# Synthetic weapon: built here, not loaded from the demo club asset.
	var weapon_root := Node3D.new()
	weapon_root.name = "SyntheticWeaponRoot"
	var weapon_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 0.5
	weapon_mesh.mesh = cyl
	weapon_root.add_child(weapon_mesh)
	weapon_mesh.owner = weapon_root
	var packed := PackedScene.new()
	_check(packed.pack(weapon_root) == OK, "synthetic weapon packed")
	var asm: Node = Assembler.new()
	asm.configure_dependencies({
		"family": StubFamily,
		"fixture": SyntheticFixture,
		"reference_fixture_mode": true,
		"skinning": Skinning,
		"weapon_scene": packed,
		"weapon_node_name": "SyntheticWeapon",
		"engines": {"power_grip_1h_v1": Engine1h},
	})
	root3.add_child(asm)
	var result: Dictionary = asm.assemble(character, "right")
	var err := str(result.get("error_class", ""))
	# Whatever happens, it must be a classified outcome — never a crash and
	# never a silent success on fabricated plate evidence.
	_check(
		bool(result.get("ok", false)) or not err.is_empty(),
		"synthetic unit produced a classified outcome (%s)" % err
	)
	_check(
		not bool(result.get("ok", false)),
		"fabricated surface evidence is NOT accepted as a valid grip (%s)" % err
	)
	var allowed := [
		"THUMB_SURFACE_TRUTH_GATE_FAILED",
		"THUMB_CONTOUR_GATE_FAILED",
		"THUMB_OPPOSITION_GATE_FAILED",
		"GRIP_GEOMETRY_FAILED",
		"GRIP_FRAME_PRECONDITION_FAILED",
		"HAND_PROFILE_FAILED",
	]
	_check(err in allowed, "synthetic failure is a known classified gate (%s)" % err)
	# No Uthana identity may appear anywhere in the synthetic run.
	var profile = asm.hand_profile()
	if profile != null:
		_check(
			str(profile.asset_id) == "synthetic_unit_v0",
			"core used the SYNTHETIC fixture identity (%s)" % str(profile.asset_id)
		)
		_check(
			str(profile.fixture_schema) == "synthetic_fixture_v0",
			"core used the SYNTHETIC fixture schema"
		)
		_check(
			str(profile.asset_id) != Fixture.ASSET_ID,
			"core did NOT fall back to the Uthana fixture"
		)
	var club: Node3D = asm.club_instance()
	if club != null:
		_check(str(club.name) == "SyntheticWeapon", "core used the INJECTED synthetic weapon")
		_check(
			not str(result.get("club_path", "")).contains("wooden_club"),
			"core did NOT fall back to the demo club"
		)
	weapon_root.queue_free()
	# Second variant: synthetic fixture with a weapon that DOES pass grip
	# geometry, so the run reaches the finger/surface gates. Fabricated
	# plate evidence must be rejected THERE, not silently accepted.
	var asm2: Node = Assembler.new()
	asm2.configure_dependencies({
		"family": StubFamily,
		"fixture": SyntheticFixture,
		"reference_fixture_mode": true,
		"skinning": Skinning,
		"weapon_path": str(Composition.CLUB_GLB_PATH),
		"weapon_node_name": "SyntheticFixtureWeapon",
		"engines": {"power_grip_1h_v1": Engine1h},
	})
	root3.add_child(asm2)
	var result2: Dictionary = asm2.assemble(character, "right")
	var err2 := str(result2.get("error_class", ""))
	_check(
		not bool(result2.get("ok", false)),
		"synthetic fixture with a valid weapon still fails closed (%s)" % err2
	)
	# Fabricated triangle IDs are not skin-bound to the thumb tip, so the
	# engine's patch-bind sanity rejects them before any pose is applied.
	_check(
		err2 in [
			"GRIP_PATCH_BIND_FAILED",
			"THUMB_SURFACE_TRUTH_GATE_FAILED",
			"THUMB_CONTOUR_GATE_FAILED",
			"THUMB_OPPOSITION_GATE_FAILED",
		],
		"fabricated plate evidence is rejected by a bind/surface gate (%s)" % err2
	)


func _same_tri_ids(a: Array, b: Array) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return str((a[0] as Dictionary).get("i", [])) == str((b[0] as Dictionary).get("i", []))


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)
