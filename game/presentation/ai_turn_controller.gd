# One KEY_A press: enumerate legal actions, decide once, submit via try_apply only.
# See docs/AI_LAYER.md, docs/RENDERING.md
class_name AITurnController
extends Node2D

const GameStateScript = preload("res://domain/game_state.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")
const TurnViewSyncScript = preload("res://presentation/turn_view_sync.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")

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
var empire_border_view
var city_worked_tiles_view
var terrain_edge_blend_view
var discovery_action_panel
var science_panel
var science_completed_popup
var discovery_popup
var map_visibility_view
var lightning_tree_view
var turn_start_banner
## Slice C8: when true, KEY_A AI submit is disabled (server-authoritative cloud prototype).
var skip_for_cloud: bool = false

func _unhandled_input(event: InputEvent) -> void:
	assert(GameStateScript != null)
	assert(LegalActionsScript != null)
	assert(RuleBasedAIPlayerScript != null)
	if skip_for_cloud:
		return
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
			var prev_log_sz = game_state.log.size()
			var result = game_state.try_apply(action)
			if result["accepted"]:
				if str(action.get("action_type", "")) == MoveUnitScript.ACTION_TYPE:
					var from_arr = action.get("from", [])
					var to_arr = action.get("to", [])
					if from_arr.size() >= 2 and to_arr.size() >= 2:
						var uid: int = int(action.get("unit_id", -1))
						var moved_u = game_state.scenario.unit_by_id(uid)
						if moved_u != null:
							units_view.present_warrior_hex_move_if_applicable(
								str(moved_u.type_id),
								uid,
								int(from_arr[0]),
								int(from_arr[1]),
								int(to_arr[0]),
								int(to_arr[1]),
							)
				DiscoveryPopupScript.run_engine_popups_after_apply(
					game_state,
					discovery_popup,
					science_completed_popup,
					prev_log_sz
				)
				if str(action.get("action_type", "")) == EndTurnScript.ACTION_TYPE:
					EndTurnController.apply_hotseat_clear_after_accepted_end_turn(
						selection,
						city_production_panel
					)
				else:
					selection.clear_unit()
				TurnViewSyncScript.refresh_map_views_and_hud_after_try_apply_turn_controllers(
					game_state,
					selection_view,
					units_view,
					terrain_foreground_view,
					unit_nameplate_view,
					city_nameplate_view,
					yield_overlay_view,
					city_territory_view,
					turn_label,
					log_view,
					city_production_panel,
					discovery_action_panel,
					science_panel,
					city_worked_tiles_view,
					empire_border_view,
					terrain_edge_blend_view,
					map_visibility_view,
					lightning_tree_view,
				)
				if str(action.get("action_type", "")) == EndTurnScript.ACTION_TYPE and turn_start_banner != null:
					turn_start_banner.show_for_current_player(game_state)
			else:
				push_warning("AI action rejected: %s" % result["reason"])
