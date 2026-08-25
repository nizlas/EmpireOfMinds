# A2 compatibility shell (A2.9): the power-grip SOLVING/MEASUREMENT engine
# is owned by res://presentation/equipment/power_grip_1h_engine.gd. This
# shell only carries the accepted A2.7 RIGHT-hand fixture data (bone chains,
# canonical pose numbers, verified surface patches, superseded false-positive
# references) and serves it through the engine's `_fallback_*` seams so the
# legacy attachment path and the A2 regression tests keep their exact
# accepted behavior. The generic assembler path injects a compiled
# HumanoidHandProfile instead and never reads these constants.
#
# History of the calibrated pose (A2.3 -> A2.7, incl. the A2.6 nail-surface
# ground-truth audit and the rejected tau=-90 overpronation) lives in
# A2_NOTES.md, A2_6_NAIL_SURFACE_GROUND_TRUTH_AUDIT.md and the versioned
# fixture res://presentation/equipment/uthana_warrior_hand_fixture.gd.
class_name UthanaA2PowerGrip
extends "res://presentation/equipment/power_grip_1h_engine.gd"

const Pads = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_skinned_pads.gd"
)
const HandFrame = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_hand_grip_frame.gd"
)

const RIGHT_CHAINS: Dictionary = {
	"thumb": [
		"mixamorig_RightHandThumb1",
		"mixamorig_RightHandThumb2",
		"mixamorig_RightHandThumb3",
	],
	"index": [
		"mixamorig_RightHandIndex1",
		"mixamorig_RightHandIndex2",
		"mixamorig_RightHandIndex3",
	],
	"middle": [
		"mixamorig_RightHandMiddle1",
		"mixamorig_RightHandMiddle2",
		"mixamorig_RightHandMiddle3",
	],
	"ring": [
		"mixamorig_RightHandRing1",
		"mixamorig_RightHandRing2",
		"mixamorig_RightHandRing3",
	],
	"pinky": [
		"mixamorig_RightHandPinky1",
		"mixamorig_RightHandPinky2",
		"mixamorig_RightHandPinky3",
	],
}
const LEFT_PROBE_BONES: Array[String] = [
	"LeftHand",
	"mixamorig_LeftHandIndex1",
	"mixamorig_LeftHandThumb1",
]

## Canonical authored power-grip flexion per chain joint (degrees, positive =
## closing toward the palm; the measured per-rig sign is applied at bind).
## Authored once for the EoM 52-bone skeleton profile (A2.3).
const CANON_FLEX_DEG: Dictionary = {
	"index": [60.0, 71.0, 35.0],
	"middle": [63.0, 75.0, 37.0],
	"ring": [69.0, 81.0, 40.0],
	"pinky": [71.0, 83.0, 43.0],
}
## A2.7 calibrated anatomical thumb pose (this warrior). CMC = sigma swing
## at phi + bounded tau pronation; MCP/IP = pure flexion about empirically
## VALIDATED per-joint axes. tau -60 is the accepted pose; the rejected
## A2.6 overpronation was tau -90 (see the ground-truth audit).
const CANON_THUMB_ANAT := {
	"sigma": 20.0,
	"phi": 0.0,
	"tau": -60.0,
	"flex_mcp": 10.0,
	"flex_ip": 80.0,
}

## SUPERSEDED (A2.7): the A2.5 "texture-verified" constants below were
## FORENSICALLY DISPROVEN by A2_6_NAIL_SURFACE_GROUND_TRUTH_AUDIT.md — the
## old nail constant tracked dorsal knuckle skin ~67 deg off the true plate
## on a CW-authored mesh; the pad normal was 56 deg off and the marker ~7 mm
## off. Kept ONLY so tests can demonstrate the historical +0.98 false
## positive; nothing in acceptance reads them.
const SUPERSEDED_A25_NAIL_NORMAL_LOCAL := Vector3(-0.158876, -0.048808, -0.986091)
const SUPERSEDED_A25_PAD_NORMAL_LOCAL := Vector3(-0.417165, -0.33319, 0.845552)
const SUPERSEDED_A25_PAD_MARKER_LOCAL := Vector3(0.011303, 0.002786, 0.00061)

## A2.7 texture/topology-VERIFIED distal thumb patches (Uthana profile
## metadata; identity = surface index + vertex indices into the hash-pinned
## imported GLB mesh; `flip` = rest-anchored winding factor, fixed by
## topology, NEVER re-flipped at pose). Runtime never analyses the albedo;
## bind-sanity re-derives UVs/weights/rest normals and fails closed.
const T3_NAIL_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [5486, 3302, 3301], "uvc": Vector2(0.923572, 0.030563), "flip": -1.0},
	{"si": 0, "i": [5486, 5488, 3302], "uvc": Vector2(0.930995, 0.032087), "flip": -1.0},
	{"si": 0, "i": [3302, 5488, 5489], "uvc": Vector2(0.933836, 0.033164), "flip": -1.0},
	{"si": 0, "i": [3302, 5489, 5484], "uvc": Vector2(0.936114, 0.033419), "flip": -1.0},
]
const T3_PAD_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [5480, 5481, 5482], "uvc": Vector2(0.932028, 0.013940), "flip": -1.0},
	{"si": 0, "i": [5480, 5482, 5483], "uvc": Vector2(0.928115, 0.010751), "flip": -1.0},
	{"si": 0, "i": [5482, 3301, 5483], "uvc": Vector2(0.920574, 0.017876), "flip": -1.0},
	{"si": 0, "i": [5482, 5481, 5485], "uvc": Vector2(0.931609, 0.020589), "flip": -1.0},
	{"si": 0, "i": [3300, 5485, 5481], "uvc": Vector2(0.934737, 0.021865), "flip": -1.0},
	{"si": 0, "i": [5486, 3301, 5482], "uvc": Vector2(0.922155, 0.023965), "flip": -1.0},
	{"si": 0, "i": [5486, 5482, 5485], "uvc": Vector2(0.929277, 0.023490), "flip": -1.0},
	{"si": 0, "i": [5487, 5485, 3300], "uvc": Vector2(0.934695, 0.024450), "flip": -1.0},
	{"si": 0, "i": [5486, 5485, 5488], "uvc": Vector2(0.930595, 0.026941), "flip": -1.0},
	{"si": 0, "i": [5487, 5488, 5485], "uvc": Vector2(0.932885, 0.026626), "flip": -1.0},
]
## Area-weighted REST aggregate normals of the verified patches (Thumb3
## bone-local). The plates are nearly PERPENDICULAR at rest on this asset
## (nail.pad = -0.02) — the old "plates must be opposed" sanity was itself
## part of the A2.5 defect.
const T3_NAIL_NORMAL_LOCAL := Vector3(0.844382, -0.028367, -0.534991)
const T3_PAD_NORMAL_LOCAL := Vector3(0.50628, -0.186105, 0.84205)
const T3_REST_NAIL_PAD_DOT := -0.02
## Pad contact marker = area centroid of the VERIFIED pad plate (Thumb3
## local): contact, approach and refinement measure the true pulp.
const T3_PAD_MARKER_LOCAL := Vector3(0.010229, -0.00161, 0.006254)


func _fallback_surface() -> Dictionary:
	return {
		"nail_tris": T3_NAIL_TRIS,
		"pad_tris": T3_PAD_TRIS,
		"nail_normal_local": T3_NAIL_NORMAL_LOCAL,
		"pad_normal_local": T3_PAD_NORMAL_LOCAL,
		"rest_nail_pad_dot": T3_REST_NAIL_PAD_DOT,
		"pad_marker_local": T3_PAD_MARKER_LOCAL,
		"superseded_nail_normal_local": SUPERSEDED_A25_NAIL_NORMAL_LOCAL,
		"superseded_pad_normal_local": SUPERSEDED_A25_PAD_NORMAL_LOCAL,
	}


func _fallback_thumb_anat() -> Dictionary:
	return CANON_THUMB_ANAT


func _fallback_finger_flex() -> Dictionary:
	return CANON_FLEX_DEG


func _fallback_bind_spec() -> Dictionary:
	return {
		"chains": RIGHT_CHAINS,
		"owner_hand": "RightHand",
		"owner_forearm": "RightForeArm",
		"owner_forearm_alt": "RightLowerArm",
		"opposite_probes": LEFT_PROBE_BONES,
	}


func _fallback_tip_bones() -> Dictionary:
	return Pads.TIP_BONES


func _fallback_live_frame(skel: Skeleton3D) -> Dictionary:
	return HandFrame.compute(skel, false)
