# Dev-only presentation experiment: render warrior/settler units from 3D GLBs on the 2D map.
# EMPIRE_USE_3D_MODELS=1 enables warrior + settler. EMPIRE_USE_3D_WARRIOR=1 enables warrior only.
# No gameplay/domain changes.
class_name Warrior3DUnitExperiment
extends RefCounted

const ENV_FLAG: String = "EMPIRE_USE_3D_MODELS"
const ENV_FLAG_LEGACY: String = "EMPIRE_USE_3D_WARRIOR"
const WARRIOR_GLB_PATH: String = "res://assets/prototype/units/warrior_3d/warrior_3d.glb"
const WARRIOR_ANIMATED_GLB_PATH: String = (
	"res://assets/prototype/units/warrior_3d/warrior_3d_animations.glb"
)
const SETTLER_GLB_PATH: String = "res://assets/prototype/units/settler_3d/settler.glb"
const SETTLER_ANIMATED_GLB_PATH: String = (
	"res://assets/prototype/units/settler_3d/settler_animations.glb"
)
const MAP_ANIMATION_ENV: String = "EOM_WARRIOR_3D_ANIM"
const ANIM_AUDIT_ENV: String = "EOM_WARRIOR_3D_ANIM_AUDIT"
const DEFAULT_MAP_ANIMATION_NAME: String = "Idle_3"
const SUPPORTED_3D_TYPE_IDS: Array = ["warrior", "settler"]

static var _logged_flag_state: bool = false


static func map_animation_name() -> String:
	var from_env: String = OS.get_environment(MAP_ANIMATION_ENV).strip_edges()
	if not from_env.is_empty():
		return from_env
	return DEFAULT_MAP_ANIMATION_NAME


static func warrior_scene_path() -> String:
	return animated_scene_path_for_type("warrior")


static func animated_scene_path_for_type(type_id: String) -> String:
	var tid: String = str(type_id)
	if tid == "warrior":
		if ResourceLoader.exists(WARRIOR_ANIMATED_GLB_PATH):
			return WARRIOR_ANIMATED_GLB_PATH
		if ResourceLoader.exists(WARRIOR_GLB_PATH):
			return WARRIOR_GLB_PATH
		return ""
	if tid == "settler":
		if ResourceLoader.exists(SETTLER_ANIMATED_GLB_PATH):
			return SETTLER_ANIMATED_GLB_PATH
		if ResourceLoader.exists(SETTLER_GLB_PATH):
			return SETTLER_GLB_PATH
		return ""
	return ""


static func env_models_flag_value() -> String:
	return OS.get_environment(ENV_FLAG).strip_edges()


static func env_legacy_warrior_flag_value() -> String:
	return OS.get_environment(ENV_FLAG_LEGACY).strip_edges()


static func is_models_flag_enabled() -> bool:
	return env_models_flag_value() == "1"


static func is_legacy_warrior_flag_enabled() -> bool:
	return env_legacy_warrior_flag_value() == "1"


static func is_enabled() -> bool:
	return is_models_flag_enabled() or is_legacy_warrior_flag_enabled()


static func is_animation_audit_enabled() -> bool:
	return OS.get_environment(ANIM_AUDIT_ENV).strip_edges() == "1"


static func should_render_unit_as_3d(type_id: String) -> bool:
	var tid: String = str(type_id)
	if tid == "settler":
		if not is_models_flag_enabled():
			return false
	elif tid == "warrior":
		if not is_enabled():
			return false
	else:
		return false
	return not animated_scene_path_for_type(tid).is_empty()


static func should_render_warrior_as_3d(type_id: String) -> bool:
	return should_render_unit_as_3d(type_id)


static func log_flag_state_once() -> void:
	if _logged_flag_state:
		return
	_logged_flag_state = true
	var models_val: String = env_models_flag_value()
	var legacy_val: String = env_legacy_warrior_flag_value()
	var models_on: bool = is_models_flag_enabled()
	var legacy_on: bool = is_legacy_warrior_flag_enabled()
	var enable_3d: bool = is_enabled()
	print(
		(
			"[Unit3D flags] EMPIRE_USE_3D_MODELS='%s' EMPIRE_USE_3D_WARRIOR='%s' "
			+ "enable_3d_models=%s enable_warrior_3d=%s enable_settler_3d=%s"
		)
		% [
			models_val,
			legacy_val,
			str(enable_3d),
			str(should_render_unit_as_3d("warrior")),
			str(should_render_unit_as_3d("settler")),
		]
	)
