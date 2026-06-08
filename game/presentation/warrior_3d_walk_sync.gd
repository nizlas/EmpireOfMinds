# Presentation-only: sync hex-move lerp duration to the GLB walk clip (Idle_02 via remap).
class_name Warrior3DWalkSync
extends RefCounted

const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")

const WALK_VISUAL_CLIP: String = "Walking"
## Measured from warrior_3d_animations.glb **Idle_02** (2026-06); used when clip length cannot be read.
const FALLBACK_WALK_CLIP_LENGTH_SEC: float = 1.0333333

static var _cached_walk_clip_length_sec: float = -1.0


static func walk_glb_clip_name(use_remap: bool) -> String:
	return Warrior3DAnimationRemapScript.glb_clip_for_visual(WALK_VISUAL_CLIP, use_remap)


static func cache_walk_clip_length_from_player(player: AnimationPlayer, use_remap: bool) -> float:
	var clip_name: String = walk_glb_clip_name(use_remap)
	if player == null or clip_name.is_empty():
		return resolved_walk_clip_length_sec()
	var anim: Animation = player.get_animation(clip_name)
	if anim == null or anim.length <= 0.0:
		return resolved_walk_clip_length_sec()
	_cached_walk_clip_length_sec = anim.length
	return _cached_walk_clip_length_sec


static func resolved_walk_clip_length_sec() -> float:
	if _cached_walk_clip_length_sec > 0.0:
		return _cached_walk_clip_length_sec
	return FALLBACK_WALK_CLIP_LENGTH_SEC


## **duration × anim_speed_scale** advances this fraction of one walk loop on the GLB clip.
static func hex_move_duration_sec(
	anim_speed_scale: float,
	stride_cycle_fraction: float,
	clip_length_sec: float = -1.0,
) -> float:
	var clip_len: float = clip_length_sec if clip_length_sec > 0.0 else resolved_walk_clip_length_sec()
	var stride: float = clampf(stride_cycle_fraction, 0.1, 2.0)
	var speed: float = maxf(anim_speed_scale, 0.05)
	return maxf(clip_len * stride / speed, 0.12)
