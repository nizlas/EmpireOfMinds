# Canonical automatic hand-fixture ingestion step (A2.11), reduced to a CLI
# adapter in A2.13a. Runs as a Godot headless step - no editor, no F6, no
# manual file nomination, no Blender:
#
#   godot --headless --path game \
#       -s res://presentation/equipment/tools/certify_hand_fixture_headless.gd \
#       -- --glb=res://... --out=res://... --policy=power_grip_1h_v1 \
#          --weapon=res://... [--sides=right,left] [--family=...]
#
# WHAT THIS FILE OWNS, AND WHAT IT NO LONGER OWNS. Until A2.13a this file ran
# the acceptance chain and then told `Certification.certify()` that the chain
# had completed and passed. Certification therefore recorded a caller's claim,
# and any caller could make the same claim without running anything.
#
# The chain now belongs to `hand_fixture_certification_authority.gd`, which is
# also the only thing that can mint a certificate. This file is an ADAPTER:
# argument parsing, path defaults, writing and re-reading the certificate, the
# machine-readable report and the exit protocol. It cannot assert a step, a
# gate result or a verdict, because the authority's API has no parameter for
# any of them.
#
# The chain the authority runs, in order, all of it automatic:
#   1. import the rigged asset
#   2. resolve the skeleton family (alias-aware; the family owns its aliases)
#   3. humanoid normalization: resolve the family's SEMANTIC height landmarks
#      and measure the humanoid in the declared canonical space
#   4. compile the fixture -> STAGING EVIDENCE
#   5. artifact integrity: write, re-read and re-verify the content hash
#   6. rig binding: bind the evidence to the imported RIG (geometry AND
#      deformation identity derived from the asset itself, never from the
#      artifact's own payload)
#   7. assemble and measure, through the REAL production assembler and grip
#      engine: live-rig binding, profile, socket, grip invariants and the
#      achieved-geometry surface gate — one step, because it is one measurement
#   8. CERTIFICATION: mint the certified runtime fixture, only now, from what
#      the authority itself observed
#
# This adapter then: writes the certificate, re-reads it, and reports.
#
# A compiler PASS is NOT an accepted asset and is NOT a runtime fixture: the
# compiler writes staging evidence, and only a fully passed chain mints a
# certificate (A2.12). Steps 5-7 can still reject an asset the compiler liked.
#
# EXIT PROTOCOL
#   0  the whole chain was accepted
#   2  expected, classified asset/fixture FAIL (named domain error class)
#   1  infrastructure / process / protocol / tooling error
extends SceneTree

const Certification = preload("res://presentation/equipment/hand_fixture_certification.gd")
const Authority = preload(
	"res://presentation/equipment/hand_fixture_certification_authority.gd"
)

const EXIT_ACCEPTED := 0
const EXIT_STEP_FAILED := 1
const EXIT_CLASSIFIED := 2

## Error classes that mean the TOOL or its invocation is wrong, not the asset.
## Everything else is a classified asset/fixture rejection (exit 2).
const INFRA_ERROR_CLASSES: Array[String] = [
	"INGEST_ARGS_MISSING",
	"INGEST_ASSET_MISSING",
	"INGEST_ASSET_NOT_A_SCENE",
	"INGEST_FAMILY_UNKNOWN",
	"INGEST_POLICY_UNKNOWN",
	"INGEST_ARTIFACT_INTEGRITY_FAILED",
	"INGEST_CERTIFICATION_INTEGRITY_FAILED",
	"FIXTURE_ARTIFACT_WRITE_FAILED",
	"WEAPON_SOURCE_REQUIRED",
	"CLUB_MISSING",
	"CLUB_LOAD_FAILED",
	"INSTANTIATE_FAILED",
	"GRIP_GEOMETRY_FAILED",
	"ENGINE_REQUIRED",
	"POLICY_NOT_IMPLEMENTED",
	"SECONDARY_IK_NOT_IMPLEMENTED",
]

var _report := {}
## The link of the chain currently being attempted, so every rejection names
## where it happened even when the failure is not the assembler's.
var _stage := "invocation"


func _init() -> void:
	_run()


func _run() -> void:
	var args: Dictionary = _parse_args()
	var glb: String = str(args.get("glb", ""))
	var out_path: String = str(args.get("out", ""))
	var policy_id: String = str(args.get("policy", ""))
	var weapon: String = str(args.get("weapon", ""))
	# Where the CERTIFIED runtime fixture goes if — and only if — the whole
	# chain passes. Defaults beside the evidence so a caller that forgets it
	# still gets a distinguishable file rather than overwriting the evidence.
	var certified_path: String = str(args.get("certified-out", ""))
	if certified_path.is_empty() and not out_path.is_empty():
		certified_path = "%s_certified.tres" % out_path.trim_suffix(".tres")
	_report = {
		"chain": [],
		"asset": glb,
		"artifact_path": out_path,
		"certified_artifact_path": certified_path,
		"policy": policy_id,
		"accepted": false,
		"certified": false,
	}
	if glb.is_empty() or out_path.is_empty() or policy_id.is_empty() or weapon.is_empty():
		_finish("INGEST_ARGS_MISSING", "--glb, --out, --policy and --weapon are required")
		return
	# `--sides` are compiled and reported; `--required` are the hands this
	# asset must certify to be ACCEPTED. A hand the compiler classifies is
	# always reported, but it only rejects the asset when it was required.
	var sides: Array = _split(str(args.get("sides", "right")))
	if sides.is_empty():
		_finish("INGEST_ARGS_MISSING", "--sides resolved to nothing")
		return
	var required: Array = _split(str(args.get("required", str(sides[0]))))
	if required.is_empty():
		_finish("INGEST_ARGS_MISSING", "--required resolved to nothing")
		return
	for r in required:
		if not r in sides:
			_finish("INGEST_ARGS_MISSING", "required side '%s' is not compiled" % r)
			return
	_report["required_sides"] = required

	# The whole chain, owned by the certification authority. This adapter hands
	# over inputs only: an asset path, a staging path, the hands, the policy id
	# and the weapon. There is no argument through which it could claim a step
	# ran or a gate passed.
	_stage = "acceptance_chain"
	var authority := Authority.new()
	var outcome: Dictionary = await authority.run({
		"host": root,
		"tree": self,
		"glb": glb,
		"staging_path": out_path,
		"sides": sides,
		"required_sides": required,
		"policy_id": policy_id,
		"weapon_path": weapon,
		"family_id": str(args.get("family", "")),
		"asset_id": str(args.get("asset_id", glb.get_file())),
	})
	_absorb(outcome)
	if not bool(outcome.get("ok", false)):
		_report["stage_failed"] = str(
			outcome.get("stage_failed", outcome.get("stage", _stage))
		)
		_finish(
			str(outcome.get("error_class", "FIXTURE_NOT_CERTIFIED")),
			str(outcome.get("detail", ""))
		)
		return

	# Transport. A certificate that cannot be written, or cannot be read back,
	# is an infrastructure failure and must never be published.
	_stage = "certification"
	var cert: Dictionary = outcome["certification"]
	cert["source_asset"] = glb
	var wrote: Dictionary = Certification.save(cert, certified_path)
	if not bool(wrote.get("ok", false)):
		_finish(str(wrote.get("error_class", "FIXTURE_ARTIFACT_WRITE_FAILED")), str(wrote))
		return
	var recheck: Dictionary = Certification.load_certified(certified_path)
	if not bool(recheck.get("ok", false)):
		_finish(
			"INGEST_CERTIFICATION_INTEGRITY_FAILED",
			"certificate did not survive its own round trip: %s"
				% str(recheck.get("error_class", ""))
		)
		return
	_report["certification_hash"] = str(cert.get("certification_hash", ""))
	_report["certification_schema"] = str(cert.get("schema", ""))
	_report["acceptance_schema"] = str(cert.get("acceptance_schema", ""))
	_report["acceptance_version"] = str(cert.get("acceptance_version", ""))
	_report["acceptance_authority_id"] = str(cert.get("acceptance_authority_id", ""))
	_report["acceptance_report_digest"] = str(cert.get("acceptance_report_digest", ""))
	_report["policy_version"] = str(cert.get("policy_version", ""))
	_report["policy_calibration_id"] = str(cert.get("policy_calibration_id", ""))
	_report["policy_calibration_version"] = str(cert.get("policy_calibration_version", ""))
	_report["certified"] = true
	_report["accepted"] = true
	_emit()
	quit(EXIT_ACCEPTED)


## Copy the authority's observations into the machine-readable report. The
## report is OUTPUT: nothing read here feeds back into a gate or a verdict.
func _absorb(outcome: Dictionary) -> void:
	_report["chain"] = (outcome.get("chain", []) as Array).duplicate()
	_report["gate_calls"] = outcome.get("gate_calls", {})
	var d: Dictionary = outcome.get("diagnostics", {})
	for key in [
		"family_diagnosis", "import_representation", "bone_map_resolution",
		"humanoid_height", "sides", "compiler_pass", "certified_side", "assembler",
		"assembler_detail", "grip_ground_truth", "gate_metrics", "failed_gate",
	]:
		if d.has(key):
			_report[key] = d[key]
	var steps: Dictionary = outcome.get("steps", {})
	var imported: Dictionary = (steps.get("import", {}) as Dictionary).get("observed", {})
	if imported.has("skeleton_bone_count"):
		_report["skeleton_bone_count"] = imported["skeleton_bone_count"]
	var fam: Dictionary = (steps.get("family_resolution", {}) as Dictionary).get("observed", {})
	if fam.has("family_id"):
		_report["family_id"] = str(fam["family_id"])
		_report["family_version"] = str(fam["family_version"])
	var compiler: Dictionary = d.get("compiler", {})
	for key in compiler.keys():
		_report[str(key)] = compiler[key]
	var binding: Dictionary = (steps.get("rig_binding", {}) as Dictionary).get("observed", {})
	if binding.has("geometry_sha256"):
		_report["expected_source_geometry_sha256"] = str(binding["geometry_sha256"])
		_report["expected_source_rig_sha256"] = str(binding["rig_sha256"])


func _split(csv: String) -> Array:
	var out: Array = []
	for s in csv.split(","):
		var t := str(s).strip_edges()
		if not t.is_empty() and not t in out:
			out.append(t)
	return out


## Single exit point for every rejection: emit the machine-readable report and
## map the error class onto the exit protocol. An asset/fixture rejection is
## EXPECTED output (exit 2) and must never be reported as a tool failure.
func _finish(error_class: String, detail: String) -> void:
	_report["accepted"] = false
	if str(_report.get("stage_failed", "")).is_empty():
		_report["stage_failed"] = _stage
	_report["error_class"] = error_class
	_report["detail"] = detail
	var infra: bool = error_class in INFRA_ERROR_CLASSES
	_report["failure_kind"] = "infrastructure" if infra else "classified_asset_failure"
	_emit()
	quit(EXIT_STEP_FAILED if infra else EXIT_CLASSIFIED)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if not s.begins_with("--"):
			continue
		var body := s.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _emit() -> void:
	print("HAND_FIXTURE_INGEST %s" % JSON.stringify(_jsonable(_report)))


func _jsonable(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in (v as Dictionary).keys():
				o[str(k)] = _jsonable((v as Dictionary)[k])
			return o
		TYPE_ARRAY:
			var a := []
			for it in (v as Array):
				a.append(_jsonable(it))
			return a
		TYPE_VECTOR3, TYPE_VECTOR2:
			return str(v)
		_:
			return v
