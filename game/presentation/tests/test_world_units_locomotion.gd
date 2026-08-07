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
# per-foot top-surface targets, JOINT two-leg pelvis solve with reach
# feasibility intervals, analytic two-bone knee bend toward the rig-derived
# ANATOMICAL POLE — never the current possibly-straight knee — extension
# margins, preserved bone lengths, whole-foot sole alignment toward each
# foot's own sampled normal with anatomical clamps and frame-rate-
# independent blending, and pose-derived uphill swing clearance that is
# zero at takeoff/landing); the uphill sections drive BOTH shipped rigs
# through their ACTUAL remapped walking clips across flat, shallow,
# medium, steep and downhill slopes and are the regression for the
# steep-uphill backward-knee snap; spawn snaps; identical reapply never
# restarts; mid-glide retargets are continuous; removal cancels cleanly;
# the final pose is EXACTLY the anchor pose.
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


# Plane rising along -Z (uphill AHEAD of a spawn-facing unit): h = base
# + slope * (-z), with the TRUE plane normal so sole alignment is testable.
class ZSlopeSampler:
	extends RefCounted
	var base := 0.0
	var slope := 0.0

	func _init(base_in: float, slope_in: float) -> void:
		base = base_in
		slope = slope_in

	func height_at(_x: float, z: float) -> float:
		return base + slope * (-z)

	func normal() -> Vector3:
		return Vector3(0.0, 1.0, slope).normalized()

	func sample(x: float, z: float, _y_hint: float) -> Dictionary:
		return {"ok": true, "height": height_at(x, z), "normal": normal()}


# General inclined plane through (ox, base, oz) with gradient (gx, gz):
# h = base + gx*(x-ox) + gz*(z-oz), true unit normal (-gx, 1, -gz)/|.| —
# the fixture for the post-alignment sole-plane contact invariant across
# slope directions (including normals with BOTH X and Z components).
class PlaneSampler:
	extends RefCounted
	var base := 0.0
	var gx := 0.0
	var gz := 0.0
	var ox := 0.0
	var oz := 0.0

	func _init(base_in: float, gx_in: float, gz_in: float, ox_in: float = 0.0, oz_in: float = 0.0) -> void:
		base = base_in
		gx = gx_in
		gz = gz_in
		ox = ox_in
		oz = oz_in

	func height_at(x: float, z: float) -> float:
		return base + gx * (x - ox) + gz * (z - oz)

	func normal() -> Vector3:
		return Vector3(-gx, 1.0, -gz).normalized()

	func sample(x: float, z: float, _y_hint: float) -> Dictionary:
		return {"ok": true, "height": height_at(x, z), "normal": normal()}


# Different terrain normal per world X sign (the two feet straddle x=0),
# flat heights — isolates per-foot INDEPENDENT normal sampling.
class SplitNormalSampler:
	extends RefCounted

	func normal_at(x: float) -> Vector3:
		if x >= 0.0:
			return Vector3(0.18, 1.0, 0.0).normalized()
		return Vector3(-0.18, 1.0, 0.0).normalized()

	func sample(x: float, _z: float, _y_hint: float) -> Dictionary:
		return {"ok": true, "height": 0.0, "normal": normal_at(x)}


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

	# --- grounder static math (joint pelvis, safe IK margins, pole knee) ---
	# Joint pelvis: baseline (lower target) passes through when both legs
	# can still reach; it is clamped into the intersection otherwise; a
	# conflict resolves to the midpoint; the absolute bound always applies.
	var iv_wide := Vector2(-1.0, 1.0)
	_check(
		absf(WorldUnitLegGrounderScript.joint_pelvis_offset(-0.1, iv_wide, iv_wide, 0.5) - (-0.1)) < EPS,
		"joint pelvis follows the lower-target baseline when feasible"
	)
	_check(
		absf(WorldUnitLegGrounderScript.joint_pelvis_offset(-0.9, Vector2(-0.3, 1.0), iv_wide, 0.5) - (-0.3)) < EPS,
		"joint pelvis is clamped into the reach-feasibility intersection"
	)
	_check(
		absf(WorldUnitLegGrounderScript.joint_pelvis_offset(0.0, Vector2(-0.4, -0.2), Vector2(0.2, 0.4), 0.5) - 0.0) < EPS,
		"conflicting reach intervals resolve to the midpoint compromise"
	)
	_check(
		absf(WorldUnitLegGrounderScript.joint_pelvis_offset(-2.0, Vector2(-3.0, 3.0), Vector2(-3.0, 3.0), 0.15) - (-0.15)) < EPS,
		"joint pelvis respects the absolute safety bound"
	)
	# Reach-feasibility interval: symmetric around the shifted target and
	# degenerate when the horizontal offset alone consumes the reach.
	var iv: Vector2 = WorldUnitLegGrounderScript.pelvis_interval(
		Vector3(0.0, -0.6, 0.0), Vector3.UP, 0.2, 1.0
	)
	_check(
		absf(iv.x - (-1.4)) < EPS and absf(iv.y - 0.6) < EPS,
		"pelvis reach interval is centered on the shifted target"
	)
	var iv_deg: Vector2 = WorldUnitLegGrounderScript.pelvis_interval(
		Vector3(2.0, -0.1, 0.0), Vector3.UP, 0.0, 1.0
	)
	_check(absf(iv_deg.x - iv_deg.y) < EPS, "out-of-reach horizontal offset degenerates the interval")

	var hip := Vector3(0, 10, 0)
	var knee0 := Vector3(0, 5.5, 1.0)
	var foot0 := Vector3(0, 1, 0)
	var l1 := (knee0 - hip).length()
	var l2 := (foot0 - knee0).length()
	var full := l1 + l2
	var far_target := hip + Vector3(0, -100, 0)
	var clamped: Vector3 = WorldUnitLegGrounderScript.clamped_reach_target(hip, far_target, l1, l2)
	_check(
		(clamped - hip).length() <= full * WorldUnitLegGrounderScript.REACH_MAX_RATIO + EPS,
		"unreachable target is clamped with a margin from full extension (no lock/hyperextension)"
	)
	var near_target := hip + Vector3(0, -0.001, 0)
	var clamped2: Vector3 = WorldUnitLegGrounderScript.clamped_reach_target(hip, near_target, l1, l2)
	_check(
		(clamped2 - hip).length() >= absf(l1 - l2),
		"degenerate-near target is clamped outside the fold limit (safe IK bound)"
	)
	# Pole-side knee: the bend branch comes from the EXPLICIT anatomical
	# pole — never from a (possibly straight) current knee — and stays on
	# that side for every reachable target height.
	var pole := Vector3(0, 0, 1)
	var knee1: Vector3 = WorldUnitLegGrounderScript.knee_position(
		hip, WorldUnitLegGrounderScript.clamped_reach_target(hip, foot0 + Vector3(0, 2.0, 0), l1, l2),
		l1, l2, pole, Vector3.UP
	)
	_check(
		absf((knee1 - hip).length() - l1) < 0.001,
		"analytic knee preserves the thigh bone length at the target"
	)
	var side_stable := true
	for lift_i in 17:
		var t_i: Vector3 = WorldUnitLegGrounderScript.clamped_reach_target(
			hip, foot0 + Vector3(0.3, 0.5 * float(lift_i), -0.4), l1, l2
		)
		var k_i: Vector3 = WorldUnitLegGrounderScript.knee_position(hip, t_i, l1, l2, pole, Vector3.UP)
		var axis_i := (t_i - hip).normalized()
		var bend_i := k_i - (hip + axis_i * (k_i - hip).dot(axis_i))
		if bend_i.length() > 0.01 and bend_i.dot(pole) <= 0.0:
			side_stable = false
	_check(side_stable, "pole-side knee never flips across the full target-height sweep")
	var arc := WorldUnitLegGrounderScript.shortest_arc(Vector3(1, 0, 0), Vector3(0, 1, 0))
	_check(
		(arc * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 1, 0)),
		"shortest-arc rotation carries the source onto the target direction"
	)
	# Sole alignment: ABSOLUTE contact orientation. The effective contact
	# normal is reconstructed EXACTLY for in-clamp normals (including a
	# mixed-XZ one) and clamped anatomically beyond the limits; the
	# correction maps the rig-derived rest sole normal onto it exactly
	# even from a TILTED animated pose, with the heading preserved.
	var n_mixed := Vector3(0.2, 1.0, 0.25).normalized()
	_check(
		WorldUnitLegGrounderScript.effective_contact_normal(Vector3(0, 0, -1), n_mixed)
			.is_equal_approx(n_mixed),
		"effective contact normal reconstructs an in-clamp mixed-XZ normal EXACTLY"
	)
	_check(
		WorldUnitLegGrounderScript.effective_contact_normal(Vector3(0, 0, -1), Vector3.UP)
			.is_equal_approx(Vector3.UP),
		"effective contact normal is exactly UP on flat ground"
	)
	var n_extreme := Vector3(0.0, 1.0, 4.0).normalized()
	var n_eff: Vector3 = WorldUnitLegGrounderScript.effective_contact_normal(
		Vector3(0, 0, -1), n_extreme
	)
	_check(
		not n_eff.is_equal_approx(n_extreme)
			and n_eff.angle_to(Vector3.UP)
				<= WorldUnitLegGrounderScript.FOOT_PITCH_DOWN_MAX + 0.001,
		"effective contact normal clamps extreme slopes anatomically"
	)
	var anim_tilt := Quaternion(Vector3(1, 0, 0), 0.15)  # authored-like foot tilt
	var corr_tilted: Quaternion = WorldUnitLegGrounderScript.sole_alignment_correction(
		anim_tilt, Vector3(0, 0, -1), Vector3.UP, n_mixed
	)
	_check(
		((corr_tilted * anim_tilt) * Vector3.UP).angle_to(n_mixed) < 0.001,
		"the correction maps a TILTED animated sole EXACTLY onto the terrain normal"
	)
	var head_before: Vector3 = anim_tilt * Vector3(0, 0, -1)
	var head_after: Vector3 = (corr_tilted * anim_tilt) * Vector3(0, 0, -1)
	_check(
		Vector3(head_after.x, 0.0, head_after.z).normalized()
			.dot(Vector3(head_before.x, 0.0, head_before.z).normalized()) > 0.999,
		"the correction preserves the animated foot heading (never yawed)"
	)
	var corr_flat: Quaternion = WorldUnitLegGrounderScript.sole_alignment_correction(
		anim_tilt, Vector3(0, 0, -1), Vector3.UP, Vector3.UP
	)
	_check(
		((corr_flat * anim_tilt) * Vector3.UP).angle_to(Vector3.UP) < 0.001,
		"on flat ground the correction is exactly the flatten delta (final sole normal == UP)"
	)
	# Contact weight + swing clearance: pose-derived, endpoint-zero,
	# uphill-only, bounded.
	_check(
		absf(WorldUnitLegGrounderScript.contact_weight(0.0, 1.0) - 1.0) < EPS,
		"grounded animated foot reads as full contact"
	)
	_check(
		WorldUnitLegGrounderScript.contact_weight(0.2, 1.0) < EPS,
		"a fully lifted animated foot reads as swing"
	)
	_check(
		WorldUnitLegGrounderScript.swing_clearance(0.0, 0.5, 1.0) == 0.0,
		"swing clearance is ZERO at takeoff/landing (zero animated lift)"
	)
	_check(
		WorldUnitLegGrounderScript.swing_clearance(0.06, 0.0, 1.0) == 0.0
			and WorldUnitLegGrounderScript.swing_clearance(0.06, -0.4, 1.0) == 0.0,
		"flat and downhill motion never acquire artificial lift"
	)
	_check(
		WorldUnitLegGrounderScript.swing_clearance(0.06, 0.3, 1.0) > 0.0,
		"uphill mid-swing gains positive clearance"
	)
	_check(
		WorldUnitLegGrounderScript.swing_clearance(1.0, 100.0, 1.0)
			<= WorldUnitLegGrounderScript.SWING_CLEARANCE_MAX_RATIO + EPS,
		"swing clearance is bounded relative to the leg length"
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

	# --- N7f uphill grounding: pole knee, joint pelvis, sole, swing ----------
	# Both shipped rigs, driven through their ACTUAL remapped walking clips
	# across flat, shallow, medium and steep uphill plus downhill slopes.
	# This is the regression for the steep-uphill backward-knee snap: the
	# old current-bend-side selection fails the stable-signed-knee checks.
	for rig in [["settler", SETTLER_WALK_CLIP], ["warrior", WARRIOR_WALK_CLIP]]:
		var type_id: String = rig[0]
		var walk_clip: String = rig[1]
		var rview = WorldUnitsViewScript.new()
		root.add_child(rview)
		rview.set_process(false)
		rview.set_tile_anchors(ANCHORS)
		rview.apply_snapshot_units([{
			"id": 9, "owner_id": 11, "position": [0, 0], "type_id": type_id,
		}])
		var r_root: Node3D = rview.root_for_unit(9)
		var r_model: Node3D = r_root.get_node("ModelRoot")
		var r_skel: Skeleton3D = _find_skeleton(r_root)
		var r_grounder = rview.grounder_for_unit(9)
		var r_player: AnimationPlayer = rview.animation_player_for_unit(9)
		_check(r_grounder != null and r_grounder.is_bound(), "%s: grounder binds (uphill suite)" % type_id)
		# This suite drives WALKING clips on a stationary view unit, so mark
		# the grounder as walking: stationary foot planting (N7f follow-up)
		# must not pin the gait being tested here.
		r_grounder.set_locomotion_active(true)
		var chains := {
			"L": [r_skel.find_bone("LeftUpLeg"), r_skel.find_bone("LeftLeg"), r_skel.find_bone("LeftFoot"), r_skel.find_bone("LeftToeBase")],
			"R": [r_skel.find_bone("RightUpLeg"), r_skel.find_bone("RightLeg"), r_skel.find_bone("RightFoot"), r_skel.find_bone("RightToeBase")],
		}
		# Rig-derived anatomical pole (skeleton space): horizontal rest
		# toe-vs-ankle direction — the same audit source the grounder uses.
		var poles := {}
		var rest_lengths := {}
		var rest_up_local := {}
		var rest_fwd_local := {}
		for side in ["L", "R"]:
			var ch: Array = chains[side]
			var foot_rest: Transform3D = r_skel.get_bone_global_rest(int(ch[2]))
			var toe_rest: Transform3D = r_skel.get_bone_global_rest(int(ch[3]))
			var fwd: Vector3 = toe_rest.origin - foot_rest.origin
			fwd.y = 0.0
			poles[side] = fwd.normalized()
			rest_lengths[side] = [
				(r_skel.get_bone_global_rest(int(ch[1])).origin - r_skel.get_bone_global_rest(int(ch[0])).origin).length(),
				(foot_rest.origin - r_skel.get_bone_global_rest(int(ch[1])).origin).length(),
			]
			rest_up_local[side] = foot_rest.basis.inverse() * Vector3.UP
			rest_fwd_local[side] = foot_rest.basis.inverse() * (poles[side] as Vector3)
		_check(r_player != null and r_player.has_animation(walk_clip), "%s: real walking clip available" % type_id)
		r_player.play(walk_clip)
		var clip_len: float = r_player.get_animation(walk_clip).length
		var model_basis_before: Basis = r_model.basis
		# The unit faces world -Z at spawn; a slope along -Z is uphill AHEAD.
		for scenario in [
			["flat", 0.0], ["shallow", 0.08], ["medium", 0.2],
			["steep", 0.42], ["downhill", -0.25],
		]:
			var s_name: String = scenario[0]
			var s_slope: float = scenario[1]
			rview.set_surface_sampler(ZSlopeSampler.new(0.0, s_slope))
			var all_finite := true
			var lengths_ok := true
			var side_ok := true
			var margin_ok := true
			var continuity_ok := true
			var prev_bend := {"L": Vector3.ZERO, "R": Vector3.ZERO}
			for step in 25:
				r_player.seek(clip_len * float(step) / 24.0, true)
				var anim_reach := {}
				for side in ["L", "R"]:
					var ch0: Array = chains[side]
					anim_reach[side] = (
						r_skel.get_bone_global_pose(int(ch0[2])).origin
						- r_skel.get_bone_global_pose(int(ch0[0])).origin
					).length()
				r_grounder.apply_grounding_now()
				for side in ["L", "R"]:
					var ch: Array = chains[side]
					var a: Vector3 = r_skel.get_bone_global_pose(int(ch[0])).origin
					var b: Vector3 = r_skel.get_bone_global_pose(int(ch[1])).origin
					var c: Vector3 = r_skel.get_bone_global_pose(int(ch[2])).origin
					if not (a.is_finite() and b.is_finite() and c.is_finite()):
						all_finite = false
						continue
					var rl: Array = rest_lengths[side]
					if absf((b - a).length() - float(rl[0])) > 0.01 * float(rl[0]) \
							or absf((c - b).length() - float(rl[1])) > 0.01 * float(rl[1]):
						lengths_ok = false
					var full_len: float = float(rl[0]) + float(rl[1])
					# The margin bounds SOLVER-placed targets; an authored
					# pose already straighter than the margin is preserved,
					# never re-posed and never extended further.
					var reach_cap: float = maxf(
						full_len * WorldUnitLegGrounderScript.REACH_MAX_RATIO,
						minf(float(anim_reach[side]), full_len * 0.999)
					)
					if (c - a).length() > reach_cap + 0.005 * full_len:
						margin_ok = false
					var axis := (c - a).normalized()
					var bend := b - (a + axis * (b - a).dot(axis))
					if bend.length() > 0.03 * full_len:
						if bend.dot(poles[side] as Vector3) <= 0.0:
							side_ok = false
						var pb: Vector3 = prev_bend[side]
						if pb.length() > 0.03 * full_len \
								and bend.normalized().angle_to(pb.normalized()) > 1.2:
							continuity_ok = false
					prev_bend[side] = bend
			_check(all_finite, "%s/%s: every grounded pose is finite" % [type_id, s_name])
			_check(lengths_ok, "%s/%s: exact bone lengths across the whole clip" % [type_id, s_name])
			_check(side_ok, "%s/%s: knee bend side stays signed toward the anatomical pole (no backward knee)" % [type_id, s_name])
			_check(margin_ok, "%s/%s: reach keeps the extension margin (no lock/hyperextension)" % [type_id, s_name])
			_check(continuity_ok, "%s/%s: bounded knee angular continuity (no single-frame branch snap)" % [type_id, s_name])
			_check(r_model.basis.is_equal_approx(model_basis_before), "%s/%s: root stays upright/unchanged" % [type_id, s_name])

		# --- sole alignment (stance): each foot follows its OWN normal ----
		# Absolute-model contract: the applied correction equals the exact
		# sole_alignment_correction delta (full weight in stance) from the
		# animated rotation to the ABSOLUTE contact orientation, so the
		# FINAL transformed sole plane coincides with the terrain plane —
		# clip-authored foot tilt is absorbed, never transplanted.
		var stance_t := _lowest_lift_time(r_player, r_skel, int(chains["L"][2]), walk_clip, clip_len)
		var slope_sampler := ZSlopeSampler.new(0.0, 0.15)
		rview.set_surface_sampler(slope_sampler)
		var world_b: Basis = r_skel.global_transform.basis
		r_player.seek(stance_t, true)
		var anim_basis_l: Basis = r_skel.get_bone_global_pose(int(chains["L"][2])).basis
		var anim_sole_l: Vector3 = (world_b * anim_basis_l * (rest_up_local["L"] as Vector3)).normalized()
		var anim_head_l: Vector3 = world_b * anim_basis_l * (rest_fwd_local["L"] as Vector3)
		r_grounder.apply_grounding_now()
		var after_basis_l: Basis = r_skel.get_bone_global_pose(int(chains["L"][2])).basis
		var sole_l: Vector3 = (world_b * after_basis_l * (rest_up_local["L"] as Vector3)).normalized()
		var applied_corr := Quaternion(
			((world_b * after_basis_l) * (world_b * anim_basis_l).inverse()).orthonormalized()
		).normalized()
		var expected_corr: Quaternion = WorldUnitLegGrounderScript.sole_alignment_correction(
			Quaternion((world_b * anim_basis_l).orthonormalized()),
			rest_fwd_local["L"] as Vector3,
			rest_up_local["L"] as Vector3,
			slope_sampler.normal()
		)
		if applied_corr.angle_to(expected_corr) >= 0.01:
			var lf_i: int = int(chains["L"][2])
			var parent_g: Transform3D = r_skel.get_bone_global_pose(r_skel.get_bone_parent(lf_i))
			var local_global: Basis = (parent_g * r_skel.get_bone_pose(lf_i)).basis
			var local_corr: Quaternion = Quaternion(
				(world_b * local_global) * (world_b * anim_basis_l).inverse()
			).normalized()
			print("DBG %s stance_t=%f applied=%f expected=%f angle_to=%f local_corr=%f skel_id=%d" % [
				type_id, stance_t, applied_corr.get_angle(), expected_corr.get_angle(),
				applied_corr.angle_to(expected_corr), local_corr.get_angle(), r_skel.get_instance_id()])
		_check(
			applied_corr.angle_to(expected_corr) < 0.01,
			"%s: stance applies the EXACT full sole-alignment slope rotation" % type_id
		)
		_check(
			sole_l.dot(slope_sampler.normal()) > anim_sole_l.dot(Vector3.UP) - 0.002,
			"%s: stance sole follows the slope (deviation from the terrain normal never exceeds the authored flat deviation)" % type_id
		)
		# Final-geometry contract: in full contact the ACTUAL transformed
		# sole normal equals the terrain normal EXACTLY — the correction
		# absorbs the clip-authored foot tilt instead of stacking the
		# slope delta on top of it.
		_check(
			sole_l.angle_to(slope_sampler.normal()) < 0.01,
			"%s: stance FINAL sole normal equals the terrain normal (off by %.4f rad)"
				% [type_id, sole_l.angle_to(slope_sampler.normal())]
		)
		# Heading preserved (horizontal forward before vs after alignment).
		var fwd_l: Vector3 = world_b * after_basis_l * (rest_fwd_local["L"] as Vector3)
		_check(
			Vector3(fwd_l.x, 0.0, fwd_l.z).normalized().dot(Vector3(anim_head_l.x, 0.0, anim_head_l.z).normalized()) > 0.995,
			"%s: sole alignment preserves the foot heading" % type_id
		)
		# Flat ground, full contact: the FINAL sole plane coincides with
		# the ground plane exactly — the correction is exactly the small
		# flatten delta of the clip-authored stance tilt (heading kept),
		# never a slope rotation stacked onto a still-tilted sole.
		rview.set_surface_sampler(ZSlopeSampler.new(0.0, 0.0))
		r_player.seek(stance_t, true)
		var flat_before: Basis = r_skel.get_bone_global_pose(int(chains["L"][2])).basis
		var flat_head: Vector3 = world_b * flat_before * (rest_fwd_local["L"] as Vector3)
		r_grounder.apply_grounding_now()
		var flat_after: Basis = r_skel.get_bone_global_pose(int(chains["L"][2])).basis
		var flat_sole: Vector3 = (world_b * flat_after * (rest_up_local["L"] as Vector3)).normalized()
		_check(
			flat_sole.angle_to(Vector3.UP) < 0.01,
			"%s: flat full contact flattens the sole exactly onto the ground plane (off by %.4f rad)"
				% [type_id, flat_sole.angle_to(Vector3.UP)]
		)
		var flat_fwd: Vector3 = world_b * flat_after * (rest_fwd_local["L"] as Vector3)
		_check(
			Vector3(flat_fwd.x, 0.0, flat_fwd.z).normalized()
				.dot(Vector3(flat_head.x, 0.0, flat_head.z).normalized()) > 0.995,
			"%s: the flat flatten delta preserves the foot heading" % type_id
		)
		# Independent per-foot normals (split sampler by world X sign): each
		# foot's FINAL sole normal moves toward ITS OWN sampled normal,
		# and the two corrections genuinely differ.
		rview.set_surface_sampler(SplitNormalSampler.new())
		r_player.seek(stance_t, true)
		var split := SplitNormalSampler.new()
		var anim_bases := {}
		var own_normals := {}
		for side in ["L", "R"]:
			var pose: Transform3D = r_skel.get_bone_global_pose(int(chains[side][2]))
			anim_bases[side] = pose.basis
			own_normals[side] = split.normal_at((r_skel.global_transform * pose.origin).x)
		r_grounder.apply_grounding_now()
		var corr_by_side := {}
		var own_ok := true
		for side in ["L", "R"]:
			var after: Basis = r_skel.get_bone_global_pose(int(chains[side][2])).basis
			var corr := Quaternion(
				((world_b * after) * (world_b * (anim_bases[side] as Basis)).inverse()).orthonormalized()
			).normalized()
			corr_by_side[side] = corr
			# Full contact expected at the stance frame for the planted
			# foot; the other foot may be partially in swing — its
			# correction must then be a partial arc TOWARD its own normal:
			# the FINAL sole normal ends closer to that foot's own sampled
			# normal than the animated one was.
			var own_n: Vector3 = own_normals[side]
			var anim_sole_s: Vector3 = (
				world_b * (anim_bases[side] as Basis) * (rest_up_local[side] as Vector3)
			).normalized()
			var after_sole_s: Vector3 = (
				world_b * after * (rest_up_local[side] as Vector3)
			).normalized()
			var improvement: float = after_sole_s.dot(own_n) - anim_sole_s.dot(own_n)
			if corr.get_angle() > 0.01 and improvement <= 0.0:
				own_ok = false
		_check(own_ok, "%s: each sole rotates toward its OWN sampled normal (independent feet)" % type_id)
		_check(
			(corr_by_side["L"] as Quaternion).angle_to(corr_by_side["R"] as Quaternion) > 0.02,
			"%s: the two feet apply genuinely different corrections" % type_id
		)

		# --- swing/contact blending + endpoint-zero uphill clearance ------
		var swing_t := _highest_lift_time(r_player, r_skel, int(chains["L"][2]), walk_clip, clip_len)
		var uphill := ZSlopeSampler.new(0.0, 0.42)
		# Flat reference at the same swing pose.
		rview.set_surface_sampler(ZSlopeSampler.new(0.0, 0.0))
		r_player.seek(swing_t, true)
		var lfoot_i2: int = int(chains["L"][2])
		var flat_anim_y: float = (r_skel.global_transform * r_skel.get_bone_global_pose(lfoot_i2).origin).y
		r_grounder.apply_grounding_now()
		var flat_ground_y: float = (r_skel.global_transform * r_skel.get_bone_global_pose(lfoot_i2).origin).y
		# Uphill at the same swing pose: the swing foot gains clearance
		# ABOVE its own terrain delta when its target is above the stance
		# foot's (uphill ahead), and the correction stays partial (blend
		# toward the landing normal, never full ground glue mid-swing).
		rview.set_surface_sampler(uphill)
		r_player.seek(swing_t, true)
		var anim_pose_w: Vector3 = r_skel.global_transform * r_skel.get_bone_global_pose(lfoot_i2).origin
		var d_swing: float = uphill.height_at(anim_pose_w.x, anim_pose_w.z)
		var rfoot_w: Vector3 = r_skel.global_transform * r_skel.get_bone_global_pose(int(chains["R"][2])).origin
		var d_stance: float = uphill.height_at(rfoot_w.x, rfoot_w.z)
		r_grounder.apply_grounding_now()
		var uphill_y: float = (r_skel.global_transform * r_skel.get_bone_global_pose(lfoot_i2).origin).y
		if d_swing > d_stance + 0.002:
			_check(
				uphill_y - (flat_ground_y + d_swing) > 0.003,
				"%s: uphill mid-swing foot gains positive clearance over the flat baseline" % type_id
			)
		else:
			# Gait phase put the swing foot below the stance foot on this
			# rig: clearance must then contribute exactly nothing.
			_check(
				absf(uphill_y - (flat_ground_y + d_swing)) < 0.02,
				"%s: no clearance without positive uphill height gain" % type_id
			)
		_check(
			absf(flat_ground_y - flat_anim_y) < 0.02,
			"%s: flat mid-swing keeps the authored trajectory (no artificial lift)" % type_id
		)

		# --- frame-rate-independent foot blending --------------------------
		var bview = WorldUnitsViewScript.new()
		root.add_child(bview)
		bview.set_process(false)
		bview.set_tile_anchors(ANCHORS)
		bview.apply_snapshot_units([{
			"id": 8, "owner_id": 11, "position": [0, 0], "type_id": type_id,
		}])
		var b_skel: Skeleton3D = _find_skeleton(bview.root_for_unit(8))
		var b_grounder = bview.grounder_for_unit(8)
		var b_player: AnimationPlayer = bview.animation_player_for_unit(8)
		b_grounder.set_locomotion_active(true)  # walking-clip-driven suite
		bview.set_surface_sampler(ZSlopeSampler.new(0.0, 0.15))
		b_player.play(walk_clip)
		b_player.seek(stance_t, true)
		var b_foot: int = b_skel.find_bone("LeftFoot")
		var anim_basis: Basis = b_skel.get_bone_global_pose(b_foot).basis
		b_grounder.apply_grounding_now(0.02)
		var partial_angle: float = Quaternion(
			(b_skel.get_bone_global_pose(b_foot).basis * anim_basis.inverse()).orthonormalized()
		).normalized().get_angle()
		for i in 40:
			b_player.seek(stance_t, true)
			b_grounder.apply_grounding_now(0.05)
		b_player.seek(stance_t, true)
		b_grounder.apply_grounding_now()
		var full_angle: float = Quaternion(
			(b_skel.get_bone_global_pose(b_foot).basis * anim_basis.inverse()).orthonormalized()
		).normalized().get_angle()
		_check(
			partial_angle < full_angle - 0.005 and partial_angle > 0.0005,
			"%s: timed foot blending is gradual (no single-frame sole snap)" % type_id
		)
		bview.queue_free()
		rview.queue_free()

	# --- N7f follow-up: sole-contact calibration + stationary planting -------
	# Regression for the two manual-gate defects: (1) the remapped idle
	# clips HOLD the feet above their rest height (measured: warrior
	# Combat_Stance ~+0.025 model units, settler Hit_Reaction_1 up to
	# ~+0.011) — a persistent hover the old animation-preserving targets
	# never corrected; (2) the same clips drift/rock the feet (up to
	# ~0.014 model units XZ per warrior loop) — planted feet must stay
	# fixed in ground space while stationary, with idle pelvis/upper-body
	# motion continuing and smooth release/replant around glides.
	for prig in [["settler", SETTLER_IDLE_CLIP, SETTLER_WALK_CLIP], ["warrior", WARRIOR_IDLE_CLIP, WARRIOR_WALK_CLIP]]:
		var p_type: String = prig[0]
		var p_idle: String = prig[1]
		var p_walk: String = prig[2]
		var pview = WorldUnitsViewScript.new()
		root.add_child(pview)
		pview.set_process(false)
		pview.set_tile_anchors(ANCHORS)
		pview.set_surface_sampler(LinearGroundSampler.new(0.0, 0.0))
		pview.apply_snapshot_units([{
			"id": 7, "owner_id": 11, "position": [0, 0], "type_id": p_type,
		}])
		var p_skel: Skeleton3D = _find_skeleton(pview.root_for_unit(7))
		var p_grounder = pview.grounder_for_unit(7)
		var p_player: AnimationPlayer = pview.animation_player_for_unit(7)
		var p_lf := p_skel.find_bone("LeftFoot")
		var p_rf := p_skel.find_bone("RightFoot")
		var p_hips := p_skel.find_bone("Hips")
		_check(
			p_grounder != null and not p_grounder.is_locomotion_active(),
			"%s: spawned unit is stationary (planting enabled)" % p_type
		)
		# Calibrated ankle contact height above the terrain (world units):
		# the audited bind-pose soles sit EXACTLY on the plane, so the rest
		# ankle height is the exact sole-contact height.
		var p_scale: float = p_skel.global_transform.basis.get_scale().y
		var rest_h := {
			"L": p_skel.get_bone_global_rest(p_lf).origin.y * p_scale,
			"R": p_skel.get_bone_global_rest(p_rf).origin.y * p_scale,
		}
		var p_clip_len: float = p_player.get_animation(p_idle).length
		p_player.play(p_idle)

		# (1) Flat terrain on the plane: the idle clip genuinely hovers the
		# feet; grounding puts each ankle at EXACTLY terrain + rest height.
		var t0: float = p_clip_len * 0.15
		p_player.seek(t0, true)
		var anim_lf_y: float = _bone_world(p_skel, p_lf).y
		var anim_rf_y: float = _bone_world(p_skel, p_rf).y
		_check(
			anim_lf_y > rest_h["L"] + 0.0005 and anim_rf_y > rest_h["R"] + 0.0005,
			"%s: the raw idle clip holds both feet ABOVE the calibrated contact height (the hover defect exists)" % p_type
		)
		p_grounder.apply_grounding_now()
		var planted_lf: Vector3 = _bone_world(p_skel, p_lf)
		var planted_rf: Vector3 = _bone_world(p_skel, p_rf)
		_check(
			absf(planted_lf.y - rest_h["L"]) < 0.003 and absf(planted_rf.y - rest_h["R"]) < 0.003,
			"%s: planted ankles sit at the calibrated sole-contact height on flat terrain (hover removed)" % p_type
		)
		var planted_lf_basis: Basis = p_skel.get_bone_global_pose(p_lf).basis.orthonormalized()

		# (2) Stationary drift: seek the idle pose that moves the raw foot
		# the most — after grounding, the planted foot must not follow it,
		# while the hips (upper body) keep animating.
		var t1: float = _max_foot_displacement_time(p_player, p_skel, p_lf, p_idle, p_clip_len, t0)
		p_player.seek(t1, true)
		var raw_drift: float = (_bone_world(p_skel, p_lf) - planted_lf).length()
		var hips_raw: Vector3 = _bone_world(p_skel, p_hips)
		p_grounder.apply_grounding_now()
		var planted_drift: float = (_bone_world(p_skel, p_lf) - planted_lf).length()
		_check(
			raw_drift > 0.0015,
			"%s: the raw idle clip genuinely drifts the foot (%.4f — the drift defect exists)" % [p_type, raw_drift]
		)
		_check(
			planted_drift < 0.002 and planted_drift < raw_drift * 0.5,
			"%s: the planted foot stays fixed in ground space (drift %.4f vs raw %.4f)" % [p_type, planted_drift, raw_drift]
		)
		_check(
			(_bone_world(p_skel, p_rf) - planted_rf).length() < 0.002,
			"%s: the other planted foot stays fixed too" % p_type
		)
		var hips_after_plant: Vector3 = _bone_world(p_skel, p_hips)
		_check(
			Vector2(hips_after_plant.x - hips_raw.x, hips_after_plant.z - hips_raw.z).length() < 0.0005
				and (hips_after_plant - _bone_world(p_skel, p_lf)).length() > 0.01,
			"%s: idle pelvis motion passes through while the legs compensate" % p_type
		)
		_check(
			Quaternion(p_skel.get_bone_global_pose(p_lf).basis.orthonormalized())
				.angle_to(Quaternion(planted_lf_basis)) < 0.01,
			"%s: the planted foot orientation is pinned (no idle rocking)" % p_type
		)

		# (3) Release: an accepted move flips the grounder's locomotion
		# gate; the feet follow the walking animation again. The visual is
		# still at the glide start, so the model plane stays at y=0 here.
		pview.apply_snapshot_units([{
			"id": 7, "owner_id": 11, "position": [1, 0], "type_id": p_type,
		}])
		_check(
			p_grounder.is_locomotion_active(),
			"%s: starting a glide releases the plants (locomotion gate on)" % p_type
		)
		p_player.play(p_walk)
		var w_len: float = p_player.get_animation(p_walk).length
		p_player.seek(w_len * 0.1, true)
		p_grounder.apply_grounding_now()
		var walk_a: Vector3 = _bone_world(p_skel, p_lf)
		p_player.seek(w_len * 0.5, true)
		p_grounder.apply_grounding_now()
		_check(
			(_bone_world(p_skel, p_lf) - walk_a).length() > 0.005,
			"%s: released feet follow the walking gait again (no residual pinning)" % p_type
		)
		pview.advance_locomotion(60.0)
		_check(
			not p_grounder.is_locomotion_active(),
			"%s: arrival re-enables planting (locomotion gate off)" % p_type
		)
		# Walking-stance calibration: at the walk clip's lowest-lift
		# (stance) pose on flat terrain the grounded ankle height follows
		# the exact contact-weighted blend from the animated height toward
		# the calibrated contact height. The gate is held on so planting
		# stays out of this walking-path math (plane is 0.4 post-arrival).
		p_grounder.set_locomotion_active(true)
		pview.set_surface_sampler(LinearGroundSampler.new(0.4, 0.0))
		var stance_w_t := _lowest_lift_time(p_player, p_skel, p_lf, p_walk, w_len)
		p_player.seek(stance_w_t, true)
		var stance_anim_y: float = _bone_world(p_skel, p_lf).y
		var p_leg_w: float = (
			(p_skel.global_transform.basis * (
				p_skel.get_bone_global_pose(p_skel.find_bone("LeftLeg")).origin
				- p_skel.get_bone_global_pose(p_skel.find_bone("LeftUpLeg")).origin
			)).length()
			+ (p_skel.global_transform.basis * (
				p_skel.get_bone_global_pose(p_lf).origin
				- p_skel.get_bone_global_pose(p_skel.find_bone("LeftLeg")).origin
			)).length()
		)
		var stance_contact: float = WorldUnitLegGrounderScript.contact_weight(
			(stance_anim_y - 0.4) - rest_h["L"], p_leg_w
		)
		p_grounder.apply_grounding_now()
		var stance_expected_y: float = lerpf(stance_anim_y, 0.4 + rest_h["L"], stance_contact)
		_check(
			absf(_bone_world(p_skel, p_lf).y - stance_expected_y) < 0.003,
			"%s: walking stance height follows the contact-weighted sole calibration" % p_type
		)
		p_grounder.set_locomotion_active(false)

		# (4) Arrival replants — on a slope the planted sole re-aligns to
		# the planted point's OWN terrain normal and stays pinned there.
		# Contact is the POST-ALIGNMENT sole-plane invariant, not a world-Y
		# offset: with d = the rig-derived signed ankle-to-sole-plane
		# distance (rest ankle height — the audited bind-pose soles sit
		# exactly on the plane), the aligned sole meets the terrain plane
		# exactly when dot(n, ankle - s) == d. The old "terrain + d"
		# vertical target gives only d * n.y of perpendicular clearance —
		# a penetration this assertion rejects (as it rejects any gap).
		var p_slope := ZSlopeSampler.new(0.4, 0.35)
		pview.set_surface_sampler(p_slope)
		p_player.play(p_idle)
		p_player.seek(t0, true)
		var slope_anim_up: Vector3 = (
			p_skel.global_transform.basis
			* p_skel.get_bone_global_pose(p_lf).basis
			* (p_skel.get_bone_global_rest(p_lf).basis.inverse() * Vector3.UP)
		).normalized()
		p_grounder.apply_grounding_now()
		var slope_lf: Vector3 = _bone_world(p_skel, p_lf)
		var slope_s := Vector3(slope_lf.x, p_slope.height_at(slope_lf.x, slope_lf.z), slope_lf.z)
		var slope_perp: float = p_slope.normal().dot(slope_lf - slope_s)
		_check(
			absf(slope_perp - rest_h["L"]) < 0.002,
			"%s: replanted aligned sole meets the slope plane exactly (perpendicular %.4f vs d %.4f — no gap, no penetration)"
				% [p_type, slope_perp, rest_h["L"]]
		)
		var slope_up: Vector3 = (
			p_skel.global_transform.basis
			* p_skel.get_bone_global_pose(p_lf).basis
			* (p_skel.get_bone_global_rest(p_lf).basis.inverse() * Vector3.UP)
		).normalized()
		_check(
			slope_up.dot(p_slope.normal()) > slope_anim_up.dot(p_slope.normal()) + 0.002,
			"%s: the planted sole aligns toward the slope normal (terrain-normal alignment preserved while planted)" % p_type
		)
		var slope_basis0: Basis = p_skel.get_bone_global_pose(p_lf).basis.orthonormalized()
		p_player.seek(t1, true)
		p_grounder.apply_grounding_now()
		_check(
			(_bone_world(p_skel, p_lf) - slope_lf).length() < 0.002
				and Quaternion(p_skel.get_bone_global_pose(p_lf).basis.orthonormalized())
					.angle_to(Quaternion(slope_basis0)) < 0.01,
			"%s: the slope plant stays fixed in position AND orientation across idle poses" % p_type
		)

		# (5) Timed replant blending: a fresh plant captures the CURRENT
		# pose (so the capture itself never snaps), then pulls a diverging
		# animated foot toward the plant anchor gradually until it
		# converges and stays put.
		pview.apply_snapshot_units([{
			"id": 7, "owner_id": 11, "position": [2, 0], "type_id": p_type,
		}])
		pview.advance_locomotion(60.0)
		pview.set_surface_sampler(LinearGroundSampler.new(0.8, 0.0))
		p_player.play(p_idle)
		p_player.seek(t1, true)
		p_grounder.apply_grounding_now(0.02)  # fresh capture AT this pose
		p_player.seek(t0, true)  # the animated pose diverges from the anchor
		p_grounder.apply_grounding_now(0.016)
		var blend_p1: Vector3 = _bone_world(p_skel, p_lf)
		for i in 40:
			p_player.seek(t0, true)
			p_grounder.apply_grounding_now(0.05)
		var blend_p2: Vector3 = _bone_world(p_skel, p_lf)
		p_player.seek(t0, true)
		p_grounder.apply_grounding_now(0.05)
		var blend_p3: Vector3 = _bone_world(p_skel, p_lf)
		_check(
			(blend_p1 - blend_p2).length() > 0.0005,
			"%s: replanting is gradual (the first timed frame is NOT already at the anchor)" % p_type
		)
		_check(
			(blend_p3 - blend_p2).length() < 0.0003,
			"%s: the timed replant converges onto a stable plant anchor" % p_type
		)

		# (6) FINAL-GEOMETRY sole-plane contact invariants across slope
		# directions. For every sampled plane (unit normal n, point s at
		# the ankle's own XZ) a grounded foot must satisfy, at once:
		#   a. dot(n, ankle - s) == d (d = rest ankle height, the
		#      rig-derived signed ankle-to-sole-plane distance);
		#   b. the ACTUAL final transformed sole normal — the post-solver
		#      foot-bone basis pushed through the rig-derived rest sole
		#      frame — equals the EFFECTIVE contact normal (the sampled
		#      normal, anatomically clamped relative to that foot's own
		#      animated heading; the separately unit-tested reconstruction
		#      is EXACT for in-clamp normals, and the flat/moderate/
		#      lateral planes below are in-clamp for every heading, so
		#      there the final sole normal must equal n itself);
		#   c. the rig-derived point on the transformed sole plane
		#      (ankle - d * final_sole_normal) lies ON the terrain plane —
		#      both gap and penetration fail.
		# (a) alone can pass while a tilted sole still intersects or gaps
		# from the terrain — (b) + (c) close that hole (the delta model
		# transplanted the clip-authored foot tilt onto every plane).
		# The unit sits at tile [2,0] (plane y = 0.8); every plane passes
		# through the anchor.
		var p_world_b: Basis = p_skel.global_transform.basis
		var p_rest_up := {
			"L": p_skel.get_bone_global_rest(p_lf).basis.inverse() * Vector3.UP,
			"R": p_skel.get_bone_global_rest(p_rf).basis.inverse() * Vector3.UP,
		}
		var p_rest_fwd := {}
		for rf_side in [["L", p_lf, "LeftToeBase"], ["R", p_rf, "RightToeBase"]]:
			var rf_rest: Transform3D = p_skel.get_bone_global_rest(int(rf_side[1]))
			var rf_fwd: Vector3 = (
				p_skel.get_bone_global_rest(p_skel.find_bone(str(rf_side[2]))).origin
				- rf_rest.origin
			)
			rf_fwd.y = 0.0
			p_rest_fwd[rf_side[0]] = rf_rest.basis.inverse() * rf_fwd.normalized()
		# Third element: the plane's slope sine stays below every anatomical
		# clamp for ANY foot heading — the effective contact normal is then
		# provably the sampled normal itself.
		for plane_case in [
			["flat", PlaneSampler.new(0.8, 0.0, 0.0, 4.0, 0.0), true],
			["moderate uphill-ahead", PlaneSampler.new(0.8, 0.0, -0.2, 4.0, 0.0), true],
			["steep uphill-ahead", PlaneSampler.new(0.8, 0.0, -0.45, 4.0, 0.0), false],
			["steep downhill-ahead", PlaneSampler.new(0.8, 0.0, 0.45, 4.0, 0.0), false],
			["lateral", PlaneSampler.new(0.8, 0.25, 0.0, 4.0, 0.0), true],
			["mixed XZ", PlaneSampler.new(0.8, 0.2, -0.3, 4.0, 0.0), false],
		]:
			var pc_name: String = plane_case[0]
			var pc_plane = plane_case[1]
			var pc_in_clamp: bool = plane_case[2]
			pview.set_surface_sampler(pc_plane)
			p_grounder.set_locomotion_active(true)  # release the old plants
			p_grounder.set_locomotion_active(false)  # fresh replant below
			p_player.play(p_idle)
			p_player.seek(t0, true)
			var pc_n: Vector3 = pc_plane.normal()
			# Pre-solve animated heading per foot (the plant capture base)
			# determines each foot's own anatomically clamped effective
			# contact normal.
			var pc_expected := {}
			for foot_case in [["L", p_lf], ["R", p_rf]]:
				var pc_anim: Basis = (
					p_world_b * p_skel.get_bone_global_pose(int(foot_case[1])).basis
				)
				pc_expected[foot_case[0]] = WorldUnitLegGrounderScript.effective_contact_normal(
					pc_anim * (p_rest_fwd[foot_case[0]] as Vector3), pc_n
				)
			p_grounder.apply_grounding_now()
			for foot_case in [["L", p_lf], ["R", p_rf]]:
				var pc_ankle: Vector3 = _bone_world(p_skel, int(foot_case[1]))
				var pc_s := Vector3(
					pc_ankle.x, pc_plane.height_at(pc_ankle.x, pc_ankle.z), pc_ankle.z
				)
				var pc_perp: float = pc_n.dot(pc_ankle - pc_s)
				var pc_d: float = rest_h[foot_case[0]]
				_check(
					absf(pc_perp - pc_d) < 0.002,
					"%s: aligned sole meets the %s plane exactly (%s: perpendicular %.4f vs d %.4f)"
						% [p_type, pc_name, foot_case[0], pc_perp, pc_d]
				)
				# (b) ACTUAL final sole normal from the post-solver basis.
				var pc_sole_n: Vector3 = (
					p_world_b
					* p_skel.get_bone_global_pose(int(foot_case[1])).basis
					* (p_rest_up[foot_case[0]] as Vector3)
				).normalized()
				var pc_want: Vector3 = pc_expected[foot_case[0]]
				if pc_in_clamp:
					_check(
						pc_want.is_equal_approx(pc_n),
						"%s: the %s plane is in-clamp for this heading — its effective contact normal IS n (%s)"
							% [p_type, pc_name, foot_case[0]]
					)
				_check(
					pc_sole_n.angle_to(pc_want) < 0.01,
					"%s: FINAL transformed sole normal equals the %s plane's effective contact normal (%s: off by %.4f rad)"
						% [p_type, pc_name, foot_case[0], pc_sole_n.angle_to(pc_want)]
				)
				# (c) rig-derived transformed sole-plane point ON the plane.
				var pc_pt: Vector3 = pc_ankle - pc_sole_n * pc_d
				var pc_res: float = pc_n.dot(
					pc_pt - Vector3(pc_pt.x, pc_plane.height_at(pc_pt.x, pc_pt.z), pc_pt.z)
				)
				_check(
					absf(pc_res) < 0.002,
					"%s: the transformed sole plane lies ON the %s plane (%s: residual %.4f — no gap, no penetration)"
						% [p_type, pc_name, foot_case[0], pc_res]
				)

		# (7) The CONTACT (non-planted, walking) path targets the same
		# corrected post-alignment height: at the walk clip's stance pose
		# on the steep plane, the grounded ankle height equals the exact
		# contact-weighted blend of the animated height toward
		# sole_contact_height (with the pose-derived clearance on the
		# animated side) — the gate is held on so planting stays out.
		p_grounder.set_locomotion_active(true)
		var c_plane := PlaneSampler.new(0.8, 0.0, -0.45, 4.0, 0.0)
		pview.set_surface_sampler(c_plane)
		p_player.play(p_walk)
		var c_t := _lowest_lift_time(p_player, p_skel, p_lf, p_walk, w_len)
		p_player.seek(c_t, true)
		var c_anim_l: Vector3 = _bone_world(p_skel, p_lf)
		var c_anim_r: Vector3 = _bone_world(p_skel, p_rf)
		var c_delta_l: float = c_plane.height_at(c_anim_l.x, c_anim_l.z) - 0.8
		var c_delta_r: float = c_plane.height_at(c_anim_r.x, c_anim_r.z) - 0.8
		var c_lift: float = (c_anim_l.y - 0.8) - rest_h["L"]
		var c_contact: float = WorldUnitLegGrounderScript.contact_weight(c_lift, p_leg_w)
		var c_extra: float = WorldUnitLegGrounderScript.swing_clearance(
			c_lift, c_delta_l - c_delta_r, p_leg_w
		)
		var c_calib: float = WorldUnitLegGrounderScript.sole_contact_height(
			c_plane.height_at(c_anim_l.x, c_anim_l.z), c_plane.normal(), rest_h["L"]
		)
		var c_expected: float = lerpf(
			c_anim_l.y + c_delta_l + c_extra, c_calib, c_contact
		)
		p_grounder.apply_grounding_now()
		_check(
			absf(_bone_world(p_skel, p_lf).y - c_expected) < 0.003,
			"%s: walking stance on the steep slope blends toward the corrected post-alignment contact height" % p_type
		)
		p_grounder.set_locomotion_active(false)
		pview.queue_free()

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


# Clip time (scan of the ACTUAL remapped clip) where one foot bone is at
# its lowest — a deterministic stance/contact pose for that rig.
static func _lowest_lift_time(player: AnimationPlayer, skel: Skeleton3D, foot_i: int, clip: String, clip_len: float) -> float:
	return _extreme_lift_time(player, skel, foot_i, clip, clip_len, false)


# Clip time where one foot bone is at its highest — a deterministic
# mid-swing pose for that rig.
static func _highest_lift_time(player: AnimationPlayer, skel: Skeleton3D, foot_i: int, clip: String, clip_len: float) -> float:
	return _extreme_lift_time(player, skel, foot_i, clip, clip_len, true)


# Clip time whose foot pose lies FARTHEST from the pose at ref_t — the
# most drift the raw clip can produce against a plant captured at ref_t.
static func _max_foot_displacement_time(player: AnimationPlayer, skel: Skeleton3D, foot_i: int, clip: String, clip_len: float, ref_t: float) -> float:
	player.play(clip)
	player.seek(ref_t, true)
	var ref_pos: Vector3 = skel.get_bone_global_pose(foot_i).origin
	var best_t := ref_t
	var best_d := -1.0
	for step in 33:
		var t: float = clip_len * float(step) / 32.0
		player.seek(t, true)
		var d: float = (skel.get_bone_global_pose(foot_i).origin - ref_pos).length()
		if d > best_d:
			best_d = d
			best_t = t
	return best_t


static func _extreme_lift_time(player: AnimationPlayer, skel: Skeleton3D, foot_i: int, clip: String, clip_len: float, highest: bool) -> float:
	player.play(clip)
	var best_t := 0.0
	var best_y := -INF if highest else INF
	for step in 49:
		var t: float = clip_len * float(step) / 48.0
		player.seek(t, true)
		var y: float = skel.get_bone_global_pose(foot_i).origin.y
		if (highest and y > best_y) or (not highest and y < best_y):
			best_y = y
			best_t = t
	return best_t


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
