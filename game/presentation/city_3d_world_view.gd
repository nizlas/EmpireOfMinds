# Real 3D ancient_village instances on the map plane (presentation only; one Node3D per city).
class_name City3DWorldView
extends Node3D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const CITY_MAT_OVERRIDE_METALLIC: float = 0.0
const CITY_MAT_OVERRIDE_ROUGHNESS: float = 0.85
const CITY_MAT_OVERRIDE_SPECULAR: float = 0.3

## Starting point from accepted SubViewport tuning (5.5 in diorama); scaled to hex layout world units.
@export var model_scale_3d: float = 440.0
@export var model_yaw_degrees_3d: float = -67.0
@export var model_pitch_degrees_3d: float = 0.0
## Presentation-only world-space offset from hex center (Y = up).
@export var model_world_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

var scenario
var layout

var _city_scene: PackedScene
var _instance_by_city_id: Dictionary = {}
var _sync_frame: int = -1
var _logged_depth_context: bool = false
var _logged_visibility_diag: Dictionary = {}


func is_real_3d_active() -> bool:
	return Warrior3DExperimentScript.should_render_city_as_3d()


func get_active_city_count() -> int:
	return _instance_by_city_id.size()


func has_city_instance(city_id: int) -> bool:
	return _instance_by_city_id.has(city_id)


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


func sync_from_scenario() -> void:
	_sync_instances()


func log_visibility_diag_once(
	city_id: int, city, world_camera: Camera3D, viewport: SubViewport, layer: Node
) -> void:
	if _logged_visibility_diag.has(city_id):
		return
	_logged_visibility_diag[city_id] = true
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


func _apply_instance_transform(root: Node3D, city) -> void:
	var world_3d: Vector3 = _hex_to_world_3d(int(city.position.q), int(city.position.r))
	root.position = world_3d
	root.rotation_degrees = Vector3(model_pitch_degrees_3d, model_yaw_degrees_3d, 0.0)
	root.scale = Vector3.ONE * model_scale_3d
	if not bool(root.get_meta(&"eom_city_transform_logged", false)):
		root.set_meta(&"eom_city_transform_logged", true)
		print(
			(
				"[City3D world] transform city_id=%d hex=(%d,%d) pos=%s "
				+ "yaw=%.1f scale=%.1f offset=%s global=%s"
			)
			% [
				int(city.id),
				int(city.position.q),
				int(city.position.r),
				str(world_3d),
				model_yaw_degrees_3d,
				model_scale_3d,
				str(model_world_offset),
				str(root.global_transform),
			]
		)


func _hex_to_world_3d(q: int, r: int) -> Vector3:
	var w: Vector2 = layout.hex_to_world(q, r)
	return Vector3(w.x, 0.0, -w.y) + model_world_offset


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
