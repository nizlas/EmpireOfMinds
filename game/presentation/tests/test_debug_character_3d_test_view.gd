# Headless: debug bronze-armed warrior + Niclas GLB figures (gated presentation only).
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const DebugViewScript = preload("res://presentation/debug_character_3d_test_view.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	OS.unset_environment(Experiment.ENV_DEBUG_EXTRA_3D_CHARACTERS)
	OS.unset_environment(Experiment.ENV_NICLAS_3D_DIAG)
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(DebugViewScript.BRONZE_GLB_PATH), "bronze GLB resource exists")
	_check(ResourceLoader.exists(DebugViewScript.NICLAS_GLB_PATH), "niclas GLB resource exists")
	_check(not DebugViewScript.is_gate_enabled(), "gate off by default")
	_check(not DebugViewScript.is_active(), "not active when gate off")

	var bronze_scene: PackedScene = ResourceLoader.load(DebugViewScript.bronze_scene_path()) as PackedScene
	var niclas_scene: PackedScene = ResourceLoader.load(DebugViewScript.niclas_scene_path()) as PackedScene
	_check(bronze_scene != null, "bronze PackedScene loads")
	_check(niclas_scene != null, "niclas PackedScene loads")

	var bronze_probe: Node = bronze_scene.instantiate()
	var niclas_probe: Node = niclas_scene.instantiate()
	_check(bronze_probe != null, "bronze scene instantiates")
	_check(niclas_probe != null, "niclas scene instantiates")
	var bronze_names: PackedStringArray = DebugViewScript._animation_names_from_model(bronze_probe)
	var niclas_names: PackedStringArray = DebugViewScript._animation_names_from_model(niclas_probe)
	_check(bronze_probe.find_children("*", "AnimationPlayer", true, false).size() > 0, "bronze has AnimationPlayer")
	_check(niclas_probe.find_children("*", "AnimationPlayer", true, false).size() > 0, "niclas has AnimationPlayer")
	_check(not niclas_names.is_empty(), "niclas animation catalog non-empty")
	var niclas_idle: String = DebugViewScript.pick_idle_clip_name(niclas_names)
	_check(not niclas_idle.is_empty(), "niclas idle candidate resolved")
	bronze_probe.queue_free()
	niclas_probe.queue_free()

	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.make_tiny_test_scenario()
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

	var debug_view = layer._debug_character_view
	_check(debug_view != null, "DebugCharacter3DTestView created under WorldPanRoot")
	_check(debug_view.get_active_debug_character_count() == 0, "no debug figures when gate off")

	OS.set_environment(Experiment.ENV_DEBUG_EXTRA_3D_CHARACTERS, "1")
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	_check(DebugViewScript.is_gate_enabled(), "gate on when env set")
	_check(DebugViewScript.is_active(), "active with real 3d + gate")
	_check(debug_view.has_bronze_instance(), "bronze instance created when gated")
	_check(debug_view.has_niclas_instance(), "niclas instance created when gated")
	_check(debug_view.get_active_debug_character_count() == 2, "two debug figures active")
	_check(debug_view.niclas_animation_catalog().size() > 0, "niclas catalog on live instance")
	_check(not debug_view.niclas_idle_clip_name().is_empty(), "niclas idle on live instance")
	_check(not debug_view.bronze_idle_clip_name().is_empty(), "bronze idle on live instance")
	_check(debug_view.niclas_placement_hex() == Vector2i(0, 1), "niclas hex offset from settler")
	_check(debug_view.bronze_placement_hex() == Vector2i(1, -1), "bronze hex offset from warrior")

	var player: AnimationPlayer = debug_view._animation_player_for_root(debug_view._niclas_root)
	_check(player != null, "niclas AnimationPlayer on instance")
	if player != null:
		_check(player.has_animation(debug_view.niclas_idle_clip_name()), "niclas idle clip playable")
		_check(player.is_playing(), "niclas idle is playing")

	OS.unset_environment(Experiment.ENV_DEBUG_EXTRA_3D_CHARACTERS)
	layer.sync_from_scenario()
	await process_frame
	_check(debug_view.get_active_debug_character_count() == 0, "instances cleared when gate off")

	root.free()
	if _failures > 0:
		push_error("test_debug_character_3d_test_view: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_debug_character_3d_test_view: %d checks, all ok" % _checks)
	quit(0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
