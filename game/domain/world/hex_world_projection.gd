# Pure domain math: canonical axial (q,r) to Godot world embedding.
# Spec: docs/WORLD_COORDINATES.md — no scene tree or rendering dependencies.
class_name HexWorldProjection
extends RefCounted

const S := 1.0
const SQRT3 := 1.7320508075688772

const DEFAULT_ELEVATION_BASE := 1


static func axial_to_world_xz(q: int, r: int) -> Vector2:
	return Vector2(
		S * SQRT3 * (float(q) + float(r) * 0.5),
		S * 1.5 * float(r)
	)


static func world_xz_to_fractional_axial(world_x: float, world_z: float) -> Vector2:
	var inv_s := 1.0 / S
	return Vector2(
		(SQRT3 / 3.0 * world_x - 1.0 / 3.0 * world_z) * inv_s,
		(2.0 / 3.0 * world_z) * inv_s
	)


static func cube_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var rq := int(roundi(qf))
	var rr := int(roundi(rf))
	var rs := int(roundi(sf))
	var q_diff := absf(rq - qf)
	var r_diff := absf(rr - rf)
	var s_diff := absf(rs - sf)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	else:
		rs = -rq - rr
	return Vector2i(rq, rr)


static func world_xz_to_axial(world_x: float, world_z: float) -> Vector2i:
	var frac := world_xz_to_fractional_axial(world_x, world_z)
	return cube_round(frac.x, frac.y)


static func elevation_to_world_y(elevation: int, elevation_step: float, elevation_base: int = DEFAULT_ELEVATION_BASE) -> float:
	return (float(elevation) - float(elevation_base)) * elevation_step


static func tile_center_world(q: int, r: int, elevation: int, elevation_step: float, elevation_base: int = DEFAULT_ELEVATION_BASE) -> Vector3:
	var xz := axial_to_world_xz(q, r)
	var y := elevation_to_world_y(elevation, elevation_step, elevation_base)
	return Vector3(xz.x, y, xz.y)


static func tile_anchor_world(q: int, r: int, elevation: int, elevation_step: float, elevation_base: int = DEFAULT_ELEVATION_BASE) -> Vector3:
	return tile_center_world(q, r, elevation, elevation_step, elevation_base)


static func corner_offsets_xz() -> Array[Vector2]:
	var corners: Array[Vector2] = []
	for k in range(6):
		var theta_deg := 30.0 + 60.0 * float(k)
		var theta := deg_to_rad(theta_deg)
		corners.append(Vector2(S * cos(theta), -S * sin(theta)))
	return corners
