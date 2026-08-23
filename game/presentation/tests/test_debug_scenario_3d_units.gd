# Headless: debug scenario units render once via Unit3DWorldView (no duplicate debug view).
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")
const AnimRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const NICLAS_UNIT_ID: int = ScenarioScript.DEBUG_NICLAS_UNIT_ID
const BRONZE_UNIT_ID: int = ScenarioScript.DEBUG_BRONZE_UNIT_ID
const GENERATED_WARRIOR_UNIT_ID: int = ScenarioScript.DEBUG_GENERATED_WARRIOR_UNIT_ID

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	call_deferred("_run")


func _run() -> void:
	_check_glb_and_definitions()
	await _check_single_renderer_path()
	if _failures > 0:
		push_error("test_debug_scenario_3d_units: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_debug_scenario_3d_units: %d checks, all ok" % _checks)
	quit(0)


func _check_glb_and_definitions() -> void:
	_check(
		ResourceLoader.exists(Experiment.NICLAS_GLB_PATH),
		"niclas GLB exists",
	)
	_check(
		ResourceLoader.exists(Experiment.BRONZE_ARMED_WARRIOR_GLB_PATH),
		"bronze GLB exists",
	)
	_check(
		ResourceLoader.exists(Experiment.GENERATED_WARRIOR_GLB_PATH),
		"generated_warrior GLB exists",
	)
	_check(
		Experiment.animated_scene_path_for_type("niclas") == Experiment.NICLAS_GLB_PATH,
		"niclas scene path",
	)
	_check(
		Experiment.animated_scene_path_for_type("bronze_armed_warrior")
			== Experiment.BRONZE_ARMED_WARRIOR_GLB_PATH,
		"bronze scene path",
	)
	_check(
		Experiment.animated_scene_path_for_type("generated_warrior")
			== Experiment.GENERATED_WARRIOR_GLB_PATH,
		"generated_warrior scene path",
	)
	_check(
		"generated_warrior" in Experiment.DEBUG_3D_TYPE_IDS,
		"generated_warrior is a supported debug 3D type",
	)
	_check(
		"generated_warrior" in Experiment.SUPPORTED_3D_TYPE_IDS,
		"generated_warrior is a supported 3D type",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Idle_3", true, "niclas") == "Idle_3",
		"niclas idle remap",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Walking", true, "niclas") == "Walking",
		"niclas walk remap",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Walking", true, "bronze_armed_warrior") == "Walking",
		"bronze walk remap",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Idle_3", true, "bronze_armed_warrior") == "Attack",
		"bronze temporary idle remap",
	)
	for semantic in [
		"Idle_3",
		"Walking",
		"Running",
		"Left_Slash",
		"Hit_Reaction_1",
		"Dead",
	]:
		_check(
			AnimRemapScript.glb_clip_for_visual(semantic, true, "generated_warrior") == semantic,
			"generated_warrior identity remap for %s" % semantic,
		)
	# Historical Warrior swap remap must not leak onto generated_warrior.
	_check(
		AnimRemapScript.glb_clip_for_visual("Dead", true, "warrior") == "Left_Slash",
		"warrior Dead still uses historical swap remap",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Dead", true, "generated_warrior") == "Dead",
		"generated_warrior Dead is identity (not warrior swap)",
	)
	_check(
		AnimRemapScript.glb_clip_for_visual("Walking", true, "settler") == "Running",
		"settler walk remap unchanged",
	)
	var niclas_def: Dictionary = UnitDefinitionsScript.get_unit("unit_niclas")
	_check(not niclas_def.is_empty(), "unit_niclas definition")
	_check(str(niclas_def.get("glb_path", "")) == Experiment.NICLAS_GLB_PATH, "niclas glb in definitions")
	var generated_def: Dictionary = UnitDefinitionsScript.get_unit("unit_generated_warrior")
	_check(not generated_def.is_empty(), "unit_generated_warrior definition")
	_check(
		str(generated_def.get("glb_path", "")) == Experiment.GENERATED_WARRIOR_GLB_PATH,
		"generated_warrior glb in definitions",
	)


func _check_single_renderer_path() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.with_debug_character_units(
		ScenarioScript.make_tiny_test_scenario()
	)
	var layer = MapLayerScript.new()
	root.add_child(layer)
	layer.real_3d_units_enabled = true
	layer.layout = layout
	layer.scenario = scenario
	layer.map_layer_origin = MAP_LAYER_ORIGIN
	var projection = MapPlaneProjectionScript.new()
	projection.vanishing_pres = (get_root().get_visible_rect().size * 0.5) - MAP_LAYER_ORIGIN
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	layer.map_camera = map_camera
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var unit_world = layer._unit_world_view
	_check(unit_world != null, "Unit3DWorldView present")
	_check(
		layer._world_pan_root.get_node_or_null("DebugCharacter3DTestView") == null,
		"no duplicate DebugCharacter3DTestView",
	)
	_check(unit_world.has_ready_unit_instance(NICLAS_UNIT_ID), "Niclas real 3D instance")
	_check(
		unit_world.has_ready_unit_instance(BRONZE_UNIT_ID),
		"Bronze real 3D instance",
	)
	_check(
		unit_world.has_ready_unit_instance(GENERATED_WARRIOR_UNIT_ID),
		"Generated Warrior real 3D instance",
	)
	_check(
		unit_world.has_ready_unit_instance(1) and unit_world.has_ready_unit_instance(2),
		"settler and warrior still render",
	)
	var expected_count: int = scenario.units().size()
	_check(expected_count == 6, "debug tiny scenario has six units")
	_check(
		unit_world.get_active_unit_count() == expected_count,
		"one real 3D instance per scenario unit (no duplicates)",
	)
	var subvp: SubViewport = layer._viewport
	if subvp != null:
		_check(subvp.msaa_3d == Viewport.MSAA_2X, "shared composite MSAA_2X")
		_check(
			subvp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
			"shared composite FXAA",
		)
	_check(
		not layer.should_auto_blit_for_unit(NICLAS_UNIT_ID, "niclas"),
		"Niclas skips per-unit blit SubViewport",
	)
	_check(
		not layer.should_auto_blit_for_unit(BRONZE_UNIT_ID, "bronze_armed_warrior"),
		"Bronze skips per-unit blit SubViewport",
	)
	_check(
		not layer.should_auto_blit_for_unit(GENERATED_WARRIOR_UNIT_ID, "generated_warrior"),
		"Generated Warrior skips per-unit blit SubViewport",
	)
	var niclas_player: AnimationPlayer = unit_world._animation_player_for_root(
		unit_world._instance_by_unit_id[NICLAS_UNIT_ID] as Node3D
	)
	_check(niclas_player != null, "Niclas AnimationPlayer")
	if niclas_player != null:
		_check(niclas_player.has_animation("Idle_3"), "Niclas Idle_3 clip")
		_check(niclas_player.is_playing(), "Niclas idle variation playing")
		_check(unit_world._idle_variation_by_unit_id.has(NICLAS_UNIT_ID), "Niclas has idle variation state")
	var generated_player: AnimationPlayer = unit_world._animation_player_for_root(
		unit_world._instance_by_unit_id[GENERATED_WARRIOR_UNIT_ID] as Node3D
	)
	_check(generated_player != null, "Generated Warrior AnimationPlayer")
	if generated_player != null:
		for clip in [
			"Idle_3",
			"Walking",
			"Running",
			"Left_Slash",
			"Hit_Reaction_1",
			"Dead",
		]:
			_check(
				generated_player.has_animation(clip),
				"Generated Warrior has raw clip %s" % clip,
			)
	root.free()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
