# TEMPORARY probe helper: resolve settler GLB Hips position track for root_motion_track.
class_name SettlerAnimationRootMotionProbe
extends RefCounted

const HIPS_BONE_NAME: String = "Hips"
const WALK_SEMANTIC_CLIP: String = "Walking"


static func resolve_hips_position_track_path(
	player: AnimationPlayer, clip_name: String, bone_name: String = HIPS_BONE_NAME
) -> NodePath:
	if player == null or clip_name.is_empty():
		return NodePath("")
	if not player.has_animation(clip_name):
		return NodePath("")
	var anim: Animation = player.get_animation(clip_name)
	if anim == null:
		return NodePath("")
	var bone_suffix: String = ":%s" % bone_name
	var i: int = 0
	while i < anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			i += 1
			continue
		var path: NodePath = anim.track_get_path(i)
		var path_str: String = str(path)
		if path_str.ends_with(bone_suffix) or path_str.ends_with(bone_name):
			return path
		i += 1
	return NodePath("")


static func print_animation_tracks(anim: Animation, clip_name: String) -> void:
	if anim == null:
		print("[Settler3D RM probe] clip='%s' missing" % clip_name)
		return
	print("[Settler3D RM probe] clip='%s' track_count=%d" % [clip_name, anim.get_track_count()])
	var i: int = 0
	while i < anim.get_track_count():
		print(
			(
				"[Settler3D RM probe] track[%d] type=%d path='%s'"
			)
			% [i, int(anim.track_get_type(i)), str(anim.track_get_path(i))]
		)
		i += 1


static func hips_pose_xz_delta(skel: Skeleton3D, bone_name: String = HIPS_BONE_NAME) -> Vector2:
	var hips_idx: int = skel.find_bone(bone_name)
	if hips_idx < 0:
		return Vector2.ZERO
	var pose: Vector3 = skel.get_bone_pose_position(hips_idx)
	var rest: Vector3 = skel.get_bone_rest(hips_idx).origin
	var delta: Vector3 = pose - rest
	return Vector2(delta.x, delta.z)
