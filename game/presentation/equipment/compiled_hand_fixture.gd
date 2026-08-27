# Runtime fixture backed by a CERTIFIED artifact (A2.10 compile, A2.12 trust).
#
# Presents the same duck-typed fixture surface the generic hand profile
# already consumes (`SCHEMA_VERSION`, `ASSET_ID`, `surface_for_side`,
# `thumb_anat_for_side`, `finger_flex`), but every triangle id, rest normal,
# winding flip and pad marker comes from `hand_fixture_compiler.gd` instead
# of a hand-authored script.
#
# Pose CALIBRATION (thumb anatomical angles, authored finger flexion) is NOT
# surface evidence and is not derivable from geometry: it is injected as
# interaction-policy data and is shared per grip profile, not authored per
# unit. Missing calibration fails closed rather than defaulting.
#
# A2.12 — WHAT MAY BECOME A RUNTIME FIXTURE:
#   * only a CERTIFIED envelope (`hand_fixture_certification.gd`), never the
#     compiler's own staging evidence — a compiler PASS is not a licence;
#   * only against an expected source identity supplied INDEPENDENTLY by the
#     caller (from the real asset), never read back out of the artifact;
#   * only with an expected family id AND family version, both non-empty;
#   * and only after `verify_against_rig` re-derives the identity from the LIVE
#     mesh + skeleton the assembler is about to pose.
extends RefCounted

const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")

## The explicit fixture verification contract (A2.12). Every fixture used in a
## production assembly must declare one of these; the assembler dispatches on
## the declared contract instead of probing for a method, so a fixture can no
## longer opt out of verification simply by not implementing it.
const CONTRACT_CERTIFIED_RUNTIME := "certified_runtime_v1"
const CONTRACT_TEST_ONLY_REFERENCE := "test_only_reference_v1"

var SCHEMA_VERSION: String = Compiler.ARTIFACT_SCHEMA
var ASSET_ID: String = ""
var artifact: Dictionary = {}
var certification: Dictionary = {}
var calibration: Dictionary = {}
var load_failures: Array[String] = []
## Source identity this fixture is bound to, from the real rigged resource.
var expected_geometry_sha256: String = ""
var expected_rig_sha256: String = ""
## The family this fixture was certified for, supplied by the caller.
var expected_family_id: String = ""
var expected_family_version: String = ""


## The declared verification contract. Not optional, and not inferred: the
## assembler reads this and refuses anything it does not recognise.
func fixture_verification_contract() -> String:
	return CONTRACT_CERTIFIED_RUNTIME


## Build a runtime fixture from a CERTIFIED envelope.
##
## `expected` must carry, all independently derived by the caller:
##   `geometry_sha256`, `rig_sha256`, `family_id`, `family_version`.
## Every one of them is mandatory; an empty value is a rejection rather than a
## skipped check, because "no expectation" used to mean "no verification".
## `options` may carry `allow_provisional`, which the certification authority
## sets while bootstrapping bind sanity (A2.13a): the assembler accepts only a
## certified fixture, so the acceptance chain needs a fixture before a
## certificate exists. Nothing else may set it — the default refuses a
## bind-sanity bootstrap envelope, and such an envelope can never be a file
## because `Certification.save` refuses to write one.
static func from_certified_artifact(
	certification_in: Dictionary,
	calibration_in: Dictionary,
	asset_id: String,
	expected: Dictionary,
	required_sides: Array = [],
	options: Dictionary = {}
) -> Dictionary:
	var f := new()
	f.ASSET_ID = asset_id
	f.calibration = calibration_in.duplicate(true)
	# 1. is this a certificate at all, and is it intact?
	var verified: Dictionary = Certification.verify(
		certification_in, bool(options.get("allow_provisional", false))
	)
	if not bool(verified.get("ok", false)):
		return f._reject(
			str(verified.get("error_class", "FIXTURE_NOT_CERTIFIED")),
			str(verified.get("detail", ""))
		)
	var cert: Dictionary = verified["certification"]
	var evidence: Dictionary = verified["evidence"]
	f.certification = cert.duplicate(true)
	f.artifact = evidence.duplicate(true)
	var schema := str(evidence.get("schema", ""))
	if not schema in Compiler.SUPPORTED_SCHEMAS:
		return f._reject("FIXTURE_SCHEMA_UNSUPPORTED", "evidence schema '%s'" % schema)
	f.SCHEMA_VERSION = schema
	if str(evidence.get("compiler_version", "")) != Compiler.COMPILER_VERSION:
		return f._reject(
			"FIXTURE_SCHEMA_UNSUPPORTED",
			"evidence was produced by '%s'" % evidence.get("compiler_version", "")
		)
	# 2. the caller's independent expectations, all mandatory.
	var want_geo := str(expected.get("geometry_sha256", "")).strip_edges()
	var want_rig := str(expected.get("rig_sha256", "")).strip_edges()
	var want_family := str(expected.get("family_id", "")).strip_edges()
	var want_family_version := str(expected.get("family_version", "")).strip_edges()
	if want_rig.is_empty() or want_geo.is_empty():
		return f._reject(
			"FIXTURE_MESH_IDENTITY_REQUIRED",
			"a certified fixture may only be bound to a named source geometry AND rig"
		)
	if want_family.is_empty():
		return f._reject(
			"FIXTURE_FAMILY_MISMATCH", "the caller must state the expected family id"
		)
	if want_family_version.is_empty():
		return f._reject(
			"FIXTURE_FAMILY_VERSION_MISMATCH",
			"the caller must state the expected family version"
		)
	if str(cert.get("family_id", "")) != want_family:
		return f._reject(
			"FIXTURE_FAMILY_MISMATCH", "certified for family '%s'" % cert.get("family_id", "")
		)
	if str(cert.get("family_version", "")) != want_family_version:
		return f._reject(
			"FIXTURE_FAMILY_VERSION_MISMATCH",
			"certified for family version '%s', expected '%s'"
				% [cert.get("family_version", ""), want_family_version]
		)
	if str(cert.get("source_geometry_sha256", "")) != want_geo:
		return f._reject(
			"FIXTURE_GEOMETRY_HASH_MISMATCH", "certified against another geometry"
		)
	if str(cert.get("source_rig_sha256", "")) != want_rig:
		return f._reject("FIXTURE_RIG_HASH_MISMATCH", "certified against another rig")
	# 3. the required hands must actually carry evidence and must be the hands
	#    the certificate was issued for.
	if (evidence.get("sides", {}) as Dictionary).is_empty():
		return f._reject(
			str(evidence.get("error_class", "THUMB_SURFACE_CANDIDATES_MISSING")),
			"evidence carries no compiled side"
		)
	for side_v in required_sides:
		var d: Dictionary = f.side_data(str(side_v))
		if d.is_empty():
			return f._reject(
				"FIXTURE_NOT_CERTIFIED", "side '%s' was never compiled" % side_v
			)
		if not bool(d.get("compiled", false)):
			return f._reject(
				str(d.get("error_class", "THUMB_SURFACE_CANDIDATES_MISSING")),
				"side '%s' was not compiled: %s" % [side_v, d.get("detail", "")]
			)
		if not (cert.get("required_sides", []) as Array).has(str(side_v)):
			return f._reject(
				"FIXTURE_NOT_CERTIFIED",
				"side '%s' is not among the certified sides" % side_v
			)
	if not calibration_in.has("thumb_anat") or not calibration_in.has("finger_flex"):
		return f._reject("FIXTURE_SCHEMA_UNSUPPORTED", "calibration requires thumb_anat + finger_flex")
	# 4. the POSE CALIBRATION the acceptance was measured under (A2.13a).
	#    A certificate records which policy and which calibration observed the
	#    achieved geometry. Injecting a different calibration is a different
	#    pose, so it may not reuse this certificate — otherwise a retuned angle
	#    set inherits an acceptance that was never measured for it.
	if str(calibration_in.get("policy_id", "")) != str(cert.get("policy_id", "")):
		return f._reject(
			"FIXTURE_POLICY_MISMATCH",
			"certified under policy '%s', assembling with '%s'"
				% [cert.get("policy_id", ""), calibration_in.get("policy_id", "")]
		)
	if str(calibration_in.get("calibration_id", "")) != str(
		cert.get("policy_calibration_id", "")
	):
		return f._reject(
			"FIXTURE_CALIBRATION_MISMATCH",
			"certified under calibration '%s', assembling with '%s'"
				% [cert.get("policy_calibration_id", ""), calibration_in.get("calibration_id", "")]
		)
	if str(calibration_in.get("calibration_version", "")) != str(
		cert.get("policy_calibration_version", "")
	):
		return f._reject(
			"FIXTURE_CALIBRATION_VERSION_MISMATCH",
			"certified under calibration version '%s', assembling with '%s'"
				% [
					cert.get("policy_calibration_version", ""),
					calibration_in.get("calibration_version", ""),
				]
		)
	f.expected_geometry_sha256 = want_geo
	f.expected_rig_sha256 = want_rig
	f.expected_family_id = want_family
	f.expected_family_version = want_family_version
	return {"ok": true, "fixture": f}


func _reject(error_class: String, detail: String) -> Dictionary:
	load_failures.append(error_class)
	return {"ok": false, "error_class": error_class, "detail": detail, "fixture": self}


## Verify the certificate still describes the RIGGED MESH that is actually
## POSED. Called by the assembler on the live skinned mesh and skeleton before
## the fixture may drive any pose or socket.
##
## Three independent sources must agree — the caller's expectation, the
## certificate, and the live geometry re-derived here — so neither the artifact
## nor the caller alone can authorise the binding. The rig hash covers bind
## poses, bone rests and hierarchy, so a re-import that preserves the vertex
## streams but moves the rig no longer passes.
func verify_against_rig(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	if mesh_instance == null or mesh_instance.mesh == null:
		return {"ok": false, "error_class": "FIXTURE_LIVE_MESH_MISSING"}
	if skeleton == null:
		return {"ok": false, "error_class": "FIXTURE_LIVE_RIG_MISSING"}
	if expected_rig_sha256.is_empty() or expected_geometry_sha256.is_empty():
		return {"ok": false, "error_class": "FIXTURE_MESH_IDENTITY_REQUIRED"}
	var live_geo: String = Compiler.geometry_identity(mesh_instance)
	if live_geo != expected_geometry_sha256:
		return {
			"ok": false,
			"error_class": "FIXTURE_GEOMETRY_HASH_MISMATCH",
			"live": live_geo,
			"expected": expected_geometry_sha256,
		}
	if live_geo != str(certification.get("source_geometry_sha256", "")):
		return {"ok": false, "error_class": "FIXTURE_GEOMETRY_HASH_MISMATCH", "live": live_geo}
	var live_rig: String = Compiler.rig_identity(mesh_instance, skeleton)
	if live_rig != expected_rig_sha256:
		return {
			"ok": false,
			"error_class": "FIXTURE_RIG_HASH_MISMATCH",
			"live": live_rig,
			"expected": expected_rig_sha256,
		}
	if live_rig != str(certification.get("source_rig_sha256", "")):
		return {"ok": false, "error_class": "FIXTURE_RIG_HASH_MISMATCH", "live": live_rig}
	return {
		"ok": true,
		"verified": true,
		"geometry_sha256": live_geo,
		"rig_sha256": live_rig,
		"certification_hash": str(certification.get("certification_hash", "")),
	}


## The family id/version this fixture was certified for, so the assembler can
## cross-check the family it was actually injected with.
func certified_family() -> Dictionary:
	return {
		"family_id": str(certification.get("family_id", "")),
		"family_version": str(certification.get("family_version", "")),
	}


func certified_policy() -> Dictionary:
	return {
		"policy_id": str(certification.get("policy_id", "")),
		"policy_version": str(certification.get("policy_version", "")),
	}


func side_data(side: String) -> Dictionary:
	var sides: Dictionary = artifact.get("sides", {})
	var key: String = "left" if side == "left" else "right"
	return sides.get(key, {})


func surface_for_side(
	side: String, _character: Node, _skeleton: Skeleton3D, _bone_map: Dictionary = {}
) -> Dictionary:
	var d: Dictionary = side_data(side)
	if d.is_empty():
		return {"compiled": false, "error_class": "THUMB_SURFACE_CANDIDATES_MISSING"}
	if not bool(d.get("compiled", false)):
		return {
			"compiled": false,
			"error_class": str(d.get("error_class", "THUMB_SURFACE_CANDIDATES_MISSING")),
		}
	return {
		"compiled": true,
		"source": str(d.get("source", "compiled")),
		"nail_tris": d["nail_tris"],
		"pad_tris": d["pad_tris"],
		"nail_normal_local": d["nail_normal_local"],
		"pad_normal_local": d["pad_normal_local"],
		"rest_nail_pad_dot": d["rest_nail_pad_dot"],
		"pad_marker_local": d["pad_marker_local"],
		"confidence": d.get("confidence", {}),
		"evidence": d.get("evidence", {}),
	}


func thumb_anat_for_side(side: String) -> Dictionary:
	var anat: Dictionary = calibration.get("thumb_anat", {})
	var key: String = "left" if side == "left" else "right"
	return (anat.get(key, {}) as Dictionary).duplicate()


func finger_flex() -> Dictionary:
	return (calibration.get("finger_flex", {}) as Dictionary).duplicate(true)


func confidence_for_side(side: String) -> Dictionary:
	return (side_data(side).get("confidence", {}) as Dictionary).duplicate(true)


func evidence_for_side(side: String) -> Dictionary:
	return (side_data(side).get("evidence", {}) as Dictionary).duplicate(true)
