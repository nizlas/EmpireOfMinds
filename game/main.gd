# Wires GameState, Scenario, HexLayout, MapView, UnitsView, SelectionView, and SelectionController. No gameplay loop, no autoloads.
# See docs/RENDERING.md, docs/SELECTION.md
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")

func _ready() -> void:
	var scenario = ScenarioScript.make_tiny_test_scenario()
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
	units_view.queue_redraw()
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
	var turn_label = $TurnLabel
	turn_label.game_state = game_state
	turn_label.refresh()
	selection_controller.turn_label = turn_label
	var end_turn_controller = $EndTurnController
	end_turn_controller.game_state = game_state
	end_turn_controller.selection = selection
	end_turn_controller.selection_view = selection_view
	end_turn_controller.units_view = units_view
	end_turn_controller.turn_label = turn_label
	var ai_turn_controller = $AITurnController
	ai_turn_controller.game_state = game_state
	ai_turn_controller.selection = selection
	ai_turn_controller.selection_view = selection_view
	ai_turn_controller.units_view = units_view
	ai_turn_controller.turn_label = turn_label
	var log_view = $LogView
	log_view.game_state = game_state
	log_view.refresh()
	selection_controller.log_view = log_view
	end_turn_controller.log_view = log_view
	ai_turn_controller.log_view = log_view
