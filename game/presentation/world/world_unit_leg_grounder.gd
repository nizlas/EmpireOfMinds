# N7f presentation-only humanoid leg grounding for WorldMap units.
#
# Contract (locked):
# - The character's ModelRoot stays UPRIGHT (world +Y, yaw only) — terrain
#   never pitches or rolls the whole body. This modifier grounds the FEET
#   instead: it runs as a SkeletonModifier3D child of the character's
#   Skeleton3D (the supported post-animation pose-override mechanism), so
#   every adjustment is applied on top of the playing clip each frame,
#   while walking and while idling. It is the ONE post-animation
#   leg-solving system — never a second IK stack.
# - Per frame it samples the rendered top surface (the same injected
#   WorldSurfaceSampler the locomotion glide uses — cliff-wall hits are
#   misses, never legality) under BOTH feet independently, then applies:
#     1. a JOINT two-leg vertical pelvis (Hips) solve: the baseline follows
#        the lower foot target, then the offset is clamped into the
#        intersection of both legs' reach-feasibility intervals (each keeps
#        its target reachable with an extension margin — REACH_MAX_RATIO of
#        l1+l2), midpoint on conflict, absolute bound MAX_PELVIS_RATIO;
#     2. an analytic TWO-BONE (UpLeg/Leg) solve per leg with an EXPLICIT
#        anatomical pole: the knee bends toward the per-leg rest-pose
#        toe-forward direction (constant in skeleton space, so it follows
#        character yaw — never terrain pitch/roll, never raw bone axes,
#        NEVER the current possibly-straight knee as branch selector),
#        with the target clamped inside [|l1-l2|*FOLD, (l1+l2)*REACH_MAX]
#        and the residual clamped to MAX_FOOT_RAISE_RATIO of the leg;
#     3. a WHOLE-FOOT sole alignment: the Foot bone is rotated (about the
#        ankle; the audited rigs move only foot+toe) so the rest-derived
#        sole normal tips toward that foot's OWN sampled terrain normal
#        while the rest-derived foot-forward keeps its heading (projected
#        onto the terrain tangent plane) — continuous on every slope, no
#        threshold, naturally zero on flat ground; dorsi/plantarflexion and
#        side roll are clamped anatomically; full alignment in
#        stance/contact, reduced blending toward the expected landing
#        normal during swing (never glued mid-air); temporally smoothed
#        frame-rate-independently (1 - exp(-rate*dt); instant when the
#        caller passes no delta, keeping direct/test calls deterministic);
#     4. a SLOPE-ADAPTIVE uphill swing clearance: a bounded extra lift on
#        the swing foot only, = gain * max(0, own target - other target) *
#        a pose-derived bell (the animated foot lift normalized by leg
#        length) that is ZERO at takeoff and landing by construction —
#        flat/downhill motion never gains artificial lift; the phase source
#        is the actual remapped clip pose, never per-unit timings.
#   Deltas are measured against the model ground plane (the ModelRoot's
#   world Y), so animation foot lift is preserved on top of the terrain.
# - Bone indices AND rest frames are resolved ONCE at setup (cached; no
#   per-frame lookups, no mesh scans): the per-leg knee pole and per-foot
#   sole frames come from the audited rest pose (toe-vs-ankle direction) —
#   no unit-id/type-specific angle constants. Both shipped rigs use the
#   same bone names (audited 2026-08: Hips / LeftUpLeg / LeftLeg /
#   LeftFoot / LeftToeBase and the Right mirror; rotating Foot moves only
#   foot+toe about the ankle). If any required bone is missing the
#   grounder reports unbound and stays inert — never a partial adjustment.
#   Assets, skin weights, and animations are never modified; exact bone
#   lengths and finite transforms are preserved.
class_name WorldUnitLegGrounder
extends SkeletonModifier3D

const BONE_HIPS := "Hips"
const BONES_LEFT: Array[String] = ["LeftUpLeg", "LeftLeg", "LeftFoot"]
const BONES_RIGHT: Array[String] = ["RightUpLeg", "RightLeg", "RightFoot"]
const BONE_TOE_LEFT := "LeftToeBase"
const BONE_TOE_RIGHT := "RightToeBase"

# --- tuning constants (ratios of leg length l1+l2, or absolute radians) ---
# Safe adjustment bounds.
const MAX_PELVIS_RATIO := 0.35
const MAX_FOOT_RAISE_RATIO := 0.6
# Extension margin: targets are kept at <= this fraction of full extension
# (never a locked/hyperextended knee) and >= the fold limit margin.
const REACH_MAX_RATIO := 0.96
const FOLD_MIN_RATIO := 1.02
# Contact weighting from the ANIMATED foot lift (rest-height-relative,
# leg-length-normalized): full contact below LO, full swing above HI.
const CONTACT_LIFT_LO_RATIO := 0.02
const CONTACT_LIFT_HI_RATIO := 0.10
# Sole alignment strength during swing (blend toward the landing normal;
# stance/idle always blends at full weight 1.0).
const SWING_ALIGN_WEIGHT := 0.35
# Frame-rate-independent smoothing rate for the foot correction.
const FOOT_BLEND_RATE := 14.0
# Anatomical foot clamps (radians): toes-up (dorsiflexion), toes-down
# (plantarflexion), and side roll.
const FOOT_PITCH_UP_MAX := 0.5
const FOOT_PITCH_DOWN_MAX := 0.6
const FOOT_ROLL_MAX := 0.3
# Uphill swing clearance: bounded gain over the positive height gain, with
# the pose-lift bell (lift / (SWING_LIFT_REF_RATIO * leg)) as phase source.
const SWING_LIFT_REF_RATIO := 0.12
const SWING_CLEARANCE_GAIN := 0.9
const SWING_CLEARANCE_MAX_RATIO := 0.18

const EPS := 0.0001

var _sampler = null
var _plane_node: Node3D = null
var _hips := -1
var _left: Array[int] = [-1, -1, -1]
var _right: Array[int] = [-1, -1, -1]
var _bound := false

# Rest-derived anatomical frames (skeleton space / foot-local; setup-cached).
# Per-leg knee pole: horizontalized rest toe-forward (skeleton space).
var _pole: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
# Per-foot rest sole frame, expressed in the FOOT bone's local space.
var _rest_up_local: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _rest_fwd_local: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]
# Per-foot rest height above the skeleton origin plane (skeleton units).
var _rest_foot_height: Array[float] = [0.0, 0.0]
# Per-foot temporally smoothed world-frame correction (presentation state).
var _foot_corr: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]


# Resolves and caches the bone map + rest frames from the owning skeleton;
# must be called after this modifier was added as a child of the
# Skeleton3D. plane_node is the unit's ModelRoot: its world Y is the model
# ground plane the deltas are measured against.
func setup(sampler, plane_node: Node3D) -> bool:
	_sampler = sampler
	_plane_node = plane_node
	_bound = false
	_foot_corr = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var skel := _resolve_skeleton()
	if skel == null:
		return false
	_hips = skel.find_bone(BONE_HIPS)
	for i in 3:
		_left[i] = skel.find_bone(BONES_LEFT[i])
		_right[i] = skel.find_bone(BONES_RIGHT[i])
	_bound = _hips >= 0 and not _left.has(-1) and not _right.has(-1)
	if not _bound:
		return false
	var toe_left := skel.find_bone(BONE_TOE_LEFT)
	var toe_right := skel.find_bone(BONE_TOE_RIGHT)
	for side in 2:
		var foot_i: int = (_left if side == 0 else _right)[2]
		var toe_i: int = toe_left if side == 0 else toe_right
		var foot_rest: Transform3D = skel.get_bone_global_rest(foot_i)
		_rest_foot_height[side] = foot_rest.origin.y
		# Anatomical forward from the audited rest toe-vs-ankle direction
		# (ToeBase is a rest-frame direction reference only — never assumed
		# to be a weighted toe control). Fallback: skeleton +Z, which the
		# 2026-08 audit established as both rigs' authored facing.
		var fwd := Vector3(0.0, 0.0, 1.0)
		if toe_i >= 0:
			var toe_fwd: Vector3 = skel.get_bone_global_rest(toe_i).origin - foot_rest.origin
			toe_fwd.y = 0.0
			if toe_fwd.length() > EPS:
				fwd = toe_fwd.normalized()
		_pole[side] = fwd
		# Rest sole frame in foot-local space: what the sole's up and the
		# foot's forward look like from inside the foot bone at rest.
		var inv: Basis = foot_rest.basis.inverse()
		_rest_up_local[side] = inv * Vector3.UP
		_rest_fwd_local[side] = inv * fwd
	return _bound


func set_surface_sampler(sampler) -> void:
	_sampler = sampler


func is_bound() -> bool:
	return _bound


# get_skeleton() resolves only after tree entry; units are created (and
# bound) before the scene may enter the tree, so fall back to the direct
# parent this modifier was just added under.
func _resolve_skeleton() -> Skeleton3D:
	var skel := get_skeleton()
	if skel != null:
		return skel
	return get_parent() as Skeleton3D


# Engine entry: runs after the AnimationPlayer applied the clip pose.
func _process_modification() -> void:
	apply_grounding_now(get_process_delta_time())


# One deterministic grounding pass over the current pose. delta < 0 (the
# default for direct/test calls) applies the foot alignment instantly;
# engine frames pass the real delta for frame-rate-independent smoothing.
# Re-entrancy guard: Skeleton3D.set_bone_global_pose force-updates dirty
# bones, which can re-enter modifier processing MID-PASS (observed in
# multi-view scenes) — the inner pass would overwrite the outer one's foot
# poses, so any re-entrant call is a no-op.
var _applying := false


func apply_grounding_now(delta: float = -1.0) -> void:
	if _applying:
		return
	_applying = true
	_apply_grounding_pass(delta)
	_applying = false


func _apply_grounding_pass(delta: float) -> void:
	if not _bound or _sampler == null or _plane_node == null:
		return
	var skel := _resolve_skeleton()
	if skel == null:
		return
	var to_world: Transform3D = skel.global_transform
	var to_skel: Transform3D = to_world.affine_inverse()
	var plane_y: float = _plane_node.global_position.y
	# Skeleton-units-per-world-unit along the vertical (uniform scale).
	var up_skel_vec: Vector3 = to_skel.basis * Vector3.UP
	var k: float = up_skel_vec.length()
	if k < EPS:
		return
	var up_s: Vector3 = up_skel_vec / k

	var legs := [_left, _right]
	var foot_w: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var deltas: Array[float] = [0.0, 0.0]
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	for side in 2:
		var bones: Array[int] = legs[side]
		foot_w[side] = to_world * skel.get_bone_global_pose(bones[2]).origin
		var res: Dictionary = _sampler.sample(foot_w[side].x, foot_w[side].z, plane_y)
		if typeof(res) != TYPE_DICTIONARY or not bool(res.get("ok", false)):
			return  # sampler miss: keep the animated pose untouched
		deltas[side] = float(res.get("height", plane_y)) - plane_y
		var n: Vector3 = res.get("normal", Vector3.UP)
		normals[side] = n.normalized() if n.length() > EPS else Vector3.UP

	# Per-leg geometry for the joint pelvis solve (skeleton space).
	var reach_intervals: Array[Vector2] = []
	var leg_len_s: Array[float] = [0.0, 0.0]
	for side in 2:
		var bones: Array[int] = legs[side]
		var a: Vector3 = skel.get_bone_global_pose(bones[0]).origin
		var b: Vector3 = skel.get_bone_global_pose(bones[1]).origin
		var c: Vector3 = skel.get_bone_global_pose(bones[2]).origin
		var l1 := (b - a).length()
		var l2 := (c - b).length()
		leg_len_s[side] = l1 + l2
		reach_intervals.append(
			pelvis_interval(
				c - a, up_s, deltas[side] * k, safe_reach_max((c - a).length(), l1, l2)
			)
		)
	if leg_len_s[0] < EPS or leg_len_s[1] < EPS:
		return
	var avg_len_s: float = (leg_len_s[0] + leg_len_s[1]) * 0.5
	var baseline: float = minf(deltas[0], deltas[1]) * k
	var pelvis_s: float = joint_pelvis_offset(
		baseline, reach_intervals[0], reach_intervals[1], avg_len_s * MAX_PELVIS_RATIO
	)

	# Snapshot the chains ONCE, then write only LOCAL bone poses computed
	# analytically from the snapshot. Global-pose setters are deliberately
	# avoided: they force-update the skeleton mid-pass, which re-enters the
	# modifier lifecycle and restores the engine's pre-modifier pose backup
	# — silently discarding earlier writes of the same pass.
	var hips_g: Transform3D = skel.get_bone_global_pose(_hips)
	var hips_parent: int = skel.get_bone_parent(_hips)
	var hips_parent_g: Transform3D = (
		skel.get_bone_global_pose(hips_parent) if hips_parent >= 0 else Transform3D.IDENTITY
	)
	var chain_g: Array = []
	for side in 2:
		var bones: Array[int] = legs[side]
		chain_g.append([
			skel.get_bone_global_pose(bones[0]),
			skel.get_bone_global_pose(bones[1]),
			skel.get_bone_global_pose(bones[2]),
		])
	var v: Vector3 = up_s * pelvis_s
	var hips_new := Transform3D(hips_g.basis, hips_g.origin + v)
	if absf(pelvis_s) > EPS:
		skel.set_bone_pose(_hips, hips_parent_g.affine_inverse() * hips_new)

	# Contact weights + uphill swing clearance from the ANIMATED pose lift.
	var leg_len_w: Array[float] = [leg_len_s[0] / k, leg_len_s[1] / k]
	var contact: Array[float] = [1.0, 1.0]
	var extra_w: Array[float] = [0.0, 0.0]
	for side in 2:
		var lift_w: float = (foot_w[side].y - plane_y) - _rest_foot_height[side] / k
		contact[side] = contact_weight(lift_w, leg_len_w[side])
		extra_w[side] = swing_clearance(
			lift_w, deltas[side] - deltas[1 - side], leg_len_w[side]
		)

	for side in 2:
		_solve_leg(
			skel,
			to_world,
			legs[side],
			side,
			chain_g[side],
			hips_new,
			v,
			(deltas[side] + extra_w[side]) * k - pelvis_s,
			up_s,
			normals[side],
			contact[side],
			delta,
			leg_len_s[side] * MAX_FOOT_RAISE_RATIO,
		)


# --- deterministic math (static, unit-tested) --------------------------------


# Reach-feasibility interval of vertical pelvis offsets (skeleton units)
# for one leg: v = hip->animated-foot, target shift (delta_s - p) along
# up_s must keep |v + up_s*(delta_s - p)| <= reach_max. Closed interval;
# degenerates to a point when the horizontal offset alone uses the reach.
static func pelvis_interval(v: Vector3, up_s: Vector3, delta_s: float, reach_max: float) -> Vector2:
	var par: float = v.dot(up_s)
	var perp_sq: float = maxf(v.length_squared() - par * par, 0.0)
	var s: float = sqrt(maxf(reach_max * reach_max - perp_sq, 0.0))
	var center: float = par + delta_s
	return Vector2(center - s, center + s)


# Joint two-leg pelvis offset: start from the lower-target baseline, then
# clamp into the intersection of both reach intervals (midpoint of the gap
# when the intervals conflict — the best shared compromise), then apply
# the absolute safety bound.
static func joint_pelvis_offset(baseline: float, a: Vector2, b: Vector2, max_abs: float) -> float:
	var lo: float = maxf(a.x, b.x)
	var hi: float = minf(a.y, b.y)
	var p: float
	if lo <= hi:
		p = clampf(baseline, lo, hi)
	else:
		p = 0.5 * (lo + hi)
	return clampf(p, -max_abs, max_abs)


# Safe maximum reach for one leg in its CURRENT animated pose: the
# extension margin (REACH_MAX_RATIO of full extension) bounds where the
# solver may PLACE a target, but an authored pose that is already
# straighter than the margin is never re-posed — the animated reach (capped
# just below full extension) then wins, so flat ground stays a strict no-op.
static func safe_reach_max(anim_reach: float, l1: float, l2: float) -> float:
	var full: float = l1 + l2
	return maxf(full * REACH_MAX_RATIO, minf(anim_reach, full * 0.999))


# Clamps an IK target inside the safe reach annulus around the hip: at
# least the fold limit, at most `reach_max` (pass safe_reach_max();
# negative uses the plain extension margin) — the margin that keeps the
# knee from locking/hyperextending. Limits are expressed relative to the
# leg's own bone lengths.
static func clamped_reach_target(a: Vector3, t: Vector3, l1: float, l2: float, reach_max: float = -1.0) -> Vector3:
	var min_r: float = absf(l1 - l2) * FOLD_MIN_RATIO + EPS
	var max_r: float = (l1 + l2) * REACH_MAX_RATIO if reach_max < 0.0 else reach_max
	max_r = maxf(max_r, min_r + EPS)
	var d := t - a
	var dist := d.length()
	if dist < EPS:
		return a + Vector3(0.0, -min_r, 0.0)
	return a + d * (clampf(dist, min_r, max_r) / dist)


# Analytic two-bone knee position for hip a and (pre-clamped) target t,
# bending toward the EXPLICIT anatomical pole: the bend direction is the
# pole projected perpendicular to the hip->target axis — deterministic and
# continuous, NEVER selected from the current (possibly straight) knee.
# `secondary` breaks the rare axis-parallel-to-pole degeneracy (a leg
# reaching straight along the pole bends toward it — e.g. skeleton up).
static func knee_position(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3, secondary: Vector3) -> Vector3:
	var dir := t - a
	var dist := dir.length()
	if dist < EPS:
		return a + pole.normalized() * l1 if pole.length() > EPS else a
	dir /= dist
	var d1 := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var r := sqrt(maxf(l1 * l1 - d1 * d1, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < EPS:
		bend = secondary - dir * secondary.dot(dir)
	if bend.length() < EPS:
		return a + dir * d1
	return a + dir * d1 + bend.normalized() * r


# Shortest-arc rotation carrying one unit direction onto another.
static func shortest_arc(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	var c := from_dir.cross(to_dir)
	var d := clampf(from_dir.dot(to_dir), -1.0, 1.0)
	if c.length_squared() < EPS * EPS:
		if d > 0.0:
			return Quaternion.IDENTITY
		var axis := from_dir.cross(Vector3.UP)
		if axis.length_squared() < EPS * EPS:
			axis = from_dir.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(c.normalized(), acos(d))


# Contact weight from the ANIMATED foot lift above its rest height: 1 on
# the ground (stance/idle), 0 fully in swing, smooth in between. Ratios of
# the leg length keep it rig-independent.
static func contact_weight(lift_w: float, leg_len_w: float) -> float:
	if leg_len_w < EPS:
		return 1.0
	var x: float = lift_w / leg_len_w
	return 1.0 - smoothstep(CONTACT_LIFT_LO_RATIO, CONTACT_LIFT_HI_RATIO, x)


# Bounded uphill swing clearance (world units). The pose-derived bell
# (animated lift normalized by SWING_LIFT_REF_RATIO of the leg) is zero at
# takeoff and landing BY CONSTRUCTION (the animated lift is zero at both
# contacts) and only positive height gain (own target above the other
# foot's target) produces lift — flat and downhill add exactly nothing.
static func swing_clearance(lift_w: float, height_gain_w: float, leg_len_w: float) -> float:
	if leg_len_w < EPS or height_gain_w <= 0.0 or lift_w <= 0.0:
		return 0.0
	var bell: float = clampf(lift_w / (SWING_LIFT_REF_RATIO * leg_len_w), 0.0, 1.0)
	return minf(
		SWING_CLEARANCE_GAIN * height_gain_w * bell,
		SWING_CLEARANCE_MAX_RATIO * leg_len_w
	)


# Sole-alignment rotation (world space): tips `up` toward the sampled
# normal while the heading stays the horizontal foot-forward projected
# onto the terrain tangent plane; dorsi/plantarflexion and side roll are
# clamped anatomically. Returns IDENTITY for degenerate inputs and
# naturally approaches IDENTITY as the normal approaches world up.
static func sole_alignment(heading_h: Vector3, normal: Vector3) -> Quaternion:
	var h := Vector3(heading_h.x, 0.0, heading_h.z)
	if h.length() < EPS or normal.length() < EPS:
		return Quaternion.IDENTITY
	h = h.normalized()
	var n := normal.normalized()
	var side := h.cross(Vector3.UP)  # rig-independent lateral axis
	# Slope angles seen from the foot: pitch tips the sole fore/aft
	# (positive = toes up / dorsiflexion, when the normal leans against the
	# heading — uphill ahead), roll tips it laterally.
	var pitch: float = clampf(
		asin(clampf(-n.dot(h), -1.0, 1.0)), -FOOT_PITCH_DOWN_MAX, FOOT_PITCH_UP_MAX
	)
	var roll: float = clampf(
		asin(clampf(n.dot(side), -1.0, 1.0)), -FOOT_ROLL_MAX, FOOT_ROLL_MAX
	)
	var n_c: Vector3 = Basis(h, roll) * (Basis(side, pitch) * Vector3.UP)
	n_c = n_c.normalized()
	var t := h - n_c * h.dot(n_c)
	if t.length() < EPS:
		return Quaternion.IDENTITY
	t = t.normalized()
	var f0 := Basis(h, Vector3.UP, h.cross(Vector3.UP))
	var f1 := Basis(t, n_c, t.cross(n_c))
	return Quaternion(f1 * f0.transposed()).normalized()


func _leg_length_world(skel: Skeleton3D, to_world: Transform3D, bones: Array[int]) -> float:
	var a: Vector3 = skel.get_bone_global_pose(bones[0]).origin
	var b: Vector3 = skel.get_bone_global_pose(bones[1]).origin
	var c: Vector3 = skel.get_bone_global_pose(bones[2]).origin
	return (to_world.basis * (b - a)).length() + (to_world.basis * (c - b)).length()


# Two-bone leg + whole-foot pass for one leg: position the foot at its
# terrain target (pole-side knee, safe reach margins, exact bone lengths),
# then rotate the Foot bone about the ankle so the sole follows the
# sampled normal (contact-weighted, clamped, smoothed). `chain` holds the
# pass-start snapshot of the leg's global poses (pre-pelvis); `v` is the
# pelvis translation. All writes are LOCAL bone poses computed from the
# snapshot — no global setters (see _apply_grounding_pass).
func _solve_leg(
	skel: Skeleton3D,
	to_world: Transform3D,
	bones: Array[int],
	side: int,
	chain: Array,
	hips_after: Transform3D,
	v: Vector3,
	residual_s: float,
	up_s: Vector3,
	normal: Vector3,
	contact: float,
	delta: float,
	max_raise_s: float,
) -> void:
	var a_g: Transform3D = chain[0]
	var b_g: Transform3D = chain[1]
	var c_g: Transform3D = chain[2]
	var anim_foot_basis: Basis = c_g.basis
	# Pelvis shift translates the whole chain (children follow the Hips
	# local write automatically — these are the analytic new globals).
	var a1 := Vector3(a_g.origin + v)
	var b1 := Vector3(b_g.origin + v)
	var c1 := Vector3(c_g.origin + v)
	var upleg_new := Transform3D(a_g.basis, a1)
	var leg_new := Transform3D(b_g.basis, b1)
	var foot_origin := c1
	var l1 := (b1 - a1).length()
	var l2 := (c1 - b1).length()
	var rotated := false
	if l1 >= EPS and l2 >= EPS and absf(residual_s) > EPS:
		var target: Vector3 = clamped_reach_target(
			a1,
			c1 + up_s * clampf(residual_s, -max_raise_s, max_raise_s),
			l1,
			l2,
			safe_reach_max((c1 - a1).length(), l1, l2),
		)
		var knee := knee_position(a1, target, l1, l2, _pole[side], up_s)
		var r0 := Basis(shortest_arc((b1 - a1).normalized(), (knee - a1).normalized()))
		var b2: Vector3 = a1 + r0 * (b1 - a1)
		var c2: Vector3 = a1 + r0 * (c1 - a1)
		var r1 := Basis(shortest_arc((c2 - b2).normalized(), (target - b2).normalized()))
		upleg_new = Transform3D(r0 * a_g.basis, a1)
		leg_new = Transform3D(r1 * (r0 * b_g.basis), b2)
		foot_origin = b2 + r1 * (c2 - b2)
		rotated = true

	# Whole-foot sole alignment about the ankle (position untouched). The
	# ANIMATED orientation is the base every frame; the correction is a
	# world-frame delta on top of it, so heading stays animation-owned.
	var world_anim: Basis = to_world.basis * anim_foot_basis
	var heading: Vector3 = world_anim * _rest_fwd_local[side]
	var q_target := sole_alignment(heading, normal)
	# Full alignment in stance; during swing only blend TOWARD the
	# expected landing normal (never glued to the ground mid-air).
	var weight: float = lerpf(SWING_ALIGN_WEIGHT, 1.0, clampf(contact, 0.0, 1.0))
	var q_goal := Quaternion.IDENTITY.slerp(q_target, weight)
	if delta >= 0.0:
		var alpha: float = 1.0 - exp(-FOOT_BLEND_RATE * maxf(delta, 0.0))
		_foot_corr[side] = _foot_corr[side].slerp(q_goal, alpha).normalized()
	else:
		_foot_corr[side] = q_goal
	var applied_world: Basis = Basis(_foot_corr[side]) * world_anim
	# Conjugating by the (uniformly scaled) world transform leaves floating
	# point skew; orthonormalize so the stored bone rotation stays exact.
	var foot_new := Transform3D(
		(to_world.basis.inverse() * applied_world).orthonormalized(), foot_origin
	)

	# LOCAL pose writes: UpLeg's parent is Hips; Leg's is UpLeg; Foot's is
	# Leg (audited chain on both rigs). Unrotated legs need no UpLeg/Leg
	# writes — they follow the Hips pelvis write automatically.
	if rotated:
		skel.set_bone_pose(bones[0], hips_after.affine_inverse() * upleg_new)
		skel.set_bone_pose(bones[1], upleg_new.affine_inverse() * leg_new)
	skel.set_bone_pose(bones[2], leg_new.affine_inverse() * foot_new)
