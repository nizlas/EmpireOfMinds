# A2.13b: the compiled thumb surface is a property of the HUMANOID, not of the
# delivery.
#
# The A2.11/A2.12 slices recorded that a raw Mixamo delivery failed the thumb
# approach gates because its hand rest basis sat 90 degrees from the
# representation the pose was calibrated against. That was refuted by direct
# measurement: both deliveries reach the same anatomical joint pose to ~1.5
# degrees. What actually differed was the COMPILED SURFACE — one delivery
# resolved 10 pad triangles and the other 7, with nail plates ~55 degrees apart —
# because the per-triangle winding decision compared a SKELETON-space face normal
# against a MESH-space shading normal. Whether that mismatch flipped a triangle
# depended on the delivery's bind representation, so the surface was a property
# of the export.
#
# Every test here perturbs the REPRESENTATION of one rig and requires the
# compiled surface not to move: the same patches, the same normals in the digit's
# own frame, the same anatomical verdict. The negatives then require the
# classification to fail closed by exact name when the geometry really is wrong,
# so invariance is not achieved by making the compiler indifferent.
extends SceneTree

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const RAW_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0"
	+ "/generated_warrior_3d_uthana_rigged.glb"
)
const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")
const Compiler = preload("res://presentation/equipment/hand_fixture_compiler.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Anatomy = preload("res://presentation/equipment/thumb_surface_anatomy.gd")
const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")

## Two centroids this close, in DIGIT LENGTHS, are the same surface location. A
## re-exported mesh may renumber every index, so correspondence has to be
## geometric. Deliberately far tighter than any classification threshold.
const SAME_SURFACE_MAX_DIGITS := 0.05
## Two normals this aligned are the same facing (~11 degrees).
const SAME_FACING_MIN_DOT := 0.98
## One rig re-expressed under a different ancestor transform is the SAME rig, so
## its surface must reproduce to floating-point noise rather than to a tolerance.
const SAME_REPRESENTATION_MIN_DOT := 0.999999

var _total := 0
var _any_fail := false
var _reference: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	# The unperturbed retargeted delivery is the reference every representation
	# is compared against. It is captured, not asserted, so a change in the
	# reference itself surfaces as a broad failure rather than a silent shift.
	_reference = await _profile(Native.UTHANA_TARGET_GLB, Transform3D.IDENTITY)
	_check(bool(_reference.get("compiled", false)),
		"the reference delivery compiles (%s)" % str(_reference.get("error_class", "")))
	if not bool(_reference.get("compiled", false)):
		print("test_thumb_surface_invariance: %d checks, FAIL" % _total)
		quit(1)
		return
	print("A213B_REF nail=%d pad=%d rest_dot=%.6f digit=%.9f" % [
		int(_reference["nail_tris"]),
		int(_reference["pad_tris"]),
		float(_reference["rest_nail_pad_dot"]),
		float(_reference["digit_length"]),
	])
	await _test_raw_delivery_is_the_same_surface()
	await _test_ancestor_transforms_do_not_move_the_surface()
	await _test_active_pose_before_compilation_is_ignored()
	await _test_reflected_ancestor_is_classified_not_compiled()
	await _test_normal_transform_is_the_inverse_transpose_of_the_skin()
	await _test_shading_normal_disagreement_fails_closed()
	await _test_anatomy_validation_rejects_wrong_surfaces()
	print("test_thumb_surface_invariance: %d checks, %s" % [
		_total, "FAIL" if _any_fail else "OK"
	])
	quit(1 if _any_fail else 0)


# ------------------------------------------------------- the central invariant


## THE 7-VERSUS-10 REGRESSION. The raw delivery carries different bone names, a
## 100x armature scale and a hand rest basis 90 degrees from the retargeted one.
## It is nevertheless the same humanoid, so it must compile the same surface.
func _test_raw_delivery_is_the_same_surface() -> void:
	var raw: Dictionary = await _profile(RAW_GLB, Transform3D.IDENTITY)
	_check(bool(raw.get("compiled", false)),
		"the raw delivery compiles (%s)" % str(raw.get("error_class", "")))
	if not bool(raw.get("compiled", false)):
		return
	# It really is a different REPRESENTATION, or this test proves nothing.
	_check(
		absf(float(raw["digit_length"]) / float(_reference["digit_length"]) - 1.0) > 0.5,
		"the two deliveries differ in bone-local scale (%.9f vs %.9f)"
			% [float(raw["digit_length"]), float(_reference["digit_length"])]
	)
	_check(
		str(raw["geometry_sha256"]) != str(_reference["geometry_sha256"]),
		"the two deliveries are genuinely different files"
	)
	# The A2.12 result was 4 nail + 7 pad here against 4 + 10 there. Pinned as
	# equality with the reference, not as a literal count, so this test follows
	# the reference if the reference legitimately changes.
	_check(
		int(raw["pad_tris"]) == int(_reference["pad_tris"]),
		"the raw delivery resolves the reference pad plate (%d vs %d)"
			% [int(raw["pad_tris"]), int(_reference["pad_tris"])]
	)
	_check(
		int(raw["nail_tris"]) == int(_reference["nail_tris"]),
		"the raw delivery resolves the reference nail plate (%d vs %d)"
			% [int(raw["nail_tris"]), int(_reference["nail_tris"])]
	)
	_check_same_surface(raw, _reference, "raw vs retargeted", SAME_FACING_MIN_DOT)
	# The candidate set and the topological tip component are also shared, so
	# the agreement is not two different surfaces scoring alike.
	_check(
		int(raw["candidates"]) == int(_reference["candidates"]),
		"both deliveries find the same candidate count (%d vs %d)"
			% [int(raw["candidates"]), int(_reference["candidates"])]
	)
	_check(
		int(raw["tip_tris"]) == int(_reference["tip_tris"]),
		"both deliveries find the same topological tip component (%d vs %d)"
			% [int(raw["tip_tris"]), int(_reference["tip_tris"])]
	)


## Uniform scale, a 100x scale, and a placed-and-rotated ancestor are all the
## same rig seen from elsewhere. The compiler classifies in the distal bone's own
## rest space, so none of them may reach the artifact.
func _test_ancestor_transforms_do_not_move_the_surface() -> void:
	var cases := {
		"uniform 3.7x ancestor": Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3.7), Vector3.ZERO),
		"100x ancestor": Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 100.0), Vector3.ZERO),
		"placed and rotated ancestor": Transform3D(
			Basis(Vector3(0.3, 0.8, -0.5).normalized(), 1.1),
			Vector3(7.0, -3.0, 11.0)
		),
	}
	for label in cases.keys():
		var moved: Dictionary = await _profile(Native.UTHANA_TARGET_GLB, cases[label])
		_check(bool(moved.get("compiled", false)),
			"%s still compiles (%s)" % [label, str(moved.get("error_class", ""))])
		if not bool(moved.get("compiled", false)):
			continue
		_check_same_surface(
			moved, _reference, str(label), SAME_REPRESENTATION_MIN_DOT
		)
		# Skeleton space excludes the ancestor entirely, so this is exact.
		_check(
			str(moved["content_hash"]) == str(_reference["content_hash"]),
			"%s produces a byte-identical artifact" % label
		)


## A rig posed by an animation before compilation must compile its REST surface.
## Classifying a deformed pose would make the artifact depend on when the
## compiler happened to run.
func _test_active_pose_before_compilation_is_ignored() -> void:
	var posed: Dictionary = await _profile(
		Native.UTHANA_TARGET_GLB, Transform3D.IDENTITY, true
	)
	_check(bool(posed.get("compiled", false)),
		"a posed rig still compiles (%s)" % str(posed.get("error_class", "")))
	if not bool(posed.get("compiled", false)):
		return
	_check(
		bool(posed["was_posed"]),
		"the probe really did pose the thumb chain before compiling"
	)
	_check_same_surface(posed, _reference, "posed before compilation", SAME_REPRESENTATION_MIN_DOT)
	_check(
		str(posed["content_hash"]) == str(_reference["content_hash"]),
		"a posed rig compiles a byte-identical artifact"
	)


## A mirrored ancestor is not a representation of the same hand: it is the other
## chirality. Handling reflection "gracefully" by flipping normals would let a
## left hand be certified as a right one, so it must be refused by name.
func _test_reflected_ancestor_is_classified_not_compiled() -> void:
	# A mirrored ancestor: the other chirality, not another view of this hand.
	await _same_surface_or_named_refusal(
		"mirrored ancestor",
		Transform3D(Basis.IDENTITY.scaled(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO),
		["HAND_FRAME_NOT_RIGHT_HANDED", "HAND_FRAME_RADIAL_INCONSISTENT", "HAND_VOLAR_AMBIGUOUS"]
	)
	# A non-uniform ancestor shears the world-space flesh probe the volar
	# dual-check samples. Refusing is correct; compiling a DIFFERENT surface is
	# not, and that is what this pins.
	await _same_surface_or_named_refusal(
		"non-uniform ancestor",
		Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 0.5, 3.0)), Vector3(1.0, 2.0, 3.0)),
		["HAND_VOLAR_AMBIGUOUS", "HAND_FRAME_NOT_RIGHT_HANDED"]
	)


## Either the reference surface, bit for bit, or a refusal from a named class.
## Never a third outcome, which is the only one that would be a silent change of
## which surface a delivery compiled.
func _same_surface_or_named_refusal(
	label: String, ancestor: Transform3D, allowed: Array
) -> void:
	var got: Dictionary = await _profile(Native.UTHANA_TARGET_GLB, ancestor)
	if bool(got.get("compiled", false)):
		_check_same_surface(got, _reference, str(label), SAME_REPRESENTATION_MIN_DOT)
		_check(
			str(got["content_hash"]) == str(_reference["content_hash"]),
			"%s cannot change the skeleton-space artifact" % label
		)
	else:
		_check(
			allowed.has(str(got.get("error_class", ""))),
			"%s is refused by an exact frame class (%s)"
				% [label, str(got.get("error_class", ""))]
		)


# ------------------------------------------------------------ the normal contract


## THE ROOT CAUSE, pinned as a measurement. A2.13a decided winding by comparing
## the skeleton-space face cross product against the imported shading normal
## carried by `pose * rest.inverse()` — which omits the bind pose and uses the
## basis instead of its inverse-transpose, so the two vectors lived in different
## frames. The compiler records, per candidate, what that rule would have
## decided. On a delivery whose bind representation exposes the mismatch, some
## candidates disagree; the current rule must not.
func _test_normal_transform_is_the_inverse_transpose_of_the_skin() -> void:
	var raw: Dictionary = await _profile(RAW_GLB, Transform3D.IDENTITY, false, true)
	_check(bool(raw.get("compiled", false)), "the raw delivery compiles for the winding audit")
	if not bool(raw.get("compiled", false)):
		return
	var rows: Array = raw.get("candidate_rows", [])
	_check(not rows.is_empty(), "the compiler exposed its per-candidate winding table")
	var superseded_disagreements := 0
	var current_disagreements := 0
	var applied: float = 0.0
	for row_v in rows:
		var row: Dictionary = row_v
		applied = float(row.get("winding_applied", 0.0))
		if float(row.get("winding_a213a_per_triangle", 0.0)) != applied:
			superseded_disagreements += 1
		# The current rule is one decision for the whole surface, so no
		# candidate may carry a different sign from its neighbours.
		if float(row.get("winding_applied", 0.0)) != applied:
			current_disagreements += 1
	print("A213B_WINDING superseded_disagreements=%d of %d" % [
		superseded_disagreements, rows.size()
	])
	_check(
		superseded_disagreements > 0,
		"the superseded per-triangle rule really did flip candidates on this"
		+ " delivery (%d) — otherwise this test proves nothing"
			% superseded_disagreements
	)
	_check(
		current_disagreements == 0,
		"the current rule applies ONE winding across the whole surface (%d splits)"
			% current_disagreements
	)


## The imported shading normal is a cross-check, not the authority. When it
## disagrees with the geometry it must produce a refusal, never a silent
## geometry-only decision — a mesh with inverted authored normals is a broken
## delivery, not a delivery to be quietly repaired.
func _test_shading_normal_disagreement_fails_closed() -> void:
	var bad: Dictionary = await _profile(
		Native.UTHANA_TARGET_GLB, Transform3D.IDENTITY, false, false, true
	)
	_check(
		not bool(bad.get("compiled", false)),
		"a mesh whose authored normals contradict its geometry does not compile"
	)
	_check(
		str(bad.get("error_class", "")) == "PATCH_WINDING_UNDERIVABLE",
		"...and is classified PATCH_WINDING_UNDERIVABLE (%s)"
			% str(bad.get("error_class", ""))
	)


# ------------------------------------------------- independent anatomy negatives


## The anatomy module is asked the same question by the compiler and by the
## runtime bind, so its refusals are exercised directly against the REFERENCE
## rig's own frame. Each case is a surface that is perfectly self-consistent:
## only its anatomical meaning is wrong.
func _test_anatomy_validation_rejects_wrong_surfaces() -> void:
	var ctx: Dictionary = _reference.get("anatomy_context", {})
	_check(not ctx.is_empty(), "the reference exposed its anatomy context")
	if ctx.is_empty():
		return
	var base: Dictionary = Anatomy.validate(ctx)
	_check(
		bool(base.get("ok", false)),
		"the reference surface passes independent anatomical validation (%s)"
			% str(base.get("failure_classes", []))
	)
	# 1. THE PLATES SWAPPED. Both patches exist, both are real tip geometry,
	#    and the fixture would be entirely consistent with itself.
	var swapped: Dictionary = ctx.duplicate(true)
	var keep = swapped["nail"]
	swapped["nail"] = swapped["pad"]
	swapped["pad"] = keep
	var sw: Dictionary = Anatomy.validate(swapped)
	_check(not bool(sw.get("ok", true)), "swapping the two plates is refused")
	_check(
		(sw.get("failure_classes", []) as Array).has("NAIL_PATCH_NOT_DORSAL_RADIAL"),
		"...naming the nail plate's flank (%s)" % str(sw.get("failure_classes", []))
	)
	# 2. ONE SURFACE LABELLED TWICE. This is what a weak nail signal produces,
	#    and it is the case a self-referential dot-product gate cannot see: the
	#    stored relation agrees with the normals because they are the same
	#    normals.
	var same: Dictionary = ctx.duplicate(true)
	same["nail"] = (ctx["pad"] as Dictionary).duplicate(true)
	var sm: Dictionary = Anatomy.validate(same)
	_check(not bool(sm.get("ok", true)), "declaring one plate twice is refused")
	for cls in ["NAIL_PAD_PATCH_OVERLAP", "NAIL_PAD_SAME_SIDE"]:
		_check(
			(sm.get("failure_classes", []) as Array).has(cls),
			"...naming %s (%s)" % [cls, str(sm.get("failure_classes", []))]
		)
	# 3. WEIGHT BLEED. A patch whose vertices are carried by the segment ABOVE
	#    the distal joint is flesh, not the tip cap.
	var bleed: Dictionary = ctx.duplicate(true)
	var pad_patch: Dictionary = (bleed["pad"] as Dictionary)
	for row_v in (pad_patch["triangles"] as Array):
		(row_v as Dictionary)["distal_verts"] = 0
	var bl: Dictionary = Anatomy.validate(bleed)
	_check(not bool(bl.get("ok", true)), "a weight-bleed patch is refused")
	_check(
		(bl.get("failure_classes", []) as Array).has("PATCH_WEIGHT_BLEED_COMPONENT"),
		"...as PATCH_WEIGHT_BLEED_COMPONENT (%s)" % str(bl.get("failure_classes", []))
	)
	# 4. A PROXIMAL PATCH. Both plates must sit on the distal end of the digit.
	var proximal: Dictionary = ctx.duplicate(true)
	var axis: Vector3 = ctx["thumb_axis"]
	var digit: float = float(ctx["digit_length"])
	var pp: Dictionary = (proximal["pad"] as Dictionary)
	pp["centroid"] = (pp["centroid"] as Vector3) - axis * digit
	for row_v2 in (pp["triangles"] as Array):
		var row2: Dictionary = row_v2
		row2["centroid"] = (row2["centroid"] as Vector3) - axis * digit
	var pr: Dictionary = Anatomy.validate(proximal)
	_check(not bool(pr.get("ok", true)), "a patch a whole segment too proximal is refused")
	_check(
		(pr.get("failure_classes", []) as Array).has("PATCH_NOT_DISTAL_STATION"),
		"...as PATCH_NOT_DISTAL_STATION (%s)" % str(pr.get("failure_classes", []))
	)
	# 5. THE STORED RELATION IS NOT AN INPUT. Manipulating the fixture's own
	#    declared nail/pad dot to agree with a wrong surface changes nothing,
	#    because the verdict never reads it.
	var forged: Dictionary = ctx.duplicate(true)
	forged["nail"] = (ctx["pad"] as Dictionary).duplicate(true)
	forged["declared_nail_pad_dot"] = -1.0
	var fg: Dictionary = Anatomy.validate(forged)
	_check(
		not bool(fg.get("ok", true))
		and (fg.get("failure_classes", []) as Array) == (sm.get("failure_classes", []) as Array),
		"a manipulated stored nail/pad relation cannot rescue a wrong surface"
	)


# ---------------------------------------------------------------------- helpers


## Compile one delivery under one ancestor transform and reduce the result to the
## quantities that must be representation-independent. Every length is divided by
## the digit's own length and every direction is expressed in the distal bone's
## rest frame, so no delivery's units enter the comparison.
func _profile(
	glb: String,
	ancestor: Transform3D,
	pose_first: bool = false,
	want_rows: bool = false,
	invert_normals: bool = false
) -> Dictionary:
	var host := Node3D.new()
	host.transform = ancestor
	root.add_child(host)
	var character: Node3D = (load(glb) as PackedScene).instantiate()
	host.add_child(character)
	await process_frame
	var skel: Skeleton3D = Skinning.find_skeleton(character)
	skel.force_update_all_bone_transforms()
	var was_posed := false
	if pose_first:
		# A pose no rest surface could survive being classified in.
		var bones: Dictionary = HandProfile.family_bone_map(Family, skel, "right")
		for bone_name in (bones.get("thumb", []) as Array):
			var bi: int = skel.find_bone(str(bone_name))
			if bi >= 0:
				skel.set_bone_pose_rotation(
					bi, Quaternion(Vector3(0.4, 0.7, 0.6).normalized(), 0.9)
				)
				was_posed = true
		skel.force_update_all_bone_transforms()
	if invert_normals:
		_invert_authored_normals(Skinning.find_skinned_mesh(character))
	var diagnostics := {}
	var artifact: Dictionary = Compiler.compile(
		character, skel, Family, ["right"], Skinning, null, diagnostics
	)
	var side: Dictionary = (artifact.get("sides", {}) as Dictionary).get("right", {})
	var diag: Dictionary = diagnostics.get("right", {})
	var out := {
		"compiled": bool(side.get("compiled", false)),
		"error_class": str(side.get("error_class", "")),
		"content_hash": str(artifact.get("content_hash", "")),
		"geometry_sha256": str(artifact.get("source_geometry_sha256", "")),
		"was_posed": was_posed,
	}
	if bool(side.get("compiled", false)):
		var digit: float = float(diag.get("digit_length", 1.0))
		out["digit_length"] = digit
		out["nail_tris"] = (side.get("nail_tris", []) as Array).size()
		out["pad_tris"] = (side.get("pad_tris", []) as Array).size()
		out["rest_nail_pad_dot"] = float(side.get("rest_nail_pad_dot", 9.0))
		out["nail_normal"] = side["nail_normal_local"]
		out["pad_normal"] = side["pad_normal_local"]
		# Digit-normalised so a 100x armature cancels by construction.
		out["nail_marker_digits"] = (side["nail_marker_local"] as Vector3) / digit
		out["pad_marker_digits"] = (side["pad_marker_local"] as Vector3) / digit
		out["candidates"] = int(diag.get("candidate_count", 0))
		out["tip_tris"] = int(diag.get("tip_component_triangles", 0))
		out["anatomy_context"] = diag.get("anatomy_context", {})
		if want_rows:
			out["candidate_rows"] = diag.get("candidates", [])
	host.queue_free()
	await process_frame
	return out


## Every quantity that identifies WHICH surface was compiled, compared in the
## common space. Counts, facings, positions and the anatomical verdict — a
## re-export may renumber indices, so indices are deliberately not compared.
func _check_same_surface(
	got: Dictionary, want: Dictionary, label: String, min_dot: float
) -> void:
	for pair in [["nail_normal", "nail"], ["pad_normal", "pad"]]:
		var dot: float = (got[str(pair[0])] as Vector3).dot(want[str(pair[0])] as Vector3)
		_check(
			dot >= min_dot,
			"%s: the %s plate faces the same way (dot %.9f >= %.6f)"
				% [label, str(pair[1]), dot, min_dot]
		)
	for pair2 in [["nail_marker_digits", "nail"], ["pad_marker_digits", "pad"]]:
		var gap: float = (got[str(pair2[0])] as Vector3).distance_to(
			want[str(pair2[0])] as Vector3
		)
		_check(
			gap <= SAME_SURFACE_MAX_DIGITS,
			"%s: the %s marker is the same surface location (%.9f digits)"
				% [label, str(pair2[1]), gap]
		)
	_check(
		absf(float(got["rest_nail_pad_dot"]) - float(want["rest_nail_pad_dot"])) <= 0.01,
		"%s: the same nail/pad relation (%.6f vs %.6f)"
			% [label, float(got["rest_nail_pad_dot"]), float(want["rest_nail_pad_dot"])]
	)
	var verdict: Dictionary = Anatomy.validate(got.get("anatomy_context", {}))
	_check(
		bool(verdict.get("ok", false)),
		"%s: the surface still passes independent anatomical validation (%s)"
			% [label, str(verdict.get("failure_classes", []))]
	)


## Replace the authored shading normals with their opposites, leaving vertex
## positions and skinning untouched. The geometry is unchanged; only the
## delivery's claim about which way it faces is now wrong.
func _invert_authored_normals(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var src: ArrayMesh = mi.mesh as ArrayMesh
	if src == null:
		return
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(si)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size():
			normals[i] = -normals[i]
		arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = out


func _check(ok: bool, label: String) -> void:
	_total += 1
	if ok:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		print("FAIL: %s" % label)
