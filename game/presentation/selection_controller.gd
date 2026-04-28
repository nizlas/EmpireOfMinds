# Mouse input: legal-destination MoveUnit (when selected) before unit re-selection; then unit pick; else clear.
# Submits actions only via game_state.try_apply. Does not mutate Scenario or Unit directly.
# See docs/SELECTION.md, docs/ACTIONS.md
class_name SelectionController
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")

var scenario
var game_state
var layout
var selection
var selection_view
var units_view
var turn_label
var log_view
@export var marker_hit_radius_ratio: float = 0.35

func _unhandled_input(event: InputEvent) -> void:
	assert(HexCoordScript != null)
	assert(MoveUnitScript != null)
	assert(MovementRulesScript != null)
	if game_state == null or layout == null or selection == null or selection_view == null or units_view == null:
		return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var scen = game_state.scenario
			var local_point = to_local(get_global_mouse_position())
			if not selection.is_empty():
				var dests = MovementRulesScript.legal_destinations(scen, selection.unit_id)
				var dest_hit = null
				var di = 0
				var dest_radius = HexLayoutScript.SIZE * 0.85
				while di < dests.size():
					var dcell = dests[di]
					var dw = layout.hex_to_world(dcell.q, dcell.r)
					if local_point.distance_to(dw) <= dest_radius:
						dest_hit = dcell
						break
					di = di + 1
				if dest_hit != null:
					var u = scen.unit_by_id(selection.unit_id)
					var action = MoveUnitScript.make(
						u.owner_id,
						u.id,
						u.position.q,
						u.position.r,
						dest_hit.q,
						dest_hit.r
					)
					var result = game_state.try_apply(action)
					if result["accepted"]:
						scenario = game_state.scenario
						selection_view.scenario = game_state.scenario
						units_view.scenario = game_state.scenario
						selection.clear()
						selection_view.queue_redraw()
						units_view.queue_redraw()
						if turn_label != null:
							turn_label.refresh()
						if log_view != null:
							log_view.refresh()
					else:
						push_warning("MoveUnit rejected: %s" % result["reason"])
					return
			var hit_radius = HexLayoutScript.SIZE * marker_hit_radius_ratio
			var ulist = scen.units()
			var found = false
			var i = 0
			while i < ulist.size():
				var u2 = ulist[i]
				var uw = layout.hex_to_world(u2.position.q, u2.position.r)
				if local_point.distance_to(uw) <= hit_radius:
					selection.select(u2.id)
					found = true
					break
				i = i + 1
			if found:
				selection_view.queue_redraw()
				return
			selection.clear()
			selection_view.queue_redraw()
