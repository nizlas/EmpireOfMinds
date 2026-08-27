# The acceptance chain, owned by the certification side of the boundary
# (A2.13a).
#
# WHY THIS FILE EXISTS. A2.12 put the envelope in
# `hand_fixture_certification.gd` but left the CHAIN in the headless CLI, and
# `certify()` accepted the completed chain and the verdict as parameters. The
# certifier therefore recorded a caller's claim. Any caller that could compile
# evidence could also mint a certificate for it by passing
# `chain = REQUIRED_CHAIN` and `{"pass": true}`, and the result was
# indistinguishable from acceptance: it verified, loaded through the production
# loader, assembled as `certified_bound` and survived save / load. Zero gates
# had run.
#
# The chain now lives here, and this is the only public certification entry
# point. It takes REAL INPUTS ONLY -- a path to a rigged asset, a staging path,
# the hands to compile, a policy id, a weapon -- and no assertion whatsoever
# about what ran or passed. It resolves the family and the policy from its own
# registries, compiles the evidence, re-reads it from disk, derives both source
# identities from the asset itself, drives the REAL production assembler and
# reads the achieved-geometry result out of the real grip engine. Only the
# observations it made itself are handed to `Certification`, which derives the
# verdict from them.
#
# WHAT A CALLER CANNOT DO THROUGH THIS API: assert a completed chain, assert a
# gate PASS, supply an acceptance report, name an identity that is not derived
# from the asset, or skip a step. There is no parameter for any of it.
#
# WHAT THIS IS NOT. Acceptance here is a historical fact about one run. It is
# never a substitute for live safety: `compiled_hand_fixture.verify_against_rig`
# and the assembler's own gates re-run on the actual rig every single time a
# fixture is used, and the certificate cannot switch them off.
extends RefCounted

const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const DefaultSkinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Assembler = preload("res://presentation/equipment/equipment_assembler.gd")
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")

## Registry of skeleton families the authority may resolve against. Identifying
## the family is part of the chain; it is never a human choice at runtime, and
## an unknown id fails closed rather than guessing.
const FAMILIES := {
	"mixamo_52_humanoid": "res://presentation/equipment/mixamo_52_hand_family.gd",
}

## Grip policies this authority can certify against: the engine that owns the
## interaction plus the calibration that owns its canonical pose data. The
## policy id/version and calibration id/version recorded in a certificate are
## read from these scripts, never from the caller.
const POLICY_ENGINES := {
	"power_grip_1h_v1": {
		"engine": "res://presentation/equipment/power_grip_1h_engine.gd",
		"calibration": "res://presentation/equipment/power_grip_1h_calibration.gd",
		"policy": "res://presentation/equipment/power_grip_1h_policy.gd",
	},
}

## Operations whose invocation is counted, so a regression can assert that the
## chain really ran rather than that a name appeared in an array.
const COUNTED_GATES: Array[String] = [
	"import",
	"family_match",
	"height_measure",
	"compile",
	"artifact_reload",
	"rig_identity_of_asset",
	"assemble",
	"surface_read",
	"mint",
]

## Everything the authority observed, per chain step, in the order it ran.
var _steps: Dictionary = {}
var _chain: Array[String] = []
## Instrumentation: how many times each real operation was actually invoked.
var _gate_calls: Dictionary = {}
## Diagnostics for the CLI's machine-readable report. Never an input to minting.
var _diagnostics: Dictionary = {}
var _stage: String = "invocation"


func _init() -> void:
	for g in COUNTED_GATES:
		_gate_calls[g] = 0


## Run the whole acceptance chain and, only if it passed, mint a certificate.
##
## `context` carries INPUTS, never claims:
##   `host`            Node the imported asset and assembler are parented to.
##   `glb`             the rigged asset to certify (required).
##   `staging_path`    where compiled evidence is written and re-read (required).
##   `sides`           hands to compile, default `["right"]`.
##   `required_sides`  hands that must certify, default the first compiled side.
##   `policy_id`       a key of `POLICY_ENGINES` (required).
##   `weapon_path`     the weapon the assembler grips (required).
##   `family_id`       optional; must exist in `FAMILIES` when given.
##   `asset_id`        optional label for the runtime fixture.
##   `keep_nodes`      keep the imported asset and assembler alive for the
##                     caller to inspect. Diagnostics only; changes no gate.
##
## Returns `{ok, stage, chain, steps, gate_calls, diagnostics, ...}` plus, on
## success, `certification`, `evidence` and `resolved`. On failure it returns
## the classified `error_class` of whatever actually refused, and no envelope
## of any kind was created.
func run(context: Dictionary) -> Dictionary:
	var host: Node = context.get("host", null)
	if host == null:
		return _fail("INGEST_ARGS_MISSING", "certification requires a host node")
	# The scene tree to yield on. A headless `-s` script is still inside its own
	# `_init` when it starts the chain, and `Engine.get_main_loop()` is not yet
	# registered at that point, so the caller passes its tree explicitly.
	var tree: SceneTree = context.get("tree", null)
	if tree == null:
		tree = host.get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("INGEST_ARGS_MISSING", "certification requires a scene tree to run in")
	var glb: String = str(context.get("glb", ""))
	var staging_path: String = str(context.get("staging_path", ""))
	var policy_id: String = str(context.get("policy_id", ""))
	var weapon_path: String = str(context.get("weapon_path", ""))
	if glb.is_empty() or staging_path.is_empty() or policy_id.is_empty() or weapon_path.is_empty():
		return _fail(
			"INGEST_ARGS_MISSING",
			"certification requires glb, staging_path, policy_id and weapon_path"
		)
	if not POLICY_ENGINES.has(policy_id):
		return _fail("INGEST_POLICY_UNKNOWN", "policy '%s' is not certifiable here" % policy_id)
	var sides: Array = _string_list(context.get("sides", ["right"]))
	if sides.is_empty():
		return _fail("INGEST_ARGS_MISSING", "no side to compile")
	var required: Array = _string_list(context.get("required_sides", [sides[0]]))
	if required.is_empty():
		return _fail("INGEST_ARGS_MISSING", "no required side")
	for r in required:
		if not r in sides:
			return _fail("INGEST_ARGS_MISSING", "required side '%s' is not compiled" % r)
	var skinning = context.get("skinning", DefaultSkinning)
	var keep_nodes: bool = bool(context.get("keep_nodes", false))

	# ---- 1. import the rigged asset. The authority instantiates it itself, so
	#         the geometry every later step measures is the asset on disk and
	#         not a node a caller had a chance to doctor.
	_stage = "import"
	if not ResourceLoader.exists(glb):
		return _fail("INGEST_ASSET_MISSING", glb)
	var packed: PackedScene = load(glb) as PackedScene
	if packed == null:
		return _fail("INGEST_ASSET_NOT_A_SCENE", glb)
	_count("import")
	var character: Node = packed.instantiate()
	host.add_child(character)
	await tree.process_frame
	var skeleton: Skeleton3D = skinning.find_skeleton(character)
	if skeleton == null:
		return _fail_with(character, keep_nodes, "HAND_SKELETON_INCOMPLETE", "asset carries no Skeleton3D")
	skeleton.force_update_all_bone_transforms()
	_observed("import", {
		"asset": glb,
		"skeleton_bone_count": skeleton.get_bone_count(),
		"skeleton_node": str(skeleton.name),
	})

	# ---- 2. family resolution, through the family's OWN alias resolution.
	_stage = "family_resolution"
	var ident: Dictionary = _resolve_family(skeleton, str(context.get("family_id", "")))
	_diagnostics["family_diagnosis"] = ident.get("diagnosis", {})
	if not bool(ident.get("ok", false)):
		return _fail_with(
			character, keep_nodes, str(ident["error_class"]), str(ident.get("detail", ""))
		)
	var family = ident["family"]
	var family_id: String = str(ident["family_id"])
	var family_version: String = str(family.FAMILY_VERSION)
	_diagnostics["import_representation"] = str(ident.get("import_representation", "unknown"))
	_diagnostics["bone_map_resolution"] = ident.get("bone_map_resolution", {})
	_observed("family_resolution", {
		"family_id": family_id,
		"family_version": family_version,
		"import_representation": str(ident.get("import_representation", "unknown")),
		"resolved_hand_bone": str(
			((ident.get("bone_map_resolution", {}) as Dictionary).get(str(required[0]), {})
				as Dictionary).get("hand", "")
		),
	})

	# ---- 3. humanoid normalization: the family's SEMANTIC height landmarks,
	#         measured in the declared canonical space.
	_stage = "humanoid_normalization"
	var landmarks: Dictionary = HandProfile.family_height_landmarks(family, skeleton)
	_count("height_measure")
	var height: Dictionary = skinning.measure_humanoid_height_from_landmarks(skeleton, landmarks)
	var height_body := {
		"ok": bool(height.get("ok", false)),
		"height": float(height.get("height", 0.0)),
		"space": str(height.get("space", "")),
		"head_bone": str(height.get("head_bone", "")),
		"floor_bones": height.get("floor_bones", []),
		"unresolved_roles": landmarks.get("unresolved", []),
	}
	_diagnostics["humanoid_height"] = height_body
	if not bool(height.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(height.get("error_class", "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED")),
			str(height.get("detail", ""))
		)
	_observed("humanoid_normalization", height_body)

	# ---- 4. compile the fixture -> STAGING EVIDENCE.
	_stage = "fixture_compilation"
	_count("compile")
	var artifact: Dictionary = Compiler.compile(character, skeleton, family, sides, skinning)
	# Provenance only, excluded from the content identity by declaration.
	artifact["source_asset"] = glb
	var saved: Dictionary = Compiler.save_artifact(artifact, staging_path)
	if not bool(saved.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(saved.get("error_class", "FIXTURE_ARTIFACT_WRITE_FAILED")),
			str(saved)
		)
	_diagnostics["compiler"] = {
		"content_hash": str(artifact.get("content_hash", "")),
		"source_geometry_sha256": str(artifact.get("source_geometry_sha256", "")),
		"source_rig_sha256": str(artifact.get("source_rig_sha256", "")),
		"compiler_version": str(artifact.get("compiler_version", "")),
		"schema": str(artifact.get("schema", "")),
		"calibration_id": str(artifact.get("calibration_id", "")),
		"calibration_version": str(artifact.get("calibration_version", "")),
		"family_bone_map_digest": str(artifact.get("family_bone_map_digest", "")),
	}
	_diagnostics["sides"] = _side_report(artifact)
	_diagnostics["compiler_pass"] = _required_sides_compiled(artifact, required)
	if not bool(_diagnostics["compiler_pass"]):
		var first: Dictionary = _first_side_error(artifact, required)
		return _fail_with(
			character, keep_nodes, str(first["error_class"]), str(first["detail"])
		)
	_observed("fixture_compilation", {
		"content_hash": str(artifact.get("content_hash", "")),
		"compiler_version": str(artifact.get("compiler_version", "")),
		"evidence_schema": str(artifact.get("schema", "")),
		"compiled_sides": _compiled_sides(artifact),
		"staging_path": staging_path,
	})

	# ---- 5. artifact integrity, from disk.
	_stage = "artifact_integrity"
	_count("artifact_reload")
	var reloaded: Dictionary = Compiler.load_artifact(staging_path)
	if not bool(reloaded.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			"INGEST_ARTIFACT_INTEGRITY_FAILED",
			"artifact did not survive its own round trip: %s"
				% str(reloaded.get("error_class", ""))
		)
	var evidence: Dictionary = reloaded["artifact"]
	_observed("artifact_integrity", {
		"path": staging_path,
		"reloaded_content_hash": str(evidence.get("content_hash", "")),
		"round_trip": "save_then_load",
	})

	# ---- 6. binding to the imported RIG. Both identities are derived from the
	#         asset on disk, never read out of the artifact being checked.
	_stage = "rig_binding"
	_count("rig_identity_of_asset")
	var expected: Dictionary = Compiler.rig_identity_of_asset(glb, skinning)
	if not bool(expected.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(expected.get("error_class", "FIXTURE_SOURCE_MESH_MISSING")),
			glb
		)
	var geometry_sha: String = str(expected["geometry_sha256"])
	var rig_sha: String = str(expected["rig_sha256"])
	if str(evidence.get("source_geometry_sha256", "")) != geometry_sha:
		return _fail_with(
			character,
			keep_nodes,
			"FIXTURE_GEOMETRY_HASH_MISMATCH",
			"evidence geometry identity does not match the asset on disk"
		)
	if str(evidence.get("source_rig_sha256", "")) != rig_sha:
		return _fail_with(
			character,
			keep_nodes,
			"FIXTURE_RIG_HASH_MISMATCH",
			"evidence rig identity does not match the asset on disk"
		)
	_observed("rig_binding", {
		"geometry_sha256": geometry_sha,
		"rig_sha256": rig_sha,
		"rig_identity_schema": str(evidence.get("rig_identity_schema", "")),
		"derived_from": "asset_on_disk",
	})

	# ---- 7. assemble and measure: ONE step, because it is one measurement.
	#         The production assembler binds the fixture to the live rig, builds
	#         the profile and socket and runs the grip engine, whose surface
	#         gates ARE the achieved-geometry ground truth. A2.12 recorded this
	#         as two chain links (`bind_sanity` + `grip_ground_truth`) although
	#         the second only re-read `closest_patch` out of the first's result.
	#
	#         The assembler accepts nothing but a CERTIFIED fixture, so the
	#         chain needs a fixture before it has a certificate: it mints a
	#         BIND-SANITY BOOTSTRAP envelope, which carries a different
	#         acceptance schema, is refused by the ordinary loader, and cannot
	#         be written to disk.
	_stage = "assemble_and_measure"
	var policy_cfg: Dictionary = POLICY_ENGINES[policy_id]
	var calibration = load(str(policy_cfg["calibration"]))
	var policy_script = load(str(policy_cfg["policy"]))
	var resolved := {
		"geometry_sha256": geometry_sha,
		"rig_sha256": rig_sha,
		"family_id": family_id,
		"family_version": family_version,
		"policy_id": policy_id,
		"policy_version": str(policy_script.POLICY_VERSION),
		"policy_calibration_id": str(calibration.CALIBRATION_ID),
		"policy_calibration_version": str(calibration.CALIBRATION_VERSION),
		"certified_side": str(required[0]),
		"required_sides": required.duplicate(),
	}
	var bootstrap: Dictionary = Certification.mint_provisional(
		evidence, resolved, _steps.duplicate(true)
	)
	if not bool(bootstrap.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(bootstrap.get("error_class", "FIXTURE_NOT_CERTIFIED")),
			str(bootstrap.get("detail", ""))
		)
	var fx: Dictionary = CompiledFixture.from_certified_artifact(
		bootstrap["certification"],
		calibration.payload(),
		str(context.get("asset_id", glb.get_file())),
		{
			"geometry_sha256": geometry_sha,
			"rig_sha256": rig_sha,
			"family_id": family_id,
			"family_version": family_version,
		},
		required,
		{"allow_provisional": true}
	)
	if not bool(fx.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(fx.get("error_class", "FIXTURE_RIG_HASH_MISMATCH")),
			str(fx.get("detail", ""))
		)
	var asm: Node = Assembler.new()
	asm.configure_dependencies({
		"family": family,
		"fixture": fx["fixture"],
		"skinning": skinning,
		"weapon_path": weapon_path,
		"weapon_node_name": "CertificationWeapon",
		"engines": {policy_id: load(str(policy_cfg["engine"]))},
	})
	host.add_child(asm)
	var side_to_certify: String = str(required[0])
	_count("assemble")
	var result: Dictionary = asm.assemble(character, side_to_certify, policy_id)
	var binding: Dictionary = asm.mesh_binding()
	_diagnostics["certified_side"] = side_to_certify
	_diagnostics["assembler"] = {
		"ok": bool(result.get("ok", false)),
		"reason": str(result.get("reason", "")),
		"error_class": str(result.get("error_class", "")),
		"mesh_binding": binding,
		"height": asm.height_measurement(),
	}
	if not bool(result.get("ok", false)):
		_diagnostics["assembler_detail"] = _assembler_detail(result)
		_diagnostics["stage_failed"] = _stage_for(result)
		return _fail_with(
			character,
			keep_nodes,
			_assembler_error_class(result),
			str(result.get("reason", "")),
			asm
		)
	# The achieved-geometry reading, straight out of the engine that posed it.
	_count("surface_read")
	var grip = asm.grip_modifier()
	var surface: Dictionary = {}
	if grip != null and grip.has_method("last_surface"):
		surface = (grip as Object).last_surface()
	var closest: String = str(surface.get("closest_patch", ""))
	var measured := {
		"policy_id": policy_id,
		"policy_version": str(policy_script.POLICY_VERSION),
		"side": side_to_certify,
		"profile_key": str(result.get("profile_key", "")),
		"invariants_pass": bool((result.get("invariants", {}) as Dictionary).get("pass", false)),
		"volar_ok": bool((result.get("volar", {}) as Dictionary).get("ok", false)),
		"closest_patch": closest,
		"mesh_binding": str(binding.get("binding", "")),
		"mesh_binding_verified": bool(binding.get("verified", false)),
	}
	_diagnostics["grip_ground_truth"] = {"pass": closest == "pad", "closest_patch": closest}
	# The exact achieved gate numbers, so a run's margins are reportable
	# without a second measurement path. Pure output: no gate reads this.
	_diagnostics["gate_metrics"] = _gate_metrics(asm, result, surface)
	if closest != "pad":
		_diagnostics["stage_failed"] = "assemble_and_measure"
		_diagnostics["failed_gate"] = "grip_ground_truth"
		return _fail_with(
			character,
			keep_nodes,
			"THUMB_SURFACE_TRUTH_GATE_FAILED",
			"closest patch is '%s', not the volar pad" % closest,
			asm
		)
	_observed("assemble_and_measure", measured)

	# ---- 8. CERTIFICATION. Everything below this line is derived from the
	#         observations above; there is no verdict to pass in.
	_stage = "certification"
	_count("mint")
	var minted: Dictionary = Certification.mint_from_observed_chain(
		evidence, resolved, _steps.duplicate(true)
	)
	if not bool(minted.get("ok", false)):
		return _fail_with(
			character,
			keep_nodes,
			str(minted.get("error_class", "FIXTURE_NOT_CERTIFIED")),
			str(minted.get("detail", "")),
			asm
		)
	var out := {
		"ok": true,
		"stage": "certification",
		"chain": _chain.duplicate(),
		"steps": _steps.duplicate(true),
		"gate_calls": _gate_calls.duplicate(),
		"diagnostics": _diagnostics.duplicate(true),
		"certification": minted["certification"],
		"evidence": evidence,
		"resolved": resolved,
		"calibration": calibration.payload(),
		"assembler_result": result,
	}
	if keep_nodes:
		out["character"] = character
		out["skeleton"] = skeleton
		out["assembler"] = asm
		out["family"] = family
	else:
		_release(character, asm)
	return out


func chain() -> Array:
	return _chain.duplicate()


func gate_calls() -> Dictionary:
	return _gate_calls.duplicate()


# ------------------------------------------------------------------ internals


## Record that a step ran AND what it observed. A step exists in the chain only
## once it has an observation body; there is no way to append a bare name.
func _observed(step: String, body: Dictionary) -> void:
	_steps[step] = {"ok": true, "error_class": "", "observed": body}
	if not step in _chain:
		_chain.append(step)


func _count(gate: String) -> void:
	_gate_calls[gate] = int(_gate_calls.get(gate, 0)) + 1


func _fail(error_class: String, detail: String) -> Dictionary:
	return {
		"ok": false,
		"error_class": error_class,
		"detail": detail,
		"stage": _stage,
		"stage_failed": str(_diagnostics.get("stage_failed", _stage)),
		"chain": _chain.duplicate(),
		"steps": _steps.duplicate(true),
		"gate_calls": _gate_calls.duplicate(),
		"diagnostics": _diagnostics.duplicate(true),
	}


func _fail_with(
	character: Node, keep_nodes: bool, error_class: String, detail: String, asm: Node = null
) -> Dictionary:
	var out: Dictionary = _fail(error_class, detail)
	if keep_nodes:
		out["character"] = character
		if asm != null:
			out["assembler"] = asm
	else:
		_release(character, asm)
	return out


func _release(character: Node, asm: Node) -> void:
	if asm != null and is_instance_valid(asm):
		asm.queue_free()
	if character != null and is_instance_valid(character):
		character.queue_free()


## Family resolution. An explicitly requested id must exist in the registry (a
## protocol error when it does not). Otherwise the rig is matched against every
## registered family through the family's OWN alias resolution, so the same
## skeleton is recognised under either import representation.
##
## When nothing matches, the rig is diagnosed rather than lumped into one
## generic mismatch: a rig whose hand resolves but whose digits do not is
## `HAND_SKELETON_INCOMPLETE`, a truthful classified asset failure.
func _resolve_family(skeleton: Skeleton3D, requested: String) -> Dictionary:
	_count("family_match")
	var ids: Array = FAMILIES.keys()
	ids.sort()
	if not requested.is_empty():
		if not FAMILIES.has(requested):
			return {
				"ok": false,
				"error_class": "INGEST_FAMILY_UNKNOWN",
				"detail": "family '%s' is not registered" % requested,
			}
		ids = [requested]
	var matches: Array = []
	var diagnosis := {}
	for fid in ids:
		var fam = load(str(FAMILIES[fid]))
		var m: Dictionary = _family_match(skeleton, fam)
		diagnosis[str(fid)] = m
		if bool(m.get("ok", false)):
			matches.append([str(fid), fam, m])
	if matches.size() > 1:
		return {
			"ok": false,
			"error_class": "FIXTURE_FAMILY_MISMATCH",
			"detail": "rig satisfies more than one registered family",
			"diagnosis": diagnosis,
		}
	if matches.is_empty():
		var incomplete := false
		for fid in diagnosis.keys():
			if bool((diagnosis[fid] as Dictionary).get("hand_present", false)):
				incomplete = true
		if incomplete:
			return {
				"ok": false,
				"error_class": "HAND_SKELETON_INCOMPLETE",
				"detail": "hand bone resolves but the finger chains do not",
				"diagnosis": diagnosis,
			}
		return {
			"ok": false,
			"error_class": "FIXTURE_FAMILY_MISMATCH",
			"detail": "no registered skeleton family matches this rig",
			"diagnosis": diagnosis,
		}
	var picked: Array = matches[0]
	var mm: Dictionary = picked[2]
	return {
		"ok": true,
		"family": picked[1],
		"family_id": str(picked[0]),
		"import_representation": str(mm.get("import_representation", "unknown")),
		"bone_map_resolution": mm.get("resolved", {}),
	}


## Does this rig satisfy the family, after the family has resolved its own
## import-name aliases? Reports WHICH part is missing so the caller can tell a
## foreign rig from an incomplete hand.
func _family_match(skeleton: Skeleton3D, family) -> Dictionary:
	if family == null or not family.has_method("bone_map"):
		return {"ok": false, "reason": "not_a_family"}
	var out := {"ok": true, "hand_present": true, "missing": [], "resolved": {}}
	for side in ["right", "left"]:
		var bm: Dictionary = HandProfile.family_bone_map(family, skeleton, side)
		(out["resolved"] as Dictionary)[side] = {
			"hand": str(bm["hand"]),
			"thumb": (bm["thumb"] as Array).duplicate(),
		}
		if skeleton.find_bone(str(bm["hand"])) < 0:
			out["ok"] = false
			out["hand_present"] = false
			(out["missing"] as Array).append("%s:hand:%s" % [side, bm["hand"]])
			continue
		for digit in ["thumb", "index", "middle", "ring", "pinky"]:
			for bn in (bm[digit] as Array):
				if skeleton.find_bone(str(bn)) < 0:
					out["ok"] = false
					(out["missing"] as Array).append("%s:%s:%s" % [side, digit, bn])
	if family.has_method("import_representation"):
		out["import_representation"] = str(family.import_representation(skeleton, "right"))
	return out


func _string_list(value) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for v in value:
		var t := str(v).strip_edges()
		if not t.is_empty() and not t in out:
			out.append(t)
	return out


func _required_sides_compiled(artifact: Dictionary, required: Array) -> bool:
	var sides: Dictionary = artifact.get("sides", {})
	for side in required:
		if not bool((sides.get(str(side), {}) as Dictionary).get("compiled", false)):
			return false
	return true


func _compiled_sides(artifact: Dictionary) -> Array:
	var out: Array = []
	for side in (artifact.get("sides", {}) as Dictionary).keys():
		if bool((artifact["sides"] as Dictionary)[side].get("compiled", false)):
			out.append(str(side))
	out.sort()
	return out


func _side_report(artifact: Dictionary) -> Dictionary:
	var out := {}
	for side in (artifact.get("sides", {}) as Dictionary).keys():
		var d: Dictionary = (artifact["sides"] as Dictionary)[side]
		out[str(side)] = {
			"compiled": bool(d.get("compiled", false)),
			"error_class": str(d.get("error_class", "")),
			"detail": str(d.get("detail", "")),
			"confidence": d.get("confidence", {}),
			"nail_tris": (d.get("nail_tris", []) as Array).size(),
			"pad_tris": (d.get("pad_tris", []) as Array).size(),
		}
	return out


func _first_side_error(artifact: Dictionary, sides: Array) -> Dictionary:
	var fallback: String = str(artifact.get("error_class", "THUMB_SURFACE_CANDIDATES_MISSING"))
	for side in sides:
		var d: Dictionary = (artifact.get("sides", {}) as Dictionary).get(str(side), {})
		if not bool(d.get("compiled", false)):
			return {
				"error_class": str(d.get("error_class", fallback)),
				"detail": str(d.get("detail", artifact.get("detail", ""))),
			}
	return {"error_class": fallback, "detail": str(artifact.get("detail", ""))}


## The assembler reports its own class per stage; the grip result nests the
## engine's class, which is the one that names the surface gate that refused.
func _assembler_error_class(result: Dictionary) -> String:
	var grip: Dictionary = result.get("grip", {})
	var nested: String = str(grip.get("error_class", ""))
	if not nested.is_empty():
		return nested
	var ec: String = str(result.get("error_class", ""))
	if ec == "HAND_PROFILE_FAILED":
		var failures: Array = result.get("failures", [])
		if not failures.is_empty():
			return str(failures[0])
	return ec if not ec.is_empty() else "GRIP_ASSEMBLY_FAILED"


## Which link of the chain the assembler's own rejection belongs to. Reported
## verbatim so a rejection never claims a stage it did not reach. Everything the
## assembler itself refuses happens inside `assemble_and_measure`, except the
## two identity/normalization facts it re-checks on the live rig.
func _stage_for(result: Dictionary) -> String:
	match str(result.get("reason", "")):
		"fixture_mesh_binding_failed":
			return "rig_binding"
		"humanoid_height_landmarks_unresolved", "degenerate_height":
			return "humanoid_normalization"
	return "assemble_and_measure"


## Every number a gate margin is computed from, with its own limit beside it,
## read from the engine that produced them. Report-only (A2.13b §8): the slice
## must be able to state exact margins for any delivery without re-deriving
## them, and a margin that is nearly zero has to be visible rather than implied
## by a PASS.
func _gate_metrics(asm, result: Dictionary, surface: Dictionary) -> Dictionary:
	var grip = asm.grip_modifier() if asm != null else null
	var diag: Dictionary = {}
	if grip != null and grip.has_method("last_diagnostics"):
		diag = (grip as Object).last_diagnostics()
	var wrap: Dictionary = diag.get("thumb_wrap", {})
	var thumb: Dictionary = diag.get("thumb", {})
	var out := {
		"limits": {},
		"achieved": {},
		"joint_pose": {},
		"surface": {},
	}
	if grip != null:
		var engine_script: Script = (grip as Object).get_script() as Script
		if engine_script != null:
			var consts: Dictionary = engine_script.get_script_constant_map()
			for k in [
				"THUMB_APPROACH_AXIAL_FRAC_MAX", "THUMB_APPROACH_RADIAL_MAX_RADII",
				"THUMB_WINDING_MIN_DEG", "THUMB_AXIAL_DOT_MAX",
				"THUMB_GAP_MAX_RADII", "THUMB_PEN_MAX_RADII",
			]:
				if consts.has(k):
					out["limits"][k] = consts[k]
	for k in [
		"approach_axial_fraction", "approach_radial_radii",
		"approach_tangential_winding_radii", "transverse_over_axial",
		"winding_thumb_deg", "opposition_dot", "nail_out_dot", "nail_axis_dot",
		"pad_in_dot", "nail_pad_dot", "rest_nail_pad_dot", "distal_roll_deg",
		"gap_final_signed", "chain_min_gap_radii", "volar_clearance_hand",
	]:
		if wrap.has(k):
			out["achieved"][k] = wrap[k]
	for k in [
		"cmc_flex_deg", "cmc_abd_deg", "cmc_twist_deg",
		"mcp_flex_deg", "ip_flex_deg",
	]:
		if wrap.has(k):
			out["joint_pose"][k] = wrap[k]
		elif thumb.has(k):
			out["joint_pose"][k] = thumb[k]
	for k in [
		"nail_pad_geom_dot", "rest_nail_pad_dot", "nail_out_geom",
		"nail_axis_geom", "pad_in_geom", "closest_patch",
		"expected_nail_tris", "expected_pad_tris", "distal_phys_roll_deg",
	]:
		if surface.has(k):
			out["surface"][k] = surface[k]
	out["socket"] = {
		"radius_mean": (result.get("invariants", {}) as Dictionary).get("radius_mean", null),
		"hand_length": (result.get("invariants", {}) as Dictionary).get("hand_length", null),
		"volar_offset_radii": (
			(result.get("invariants", {}) as Dictionary).get("volar_offset_radii", null)
		),
	}
	return out


func _assembler_detail(result: Dictionary) -> Dictionary:
	var grip: Dictionary = result.get("grip", {})
	return {
		"failures": result.get("failures", []),
		"grip_reason": str(grip.get("reason", "")),
		"thumb_surface_failures": grip.get("thumb_surface_failures", []),
		"thumb_wrap_failures": grip.get("thumb_wrap_failures", []),
		"thumb_contour_failures": grip.get("thumb_contour_failures", []),
		"invariants": result.get("invariants", {}),
		"mesh_binding": result.get("mesh_binding", {}),
	}
