# Development diagnostic: are two deliveries of ONE humanoid compiled to the
# same thumb surface? (A2.13b)
#
#   godot --headless --path game \
#       -s res://presentation/equipment/tools/thumb_surface_correspondence.gd \
#       -- --a=res://... --b=res://... [--side=right] [--family=...] [--json]
#
# WHY THIS EXISTS. The A2.12 slice concluded that a rejected raw delivery failed
# the thumb approach gates because its rest basis was 90 degrees from the
# representation the pose calibration was authored against. That was refuted:
# both deliveries reach the same anatomical joint pose to within ~1.5 degrees.
# What actually differed was the COMPILED SURFACE - one resolved 10 pad
# triangles, the other 7, and the compiled pad normal is an input to the axes
# the calibration rotates about. Diagnosing that from the final gate numbers is
# guesswork, so this tool reports the FIRST operation at which two
# corresponding triangles diverge.
#
# WHAT IT IS NOT. It is not a gate, not a test and not part of any acceptance
# chain. It reads the compiler's own per-candidate table
# (`Compiler.compile(..., diagnostics)`) rather than reimplementing
# classification, so it cannot drift away from what the compiler actually did.
#
# COMMON SPACE. Every length is expressed in DIGIT LENGTHS (the distal thumb
# segment's own length) inside the distal bone's rest frame, and every direction
# is a dot product against that hand's own anatomical volar/radial/axis
# directions. Both are derived from each rig's own bones, so a 100x armature
# scale and a 90-degree rest permutation cancel by construction and neither
# delivery's units or names appear in any comparison.
extends SceneTree

const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const DefaultSkinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")

const FAMILIES := {
	"mixamo_52_humanoid": "res://presentation/equipment/mixamo_52_hand_family.gd",
}

## Two centroids this close, in digit lengths, are the same surface location.
## A retriangulated export may renumber every index, so correspondence has to
## be geometric; this is deliberately much tighter than the classification
## thresholds it is used to explain.
const SAME_SURFACE_MAX_DIGITS := 0.05
## Two normals this aligned are the same facing.
const SAME_FACING_MIN_DOT := 0.98

var _out := {}


func _init() -> void:
	_run()


func _run() -> void:
	# The hand frame reads `skeleton.global_transform`, so the delivery has to
	# be a live child of a real tree before anything is measured.
	await process_frame
	var args: Dictionary = _parse_args()
	var side: String = str(args.get("side", "right"))
	var a_path: String = str(args.get("a", ""))
	var b_path: String = str(args.get("b", ""))
	if a_path.is_empty() or b_path.is_empty():
		push_error("--a and --b are required")
		quit(1)
		return
	var a: Dictionary = await _profile(a_path, side, str(args.get("family", "")))
	var b: Dictionary = await _profile(b_path, side, str(args.get("family", "")))
	_out = {
		"side": side,
		"a": a,
		"b": b,
	}
	if bool(a.get("ok", false)) and bool(b.get("ok", false)):
		_out["correspondence"] = _correspond(a, b)
	if args.has("json"):
		print("THUMB_SURFACE_CORRESPONDENCE %s" % JSON.stringify(_jsonable(_out)))
	else:
		_print_human()
	quit(0)


## Compile one delivery and keep the compiler's own candidate table.
func _profile(scene_path: String, side: String, family_id: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "path": scene_path, "error": "asset missing"}
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return {"ok": false, "path": scene_path, "error": "not a scene"}
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var skeleton: Skeleton3D = DefaultSkinning.find_skeleton(inst)
	if skeleton == null:
		inst.queue_free()
		return {"ok": false, "path": scene_path, "error": "no skeleton"}
	skeleton.force_update_all_bone_transforms()
	var family = _resolve_family(skeleton, family_id)
	if family == null:
		inst.queue_free()
		return {"ok": false, "path": scene_path, "error": "no family resolved"}
	var diagnostics := {}
	var artifact: Dictionary = Compiler.compile(
		inst, skeleton, family, [side], null, null, diagnostics
	)
	var per_side: Dictionary = (artifact.get("sides", {}) as Dictionary).get(side, {})
	var out := {
		"ok": true,
		"path": scene_path,
		"family_id": str(family.FAMILY_ID),
		"family_version": str(family.FAMILY_VERSION),
		"bone_count": skeleton.get_bone_count(),
		"armature_scale": _armature_scale(skeleton),
		"geometry_sha256": str(artifact.get("source_geometry_sha256", "")),
		"rig_sha256": str(artifact.get("source_rig_sha256", "")),
		"compiled": bool(per_side.get("compiled", false)),
		"error_class": str(per_side.get("error_class", "")),
		"detail": str(per_side.get("detail", "")),
		"diagnostics": diagnostics.get(side, {}),
	}
	if bool(per_side.get("compiled", false)):
		out["nail_normal_local"] = per_side["nail_normal_local"]
		out["pad_normal_local"] = per_side["pad_normal_local"]
		out["rest_nail_pad_dot"] = float(per_side["rest_nail_pad_dot"])
		out["pad_marker_local"] = per_side["pad_marker_local"]
		out["nail_marker_local"] = per_side["nail_marker_local"]
		out["evidence"] = per_side["evidence"]
		out["confidence"] = per_side["confidence"]
	inst.queue_free()
	return out


func _armature_scale(skeleton: Skeleton3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var cursor: Node3D = skeleton
	while cursor != null:
		t = cursor.transform * t
		cursor = cursor.get_parent() as Node3D
	return t.basis.get_scale()


func _resolve_family(skeleton: Skeleton3D, requested: String):
	for fid in FAMILIES.keys():
		if not requested.is_empty() and str(fid) != requested:
			continue
		var fam = load(str(FAMILIES[fid]))
		if fam == null:
			continue
		var bones: Dictionary = HandProfile.family_bone_map(fam, skeleton, "right")
		if not bones.is_empty() and skeleton.find_bone(str(bones.get("hand", ""))) >= 0:
			return fam
	return null


## Match every candidate of A to a candidate of B by SURFACE LOCATION in the
## common space, then report the first operation at which the pair diverges.
func _correspond(a: Dictionary, b: Dictionary) -> Dictionary:
	var da: Dictionary = a["diagnostics"]
	var db: Dictionary = b["diagnostics"]
	var rows_a: Array = da.get("candidates", [])
	var rows_b: Array = db.get("candidates", [])
	var by_key_b := {}
	for r in rows_b:
		by_key_b[str(r["key"])] = r
	var pairs: Array = []
	var unmatched_a: Array = []
	var index_identical := 0
	for ra in rows_a:
		var best = null
		var best_d := INF
		for rb in rows_b:
			var d: float = (
				(ra["centroid_digits"] as Vector3).distance_to(rb["centroid_digits"] as Vector3)
			)
			if d < best_d:
				best_d = d
				best = rb
		if best == null or best_d > SAME_SURFACE_MAX_DIGITS:
			unmatched_a.append({"key": str(ra["key"]), "nearest_digits": best_d})
			continue
		if str(ra["key"]) == str(best["key"]):
			index_identical += 1
		pairs.append(_compare_pair(ra, best, best_d))
	# The FIRST operation at which any pair diverges. Ordered as the compiler
	# performs them, so the answer is an operation and not a final value.
	# A renumbered index buffer is NOT a divergence: an export is allowed to
	# renumber topology, and the brief requires that geometric correspondence
	# then carries the proof instead. It is reported as its own fact.
	var renumbered := 0
	for p in pairs:
		if "vertex_correspondence" in (p["diverged"] as Array):
			renumbered += 1
			(p["diverged"] as Array).erase("vertex_correspondence")
	var stages: Array[String] = [
		"candidate_set",
		"skin_determinant",
		"index_order_normal",
		"imported_normal_carried",
		"winding_decision",
		"classified_normal",
		"anatomical_score",
		"component_membership",
		"patch_outcome",
	]
	# What the A2.13a per-triangle winding rule would have decided for the same
	# pairs, so the repair's effect is evidenced rather than asserted.
	var legacy_split: Array = []
	for p in pairs:
		if bool(p["a213a_winding_diverged"]):
			legacy_split.append(p["key_a"])
	var first_divergence := ""
	var diverging: Array = []
	for st in stages:
		var hits: Array = []
		for p in pairs:
			if str(st) in (p["diverged"] as Array):
				hits.append(p["key_a"])
		if not hits.is_empty():
			if first_divergence.is_empty():
				first_divergence = str(st)
			diverging.append({"stage": str(st), "pairs": hits.size(), "keys": hits})
	var wa: Dictionary = da.get("winding_resolution", {})
	var wb: Dictionary = db.get("winding_resolution", {})
	return {
		"candidates_a": rows_a.size(),
		"candidates_b": rows_b.size(),
		"matched_pairs": pairs.size(),
		"unmatched_a": unmatched_a,
		"vertex_indices_identical": index_identical,
		"vertex_indices_renumbered": renumbered,
		"worst_centroid_gap_digits": _worst_gap(pairs),
		"components_a": (da.get("components", []) as Array).size(),
		"components_b": (db.get("components", []) as Array).size(),
		"tip_a": (da.get("tip_keys", []) as Array).size(),
		"tip_b": (db.get("tip_keys", []) as Array).size(),
		"nail_a": (da.get("nail_keys", []) as Array).size(),
		"nail_b": (db.get("nail_keys", []) as Array).size(),
		"pad_a": (da.get("pad_keys", []) as Array).size(),
		"pad_b": (db.get("pad_keys", []) as Array).size(),
		"winding_a": wa,
		"winding_b": wb,
		"first_divergence": first_divergence,
		"divergences": diverging,
		"a213a_winding_would_diverge": legacy_split,
		"pairs": pairs,
		"digit_length_a": float(da.get("digit_length", 0.0)),
		"digit_length_b": float(db.get("digit_length", 0.0)),
		"anatomy_agreement": {
			"volar_dot": (da.get("volar_t3", Vector3.ZERO) as Vector3).dot(
				db.get("volar_t3", Vector3.ZERO) as Vector3
			),
			"radial_dot": (da.get("radial_t3", Vector3.ZERO) as Vector3).dot(
				db.get("radial_t3", Vector3.ZERO) as Vector3
			),
			"axis_dot": (da.get("thumb_axis_t3", Vector3.ZERO) as Vector3).dot(
				db.get("thumb_axis_t3", Vector3.ZERO) as Vector3
			),
		},
	}


func _worst_gap(pairs: Array) -> float:
	var worst := 0.0
	for p in pairs:
		worst = maxf(worst, float(p["centroid_gap_digits"]))
	return worst


func _compare_pair(ra: Dictionary, rb: Dictionary, centroid_gap: float) -> Dictionary:
	var diverged: Array[String] = []
	if str(ra["key"]) != str(rb["key"]):
		diverged.append("vertex_correspondence")
	if float(ra["skin_determinant_sign"]) != float(rb["skin_determinant_sign"]):
		diverged.append("skin_determinant")
	var idx_dot: float = (
		(ra["normal_index_order"] as Vector3).dot(rb["normal_index_order"] as Vector3)
	)
	if idx_dot < SAME_FACING_MIN_DOT:
		diverged.append("index_order_normal")
	var imp_ok: bool = (
		bool(ra["imported_normal_available"]) and bool(rb["imported_normal_available"])
	)
	var imp_dot: float = 0.0
	if imp_ok:
		imp_dot = (
			(ra["normal_imported_carried"] as Vector3).dot(
				rb["normal_imported_carried"] as Vector3
			)
		)
		if imp_dot < SAME_FACING_MIN_DOT:
			diverged.append("imported_normal_carried")
	elif bool(ra["imported_normal_available"]) != bool(rb["imported_normal_available"]):
		diverged.append("imported_normal_carried")
	if float(ra["winding_applied"]) != float(rb["winding_applied"]):
		diverged.append("winding_decision")
	var legacy_diverged: bool = (
		float(ra["winding_a213a_per_triangle"]) != float(rb["winding_a213a_per_triangle"])
	)
	var cls_dot: float = (
		(ra["normal_classified"] as Vector3).dot(rb["normal_classified"] as Vector3)
	)
	if cls_dot < SAME_FACING_MIN_DOT:
		diverged.append("classified_normal")
	# Anatomical scores decide the patches, so a divergence here is the one
	# that changes the compiled surface.
	var d_volar_gap: float = absf(float(ra["d_volar"]) - float(rb["d_volar"]))
	var d_nail_gap: float = absf(float(ra["d_nail"]) - float(rb["d_nail"]))
	if maxf(d_volar_gap, d_nail_gap) > 1.0 - SAME_FACING_MIN_DOT:
		diverged.append("anatomical_score")
	if int(ra.get("component", -1)) != int(rb.get("component", -1)):
		diverged.append("component_membership")
	if str(ra.get("outcome", "")) != str(rb.get("outcome", "")):
		diverged.append("patch_outcome")
	return {
		"key_a": str(ra["key"]),
		"key_b": str(rb["key"]),
		"centroid_gap_digits": centroid_gap,
		"index_order_normal_dot": idx_dot,
		"imported_normal_dot": imp_dot,
		"classified_normal_dot": cls_dot,
		"winding_a": float(ra["winding_applied"]),
		"winding_b": float(rb["winding_applied"]),
		"winding_a213a_a": float(ra["winding_a213a_per_triangle"]),
		"winding_a213a_b": float(rb["winding_a213a_per_triangle"]),
		"a213a_winding_diverged": legacy_diverged,
		"det_a": float(ra["skin_determinant_sign"]),
		"det_b": float(rb["skin_determinant_sign"]),
		"d_volar_a": float(ra["d_volar"]),
		"d_volar_b": float(rb["d_volar"]),
		"d_nail_a": float(ra["d_nail"]),
		"d_nail_b": float(rb["d_nail"]),
		"outcome_a": str(ra.get("outcome", "")),
		"outcome_b": str(rb.get("outcome", "")),
		"area_a_digits2": float(ra["area_digits2"]),
		"area_b_digits2": float(rb["area_digits2"]),
		"diverged": diverged,
	}


func _print_human() -> void:
	for label in ["a", "b"]:
		var d: Dictionary = _out[label]
		print("--- %s : %s" % [label.to_upper(), d.get("path", "")])
		if not bool(d.get("ok", false)):
			print("    UNAVAILABLE: %s" % d.get("error", ""))
			continue
		print("    family        %s %s" % [d["family_id"], d["family_version"]])
		print("    bones         %d, armature scale %s" % [d["bone_count"], d["armature_scale"]])
		print("    geometry      %s" % str(d["geometry_sha256"]).substr(0, 16))
		print("    rig           %s" % str(d["rig_sha256"]).substr(0, 16))
		print("    compiled      %s %s" % [d["compiled"], d.get("error_class", "")])
		var dg: Dictionary = d.get("diagnostics", {})
		print("    candidates    %d" % (dg.get("candidates", []) as Array).size())
		print("    winding       %s" % str(dg.get("winding_resolution", {})))
		if bool(d.get("compiled", false)):
			var ev: Dictionary = d["evidence"]
			print("    nail/pad      %d / %d" % [
				(dg.get("nail_keys", []) as Array).size(),
				(dg.get("pad_keys", []) as Array).size(),
			])
			print("    rest dot      %.6f" % d["rest_nail_pad_dot"])
			print("    pad normal    %s" % str(d["pad_normal_local"]))
			print("    margins       nail %.4f pad %.4f" % [
				ev["nail_margin"], ev["pad_margin"]
			])
	if not _out.has("correspondence"):
		print("--- CORRESPONDENCE unavailable: one delivery did not compile")
		return
	var c: Dictionary = _out["correspondence"]
	print("--- CORRESPONDENCE")
	print("    candidates          %d vs %d, matched %d" % [
		c["candidates_a"], c["candidates_b"], c["matched_pairs"]
	])
	print("    identical indices   %d, renumbered %d (worst centroid gap %.9f digits)" % [
		c["vertex_indices_identical"], c["vertex_indices_renumbered"],
		c["worst_centroid_gap_digits"],
	])
	print("    digit length        %.9f vs %.9f" % [c["digit_length_a"], c["digit_length_b"]])
	print("    anatomy agreement   %s" % str(c["anatomy_agreement"]))
	print("    tip / nail / pad    %d/%d/%d vs %d/%d/%d" % [
		c["tip_a"], c["nail_a"], c["pad_a"], c["tip_b"], c["nail_b"], c["pad_b"]
	])
	print("    FIRST DIVERGENCE    %s" % (
		c["first_divergence"] if not str(c["first_divergence"]).is_empty() else "(none)"
	))
	for dv in (c["divergences"] as Array):
		print("      %-26s %d pair(s)" % [dv["stage"], dv["pairs"]])
	print("    A2.13a per-triangle winding would have split %d pair(s): %s" % [
		(c["a213a_winding_would_diverge"] as Array).size(),
		str(c["a213a_winding_would_diverge"]),
	])
	for p in (c["pairs"] as Array):
		if (p["diverged"] as Array).is_empty():
			continue
		print("      %s vs %s gap %.6f d_volar %.4f/%.4f d_nail %.4f/%.4f %s -> %s : %s" % [
			p["key_a"], p["key_b"], p["centroid_gap_digits"],
			p["d_volar_a"], p["d_volar_b"], p["d_nail_a"], p["d_nail_b"],
			p["outcome_a"], p["outcome_b"], str(p["diverged"]),
		])


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if not s.begins_with("--"):
			continue
		var body := s.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _jsonable(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in (v as Dictionary).keys():
				o[str(k)] = _jsonable((v as Dictionary)[k])
			return o
		TYPE_ARRAY:
			var arr := []
			for it in (v as Array):
				arr.append(_jsonable(it))
			return arr
		TYPE_VECTOR3, TYPE_VECTOR2:
			return str(v)
		_:
			return v
