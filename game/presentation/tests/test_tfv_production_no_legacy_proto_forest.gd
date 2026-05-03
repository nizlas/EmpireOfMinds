# Headless: production TFV + symbol scatter + depth merge — legacy front proc/asset call counts stay **0**.
# Usage: godot --headless --path game -s res://presentation/tests/test_tfv_production_no_legacy_proto_forest.gd
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const MapViewScript = preload("res://presentation/map_view.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rt: Node = get_root()
	var tfv = TerrainForegroundViewScript.new()
	var uv = UnitsViewScript.new()
	var cv = CitiesViewScript.new()
	var mv = MapViewScript.new()
	var scenario = ScenarioScript.make_prototype_play_scenario()
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	tfv.map = scenario.map
	tfv.layout = layout
	tfv.camera = cam
	tfv.scenario = scenario
	tfv.forest_density_ratio = 0.25
	tfv.use_forest_symbol_scatter = true
	tfv.forest_grid_debug_isolated = false
	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.PRODUCTION
	tfv.units_view = uv
	tfv.cities_view = cv
	tfv.map_view = mv
	mv.terrain_foreground_view = tfv
	uv.scenario = scenario
	uv.layout = layout
	uv.camera = cam
	uv.terrain_foreground_view = tfv
	cv.scenario = scenario
	cv.layout = layout
	cv.camera = cam
	cv.terrain_foreground_view = tfv
	rt.add_child(tfv)
	rt.add_child(uv)
	rt.add_child(cv)
	TerrainForegroundViewScript.debug_pipeline_tfv_front_proc = -1
	TerrainForegroundViewScript.debug_pipeline_tfv_front_asset = -1
	await process_frame
	tfv.queue_redraw()
	await process_frame
	rt.remove_child(tfv)
	rt.remove_child(uv)
	rt.remove_child(cv)
	tfv.queue_free()
	uv.queue_free()
	cv.queue_free()
	if TerrainForegroundViewScript.debug_pipeline_tfv_front_proc != 0:
		push_error(
			"FAIL: expected tfv_front_proc=0 got %d"
			% TerrainForegroundViewScript.debug_pipeline_tfv_front_proc
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_pipeline_tfv_front_asset != 0:
		push_error(
			"FAIL: expected tfv_front_asset=0 got %d"
			% TerrainForegroundViewScript.debug_pipeline_tfv_front_asset
		)
		call_deferred("quit", 1)
		return
	print("PASS test_tfv_production_no_legacy_proto_forest")
	call_deferred("quit", 0)
