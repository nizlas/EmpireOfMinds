# The trust boundary between compiled evidence and a runtime fixture
# (A2.12, authority corrected in A2.13a).
#
# WHY THIS IS NOT PART OF THE COMPILER. The compiler must not be able to mint a
# licence for its own output. Before A2.12 acceptance was a property of WHERE a
# file sat: a classified-rejected asset's staged artifact loaded successfully,
# passed live-mesh binding against its own mesh and was indistinguishable from
# an accepted one, because nothing inside it recorded the chain verdict and the
# runtime loader accepted the compiler's own schema.
#
# WHY A2.12's OWN BOUNDARY WAS STILL INVERTED. A2.12 moved certification out of
# the compiler but let the CALLER supply the completed chain and the acceptance
# verdict. `certify(evidence, {"chain": REQUIRED_CHAIN, "acceptance_report":
# {"pass": true}})` therefore minted a certificate that verified, loaded through
# the real runtime loader, assembled as `certified_bound` and survived a save /
# load round trip -- without a single gate having run. The envelope proved
# INTEGRITY (nothing drifted after minting); it never proved EXECUTION.
#
# A2.13a removes the inversion. There is no public entry point that accepts a
# completed chain, a gate PASS, an acceptance verdict or a free-form acceptance
# report. The acceptance chain is run by
# `hand_fixture_certification_authority.gd`, which owns the real dependencies
# and reports only what it observed; this module turns those observations into a
# report and an envelope, and refuses anything that is not a complete, mutually
# consistent set of step evidence bound to the evidence being certified.
#
# THREE STATES, ONE DIRECTION:
#
#   1. compiled evidence   -- `hand_fixture_compiler.gd` output, schema
#      `hand_fixture_evidence_v4`, written to STAGING. Never runtime-valid.
#   2. rejected diagnostic -- the same evidence for an asset the chain refused.
#      Kept for traceability; can never be promoted, because no envelope exists.
#   3. certified runtime fixture -- this envelope, schema
#      `hand_fixture_certification_v1`, produced only when the authority's own
#      chain returned PASS, and the ONLY thing the runtime loader accepts.
#
# WHAT THE ENVELOPE BINDS. A lone `accepted = true` would be worthless, so the
# envelope names every identity the acceptance was true FOR, and its own hash
# covers all of it. Editing the verdict, the chain, the policy, the family
# version or the bound identities invalidates the certificate:
#
#   * fixture content hash of the exact evidence payload (embedded verbatim)
#   * source geometry identity and source RIG/deformation identity
#   * family id + family version + resolved bone-map digest
#   * compiler version, evidence schema, compiler-calibration id + version
#   * grip policy id + policy version and its calibration id + version
#   * acceptance schema + version, the completed chain, the certified side
#   * a digest of the canonical acceptance report (the gate results themselves)
#
# WHAT CERTIFICATE VERIFICATION PROVES, AND WHAT IT DOES NOT. See `verify`.
# It is deliberately NOT a substitute for runtime re-verification: both are
# required, and the runtime gates remain the live safety property.
extends RefCounted

const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const CertifiedResource = preload(
	"res://presentation/equipment/certified_hand_fixture_artifact.gd"
)

const CERTIFICATION_SCHEMA := "hand_fixture_certification_v1"
const SUPPORTED_CERTIFICATION_SCHEMAS: Array[String] = [CERTIFICATION_SCHEMA]

## Bumped by A2.13a: the report gained a per-step evidence body, the verdict is
## now DERIVED from those bodies rather than declared, and the chain merged two
## steps that were only ever one measurement. An A2.12 certificate is therefore
## refused rather than silently reinterpreted.
const ACCEPTANCE_SCHEMA := "hand_fixture_acceptance_v2"
const ACCEPTANCE_VERSION := "2"

## The bind-sanity bootstrap envelope (A2.13a). The assembler only accepts a
## CERTIFIED fixture, so the acceptance chain needs a fixture before it has a
## certificate. A2.12 solved that by minting a normal certificate that claimed
## the WHOLE chain and marked itself `provisional: true` -- a field no consumer
## read, which made it a fully privileged certificate in every way that
## mattered. It now carries a DIFFERENT acceptance schema, so:
##   * `verify` refuses it unless the caller explicitly asks for it,
##   * `save` refuses to write it at all,
##   * a runtime loader that does not opt in cannot consume it.
const ACCEPTANCE_SCHEMA_PROVISIONAL := "hand_fixture_acceptance_provisional_v2"

## Who is allowed to have produced an acceptance report. Recorded inside the
## report and re-checked by `verify`, so a report that does not name the
## canonical authority is not an acceptance report.
const AUTHORITY_ID := "hand_fixture_certification_authority"
const AUTHORITY_VERSION := "1"

## Every link that must have been RUN, with its own observed result, before a
## certificate may exist. `verify` requires the recorded chain to be exactly
## this list, in this order: a missing step, an extra step, a duplicated step or
## a reordered chain is a refusal.
##
## A2.13a merged A2.12's `bind_sanity` and `grip_ground_truth`. They were never
## two independent gates: the full surface-truth gate runs inside
## `assemble()`, and the second "step" only re-read `closest_patch` out of the
## same measurement. Claiming two gates for one measurement is exactly the kind
## of chain inflation this module exists to prevent, so the honest contract is
## one step that assembles and measures.
const REQUIRED_CHAIN: Array[String] = [
	"import",
	"family_resolution",
	"humanoid_normalization",
	"fixture_compilation",
	"artifact_integrity",
	"rig_binding",
	"assemble_and_measure",
]

## Identity fields the report must repeat and `verify` must find equal to the
## envelope's. This is what stops a report for another asset, another family or
## another policy from being carried inside a correctly re-hashed certificate.
const REPORT_BOUND_FIELDS: Array[String] = [
	"fixture_content_hash",
	"source_geometry_sha256",
	"source_rig_sha256",
	"family_id",
	"family_version",
	"family_bone_map_digest",
	"compiler_version",
	"evidence_schema",
	"compiler_calibration_id",
	"compiler_calibration_version",
	"policy_id",
	"policy_version",
	"policy_calibration_id",
	"policy_calibration_version",
	"certified_side",
]

## Resolved context the authority must supply. Every one of these is something
## the authority RESOLVED from a real object, never something a caller asserted.
const REQUIRED_RESOLVED_FIELDS: Array[String] = [
	"geometry_sha256",
	"rig_sha256",
	"family_id",
	"family_version",
	"policy_id",
	"policy_version",
	"policy_calibration_id",
	"policy_calibration_version",
	"certified_side",
]

## Excluded from the certification hash: the hash field itself, and provenance
## that must not be able to change a certificate's identity.
const CERTIFICATION_EXCLUDED_KEYS: Array[String] = ["certification_hash", "source_asset"]


# ------------------------------------------------------------------- minting


## Turn the authority's OBSERVED chain results into a certificate.
##
## This is the module's only minting path and it is internal to the
## certification owner: `hand_fixture_certification_authority.gd` is the
## intended and only caller. There is deliberately no parameter through which a
## completed chain, a gate PASS or an acceptance verdict can be asserted.
##
##   * `evidence`  -- the compiled evidence payload, verbatim.
##   * `resolved`  -- identities the authority RESOLVED (see
##                    `REQUIRED_RESOLVED_FIELDS`), not identities a caller named.
##   * `steps`     -- `{step_name: {"ok": bool, "error_class": String,
##                    "observed": Dictionary}}`, one entry per `REQUIRED_CHAIN`
##                    step, each produced by the operation that actually ran.
##
## The verdict is DERIVED here: `pass` is true only when every required step is
## present, ran, reported `ok`, carries a non-empty observed body and is
## consistent with the evidence being certified. A call with no step evidence -
## the zero-gate case - is therefore refused deterministically before any
## envelope exists, rather than producing a certificate with a gap in it.
static func mint_from_observed_chain(
	evidence: Dictionary, resolved: Dictionary, steps: Dictionary
) -> Dictionary:
	var checked: Dictionary = _check_evidence(evidence, resolved)
	if not bool(checked.get("ok", false)):
		return checked
	for key in REQUIRED_RESOLVED_FIELDS:
		if str(resolved.get(key, "")).strip_edges().is_empty():
			return _refuse(
				"FIXTURE_NOT_CERTIFIED", "certification requires resolved '%s'" % key
			)
	var chain_check: Dictionary = _check_steps(evidence, resolved, steps)
	if not bool(chain_check.get("ok", false)):
		return chain_check
	var report: Dictionary = _build_report(evidence, resolved, steps)
	# Belt and braces: the report this module just built must satisfy the same
	# derivation the loader will apply to it later. If it does not, the bug is
	# here and must not become a certificate.
	var derived: Dictionary = _check_report_derivation(report)
	if not bool(derived.get("ok", false)):
		return derived
	return _seal(evidence, resolved, report, ACCEPTANCE_SCHEMA)


## The bind-sanity bootstrap fixture (see `ACCEPTANCE_SCHEMA_PROVISIONAL`).
## Records only the steps that have genuinely run so far and is marked by its
## acceptance schema, not by a flag, so it cannot be mistaken for acceptance.
static func mint_provisional(
	evidence: Dictionary, resolved: Dictionary, steps: Dictionary
) -> Dictionary:
	var checked: Dictionary = _check_evidence(evidence, resolved)
	if not bool(checked.get("ok", false)):
		return checked
	var report := {
		"authority_id": AUTHORITY_ID,
		"authority_version": AUTHORITY_VERSION,
		"provisional": true,
		"pass": false,
		"detail": "scoped to bind-sanity execution; never acceptance, never saved",
		"steps": steps.duplicate(true),
	}
	for f in REPORT_BOUND_FIELDS:
		report[f] = _bound_value(f, evidence, resolved)
	return _seal(evidence, resolved, report, ACCEPTANCE_SCHEMA_PROVISIONAL)


static func _seal(
	evidence: Dictionary, resolved: Dictionary, report: Dictionary, acceptance_schema: String
) -> Dictionary:
	var cert := {
		"schema": CERTIFICATION_SCHEMA,
		"acceptance_schema": acceptance_schema,
		"acceptance_version": ACCEPTANCE_VERSION,
		"acceptance_authority_id": AUTHORITY_ID,
		"acceptance_authority_version": AUTHORITY_VERSION,
		"certified": acceptance_schema == ACCEPTANCE_SCHEMA,
		# The chain as the authority ran it. `verify` requires it to be exactly
		# `REQUIRED_CHAIN`, so this is a record, never a claim.
		"chain": _as_strings(report.get("chain", [])),
		"certified_side": str(resolved["certified_side"]),
		"required_sides": _sorted_strings(resolved.get("required_sides", [])),
		# What the acceptance was true FOR.
		"fixture_content_hash": str(evidence["content_hash"]),
		"source_geometry_sha256": str(resolved["geometry_sha256"]),
		"source_rig_sha256": str(resolved["rig_sha256"]),
		"rig_identity_schema": str(evidence.get("rig_identity_schema", "")),
		"family_id": str(resolved["family_id"]),
		"family_version": str(resolved["family_version"]),
		"family_bone_map_digest": str(evidence.get("family_bone_map_digest", "")),
		"compiler_version": str(evidence.get("compiler_version", "")),
		"evidence_schema": str(evidence.get("schema", "")),
		"compiler_calibration_id": str(evidence.get("calibration_id", "")),
		"compiler_calibration_version": str(evidence.get("calibration_version", "")),
		"policy_id": str(resolved["policy_id"]),
		"policy_version": str(resolved["policy_version"]),
		"policy_calibration_id": str(resolved["policy_calibration_id"]),
		"policy_calibration_version": str(resolved["policy_calibration_version"]),
		"acceptance_report_digest": acceptance_report_digest(report),
		"acceptance_report": Compiler.canonicalize(report),
		# The evidence itself, verbatim, so the runtime fixture and the
		# certificate can never describe different surfaces.
		"evidence": Compiler.canonicalize(evidence),
	}
	cert = Compiler.canonicalize(cert)
	cert["certification_hash"] = certification_hash(cert)
	return {"ok": true, "certification": cert}


## Evidence must be real, intact and compiled on the rig the authority
## resolved, before any of its gate results mean anything.
static func _check_evidence(evidence: Dictionary, resolved: Dictionary) -> Dictionary:
	if evidence.is_empty():
		return _refuse("FIXTURE_NOT_CERTIFIED", "no compiled evidence to certify")
	if str(evidence.get("schema", "")) != Compiler.ARTIFACT_SCHEMA:
		return _refuse(
			"FIXTURE_SCHEMA_UNSUPPORTED",
			"evidence schema '%s'" % evidence.get("schema", "")
		)
	if Compiler.content_hash(evidence) != str(evidence.get("content_hash", "")):
		return _refuse(
			"FIXTURE_ARTIFACT_HASH_MISMATCH", "evidence does not match its own content hash"
		)
	var required: Array = resolved.get("required_sides", [])
	if required.is_empty():
		return _refuse("FIXTURE_NOT_CERTIFIED", "no required side was named")
	for side in required:
		var d: Dictionary = (evidence.get("sides", {}) as Dictionary).get(str(side), {})
		if not bool(d.get("compiled", false)):
			return _refuse(
				str(d.get("error_class", "THUMB_SURFACE_CANDIDATES_MISSING")),
				"required side '%s' carries no compiled evidence" % side
			)
	if not str(resolved.get("certified_side", "")) in _as_strings(required):
		return _refuse(
			"FIXTURE_NOT_CERTIFIED", "the certified side is not one of the required sides"
		)
	# The certificate may only name the identities the evidence was actually
	# compiled from: it cannot re-point a fixture at another rig.
	if str(evidence.get("source_geometry_sha256", "")) != str(
		resolved.get("geometry_sha256", "")
	):
		return _refuse(
			"FIXTURE_GEOMETRY_HASH_MISMATCH", "evidence was compiled on another geometry"
		)
	if str(evidence.get("source_rig_sha256", "")) != str(resolved.get("rig_sha256", "")):
		return _refuse("FIXTURE_RIG_HASH_MISMATCH", "evidence was compiled on another rig")
	return {"ok": true}


## Every required step must be present, have run, have reported a result, and
## have observed something consistent with the evidence being certified. This
## is where a fabricated or borrowed step set is rejected: the observations are
## cross-checked against the real evidence rather than trusted.
static func _check_steps(
	evidence: Dictionary, resolved: Dictionary, steps: Dictionary
) -> Dictionary:
	var missing: Array[String] = []
	for step in REQUIRED_CHAIN:
		if not steps.has(step):
			missing.append(str(step))
	if not missing.is_empty():
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"the acceptance chain did not run: no observed result for %s"
				% ", ".join(missing)
		)
	for key in steps.keys():
		if not str(key) in REQUIRED_CHAIN:
			return _refuse(
				"FIXTURE_NOT_CERTIFIED", "'%s' is not a step of the acceptance chain" % key
			)
	for step in REQUIRED_CHAIN:
		var s: Dictionary = steps[step]
		if not bool(s.get("ok", false)):
			return _refuse(
				str(s.get("error_class", "FIXTURE_NOT_CERTIFIED")),
				"step '%s' did not pass" % step
			)
		if not str(s.get("error_class", "")).is_empty():
			return _refuse(
				str(s["error_class"]),
				"step '%s' reported both a pass and an error class" % step
			)
		if (s.get("observed", {}) as Dictionary).is_empty():
			return _refuse(
				"FIXTURE_NOT_CERTIFIED",
				"step '%s' recorded no observation, so it cannot have run" % step
			)
	# Cross-checks: the observations must be about THIS evidence and THIS rig.
	var compiled: Dictionary = (steps["fixture_compilation"] as Dictionary)["observed"]
	if str(compiled.get("content_hash", "")) != str(evidence.get("content_hash", "")):
		return _refuse(
			"FIXTURE_ARTIFACT_HASH_MISMATCH",
			"the compilation step observed different evidence"
		)
	var binding: Dictionary = (steps["rig_binding"] as Dictionary)["observed"]
	if str(binding.get("geometry_sha256", "")) != str(resolved.get("geometry_sha256", "")):
		return _refuse(
			"FIXTURE_GEOMETRY_HASH_MISMATCH", "the binding step observed another geometry"
		)
	if str(binding.get("rig_sha256", "")) != str(resolved.get("rig_sha256", "")):
		return _refuse(
			"FIXTURE_RIG_HASH_MISMATCH", "the binding step observed another rig"
		)
	var family: Dictionary = (steps["family_resolution"] as Dictionary)["observed"]
	if str(family.get("family_id", "")) != str(resolved.get("family_id", "")):
		return _refuse(
			"FIXTURE_FAMILY_MISMATCH", "the family step resolved a different family"
		)
	if str(family.get("family_version", "")) != str(resolved.get("family_version", "")):
		return _refuse(
			"FIXTURE_FAMILY_VERSION_MISMATCH",
			"the family step resolved a different family version"
		)
	# Achieved geometry: the one externally anchored behavioural observation.
	var measured: Dictionary = (steps["assemble_and_measure"] as Dictionary)["observed"]
	if str(measured.get("policy_id", "")) != str(resolved.get("policy_id", "")):
		return _refuse(
			"FIXTURE_NOT_CERTIFIED", "the assembly step ran under a different policy"
		)
	if str(measured.get("closest_patch", "")) != "pad":
		return _refuse(
			"THUMB_SURFACE_TRUTH_GATE_FAILED",
			"achieved closest patch is '%s', not the volar pad"
				% str(measured.get("closest_patch", ""))
		)
	if not bool(measured.get("invariants_pass", false)):
		return _refuse(
			"GRIP_GEOMETRY_FAILED", "the achieved grip invariants did not pass"
		)
	if not bool(measured.get("mesh_binding_verified", false)):
		return _refuse(
			"FIXTURE_MESH_BINDING_FAILED",
			"the assembly step did not verify the fixture against the live rig"
		)
	var height: Dictionary = (steps["humanoid_normalization"] as Dictionary)["observed"]
	if float(height.get("height", 0.0)) <= 0.0:
		return _refuse(
			"DEGENERATE_HEIGHT", "the normalization step observed no humanoid height"
		)
	return {"ok": true}


## The canonical acceptance report: an OUTPUT of what the authority observed,
## never an input. Its digest protects its integrity afterwards; its truth
## comes from the chain that produced the observations.
static func _build_report(
	evidence: Dictionary, resolved: Dictionary, steps: Dictionary
) -> Dictionary:
	var report := {
		"authority_id": AUTHORITY_ID,
		"authority_version": AUTHORITY_VERSION,
		"provisional": false,
		# Derived, not declared: see `_check_report_derivation`.
		"pass": true,
		"chain": REQUIRED_CHAIN.duplicate(),
		"required_sides": _sorted_strings(resolved.get("required_sides", [])),
		"steps": steps.duplicate(true),
	}
	for f in REPORT_BOUND_FIELDS:
		report[f] = _bound_value(f, evidence, resolved)
	return report


static func _bound_value(field: String, evidence: Dictionary, resolved: Dictionary) -> String:
	match field:
		"fixture_content_hash":
			return str(evidence.get("content_hash", ""))
		"source_geometry_sha256":
			return str(resolved.get("geometry_sha256", ""))
		"source_rig_sha256":
			return str(resolved.get("rig_sha256", ""))
		"family_bone_map_digest":
			return str(evidence.get("family_bone_map_digest", ""))
		"compiler_version":
			return str(evidence.get("compiler_version", ""))
		"evidence_schema":
			return str(evidence.get("schema", ""))
		"compiler_calibration_id":
			return str(evidence.get("calibration_id", ""))
		"compiler_calibration_version":
			return str(evidence.get("calibration_version", ""))
	return str(resolved.get(field, ""))


# --------------------------------------------------------------------- hashes


## Identity level 4: the envelope's own hash, over the WHOLE certificate except
## the hash field and provenance. Manipulating any acceptance metadata -- the
## verdict, the chain, the gate results, the bound identities, the policy -- is
## therefore detectable without re-running the chain.
static func certification_hash(cert: Dictionary) -> String:
	var hashable := {}
	for k in cert.keys():
		if str(k) in CERTIFICATION_EXCLUDED_KEYS:
			continue
		hashable[str(k)] = cert[k]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(Compiler.canonical_text(Compiler.canonicalize(hashable)).to_utf8_buffer())
	return ctx.finish().hex_encode().to_upper()


## Digest of the gate results themselves, so the report cannot be swapped for a
## different one that happens to say "pass". Integrity only: a correctly
## recomputed digest never makes a report TRUE, which is why `verify` also
## re-derives the verdict and re-binds the report to the envelope.
static func acceptance_report_digest(report: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(ACCEPTANCE_SCHEMA.to_utf8_buffer())
	ctx.update(ACCEPTANCE_VERSION.to_utf8_buffer())
	ctx.update(Compiler.canonical_text(Compiler.canonicalize(report)).to_utf8_buffer())
	return ctx.finish().hex_encode().to_upper()


# --------------------------------------------------------------- verification


## CERTIFICATE VERIFICATION. What this proves:
##
##   * the envelope and its embedded evidence have not drifted since minting,
##   * the certificate has the shape only the canonical certification path
##     produces: exactly `REQUIRED_CHAIN`, in order, with one observed result
##     per step, naming this authority,
##   * the certificate is bound to a specific evidence payload, geometry
##     identity, rig identity, family + version and policy + calibration,
##   * the recorded verdict is DERIVED from the recorded step results rather
##     than declared alongside them, and every step recorded a pass,
##   * the acceptance report describes the same asset, family and policy as the
##     envelope, so a report cannot be borrowed from another certificate.
##
## What this does NOT prove: that the recorded measurements were really taken.
## No local check can, because there is no signing authority; a forger with the
## real asset who fabricates a fully self-consistent step set still gets past
## this function. That is why certificate verification is not the live safety
## property -- see `compiled_hand_fixture.gd::verify_against_rig` and the
## assembler's gates, which re-run bind sanity and the achieved-geometry gates
## on the actual rig every time a fixture is used. BOTH are required.
static func verify(cert: Dictionary, allow_provisional: bool = false) -> Dictionary:
	if cert.is_empty():
		return _refuse("FIXTURE_NOT_CERTIFIED", "no certification envelope")
	if not str(cert.get("schema", "")) in SUPPORTED_CERTIFICATION_SCHEMAS:
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"'%s' is not a certification envelope" % cert.get("schema", "")
		)
	var acceptance: String = str(cert.get("acceptance_schema", ""))
	var is_provisional: bool = acceptance == ACCEPTANCE_SCHEMA_PROVISIONAL
	if is_provisional and not allow_provisional:
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"this is a bind-sanity bootstrap envelope, not an acceptance"
		)
	if not is_provisional and acceptance != ACCEPTANCE_SCHEMA:
		return _refuse(
			"FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED", "acceptance schema '%s'" % acceptance
		)
	if str(cert.get("acceptance_version", "")) != ACCEPTANCE_VERSION:
		return _refuse(
			"FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED",
			"acceptance version '%s'" % cert.get("acceptance_version", "")
		)
	if certification_hash(cert) != str(cert.get("certification_hash", "")):
		return _refuse(
			"FIXTURE_CERTIFICATION_HASH_MISMATCH",
			"the certification envelope does not match its own hash"
		)
	var report: Dictionary = cert.get("acceptance_report", {})
	if acceptance_report_digest(report) != str(cert.get("acceptance_report_digest", "")):
		return _refuse(
			"FIXTURE_CERTIFICATION_HASH_MISMATCH",
			"the acceptance report does not match its digest"
		)
	var evidence: Dictionary = cert.get("evidence", {})
	var embedded: Dictionary = _check_embedded_evidence(cert, evidence)
	if not bool(embedded.get("ok", false)):
		return embedded
	if is_provisional:
		return {"ok": true, "certification": cert, "evidence": evidence, "provisional": true}
	if not bool(cert.get("certified", false)):
		return _refuse("FIXTURE_NOT_CERTIFIED", "the envelope does not record a certification")
	if str(cert.get("acceptance_authority_id", "")) != AUTHORITY_ID:
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"the envelope names authority '%s'" % cert.get("acceptance_authority_id", "")
		)
	if str(cert.get("acceptance_authority_version", "")) != AUTHORITY_VERSION:
		return _refuse(
			"FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED",
			"authority version '%s'" % cert.get("acceptance_authority_version", "")
		)
	# The chain is a record of what ran, so it must be exactly the required
	# chain: no missing step, no extra step, no duplicate, no reordering.
	var chain_ok: Dictionary = _check_exact_chain(cert.get("chain", []))
	if not bool(chain_ok.get("ok", false)):
		return chain_ok
	var derived: Dictionary = _check_report_derivation(report)
	if not bool(derived.get("ok", false)):
		return derived
	# The report must be about THIS certificate's asset, family and policy.
	for f in REPORT_BOUND_FIELDS:
		if str(report.get(f, "")) != str(cert.get(f, "")):
			return _refuse(
				_binding_error_class(f),
				"the acceptance report names a different '%s' than the certificate" % f
			)
	if str(report.get("certified_side", "")) != str(cert.get("certified_side", "")):
		return _refuse("FIXTURE_NOT_CERTIFIED", "the report certifies another side")
	if not str(cert.get("certified_side", "")) in _as_strings(cert.get("required_sides", [])):
		return _refuse(
			"FIXTURE_NOT_CERTIFIED", "the certified side is not among the required sides"
		)
	return {"ok": true, "certification": cert, "evidence": evidence}


## The recorded verdict must follow from the recorded step results, and every
## step must carry an observation. This is what makes a hand-written
## `{"pass": true}` report useless even when its digest is recomputed.
static func _check_report_derivation(report: Dictionary) -> Dictionary:
	if report.is_empty():
		return _refuse("FIXTURE_NOT_CERTIFIED", "no acceptance report")
	if str(report.get("authority_id", "")) != AUTHORITY_ID:
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"the acceptance report names authority '%s'" % report.get("authority_id", "")
		)
	if str(report.get("authority_version", "")) != AUTHORITY_VERSION:
		return _refuse(
			"FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED",
			"report authority version '%s'" % report.get("authority_version", "")
		)
	if bool(report.get("provisional", false)):
		return _refuse(
			"FIXTURE_NOT_CERTIFIED", "a bind-sanity bootstrap report is not an acceptance"
		)
	var chain_ok: Dictionary = _check_exact_chain(report.get("chain", []))
	if not bool(chain_ok.get("ok", false)):
		return chain_ok
	if not (report.get("steps", null) is Dictionary):
		return _refuse(
			"FIXTURE_NOT_CERTIFIED", "the acceptance report records no per-step results"
		)
	var steps: Dictionary = report["steps"]
	var all_ok := true
	for step in REQUIRED_CHAIN:
		if not steps.has(step):
			return _refuse(
				"FIXTURE_NOT_CERTIFIED",
				"the acceptance report has no observed result for '%s'" % step
			)
		var s = steps[step]
		if not (s is Dictionary):
			return _refuse(
				"FIXTURE_NOT_CERTIFIED", "step '%s' is not an observed result" % step
			)
		var sd: Dictionary = s
		if (sd.get("observed", {}) as Dictionary).is_empty():
			return _refuse(
				"FIXTURE_NOT_CERTIFIED",
				"step '%s' recorded no observation, so it cannot have run" % step
			)
		if not str(sd.get("error_class", "")).is_empty():
			return _refuse(
				str(sd["error_class"]), "step '%s' records a failure" % step
			)
		all_ok = all_ok and bool(sd.get("ok", false))
	for key in steps.keys():
		if not str(key) in REQUIRED_CHAIN:
			return _refuse(
				"FIXTURE_NOT_CERTIFIED", "'%s' is not a step of the acceptance chain" % key
			)
	if not all_ok:
		return _refuse("FIXTURE_NOT_CERTIFIED", "a recorded step did not pass")
	# The verdict is not allowed to disagree with its own evidence.
	if bool(report.get("pass", false)) != all_ok:
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"the recorded verdict does not follow from the recorded step results"
		)
	# The achieved-geometry observation is the acceptance's behavioural anchor.
	var measured: Dictionary = (steps["assemble_and_measure"] as Dictionary).get("observed", {})
	if str(measured.get("closest_patch", "")) != "pad":
		return _refuse(
			"THUMB_SURFACE_TRUTH_GATE_FAILED",
			"the recorded achieved contact is '%s'" % str(measured.get("closest_patch", ""))
		)
	if not bool(measured.get("invariants_pass", false)):
		return _refuse("GRIP_GEOMETRY_FAILED", "the recorded grip invariants did not pass")
	return {"ok": true}


static func _check_exact_chain(chain) -> Dictionary:
	if not (chain is Array):
		return _refuse("FIXTURE_NOT_CERTIFIED", "no recorded chain")
	var got: Array = _as_strings(chain)
	if got.size() != REQUIRED_CHAIN.size():
		return _refuse(
			"FIXTURE_NOT_CERTIFIED",
			"the recorded chain has %d steps, the acceptance chain has %d"
				% [got.size(), REQUIRED_CHAIN.size()]
		)
	for i in REQUIRED_CHAIN.size():
		if str(got[i]) != str(REQUIRED_CHAIN[i]):
			return _refuse(
				"FIXTURE_NOT_CERTIFIED",
				"the recorded chain is not the acceptance chain (step %d is '%s', expected '%s')"
					% [i, got[i], REQUIRED_CHAIN[i]]
			)
	return {"ok": true}


static func _check_embedded_evidence(cert: Dictionary, evidence: Dictionary) -> Dictionary:
	if Compiler.content_hash(evidence) != str(cert.get("fixture_content_hash", "")):
		return _refuse(
			"FIXTURE_ARTIFACT_HASH_MISMATCH",
			"the embedded evidence is not the evidence that was certified"
		)
	if str(evidence.get("content_hash", "")) != str(cert.get("fixture_content_hash", "")):
		return _refuse(
			"FIXTURE_ARTIFACT_HASH_MISMATCH", "the evidence carries a different content hash"
		)
	if str(evidence.get("source_rig_sha256", "")) != str(cert.get("source_rig_sha256", "")):
		return _refuse("FIXTURE_RIG_HASH_MISMATCH", "certificate and evidence name different rigs")
	if str(evidence.get("source_geometry_sha256", "")) != str(
		cert.get("source_geometry_sha256", "")
	):
		return _refuse(
			"FIXTURE_GEOMETRY_HASH_MISMATCH",
			"certificate and evidence name different geometries"
		)
	return {"ok": true}


## Report-versus-envelope disagreement reported in the vocabulary of whatever
## disagreed, so a rejection names the real domain fact.
static func _binding_error_class(field: String) -> String:
	match field:
		"source_geometry_sha256":
			return "FIXTURE_GEOMETRY_HASH_MISMATCH"
		"source_rig_sha256":
			return "FIXTURE_RIG_HASH_MISMATCH"
		"fixture_content_hash":
			return "FIXTURE_ARTIFACT_HASH_MISMATCH"
		"family_id":
			return "FIXTURE_FAMILY_MISMATCH"
		"family_version":
			return "FIXTURE_FAMILY_VERSION_MISMATCH"
	return "FIXTURE_NOT_CERTIFIED"


# ------------------------------------------------------------------ transport


## Write a certificate. A bind-sanity bootstrap envelope is refused: it exists
## only to let the acceptance chain run the assembler, and a file is exactly
## what it must never become.
static func save(cert: Dictionary, path: String) -> Dictionary:
	if str(cert.get("acceptance_schema", "")) == ACCEPTANCE_SCHEMA_PROVISIONAL:
		return {
			"ok": false,
			"error_class": "FIXTURE_NOT_CERTIFIED",
			"detail": "a bind-sanity bootstrap envelope may not be written to disk",
		}
	var res: Resource = CertifiedResource.new()
	res.certification = cert.duplicate(true)
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_WRITE_FAILED", "godot_error": err}
	return {
		"ok": true,
		"path": path,
		"certification_hash": str(cert.get("certification_hash", "")),
	}


## Load a certified runtime fixture. A compiled-evidence resource at this path
## is refused by TYPE, not by inspecting a flag: it has no `certification`
## property at all, so a renamed staging file reports `FIXTURE_NOT_CERTIFIED`.
static func load_certified(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_MISSING", "path": path}
	var res: Resource = load(path)
	if res == null:
		return {"ok": false, "error_class": "FIXTURE_ARTIFACT_MISSING", "path": path}
	if not ("certification" in res):
		return {
			"ok": false,
			"error_class": "FIXTURE_NOT_CERTIFIED",
			"detail": "the resource at this path carries no certification envelope",
			"path": path,
		}
	return verify(res.certification)


static func _as_strings(values) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for v in values:
		out.append(str(v))
	return out


static func _sorted_strings(values) -> Array:
	var out: Array = _as_strings(values)
	out.sort()
	return out


static func _refuse(error_class: String, detail: String) -> Dictionary:
	return {"ok": false, "error_class": error_class, "detail": detail}
