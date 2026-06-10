# Headless: real scene 3D city instances sync from Scenario (stale-scenario safe).
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

var _failures: int = 0
var _checks: int = 0


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
	var layer = MapLayerScript.new()
	root.add_child(layer)
	layer.real_3d_city_enabled = true
	layer.city_blit_fallback_enabled = false
	cities_view.map_presentation_3d_layer = layer
	layer.layout = layout
	layer.scenario = scenario
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var city_world = layer._city_world_view
	_check(layer._viewport_container.stretch == false, "SubViewportContainer.stretch=false for manual resize")
	_check(layer._viewport_container.size.x > 0.0, "non-zero SubViewportContainer width")
	_check(layer._viewport_container.size.y > 0.0, "non-zero SubViewportContainer height")
	_check(layer._viewport.size.x > 0, "non-zero SubViewport width")
	_check(layer._viewport.size.y > 0, "non-zero SubViewport height")
	_check(layer.is_composite_viewport_ready(), "composite viewport ready")
	_check(layer.uses_real_3d_city(), "uses_real_3d_city when models flag on")
	_check(city_world != null, "City3DWorldView created inside composite viewport")
	_check(city_world.has_ready_city_instance(1), "ready instance for city_id=1")
	_check(layer.is_city_active_in_real_3d(1), "layer reports city active in real 3d")
	_check(not layer.should_auto_blit_for_city(1), "no auto blit when real 3d instance ready")
	var inst: Node3D = city_world._instance_by_city_id.get(1) as Node3D
	_check(inst != null, "instance node exists")
	if inst != null:
		_check(inst.get_child_count() > 0, "instance has GLB child")
		var want: Vector3 = city_world._hex_to_world_3d(1, -1)
		_check(inst.position.is_equal_approx(want), "instance at hex world 3d %s" % str(want))
	var boot = ScenarioScript.make_prototype_play_scenario()
	layer.scenario = boot
	layer.sync_from_scenario()
	await process_frame
	_check(not city_world.has_ready_city_instance(1), "stale boot scenario removes city instance")
	_check(layer.should_auto_blit_for_city(1), "auto blit when real 3d instance missing")
	var bare_layer = MapLayerScript.new()
	_check(not bare_layer.is_composite_viewport_ready(), "layer without viewport composite is invalid")
	_check(bare_layer.should_auto_blit_for_city(1), "auto blit when composite viewport invalid")
	layer.scenario = scenario
	layer.sync_from_scenario()
	await process_frame
	_check(city_world.has_ready_city_instance(1), "fresh scenario restores city instance")
	_check(not cities_view._uses_city_blit_path(), "explicit blit path off when real 3d without fallback")
	root.free()
	if _failures > 0:
		push_error("test_city_3d_world_probe: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_city_3d_world_probe: %d checks, all ok" % _checks)
	quit(0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
