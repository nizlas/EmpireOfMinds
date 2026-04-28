# Wires a single Scenario and HexLayout to MapView and UnitsView. No gameplay, no input, no autoloads.
# See docs/RENDERING.md
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

func _ready() -> void:
	var scenario = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var map_view = $MapView
	map_view.map = scenario.map
	map_view.layout = layout
	map_view.queue_redraw()
	var units_view = $UnitsView
	units_view.scenario = scenario
	units_view.layout = layout
	units_view.queue_redraw()
