# A2 compatibility shell (A2.9): the melee_1h compiler/normalizer is owned
# by res://presentation/equipment/melee_1h_normalize.gd. This shell only
# owns the A2 demo weapon SELECTION (which club asset to load) and keeps
# the legacy static API for the accepted A2.7 path and its tests.
extends RefCounted

const Impl = preload("res://presentation/equipment/melee_1h_normalize.gd")

const INTERACTION_PROFILE := Impl.INTERACTION_PROFILE
const OWNER_HAND := Impl.OWNER_HAND
const CLUB_GLB_PATH := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const MIN_MARKER_CONFIDENCE := Impl.MIN_MARKER_CONFIDENCE
const GRIP_RADIUS_HEIGHT_MIN := Impl.GRIP_RADIUS_HEIGHT_MIN
const GRIP_RADIUS_HEIGHT_MAX := Impl.GRIP_RADIUS_HEIGHT_MAX
const LENGTH_ENVELOPE_FRAC := Impl.LENGTH_ENVELOPE_FRAC


static func club_source_path() -> String:
	return CLUB_GLB_PATH


static func inspect_geometry(weapon_root: Node3D) -> Dictionary:
	var out: Dictionary = Impl.inspect_geometry(weapon_root)
	if bool(out.get("ok", false)):
		out["source_path"] = CLUB_GLB_PATH
	return out


static func cross_section_rms_radius(
	weapon_root: Node3D, axis: int, axis_coord: float, band: float
) -> Dictionary:
	return Impl.cross_section_rms_radius(weapon_root, axis, axis_coord, band)


static func analyze(weapon_root: Node3D, target_length: float) -> Dictionary:
	var out: Dictionary = Impl.analyze(weapon_root, target_length)
	if out.has("geometry") and bool((out["geometry"] as Dictionary).get("ok", false)):
		(out["geometry"] as Dictionary)["source_path"] = CLUB_GLB_PATH
	return out


static func apply_normalize(weapon_root: Node3D, analysis: Dictionary) -> Dictionary:
	return Impl.apply_normalize(weapon_root, analysis)


static func build_marker_metadata(analysis: Dictionary, humanoid_height: float) -> Dictionary:
	return Impl.build_marker_metadata(analysis, humanoid_height)


static func validate_envelope(analysis: Dictionary, humanoid_height: float) -> Dictionary:
	return Impl.validate_envelope(analysis, humanoid_height)
