# Mouse input for unit selection only. Does not mutate Scenario or Unit.
# See docs/SELECTION.md
class_name SelectionController
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var scenario
var layout
var selection
var selection_view
@export var marker_hit_radius_ratio: float = 0.35

func _unhandled_input(event: InputEvent) -> void:
	assert(HexCoordScript != null)
	if scenario == null or layout == null or selection == null or selection_view == null:
		return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var local_point = to_local(get_global_mouse_position())
			var hit_radius = HexLayoutScript.SIZE * marker_hit_radius_ratio
			var ulist = scenario.units()
			var found = false
			var i = 0
			while i < ulist.size():
				var u = ulist[i]
				var uw = layout.hex_to_world(u.position.q, u.position.r)
				if local_point.distance_to(uw) <= hit_radius:
					selection.select(u.id)
					found = true
					break
				i = i + 1
			if not found:
				selection.clear()
			selection_view.queue_redraw()
