# Dev-only presentation experiment: render warrior/settler units from 3D GLBs on the 2D map.
# EMPIRE_USE_3D_MODELS=1 enables warrior + settler. EMPIRE_USE_3D_WARRIOR=1 enables warrior only.
# No gameplay/domain changes.
class_name Warrior3DUnitExperiment
extends RefCounted

const ENV_FLAG: String = "EMPIRE_USE_3D_MODELS"
const ENV_FLAG_LEGACY: String = "EMPIRE_USE_3D_WARRIOR"
const WARRIOR_GLB_PATH: String = "res://assets/prototype/3d/units/warrior/warrior_3d.glb"
const WARRIOR_ANIMATED_GLB_PATH: String = (
	"res://assets/prototype/3d/units/warrior/warrior_3d_animations.glb"
)
const SETTLER_GLB_PATH: String = "res://assets/prototype/3d/units/settler/settler.glb"
const SETTLER_ANIMATED_GLB_PATH: String = (
	"res://assets/prototype/3d/units/settler/settler_animations.glb"
)
const ANCIENT_VILLAGE_GLB_PATH: String = (
	"res://assets/prototype/3d/cities/ancient_village/ancient_village.glb"
)
const MAP_ANIMATION_ENV: String = "EOM_WARRIOR_3D_ANIM"
const ANIM_AUDIT_ENV: String = "EOM_WARRIOR_3D_ANIM_AUDIT"
## TEMPORARY probe: built-in AnimationPlayer root_motion_track instead of manual anchor cancel.
const SETTLER_BUILTIN_RM_ENV: String = "EOM_SETTLER_BUILTIN_RM"
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


static func is_settler_builtin_root_motion_enabled() -> bool:
	return OS.get_environment(SETTLER_BUILTIN_RM_ENV).strip_edges() == "1"


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


static func city_scene_path() -> String:
	if ResourceLoader.exists(ANCIENT_VILLAGE_GLB_PATH):
		return ANCIENT_VILLAGE_GLB_PATH
	return ""


static func should_render_city_as_3d() -> bool:
	return is_models_flag_enabled() and not city_scene_path().is_empty()


## Env **EOM_REAL_3D_CITY=0** disables real scene 3D cities (SubViewport blit remains if enabled).
static func env_real_3d_city_disabled() -> bool:
	return OS.get_environment("EOM_REAL_3D_CITY").strip_edges() == "0"


## Env **EOM_CITY_BLIT_FALLBACK=1** keeps SubViewport blit alongside real scene 3D cities.
static func env_city_blit_fallback_enabled() -> bool:
	return OS.get_environment("EOM_CITY_BLIT_FALLBACK").strip_edges() == "1"


## TEMP DIAG — env **EOM_CITY3D_DEBUG_PROBE=1**: opaque composite bg + origin/city marker cubes.
static func env_city3d_debug_probe_enabled() -> bool:
	return OS.get_environment("EOM_CITY3D_DEBUG_PROBE").strip_edges() == "1"


const ENV_REAL_3D_UNITS: String = "EOM_REAL_3D_UNITS"


## Env **EOM_REAL_3D_UNITS=1** (requires **EMPIRE_USE_3D_MODELS=1**): warrior + settler Node3D in map composite.
static func env_real_3d_units_enabled() -> bool:
	return is_models_flag_enabled() and OS.get_environment(ENV_REAL_3D_UNITS).strip_edges() == "1"


## True when **type_id** should use **Unit3DWorldView** (not per-unit SubViewport blit).
static func uses_real_3d_composite_for_type(type_id: String) -> bool:
	var tid: String = str(type_id)
	if tid != "warrior" and tid != "settler":
		return false
	return env_real_3d_units_enabled() and should_render_unit_as_3d(tid)


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
			+ "EOM_REAL_3D_UNITS='%s' EOM_SETTLER_BUILTIN_RM='%s' enable_3d_models=%s "
			+ "enable_warrior_3d=%s enable_settler_3d=%s enable_city_3d=%s settler_builtin_rm=%s"
		)
		% [
			models_val,
			legacy_val,
			OS.get_environment(ENV_REAL_3D_UNITS).strip_edges(),
			OS.get_environment(SETTLER_BUILTIN_RM_ENV).strip_edges(),
			str(enable_3d),
			str(should_render_unit_as_3d("warrior")),
			str(should_render_unit_as_3d("settler")),
			str(should_render_city_as_3d()),
			str(is_settler_builtin_root_motion_enabled()),
		]
	)
