# Dev-only presentation experiment: render warrior units from warrior_3d.glb on the 2D map.
# Enable with EMPIRE_USE_3D_WARRIOR=1. No gameplay/domain changes.
class_name Warrior3DUnitExperiment
extends RefCounted

const ENV_FLAG: String = "EMPIRE_USE_3D_WARRIOR"
const WARRIOR_GLB_PATH: String = "res://assets/prototype/units/warrior_3d/warrior_3d.glb"
const WARRIOR_ANIMATED_GLB_PATH: String = (
	"res://assets/prototype/units/warrior_3d/warrior_3d_animations.glb"
)
const MAP_ANIMATION_ENV: String = "EOM_WARRIOR_3D_ANIM"
const ANIM_AUDIT_ENV: String = "EOM_WARRIOR_3D_ANIM_AUDIT"
const DEFAULT_MAP_ANIMATION_NAME: String = "Idle_3"


static func map_animation_name() -> String:
	var from_env: String = OS.get_environment(MAP_ANIMATION_ENV).strip_edges()
	if not from_env.is_empty():
		return from_env
	return DEFAULT_MAP_ANIMATION_NAME


static func warrior_scene_path() -> String:
	return WARRIOR_ANIMATED_GLB_PATH


static func is_enabled() -> bool:
	return OS.get_environment(ENV_FLAG).strip_edges() == "1"


static func is_animation_audit_enabled() -> bool:
	return OS.get_environment(ANIM_AUDIT_ENV).strip_edges() == "1"


static func should_render_warrior_as_3d(type_id: String) -> bool:
	if str(type_id) != "warrior":
		return false
	if not is_enabled():
		return false
	return ResourceLoader.exists(WARRIOR_ANIMATED_GLB_PATH)
