# Wires GameState, Scenario, HexLayout, MapView, UnitsView, SelectionView, and SelectionController. No gameplay loop, no autoloads.
# See docs/RENDERING.md, docs/SELECTION.md
extends Node2D

## Initial pixel origin for MapView, CitiesView, SelectionView, UnitsView, TerrainForegroundView, SelectionController (Phase 4.3g). **4.5m:** set **once** on each node in `_ready`; pan uses **MapCamera.camera_world_offset** only.
const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FactionBannerGalleryScript = preload("res://presentation/faction_banner_gallery.gd")

var _faction_banner_gallery
var _map_projection
var _map_camera

func _redraw_map_layers() -> void:
	$MapView.queue_redraw()
	$CitiesView.queue_redraw()
	$SelectionView.queue_redraw()
	$UnitsView.queue_redraw()
	$TerrainForegroundView.queue_redraw()

func _ready() -> void:
	_map_projection = MapPlaneProjectionScript.new()
	_map_projection.vanishing_pres = (get_viewport_rect().size * 0.5) - MAP_LAYER_ORIGIN
	_map_camera = MapCameraScript.new()
	_map_camera.projection = _map_projection
	for n in [
		$MapView,
		$CitiesView,
		$SelectionView,
		$UnitsView,
		$TerrainForegroundView,
		$SelectionController,
	]:
		n.position = MAP_LAYER_ORIGIN
	$MapView.scale = Vector2.ONE
	$MapView.camera = _map_camera
	$CitiesView.scale = Vector2.ONE
	$CitiesView.camera = _map_camera
	$SelectionView.scale = Vector2.ONE
	$SelectionView.camera = _map_camera
	$UnitsView.scale = Vector2.ONE
	$UnitsView.camera = _map_camera
	$TerrainForegroundView.scale = Vector2.ONE
	$TerrainForegroundView.camera = _map_camera
	$SelectionController.scale = Vector2.ONE
	$SelectionController.camera = _map_camera
	_redraw_map_layers()
	var scenario = ScenarioScript.make_prototype_play_scenario()
	var game_state = GameStateScript.new(scenario)
	var layout = HexLayoutScript.new()
	var selection = SelectionStateScript.new()
	var map_view = $MapView
	map_view.map = scenario.map
	map_view.layout = layout
	map_view.queue_redraw()
	var cities_view = $CitiesView
	cities_view.scenario = scenario
	cities_view.layout = layout
	cities_view.queue_redraw()
	var units_view = $UnitsView
	units_view.scenario = scenario
	units_view.layout = layout
	units_view.selection = selection
	units_view.queue_redraw()
	var terrain_foreground = $TerrainForegroundView
	terrain_foreground.map = scenario.map
	terrain_foreground.layout = layout
	terrain_foreground.scenario = scenario
	terrain_foreground.forest_density_ratio = map_view.forest_density_ratio
	terrain_foreground.foreground_unit_reference_height_ratio = units_view.unit_icon_height_ratio
	terrain_foreground.queue_redraw()
	var selection_view = $SelectionView
	selection_view.scenario = scenario
	selection_view.layout = layout
	selection_view.selection = selection
	selection_view.queue_redraw()
	var selection_controller = $SelectionController
	selection_controller.scenario = scenario
	selection_controller.game_state = game_state
	selection_controller.layout = layout
	selection_controller.selection = selection
	selection_controller.selection_view = selection_view
	selection_controller.units_view = units_view
	selection_controller.cities_view = cities_view
	selection_controller.terrain_foreground_view = terrain_foreground
	var turn_label = $TurnLabel
	turn_label.game_state = game_state
	turn_label.refresh()
	selection_controller.turn_label = turn_label
	var end_turn_controller = $EndTurnController
	end_turn_controller.game_state = game_state
	end_turn_controller.selection = selection
	end_turn_controller.selection_view = selection_view
	end_turn_controller.units_view = units_view
	end_turn_controller.terrain_foreground_view = terrain_foreground
	end_turn_controller.turn_label = turn_label
	var ai_turn_controller = $AITurnController
	ai_turn_controller.game_state = game_state
	ai_turn_controller.selection = selection
	ai_turn_controller.selection_view = selection_view
	ai_turn_controller.units_view = units_view
	ai_turn_controller.terrain_foreground_view = terrain_foreground
	ai_turn_controller.turn_label = turn_label
	var log_view = $LogView
	log_view.game_state = game_state
	log_view.refresh()
	selection_controller.log_view = log_view
	end_turn_controller.log_view = log_view
	ai_turn_controller.log_view = log_view
	_faction_banner_gallery = FactionBannerGalleryScript.new()
	add_child(_faction_banner_gallery)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var map_v: Node2D = $MapView
			var prev_local: Vector2 = map_v.to_local(mm.global_position - mm.relative)
			var cur_local: Vector2 = map_v.to_local(mm.global_position)
			var prev_world: Vector2 = _map_camera.to_layout(prev_local)
			var cur_world: Vector2 = _map_camera.to_layout(cur_local)
			if not (prev_world.is_finite() and cur_world.is_finite()):
				return
			_map_camera.camera_world_offset += prev_world - cur_world
			_redraw_map_layers()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_F1:
			if _faction_banner_gallery != null:
				_faction_banner_gallery.toggle_visible()
