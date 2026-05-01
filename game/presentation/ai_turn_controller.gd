# One KEY_A press: enumerate legal actions, decide once, submit via try_apply only.
# See docs/AI_LAYER.md, docs/RENDERING.md
class_name AITurnController
extends Node2D

const GameStateScript = preload("res://domain/game_state.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")

var game_state
var selection
var selection_view
var units_view
var terrain_foreground_view
var turn_label
var log_view

func _unhandled_input(event: InputEvent) -> void:
	assert(GameStateScript != null)
	assert(LegalActionsScript != null)
	assert(RuleBasedAIPlayerScript != null)
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
		if ek.pressed and not ek.echo and ek.keycode == KEY_A:
			var legal_actions = LegalActionsScript.for_current_player(game_state)
			var action = RuleBasedAIPlayerScript.decide(game_state, legal_actions)
			if action.size() == 0:
				push_warning("AI found no legal action")
				return
			var result = game_state.try_apply(action)
			if result["accepted"]:
				selection.clear()
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
				turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("AI action rejected: %s" % result["reason"])
