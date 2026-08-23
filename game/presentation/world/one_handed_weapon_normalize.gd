# Canonical one-handed weapon normalization (EoM One-Handed Weapon Reference v1).
# Grip end → canonical −Y, head → +Y, reference front → +Z. Pure geometry math;
# target length is supplied by the caller (humanoid_height × profile ratio).
extends RefCounted

const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const ENV_DEBUG: String = "EOM_WEAPON_NORMALIZE_DEBUG"


static func debug_enabled() -> bool:
	return OS.get_environment(ENV_DEBUG).strip_edges() == "1"


static func primary_grip_fraction() -> float:
	return Profile.PRIMARY_GRIP_FRACTION


## Combined vertex AABB in `weapon_root` local space (requires nodes in tree).
static func compute_vertex_bounds(weapon_root: Node3D) -> Dictionary:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var count := 0
	var root_inv: Transform3D = weapon_root.global_transform.affine_inverse()
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
				var local: Vector3 = root_inv * (mi.global_transform * v)
				min_v = min_v.min(local)
				max_v = max_v.max(local)
				count += 1
	if count == 0:
		return {}
	return {
		"min": min_v,
		"max": max_v,
		"size": max_v - min_v,
		"center": (min_v + max_v) * 0.5,
		"count": count,
	}


## Returns axis index 0/1/2 for X/Y/Z with the largest extent.
static func principal_axis_index(size: Vector3) -> int:
	if size.x >= size.y and size.x >= size.z:
		return 0
	if size.y >= size.z:
		return 1
	return 2


static func _axis_vector(axis: int) -> Vector3:
	match axis:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK  # +Z


## Build orthonormal Basis: +Y = length_dir (unit), +Z = front (unit, ortho), +X = Y×Z.
static func basis_from_length_and_front(length_dir: Vector3, front_hint: Vector3) -> Basis:
	var y_axis: Vector3 = length_dir.normalized()
	var z_axis: Vector3 = front_hint - y_axis * front_hint.dot(y_axis)
	if z_axis.length_squared() < 1e-10:
		z_axis = y_axis.cross(Vector3.RIGHT)
		if z_axis.length_squared() < 1e-10:
			z_axis = y_axis.cross(Vector3.FORWARD)
	z_axis = z_axis.normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


## Inspect + compute normalization. Does not mutate the instance.
## `target_length` must be the desired geometric length after normalize
## (typically humanoid_height * TARGET_LENGTH_RATIO).
static func analyze(weapon_root: Node3D, target_length: float) -> Dictionary:
	var bounds: Dictionary = compute_vertex_bounds(weapon_root)
	if bounds.is_empty():
		return {"ok": false, "reason": "no_vertices"}
	if target_length < 1e-6:
		return {"ok": false, "reason": "degenerate_target_length"}
	var size: Vector3 = bounds["size"]
	var bmin: Vector3 = bounds["min"]
	var axis: int = principal_axis_index(size)
	var length: float = size[axis]
	if length < 1e-6:
		return {"ok": false, "reason": "degenerate_length"}
	var lower := Vector3(bounds["center"])
	var upper := Vector3(bounds["center"])
	lower[axis] = bmin[axis]
	upper[axis] = bmin[axis] + length
	var length_dir: Vector3 = (upper - lower).normalized()
	var front_hint := Vector3.BACK  # Godot +Z
	if absf(length_dir.dot(front_hint)) > 0.95:
		front_hint = Vector3.RIGHT
	var authored_to_canonical: Basis = basis_from_length_and_front(length_dir, front_hint)
	var grip_frac: float = Profile.PRIMARY_GRIP_FRACTION
	var grip: Vector3 = lower.lerp(upper, grip_frac)
	var scale: float = target_length / length
	return {
		"ok": true,
		"principal_axis": axis,
		"principal_axis_name": ["X", "Y", "Z"][axis],
		"lower": lower,
		"upper": upper,
		"grip": grip,
		"length": length,
		"scale": scale,
		"target_length": target_length,
		"grip_fraction": grip_frac,
		"length_dir": length_dir,
		"front_dir": authored_to_canonical.z,
		"normalize_basis": authored_to_canonical,
		"bounds": bounds,
	}


## Apply normalize: grip at parent origin, +Y toward head, +Z front, scaled
## to analysis.target_length.
static func apply_normalize(weapon_root: Node3D, analysis: Dictionary) -> Dictionary:
	if not bool(analysis.get("ok", false)):
		return analysis
	var basis: Basis = analysis["normalize_basis"]
	var grip: Vector3 = analysis["grip"]
	var scale: float = float(analysis["scale"])
	var rinv: Basis = basis.inverse()
	weapon_root.transform = Transform3D(rinv * scale, rinv * (-grip) * scale)
	return analysis


static func log_analysis_once(analysis: Dictionary, label: String = "one_handed_club") -> void:
	if not debug_enabled():
		return
	if not bool(analysis.get("ok", false)):
		print("weapon_normalize[%s]: FAILED %s" % [label, analysis.get("reason", "")])
		return
	print(
		(
			"weapon_normalize[%s]: axis=%s length=%.4f→%.4f scale=%.4f "
			+ "lower=%s upper=%s grip=%s (frac=%.2f) front=%s"
		)
		% [
			label,
			analysis["principal_axis_name"],
			analysis["length"],
			analysis["target_length"],
			analysis["scale"],
			analysis["lower"],
			analysis["upper"],
			analysis["grip"],
			analysis["grip_fraction"],
			analysis["front_dir"],
		]
	)
