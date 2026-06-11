# Headless: real scene 3D warrior instances sync from Scenario (stale-scenario safe).
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")
const CityWorldScript = preload("res://presentation/city_3d_world_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const WARRIOR_UNIT_ID: int = 2
const FEET_DELTA_TOL_PX: float = 12.0

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.unset_environment(Experiment.ENV_REAL_3D_UNITS)
	call_deferred("_run")


func _run() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.make_tiny_test_scenario()
	var units_view = UnitsViewScript.new()
	root.add_child(units_view)
	var layer = MapLayerScript.new()
	root.add_child(layer)
	layer.real_3d_units_enabled = true
	units_view.map_presentation_3d_layer = layer
	layer.layout = layout
	layer.scenario = scenario
	layer.map_layer_origin = MAP_LAYER_ORIGIN
	var projection = MapPlaneProjectionScript.new()
	projection.vanishing_pres = (get_root().get_visible_rect().size * 0.5) - MAP_LAYER_ORIGIN
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	layer.map_camera = map_camera
	await process_frame
	_check(layer.should_auto_blit_for_unit(WARRIOR_UNIT_ID), "blit fallback when EOM_REAL_3D_UNITS off")
	_check(not layer.uses_real_3d_units(), "real 3d units off without env flag")

	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var unit_world = layer._unit_world_view
	_check(layer.uses_real_3d_units(), "uses_real_3d_units when flags on")
	_check(unit_world != null, "Unit3DWorldView created under WorldPanRoot")
	_check(
		layer._world_pan_root.get_node_or_null("Unit3DWorldView") != null,
		"Unit3DWorldView is sibling under WorldPanRoot",
	)
	_check(unit_world.has_ready_unit_instance(WARRIOR_UNIT_ID), "ready warrior instance id=2")
	_check(layer.is_unit_active_in_real_3d(WARRIOR_UNIT_ID), "layer reports warrior active in real 3d")
	_check(not layer.should_auto_blit_for_unit(WARRIOR_UNIT_ID), "no auto blit when real 3d warrior ready")
	var inst: Node3D = unit_world._instance_by_unit_id.get(WARRIOR_UNIT_ID) as Node3D
	_check(inst != null, "warrior instance node exists")
	if inst != null:
		_check(inst.get_node_or_null("ModelRoot") != null, "instance has ModelRoot child")
		var warrior = _warrior_from_scenario(scenario, WARRIOR_UNIT_ID)
		var world_2d: Vector2 = layout.hex_to_world(
			int(warrior.position.q), int(warrior.position.r)
		)
		var anchor_2d: Vector2 = CityWorldScript.compute_anchor_2d(
			world_2d, map_camera, MAP_LAYER_ORIGIN
		)
		var root_delta: float = CityWorldScript.anchor_lock_delta_px(
			layer._world_camera, inst.global_position, anchor_2d
		)
		_check(root_delta < 0.5, "unit root locked to 2D anchor delta=%.4f px" % root_delta)
		var feet_2d: Vector2 = UnitWorldScript.projected_mesh_feet_2d(layer._world_camera, inst)
		var feet_delta: float = feet_2d.distance_to(anchor_2d)
		_check(
			feet_delta < FEET_DELTA_TOL_PX,
			"mesh feet locked to unit anchor delta=%.4f px" % feet_delta,
		)
		var expected_scale: float = UnitWorldScript.effective_scale_at_world(
			map_camera,
			unit_world.model_scale_3d,
			unit_world.reference_world_y,
			world_2d,
		)
		_check(
			absf(inst.scale.y - expected_scale) < 0.05,
			"UnitRoot scale=%.3f matches effective formula=%.3f" % [inst.scale.y, expected_scale],
		)

	var boot = ScenarioScript.make_prototype_play_scenario()
	layer.scenario = boot
	layer.sync_from_scenario()
	await process_frame
	_check(
		not unit_world.has_ready_unit_instance(WARRIOR_UNIT_ID),
		"stale boot scenario removes warrior instance",
	)
	_check(layer.should_auto_blit_for_unit(WARRIOR_UNIT_ID), "auto blit when real 3d warrior missing")

	var bare_layer = MapLayerScript.new()
	_check(not bare_layer.is_composite_viewport_ready(), "layer without viewport composite is invalid")
	_check(
		bare_layer.should_auto_blit_for_unit(WARRIOR_UNIT_ID),
		"auto blit when composite viewport invalid",
	)

	layer.scenario = scenario
	layer.sync_from_scenario()
	await process_frame
	_check(unit_world.has_ready_unit_instance(WARRIOR_UNIT_ID), "fresh scenario restores warrior instance")

	var skip_blit: bool = not layer.should_auto_blit_for_unit(WARRIOR_UNIT_ID)
	_check(skip_blit, "units_view routing would skip warrior blit when real 3d active")

	root.free()
	if _failures > 0:
		push_error("test_unit_3d_world_probe: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_unit_3d_world_probe: %d checks, all ok" % _checks)
	quit(0)


func _warrior_from_scenario(scenario, unit_id: int):
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		if int(ulist[i].id) == unit_id:
			return ulist[i]
		i += 1
	return null


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
