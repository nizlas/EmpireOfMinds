# Grip geometry independent of a specific hand. First implemented shape:
# elliptical/circular cylinder suitable for clubs, swords, axes and similar
# handles. Extensible by contact_model without implementing every future
# shape now.
extends RefCounted

const GripShape = preload("res://presentation/equipment/melee_grip_shape.gd")
const Melee1h = preload("res://presentation/equipment/melee_1h_normalize.gd")
const LengthProfile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const POLICY_POWER_GRIP_1H := "power_grip_1h_v1"

var ok: bool = false
var interaction_profile: String = POLICY_POWER_GRIP_1H
var owner_hand: String = "right"
var contact_model: String = "elliptical_cylinder"
var primary_grip: Transform3D = Transform3D.IDENTITY
var secondary_grip: Variant = null
var shaft_axis: Vector3 = Vector3.UP
var radius_x: float = 0.0
var radius_z: float = 0.0
var radius_mean: float = 0.0
var axial_extent: float = 0.0
var head_side: String = "radial"
var analysis: Dictionary = {}
var shape: Dictionary = {}
var metadata: Dictionary = {}
var failures: Array[String] = []


static func from_normalized_melee(
	weapon_root: Node3D, humanoid_height: float, owner_hand_in: String = "right"
) -> Dictionary:
	var geo := new()
	return geo._from_normalized_melee(weapon_root, humanoid_height, owner_hand_in)


func _from_normalized_melee(
	weapon_root: Node3D, humanoid_height: float, owner_hand_in: String
) -> Dictionary:
	owner_hand = "left" if owner_hand_in == "left" else "right"
	interaction_profile = POLICY_POWER_GRIP_1H
	if weapon_root == null:
		failures.append("GRIP_GEOM_NO_WEAPON")
		return _result()
	var target_length: float = humanoid_height * LengthProfile.TARGET_LENGTH_RATIO
	analysis = Melee1h.analyze(weapon_root, target_length)
	if not bool(analysis.get("ok", false)):
		failures.append(str(analysis.get("error_class", "NORMALIZE_FAILED")))
		return _result()
	Melee1h.apply_normalize(weapon_root, analysis)
	shape = GripShape.derive_from_normalized_club(weapon_root)
	if not bool(shape.get("ok", false)):
		failures.append("GRIP_SHAPE_FAILED")
		return _result()
	metadata = Melee1h.build_marker_metadata(analysis, humanoid_height)
	metadata["grip_shape"] = shape
	var envelope: Dictionary = Melee1h.validate_envelope(analysis, humanoid_height)
	if not bool(envelope.get("ok", false)):
		failures.append("ENVELOPE_FAILED")
		return _result()
	radius_x = float(shape.get("radius_x", 0.0))
	radius_z = float(shape.get("radius_z", 0.0))
	radius_mean = float(shape.get("radius_mean", 0.0))
	axial_extent = float(shape.get("segment_length", 0.0))
	shaft_axis = Vector3.UP
	head_side = str(metadata.get("head_side", LengthProfile.MELEE_1H_HEAD_SIDE))
	contact_model = str(shape.get("contact_model", "elliptical_cylinder"))
	primary_grip = Transform3D.IDENTITY
	secondary_grip = null
	ok = failures.is_empty()
	return _result()


func _result() -> Dictionary:
	return {
		"ok": ok,
		"geometry": self,
		"interaction_profile": interaction_profile,
		"owner_hand": owner_hand,
		"contact_model": contact_model,
		"primary_grip": primary_grip,
		"secondary_grip": secondary_grip,
		"shaft_axis": shaft_axis,
		"radius_x": radius_x,
		"radius_z": radius_z,
		"radius_mean": radius_mean,
		"axial_extent": axial_extent,
		"head_side": head_side,
		"analysis": analysis,
		"shape": shape,
		"metadata": metadata,
		"failures": failures,
	}
