# Debug-only GLB character figures on the real-3D map composite (presentation only).
# Gate: EOM_DEBUG_EXTRA_3D_CHARACTERS=1 (+ EMPIRE_USE_3D_MODELS=1 + EOM_REAL_3D_UNITS=1).
# Niclas animation cycle: EOM_NICLAS_3D_DIAG=1 + KEY_F10.
class_name DebugCharacter3DTestView
extends Node3D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Unit3DWorldViewScript = preload("res://presentation/unit_3d_world_view.gd")
const City3DWorldViewScript = preload("res://presentation/city_3d_world_view.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

const BRONZE_GLB_PATH: String = (
	"res://assets/prototype/3d/units/bronze_armed_warrior/bronze_armed_warrior_3d.glb"
)
const NICLAS_GLB_PATH: String = "res://assets/prototype/3d/units/niclas/niclas_3d.glb"
const MODEL_ROOT_NAME: String = "ModelRoot"
const ASSET_BRONZE: String = "bronze_armed_warrior"
const ASSET_NICLAS: String = "niclas"
const NICLAS_CYCLE_KEY: Key = KEY_F10
## Settler at (0,0) -> Niclas at (0,1) SE; warrior at (1,0) -> bronze at (1,-1) NE.
const NICLAS_HEX_OFFSET_FROM_SETTLER: Vector2i = Vector2i(0, 1)
const BRONZE_HEX_OFFSET_FROM_WARRIOR: Vector2i = Vector2i(0, -1)

@export_group("Bronze-Armed Warrior debug")
@export var bronze_model_scale_3d: float = 75.0
@export var bronze_reference_world_y: float = 0.0
@export var bronze_model_yaw_degrees: float = 48.0
@export var bronze_model_pitch_degrees: float = 0.0
@export var bronze_model_offset_y_local: float = 0.0
@export var bronze_model_world_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

@export_group("Niclas debug")
@export var niclas_model_scale_3d: float = 75.0
@export var niclas_reference_world_y: float = 0.0
@export var niclas_model_yaw_degrees: float = 48.0
@export var niclas_model_pitch_degrees: float = 0.0
@export var niclas_model_offset_y_local: float = 0.0
@export var niclas_model_world_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

var scenario
var layout

var _world_camera: Camera3D
var _map_camera
var _map_layer_origin: Vector2 = Vector2.ZERO
var _world_camera_back_distance: float = -1.0

var _bronze_root: Node3D
var _niclas_root: Node3D
var _bronze_scene: PackedScene
var _niclas_scene: PackedScene
var _sync_frame: int = -1

var _niclas_clip_names: PackedStringArray = PackedStringArray()
var _niclas_clip_index: int = 0
var _niclas_idle_clip: String = ""
var _bronze_idle_clip: String = ""
var _logged_bronze_catalog: bool = false


static func is_gate_enabled() -> bool:
	return Warrior3DExperimentScript.env_debug_extra_3d_characters_enabled()


static func is_active() -> bool:
	return is_gate_enabled() and Warrior3DExperimentScript.env_real_3d_units_enabled()


static func bronze_scene_path() -> String:
	return BRONZE_GLB_PATH if ResourceLoader.exists(BRONZE_GLB_PATH) else ""


static func niclas_scene_path() -> String:
	return NICLAS_GLB_PATH if ResourceLoader.exists(NICLAS_GLB_PATH) else ""


func get_active_debug_character_count() -> int:
	var count: int = 0
	if _is_live_root(_bronze_root):
		count += 1
	if _is_live_root(_niclas_root):
		count += 1
	return count


func has_bronze_instance() -> bool:
	return _is_live_root(_bronze_root)


func has_niclas_instance() -> bool:
	return _is_live_root(_niclas_root)


func niclas_animation_catalog() -> PackedStringArray:
	return _niclas_clip_names.duplicate()


func niclas_idle_clip_name() -> String:
	return _niclas_idle_clip


func bronze_idle_clip_name() -> String:
	return _bronze_idle_clip


func niclas_placement_hex() -> Vector2i:
	return _target_hex_for_asset(ASSET_NICLAS)


func bronze_placement_hex() -> Vector2i:
	return _target_hex_for_asset(ASSET_BRONZE)


func set_placement_context(
	world_cam: Camera3D, map_cam, layer_origin: Vector2, camera_back_distance: float = -1.0
) -> void:
	_world_camera = world_cam
	_map_camera = map_cam
	_map_layer_origin = layer_origin
	_world_camera_back_distance = camera_back_distance


func prepare_for_draw() -> void:
	_sync_once_per_frame()
	_refresh_placements()


func refresh_placements() -> void:
	_refresh_placements()


func sync_from_scenario() -> void:
	_sync_instances()


func handle_input(event: InputEvent) -> bool:
	if not is_active() or not Warrior3DExperimentScript.env_niclas_3d_diag_enabled():
		return false
	if not (event is InputEventKey):
		return false
	var ek: InputEventKey = event as InputEventKey
	if not ek.pressed or ek.echo or ek.keycode != NICLAS_CYCLE_KEY:
		return false
	_cycle_niclas_animation()
	return true


func _sync_once_per_frame() -> void:
	var frame: int = Engine.get_frames_drawn()
	if _sync_frame == frame:
		return
	_sync_frame = frame
	_sync_instances()


func _sync_instances() -> void:
	if not is_active():
		_clear_instances()
		visible = false
		return
	visible = true
	if scenario == null or layout == null:
		return
	_ensure_character(ASSET_BRONZE)
	_ensure_character(ASSET_NICLAS)
	_refresh_placements()


func _ensure_character(asset_key: String) -> void:
	var scene_path: String = bronze_scene_path() if asset_key == ASSET_BRONZE else niclas_scene_path()
	if scene_path.is_empty():
		push_warning("[DebugCharacter3D] missing GLB for asset=%s" % asset_key)
		return
	if not _ensure_scene_loaded(asset_key, scene_path):
		return
	var root: Node3D = _bronze_root if asset_key == ASSET_BRONZE else _niclas_root
	if root == null:
		root = _create_character_instance(asset_key)
		if root == null:
			return
		if asset_key == ASSET_BRONZE:
			_bronze_root = root
		else:
			_niclas_root = root
	var idle_clip: String = _bronze_idle_clip if asset_key == ASSET_BRONZE else _niclas_idle_clip
	if not idle_clip.is_empty():
		_play_clip(root, idle_clip, true)


func _create_character_instance(asset_key: String) -> Node3D:
	var scene: PackedScene = _bronze_scene if asset_key == ASSET_BRONZE else _niclas_scene
	if scene == null:
		return null
	var unit_root := Node3D.new()
	unit_root.name = "DebugCharacter3D_%s" % asset_key
	var model_root := Node3D.new()
	model_root.name = MODEL_ROOT_NAME
	var model: Node = scene.instantiate()
	if model == null:
		push_warning("[DebugCharacter3D] instantiate failed asset=%s" % asset_key)
		unit_root.queue_free()
		return null
	_apply_material_override(model)
	model_root.add_child(model)
	unit_root.add_child(model_root)
	add_child(unit_root)
	var clip_names: PackedStringArray = _animation_names_from_model(model)
	var idle_clip: String = pick_idle_clip_name(clip_names)
	if asset_key == ASSET_BRONZE:
		_bronze_idle_clip = idle_clip
		if not _logged_bronze_catalog:
			_logged_bronze_catalog = true
			print(
				"[DebugCharacter3D] asset=%s animations=[%s] idle_candidate=%s"
				% [asset_key, ", ".join(clip_names), idle_clip]
			)
	else:
		_niclas_clip_names = clip_names
		_niclas_clip_index = _index_of_clip(clip_names, idle_clip)
		_niclas_idle_clip = idle_clip
		print(
			"[DebugCharacter3D] asset=niclas animations=[%s] idle_candidate=%s cycle_key=F10 diag=%s"
			% [
				", ".join(clip_names),
				idle_clip,
				str(Warrior3DExperimentScript.env_niclas_3d_diag_enabled()),
			]
		)
	if not idle_clip.is_empty():
		_play_clip(unit_root, idle_clip, true)
	var hex: Vector2i = _target_hex_for_asset(asset_key)
	print(
		"[DebugCharacter3D] created asset=%s hex=(%d,%d) scale=%.1f yaw=%.1f offset_local=%.3f"
		% [
			asset_key,
			hex.x,
			hex.y,
			_scale_for_asset(asset_key),
			_yaw_for_asset(asset_key),
			_offset_y_local_for_asset(asset_key),
		]
	)
	return unit_root


func _refresh_placements() -> void:
	if not is_active():
		return
	if _is_live_root(_bronze_root):
		_apply_instance_transform(_bronze_root, ASSET_BRONZE)
	if _is_live_root(_niclas_root):
		_apply_instance_transform(_niclas_root, ASSET_NICLAS)


func _apply_instance_transform(unit_root: Node3D, asset_key: String) -> void:
	var pos_global: Vector3 = _placement_position_global(asset_key, unit_root)
	if unit_root.is_inside_tree():
		unit_root.global_position = pos_global
	else:
		unit_root.position = pos_global
	unit_root.rotation_degrees = Vector3(
		_pitch_for_asset(asset_key), _yaw_for_asset(asset_key), 0.0
	)
	unit_root.scale = Vector3.ONE * _effective_scale_for_asset(asset_key)
	_reassert_model_root_frame(unit_root, asset_key)


func _reassert_model_root_frame(unit_root: Node3D, asset_key: String) -> void:
	var model_root: Node3D = unit_root.get_node_or_null(MODEL_ROOT_NAME) as Node3D
	if model_root == null:
		return
	model_root.position = Vector3(0.0, _offset_y_local_for_asset(asset_key), 0.0)
	model_root.rotation_degrees = Vector3.ZERO
	model_root.scale = Vector3.ONE
	var ci: int = 0
	while ci < model_root.get_child_count():
		var child: Node = model_root.get_child(ci)
		if child is Node3D:
			var child_3d: Node3D = child as Node3D
			child_3d.position = Vector3.ZERO
			child_3d.rotation_degrees = Vector3.ZERO
			child_3d.scale = Vector3.ONE
		ci += 1


func _placement_position_global(asset_key: String, root: Node3D) -> Vector3:
	var world_2d: Vector2 = _world_2d_for_asset(asset_key)
	var world_offset: Vector3 = (
		bronze_model_world_offset if asset_key == ASSET_BRONZE else niclas_model_world_offset
	)
	var fallback: Vector3 = Vector3(world_2d.x, 0.0, world_2d.y) + world_offset
	if _world_camera == null or _map_camera == null or layout == null:
		return fallback
	var anchor_2d: Vector2 = City3DWorldViewScript.compute_anchor_2d(
		world_2d, _map_camera, _map_layer_origin
	)
	var hit_global: Vector3 = City3DWorldViewScript.ray_intersect_ground_y0(_world_camera, anchor_2d)
	if not hit_global.is_finite():
		if root.is_inside_tree():
			return root.global_position
		return fallback
	return hit_global + world_offset


func _world_2d_for_asset(asset_key: String) -> Vector2:
	var hex: Vector2i = _target_hex_for_asset(asset_key)
	if layout == null:
		return Vector2(float(hex.x), float(hex.y))
	return layout.hex_to_world(hex.x, hex.y)


func _target_hex_for_asset(asset_key: String) -> Vector2i:
	if asset_key == ASSET_NICLAS:
		return _reference_hex_for_type("settler") + NICLAS_HEX_OFFSET_FROM_SETTLER
	return _reference_hex_for_type("warrior") + BRONZE_HEX_OFFSET_FROM_WARRIOR


func _reference_hex_for_type(type_id: String) -> Vector2i:
	if scenario == null:
		return Vector2i.ZERO
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		var unit = ulist[i]
		if str(unit.type_id) == type_id and int(unit.owner_id) == 0:
			return Vector2i(int(unit.position.q), int(unit.position.r))
		i += 1
	i = 0
	while i < ulist.size():
		var unit = ulist[i]
		if str(unit.type_id) == type_id:
			return Vector2i(int(unit.position.q), int(unit.position.r))
		i += 1
	return Vector2i.ZERO


func _cycle_niclas_animation() -> void:
	if not _is_live_root(_niclas_root) or _niclas_clip_names.is_empty():
		return
	_niclas_clip_index = (_niclas_clip_index + 1) % _niclas_clip_names.size()
	var clip_name: String = _niclas_clip_names[_niclas_clip_index]
	var forced_loop: bool = _play_clip(_niclas_root, clip_name, true)
	var duration: float = _clip_duration_sec(_niclas_root, clip_name)
	print(
		(
			"[DebugCharacter3D] asset=niclas animation_index=%d clip=%s duration=%.3f "
			+ "loop_forced=%s"
		)
		% [_niclas_clip_index, clip_name, duration, str(forced_loop)]
	)


func _play_clip(root: Node3D, clip_name: String, force_loop: bool) -> bool:
	var player: AnimationPlayer = _animation_player_for_root(root)
	if player == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return false
	var anim: Animation = player.get_animation(clip_name)
	if anim != null and force_loop:
		anim.loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = 1.0
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.play(clip_name)
	return force_loop


func _clip_duration_sec(root: Node3D, clip_name: String) -> float:
	var player: AnimationPlayer = _animation_player_for_root(root)
	if player == null:
		return 0.0
	var anim: Animation = player.get_animation(clip_name)
	if anim == null:
		return 0.0
	return anim.length


func _animation_player_for_root(root: Node3D) -> AnimationPlayer:
	if root == null:
		return null
	var model_root: Node3D = root.get_node_or_null(MODEL_ROOT_NAME) as Node3D
	if model_root == null:
		return null
	var ci: int = 0
	while ci < model_root.get_child_count():
		var found: AnimationPlayer = _find_animation_player(model_root.get_child(ci))
		if found != null:
			return found
		ci += 1
	return null


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	var children: Array = node.get_children()
	var i: int = 0
	while i < children.size():
		var found: AnimationPlayer = _find_animation_player(children[i] as Node)
		if found != null:
			return found
		i += 1
	return null


static func _animation_names_from_model(model: Node) -> PackedStringArray:
	var player: AnimationPlayer = _find_animation_player(model)
	if player == null:
		return PackedStringArray()
	return player.get_animation_list()


static func pick_idle_clip_name(names: PackedStringArray) -> String:
	if names.is_empty():
		return ""
	var exact_prefs: Array = ["Idle_3", "Idle", "idle", "Stand", "TPose", "T-Pose", "Rest"]
	var pi: int = 0
	while pi < exact_prefs.size():
		var pref: String = str(exact_prefs[pi])
		var ni: int = 0
		while ni < names.size():
			if names[ni] == pref:
				return names[ni]
			ni += 1
		pi += 1
	var ni2: int = 0
	while ni2 < names.size():
		var low: String = names[ni2].to_lower()
		if low.contains("idle") or low.contains("stand"):
			return names[ni2]
		ni2 += 1
	var ni3: int = 0
	while ni3 < names.size():
		if not _is_locomotion_clip(names[ni3]):
			return names[ni3]
		ni3 += 1
	return names[0]


static func _is_locomotion_clip(name: String) -> bool:
	var low: String = name.to_lower()
	return low.contains("walk") or low.contains("run") or low.contains("move")


static func _index_of_clip(names: PackedStringArray, clip_name: String) -> int:
	var i: int = 0
	while i < names.size():
		if names[i] == clip_name:
			return i
		i += 1
	return 0


func _ensure_scene_loaded(asset_key: String, scene_path: String) -> bool:
	var cached: PackedScene = _bronze_scene if asset_key == ASSET_BRONZE else _niclas_scene
	if cached != null:
		return true
	var scene: PackedScene = (
		ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	)
	if scene == null:
		push_warning("[DebugCharacter3D] failed to load %s" % scene_path)
		return false
	if asset_key == ASSET_BRONZE:
		_bronze_scene = scene
	else:
		_niclas_scene = scene
	return true


func _clear_instances() -> void:
	if _bronze_root != null:
		_bronze_root.queue_free()
		_bronze_root = null
	if _niclas_root != null:
		_niclas_root.queue_free()
		_niclas_root = null
	_niclas_clip_names = PackedStringArray()
	_niclas_clip_index = 0
	_niclas_idle_clip = ""
	_bronze_idle_clip = ""
	_logged_bronze_catalog = false


func _is_live_root(root: Node3D) -> bool:
	return root != null and is_instance_valid(root) and root.is_inside_tree()


func _effective_scale_for_asset(asset_key: String) -> float:
	if _map_camera == null:
		return _scale_for_asset(asset_key)
	return Unit3DWorldViewScript.effective_scale_at_world(
		_map_camera,
		_scale_for_asset(asset_key),
		_reference_world_y_for_asset(asset_key),
		_world_2d_for_asset(asset_key),
	)


func _scale_for_asset(asset_key: String) -> float:
	return bronze_model_scale_3d if asset_key == ASSET_BRONZE else niclas_model_scale_3d


func _reference_world_y_for_asset(asset_key: String) -> float:
	return bronze_reference_world_y if asset_key == ASSET_BRONZE else niclas_reference_world_y


func _yaw_for_asset(asset_key: String) -> float:
	return bronze_model_yaw_degrees if asset_key == ASSET_BRONZE else niclas_model_yaw_degrees


func _pitch_for_asset(asset_key: String) -> float:
	return bronze_model_pitch_degrees if asset_key == ASSET_BRONZE else niclas_model_pitch_degrees


func _offset_y_local_for_asset(asset_key: String) -> float:
	return bronze_model_offset_y_local if asset_key == ASSET_BRONZE else niclas_model_offset_y_local


func _apply_material_override(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		var si: int = 0
		while si < mesh.get_surface_count():
			var src_mat: Material = mesh_inst.get_surface_override_material(si)
			if src_mat == null:
				src_mat = mesh.surface_get_material(si)
			if src_mat is StandardMaterial3D:
				var override_mat: StandardMaterial3D = src_mat.duplicate() as StandardMaterial3D
				override_mat.metallic = Unit3DWorldViewScript.UNIT_MAT_OVERRIDE_METALLIC
				override_mat.roughness = Unit3DWorldViewScript.UNIT_MAT_OVERRIDE_ROUGHNESS
				override_mat.metallic_specular = Unit3DWorldViewScript.UNIT_MAT_OVERRIDE_SPECULAR
				mesh_inst.set_surface_override_material(si, override_mat)
			si += 1
