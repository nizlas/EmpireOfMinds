# Mixamo / Godot-humanoid 52-bone hand family conventions.
# Skeleton-family data only: bone-name templates and hinge-axis convention.
# Per-asset mesh patches and calibrated angles live in a warrior fixture.
extends RefCounted

const FAMILY_ID := "mixamo_52_humanoid"
## Bumped whenever the bone map, the alias table or a convention constant
## below changes. A compiled fixture stores this version plus a digest of the
## resolved bone map, so an unversioned edit still invalidates old artifacts.
## 2 = A2.11: explicit import-name aliases (raw Mixamo / Godot-humanoid).
## 3 = A2.12: semantic height landmarks resolved through the same alias table.
const FAMILY_VERSION := "3"

## The two import representations this family accepts for the SAME rig:
## Godot's humanoid retarget renames the wrist to `RightHand` while leaving
## finger bones as `mixamorig_RightHandIndex1`, whereas a raw GLB keeps
## `mixamorig_` on every bone. Both are the same skeleton family, so the
## alias table lives here (family data) and never in the generic compiler.
const IMPORT_REPRESENTATIONS: Array[String] = ["godot_humanoid_retarget", "raw_mixamo"]
const NAME_ALIAS_PREFIXES: Array[String] = ["mixamorig_", "mixamorig:"]

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


## Every accepted spelling of one canonical bone name, most canonical first.
## Pure family data: prefix presence differs per import representation, it is
## never a per-asset or per-warrior fact.
static func bone_name_candidates(canonical: String) -> Array[String]:
	var out: Array[String] = [canonical]
	var bare: String = canonical
	for p in NAME_ALIAS_PREFIXES:
		if bare.begins_with(p):
			bare = bare.substr(p.length())
			break
	if bare != canonical and not out.has(bare):
		out.append(bare)
	for p in NAME_ALIAS_PREFIXES:
		var prefixed: String = p + bare
		if not out.has(prefixed):
			out.append(prefixed)
	return out


## The bone map as it exists on THIS skeleton: each canonical name replaced by
## the alias actually present. Names with no match stay canonical so the
## consumer fails closed reporting the canonical name it wanted.
static func resolved_bone_map(skeleton: Skeleton3D, side: String) -> Dictionary:
	var map: Dictionary = bone_map(side)
	if skeleton == null:
		return map
	var out := {}
	for key in map.keys():
		var value = map[key]
		if value is Array:
			var chain: Array = []
			for name in (value as Array):
				chain.append(_resolve_name(skeleton, str(name)))
			out[key] = chain
		elif value is String and key != "side":
			out[key] = _resolve_name(skeleton, str(value))
		else:
			out[key] = value
	return out


static func _resolve_name(skeleton: Skeleton3D, canonical: String) -> String:
	for candidate in bone_name_candidates(canonical):
		if skeleton.find_bone(candidate) >= 0:
			return candidate
	return canonical


## Which import representation this skeleton uses, for machine-readable
## ingestion reports. `unknown` when the hand bone matches no accepted alias.
static func import_representation(skeleton: Skeleton3D, side: String) -> String:
	if skeleton == null:
		return "unknown"
	var canonical: String = str(bone_map(side)["hand"])
	if skeleton.find_bone(canonical) >= 0:
		return IMPORT_REPRESENTATIONS[0]
	for p in NAME_ALIAS_PREFIXES:
		if skeleton.find_bone(p + canonical) >= 0:
			return IMPORT_REPRESENTATIONS[1]
	return "unknown"


## MCP hinge on THIS family is the bone-local +X axis (Mixamo finger rest).
## Not a universal claim that +X is flexion on every rig or on the thumb.
const MCP_HINGE_LOCAL := Vector3(1.0, 0.0, 0.0)
## Distal tip estimate as a fraction of the middle segment (no tip-end bone).
const DISTAL_TIP_FRACTION := 0.9

## SEMANTIC LANDMARK ROLES (A2.12).
##
## Humanoid height used to be measured from two flat name lists, one of which
## had `mixamorig_` variants hand-patched in and one of which did not — so the
## same rig measured 0.888740689 under Godot-humanoid naming and exactly 0.0
## under raw Mixamo naming, and a raw delivery was rejected as
## `DEGENERATE_HEIGHT` although its geometry was fine.
##
## Landmarks are therefore addressed by ROLE. Generic ingestion, the assembler
## and the height utility name roles only; this family owns every spelling and
## resolves each canonical name through its OWN alias table
## (`bone_name_candidates`), so no consumer and no second string list ever has
## to know that `mixamorig_` exists.
const LANDMARK_HEAD_TOP := "head_top"
const LANDMARK_FLOOR_CONTACT := "floor_contact"
const HEIGHT_LANDMARK_ROLES: Array[String] = [LANDMARK_HEAD_TOP, LANDMARK_FLOOR_CONTACT]

## Role -> canonical bone names for this family, most canonical first. Alias
## spellings are NOT listed: they are derived, not enumerated.
const SEMANTIC_LANDMARKS := {
	LANDMARK_HEAD_TOP: ["head_end", "Head"],
	LANDMARK_FLOOR_CONTACT: [
		"LeftToeBase", "RightToeBase", "LeftToes", "RightToes", "LeftFoot", "RightFoot",
	],
}

## `head_top` is a single landmark (the first canonical name that resolves).
## `floor_contact` is a set: every resolved bone counts and the lowest one is
## the floor, so a rig that ships toes on one side only still measures.
const LANDMARK_SINGLE_ROLES: Array[String] = [LANDMARK_HEAD_TOP]


## Every height landmark role as it exists on THIS skeleton. Fails closed with
## the unresolved roles named, so "this rig spells its head bone differently"
## can never again be reported as "this rig has no height".
static func resolved_height_landmarks(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {
			"ok": false,
			"error_class": "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
			"detail": "no skeleton",
			"unresolved": HEIGHT_LANDMARK_ROLES.duplicate(),
			"roles": {},
		}
	var roles := {}
	var unresolved: Array[String] = []
	for role in HEIGHT_LANDMARK_ROLES:
		var found: Array[String] = []
		for canonical in (SEMANTIC_LANDMARKS[role] as Array):
			var resolved: String = _resolve_name(skeleton, str(canonical))
			if skeleton.find_bone(resolved) < 0 or resolved in found:
				continue
			found.append(resolved)
			if role in LANDMARK_SINGLE_ROLES:
				break
		if found.is_empty():
			unresolved.append(str(role))
		roles[role] = found
	if not unresolved.is_empty():
		return {
			"ok": false,
			"error_class": "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED",
			"detail": "unresolved landmark role(s): %s" % ", ".join(unresolved),
			"unresolved": unresolved,
			"roles": roles,
		}
	return {
		"ok": true,
		"roles": roles,
		"head_role": LANDMARK_HEAD_TOP,
		"floor_role": LANDMARK_FLOOR_CONTACT,
		"unresolved": unresolved,
	}
