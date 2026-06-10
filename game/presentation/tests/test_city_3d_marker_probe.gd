# Headless probe: diagnose City3DMarkersView ancient_village rendering path.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const City3DView = preload("res://presentation/city_3d_markers_view.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	_check(
		ResourceLoader.exists(Experiment.ANCIENT_VILLAGE_GLB_PATH),
		"ancient_village.glb exists at %s" % Experiment.ANCIENT_VILLAGE_GLB_PATH,
	)
	var scene_path: String = Experiment.city_scene_path()
	_check(not scene_path.is_empty(), "city_scene_path non-empty: '%s'" % scene_path)
	var packed: PackedScene = load(scene_path) as PackedScene
	_check(packed != null, "load(city_scene_path) returns PackedScene")
	var probe_root: Node = null
	if packed != null:
		probe_root = packed.instantiate()
		_check(probe_root != null, "ancient_village PackedScene.instantiate() ok")
		var mesh_count: int = 0
		if probe_root != null:
			for _n in probe_root.find_children("*", "MeshInstance3D", true, false):
				mesh_count += 1
		_check(mesh_count > 0, "ancient_village has MeshInstance3D count=%d" % mesh_count)
		if probe_root != null:
			probe_root.free()

	var root := Node.new()
	root.name = "ProbeRoot"
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var m = HexMapScript.make_tiny_test_map()
	var cs = [CityScript.new(1, 0, HexCoordScript.new(1, -1))]
	var scenario = ScenarioScript.new(m, [UnitScript.new(7, 0, HexCoordScript.new(0, 0))], cs)
	var cities_view = CitiesViewScript.new()
	root.add_child(cities_view)
	cities_view.scenario = scenario
	cities_view.layout = layout
	var city_3d = City3DView.new()
	root.add_child(city_3d)
	city_3d.scenario = scenario
	city_3d.layout = layout
	var map_cam = MapCameraScript.new()
	map_cam.projection = MapPlaneProjectionScript.new()
	city_3d.camera = map_cam
	city_3d.cities_view = cities_view
	cities_view.city_3d_markers_view = city_3d
	city_3d.set_blit_via_terrain_foreground(true)

	await process_frame
	await process_frame

	_check(city_3d._slot_by_city_id.size() > 0, "City3DMarkersView synced slots=%d" % city_3d._slot_by_city_id.size())
	var city_id: int = int(scenario.cities()[0].id)
	var slot: Node2D = city_3d._slot_by_city_id.get(city_id) as Node2D
	_check(slot != null, "slot for city_id=%d exists" % city_id)
	var viewport: SubViewport = null
	if slot != null:
		viewport = city_3d._viewport_for_slot(slot)
	_check(viewport != null, "SubViewport for city slot exists")
	if viewport != null:
		var model_root: Node3D = viewport.find_child("ModelRoot", true, false) as Node3D
		_check(model_root != null, "ModelRoot in viewport")
		if model_root != null:
			print(
				"[City3D probe] model_root pos=%s scale=%s rot=%s children=%d"
				% [str(model_root.position), str(model_root.scale), str(model_root.rotation_degrees), model_root.get_child_count()]
			)
			var aabb: AABB = _visual_aabb(model_root)
			print("[City3D probe] model_root visual_aabb=%s" % str(aabb))
		var cam: Camera3D = viewport.get_child(0) as Camera3D
		if cam != null:
			print(
				"[City3D probe] camera pos=%s ortho_size=%.3f current=%s"
				% [str(cam.position), cam.size, str(cam.current)]
			)

	await process_frame
	await process_frame

	var world_center: Vector2 = layout.hex_to_world(
		scenario.cities()[0].position.q, scenario.cities()[0].position.r
	)
	var anchor_pres: Vector2 = map_cam.to_presentation(world_center)
	var pscale: float = map_cam.perspective_scale_at(world_center)
	var canvas := Node2D.new()
	root.add_child(canvas)
	await process_frame
	var blit_ok: bool = city_3d.try_draw_city_marker_at(canvas, anchor_pres, pscale, city_id, 0)
	_check(blit_ok, "try_draw_city_marker_at returned true (texture blit succeeded)")

	# Yaw must re-apply on existing slots (not only at _create_slot).
	var yaw_probe_slot: Node2D = city_3d._slot_by_city_id.get(city_id) as Node2D
	var yaw_probe_root: Node3D = null
	if yaw_probe_slot != null:
		yaw_probe_root = city_3d._model_root_for_slot(yaw_probe_slot)
	_check(yaw_probe_root != null, "ModelRoot exists for yaw re-apply probe")
	if yaw_probe_root != null:
		_check(
			is_equal_approx(yaw_probe_root.rotation_degrees.y, city_3d.model_yaw_degrees),
			"ModelRoot yaw matches export before delta (%.1f)" % city_3d.model_yaw_degrees
		)
		city_3d.model_yaw_degrees = city_3d.model_yaw_degrees - 20.0
		city_3d._sync_markers_frame = -1
		city_3d._sync_markers()
		_check(
			is_equal_approx(yaw_probe_root.rotation_degrees.y, city_3d.model_yaw_degrees),
			"ModelRoot yaw updates on existing slot after export change (%.1f)" % city_3d.model_yaw_degrees
		)
		city_3d.model_yaw_degrees = city_3d.model_yaw_degrees + 20.0
		city_3d._sync_markers_frame = -1
		city_3d._sync_markers()

	# TFV-style stale scenario: boot has no cities; after found_city TFV reassigns scenario.
	var boot_scenario = ScenarioScript.make_prototype_play_scenario()
	_check(boot_scenario.cities().size() == 0, "boot scenario has no cities (play map start)")
	city_3d.scenario = boot_scenario
	cities_view.scenario = boot_scenario
	city_3d._slot_by_city_id.clear()
	city_3d._sync_markers_frame = -1
	await process_frame
	var stale_blit: bool = city_3d.try_draw_city_marker_at(canvas, anchor_pres, pscale, city_id, 0)
	_check(not stale_blit, "stale boot scenario (0 cities) fails 3D blit for founded city_id")
	city_3d.scenario = scenario
	cities_view.scenario = scenario
	city_3d._sync_markers_frame = -1
	await process_frame
	var fresh_blit: bool = city_3d.try_draw_city_marker_at(canvas, anchor_pres, pscale, city_id, 0)
	_check(fresh_blit, "TFV-style scenario reassignment restores 3D blit")

	root.free()
	if _failures > 0:
		push_error("test_city_3d_marker_probe: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_city_3d_marker_probe: %d checks, all ok" % _checks)
	quit(0)


func _visual_aabb(node: Node3D) -> AABB:
	var merged := AABB()
	var first: bool = true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var local_aabb: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var world_aabb: AABB = xf * local_aabb
		if first:
			merged = world_aabb
			first = false
		else:
			merged = merged.merge(world_aabb)
	return merged


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
