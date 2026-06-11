# Headless: main.tscn MapPresentation3DLayer uses stretch=false before SubViewport resize.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var layer: MapPresentation3DLayer = main.get_node_or_null(
		"MapPresentation3DLayer"
	) as MapPresentation3DLayer
	_check(layer != null, "MapPresentation3DLayer exists on Main")
	_check(
		MapLayerScript.RESIZE_FIX_VERSION == "2026-06-10b",
		"resize_fix_version marker present in script"
	)
	var scene_container: SubViewportContainer = main.get_node_or_null(
		"MapPresentation3DLayer/City3DViewportContainer"
	) as SubViewportContainer
	_check(scene_container != null, "City3DViewportContainer serialized in main.tscn")
	if scene_container != null:
		_check(scene_container.stretch == false, "main.tscn SubViewportContainer.stretch=false")
	var active_container: SubViewportContainer = layer._viewport_container
	_check(active_container != null, "layer resolved active SubViewportContainer")
	if active_container != null and scene_container != null:
		_check(active_container == scene_container, "active container matches main.tscn node")
		_check(active_container.stretch == false, "active container stretch=false after _ready")
	var active_subvp: SubViewport = layer._viewport
	_check(active_subvp != null, "layer resolved active SubViewport")
	if active_subvp != null and active_container != null:
		_check(active_subvp.get_parent() == active_container, "SubViewport parent is active container")
		_check(
			active_subvp.msaa_3d == Viewport.MSAA_2X,
			"composite SubViewport msaa_3d=MSAA_2X",
		)
		_check(
			active_subvp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
			"composite SubViewport screen_space_aa=FXAA",
		)
	# Simulate stale stretch=true (in-game regression) then resize.
	if active_container != null:
		active_container.stretch = true
		_check(active_container.stretch == true, "precondition stretch=true before resize")
		layer.prepare_for_draw()
		_check(active_container.stretch == false, "prepare_for_draw enforces stretch=false")
		_check(active_subvp.size.x > 0, "SubViewport resized with stretch=false")
		_check(active_subvp.size.y > 0, "SubViewport height non-zero after resize")
		_check(
			active_subvp.msaa_3d == Viewport.MSAA_2X,
			"composite SubViewport msaa_3d preserved after prepare_for_draw",
		)
		_check(
			active_subvp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
			"composite SubViewport FXAA preserved after prepare_for_draw",
		)
	main.free()
	if _failures > 0:
		push_error(
			"test_map_presentation_3d_layer_main_tscn: %d failures / %d checks" % [_failures, _checks]
		)
		quit(1)
	print("test_map_presentation_3d_layer_main_tscn: %d checks, all ok" % _checks)
	quit(0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
