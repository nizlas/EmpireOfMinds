# Space submits EndTurn for the current player via GameState.try_apply only.
# See docs/TURNS.md, docs/ACTIONS.md
class_name EndTurnController
extends Node2D

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")
const TurnViewSyncScript = preload("res://presentation/turn_view_sync.gd")

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
## Slice C14d-4b: cloud uses **Main** + seat-token POST; disable local hotseat EndTurn apply.
var skip_for_cloud: bool = false

## Phase **5.2.1** hotseat: after accepted **`EndTurn`**, clear unit + city selection and exit **PLANNING** so the next **current** player does not inherit hub focus. Presentation-only.
static func apply_hotseat_clear_after_accepted_end_turn(selection, city_production_panel) -> void:
	if selection != null:
		selection.clear_unit()
	if city_production_panel != null and city_production_panel.city_view_state != null:
		city_production_panel.city_view_state.reset_to_normal()
	if selection != null:
		selection.clear_city()


func _unhandled_input(event: InputEvent) -> void:
	assert(GameStateScript != null)
	assert(EndTurnScript != null)
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
				apply_hotseat_clear_after_accepted_end_turn(selection, city_production_panel)
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
				if turn_start_banner != null:
					turn_start_banner.show_for_current_player(game_state)
			else:
				push_warning("EndTurn rejected: %s" % result["reason"])
			return
