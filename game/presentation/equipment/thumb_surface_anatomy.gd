# Independent anatomical validation of a compiled thumb nail/pad surface
# (A2.13b). ONE implementation, called at BOTH ends:
#
#   * the fixture compiler, on the patches it just selected, so a
#     misclassified surface never becomes evidence;
#   * the grip engine's patch bind, on the patches a CERTIFIED fixture claims,
#     so a self-consistent but anatomically wrong fixture is refused at
#     assembly even if it was minted somewhere else.
#
# WHY IT EXISTS. Until A2.13b the only checks on "is this the right surface"
# compared the fixture with ITSELF:
#
#   * the bind-time check `|nail_local · pad_local − rest_nail_pad_dot| > 0.15`
#     compares the fixture's own two normals against the fixture's own stored
#     dot product of them;
#   * the achieved-pose check `|nail_pad_dot − rest_nail_pad_dot| > 0.15`
#     compares the posed relation against the same stored value.
#
# Both are true statements about DEFORMATION DRIFT and neither is evidence that
# the compiler picked the nail and the pad. A surface classified onto the wrong
# side of the digit satisfies both perfectly, because it is consistent with
# itself. Those two checks are kept, and renamed for what they measure, but
# they are no longer the answer to "is this the right surface".
#
# WHAT MAKES THIS INDEPENDENT. Every verdict below is derived from information
# the chosen patch's own normals do not produce:
#
#   * the resolved hand and thumb chain, and this hand's own chirality;
#   * the longitudinal / radial / volar hand frame derived from that hand's own
#     bones;
#   * WHERE each patch sits - its centroid's offset from the digit's medial
#     axis, and its axial station along the digit;
#   * skin-weight dominance on the distal segment;
#   * the topological tip component the candidates came from;
#   * that the two patches occupy opposite sides and do not overlap.
#
# Patch planarity is the one metric read from the patch itself. It is included
# because a plate that is not a plate is not a plate regardless of where it
# sits, and it is never allowed to stand in for a side or a station verdict.
#
# NO ASSET KNOWLEDGE. No delivery name, triangle id, mesh hash, per-asset
# coordinate or per-representation branch appears here or may be added. Every
# length is expressed in the digit's own length and every direction in the
# hand's own frame, so the same humanoid delivered in any representation is
# judged identically.
extends RefCounted

const VALIDATION_ID := "thumb_surface_anatomy_v1"

## A patch centroid must sit CLEARLY on its own side of the digit's medial
## axis. Anatomically the nail and the volar pad are on opposite sides of the
## distal phalanx, so a correctly classified patch is nowhere near the axis.
const POSITION_SIDE_MIN := 0.20
## The two plates must be SEPARATED across the digit, and the pad must be the
## volar one. Both plates sit on the distal cap, so both centroids share the
## tip's own outward bulge and their absolute offsets are far from opposed --
## what distinguishes them is the direction FROM the nail TO the pad, which is
## the anatomically meaningful statement and is independent of either plate's
## reported normal.
const SEPARATION_VOLAR_MIN := 0.30
## The plates must actually be apart, not two names for one location. Measured
## across the digit in digit lengths.
const SEPARATION_MIN_DIGITS := 0.02
## Both plates belong to the DISTAL end of the digit. The station is measured
## along the digit's own axis from the DISTAL JOINT, in digit lengths, so it is
## derived entirely from the live rig: no candidate set, no stored span, and
## therefore nothing the fixture itself could shift. Station 0 is the distal
## joint and station -1 is the joint above it, so a plate whose area sits past
## the midpoint of the distal segment is not the tip cap - it is flesh carried
## by weight bleed off the segment above. A real volar pad does wrap slightly
## back past the joint, which is why the bound is not zero.
const DISTAL_STATION_MIN_DIGITS := -0.50
## Fraction of a patch's vertices that must be dominated by the DISTAL
## segment. A component that only touches the digit through weight bleed off
## the middle segment cannot reach this.
const DISTAL_VERTEX_FRAC_MIN := 0.50
## A plate's triangles must agree on a facing. Area-weighted mean dot against
## the patch's own aggregate normal.
const NORMAL_CONCENTRATION_MIN := 0.70


## `ctx` keys, all in the distal thumb bone's own rest frame:
##   volar, radial, nail_dir, thumb_axis : Vector3, from the resolved chain
##   digit_length                        : float, this digit's own length
##   nail, pad                           : patch dictionaries, each
##       centroid  : Vector3
##       normal    : Vector3, aggregate
##       keys       : Array[String]
##       triangles : Array of {centroid, normal, area, distal_verts, min_weight}
##
## Returns `{ok, validation_id, failures: [{class, detail}], metrics: {...}}`.
## Fail-closed: a context that cannot be evaluated is a failure, never a pass.
static func validate(ctx: Dictionary) -> Dictionary:
	var failures: Array = []
	var metrics := {"validation_id": VALIDATION_ID}
	var axis: Vector3 = _unit(ctx.get("thumb_axis", Vector3.ZERO))
	var volar: Vector3 = _unit(ctx.get("volar", Vector3.ZERO))
	var nail_dir: Vector3 = _unit(ctx.get("nail_dir", Vector3.ZERO))
	var digit_length: float = float(ctx.get("digit_length", 0.0))
	if (
		axis == Vector3.ZERO or volar == Vector3.ZERO or nail_dir == Vector3.ZERO
		or digit_length <= 0.0
	):
		return _refuse(
			"THUMB_ANATOMY_FRAME_UNDERIVABLE",
			"the resolved chain did not yield a usable digit frame",
			metrics
		)
	var nail: Dictionary = ctx.get("nail", {})
	var pad: Dictionary = ctx.get("pad", {})
	if nail.is_empty() or pad.is_empty():
		return _refuse(
			"THUMB_ANATOMY_PATCH_MISSING", "both plates are required", metrics
		)
	# 1/2. SIDE. Where the plate SITS, from its centroid's offset off the
	# digit's medial axis - not from the normal the plate reports.
	var nail_side: Vector3 = _side_direction(nail.get("centroid", Vector3.ZERO), axis)
	var pad_side: Vector3 = _side_direction(pad.get("centroid", Vector3.ZERO), axis)
	if nail_side == Vector3.ZERO or pad_side == Vector3.ZERO:
		return _refuse(
			"THUMB_ANATOMY_PATCH_ON_AXIS",
			"a plate's centroid sits on the digit's medial axis, so it has no side",
			metrics
		)
	var nail_dorsal: float = nail_side.dot(nail_dir)
	var pad_volar: float = pad_side.dot(volar)
	metrics["nail_position_dorsal_radial"] = nail_dorsal
	metrics["pad_position_volar"] = pad_volar
	metrics["nail_position_margin"] = nail_dorsal - POSITION_SIDE_MIN
	metrics["pad_position_margin"] = pad_volar - POSITION_SIDE_MIN
	if nail_dorsal < POSITION_SIDE_MIN:
		failures.append({
			"class": "NAIL_PATCH_NOT_DORSAL_RADIAL",
			"detail": "nail plate sits at %.4f along the dorsal-radial bisector, below %.2f"
				% [nail_dorsal, POSITION_SIDE_MIN],
		})
	if pad_volar < POSITION_SIDE_MIN:
		failures.append({
			"class": "PAD_PATCH_NOT_VOLAR",
			"detail": "pad plate sits at %.4f on the volar side, below %.2f"
				% [pad_volar, POSITION_SIDE_MIN],
		})

	# 3. SEPARATED ACROSS THE DIGIT, PAD ON THE VOLAR SIDE OF THE NAIL. Both
	# plates share the tip's own outward bulge, so their absolute offsets are
	# not opposed; the direction from the nail to the pad is.
	metrics["patch_side_dot"] = nail_side.dot(pad_side)
	var gap: Vector3 = (
		(pad.get("centroid", Vector3.ZERO) as Vector3)
		- (nail.get("centroid", Vector3.ZERO) as Vector3)
	)
	var gap_across: Vector3 = gap - axis * gap.dot(axis)
	var gap_digits: float = gap_across.length() / digit_length
	metrics["patch_separation_digits"] = gap_digits
	metrics["patch_separation_margin"] = gap_digits - SEPARATION_MIN_DIGITS
	if gap_digits < SEPARATION_MIN_DIGITS:
		failures.append({
			"class": "NAIL_PAD_SAME_SIDE",
			"detail": (
				"the two plates sit %.6f digit lengths apart across the digit,"
				+ " below %.4f: this is one surface labelled twice"
			) % [gap_digits, SEPARATION_MIN_DIGITS],
		})
	else:
		var toward_pad: Vector3 = gap_across.normalized()
		var sep_volar: float = toward_pad.dot(volar)
		var sep_nail: float = toward_pad.dot(nail_dir)
		metrics["separation_toward_volar"] = sep_volar
		metrics["separation_toward_nail_dir"] = sep_nail
		metrics["separation_volar_margin"] = sep_volar - SEPARATION_VOLAR_MIN
		metrics["separation_nail_margin"] = -sep_nail - SEPARATION_VOLAR_MIN
		if sep_volar < SEPARATION_VOLAR_MIN:
			failures.append({
				"class": "NAIL_PAD_SAME_SIDE",
				"detail": "the pad does not sit volar of the nail (%.4f below %.2f)"
					% [sep_volar, SEPARATION_VOLAR_MIN],
			})
		if -sep_nail < SEPARATION_VOLAR_MIN:
			failures.append({
				"class": "NAIL_PAD_SAME_SIDE",
				"detail": (
					"the pad does not sit away from the dorsal-radial bisector"
					+ " relative to the nail (%.4f below %.2f)"
				) % [-sep_nail, SEPARATION_VOLAR_MIN],
			})

	# 4. NON-OVERLAP, by identity rather than by geometry.
	var shared: Array = _shared_keys(nail.get("keys", []), pad.get("keys", []))
	metrics["shared_triangles"] = shared.size()
	if not shared.is_empty():
		failures.append({
			"class": "NAIL_PAD_PATCH_OVERLAP",
			"detail": "%d triangle(s) are claimed by both plates" % shared.size(),
		})

	# 5. DISTAL STATION, and 6. weight evidence and 7. planarity, per plate.
	for entry in [["nail", nail], ["pad", pad]]:
		var label: String = entry[0]
		var patch: Dictionary = entry[1]
		var tris: Array = patch.get("triangles", [])
		if tris.is_empty():
			failures.append({
				"class": "THUMB_ANATOMY_PATCH_MISSING",
				"detail": "%s plate carries no triangles" % label,
			})
			continue
		var area_sum := 0.0
		var station_sum := 0.0
		var distal_verts := 0
		var total_verts := 0
		var concentration := 0.0
		var min_weight := 1.0
		var agg: Vector3 = _unit(patch.get("normal", Vector3.ZERO))
		for tri_v in tris:
			var tri: Dictionary = tri_v
			var a: float = float(tri.get("area", 0.0))
			area_sum += a
			station_sum += (
				(tri.get("centroid", Vector3.ZERO) as Vector3).dot(axis) * a
			)
			distal_verts += int(tri.get("distal_verts", 0))
			total_verts += 3
			min_weight = minf(min_weight, float(tri.get("min_weight", 0.0)))
			if agg != Vector3.ZERO:
				concentration += absf(_unit(tri.get("normal", Vector3.ZERO)).dot(agg)) * a
		if area_sum <= 0.0:
			failures.append({
				"class": "THUMB_ANATOMY_PATCH_DEGENERATE",
				"detail": "%s plate has no area" % label,
			})
			continue
		var station_frac: float = (station_sum / area_sum) / digit_length
		var distal_frac: float = float(distal_verts) / float(maxf(total_verts, 1))
		var conc: float = concentration / area_sum
		metrics["%s_station_digits" % label] = station_frac
		metrics["%s_station_margin" % label] = station_frac - DISTAL_STATION_MIN_DIGITS
		metrics["%s_distal_vertex_fraction" % label] = distal_frac
		metrics["%s_min_bone_weight" % label] = min_weight
		metrics["%s_normal_concentration" % label] = conc
		metrics["%s_area_digits2" % label] = area_sum / (digit_length * digit_length)
		if station_frac < DISTAL_STATION_MIN_DIGITS:
			failures.append({
				"class": "PATCH_NOT_DISTAL_STATION",
				"detail": "%s plate sits %.4f digit lengths along the digit, below %.4f"
					% [label, station_frac, DISTAL_STATION_MIN_DIGITS],
			})
		if distal_frac < DISTAL_VERTEX_FRAC_MIN:
			failures.append({
				"class": "PATCH_WEIGHT_BLEED_COMPONENT",
				"detail": (
					"%s plate is only %.4f distal-dominated, below %.2f:"
					+ " this is weight bleed off the middle segment"
				) % [label, distal_frac, DISTAL_VERTEX_FRAC_MIN],
			})
		if conc < NORMAL_CONCENTRATION_MIN:
			failures.append({
				"class": "PATCH_NORMAL_DISPERSED",
				"detail": "%s plate normals concentrate only %.4f, below %.2f"
					% [label, conc, NORMAL_CONCENTRATION_MIN],
			})
	return {
		"ok": failures.is_empty(),
		"validation_id": VALIDATION_ID,
		"failures": failures,
		"failure_classes": _classes(failures),
		"metrics": metrics,
	}


## The direction a point sits in, off the digit's medial axis.
static func _side_direction(point: Vector3, axis: Vector3) -> Vector3:
	var perp: Vector3 = point - axis * point.dot(axis)
	if perp.length_squared() < 1e-24:
		return Vector3.ZERO
	return perp.normalized()


static func _shared_keys(a: Array, b: Array) -> Array:
	var seen := {}
	for k in a:
		seen[str(k)] = true
	var out: Array = []
	for k in b:
		if seen.has(str(k)):
			out.append(str(k))
	return out


static func _classes(failures: Array) -> Array:
	var out: Array = []
	for f in failures:
		var c: String = str((f as Dictionary).get("class", ""))
		if not c in out:
			out.append(c)
	return out


static func _unit(v) -> Vector3:
	var vec: Vector3 = v
	if vec.length_squared() < 1e-24:
		return Vector3.ZERO
	return vec.normalized()


static func _refuse(error_class: String, detail: String, metrics: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"validation_id": VALIDATION_ID,
		"failures": [{"class": error_class, "detail": detail}],
		"failure_classes": [error_class],
		"metrics": metrics,
	}
