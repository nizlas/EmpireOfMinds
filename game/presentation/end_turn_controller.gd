# Space submits EndTurn for the current player via GameState.try_apply only.
# See docs/TURNS.md, docs/ACTIONS.md
class_name EndTurnController
extends Node2D

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")

var game_state
var selection
var selection_view
var units_view
var terrain_foreground_view
var unit_nameplate_view
var city_nameplate_view
var turn_label
var log_view
var city_production_panel
var yield_overlay_view
var city_territory_view
var discovery_action_panel
var science_panel
var science_completed_popup
var discovery_popup

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
			var prev_log_sz = game_state.log.size()
			var result = game_state.try_apply(action)
			if result["accepted"]:
				DiscoveryPopupScript.run_engine_popups_after_apply(
					game_state,
					discovery_popup,
					science_completed_popup,
					prev_log_sz
				)
				selection.clear_unit()
				selection_view.scenario = game_state.scenario
				units_view.scenario = game_state.scenario
				if terrain_foreground_view != null:
					var scen = game_state.scenario
					terrain_foreground_view.scenario = scen
					terrain_foreground_view.map = scen.map
				selection_view.queue_redraw()
				units_view.queue_redraw()
				if terrain_foreground_view != null:
					terrain_foreground_view.queue_redraw()
				if unit_nameplate_view != null:
					unit_nameplate_view.scenario = game_state.scenario
					unit_nameplate_view.queue_redraw()
				if city_nameplate_view != null:
					city_nameplate_view.scenario = game_state.scenario
					city_nameplate_view.queue_redraw()
				if yield_overlay_view != null:
					yield_overlay_view.scenario = game_state.scenario
					yield_overlay_view.queue_redraw()
				if city_territory_view != null:
					city_territory_view.scenario = game_state.scenario
					city_territory_view.queue_redraw()
				turn_label.refresh()
				if log_view != null:
					log_view.refresh()
				if city_production_panel != null:
					city_production_panel.refresh()
				if discovery_action_panel != null:
					discovery_action_panel.refresh()
				if science_panel != null:
					science_panel.refresh()
			else:
				push_warning("EndTurn rejected: %s" % result["reason"])
