# Mixamo / Godot-humanoid 52-bone hand family conventions.
# Skeleton-family data only: bone-name templates and hinge-axis convention.
# Per-asset mesh patches and calibrated angles live in a warrior fixture.
extends RefCounted

const FAMILY_ID := "mixamo_52_humanoid"

const DIGITS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]

## Mixamo finger bones use mixamorig_<Side>Hand<Digit><N>.
## Godot humanoid wrist/forearm use <Side>Hand / <Side>ForeArm.
static func bone_map(side: String) -> Dictionary:
	var s: String = "Right" if side == "right" else "Left"
	var other: String = "Left" if side == "right" else "Right"
	return {
		"side": side,
		"hand": "%sHand" % s,
		"forearm": "%sForeArm" % s,
		"forearm_alt": "%sLowerArm" % s,
		"opposite_hand": "%sHand" % other,
		"opposite_index_mcp": "mixamorig_%sHandIndex1" % other,
		"opposite_thumb_cmc": "mixamorig_%sHandThumb1" % other,
		"thumb": [
			"mixamorig_%sHandThumb1" % s,
			"mixamorig_%sHandThumb2" % s,
			"mixamorig_%sHandThumb3" % s,
		],
		"index": [
			"mixamorig_%sHandIndex1" % s,
			"mixamorig_%sHandIndex2" % s,
			"mixamorig_%sHandIndex3" % s,
		],
		"middle": [
			"mixamorig_%sHandMiddle1" % s,
			"mixamorig_%sHandMiddle2" % s,
			"mixamorig_%sHandMiddle3" % s,
		],
		"ring": [
			"mixamorig_%sHandRing1" % s,
			"mixamorig_%sHandRing2" % s,
			"mixamorig_%sHandRing3" % s,
		],
		"pinky": [
			"mixamorig_%sHandPinky1" % s,
			"mixamorig_%sHandPinky2" % s,
			"mixamorig_%sHandPinky3" % s,
		],
	}


## MCP hinge on THIS family is the bone-local +X axis (Mixamo finger rest).
## Not a universal claim that +X is flexion on every rig or on the thumb.
const MCP_HINGE_LOCAL := Vector3(1.0, 0.0, 0.0)
## Distal tip estimate as a fraction of the middle segment (no tip-end bone).
const DISTAL_TIP_FRACTION := 0.9

## Humanoid-height bone candidates for this family (canonical Godot-humanoid
## names first, Mixamo raw names as fallback). Family data — the generic
## skinning utility receives these, it never names bones itself.
const HEIGHT_HEAD_CANDIDATES: Array[String] = ["head_end", "Head"]
const HEIGHT_FLOOR_CANDIDATES: Array[String] = [
	"LeftToes",
	"RightToes",
	"LeftToeBase",
	"RightToeBase",
	"mixamorig_LeftToeBase",
	"mixamorig_RightToeBase",
	"LeftFoot",
	"RightFoot",
]
