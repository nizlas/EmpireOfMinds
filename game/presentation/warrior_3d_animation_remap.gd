# Presentation-only: map desired *visual* clip names to GLB AnimationPlayer keys.
# Warrior remap derived from manual EOM_WARRIOR_3D_ANIM_AUDIT (2026-06).
# Settler remap derived from manual F9 visual audit (2026-06); GLB names are not trustworthy.
# Do not rename assets; remove per-type remap after a corrected GLB re-export.
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

## Settler F9 audit (2026-06): semantic desired motion -> actual GLB key on AnimationPlayer.
const SETTLER_GLB_CLIP_FOR_VISUAL: Dictionary = {
	"Idle_3": "Hit_Reaction_1",
	"Walking": "Running",
	"Dead": "walking_2",
}


static func glb_clip_for_visual(
	visual_name: String, use_remap: bool, type_id: String = "warrior"
) -> String:
	var key: String = visual_name.strip_edges()
	if key.is_empty() or not use_remap:
		return key
	if str(type_id) == "settler":
		return str(SETTLER_GLB_CLIP_FOR_VISUAL.get(key, key))
	return str(GLB_CLIP_FOR_VISUAL.get(key, key))
