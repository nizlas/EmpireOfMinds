# Headless: real 3D city screen lock to 2D hex anchor across pan/zoom sweep.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const CityWorldScript = preload("res://presentation/city_3d_world_view.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const DELTA_TOL_PX: float = 0.5

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	call_deferred("_run")


func _run() -> void:
	var layout = HexLayoutScript.new()
	var m = HexMapScript.make_tiny_test_map()
	var city = CityScript.new(1, 0, HexCoordScript.new(0, 0))
	var scenario = ScenarioScript.new(m, [], [city])
	var projection = MapPlaneProjectionScript.new()
	var vp_size: Vector2 = get_root().get_visible_rect().size
	projection.vanishing_pres = (vp_size * 0.5) - MAP_LAYER_ORIGIN
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	var layer = MapLayerScript.new()
	get_root().add_child(layer)
	layer.map_layer_origin = MAP_LAYER_ORIGIN
	layer.layout = layout
	layer.scenario = scenario
	layer.map_camera = map_camera
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var city_world = layer._city_world_view
	var inst: Node3D = city_world._instance_by_city_id.get(1) as Node3D
	_check(inst != null, "city instance exists for anchor lock sweep")
	var world_2d: Vector2 = layout.hex_to_world(0, 0)
	var offsets_x: Array = [-1000.0, 0.0, 1000.0]
	var offsets_y: Array = [-800.0, 0.0, 800.0]
	var zooms: Array = [0.5, 1.0, 2.0]
	var ox: int = 0
	while ox < offsets_x.size():
		var oy: int = 0
		while oy < offsets_y.size():
			var zi: int = 0
			while zi < zooms.size():
				map_camera.camera_world_offset = Vector2(
					float(offsets_x[ox]), float(offsets_y[oy])
				)
				map_camera.set_zoom_clamped(float(zooms[zi]))
				layer.prepare_for_draw()
				await process_frame
				var anchor_2d: Vector2 = CityWorldScript.compute_anchor_2d(
					world_2d, map_camera, MAP_LAYER_ORIGIN
				)
				var delta: float = CityWorldScript.anchor_lock_delta_px(
					layer._world_camera, inst.global_position, anchor_2d
				)
				_check(
					delta < DELTA_TOL_PX,
					(
						"anchor lock off=(%.0f,%.0f) zoom=%.1f delta=%.4f px"
						% [offsets_x[ox], offsets_y[oy], zooms[zi], delta]
					),
				)
				zi += 1
			oy += 1
		ox += 1
	layer.free()
	if _failures > 0:
		push_error("test_city_3d_anchor_lock: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_city_3d_anchor_lock: %d checks, all ok" % _checks)
	quit(0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
