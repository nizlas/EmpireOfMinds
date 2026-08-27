# CALIBRATING compiler thresholds — explicit, versioned, injectable.
#
# These are NOT proven generic skeleton-family anatomy. Every value here was
# measured on ONE reference rig (Uthana A2.7) and is kept in its own owner so
# that it cannot masquerade as a universal core constant of the compiler.
#
# `MIN_CLASSIFICATION_MARGIN` in particular is calibration data:
#   * the accepted right-hand reference clears it with a wide margin;
#   * the left reference's outcome is decided by 0.0511, i.e. it fails BECAUSE
#     the threshold sits above that value;
#   * the value was raised from 0.05 to 0.08 while implementing that reference.
# Two rigs are not evidence of a species-wide constant. Widening it to admit
# more assets is forbidden in this stage: it would convert a fail-closed
# left-hand rejection into a silent "closest wins" selection.
#
# Any change to a value here changes CALIBRATION_VERSION, which is part of the
# compiled artifact's hashed identity, so existing artifacts are invalidated.
extends RefCounted

const CALIBRATION_ID := "hand_fixture_compiler_calibration_uthana_a2_7"
const CALIBRATION_VERSION := "1"
## Evidence base behind the numbers below. One rig, two hands.
const CALIBRATION_STAGE := "CALIBRATING"
const CALIBRATION_EVIDENCE_RIGS: Array[String] = ["uthana_a2_7_right", "uthana_a2_7_left"]

## A patch must clear the best rejected candidate by this margin, otherwise
## the choice is not stable enough to certify. Without it the compiler would
## be silently picking a "best" candidate out of a continuum, which is exactly
## the manual judgement the compiler slice removed.
const MIN_CLASSIFICATION_MARGIN := 0.08


## Identity of this calibration as it enters the artifact hash.
static func identity() -> Dictionary:
	return {
		"calibration_id": CALIBRATION_ID,
		"calibration_version": CALIBRATION_VERSION,
		"calibration_stage": CALIBRATION_STAGE,
		"min_classification_margin": MIN_CLASSIFICATION_MARGIN,
	}
