# A2 compatibility shell (A2.9): grip-segment shape math is owned by
# res://presentation/equipment/melee_grip_shape.gd. Kept for the accepted
# A2.7 path and its tests.
extends RefCounted

const Impl = preload("res://presentation/equipment/melee_grip_shape.gd")

const SEGMENT_HALF_DEFAULT := Impl.SEGMENT_HALF_DEFAULT
const BAND_SAMPLES_MIN := Impl.BAND_SAMPLES_MIN


static func derive_from_normalized_club(
	weapon_root: Node3D, segment_half: float = SEGMENT_HALF_DEFAULT
) -> Dictionary:
	return Impl.derive_from_normalized_club(weapon_root, segment_half)


static func ellipse_point(radius_x: float, radius_z: float, angle_rad: float) -> Vector3:
	return Impl.ellipse_point(radius_x, radius_z, angle_rad)


static func signed_gap_local(p: Vector3, radius_x: float, radius_z: float) -> float:
	return Impl.signed_gap_local(p, radius_x, radius_z)
