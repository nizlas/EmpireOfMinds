# TEMP DIAG — windowed (NOT headless) screenshot probe for the real 3D city composite.
# Usage: godot --path game -s res://presentation/tests/test_city_3d_composite_screenshot.gd
# Mimics real-play camera state (offset/zoom/vanishing) and saves res://.tmp/city3d_probe.png.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const OUT_PATH: String = "res://.tmp/city3d_probe.png"


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	call_deferred("_run")


func _run() -> void:
	var layout = HexLayoutScript.new()
	var m = HexMapScript.make_tiny_test_map()
	var cs = [CityScript.new(1, 0, HexCoordScript.new(0, 0))]
	var scenario = ScenarioScript.new(m, [], cs)
	var projection = MapPlaneProjectionScript.new()
	projection.vanishing_pres = Vector2(1200.0, 532.0)
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	map_camera.camera_world_offset = Vector2(-1074.0, -384.0)
	map_camera.zoom = 1.0
	var layer = MapLayerScript.new()
	get_root().add_child(layer)
	layer.layout = layout
	layer.scenario = scenario
	layer.map_camera = map_camera
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	var city = scenario.cities()[0]
	var i: int = 0
	while i < 20:
		await process_frame
		i += 1
	layer.log_city_visibility_diag_once(1, city)
	await process_frame
	var img: Image = get_root().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tmp"))
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("screenshot saved=%s err=%d size=%s" % [OUT_PATH, err, str(img.get_size())])
	quit(0)
