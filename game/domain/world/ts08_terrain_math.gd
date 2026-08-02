# TS-08 terrain construction math (domain-only, no scene tree).
# Mirrors accepted Python helpers in tools/blender/terrain/eom_terrain_math_core.py
# for Stage-0 cut-lattice topology. Spec: docs/TERRAIN_SURFACE_TARGET.md
#
# All construction math uses scalar float (64-bit) until pos_key rounding. Avoid
# Vector2 arithmetic for authoritative coordinates — Vector2 stores 32-bit floats
# and breaks corner merging parity with Python round(x, 6).
class_name Ts08TerrainMath
extends RefCounted

const DEFAULT_HEX_RADIUS := 1.0
const DEFAULT_SURFACE_SUBDIVISIONS := 12
const POS_KEY_PRECISION := 6
const SQRT3 := 1.7320508075688772

const NEIGHBOR_DELTAS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func pos_key(x: float, y: float) -> Vector2:
	# Match Python eom_terrain_math_core.pos_key: round(x, precision).
	var parts := pos_key_parts(x, y)
	return Vector2(parts[0], parts[1])


static func pos_key_parts(x: float, y: float) -> Array:
	var scale := pow(10.0, POS_KEY_PRECISION)
	return [round(x * scale) / scale, round(y * scale) / scale]


static func pos_key_id(x: float, y: float) -> String:
	var parts: Array = pos_key_parts(x, y)
	return "%.*f|%.*f" % [POS_KEY_PRECISION, parts[0], POS_KEY_PRECISION, parts[1]]


static func pos_key_from_id(key_id: String) -> Vector2:
	var parts: PackedStringArray = key_id.split("|")
	return Vector2(float(parts[0]), float(parts[1]))


static func pos_key_from_xy(plane_xy: Vector2) -> Vector2:
	return pos_key(plane_xy.x, plane_xy.y)


static func positive_mod(value: int, modulo: int) -> int:
	return ((value % modulo) + modulo) % modulo


static func handdrawn_to_baseline_axial(q: int, r: int) -> Vector2i:
	return Vector2i(q + r, -r)


static func axial_to_world_x(q: int, r: int, radius: float = DEFAULT_HEX_RADIUS) -> float:
	return radius * SQRT3 * (float(q) + float(r) * 0.5)


static func axial_to_world_y(q: int, r: int, radius: float = DEFAULT_HEX_RADIUS) -> float:
	return radius * 1.5 * float(r)


static func axial_to_world_xy(q: int, r: int, radius: float = DEFAULT_HEX_RADIUS) -> Vector2:
	return Vector2(axial_to_world_x(q, r, radius), axial_to_world_y(q, r, radius))


static func handdrawn_center_world_xy(q: int, r: int, radius: float = DEFAULT_HEX_RADIUS) -> Vector2:
	var baseline := handdrawn_to_baseline_axial(q, r)
	return axial_to_world_xy(baseline.x, baseline.y, radius)


static func corner_xy_local_x(corner_index: int, radius: float = DEFAULT_HEX_RADIUS) -> float:
	var angle_rad := deg_to_rad(60.0 * float(corner_index) + 30.0)
	return radius * cos(angle_rad)


static func corner_xy_local_y(corner_index: int, radius: float = DEFAULT_HEX_RADIUS) -> float:
	var angle_rad := deg_to_rad(60.0 * float(corner_index) + 30.0)
	return radius * sin(angle_rad)


static func corner_xy_local(corner_index: int, radius: float = DEFAULT_HEX_RADIUS) -> Vector2:
	return Vector2(corner_xy_local_x(corner_index, radius), corner_xy_local_y(corner_index, radius))


static func handdrawn_corner_world_xy(
	q: int,
	r: int,
	corner_index: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> Vector2:
	var wx := handdrawn_corner_world_x(q, r, corner_index, radius)
	var wy := handdrawn_corner_world_y(q, r, corner_index, radius)
	return Vector2(wx, wy)


static func handdrawn_corner_world_x(
	q: int,
	r: int,
	corner_index: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> float:
	var baseline := handdrawn_to_baseline_axial(q, r)
	return (
		axial_to_world_x(baseline.x, baseline.y, radius)
		+ corner_xy_local_x(corner_index, radius)
	)


static func handdrawn_corner_world_y(
	q: int,
	r: int,
	corner_index: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> float:
	var baseline := handdrawn_to_baseline_axial(q, r)
	return (
		axial_to_world_y(baseline.x, baseline.y, radius)
		+ corner_xy_local_y(corner_index, radius)
	)


static func plane_xy_to_godot_xz(plane_xy: Vector2) -> Vector2:
	return Vector2(plane_xy.x, -plane_xy.y)


static func sector_barycentric_xy(
	sector: int,
	si: int,
	sj: int,
	subdiv: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> Vector2:
	var lx := sector_barycentric_x(sector, si, sj, subdiv, radius)
	var ly := sector_barycentric_y(sector, si, sj, subdiv, radius)
	return Vector2(lx, ly)


static func sector_barycentric_x(
	sector: int,
	si: int,
	sj: int,
	subdiv: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> float:
	var ci := sector
	var cj := positive_mod(sector + 1, 6)
	var denom := float(subdiv)
	var wb := float(si) / denom
	var wc := float(sj) / denom
	return wb * corner_xy_local_x(ci, radius) + wc * corner_xy_local_x(cj, radius)


static func sector_barycentric_y(
	sector: int,
	si: int,
	sj: int,
	subdiv: int,
	radius: float = DEFAULT_HEX_RADIUS
) -> float:
	var ci := sector
	var cj := positive_mod(sector + 1, 6)
	var denom := float(subdiv)
	var wb := float(si) / denom
	var wc := float(sj) / denom
	return wb * corner_xy_local_y(ci, radius) + wc * corner_xy_local_y(cj, radius)


static func canonical_center_world_y(
	elevation: int,
	elevation_step: float,
	elevation_base: int
) -> float:
	return (float(elevation) - float(elevation_base)) * elevation_step


static func compare_tile_coords(a: Vector2i, b: Vector2i) -> int:
	if a.x != b.x:
		return -1 if a.x < b.x else 1
	if a.y != b.y:
		return -1 if a.y < b.y else 1
	return 0


static func sorted_tile_pair(a: Vector2i, b: Vector2i) -> Array:
	if compare_tile_coords(a, b) <= 0:
		return [a, b]
	return [b, a]


static func cliff_pair_key(a: Vector2i, b: Vector2i) -> String:
	var pair := sorted_tile_pair(a, b)
	return "%d,%d|%d,%d" % [pair[0].x, pair[0].y, pair[1].x, pair[1].y]
