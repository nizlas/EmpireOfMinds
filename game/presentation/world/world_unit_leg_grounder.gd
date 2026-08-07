# N7f presentation-only humanoid leg grounding for WorldMap units.
#
# Contract (locked):
# - The character's ModelRoot stays UPRIGHT (world +Y, yaw only) — terrain
#   never pitches or rolls the whole body. This modifier grounds the FEET
#   instead: it runs as a SkeletonModifier3D child of the character's
#   Skeleton3D (the supported post-animation pose-override mechanism), so
#   every adjustment is applied on top of the playing clip each frame,
#   while walking and while idling.
# - Per frame it samples the rendered top surface (the same injected
#   WorldSurfaceSampler the locomotion glide uses — cliff-wall hits are
#   misses, never legality) under BOTH feet independently, then applies:
#     1. a VERTICAL pelvis (Hips) adjustment of min(left delta, right
#        delta), clamped to MAX_PELVIS_RATIO of the leg length, so the
#        lower foot can reach without hyper-extending; and
#     2. an analytic TWO-BONE (UpLeg/Leg) adjustment per leg that bends
#        the knee until the foot reaches its terrain target, with the
#        residual clamped to MAX_FOOT_RAISE_RATIO of the leg length and
#        the reach clamped inside [|L1-L2|, L1+L2] (safe IK bounds).
#   Deltas are measured against the model ground plane (the ModelRoot's
#   world Y), so animation foot lift is preserved on top of the terrain.
# - The animated FOOT ORIENTATION is preserved (only its position moves).
#   Rotating the sole to match the local terrain normal is a deliberately
#   deferred visual fine-tuning item (documented in UNITS.md); this pass
#   eliminates floating/sinking, not sole-angle mismatch.
# - Bone indices are resolved ONCE at setup (cached; no per-frame lookups,
#   no mesh scans). Both shipped rigs use the same bone names (audited
#   2026-08: Hips / LeftUpLeg / LeftLeg / LeftFoot and the Right mirror).
#   If any bone is missing the grounder reports unbound and stays inert —
#   never a partial adjustment. Assets are never modified.
class_name WorldUnitLegGrounder
extends SkeletonModifier3D

const BONE_HIPS := "Hips"
const BONES_LEFT: Array[String] = ["LeftUpLeg", "LeftLeg", "LeftFoot"]
const BONES_RIGHT: Array[String] = ["RightUpLeg", "RightLeg", "RightFoot"]

# Safe adjustment bounds, as fractions of the (current-pose) leg length.
const MAX_PELVIS_RATIO := 0.35
const MAX_FOOT_RAISE_RATIO := 0.6
const EPS := 0.0001

var _sampler = null
var _plane_node: Node3D = null
var _hips := -1
var _left: Array[int] = [-1, -1, -1]
var _right: Array[int] = [-1, -1, -1]
var _bound := false


# Resolves and caches the bone map from the owning skeleton; must be called
# after this modifier was added as a child of the Skeleton3D. plane_node is
# the unit's ModelRoot: its world Y is the model ground plane the deltas
# are measured against. Returns the binding result (also via is_bound()).
func setup(sampler, plane_node: Node3D) -> bool:
	_sampler = sampler
	_plane_node = plane_node
	_bound = false
	var skel := _resolve_skeleton()
	if skel == null:
		return false
	_hips = skel.find_bone(BONE_HIPS)
	for i in 3:
		_left[i] = skel.find_bone(BONES_LEFT[i])
		_right[i] = skel.find_bone(BONES_RIGHT[i])
	_bound = _hips >= 0 and not _left.has(-1) and not _right.has(-1)
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
	apply_grounding_now()


# One deterministic grounding pass over the current pose (public so tests
# can drive it directly without waiting for engine frames).
func apply_grounding_now() -> void:
	if not _bound or _sampler == null or _plane_node == null:
		return
	var skel := _resolve_skeleton()
	if skel == null:
		return
	var to_world: Transform3D = skel.global_transform
	var to_skel: Transform3D = to_world.affine_inverse()
	var plane_y: float = _plane_node.global_position.y
	var left_foot_w: Vector3 = to_world * skel.get_bone_global_pose(_left[2]).origin
	var right_foot_w: Vector3 = to_world * skel.get_bone_global_pose(_right[2]).origin
	var d_left := _ground_delta(left_foot_w, plane_y)
	var d_right := _ground_delta(right_foot_w, plane_y)
	if is_nan(d_left) or is_nan(d_right):
		return  # sampler miss: keep the animated pose untouched
	var leg_len_w := _leg_length_world(skel, to_world, _left)
	if leg_len_w < EPS:
		return
	var pelvis := pelvis_offset(d_left, d_right, leg_len_w * MAX_PELVIS_RATIO)
	if absf(pelvis) > EPS:
		var hips_g: Transform3D = skel.get_bone_global_pose(_hips)
		hips_g.origin += to_skel.basis * Vector3(0.0, pelvis, 0.0)
		skel.set_bone_global_pose(_hips, hips_g)
	var max_raise := leg_len_w * MAX_FOOT_RAISE_RATIO
	_solve_leg(skel, to_skel, _left, left_foot_w, d_left, pelvis, max_raise)
	_solve_leg(skel, to_skel, _right, right_foot_w, d_right, pelvis, max_raise)


# Terrain height under one foot, as a vertical delta from the model ground
# plane (NAN on a sampler miss — cliff walls and off-surface stay misses).
func _ground_delta(foot_world: Vector3, plane_y: float) -> float:
	var res: Dictionary = _sampler.sample(foot_world.x, foot_world.z, plane_y)
	if typeof(res) != TYPE_DICTIONARY or not bool(res.get("ok", false)):
		return NAN
	return float(res.get("height", plane_y)) - plane_y


# --- deterministic math (static, unit-tested) --------------------------------


# Vertical pelvis adjustment: follow the LOWER of the two foot targets so
# that leg only needs the pelvis shift, clamped to the safe bound.
static func pelvis_offset(d_left: float, d_right: float, max_abs: float) -> float:
	return clampf(minf(d_left, d_right), -max_abs, max_abs)


# Clamps an IK target inside the reachable annulus [|l1-l2|, l1+l2] around
# the hip (safe two-bone bounds; keeps a margin so the leg never locks).
static func clamped_reach_target(a: Vector3, t: Vector3, l1: float, l2: float) -> Vector3:
	var min_r: float = absf(l1 - l2) + EPS
	var max_r: float = maxf(l1 + l2 - EPS, min_r + EPS)
	var d := t - a
	var dist := d.length()
	if dist < EPS:
		return a + Vector3(0.0, -min_r, 0.0)
	return a + d * (clampf(dist, min_r, max_r) / dist)


# Analytic two-bone knee position for hip a, current knee b, (pre-clamped)
# target t: keeps the knee on its current bend side, at exact bone lengths.
static func knee_position(a: Vector3, b: Vector3, t: Vector3, l1: float, l2: float, bend_hint: Vector3) -> Vector3:
	var dir := t - a
	var dist := dir.length()
	if dist < EPS:
		return b
	dir /= dist
	var d1 := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var r := sqrt(maxf(l1 * l1 - d1 * d1, 0.0))
	var bend := b - (a + dir * (b - a).dot(dir))
	if bend.length() < EPS:
		bend = bend_hint - dir * bend_hint.dot(dir)
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


func _leg_length_world(skel: Skeleton3D, to_world: Transform3D, bones: Array[int]) -> float:
	var a: Vector3 = skel.get_bone_global_pose(bones[0]).origin
	var b: Vector3 = skel.get_bone_global_pose(bones[1]).origin
	var c: Vector3 = skel.get_bone_global_pose(bones[2]).origin
	return (to_world.basis * (b - a)).length() + (to_world.basis * (c - b)).length()


# Two-bone leg adjustment: move the animated foot vertically to its terrain
# target (delta relative to the plane, minus what the pelvis already did),
# bending the knee on its current side; the animated foot ORIENTATION is
# restored afterwards (sole-angle matching is the deferred fine-tune).
func _solve_leg(
	skel: Skeleton3D,
	to_skel: Transform3D,
	bones: Array[int],
	foot_world: Vector3,
	delta: float,
	pelvis: float,
	max_raise: float,
) -> void:
	var residual := clampf(delta - pelvis, -max_raise, max_raise)
	if absf(residual) < EPS:
		return
	# Pelvis already shifted the whole chain by `pelvis`; the remaining
	# correction on top of the CURRENT chain is exactly `residual`.
	var a_g: Transform3D = skel.get_bone_global_pose(bones[0])
	var b_g: Transform3D = skel.get_bone_global_pose(bones[1])
	var c_g: Transform3D = skel.get_bone_global_pose(bones[2])
	var target_skel: Vector3 = c_g.origin + to_skel.basis * Vector3(0.0, residual, 0.0)
	var l1 := (b_g.origin - a_g.origin).length()
	var l2 := (c_g.origin - b_g.origin).length()
	if l1 < EPS or l2 < EPS:
		return
	var t2 := clamped_reach_target(a_g.origin, target_skel, l1, l2)
	var bend_hint: Vector3 = a_g.basis.z
	var knee := knee_position(a_g.origin, b_g.origin, t2, l1, l2, bend_hint)
	var foot_basis: Basis = c_g.basis
	var r0 := shortest_arc(
		(b_g.origin - a_g.origin).normalized(), (knee - a_g.origin).normalized()
	)
	skel.set_bone_global_pose(bones[0], Transform3D(Basis(r0) * a_g.basis, a_g.origin))
	var b2_g: Transform3D = skel.get_bone_global_pose(bones[1])
	var c2: Vector3 = skel.get_bone_global_pose(bones[2]).origin
	var r1 := shortest_arc(
		(c2 - b2_g.origin).normalized(), (t2 - b2_g.origin).normalized()
	)
	skel.set_bone_global_pose(bones[1], Transform3D(Basis(r1) * b2_g.basis, b2_g.origin))
	var c3_g: Transform3D = skel.get_bone_global_pose(bones[2])
	skel.set_bone_global_pose(bones[2], Transform3D(foot_basis, c3_g.origin))
