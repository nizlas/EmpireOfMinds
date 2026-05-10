# Wires GameState, Scenario, HexLayout, MapView, UnitsView, SelectionView, and SelectionController. No gameplay loop, no autoloads.
# See docs/RENDERING.md, docs/SELECTION.md
extends Node2D

## Initial pixel origin for map-layer **Node2D** children including **UnitNameplateView** (Phase 5.1.11). **4.5m:** set **once** in `_ready`; pan uses **MapCamera.camera_world_offset**. **5.1.11:** **UnitNameplateView** uses **`z_index` 2** so nameplates draw above terrain/unit markers, still below **HudCanvas**.
const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FactionBannerGalleryScript = preload("res://presentation/faction_banner_gallery.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")
## Phase 4.5n: mouse-wheel zoom multiplier (center-anchored in layer-local space; not cursor-anchored).
const ZOOM_STEP: float = 1.10

var _faction_banner_gallery
var _map_projection
var _map_camera

func _redraw_map_layers() -> void:
	$MapView.queue_redraw()
	$CitiesView.queue_redraw()
	$SelectionView.queue_redraw()
	$UnitsView.queue_redraw()
	$TerrainForegroundView.queue_redraw()
	$LightningTreeView.queue_redraw()
	$UnitNameplateView.queue_redraw()

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
		$LightningTreeView,
		$UnitNameplateView,
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
	# Phase **4.6p:** **`TerrainForegroundView.z_index = 1`** lifts the **entire foreground canvas**
	# above **`MapView`** / **`CitiesView`** / **`SelectionView`** / **`UnitsView`** node shells so **back**
	# terrain stays behind **and** forest grid passes + marker pass run in **one** TFV **`_draw`**. **`UnitsView`** /
	# **`CitiesView`** **`_draw`** are no-ops when wired to TFV — markers are not painted on a second **`CanvasItem`**.
	$UnitsView.z_index = 0
	$TerrainForegroundView.scale = Vector2.ONE
	$TerrainForegroundView.camera = _map_camera
	$TerrainForegroundView.z_index = 1
	$LightningTreeView.z_index = 1
	$UnitNameplateView.scale = Vector2.ONE
	$UnitNameplateView.camera = _map_camera
	$UnitNameplateView.z_index = 2
	$SelectionController.scale = Vector2.ONE
	$SelectionController.camera = _map_camera
	var scenario = ScenarioScript.make_prototype_play_scenario()
	var game_state = GameStateScript.new(scenario)
	var layout = HexLayoutScript.new()
	var selection = SelectionStateScript.new()
	var map_view = $MapView
	map_view.map = scenario.map
	map_view.layout = layout
	var cities_view = $CitiesView
	cities_view.scenario = scenario
	cities_view.layout = layout
	var lightning_tree_view = $LightningTreeView
	lightning_tree_view.game_state = game_state
	lightning_tree_view.scenario = scenario
	lightning_tree_view.layout = layout
	lightning_tree_view.camera = _map_camera
	var units_view = $UnitsView
	units_view.scenario = scenario
	units_view.layout = layout
	units_view.selection = selection
	var terrain_foreground = $TerrainForegroundView
	map_view.terrain_foreground_view = terrain_foreground
	terrain_foreground.map = scenario.map
	terrain_foreground.layout = layout
	terrain_foreground.scenario = scenario
	terrain_foreground.forest_density_ratio = map_view.forest_density_ratio
	terrain_foreground.foreground_unit_reference_height_ratio = units_view.unit_icon_height_ratio
	# Prototype play map only: deterministic forest clusters for visual review (not gameplay / not biome rules).
	var proto_forest_override: Dictionary = PlainsForestScript.prototype_forest_cluster_set()
	map_view.forest_decoration_override = proto_forest_override
	terrain_foreground.forest_decoration_override = proto_forest_override
	# Phase **4.6p:** cross-wire **before** any **`queue_redraw`** so **`UnitsView._draw`** / **`CitiesView._draw`**
	# skip own-canvas markers when **`TerrainForegroundView`** hosts forest + marker order.
	terrain_foreground.units_view = units_view
	terrain_foreground.map_view = map_view
	terrain_foreground.cities_view = cities_view
	cities_view.terrain_foreground_view = terrain_foreground
	units_view.terrain_foreground_view = terrain_foreground
	var unit_nameplate_view = $UnitNameplateView
	unit_nameplate_view.scenario = scenario
	unit_nameplate_view.layout = layout
	unit_nameplate_view.units_view = units_view
	var selection_view = $SelectionView
	selection_view.scenario = scenario
	selection_view.layout = layout
	selection_view.selection = selection
	var selection_controller = $SelectionController
	selection_controller.scenario = scenario
	selection_controller.game_state = game_state
	selection_controller.layout = layout
	selection_controller.selection = selection
	selection_controller.selection_view = selection_view
	selection_controller.units_view = units_view
	selection_controller.cities_view = cities_view
	selection_controller.terrain_foreground_view = terrain_foreground
	selection_controller.unit_nameplate_view = unit_nameplate_view
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
	end_turn_controller.unit_nameplate_view = unit_nameplate_view
	end_turn_controller.turn_label = turn_label
	var ai_turn_controller = $AITurnController
	ai_turn_controller.game_state = game_state
	ai_turn_controller.selection = selection
	ai_turn_controller.selection_view = selection_view
	ai_turn_controller.units_view = units_view
	ai_turn_controller.terrain_foreground_view = terrain_foreground
	ai_turn_controller.unit_nameplate_view = unit_nameplate_view
	ai_turn_controller.turn_label = turn_label
	var log_view = $LogView
	log_view.game_state = game_state
	log_view.refresh()
	selection_controller.log_view = log_view
	end_turn_controller.log_view = log_view
	ai_turn_controller.log_view = log_view
	var city_production_panel = $HudCanvas/CityProductionPanel
	city_production_panel.game_state = game_state
	city_production_panel.selection = selection
	city_production_panel.cities_view = cities_view
	city_production_panel.turn_label = turn_label
	city_production_panel.log_view = log_view
	selection_controller.city_production_panel = city_production_panel
	end_turn_controller.city_production_panel = city_production_panel
	ai_turn_controller.city_production_panel = city_production_panel
	city_production_panel.refresh()
	var discovery_action_panel = $HudCanvas/DiscoveryActionPanel
	discovery_action_panel.game_state = game_state
	discovery_action_panel.turn_label = turn_label
	discovery_action_panel.log_view = log_view
	discovery_action_panel.city_production_panel = city_production_panel
	var discovery_popup = $HudCanvas/DiscoveryPopup
	discovery_popup.game_state = game_state
	discovery_action_panel.discovery_popup = discovery_popup
	var science_completed_popup = $HudCanvas/ScienceCompletedPopup
	science_completed_popup.game_state = game_state
	selection_controller.discovery_action_panel = discovery_action_panel
	end_turn_controller.discovery_action_panel = discovery_action_panel
	ai_turn_controller.discovery_action_panel = discovery_action_panel
	discovery_action_panel.refresh()
	selection_controller.discovery_popup = discovery_popup
	selection_controller.science_completed_popup = science_completed_popup
	end_turn_controller.discovery_popup = discovery_popup
	end_turn_controller.science_completed_popup = science_completed_popup
	ai_turn_controller.discovery_popup = discovery_popup
	ai_turn_controller.science_completed_popup = science_completed_popup
	_faction_banner_gallery = FactionBannerGalleryScript.new()
	add_child(_faction_banner_gallery)
	_redraw_map_layers()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		var factor: float = 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			factor = ZOOM_STEP
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			factor = 1.0 / ZOOM_STEP
		else:
			return
		var center_local: Vector2 = get_viewport_rect().size * 0.5 - MAP_LAYER_ORIGIN
		var old_zoom: float = _map_camera.zoom
		var world_before: Vector2 = _map_camera.to_layout(center_local)
		_map_camera.set_zoom_clamped(_map_camera.zoom * factor)
		if is_equal_approx(_map_camera.zoom, old_zoom):
			get_viewport().set_input_as_handled()
			return
		var world_after: Vector2 = _map_camera.to_layout(center_local)
		if world_before.is_finite() and world_after.is_finite():
			_map_camera.camera_world_offset += world_before - world_after
		_redraw_map_layers()
		get_viewport().set_input_as_handled()
		return
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
