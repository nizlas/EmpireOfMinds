# Real 3D ancient_village instances on the map plane (presentation only; one Node3D per city).
class_name City3DWorldView
extends Node3D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const CITY_MAT_OVERRIDE_METALLIC: float = 0.0
const CITY_MAT_OVERRIDE_ROUGHNESS: float = 0.85
const CITY_MAT_OVERRIDE_SPECULAR: float = 0.3

## Starting point from accepted SubViewport tuning (5.5 in diorama); scaled to hex layout world units.
@export var model_scale_3d: float = 800.0
@export var model_yaw_degrees_3d: float = -67.0
@export var model_pitch_degrees_3d: float = 0.0
## Presentation-only world-space offset from hex center (Y = up).
@export var model_world_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

var scenario
var layout

var _world_camera: Camera3D
var _map_camera
var _map_layer_origin: Vector2 = Vector2.ZERO

var _city_scene: PackedScene
var _instance_by_city_id: Dictionary = {}
var _sync_frame: int = -1
var _logged_depth_context: bool = false
var _logged_visibility_diag: Dictionary = {}
var _ray_parallel_warned: Dictionary = {}


func set_placement_context(world_cam: Camera3D, map_cam, layer_origin: Vector2) -> void:
	_world_camera = world_cam
	_map_camera = map_cam
	_map_layer_origin = layer_origin


func is_real_3d_active() -> bool:
	return Warrior3DExperimentScript.should_render_city_as_3d()


func get_active_city_count() -> int:
	return _instance_by_city_id.size()


func has_city_instance(city_id: int) -> bool:
	return _instance_by_city_id.has(city_id)


func first_city_instance() -> Node3D:
	for k in _instance_by_city_id.keys():
		var inst: Node3D = _instance_by_city_id[k] as Node3D
		if inst != null and is_instance_valid(inst):
			return inst
	return null


func has_ready_city_instance(city_id: int) -> bool:
	var root: Node3D = _instance_by_city_id.get(city_id) as Node3D
	if root == null:
		return false
	if not is_instance_valid(root):
		return false
	if not root.is_inside_tree():
		return false
	if not root.visible:
		return false
	if root.get_child_count() <= 0:
		return false
	return true


func prepare_for_draw() -> void:
	_sync_once_per_frame()
	_refresh_placements()


func refresh_placements() -> void:
	_refresh_placements()


static func compute_anchor_2d(world_2d: Vector2, map_cam, map_layer_origin: Vector2) -> Vector2:
	return map_layer_origin + map_cam.to_presentation(world_2d)


static func ray_intersect_ground_y0(world_camera: Camera3D, anchor_2d: Vector2) -> Vector3:
	if world_camera == null:
		return Vector3(NAN, NAN, NAN)
	var ray_origin: Vector3 = world_camera.project_ray_origin(anchor_2d)
	var ray_dir: Vector3 = world_camera.project_ray_normal(anchor_2d)
	if not ray_origin.is_finite() or not ray_dir.is_finite():
		return Vector3(NAN, NAN, NAN)
	if absf(ray_dir.y) < 1e-6:
		return Vector3(NAN, NAN, NAN)
	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return ray_origin + ray_dir * t


static func anchor_lock_delta_px(world_camera: Camera3D, instance_global: Vector3, anchor_2d: Vector2) -> float:
	if world_camera == null:
		return INF
	return world_camera.unproject_position(instance_global).distance_to(anchor_2d)


func sync_from_scenario() -> void:
	_sync_instances()


func log_visibility_diag_once(
	city_id: int,
	city,
	world_camera: Camera3D,
	viewport: SubViewport,
	layer: Node,
	map_camera_2d = null,
	map_layer_origin: Vector2 = Vector2.ZERO,
) -> void:
	if _logged_visibility_diag.has(city_id):
		return
	_logged_visibility_diag[city_id] = true
	_log_coordinate_space_diag(city_id, city, world_camera, map_camera_2d, map_layer_origin)
	var root: Node3D = _instance_by_city_id.get(city_id) as Node3D
	var hex_q: int = -999
	var hex_r: int = -999
	var layout_world: Vector2 = Vector2.ZERO
	var world_3d: Vector3 = Vector3.ZERO
	if city != null and layout != null:
		hex_q = int(city.position.q)
		hex_r = int(city.position.r)
		layout_world = layout.hex_to_world(hex_q, hex_r)
		world_3d = _hex_to_world_3d(hex_q, hex_r)
	var global_xf: String = "n/a"
	var in_tree: bool = false
	var mesh_count: int = 0
	if root != null:
		global_xf = str(root.global_transform)
		in_tree = root.is_inside_tree()
		for _n in root.find_children("*", "MeshInstance3D", true, false):
			mesh_count += 1
	var cam_pos: String = "n/a"
	var cam_rot: String = "n/a"
	var cam_size: float = -1.0
	var cam_current: bool = false
	if world_camera != null:
		cam_pos = str(world_camera.global_position)
		cam_rot = str(world_camera.global_rotation_degrees)
		cam_size = world_camera.size
		cam_current = world_camera.current
	print(
		(
			"[City3D world diag] city_id=%d hex=(%d,%d) layout_world=%s world_3d=%s "
			+ "scale=%.1f yaw=%.1f glb_loaded=%s instance=%s in_tree=%s visible=%s "
			+ "mesh_children=%d global_transform=%s camera_pos=%s camera_rot=%s "
			+ "camera_ortho=%.1f camera_current=%s viewport_size=%s layer_in_tree=%s "
			+ "layer_visible=%s"
		)
		% [
			city_id,
			hex_q,
			hex_r,
			str(layout_world),
			str(world_3d),
			model_scale_3d,
			model_yaw_degrees_3d,
			str(_city_scene != null),
			str(root != null),
			str(in_tree),
			str(root.visible if root != null else false),
			mesh_count,
			global_xf,
			cam_pos,
			cam_rot,
			cam_size,
			str(cam_current),
			str(viewport.size if viewport != null else Vector2i.ZERO),
			str(layer.is_inside_tree() if layer != null else false),
			str(layer.visible if layer is CanvasItem else true),
		]
	)


## TEMP DIAG — paths/transforms of layer chain + camera-space, frustum, screen alignment.
func _log_coordinate_space_diag(
	city_id: int, city, world_camera: Camera3D, map_camera_2d, map_layer_origin: Vector2
) -> void:
	var inst: Node3D = _instance_by_city_id.get(city_id) as Node3D
	var pan_root: Node3D = get_parent() as Node3D
	var layer_node: Node = pan_root.get_parent().get_parent() if pan_root != null else null
	var chain: Array = [
		["layer", layer_node],
		["pan_root", pan_root],
		["world_camera", world_camera],
		["city_view", self],
		["city_instance", inst],
	]
	for entry in chain:
		var label: String = entry[0]
		var node = entry[1]
		if node == null:
			print("[City3D space diag] %s=null" % label)
			continue
		var local_xf: String = "n/a"
		var global_xf: String = "n/a"
		if node is Node3D:
			local_xf = str((node as Node3D).transform)
			global_xf = str((node as Node3D).global_transform)
		elif node is Node2D:
			local_xf = str((node as Node2D).transform)
			global_xf = str((node as Node2D).get_global_transform())
		print(
			"[City3D space diag] %s path=%s local=%s global=%s"
			% [label, str(node.get_path()), local_xf, global_xf]
		)
	if inst == null or world_camera == null:
		return
	var same_parent: bool = (
		world_camera.get_parent() == pan_root if pan_root != null else false
	)
	var combined_aabb: AABB = AABB()
	var first_aabb: bool = true
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		var world_aabb: AABB = mi.global_transform * mi.get_aabb()
		if first_aabb:
			combined_aabb = world_aabb
			first_aabb = false
		else:
			combined_aabb = combined_aabb.merge(world_aabb)
	print(
		"[City3D space diag] city_id=%d model_world_aabb pos=%s size=%s center=%s"
		% [city_id, str(combined_aabb.position), str(combined_aabb.size), str(combined_aabb.get_center())]
	)
	var cam_space: Vector3 = (
		world_camera.global_transform.affine_inverse() * inst.global_position
	)
	var in_frustum: bool = world_camera.is_position_in_frustum(inst.global_position)
	var unprojected: Vector2 = world_camera.unproject_position(inst.global_position)
	var anchor_2d: Vector2 = Vector2(-1.0, -1.0)
	var world_2d: Vector2 = Vector2.ZERO
	var ray_origin: Vector3 = Vector3.ZERO
	var ray_dir: Vector3 = Vector3.ZERO
	var ground_hit: Vector3 = Vector3.ZERO
	if map_camera_2d != null and layout != null and city != null:
		world_2d = layout.hex_to_world(int(city.position.q), int(city.position.r))
		anchor_2d = compute_anchor_2d(world_2d, map_camera_2d, map_layer_origin)
		ray_origin = world_camera.project_ray_origin(anchor_2d)
		ray_dir = world_camera.project_ray_normal(anchor_2d)
		ground_hit = ray_intersect_ground_y0(world_camera, anchor_2d)
	var delta_px: float = unprojected.distance_to(anchor_2d)
	var zoom: float = map_camera_2d.zoom if map_camera_2d != null else -1.0
	var pan: Vector2 = (
		map_camera_2d.camera_world_offset if map_camera_2d != null else Vector2.ZERO
	)
	print(
		(
			"[City3D space diag] city_id=%d camera_under_pan_root=%s camera_space=%s "
			+ "in_frustum=%s unprojected_screen=%s anchor_2d=%s delta_px=%.4f "
			+ "world_2d=%s ray_origin=%s ray_dir=%s ground_hit=%s "
			+ "instance_global=%s zoom=%.3f pan=%s camera_ortho=%.1f"
		)
		% [
			city_id,
			str(same_parent),
			str(cam_space),
			str(in_frustum),
			str(unprojected),
			str(anchor_2d),
			delta_px,
			str(world_2d),
			str(ray_origin),
			str(ray_dir),
			str(ground_hit),
			str(inst.global_position),
			zoom,
			str(pan),
			world_camera.size,
		]
	)


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
	_load_city_scene()
	if _city_scene == null:
		push_warning("[City3D world] GLB scene failed to load; no real 3D city instances")
		return
	if not _logged_depth_context:
		_logged_depth_context = true
		print(
			(
				"[City3D world] depth_context=SubViewport_composite_3d "
				+ "units=SubViewport_2D_blit shared_z_buffer=false "
				+ "owner=City3DWorldView"
			)
		)
	var active_ids: Dictionary = {}
	var clist: Array = scenario.cities()
	var i: int = 0
	while i < clist.size():
		var city = clist[i]
		var city_id: int = int(city.id)
		active_ids[city_id] = true
		var root: Node3D = _instance_by_city_id.get(city_id) as Node3D
		if root == null:
			root = _create_city_instance(city_id, city)
			if root == null:
				i += 1
				continue
		_apply_instance_transform(root, city)
		i += 1
	var stale: Array = _instance_by_city_id.keys()
	var si: int = 0
	while si < stale.size():
		var stale_id: int = int(stale[si])
		if not active_ids.has(stale_id):
			var node: Node = _instance_by_city_id[stale_id] as Node
			if node != null:
				print(
					"[City3D world] destroyed city_id=%d hex=removed"
					% stale_id
				)
				node.queue_free()
			_instance_by_city_id.erase(stale_id)
			_logged_visibility_diag.erase(stale_id)
		si += 1


func _create_city_instance(city_id: int, city) -> Node3D:
	var model_root := Node3D.new()
	model_root.name = "City3D_%d" % city_id
	var model: Node = _city_scene.instantiate()
	if model == null:
		push_warning("City3DWorldView: instantiate failed for city_id=%d" % city_id)
		return null
	_apply_material_override(model)
	model_root.add_child(model)
	add_child(model_root)
	_instance_by_city_id[city_id] = model_root
	print(
		(
			"[City3D world] created city_id=%d hex=(%d,%d) render=real_scene_3d "
			+ "scenario_cities=%d"
		)
		% [
			city_id,
			int(city.position.q),
			int(city.position.r),
			scenario.cities().size() if scenario != null else 0,
		]
	)
	return model_root


func _refresh_placements() -> void:
	if not is_real_3d_active() or scenario == null:
		return
	var clist: Array = scenario.cities()
	var i: int = 0
	while i < clist.size():
		var city = clist[i]
		var city_id: int = int(city.id)
		var root: Node3D = _instance_by_city_id.get(city_id) as Node3D
		if root != null:
			_apply_instance_transform(root, city)
		i += 1


func _apply_instance_transform(root: Node3D, city) -> void:
	var pos_global: Vector3 = _placement_position_global_for_city(city, root)
	if root.is_inside_tree():
		root.global_position = pos_global
	else:
		root.position = pos_global
	root.rotation_degrees = Vector3(model_pitch_degrees_3d, model_yaw_degrees_3d, 0.0)
	root.scale = Vector3.ONE * model_scale_3d
	if not bool(root.get_meta(&"eom_city_transform_logged", false)):
		root.set_meta(&"eom_city_transform_logged", true)
		print(
			(
				"[City3D world] transform city_id=%d hex=(%d,%d) pos=%s "
				+ "yaw=%.1f scale=%.1f offset=%s global=%s anchor_lock=%s"
			)
			% [
				int(city.id),
				int(city.position.q),
				int(city.position.r),
				str(root.position),
				model_yaw_degrees_3d,
				model_scale_3d,
				str(model_world_offset),
				str(root.global_transform),
				str(_world_camera != null and _map_camera != null),
			]
		)


func _placement_position_global_for_city(city, root: Node3D) -> Vector3:
	var fallback: Vector3 = _hex_to_world_3d(int(city.position.q), int(city.position.r))
	if _world_camera == null or _map_camera == null or layout == null:
		return fallback
	var world_2d: Vector2 = layout.hex_to_world(int(city.position.q), int(city.position.r))
	var anchor_2d: Vector2 = compute_anchor_2d(world_2d, _map_camera, _map_layer_origin)
	var hit_global: Vector3 = ray_intersect_ground_y0(_world_camera, anchor_2d)
	if not hit_global.is_finite():
		_warn_ray_parallel_once(int(city.id), anchor_2d)
		if root.is_inside_tree():
			return root.global_position
		return fallback
	return hit_global + model_world_offset


func _warn_ray_parallel_once(city_id: int, anchor_2d: Vector2) -> void:
	if _ray_parallel_warned.has(city_id):
		return
	_ray_parallel_warned[city_id] = true
	push_warning(
		"[City3D world] anchor ray-ground miss city_id=%d anchor_2d=%s; keeping prior transform"
		% [city_id, str(anchor_2d)]
	)


func _hex_to_world_3d(q: int, r: int) -> Vector3:
	var w: Vector2 = layout.hex_to_world(q, r)
	# Map-south (+y, lower on screen) maps to +Z (closer to the south-placed camera).
	return Vector3(w.x, 0.0, w.y) + model_world_offset


func _load_city_scene() -> void:
	if _city_scene != null:
		return
	var scene_path: String = Warrior3DExperimentScript.city_scene_path()
	if scene_path.is_empty():
		push_warning("[City3D world] city_scene_path empty")
		return
	_city_scene = (
		ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	)
	if _city_scene == null:
		push_warning("[City3D world] failed to load %s" % scene_path)


func _clear_all_instances() -> void:
	for k in _instance_by_city_id.keys():
		var node: Node = _instance_by_city_id[k] as Node
		if node != null:
			node.queue_free()
	_instance_by_city_id.clear()
	_logged_visibility_diag.clear()


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
				override_mat.metallic = CITY_MAT_OVERRIDE_METALLIC
				override_mat.roughness = CITY_MAT_OVERRIDE_ROUGHNESS
				override_mat.metallic_specular = CITY_MAT_OVERRIDE_SPECULAR
				mesh_inst.set_surface_override_material(si, override_mat)
			si += 1
