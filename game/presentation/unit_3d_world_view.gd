# Real 3D warrior instances on the map plane (presentation only; one Node3D per warrior).
class_name Unit3DWorldView
extends Node3D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const Warrior3DWalkSyncScript = preload("res://presentation/warrior_3d_walk_sync.gd")
const City3DWorldViewScript = preload("res://presentation/city_3d_world_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

const UNIT_MAT_OVERRIDE_METALLIC: float = 0.0
const UNIT_MAT_OVERRIDE_ROUGHNESS: float = 0.85
const UNIT_MAT_OVERRIDE_SPECULAR: float = 0.3
const HEX_MOVE_WALK_ANIM_SPEED: float = 0.5
const SEMANTIC_IDLE_CLIP: String = "Idle_3"
const SEMANTIC_WALK_CLIP: String = "Walking"
const WARRIOR_TYPE_ID: String = "warrior"
const MODEL_ROOT_NAME: String = "ModelRoot"

## Base scale tuned at [member reference_world_y] (pan=0, zoom=1); row factor applied per frame.
@export var model_scale_3d: float = 155.0
## Layout world_y where [member model_scale_3d] was tuned (pan-free reference for perspective ratio).
@export var reference_world_y: float = 0.0
@export var model_yaw_degrees: float = 48.0
@export var model_pitch_degrees: float = 0.0
@export var model_world_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Model-local Y lift (pre-scale). World path anchors UnitRoot at ground; keep 0 unless bind-pose needs lift.
@export var model_offset_y_local: float = 0.0
@export var travel_facing_yaw_offset_deg: float = 69.0
@export_range(0.2, 2.0) var hex_stride_cycle_fraction: float = 1.15
@export var use_glb_animation_name_remap: bool = true
@export_range(0.20, 0.35, 0.01) var idle_end_blend_sec: float = 0.28

var scenario
var layout

var _world_camera: Camera3D
var _map_camera
var _map_layer_origin: Vector2 = Vector2.ZERO
var _world_camera_back_distance: float = -1.0

var _warrior_scene: PackedScene
var _instance_by_unit_id: Dictionary = {}
var _type_id_by_unit_id: Dictionary = {}
var _sync_frame: int = -1
var _active_hex_moves: Dictionary = {}
var _facing_yaw_by_unit_id: Dictionary = {}
var _ray_parallel_warned: Dictionary = {}
var _logged_placement_diag: Dictionary = {}


func set_placement_context(
	world_cam: Camera3D, map_cam, layer_origin: Vector2, camera_back_distance: float = -1.0
) -> void:
	_world_camera = world_cam
	_map_camera = map_cam
	_map_layer_origin = layer_origin
	_world_camera_back_distance = camera_back_distance


func is_real_3d_active() -> bool:
	return Warrior3DExperimentScript.env_real_3d_units_enabled()


func get_active_warrior_count() -> int:
	return _instance_by_unit_id.size()


func has_unit_instance(unit_id: int) -> bool:
	return _instance_by_unit_id.has(unit_id)


func has_ready_unit_instance(unit_id: int) -> bool:
	var root: Node3D = _instance_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return false
	if not is_instance_valid(root):
		return false
	if not root.is_inside_tree():
		return false
	if not root.visible:
		return false
	if root.get_node_or_null(MODEL_ROOT_NAME) == null:
		return false
	return true


func first_unit_instance() -> Node3D:
	for k in _instance_by_unit_id.keys():
		var inst: Node3D = _instance_by_unit_id[k] as Node3D
		if inst != null and is_instance_valid(inst):
			return inst
	return null


func is_unit_hex_move_active(unit_id: int) -> bool:
	return _active_hex_moves.has(unit_id)


func hex_move_progress(unit_id: int) -> float:
	if not _active_hex_moves.has(unit_id):
		return 0.0
	return float(_active_hex_moves[unit_id].get("progress", 0.0))


func prepare_for_draw() -> void:
	_sync_once_per_frame()
	_refresh_placements()


func refresh_placements() -> void:
	_refresh_placements()


func sync_from_scenario() -> void:
	_sync_instances()


func begin_hex_move(
	unit_id: int,
	type_id: String,
	from_q: int,
	from_r: int,
	to_q: int,
	to_r: int,
) -> void:
	if not is_real_3d_active():
		return
	if str(type_id) != WARRIOR_TYPE_ID:
		return
	if layout == null:
		return
	if _map_camera == null:
		_map_camera = MapCameraScript.new()
	var from_world: Vector2 = layout.hex_to_world(from_q, from_r)
	var to_world: Vector2 = layout.hex_to_world(to_q, to_r)
	var from_pres: Vector2 = _map_camera.to_presentation(from_world)
	var to_pres: Vector2 = _map_camera.to_presentation(to_world)
	var pres_dir: Vector2 = to_pres - from_pres
	var facing: Dictionary = _travel_facing_from_hex_step(from_world, to_world, pres_dir, unit_id)
	var facing_yaw: float = float(facing["model_yaw"])
	_facing_yaw_by_unit_id[unit_id] = facing_yaw
	var walk_glb: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	_active_hex_moves[unit_id] = {
		"type_id": type_id,
		"from_q": from_q,
		"from_r": from_r,
		"to_q": to_q,
		"to_r": to_r,
		"progress": 0.0,
		"anim_elapsed_sec": 0.0,
		"facing_yaw": facing_yaw,
		"pres_dir": pres_dir,
	}
	var root: Node3D = _instance_by_unit_id.get(unit_id) as Node3D
	if root != null:
		_apply_instance_transform(root, unit_id)
		_play_clip_on_instance(root, walk_glb, HEX_MOVE_WALK_ANIM_SPEED, 0.0, type_id)


func _process(delta: float) -> void:
	if not is_real_3d_active() or _active_hex_moves.is_empty():
		return
	_tick_hex_moves(delta)
	_refresh_placements()


func _sync_once_per_frame() -> void:
	var frame: int = Engine.get_frames_drawn()
	if _sync_frame == frame:
		return
	_sync_frame = frame
	_sync_instances()


func _sync_instances() -> void:
	if not is_real_3d_active():
		_clear_all_instances()
		return
	if scenario == null or layout == null:
		return
	_load_warrior_scene()
	if _warrior_scene == null:
		push_warning("[Unit3D world] GLB scene failed to load; no real 3D warrior instances")
		return
	var active_ids: Dictionary = {}
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		var unit = ulist[i]
		var type_id: String = str(unit.type_id)
		if type_id != WARRIOR_TYPE_ID:
			i += 1
			continue
		var unit_id: int = int(unit.id)
		active_ids[unit_id] = true
		_type_id_by_unit_id[unit_id] = type_id
		var root: Node3D = _instance_by_unit_id.get(unit_id) as Node3D
		if root == null:
			root = _create_unit_instance(unit_id, unit)
			if root == null:
				i += 1
				continue
		if not _active_hex_moves.has(unit_id):
			_apply_idle_animation(root, type_id)
		_apply_instance_transform(root, unit_id)
		i += 1
	var stale: Array = _instance_by_unit_id.keys()
	var si: int = 0
	while si < stale.size():
		var stale_id: int = int(stale[si])
		if not active_ids.has(stale_id):
			var node: Node = _instance_by_unit_id[stale_id] as Node
			if node != null:
				node.queue_free()
			_instance_by_unit_id.erase(stale_id)
			_type_id_by_unit_id.erase(stale_id)
			_active_hex_moves.erase(stale_id)
			_facing_yaw_by_unit_id.erase(stale_id)
			_logged_placement_diag.erase(stale_id)
		si += 1


func _create_unit_instance(unit_id: int, unit) -> Node3D:
	var unit_root := Node3D.new()
	unit_root.name = "Unit3D_%d" % unit_id
	var model_root := Node3D.new()
	model_root.name = MODEL_ROOT_NAME
	var model: Node = _warrior_scene.instantiate()
	if model == null:
		push_warning("Unit3DWorldView: instantiate failed for unit_id=%d" % unit_id)
		return null
	_apply_material_override(model)
	model_root.add_child(model)
	unit_root.add_child(model_root)
	add_child(unit_root)
	_instance_by_unit_id[unit_id] = unit_root
	_type_id_by_unit_id[unit_id] = WARRIOR_TYPE_ID
	_prime_walk_clip_length(model)
	_apply_idle_animation(unit_root, WARRIOR_TYPE_ID)
	print(
		(
			"[Unit3D world] created unit_id=%d hex=(%d,%d) type=%s render=real_scene_3d "
			+ "scenario_units=%d scale=%.1f offset_local=%.3f"
		)
		% [
			unit_id,
			int(unit.position.q),
			int(unit.position.r),
			WARRIOR_TYPE_ID,
			scenario.units().size() if scenario != null else 0,
			model_scale_3d,
			model_offset_y_local,
		]
	)
	return unit_root


func _refresh_placements() -> void:
	if not is_real_3d_active() or scenario == null:
		return
	for unit_id_key in _instance_by_unit_id.keys():
		var unit_id: int = int(unit_id_key)
		var root: Node3D = _instance_by_unit_id[unit_id] as Node3D
		if root != null:
			_apply_instance_transform(root, unit_id)


func _apply_instance_transform(unit_root: Node3D, unit_id: int) -> void:
	var pos_global: Vector3 = _placement_position_global_for_unit(unit_id, unit_root)
	if unit_root.is_inside_tree():
		unit_root.global_position = pos_global
	else:
		unit_root.position = pos_global
	var yaw: float = _facing_yaw_for_unit(unit_id)
	unit_root.rotation_degrees = Vector3(model_pitch_degrees, yaw, 0.0)
	var world_2d: Vector2 = _world_2d_for_unit(unit_id)
	unit_root.scale = Vector3.ONE * _effective_scale_for_world(world_2d)
	_reassert_model_root_frame(unit_root)
	_log_placement_diag_once(unit_id, unit_root)


func _reassert_model_root_frame(unit_root: Node3D) -> void:
	var model_root: Node3D = unit_root.get_node_or_null(MODEL_ROOT_NAME) as Node3D
	if model_root == null:
		return
	model_root.position = Vector3(0.0, model_offset_y_local, 0.0)
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


func _placement_position_global_for_unit(unit_id: int, root: Node3D) -> Vector3:
	var world_2d: Vector2 = _world_2d_for_unit(unit_id)
	var fallback: Vector3 = _layout_world_to_fallback_3d(world_2d)
	if _world_camera == null or _map_camera == null or layout == null:
		return fallback
	var anchor_2d: Vector2 = City3DWorldViewScript.compute_anchor_2d(
		world_2d, _map_camera, _map_layer_origin
	)
	var hit_global: Vector3 = City3DWorldViewScript.ray_intersect_ground_y0(_world_camera, anchor_2d)
	if not hit_global.is_finite():
		_warn_ray_parallel_once(unit_id, anchor_2d)
		if root.is_inside_tree():
			return root.global_position
		return fallback
	return hit_global + model_world_offset


func _log_placement_diag_once(unit_id: int, unit_root: Node3D) -> void:
	if _logged_placement_diag.has(unit_id):
		return
	if _world_camera == null or _map_camera == null or layout == null:
		return
	_logged_placement_diag[unit_id] = true
	var world_2d: Vector2 = _world_2d_for_unit(unit_id)
	var anchor_2d: Vector2 = City3DWorldViewScript.compute_anchor_2d(
		world_2d, _map_camera, _map_layer_origin
	)
	var ray_origin: Vector3 = _world_camera.project_ray_origin(anchor_2d)
	var ray_dir: Vector3 = _world_camera.project_ray_normal(anchor_2d)
	var ground_hit: Vector3 = City3DWorldViewScript.ray_intersect_ground_y0(_world_camera, anchor_2d)
	unit_root.force_update_transform()
	var mesh_aabb: AABB = combined_mesh_global_aabb(unit_root)
	var feet_global: Vector3 = mesh_feet_global(unit_root)
	var top_global: Vector3 = mesh_top_global(unit_root)
	var feet_2d: Vector2 = projected_mesh_feet_2d(_world_camera, unit_root)
	var height_px: float = projected_mesh_height_px(_world_camera, unit_root)
	var delta_px: float = feet_2d.distance_to(anchor_2d)
	var cam_forward: Vector3 = camera_forward_vector(_world_camera)
	var feet_depth: float = camera_forward_depth(_world_camera, feet_global)
	var top_depth: float = camera_forward_depth(_world_camera, top_global)
	var feet_in_frustum: bool = is_in_camera_frustum(_world_camera, feet_global)
	var top_in_frustum: bool = is_in_camera_frustum(_world_camera, top_global)
	var arm_len: float = camera_arm_length(_world_camera)
	var subvp_size: Vector2i = Vector2i.ZERO
	var container_rect: Rect2 = Rect2()
	var vp: SubViewport = _world_camera.get_viewport() as SubViewport
	if vp != null:
		subvp_size = vp.size
		var container: SubViewportContainer = vp.get_parent() as SubViewportContainer
		if container != null:
			container_rect = Rect2(container.position, container.size)
	var pscale: float = _map_camera.perspective_scale_at(world_2d)
	var factor_zoom_free: float = perspective_factor_zoom_free(_map_camera, world_2d)
	var ref_factor: float = reference_perspective_factor(_map_camera, reference_world_y)
	var effective_scale: float = _effective_scale_for_world(world_2d)
	var expected_blit_h: float = expected_blit_marker_height_from_pscale(pscale)
	var height_ratio_est: float = (
		effective_scale / model_scale_3d if model_scale_3d > 0.0 else 0.0
	)
	var model_root: Node3D = unit_root.get_node_or_null(MODEL_ROOT_NAME) as Node3D
	var anim_name: String = ""
	var anim_time: float = -1.0
	var player: AnimationPlayer = _animation_player_for_root(unit_root)
	if player != null:
		anim_name = str(player.current_animation)
		anim_time = player.current_animation_position
	print(
		(
			"[Unit3D placement diag] unit_id=%d type=%s hex_world=%s anchor_2d=%s "
			+ "map_origin=%s pan=%s zoom=%.3f pscale=%.6f factor_zoom_free=%.6f "
			+ "reference_factor=%.6f base_scale=%.1f effective_scale=%.3f "
			+ "expected_blit_h_px=%.1f height_ratio_est=%.3f "
			+ "ray_origin=%s ray_dir=%s ground_hit=%s unit_root_global=%s "
			+ "model_root_local=%s feet_projected=%s mesh_world_aabb=%s "
			+ "mesh_height_px=%.1f delta_px=%.4f "
			+ "camera_near=%.1f camera_far=%.1f camera_arm_len=%.1f "
			+ "world_camera_back_distance=%.1f camera_forward=%s "
			+ "feet_depth=%.1f top_depth=%.1f feet_in_frustum=%s top_in_frustum=%s "
			+ "subvp_size=%s container_rect=%s anim=%s t=%.3f"
		)
		% [
			unit_id,
			WARRIOR_TYPE_ID,
			str(world_2d),
			str(anchor_2d),
			str(_map_layer_origin),
			str(_map_camera.camera_world_offset),
			_map_camera.zoom,
			pscale,
			factor_zoom_free,
			ref_factor,
			model_scale_3d,
			effective_scale,
			expected_blit_h,
			height_ratio_est,
			str(ray_origin),
			str(ray_dir),
			str(ground_hit),
			str(unit_root.global_position),
			str(model_root.transform if model_root != null else "n/a"),
			str(feet_2d),
			str(mesh_aabb),
			height_px,
			delta_px,
			_world_camera.near,
			_world_camera.far,
			arm_len,
			_world_camera_back_distance,
			str(cam_forward),
			feet_depth,
			top_depth,
			str(feet_in_frustum),
			str(top_in_frustum),
			str(subvp_size),
			str(container_rect),
			anim_name,
			anim_time,
		]
	)


static func combined_mesh_global_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var combined: AABB = AABB()
	var first: bool = true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = n as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		var world_aabb: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		if first:
			combined = world_aabb
			first = false
		else:
			combined = combined.merge(world_aabb)
	return combined


static func mesh_feet_global(root: Node3D) -> Vector3:
	var aabb: AABB = combined_mesh_global_aabb(root)
	if aabb.size.length_squared() <= 0.0:
		return root.global_position if root != null else Vector3.ZERO
	return Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5,
	)


static func mesh_top_global(root: Node3D) -> Vector3:
	var aabb: AABB = combined_mesh_global_aabb(root)
	if aabb.size.length_squared() <= 0.0:
		return root.global_position if root != null else Vector3.ZERO
	return Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y + aabb.size.y,
		aabb.position.z + aabb.size.z * 0.5,
	)


static func camera_forward_vector(camera: Camera3D) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	return -camera.global_transform.basis.z.normalized()


static func camera_forward_depth(camera: Camera3D, world_point: Vector3) -> float:
	if camera == null:
		return 0.0
	return camera_forward_vector(camera).dot(world_point - camera.global_position)


static func is_in_camera_frustum(camera: Camera3D, world_point: Vector3) -> bool:
	return camera != null and camera.is_position_in_frustum(world_point)


static func camera_arm_length(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	var center: Vector2 = camera.get_viewport().get_visible_rect().size * 0.5
	var ground: Vector3 = City3DWorldViewScript.ray_intersect_ground_y0(camera, center)
	if not ground.is_finite():
		return 0.0
	return camera.global_position.distance_to(ground)


static func projected_mesh_feet_2d(camera: Camera3D, root: Node3D) -> Vector2:
	if camera == null or root == null:
		return Vector2.ZERO
	return camera.unproject_position(mesh_feet_global(root))


static func projected_mesh_screen_bounds(camera: Camera3D, root: Node3D) -> Rect2:
	if camera == null or root == null:
		return Rect2()
	var aabb: AABB = combined_mesh_global_aabb(root)
	if aabb.size.length_squared() <= 0.0:
		return Rect2()
	var corners: Array = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.end,
	]
	var min_p: Vector2 = Vector2(INF, INF)
	var max_p: Vector2 = Vector2(-INF, -INF)
	var ci: int = 0
	while ci < corners.size():
		var sp: Vector2 = camera.unproject_position(corners[ci] as Vector3)
		min_p.x = minf(min_p.x, sp.x)
		min_p.y = minf(min_p.y, sp.y)
		max_p.x = maxf(max_p.x, sp.x)
		max_p.y = maxf(max_p.y, sp.y)
		ci += 1
	return Rect2(min_p, max_p - min_p)


static func projected_mesh_height_px(camera: Camera3D, root: Node3D) -> float:
	return projected_mesh_screen_bounds(camera, root).size.y


static func expected_blit_marker_height_px(zoom: float, icon_height_ratio: float = 0.70) -> float:
	return HexLayoutScript.SIZE * 2.0 * icon_height_ratio * zoom


static func expected_blit_marker_height_from_pscale(
	pscale: float, icon_height_ratio: float = 0.70
) -> float:
	return HexLayoutScript.SIZE * 2.0 * icon_height_ratio * pscale


static func perspective_factor_zoom_free(map_camera, world_2d: Vector2) -> float:
	if map_camera == null:
		return 1.0
	return map_camera.perspective_scale_at(world_2d) / maxf(map_camera.zoom, 0.001)


static func reference_perspective_factor(map_camera, reference_world_y: float) -> float:
	if map_camera == null or map_camera.projection == null:
		return 1.0
	return map_camera.projection.perspective_scale_at(Vector2(0.0, reference_world_y))


static func effective_scale_at_world(
	map_camera,
	base_scale: float,
	reference_world_y: float,
	world_2d: Vector2,
) -> float:
	var ref_factor: float = reference_perspective_factor(map_camera, reference_world_y)
	if ref_factor <= 0.0:
		return base_scale
	var factor: float = perspective_factor_zoom_free(map_camera, world_2d)
	return maxf(base_scale * factor / ref_factor, 0.01)


func _effective_scale_for_world(world_2d: Vector2) -> float:
	return Unit3DWorldView.effective_scale_at_world(
		_map_camera, model_scale_3d, reference_world_y, world_2d
	)


## Bind-pose mesh extent in world space before UnitRoot scale (headless AABB omits parent scale).
static func mesh_bind_world_extent_y(unit_root: Node3D) -> float:
	return combined_mesh_global_aabb(unit_root).size.y


static func mesh_scaled_world_extent_y(unit_root: Node3D, model_scale: float) -> float:
	return mesh_bind_world_extent_y(unit_root) * model_scale


## Linear estimate from diagnosed reference: scale 55 ≈ 60 px, target blit ≈ 174 px at scale ~165.
static func estimated_screen_height_from_reference_scale(
	model_scale: float,
	reference_scale: float = 55.0,
	reference_screen_px: float = 60.0,
) -> float:
	if reference_scale <= 0.0:
		return 0.0
	return reference_screen_px * (model_scale / reference_scale)


func _world_2d_for_unit(unit_id: int) -> Vector2:
	if _active_hex_moves.has(unit_id):
		var move: Dictionary = _active_hex_moves[unit_id]
		var from_world: Vector2 = layout.hex_to_world(
			int(move["from_q"]), int(move["from_r"])
		)
		var to_world: Vector2 = layout.hex_to_world(int(move["to_q"]), int(move["to_r"]))
		var t: float = float(move.get("progress", 0.0))
		return from_world.lerp(to_world, t)
	return _scenario_world_for_unit(unit_id)


func _scenario_world_for_unit(unit_id: int) -> Vector2:
	if scenario == null or layout == null:
		return Vector2.ZERO
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		var unit = ulist[i]
		if int(unit.id) == unit_id:
			return layout.hex_to_world(int(unit.position.q), int(unit.position.r))
		i += 1
	return Vector2.ZERO


func _layout_world_to_fallback_3d(world_2d: Vector2) -> Vector3:
	return Vector3(world_2d.x, 0.0, world_2d.y) + model_world_offset


func _warn_ray_parallel_once(unit_id: int, anchor_2d: Vector2) -> void:
	if _ray_parallel_warned.has(unit_id):
		return
	_ray_parallel_warned[unit_id] = true
	push_warning(
		"[Unit3D world] anchor ray-ground miss unit_id=%d anchor_2d=%s; keeping prior transform"
		% [unit_id, str(anchor_2d)]
	)


func _tick_hex_moves(delta: float) -> void:
	var finished_ids: Array = []
	for unit_id_key in _active_hex_moves.keys():
		var unit_id: int = int(unit_id_key)
		var move: Dictionary = _active_hex_moves[unit_id]
		var type_id: String = str(move.get("type_id", WARRIOR_TYPE_ID))
		var stride_sec: float = _hex_move_stride_anim_sec(type_id)
		var anim_elapsed: float = float(move.get("anim_elapsed_sec", 0.0))
		if anim_elapsed < stride_sec:
			anim_elapsed += delta * HEX_MOVE_WALK_ANIM_SPEED
			anim_elapsed = minf(anim_elapsed, stride_sec)
			move["anim_elapsed_sec"] = anim_elapsed
			var root: Node3D = _instance_by_unit_id.get(unit_id) as Node3D
			if root != null:
				_update_walk_animation(root, anim_elapsed, type_id)
				_reassert_model_root_frame(root)
		var progress: float = 1.0 if stride_sec <= 0.0 else clampf(anim_elapsed / stride_sec, 0.0, 1.0)
		if progress >= 1.0:
			finished_ids.append(unit_id)
		move["progress"] = progress
		_active_hex_moves[unit_id] = move
	var fi: int = 0
	while fi < finished_ids.size():
		var done_id: int = int(finished_ids[fi])
		_active_hex_moves.erase(done_id)
		var root_done: Node3D = _instance_by_unit_id.get(done_id) as Node3D
		if root_done != null:
			_apply_idle_animation(root_done, WARRIOR_TYPE_ID, idle_end_blend_sec)
			_apply_instance_transform(root_done, done_id)
		fi += 1


func _hex_move_stride_anim_sec(type_id: String) -> float:
	return (
		Warrior3DWalkSyncScript.resolved_walk_clip_length_sec(type_id)
		* hex_stride_cycle_fraction
	)


func _apply_idle_animation(root: Node3D, type_id: String, blend_sec: float = -1.0) -> void:
	var idle_glb: String = _glb_clip_for_semantic(SEMANTIC_IDLE_CLIP, type_id)
	_play_clip_on_instance(root, idle_glb, 1.0, blend_sec, type_id)


func _update_walk_animation(root: Node3D, anim_elapsed: float, type_id: String) -> void:
	var player: AnimationPlayer = _animation_player_for_root(root)
	if player == null:
		return
	var walk_clip: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	var walk_anim: Animation = player.get_animation(walk_clip)
	if walk_anim == null or walk_anim.length <= 0.0:
		return
	if str(player.current_animation) != walk_clip:
		player.speed_scale = HEX_MOVE_WALK_ANIM_SPEED
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.play(walk_clip)
		player.seek(0.0, true)
	var loop_len: float = maxf(walk_anim.length - 0.0001, 0.001)
	player.seek(fposmod(anim_elapsed, loop_len), true)
	player.advance(0.0)


func _play_clip_on_instance(
	root: Node3D,
	clip_name: String,
	anim_speed_scale: float,
	blend_sec: float,
	type_id: String,
) -> void:
	var player: AnimationPlayer = _animation_player_for_root(root)
	if player == null:
		return
	if not player.has_animation(clip_name):
		push_warning(
			"Unit3DWorldView: clip '%s' not found on %s"
			% [clip_name, Warrior3DExperimentScript.animated_scene_path_for_type(type_id)]
		)
		return
	var walk_clip: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	var manual_walk: bool = clip_name == walk_clip
	player.speed_scale = anim_speed_scale
	player.process_mode = (
		Node.PROCESS_MODE_DISABLED if manual_walk else Node.PROCESS_MODE_INHERIT
	)
	var anim: Animation = player.get_animation(clip_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	if blend_sec > 0.0:
		player.play(clip_name, blend_sec, -1.0)
	elif manual_walk:
		player.play(clip_name)
		player.seek(0.0, true)
	else:
		player.play(clip_name)


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


func _prime_walk_clip_length(model: Node) -> void:
	var player: AnimationPlayer = _find_animation_player(model)
	if player != null:
		Warrior3DWalkSyncScript.cache_walk_clip_length_from_player(
			player,
			use_glb_animation_name_remap,
			WARRIOR_TYPE_ID,
		)


func _glb_clip_for_semantic(semantic: String, type_id: String) -> String:
	return Warrior3DAnimationRemapScript.glb_clip_for_visual(
		semantic, use_glb_animation_name_remap, type_id
	)


func _facing_yaw_for_unit(unit_id: int) -> float:
	if _active_hex_moves.has(unit_id):
		return float(_active_hex_moves[unit_id].get("facing_yaw", model_yaw_degrees))
	if _facing_yaw_by_unit_id.has(unit_id):
		return float(_facing_yaw_by_unit_id[unit_id])
	return model_yaw_degrees


func _travel_facing_from_hex_step(
	from_world: Vector2,
	to_world: Vector2,
	pres_dir: Vector2,
	unit_id: int,
) -> Dictionary:
	var world_dir: Vector2 = to_world - from_world
	if world_dir.length_squared() < 0.0001:
		var idle_yaw: float = _facing_yaw_for_unit(unit_id)
		return {
			"plan_bearing_deg": 0.0,
			"map_bearing_deg": 0.0,
			"map_skew_deg": 0.0,
			"model_yaw": idle_yaw,
		}
	var plan_bearing_deg: float = _travel_bearing_screen_up_deg(world_dir)
	var map_bearing_deg: float = _travel_bearing_screen_up_deg(pres_dir)
	var map_skew_deg: float = _bearing_delta_deg(map_bearing_deg, plan_bearing_deg)
	var model_yaw: float = _yaw_for_map_bearing(pres_dir, unit_id)
	return {
		"plan_bearing_deg": plan_bearing_deg,
		"map_bearing_deg": map_bearing_deg,
		"map_skew_deg": map_skew_deg,
		"model_yaw": model_yaw,
	}


func _yaw_for_map_bearing(pres_dir: Vector2, unit_id: int) -> float:
	if pres_dir.length_squared() < 0.0001:
		return _facing_yaw_for_unit(unit_id)
	var map_bearing_deg: float = _travel_bearing_screen_up_deg(pres_dir)
	return travel_facing_yaw_offset_deg + map_bearing_deg


static func _travel_bearing_screen_up_deg(dir: Vector2) -> float:
	return rad_to_deg(Vector2(dir.x, -dir.y).angle())


static func _bearing_delta_deg(to_deg: float, from_deg: float) -> float:
	return rad_to_deg(atan2(sin(deg_to_rad(to_deg - from_deg)), cos(deg_to_rad(to_deg - from_deg))))


func _load_warrior_scene() -> void:
	if _warrior_scene != null:
		return
	var scene_path: String = Warrior3DExperimentScript.animated_scene_path_for_type(WARRIOR_TYPE_ID)
	if scene_path.is_empty():
		push_warning("[Unit3D world] warrior scene path empty")
		return
	_warrior_scene = (
		ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	)
	if _warrior_scene == null:
		push_warning("[Unit3D world] failed to load %s" % scene_path)


func _clear_all_instances() -> void:
	for k in _instance_by_unit_id.keys():
		var node: Node = _instance_by_unit_id[k] as Node
		if node != null:
			node.queue_free()
	_instance_by_unit_id.clear()
	_type_id_by_unit_id.clear()
	_active_hex_moves.clear()
	_facing_yaw_by_unit_id.clear()
	_ray_parallel_warned.clear()
	_logged_placement_diag.clear()


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
				override_mat.metallic = UNIT_MAT_OVERRIDE_METALLIC
				override_mat.roughness = UNIT_MAT_OVERRIDE_ROUGHNESS
				override_mat.metallic_specular = UNIT_MAT_OVERRIDE_SPECULAR
				mesh_inst.set_surface_override_material(si, override_mat)
			si += 1
