# Presentation-only: map desired *visual* clip names to GLB AnimationPlayer keys.
# Derived from manual EOM_WARRIOR_3D_ANIM_AUDIT (2026-06) — GLB names do not match clip contents.
# Do not rename assets; remove this remap after a corrected GLB re-export.
class_name Warrior3DAnimationRemap
extends RefCounted

## User audit: playing GLB key **K** showed visual motion normally associated with **V**.
## To obtain visual **V**, play **`GLB_CLIP_FOR_VISUAL[V]`** (verbatim Godot `get_animation_list()` strings).
const GLB_CLIP_FOR_VISUAL: Dictionary = {
	"Dead": "Left_Slash",
	"Left_Slash": "Dead",
	"Hit_Reaction_1": "Running",
	"Running": "Hit_Reaction_1",
	"Idle_02": "Walking",
	"Walking": "Idle_02",
	"Combat_Stance": "Idle_3",
	"Idle_3": "Combat_Stance",
}


static func glb_clip_for_visual(visual_name: String, use_remap: bool) -> String:
	var key: String = visual_name.strip_edges()
	if key.is_empty() or not use_remap:
		return key
	return str(GLB_CLIP_FOR_VISUAL.get(key, key))
