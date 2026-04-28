# Wires Scenario, HexLayout, MapView, UnitsView, SelectionView, and SelectionController. No gameplay loop, no autoloads.
# See docs/RENDERING.md, docs/SELECTION.md
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

func _ready() -> void:
	var scenario = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var selection = SelectionStateScript.new()
	var map_view = $MapView
	map_view.map = scenario.map
	map_view.layout = layout
	map_view.queue_redraw()
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
	selection_controller.layout = layout
	selection_controller.selection = selection
	selection_controller.selection_view = selection_view
