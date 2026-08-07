# Headless: godot --headless --path game -s res://presentation/tests/test_world_units_locomotion.gd
#
# N7f unit locomotion (presentation-only): the authoritative unit root
# snaps to its new anchor immediately while the visual ModelRoot glides one
# straight segment at LOCOMOTION_SPEED_UNITS_PER_SEC; semantic Walking
# plays while moving and Idle_3 resumes on arrival; the ModelRoot stays
# UPRIGHT (world +Y, yaw only) and the EFFECTIVE rendered forward (the
# whole chain: ModelRoot yaw x authoring-convention correction x rig) points
# along the horizontal movement direction and is retained after arrival;
# glide height samples the injected surface sampler with an anchor-lerp
# fallback; terrain contact is skeletal (WorldUnitLegGrounder: independent
# per-foot top-surface targets, vertical pelvis adjustment, analytic
# two-bone knee bend, safe IK bounds, preserved bone lengths); spawn snaps;
# identical reapply never restarts; mid-glide retargets are continuous;
# removal cancels cleanly; the final pose is EXACTLY the anchor pose.
# Fast — no terrain build, no networking.
extends SceneTree

const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldUnitLegGrounderScript = preload("res://presentation/world/world_unit_leg_grounder.gd")

# Anchor heights sit exactly on the ramp h(x, z) = 0.2x + 0.1z, so anchor
# poses and sampled poses agree at segment endpoints.
const ANCHORS := {
	Vector2i(0, 0): Vector3(0.0, 0.0, 0.0),
	Vector2i(1, 0): Vector3(2.0, 0.4, 0.0),
	Vector2i(2, 0): Vector3(4.0, 0.8, 0.0),
	Vector2i(0, 1): Vector3(0.0, 0.2, 2.0),
	Vector2i(1, 1): Vector3(2.0, 0.6, 2.0),
}
# Audited remapped GLB clips (warrior_3d_animation_remap.gd).
const SETTLER_WALK_CLIP := "Running"
const SETTLER_IDLE_CLIP := "Hit_Reaction_1"
const WARRIOR_WALK_CLIP := "Idle_02"
const WARRIOR_IDLE_CLIP := "Combat_Stance"

const SPEED: float = WorldUnitsViewScript.LOCOMOTION_SPEED_UNITS_PER_SEC
const EPS := 0.0001

var _total := 0
var _any_fail := false


# Deterministic synthetic top-surface sampler: the ramp plus a mid-segment
# hump that vanishes at every anchor — a straight anchor-lerp CANNOT
# reproduce mid-segment heights, so the glide provably uses the sampler.
class RampSampler:
	extends RefCounted

	func height_at(x: float, z: float) -> float:
		return 0.2 * x + 0.1 * z + 0.25 * sin(PI * x / 2.0)

	func sample(x: float, z: float, _y_hint: float) -> Dictionary:
		return {"ok": true, "height": height_at(x, z), "normal": Vector3(-0.2, 1.0, -0.1).normalized()}


# Grounding samplers: heights measured from the model plane at y=0.
class LinearGroundSampler:
	extends RefCounted
	var base := 0.0
	var slope_x := 0.0

	func _init(base_in: float, slope_in: float) -> void:
		base = base_in
		slope_x = slope_in

	func height_at(x: float, _z: float) -> float:
		return base + slope_x * x

	func sample(x: float, z: float, _y_hint: float) -> Dictionary:
		return {"ok": true, "height": height_at(x, z), "normal": Vector3.UP}


class MissSampler:
	extends RefCounted

	func sample(_x: float, _z: float, _y_hint: float) -> Dictionary:
		return {"ok": false, "height": 0.0, "normal": Vector3.UP}


# Counts engine-driven post-animation modifier invocations.
class CountingGrounder:
	extends WorldUnitLegGrounderScript
	var calls := 0

	func _process_modification() -> void:
		calls += 1


func _units(settler_pos: Array, warrior_pos: Array) -> Array:
	return [
		{"id": 1, "owner_id": 11, "position": settler_pos, "type_id": "settler"},
		{"id": 2, "owner_id": 22, "position": warrior_pos, "type_id": "warrior"},
	]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var sampler := RampSampler.new()

	# --- deterministic yaw-only orientation math ------------------------------
	var yaw_a: Basis = WorldUnitsViewScript.locomotion_yaw(Vector3(1, 0, 0))
	var yaw_b: Basis = WorldUnitsViewScript.locomotion_yaw(Vector3(1, 0, 0))
	_check(yaw_a == yaw_b, "yaw math is deterministic (identical inputs, identical basis)")
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 1).normalized()]:
		var yb: Basis = WorldUnitsViewScript.locomotion_yaw(dir)
		_check(_is_orthonormal(yb), "yaw basis orthonormal for dir %s" % str(dir))
		_check(yb.y.is_equal_approx(Vector3.UP), "yaw basis stays upright (+Y) for dir %s" % str(dir))
		_check((-yb.z).is_equal_approx(Vector3(dir.x, 0.0, dir.z).normalized()), "-Z follows movement for dir %s" % str(dir))
	_check(
		WorldUnitsViewScript.locomotion_yaw(Vector3.ZERO) == Basis.IDENTITY,
		"degenerate direction yields the identity yaw"
	)
	# Tilted input directions only yaw (no pitch/roll from vertical parts).
	_check(
		WorldUnitsViewScript.locomotion_yaw(Vector3(1, 5, 0)).y.is_equal_approx(Vector3.UP),
		"vertical movement components never tilt the body"
	)

	# --- grounder static math (pelvis, safe IK bounds, knee, bone lengths) ---
	_check(
		absf(WorldUnitLegGrounderScript.pelvis_offset(-0.1, 0.05, 0.5) - (-0.1)) < EPS,
		"pelvis follows the lower foot target"
	)
	_check(
		absf(WorldUnitLegGrounderScript.pelvis_offset(-2.0, 1.0, 0.15) - (-0.15)) < EPS,
		"pelvis adjustment is clamped to the safe bound"
	)
	var hip := Vector3(0, 10, 0)
	var knee0 := Vector3(0, 5.5, 1.0)
	var foot0 := Vector3(0, 1, 0)
	var l1 := (knee0 - hip).length()
	var l2 := (foot0 - knee0).length()
	var far_target := hip + Vector3(0, -100, 0)
	var clamped: Vector3 = WorldUnitLegGrounderScript.clamped_reach_target(hip, far_target, l1, l2)
	_check(
		(clamped - hip).length() <= l1 + l2,
		"unreachable target is clamped inside the leg reach (safe IK bound)"
	)
	var near_target := hip + Vector3(0, -0.001, 0)
	var clamped2: Vector3 = WorldUnitLegGrounderScript.clamped_reach_target(hip, near_target, l1, l2)
	_check(
		(clamped2 - hip).length() >= absf(l1 - l2),
		"degenerate-near target is clamped outside the fold limit (safe IK bound)"
	)
	var lift_target := WorldUnitLegGrounderScript.clamped_reach_target(hip, foot0 + Vector3(0, 2.0, 0), l1, l2)
	var knee1: Vector3 = WorldUnitLegGrounderScript.knee_position(hip, knee0, lift_target, l1, l2, Vector3(0, 0, 1))
	_check(
		absf((knee1 - hip).length() - l1) < 0.001 and absf((lift_target - knee1).length() - l2) < 0.001,
		"analytic knee preserves both bone lengths at the target"
	)
	_check(
		knee1.z > 0.0,
		"knee bends on its current bend side (no direction flip)"
	)
	var arc := WorldUnitLegGrounderScript.shortest_arc(Vector3(1, 0, 0), Vector3(0, 1, 0))
	_check(
		(arc * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 1, 0)),
		"shortest-arc rotation carries the source onto the target direction"
	)

	# --- first placement snaps ------------------------------------------------
	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_process(false)  # tests drive advance_locomotion deterministically
	view.set_surface_sampler(sampler)
	view.set_tile_anchors(ANCHORS)
	view.apply_snapshot_units(_units([0, 0], [0, 1]))
	_check(view.unit_count() == 2, "both units render")
	_check(not view.is_unit_moving(1), "initial spawn snaps (no locomotion)")
	var settler_root: Node3D = view.root_for_unit(1)
	var settler_model: Node3D = settler_root.get_node("ModelRoot")
	_check(settler_model.position == Vector3.ZERO, "spawned ModelRoot offset is exactly zero")
	_check(settler_root.position == ANCHORS[Vector2i(0, 0)], "spawned root sits exactly at its anchor")
	var settler_player: AnimationPlayer = view.animation_player_for_unit(1)
	_check(settler_player != null, "settler has an AnimationPlayer")
	_check(settler_player.current_animation == SETTLER_IDLE_CLIP, "settler idles after spawn")
	view.advance_locomotion(0.5)
	_check(settler_model.position == Vector3.ZERO, "advancing without a move changes nothing")

	# --- effective rendered forward at spawn (whole transform chain) ---------
	var fwd0 := _effective_forward(settler_root)
	_check(
		fwd0.dot(Vector3(0, 0, -1)) > 0.99,
		"spawn: effective rendered forward is world -Z (locked convention)"
	)

	# --- rig binding for both unit types --------------------------------------
	for probe in [[1, "settler"], [2, "warrior"]]:
		var g = view.grounder_for_unit(int(probe[0]))
		_check(g != null and g.is_bound(), "%s leg grounder binds its rig (Hips + both leg chains)" % str(probe[1]))

	# --- accepted move: root immediate, visual glides, Walking plays ----------
	var start_anchor: Vector3 = ANCHORS[Vector2i(0, 0)]
	var mid_anchor: Vector3 = ANCHORS[Vector2i(1, 0)]
	view.apply_snapshot_units(_units([1, 0], [0, 1]))
	_check(settler_root.position == mid_anchor, "root snaps to the new anchor immediately")
	_check(view.is_unit_moving(1), "visual locomotion is active after the move")
	_check(
		view.visual_position_for_unit(1).is_equal_approx(start_anchor),
		"visual starts exactly where it was (no teleport)"
	)
	_check(settler_player.current_animation == SETTLER_WALK_CLIP, "semantic Walking plays while moving")
	var move_basis: Basis = WorldUnitsViewScript.locomotion_yaw(Vector3(1, 0, 0))
	_check(
		_rotation_of(settler_model).is_equal_approx(move_basis),
		"mover yaws toward the destination"
	)
	_check(
		_rotation_of(settler_model).y.is_equal_approx(Vector3.UP),
		"ModelRoot stays upright while moving (yaw only, no slope tilt)"
	)
	_check(
		settler_model.scale.is_equal_approx(Vector3.ONE * 0.5),
		"ModelRoot keeps the locked 0.5 scale while oriented"
	)
	_check(
		_effective_forward(settler_root).dot(Vector3(1, 0, 0)) > 0.99,
		"effective rendered forward points along +X movement (no moonwalk)"
	)

	# --- grounded mid-segment glide height (sampler-provided) -----------------
	var duration: float = start_anchor.distance_to(Vector3(mid_anchor.x, start_anchor.y, mid_anchor.z)) / SPEED
	view.advance_locomotion(duration * 0.5)
	var half_pos: Vector3 = view.visual_position_for_unit(1)
	_check(absf(half_pos.x - 1.0) < EPS and absf(half_pos.z) < EPS, "half-way visual XZ is on the segment")
	_check(
		absf(half_pos.y - sampler.height_at(half_pos.x, half_pos.z)) < EPS,
		"glide height rides the SAMPLED surface mid-segment (not the anchor lerp)"
	)
	_check(absf(half_pos.y - 0.45) < EPS, "mid-segment hump height proves the sampler is used")
	_check(
		_rotation_of(settler_model).y.is_equal_approx(Vector3.UP),
		"mid-glide body stays upright on the slope (grounding is skeletal, not body tilt)"
	)

	# --- identical reapply mid-glide never restarts ----------------------------
	var before_reapply: Vector3 = view.visual_position_for_unit(1)
	view.apply_snapshot_units(_units([1, 0], [0, 1]))
	_check(
		view.visual_position_for_unit(1).is_equal_approx(before_reapply),
		"identical snapshot reapply leaves the glide untouched"
	)
	_check(settler_player.current_animation == SETTLER_WALK_CLIP, "identical reapply never restarts the clip")
	view.advance_locomotion(duration * 0.25)
	_check(
		absf(view.visual_position_for_unit(1).x - 1.5) < EPS,
		"glide progress was preserved across the reapply (75% of the segment)"
	)

	# --- mid-glide retarget: deterministic, continuous, no duplicates ---------
	var far_anchor: Vector3 = ANCHORS[Vector2i(2, 0)]
	var before_retarget: Vector3 = view.visual_position_for_unit(1)
	view.apply_snapshot_units(_units([2, 0], [0, 1]))
	_check(view.unit_count() == 2, "retarget creates no duplicate roots")
	_check(settler_root.position == far_anchor, "retargeted root snaps to the newest anchor")
	_check(
		view.visual_position_for_unit(1).is_equal_approx(before_retarget),
		"retarget continues from the in-flight visual position (no visible teleport)"
	)
	_check(view.is_unit_moving(1), "retargeted locomotion is active")
	_check(settler_player.current_animation == SETTLER_WALK_CLIP, "Walking continues across the retarget")

	# --- arrival: exact final-anchor pose, facing retained, idle resumes ------
	view.advance_locomotion(60.0)
	_check(not view.is_unit_moving(1), "locomotion ends on arrival")
	_check(settler_model.position == Vector3.ZERO, "final ModelRoot offset is EXACTLY zero")
	_check(settler_root.position == far_anchor, "final root position is EXACTLY the anchor")
	_check(settler_player.current_animation == SETTLER_IDLE_CLIP, "semantic Idle_3 resumes after arrival")
	var arrival_basis: Basis = _rotation_of(settler_model)
	_check(arrival_basis.is_equal_approx(move_basis), "movement facing is retained after arrival")
	_check(
		_effective_forward(settler_root).dot(Vector3(1, 0, 0)) > 0.99,
		"effective rendered forward is retained after arrival"
	)
	view.advance_locomotion(1.0)
	_check(settler_model.position == Vector3.ZERO, "post-arrival advance changes nothing")
	_check(_rotation_of(settler_model).is_equal_approx(arrival_basis), "post-arrival facing stays put")
	view.apply_snapshot_units(_units([2, 0], [0, 1]))
	_check(not view.is_unit_moving(1), "reapply after arrival starts no new glide")
	_check(settler_player.current_animation == SETTLER_IDLE_CLIP, "reapply after arrival keeps idling")

	# --- a second movement direction: effective forward follows ---------------
	view.apply_snapshot_units(_units([1, 1], [0, 1]))
	var diag_dir := Vector3(-2.0, 0.0, 2.0).normalized()
	_check(
		_effective_forward(settler_root).dot(diag_dir) > 0.99,
		"effective rendered forward follows a diagonal (-X,+Z) move"
	)
	view.advance_locomotion(60.0)
	_check(
		_effective_forward(settler_root).dot(diag_dir) > 0.99,
		"diagonal facing is retained after arrival"
	)

	# --- warrior clips use its own remap ---------------------------------------
	var warrior_player: AnimationPlayer = view.animation_player_for_unit(2)
	_check(warrior_player.current_animation == WARRIOR_IDLE_CLIP, "warrior idles before moving")
	view.apply_snapshot_units(_units([1, 1], [1, 1]))  # warrior (0,1) -> (1,1): +X move
	_check(warrior_player.current_animation == WARRIOR_WALK_CLIP, "warrior Walking uses its remapped clip")
	_check(
		_effective_forward(view.root_for_unit(2)).dot(Vector3(1, 0, 0)) > 0.9,
		"warrior effective rendered forward also follows the movement"
	)

	# --- removal mid-glide cancels cleanly --------------------------------------
	view.apply_snapshot_units([_units([1, 1], [1, 1])[0]])
	await process_frame
	_check(view.unit_count() == 1, "removed unit frees its root mid-glide")
	_check(not view.is_unit_moving(2), "removal cancels the in-flight locomotion")
	view.advance_locomotion(0.5)
	_check(view.unit_count() == 1, "advancing after a removal is safe")

	# --- fallback without a sampler: anchor-height interpolation ----------------
	var plain = WorldUnitsViewScript.new()
	root.add_child(plain)
	plain.set_process(false)
	plain.set_tile_anchors(ANCHORS)
	plain.apply_snapshot_units([_units([0, 0], [0, 1])[0]])
	plain.apply_snapshot_units([_units([1, 0], [0, 1])[0]])
	plain.advance_locomotion(duration * 0.5)
	var fallback_pos: Vector3 = plain.visual_position_for_unit(1)
	_check(
		absf(fallback_pos.y - 0.2) < EPS,
		"without a sampler the glide height falls back to the anchor lerp"
	)
	var plain_model: Node3D = (plain.root_for_unit(1) as Node3D).get_node("ModelRoot")
	_check(
		_rotation_of(plain_model).y.is_equal_approx(Vector3.UP),
		"fallback keeps the upright yaw-only orientation"
	)

	# --- skeletal grounding application (deterministic rest pose) ---------------
	# Fresh view, no frames processed after creation, so bone poses stay at
	# the deterministic rest pose while grounding is applied directly.
	var gview = WorldUnitsViewScript.new()
	root.add_child(gview)
	gview.set_process(false)
	gview.set_tile_anchors(ANCHORS)
	gview.apply_snapshot_units([_units([0, 0], [0, 1])[0]])
	var g_root: Node3D = gview.root_for_unit(1)
	var grounder = gview.grounder_for_unit(1)
	_check(grounder != null and grounder.is_bound(), "grounding view: settler rig bound")
	var skel: Skeleton3D = _find_skeleton(g_root)
	var hips_i := skel.find_bone("Hips")
	var lfoot_i := skel.find_bone("LeftFoot")
	var rfoot_i := skel.find_bone("RightFoot")
	var lknee_i := skel.find_bone("LeftLeg")
	var lhip_i := skel.find_bone("LeftUpLeg")

	# Flat ground exactly on the plane: grounding must be a no-op.
	gview.set_surface_sampler(LinearGroundSampler.new(0.0, 0.0))
	var hips_before: Vector3 = _bone_world(skel, hips_i)
	var lfoot_before: Vector3 = _bone_world(skel, lfoot_i)
	grounder.apply_grounding_now()
	_check(
		_bone_world(skel, hips_i).is_equal_approx(hips_before)
			and _bone_world(skel, lfoot_i).is_equal_approx(lfoot_before),
		"flat ground on the plane leaves the animated pose untouched"
	)

	# Sampler miss: grounding stays inert (never a guessed adjustment).
	gview.set_surface_sampler(MissSampler.new())
	grounder.apply_grounding_now()
	_check(
		_bone_world(skel, hips_i).is_equal_approx(hips_before),
		"sampler miss keeps the animated pose (fail quiet, no guess)"
	)

	# Cross-slope under the feet: pelvis follows the lower target, each foot
	# reaches its OWN sampled height, bone lengths stay exact.
	var slope := LinearGroundSampler.new(0.03, 0.4)
	gview.set_surface_sampler(slope)
	var lf0: Vector3 = _bone_world(skel, lfoot_i)
	var rf0: Vector3 = _bone_world(skel, rfoot_i)
	var d_left: float = slope.height_at(lf0.x, lf0.z)  # plane_y = 0 at this anchor
	var d_right: float = slope.height_at(rf0.x, rf0.z)
	var l1_before: float = (skel.get_bone_global_pose(lknee_i).origin - skel.get_bone_global_pose(lhip_i).origin).length()
	var l2_before: float = (skel.get_bone_global_pose(lfoot_i).origin - skel.get_bone_global_pose(lknee_i).origin).length()
	grounder.apply_grounding_now()
	var lf1: Vector3 = _bone_world(skel, lfoot_i)
	var rf1: Vector3 = _bone_world(skel, rfoot_i)
	_check(
		absf((lf1.y - lf0.y) - d_left) < 0.02,
		"left foot reaches its own terrain target (delta %.3f)" % d_left
	)
	_check(
		absf((rf1.y - rf0.y) - d_right) < 0.02,
		"right foot reaches its own terrain target (delta %.3f)" % d_right
	)
	_check(
		absf(d_left - d_right) > 0.001,
		"the two foot targets are genuinely independent in this scenario"
	)
	var hips_after: Vector3 = _bone_world(skel, hips_i)
	var expected_pelvis: float = minf(d_left, d_right)
	_check(
		absf((hips_after.y - hips_before.y) - expected_pelvis) < 0.01,
		"pelvis adjusts vertically by the lower foot target (%.3f)" % expected_pelvis
	)
	var l1_after: float = (skel.get_bone_global_pose(lknee_i).origin - skel.get_bone_global_pose(lhip_i).origin).length()
	var l2_after: float = (skel.get_bone_global_pose(lfoot_i).origin - skel.get_bone_global_pose(lknee_i).origin).length()
	_check(
		absf(l1_after - l1_before) < 0.01 and absf(l2_after - l2_before) < 0.01,
		"two-bone adjustment preserves both leg bone lengths"
	)

	# Extreme target: adjustments stay inside the safe bounds and finite.
	var gview2 = WorldUnitsViewScript.new()
	root.add_child(gview2)
	gview2.set_process(false)
	gview2.set_tile_anchors(ANCHORS)
	gview2.apply_snapshot_units([_units([0, 0], [0, 1])[0]])
	var skel2: Skeleton3D = _find_skeleton(gview2.root_for_unit(1))
	var grounder2 = gview2.grounder_for_unit(1)
	var hips2_before: Vector3 = _bone_world(skel2, skel2.find_bone("Hips"))
	var lfoot2_before: Vector3 = _bone_world(skel2, skel2.find_bone("LeftFoot"))
	gview2.set_surface_sampler(LinearGroundSampler.new(10.0, 0.0))
	grounder2.apply_grounding_now()
	var hips2_after: Vector3 = _bone_world(skel2, skel2.find_bone("Hips"))
	var lfoot2_after: Vector3 = _bone_world(skel2, skel2.find_bone("LeftFoot"))
	var leg_world: float = (
		(skel2.global_transform.basis * (
			skel2.get_bone_global_pose(skel2.find_bone("LeftLeg")).origin
			- skel2.get_bone_global_pose(skel2.find_bone("LeftUpLeg")).origin
		)).length()
		+ (skel2.global_transform.basis * (
			skel2.get_bone_global_pose(skel2.find_bone("LeftFoot")).origin
			- skel2.get_bone_global_pose(skel2.find_bone("LeftLeg")).origin
		)).length()
	)
	var pelvis_moved: float = hips2_after.y - hips2_before.y
	var foot_moved: float = lfoot2_after.y - lfoot2_before.y
	_check(
		pelvis_moved <= leg_world * WorldUnitLegGrounderScript.MAX_PELVIS_RATIO + 0.01,
		"extreme target: pelvis adjustment respects the safe bound"
	)
	_check(
		foot_moved <= pelvis_moved + leg_world * WorldUnitLegGrounderScript.MAX_FOOT_RAISE_RATIO + 0.02,
		"extreme target: foot raise respects the safe IK bound"
	)
	_check(
		lfoot2_after.is_finite() and hips2_after.is_finite(),
		"extreme target: pose stays finite (no IK blow-up)"
	)

	# --- engine invocation: the modifier runs post-animation ------------------
	var counting := CountingGrounder.new()
	counting.name = "CountingGrounder"
	skel.add_child(counting)
	await process_frame
	await process_frame
	_check(counting.calls > 0, "SkeletonModifier3D grounding runs during engine frames")

	view.queue_free()
	plain.queue_free()
	gview.queue_free()
	gview2.queue_free()
	await process_frame

	print("WorldUnitsLocomotion tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)


# World position of one bone under the CURRENT pose.
static func _bone_world(skel: Skeleton3D, bone_idx: int) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(bone_idx).origin


# EFFECTIVE rendered forward of a unit: the horizontal toe-vs-ankle rest
# direction of both feet pushed through the whole live transform chain
# (root -> ModelRoot yaw/scale -> authoring-convention correction ->
# armature -> skeleton). Pose-independent (rest offsets), so it measures
# exactly what the -Z facing contract promises the viewer sees.
static func _effective_forward(unit_root: Node3D) -> Vector3:
	var skel := _find_skeleton(unit_root)
	if skel == null:
		return Vector3.ZERO
	var rests: Array = []
	for i in skel.get_bone_count():
		var g: Transform3D = skel.get_bone_rest(i)
		var p := skel.get_bone_parent(i)
		if p >= 0:
			g = (rests[p] as Transform3D) * g
		rests.append(g)
	var fwd := Vector3.ZERO
	for pair in [["LeftFoot", "LeftToeBase"], ["RightFoot", "RightToeBase"]]:
		var fi := skel.find_bone(str(pair[0]))
		var ti := skel.find_bone(str(pair[1]))
		if fi < 0 or ti < 0:
			return Vector3.ZERO
		fwd += skel.global_transform.basis * ((rests[ti] as Transform3D).origin - (rests[fi] as Transform3D).origin)
	fwd.y = 0.0
	return fwd.normalized()


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child as Node)
		if found != null:
			return found
	return null


# Pure rotation part of the ModelRoot basis (scale divided out).
static func _rotation_of(model_root: Node3D) -> Basis:
	return model_root.basis.orthonormalized()


static func _is_orthonormal(b: Basis) -> bool:
	return (
		absf(b.x.length() - 1.0) < 0.0001
		and absf(b.y.length() - 1.0) < 0.0001
		and absf(b.z.length() - 1.0) < 0.0001
		and absf(b.x.dot(b.y)) < 0.0001
		and absf(b.x.dot(b.z)) < 0.0001
		and absf(b.y.dot(b.z)) < 0.0001
		and b.x.cross(b.y).is_equal_approx(b.z)
	)


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS %s" % label)
	else:
		_any_fail = true
		print("FAIL %s" % label)
