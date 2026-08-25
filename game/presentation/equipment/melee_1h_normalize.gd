# Generic melee_1h weapon compiler / normalizer (A2.9 owner; the A2 file is
# a compatibility shell). Dual grip-end hypotheses scored from geometry —
# never filename-only, never a handwritten transform for one weapon or one
# warrior. Weapon SELECTION (which asset to load) is never made here.
extends RefCounted

const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")
const OneHandedWeaponNormalize = preload(
	"res://presentation/world/one_handed_weapon_normalize.gd"
)

const INTERACTION_PROFILE := "melee_1h"
const OWNER_HAND := "right"

## Fail closed below this combined confidence (0..1).
const MIN_MARKER_CONFIDENCE := 0.55
## Grip radius as fraction of humanoid height must stay inside this band.
const GRIP_RADIUS_HEIGHT_MIN := 0.004
const GRIP_RADIUS_HEIGHT_MAX := 0.06
## Normalized length must stay near the profile envelope (±fraction).
const LENGTH_ENVELOPE_FRAC := 0.20


## Inspect mesh geometry of an already-instanced weapon root (tree-attached).
static func inspect_geometry(weapon_root: Node3D) -> Dictionary:
	var mesh_count := 0
	var verts := 0
	var tris := 0
	var materials := 0
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var root_inv: Transform3D = weapon_root.global_transform.affine_inverse()
	for node in weapon_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		mesh_count += 1
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var varr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			verts += varr.size()
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				tris += int(idx.size() / 3)
			else:
				tris += int(varr.size() / 3)
			if mi.mesh.surface_get_material(si) != null or mi.get_active_material(si) != null:
				materials += 1
			for v in varr:
				var local: Vector3 = root_inv * (mi.global_transform * v)
				min_v = min_v.min(local)
				max_v = max_v.max(local)
	if mesh_count == 0 or verts == 0:
		return {"ok": false, "reason": "no_mesh_geometry"}
	var size: Vector3 = max_v - min_v
	var axis: int = OneHandedWeaponNormalize.principal_axis_index(size)
	return {
		"ok": true,
		"source_path": "",
		"mesh_count": mesh_count,
		"vertex_count": verts,
		"triangle_count": tris,
		"material_count": materials,
		"bounds_min": min_v,
		"bounds_max": max_v,
		"bounds_size": size,
		"origin": weapon_root.transform.origin,
		"basis_determinant": weapon_root.transform.basis.determinant(),
		"principal_axis": axis,
		"principal_axis_name": ["X", "Y", "Z"][axis],
		"principal_length": size[axis],
		"handedness_det": weapon_root.transform.basis.determinant(),
	}


## RMS radius of vertices near a point along the principal axis.
static func cross_section_rms_radius(
	weapon_root: Node3D, axis: int, axis_coord: float, band: float
) -> Dictionary:
	var sum_r2 := 0.0
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
			var varr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in varr:
				var local: Vector3 = root_inv * (mi.global_transform * v)
				if absf(local[axis] - axis_coord) > band:
					continue
				var r2 := 0.0
				for c in 3:
					if c == axis:
						continue
					r2 += local[c] * local[c]
				sum_r2 += r2
				count += 1
	if count < 8:
		return {"ok": false, "count": count, "radius": 0.0}
	return {"ok": true, "count": count, "radius": sqrt(sum_r2 / float(count))}


static func _score_grip_hypothesis(
	weapon_root: Node3D,
	axis: int,
	grip_end: Vector3,
	head_end: Vector3,
	length: float
) -> Dictionary:
	## Heuristics (reported explicitly):
	## 1) narrower_end — generation convention: grip is the thinner handle end
	## 2) end_radius_ratio — head_rms / grip_rms
	## 3) mid_handle_thin — mid-handle thinner than head (club shape)
	var band: float = maxf(length * 0.045, 0.012)
	var grip_sample: float = grip_end[axis] + (head_end[axis] - grip_end[axis]) * 0.08
	var head_sample: float = grip_end[axis] + (head_end[axis] - grip_end[axis]) * 0.92
	var mid_sample: float = grip_end[axis] + (head_end[axis] - grip_end[axis]) * 0.45
	var grip_cs: Dictionary = cross_section_rms_radius(weapon_root, axis, grip_sample, band)
	var head_cs: Dictionary = cross_section_rms_radius(weapon_root, axis, head_sample, band)
	var mid_cs: Dictionary = cross_section_rms_radius(weapon_root, axis, mid_sample, band)
	if not bool(grip_cs.get("ok", false)) or not bool(head_cs.get("ok", false)):
		return {
			"ok": false,
			"reason": "cross_section_undersampled",
			"score": 0.0,
			"confidence": 0.0,
			"heuristics": ["cross_section_undersampled"],
		}
	var rg: float = float(grip_cs["radius"])
	var rh: float = float(head_cs["radius"])
	var rm: float = float(mid_cs.get("radius", rg))
	var narrower: float = 0.0
	if rh > rg + 1e-6:
		narrower = clampf((rh - rg) / maxf(rh, 1e-6), 0.0, 1.0)
	elif rg > rh + 1e-6:
		narrower = -clampf((rg - rh) / maxf(rg, 1e-6), 0.0, 1.0)
	var ratio: float = rh / maxf(rg, 1e-6)
	var ratio_term: float = clampf((ratio - 1.0) / 1.5, -1.0, 1.0)
	var mid_term := 0.0
	if bool(mid_cs.get("ok", false)) and rh > 1e-6:
		mid_term = clampf((rh - rm) / rh, -1.0, 1.0)
	# Weighted score in [-1, 1]; positive favors this grip-end choice.
	var score: float = 0.55 * narrower + 0.30 * ratio_term + 0.15 * mid_term
	var confidence: float = clampf(0.5 + 0.5 * score, 0.0, 1.0)
	return {
		"ok": true,
		"score": score,
		"confidence": confidence,
		"grip_radius_rms": rg,
		"head_radius_rms": rh,
		"mid_radius_rms": rm,
		"end_radius_ratio": ratio,
		"heuristics": [
			"narrower_end_is_grip",
			"end_radius_ratio",
			"mid_handle_vs_head",
			"generation_convention_thin_handle",
		],
		"grip_sample_axis": grip_sample,
		"head_sample_axis": head_sample,
	}


## Analyze + score both grip-end directions. Does not mutate the instance.
## `target_length` = desired geometric length (humanoid_height * profile ratio).
static func analyze(weapon_root: Node3D, target_length: float) -> Dictionary:
	var geom: Dictionary = inspect_geometry(weapon_root)
	if not bool(geom.get("ok", false)):
		return {"ok": false, "reason": geom.get("reason", "geometry_failed"), "geometry": geom}
	if target_length < 1e-6:
		return {"ok": false, "reason": "degenerate_target_length", "geometry": geom}

	var bounds: Dictionary = OneHandedWeaponNormalize.compute_vertex_bounds(weapon_root)
	if bounds.is_empty():
		return {"ok": false, "reason": "no_vertices", "geometry": geom}
	var size: Vector3 = bounds["size"]
	var bmin: Vector3 = bounds["min"]
	var axis: int = OneHandedWeaponNormalize.principal_axis_index(size)
	var length: float = size[axis]
	if length < 1e-6:
		return {"ok": false, "reason": "degenerate_length", "geometry": geom}

	# Axis dominance confidence: how clearly one axis is longest.
	var extents: Array[float] = [size.x, size.y, size.z]
	extents.sort()
	var axis_clarity: float = 0.0
	if extents[1] > 1e-6:
		axis_clarity = clampf((extents[2] / extents[1]) - 1.0, 0.0, 1.0)
	else:
		axis_clarity = 1.0

	var end_a := Vector3(bounds["center"])
	var end_b := Vector3(bounds["center"])
	end_a[axis] = bmin[axis]
	end_b[axis] = bmin[axis] + length

	var hyp_a: Dictionary = _score_grip_hypothesis(weapon_root, axis, end_a, end_b, length)
	hyp_a["name"] = "grip_at_lower_end"
	hyp_a["grip_end"] = end_a
	hyp_a["active_end"] = end_b

	var hyp_b: Dictionary = _score_grip_hypothesis(weapon_root, axis, end_b, end_a, length)
	hyp_b["name"] = "grip_at_upper_end"
	hyp_b["grip_end"] = end_b
	hyp_b["active_end"] = end_a

	if not bool(hyp_a.get("ok", false)) and not bool(hyp_b.get("ok", false)):
		return {
			"ok": false,
			"reason": "both_hypotheses_failed",
			"geometry": geom,
			"hypothesis_a": hyp_a,
			"hypothesis_b": hyp_b,
		}

	var chosen: Dictionary = hyp_a
	var other: Dictionary = hyp_b
	if float(hyp_b.get("score", -INF)) > float(hyp_a.get("score", -INF)):
		chosen = hyp_b
		other = hyp_a

	var margin: float = float(chosen.get("score", 0.0)) - float(other.get("score", 0.0))
	var margin_conf: float = clampf(margin / 0.75, 0.0, 1.0)
	var marker_confidence: float = clampf(
		0.40 * float(chosen.get("confidence", 0.0))
		+ 0.35 * margin_conf
		+ 0.25 * axis_clarity,
		0.0,
		1.0
	)

	if marker_confidence < MIN_MARKER_CONFIDENCE:
		return {
			"ok": false,
			"reason": "insufficient_grip_end_confidence",
			"error_class": "MARKER_CONFIDENCE_TOO_LOW",
			"marker_confidence": marker_confidence,
			"min_required": MIN_MARKER_CONFIDENCE,
			"geometry": geom,
			"hypothesis_a": hyp_a,
			"hypothesis_b": hyp_b,
			"chosen_hypothesis": chosen.get("name", ""),
			"score_margin": margin,
		}

	var grip_end: Vector3 = chosen["grip_end"]
	var active_end: Vector3 = chosen["active_end"]
	var length_dir: Vector3 = (active_end - grip_end).normalized()
	var front_hint := Vector3.BACK
	if absf(length_dir.dot(front_hint)) > 0.95:
		front_hint = Vector3.RIGHT
	var normalize_basis: Basis = OneHandedWeaponNormalize.basis_from_length_and_front(
		length_dir, front_hint
	)
	# Orthonormal check: forward = length (+Y), up = front (+Z).
	var forward_axis: Vector3 = length_dir
	var up_axis: Vector3 = normalize_basis.z
	var right_axis: Vector3 = normalize_basis.x
	var det: float = Basis(right_axis, forward_axis, up_axis).determinant()

	var grip_frac: float = Profile.PRIMARY_GRIP_FRACTION
	var primary_grip: Vector3 = grip_end.lerp(active_end, grip_frac)
	var grip_radius: float = float(chosen.get("grip_radius_rms", 0.0))
	var scale: float = target_length / length

	# Sample radius at the actual primary_grip station for metadata.
	var grip_axis_coord: float = primary_grip[axis]
	var grip_at: Dictionary = cross_section_rms_radius(
		weapon_root, axis, grip_axis_coord, maxf(length * 0.04, 0.01)
	)
	if bool(grip_at.get("ok", false)):
		grip_radius = float(grip_at["radius"])

	return {
		"ok": true,
		"interaction_profile": INTERACTION_PROFILE,
		"owner_hand": OWNER_HAND,
		"geometry": geom,
		"principal_axis": axis,
		"principal_axis_name": ["X", "Y", "Z"][axis],
		"axis_clarity": axis_clarity,
		"length": length,
		"target_length": target_length,
		"normalize_scale": scale,
		"grip_fraction": grip_frac,
		"grip_end": grip_end,
		"active_end": active_end,
		"primary_grip": primary_grip,
		"forward_axis": forward_axis,
		"up_axis": up_axis,
		"right_axis": right_axis,
		"basis_determinant": det,
		"grip_radius": grip_radius,
		"marker_confidence": marker_confidence,
		"score_margin": margin,
		"hypothesis_a": hyp_a,
		"hypothesis_b": hyp_b,
		"chosen_hypothesis": chosen.get("name", ""),
		"chosen_heuristics": chosen.get("heuristics", []),
		"normalize_basis": normalize_basis,
		"bounds": bounds,
		"length_dir": length_dir,
		"front_dir": up_axis,
	}


## Apply canonical normalize: primary_grip → parent origin, +Y toward active end.
static func apply_normalize(weapon_root: Node3D, analysis: Dictionary) -> Dictionary:
	if not bool(analysis.get("ok", false)):
		return analysis
	var basis: Basis = analysis["normalize_basis"]
	var grip: Vector3 = analysis["primary_grip"]
	var scale: float = float(analysis["normalize_scale"])
	var rinv: Basis = basis.inverse()
	weapon_root.transform = Transform3D(rinv * scale, rinv * (-grip) * scale)
	analysis["applied"] = true
	return analysis


static func build_marker_metadata(analysis: Dictionary, humanoid_height: float) -> Dictionary:
	if not bool(analysis.get("ok", false)):
		return {
			"ok": false,
			"reason": analysis.get("reason", "analyze_failed"),
			"error_class": analysis.get("error_class", "ANALYZE_FAILED"),
		}
	var length: float = float(analysis.get("length", 0.0))
	var target: float = float(analysis.get("target_length", 0.0))
	var ratio: float = 0.0
	if humanoid_height > 1e-6:
		ratio = target / humanoid_height
	return {
		"ok": true,
		"interaction_profile": INTERACTION_PROFILE,
		"owner_hand": OWNER_HAND,
		"head_side": Profile.MELEE_1H_HEAD_SIDE,
		"primary_grip": analysis["primary_grip"],
		"forward_axis": analysis["forward_axis"],
		"up_axis": analysis["up_axis"],
		# Fully oriented grip frame after normalize: origin = primary_grip
		# (parent origin), +Y = shaft grip->head, +Z = section reference for
		# radius_z, +X = radius_x. det = +1 (validated in the envelope).
		"grip_frame": {
			"origin_local": Vector3.ZERO,
			"shaft_axis_local": Vector3.UP,
			"section_x_local": Vector3.RIGHT,
			"section_z_local": Vector3.BACK,
			"head_side": Profile.MELEE_1H_HEAD_SIDE,
		},
		"grip_radius": float(analysis["grip_radius"]),
		"marker_confidence": float(analysis["marker_confidence"]),
		"normalize_scale": float(analysis["normalize_scale"]),
		"authored_length": length,
		"normalized_length": target,
		"length_over_height": ratio,
		"target_length_ratio": Profile.TARGET_LENGTH_RATIO,
		"chosen_hypothesis": analysis.get("chosen_hypothesis", ""),
		"heuristics": analysis.get("chosen_heuristics", []),
		"basis_determinant": float(analysis.get("basis_determinant", 0.0)),
	}


static func validate_envelope(analysis: Dictionary, humanoid_height: float) -> Dictionary:
	if not bool(analysis.get("ok", false)):
		return {"ok": false, "reason": analysis.get("reason", "bad_analysis")}
	var target: float = float(analysis["target_length"])
	var expected: float = humanoid_height * Profile.TARGET_LENGTH_RATIO
	var len_err: float = absf(target - expected) / maxf(expected, 1e-6)
	if len_err > LENGTH_ENVELOPE_FRAC:
		return {
			"ok": false,
			"reason": "length_outside_melee_1h_envelope",
			"length_error_frac": len_err,
		}
	var grip_r: float = float(analysis["grip_radius"]) * float(analysis["normalize_scale"])
	var r_over_h: float = grip_r / maxf(humanoid_height, 1e-6)
	if r_over_h < GRIP_RADIUS_HEIGHT_MIN or r_over_h > GRIP_RADIUS_HEIGHT_MAX:
		return {
			"ok": false,
			"reason": "grip_radius_outside_range",
			"grip_radius_over_height": r_over_h,
		}
	var det: float = float(analysis.get("basis_determinant", 0.0))
	if det <= 0.0:
		return {"ok": false, "reason": "non_positive_basis_determinant", "det": det}
	var f: Vector3 = analysis["forward_axis"]
	var u: Vector3 = analysis["up_axis"]
	var r: Vector3 = analysis["right_axis"]
	if absf(f.dot(u)) > 0.05 or absf(f.dot(r)) > 0.05 or absf(u.dot(r)) > 0.05:
		return {"ok": false, "reason": "axes_not_orthogonal"}
	return {"ok": true, "length_error_frac": len_err, "grip_radius_over_height": r_over_h}
