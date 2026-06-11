# Headless: real 3D warrior mesh feet lock to 2D unit anchor across pan/zoom sweep.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")
const CityWorldScript = preload("res://presentation/city_3d_world_view.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const ROOT_DELTA_TOL_PX: float = 0.5
## Mesh feet may sit slightly below hex-center anchor (blit pivot); allow modest bind-pose offset.
const FEET_DELTA_TOL_PX: float = 12.0
const HEIGHT_RATIO_MIN: float = 0.55
const HEIGHT_RATIO_MAX: float = 1.45
const WARRIOR_UNIT_ID: int = 2
const UNIT_ID_TOP: int = 10
const UNIT_ID_MID: int = 11
const UNIT_ID_BOTTOM: int = 12
const SCALE_EPS: float = 0.05

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	call_deferred("_run")


func _run() -> void:
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.make_tiny_test_scenario()
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
	layer.real_3d_units_enabled = true
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var unit_world = layer._unit_world_view
	var inst: Node3D = unit_world._instance_by_unit_id.get(WARRIOR_UNIT_ID) as Node3D
	_check(inst != null, "warrior instance exists for anchor lock sweep")
	var warrior = _warrior_from_scenario(scenario, WARRIOR_UNIT_ID)
	var world_2d: Vector2 = layout.hex_to_world(int(warrior.position.q), int(warrior.position.r))
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
				var root_delta: float = CityWorldScript.anchor_lock_delta_px(
					layer._world_camera, inst.global_position, anchor_2d
				)
				_check(
					root_delta < ROOT_DELTA_TOL_PX,
					(
						"unit root anchor lock off=(%.0f,%.0f) zoom=%.1f delta=%.4f px"
						% [offsets_x[ox], offsets_y[oy], zooms[zi], root_delta]
					),
				)
				var feet_2d: Vector2 = UnitWorldScript.projected_mesh_feet_2d(
					layer._world_camera, inst
				)
				var feet_delta: float = feet_2d.distance_to(anchor_2d)
				_check(
					feet_delta < FEET_DELTA_TOL_PX,
					(
						"mesh feet anchor lock off=(%.0f,%.0f) zoom=%.1f delta=%.4f px"
						% [offsets_x[ox], offsets_y[oy], zooms[zi], feet_delta]
					),
				)
				zi += 1
			oy += 1
		ox += 1

	map_camera.camera_world_offset = Vector2.ZERO
	map_camera.set_zoom_clamped(1.0)
	layer.prepare_for_draw()
	await process_frame
	_check(
		absf(inst.scale.y - unit_world.model_scale_3d) < SCALE_EPS,
		"reference row effective_scale=%.3f equals base=%.1f"
		% [inst.scale.y, unit_world.model_scale_3d],
	)

	# Row perspective scale: top / mid / bottom warriors on tiny map.
	var row_map = HexMapScript.make_tiny_test_map()
	var row_units = [
		UnitScript.new(UNIT_ID_TOP, 0, HexCoordScript.new(0, -1), "warrior"),
		UnitScript.new(UNIT_ID_MID, 0, HexCoordScript.new(1, 0), "warrior"),
		UnitScript.new(UNIT_ID_BOTTOM, 0, HexCoordScript.new(0, 1), "warrior"),
	]
	var row_scenario = ScenarioScript.new(row_map, row_units)
	layer.scenario = row_scenario
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var ref_factor: float = UnitWorldScript.reference_perspective_factor(
		map_camera, unit_world.reference_world_y
	)
	var top_world: Vector2 = layout.hex_to_world(0, -1)
	var mid_world: Vector2 = layout.hex_to_world(1, 0)
	var bottom_world: Vector2 = layout.hex_to_world(0, 1)
	var top_inst: Node3D = unit_world._instance_by_unit_id.get(UNIT_ID_TOP) as Node3D
	var mid_inst: Node3D = unit_world._instance_by_unit_id.get(UNIT_ID_MID) as Node3D
	var bottom_inst: Node3D = unit_world._instance_by_unit_id.get(UNIT_ID_BOTTOM) as Node3D
	_check(top_inst != null and mid_inst != null and bottom_inst != null, "row warriors created")
	var top_expected: float = UnitWorldScript.effective_scale_at_world(
		map_camera, unit_world.model_scale_3d, unit_world.reference_world_y, top_world
	)
	var mid_expected: float = UnitWorldScript.effective_scale_at_world(
		map_camera, unit_world.model_scale_3d, unit_world.reference_world_y, mid_world
	)
	var bottom_expected: float = UnitWorldScript.effective_scale_at_world(
		map_camera, unit_world.model_scale_3d, unit_world.reference_world_y, bottom_world
	)
	_check(
		absf(top_inst.scale.y - top_expected) < SCALE_EPS,
		"top row scale=%.3f expected=%.3f" % [top_inst.scale.y, top_expected],
	)
	_check(
		absf(mid_inst.scale.y - mid_expected) < SCALE_EPS,
		"mid row scale=%.3f expected=%.3f" % [mid_inst.scale.y, mid_expected],
	)
	_check(
		absf(bottom_inst.scale.y - bottom_expected) < SCALE_EPS,
		"bottom row scale=%.3f expected=%.3f" % [bottom_inst.scale.y, bottom_expected],
	)
	var factor_top: float = UnitWorldScript.perspective_factor_zoom_free(map_camera, top_world)
	var factor_bottom: float = UnitWorldScript.perspective_factor_zoom_free(
		map_camera, bottom_world
	)
	_check(
		absf(top_inst.scale.y / bottom_inst.scale.y - factor_top / factor_bottom) < 0.001,
		"cross-row scale ratio top/bottom=%.4f factor ratio=%.4f"
		% [top_inst.scale.y / bottom_inst.scale.y, factor_top / factor_bottom],
	)
	print(
		"row scales top=%.3f mid=%.3f bottom=%.3f ref_factor=%.6f"
		% [top_inst.scale.y, mid_inst.scale.y, bottom_inst.scale.y, ref_factor]
	)

	# South-pan / bottom-band: warrior anchor in lower screen must stay in frustum (near-plane fix).
	_check(
		absf(layer.world_camera_back_distance - 3000.0) < 0.01,
		"world_camera_back_distance=%.1f" % layer.world_camera_back_distance,
	)
	_check(
		absf(layer._world_camera.near - 10.0) < 0.01,
		"camera near=%.1f" % layer._world_camera.near,
	)
	_check(
		absf(layer._world_camera.far - (layer.world_camera_back_distance + 4000.0)) < 0.01,
		"camera far=%.1f" % layer._world_camera.far,
	)
	var south_zooms: Array = [1.0, 0.5]
	var zi_south: int = 0
	while zi_south < south_zooms.size():
		var south_zoom: float = float(south_zooms[zi_south])
		map_camera.set_zoom_clamped(south_zoom)
		var south_off: Vector2 = _pan_offset_for_bottom_band(
			map_camera, bottom_world, MAP_LAYER_ORIGIN, vp_size, 0.72
		)
		map_camera.camera_world_offset = south_off
		layer.prepare_for_draw()
		await process_frame
		var south_anchor: Vector2 = CityWorldScript.compute_anchor_2d(
			bottom_world, map_camera, MAP_LAYER_ORIGIN
		)
		_check(
			south_anchor.y >= vp_size.y * 0.55 and south_anchor.y <= vp_size.y * 0.95,
			"bottom-band anchor y=%.1f zoom=%.1f pan=%s" % [south_anchor.y, south_zoom, str(south_off)],
		)
		var south_feet_2d: Vector2 = UnitWorldScript.projected_mesh_feet_2d(
			layer._world_camera, bottom_inst
		)
		var south_feet_delta: float = south_feet_2d.distance_to(south_anchor)
		_check(
			south_feet_delta < FEET_DELTA_TOL_PX,
			"bottom-band feet lock zoom=%.1f delta=%.4f px" % [south_zoom, south_feet_delta],
		)
		var feet_global: Vector3 = UnitWorldScript.mesh_feet_global(bottom_inst)
		var top_global: Vector3 = UnitWorldScript.mesh_top_global(bottom_inst)
		var feet_depth: float = UnitWorldScript.camera_forward_depth(layer._world_camera, feet_global)
		var top_depth: float = UnitWorldScript.camera_forward_depth(layer._world_camera, top_global)
		_check(
			feet_depth > layer._world_camera.near,
			"bottom-band feet depth=%.1f > near=%.1f zoom=%.1f"
			% [feet_depth, layer._world_camera.near, south_zoom],
		)
		_check(
			top_depth > layer._world_camera.near,
			"bottom-band top depth=%.1f > near=%.1f zoom=%.1f"
			% [top_depth, layer._world_camera.near, south_zoom],
		)
		_check(
			UnitWorldScript.is_in_camera_frustum(layer._world_camera, feet_global),
			"bottom-band feet in frustum zoom=%.1f depth=%.1f" % [south_zoom, feet_depth],
		)
		_check(
			UnitWorldScript.is_in_camera_frustum(layer._world_camera, top_global),
			"bottom-band top in frustum zoom=%.1f depth=%.1f" % [south_zoom, top_depth],
		)
		print(
			"bottom-band diag zoom=%.1f pan=%s anchor_y=%.1f feet_depth=%.1f top_depth=%.1f near=%.1f far=%.1f"
			% [
				south_zoom,
				str(south_off),
				south_anchor.y,
				feet_depth,
				top_depth,
				layer._world_camera.near,
				layer._world_camera.far,
			]
		)
		zi_south += 1

	# No double zoom: same pan/world, zoom change must not alter UnitRoot scale.
	map_camera.camera_world_offset = Vector2.ZERO
	map_camera.set_zoom_clamped(1.0)
	layer.scenario = scenario
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	inst = unit_world._instance_by_unit_id.get(WARRIOR_UNIT_ID) as Node3D
	_check(inst != null, "warrior instance restored after row scenario")
	var scale_zoom1: float = inst.scale.y
	map_camera.set_zoom_clamped(2.0)
	layer.prepare_for_draw()
	await process_frame
	var scale_zoom2: float = inst.scale.y
	_check(
		absf(scale_zoom1 - scale_zoom2) < SCALE_EPS,
		"no double zoom scale@1=%.3f scale@2=%.3f" % [scale_zoom1, scale_zoom2],
	)

	map_camera.set_zoom_clamped(1.0)
	layer.prepare_for_draw()
	await process_frame

	# Mid-move: interpolated world position should still anchor-lock mesh feet.
	unit_world.set_process(false)
	unit_world.begin_hex_move(WARRIOR_UNIT_ID, "warrior", 1, 0, 0, 0)
	var stride_sec: float = unit_world._hex_move_stride_anim_sec("warrior")
	var move: Dictionary = unit_world._active_hex_moves[WARRIOR_UNIT_ID]
	move["progress"] = 0.5
	move["anim_elapsed_sec"] = stride_sec * 0.5
	unit_world._active_hex_moves[WARRIOR_UNIT_ID] = move
	layer.prepare_for_draw()
	var mid_move_world: Vector2 = layout.hex_to_world(1, 0).lerp(layout.hex_to_world(0, 0), 0.5)
	var mid_anchor: Vector2 = CityWorldScript.compute_anchor_2d(
		mid_move_world, map_camera, MAP_LAYER_ORIGIN
	)
	var mid_feet: Vector2 = UnitWorldScript.projected_mesh_feet_2d(layer._world_camera, inst)
	var mid_delta: float = mid_feet.distance_to(mid_anchor)
	_check(
		mid_delta < FEET_DELTA_TOL_PX,
		"mid-move mesh feet anchor lock delta=%.4f px" % mid_delta,
	)
	var mid_scale_expected: float = UnitWorldScript.effective_scale_at_world(
		map_camera,
		unit_world.model_scale_3d,
		unit_world.reference_world_y,
		mid_move_world,
	)
	_check(
		absf(inst.scale.y - mid_scale_expected) < SCALE_EPS,
		"mid-move scale=%.3f expected=%.3f" % [inst.scale.y, mid_scale_expected],
	)

	# Animation stability: walk ticks must not drift UnitRoot or mesh feet off anchor.
	unit_world.set_process(true)
	unit_world.begin_hex_move(WARRIOR_UNIT_ID, "warrior", 1, 0, 0, 0)
	var walk_ticks: int = 0
	while walk_ticks < 8:
		unit_world._tick_hex_moves(0.05)
		unit_world._refresh_placements()
		walk_ticks += 1
	var walk_world: Vector2 = unit_world._world_2d_for_unit(WARRIOR_UNIT_ID)
	var walk_anchor: Vector2 = CityWorldScript.compute_anchor_2d(
		walk_world, map_camera, MAP_LAYER_ORIGIN
	)
	var walk_feet: Vector2 = UnitWorldScript.projected_mesh_feet_2d(layer._world_camera, inst)
	_check(
		walk_feet.distance_to(walk_anchor) < FEET_DELTA_TOL_PX,
		"during walk mesh feet delta=%.4f px" % walk_feet.distance_to(walk_anchor),
	)
	_check(
		CityWorldScript.anchor_lock_delta_px(layer._world_camera, inst.global_position, walk_anchor)
		< ROOT_DELTA_TOL_PX,
		"during walk unit root stays on interpolated anchor",
	)

	# Finish move to idle and re-check feet.
	while unit_world.is_unit_hex_move_active(WARRIOR_UNIT_ID):
		unit_world._tick_hex_moves(0.08)
		unit_world._refresh_placements()
	var idle_anchor: Vector2 = CityWorldScript.compute_anchor_2d(
		world_2d, map_camera, MAP_LAYER_ORIGIN
	)
	var idle_feet: Vector2 = UnitWorldScript.projected_mesh_feet_2d(layer._world_camera, inst)
	_check(
		idle_feet.distance_to(idle_anchor) < FEET_DELTA_TOL_PX,
		"after idle return mesh feet delta=%.4f px" % idle_feet.distance_to(idle_anchor),
	)

	layer.free()
	if _failures > 0:
		push_error("test_unit_3d_anchor_lock: %d failures / %d checks" % [_failures, _checks])
		quit(1)
		return
	print("test_unit_3d_anchor_lock: %d checks, all ok" % _checks)
	quit(0)


func _warrior_from_scenario(scenario, unit_id: int):
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		if int(ulist[i].id) == unit_id:
			return ulist[i]
		i += 1
	return null


func _pan_offset_for_bottom_band(
	map_camera,
	world_2d: Vector2,
	map_layer_origin: Vector2,
	screen_size: Vector2,
	target_frac_y: float,
) -> Vector2:
	var target_y: float = target_frac_y * screen_size.y
	var band_min_y: float = screen_size.y * 0.55
	var band_max_y: float = screen_size.y * 0.92
	var best_off: Vector2 = Vector2.ZERO
	var best_score: float = INF
	var oy: float = -1200.0
	while oy <= 1200.0:
		map_camera.camera_world_offset = Vector2(0.0, oy)
		var anchor: Vector2 = CityWorldScript.compute_anchor_2d(world_2d, map_camera, map_layer_origin)
		if anchor.y < band_min_y or anchor.y > band_max_y:
			oy += 40.0
			continue
		if anchor.y < 0.0 or anchor.y > screen_size.y:
			oy += 40.0
			continue
		var score: float = absf(anchor.y - target_y)
		if score < best_score:
			best_score = score
			best_off = Vector2(0.0, oy)
		oy += 40.0
	if best_score < INF:
		return best_off
	oy = -1200.0
	while oy <= 1200.0:
		map_camera.camera_world_offset = Vector2(0.0, oy)
		var anchor: Vector2 = CityWorldScript.compute_anchor_2d(world_2d, map_camera, map_layer_origin)
		if anchor.y < 0.0 or anchor.y > screen_size.y:
			oy += 40.0
			continue
		var score: float = absf(anchor.y - target_y)
		if score < best_score:
			best_score = score
			best_off = Vector2(0.0, oy)
		oy += 40.0
	return best_off


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
