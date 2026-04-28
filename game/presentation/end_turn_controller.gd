# Space submits EndTurn for the current player via GameState.try_apply only.
# See docs/TURNS.md, docs/ACTIONS.md
class_name EndTurnController
extends Node2D

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var game_state
var selection
var selection_view
var units_view
var turn_label
var log_view

func _unhandled_input(event: InputEvent) -> void:
	assert(GameStateScript != null)
	assert(EndTurnScript != null)
	if (
		game_state == null
		or selection == null
		or selection_view == null
		or units_view == null
		or turn_label == null
	):
		return
	if event is InputEventKey:
		var ek = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_SPACE:
			var ts = game_state.turn_state
			var action = EndTurnScript.make(ts.current_player_id())
			var result = game_state.try_apply(action)
			if result["accepted"]:
				selection.clear()
				selection_view.scenario = game_state.scenario
				units_view.scenario = game_state.scenario
				selection_view.queue_redraw()
				units_view.queue_redraw()
				turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("EndTurn rejected: %s" % result["reason"])
