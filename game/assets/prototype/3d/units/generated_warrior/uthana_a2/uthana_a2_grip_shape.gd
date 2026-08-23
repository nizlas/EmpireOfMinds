# Local melee_1h grip-segment shape from the normalized club mesh.
# Axis and elliptical radii are measured, never a global default radius alone.
extends RefCounted

const SEGMENT_HALF_DEFAULT := 0.028
const BAND_SAMPLES_MIN := 24


## After normalize: primary_grip at club origin, +Y toward active end.
## Samples in the parent (socket) metric space so radii match the scaled club.
static func derive_from_normalized_club(
	weapon_root: Node3D, segment_half: float = SEGMENT_HALF_DEFAULT
) -> Dictionary:
	if weapon_root == null:
		return {"ok": false, "reason": "null_weapon"}
	var parent: Node3D = weapon_root.get_parent() as Node3D
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var y_min := INF
	var y_max := -INF
	for node in weapon_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var world: Vector3 = mi.to_global(v)
				# Parent space == post-normalize socket metric (grip at origin, +Y shaft).
				var local: Vector3
				if parent != null:
					local = parent.to_local(world)
				else:
					local = weapon_root.transform * (mi.transform * v)
				if absf(local.y) > segment_half:
					continue
				xs.append(local.x)
				zs.append(local.z)
				y_min = minf(y_min, local.y)
				y_max = maxf(y_max, local.y)
	if xs.size() < BAND_SAMPLES_MIN:
		return {
			"ok": false,
			"reason": "grip_segment_undersampled",
			"sample_count": xs.size(),
		}
	var sum_x2 := 0.0
	var sum_z2 := 0.0
	var max_abs_x := 0.0
	var max_abs_z := 0.0
	for i in xs.size():
		var x: float = xs[i]
		var z: float = zs[i]
		sum_x2 += x * x
		sum_z2 += z * z
		max_abs_x = maxf(max_abs_x, absf(x))
		max_abs_z = maxf(max_abs_z, absf(z))
	var n: float = float(xs.size())
	var rms_x: float = sqrt(sum_x2 / n)
	var rms_z: float = sqrt(sum_z2 / n)
	# Use a blend of RMS and peak so thin handles are not overestimated.
	var radius_x: float = 0.65 * rms_x + 0.35 * max_abs_x
	var radius_z: float = 0.65 * rms_z + 0.35 * max_abs_z
	var radius_mean: float = 0.5 * (radius_x + radius_z)
	return {
		"ok": true,
		"axis_origin_local": Vector3.ZERO,
		"axis_dir_local": Vector3.UP,
		"segment_half": segment_half,
		"segment_length": y_max - y_min if y_max > y_min else segment_half * 2.0,
		"radius_x": radius_x,
		"radius_z": radius_z,
		"radius_mean": radius_mean,
		"rms_x": rms_x,
		"rms_z": rms_z,
		"sample_count": xs.size(),
		"contact_model": "elliptical_cylinder",
	}


## Point on the elliptical cross-section in club-local XZ at angle (0 = +X).
static func ellipse_point(radius_x: float, radius_z: float, angle_rad: float) -> Vector3:
	return Vector3(cos(angle_rad) * radius_x, 0.0, sin(angle_rad) * radius_z)


## Signed radial gap from a club-local point to the ellipse surface.
## Positive = outside, negative = penetrating.
static func signed_gap_local(p: Vector3, radius_x: float, radius_z: float) -> float:
	var rx: float = maxf(radius_x, 1e-6)
	var rz: float = maxf(radius_z, 1e-6)
	var radial := Vector2(p.x, p.z)
	if radial.length_squared() < 1e-12:
		return -minf(rx, rz)
	var ang: float = atan2(p.z, p.x)
	var surface: Vector2 = Vector2(cos(ang) * rx, sin(ang) * rz)
	return radial.length() - surface.length()
