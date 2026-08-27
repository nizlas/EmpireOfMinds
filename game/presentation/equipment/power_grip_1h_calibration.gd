# Canonical POSE calibration for the power_grip_1h_v1 interaction profile.
#
# A2.10 contract split. The hand-fixture compiler derives per-unit SURFACE
# evidence (which triangles are the nail plate and the volar pad, their rest
# normals, winding and pad marker) from the rigged mesh. It cannot derive
# how far a canonical power grip flexes the fingers or how the thumb column
# is opposed: those are authored INTERACTION-POLICY numbers for this grip
# profile, shared by every unit of the profile rather than authored per
# asset, and must not be faked out of geometry.
#
# These numbers are the accepted A2.7 calibration. They are reproduced here
# as profile data so that the production path no longer has to read the
# hand-authored Uthana fixture, which is now reference/regression only. A
# regression test pins them to that fixture's constants so the two cannot
# drift apart silently.
extends RefCounted

const CALIBRATION_ID := "power_grip_1h_v1_canon_a27"
## Bumped whenever an angle below changes. Recorded in a certified fixture
## (A2.12) so a recalibrated pose cannot reuse an old certificate.
## 1 = the accepted A2.7 canonical pose, unchanged.
const CALIBRATION_VERSION := "1"
const POLICY_ID := "power_grip_1h_v1"

## Accepted A2.7 right-hand thumb column. CMC tau is opposition/pronation;
## MCP/IP stay pure flexion. A2.6's tau = -90 is a rejected false positive.
const CANON_THUMB_ANAT := {
	"sigma": 20.0,
	"phi": 0.0,
	"tau": -60.0,
	"flex_mcp": 10.0,
	"flex_ip": 80.0,
}
## Left CMC derived independently on the reference asset (A2.8), NOT a
## negated copy of the right Euler numbers. The full left grip still
## fail-closes on the T2/distal-station conflict: these are not a PASS.
const CANON_THUMB_ANAT_LEFT := {
	"sigma": 19.0,
	"phi": -110.0,
	"tau": -80.0,
	"flex_mcp": 10.0,
	"flex_ip": 80.0,
}
## Authored finger flexion of the canonical power grip, per digit,
## proximal -> distal, in degrees.
const CANON_FLEX_DEG := {
	"index": [60.0, 71.0, 35.0],
	"middle": [63.0, 75.0, 37.0],
	"ring": [69.0, 81.0, 40.0],
	"pinky": [71.0, 83.0, 43.0],
}


static func thumb_anat_for_side(side: String) -> Dictionary:
	if side == "left":
		return CANON_THUMB_ANAT_LEFT.duplicate()
	return CANON_THUMB_ANAT.duplicate()


static func finger_flex() -> Dictionary:
	return CANON_FLEX_DEG.duplicate(true)


## Calibration payload in the shape `compiled_hand_fixture.gd` expects.
static func payload() -> Dictionary:
	return {
		"calibration_id": CALIBRATION_ID,
		# Carried so a certified fixture can refuse a payload that is not the
		# calibration its acceptance was measured under (A2.13a).
		"calibration_version": CALIBRATION_VERSION,
		"policy_id": POLICY_ID,
		"thumb_anat": {
			"right": CANON_THUMB_ANAT.duplicate(),
			"left": CANON_THUMB_ANAT_LEFT.duplicate(),
		},
		"finger_flex": CANON_FLEX_DEG.duplicate(true),
	}
