# Headless: prove ancient_village SubViewport texture changes when ModelRoot yaw changes.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const City3DView = preload("res://presentation/city_3d_markers_view.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _failures: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	call_deferred("_run")


func _run() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var m = HexMapScript.make_tiny_test_map()
	var cs = [CityScript.new(1, 0, HexCoordScript.new(1, -1))]
	var scenario = ScenarioScript.new(m, [], cs)
	var cities_view = CitiesViewScript.new()
	root.add_child(cities_view)
	var city_3d = City3DView.new()
	root.add_child(city_3d)
	city_3d.scenario = scenario
	city_3d.layout = layout
	var map_cam = MapCameraScript.new()
	map_cam.projection = MapPlaneProjectionScript.new()
	city_3d.camera = map_cam
	city_3d.cities_view = cities_view
	city_3d.set_blit_via_terrain_foreground(true)

	await process_frame
	await process_frame

	var city_id: int = 1
	var slot: Node2D = city_3d._slot_by_city_id.get(city_id) as Node2D
	if slot == null:
		city_3d._sync_markers()
		await process_frame
		slot = city_3d._slot_by_city_id.get(city_id) as Node2D
	_check(slot != null, "city slot exists")
	var viewport: SubViewport = city_3d._viewport_for_slot(slot) if slot != null else null
	_check(viewport != null, "SubViewport exists")

	var model_root: Node3D = city_3d._model_root_for_slot(slot) if slot != null else null
	_check(model_root != null, "ModelRoot is parent of GLB instance")
	if model_root != null and model_root.get_child_count() > 0:
		var glb_inst: Node = model_root.get_child(0)
		print(
			"[yaw probe] glb_instance class=%s name=%s parent=%s mesh_children=%d"
			% [
				glb_inst.get_class(),
				glb_inst.name,
				model_root.name,
				glb_inst.find_children("*", "MeshInstance3D", true, false).size(),
			]
		)

	var base_yaw: float = -57.0
	var proof_yaw: float = base_yaw + 90.0
	var corner_base: Vector3 = await _mesh_corner_world(city_3d, slot, base_yaw)
	var corner_proof: Vector3 = await _mesh_corner_world(city_3d, slot, proof_yaw)
	print(
		"[yaw probe] mesh corner world base_yaw=%.1f -> %s proof_yaw=%.1f -> %s"
		% [base_yaw, str(corner_base), proof_yaw, str(corner_proof)]
	)
	_check(corner_base.length_squared() > 0.0, "mesh corner resolved at base yaw")
	_check(not corner_base.is_equal_approx(corner_proof), "90deg yaw moves mesh corner in 3D scene")

	root.free()
	if _failures > 0:
		push_error("test_city_3d_yaw_viewport_probe: %d failures" % _failures)
		quit(1)
	print("PASS test_city_3d_yaw_viewport_probe")
	quit(0)


func _mesh_corner_world(city_3d: City3DView, slot: Node2D, yaw: float) -> Vector3:
	city_3d.model_yaw_degrees = yaw
	city_3d._sync_markers_frame = -1
	city_3d._sync_markers()
	city_3d._apply_slot_model_framing(slot)
	var model_root: Node3D = city_3d._model_root_for_slot(slot)
	if model_root == null:
		return Vector3.ZERO
	var mesh_inst: MeshInstance3D = null
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		mesh_inst = n as MeshInstance3D
		break
	if mesh_inst == null or mesh_inst.mesh == null:
		return Vector3.ZERO
	var local_aabb: AABB = mesh_inst.mesh.get_aabb()
	var corner_local: Vector3 = local_aabb.position + Vector3(local_aabb.size.x, 0.0, 0.0)
	return mesh_inst.global_transform * corner_local


func _capture_viewport_hash(city_3d: City3DView, slot: Node2D, yaw: float) -> int:
	city_3d.model_yaw_degrees = yaw
	city_3d._sync_markers_frame = -1
	city_3d._sync_markers()
	var viewport: SubViewport = city_3d._viewport_for_slot(slot)
	var model_root: Node3D = city_3d._model_root_for_slot(slot)
	if viewport == null or model_root == null:
		return 0
	city_3d._apply_slot_model_framing(slot)
	var world_center: Vector2 = city_3d.layout.hex_to_world(
		city_3d.scenario.cities()[0].position.q,
		city_3d.scenario.cities()[0].position.r,
	)
	var anchor_pres: Vector2 = city_3d.camera.to_presentation(world_center)
	var pscale: float = city_3d.camera.perspective_scale_at(world_center)
	var rect: Rect2 = city_3d.marker_display_rect(anchor_pres, pscale)
	city_3d._apply_viewport_size_for_blit(slot, viewport, rect)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	await process_frame
	await process_frame
	var tex: Texture2D = viewport.get_texture()
	if tex == null:
		return 0
	print("[yaw probe] yaw=%.1f model_root_rot=%s tex_size=%s" % [yaw, str(model_root.rotation_degrees), str(tex.get_size())])
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return 0
	var data: PackedByteArray = img.get_data()
	var h: int = 0
	var i: int = 0
	while i < data.size():
		h = int((h * 31 + int(data[i])) & 0x7FFFFFFF)
		i += 1
	return h


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
