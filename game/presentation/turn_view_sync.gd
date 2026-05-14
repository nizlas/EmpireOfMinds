# Dedup **`Scenario`** → map **`Node2D`** views → HUD **`refresh`** sequences shared by **EndTurnController** / **AITurnController** and **SelectionController** foreground sync.
extends RefCounted


## Mirrors **`SelectionController`** `_sync_terrain_foreground_from_game_state` (**terrain + nameplates + yield overlay + territory + worked-tile markers**); keeps **immediate** **`TerrainForegroundView.queue_redraw`** like that path.
static func sync_terrain_related_views(
	scen,
	terrain_foreground_view,
	unit_nameplate_view,
	city_nameplate_view,
	yield_overlay_view,
	city_territory_view,
	city_worked_tiles_view = null,
) -> void:
	if scen == null:
		return
	if terrain_foreground_view != null:
		terrain_foreground_view.scenario = scen
		terrain_foreground_view.map = scen.map
		terrain_foreground_view.queue_redraw()
	if unit_nameplate_view != null:
		unit_nameplate_view.scenario = scen
		unit_nameplate_view.queue_redraw()
	if city_nameplate_view != null:
		city_nameplate_view.scenario = scen
		city_nameplate_view.queue_redraw()
	if yield_overlay_view != null:
		yield_overlay_view.scenario = scen
		yield_overlay_view.queue_redraw()
	if city_territory_view != null:
		city_territory_view.scenario = scen
		city_territory_view.queue_redraw()
	if city_worked_tiles_view != null:
		city_worked_tiles_view.scenario = scen
		city_worked_tiles_view.queue_redraw()

## Mirrors **EndTurnController** / **AITurnController** accepted-action block after **`discovery_popup`** / **`selection.clear_unit()`** (**not** inclusive of those callers).
static func refresh_map_views_and_hud_after_try_apply_turn_controllers(game_state,
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
	city_worked_tiles_view = null,
) -> void:
	if game_state == null:
		return
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
	if city_worked_tiles_view != null:
		city_worked_tiles_view.scenario = game_state.scenario
		city_worked_tiles_view.queue_redraw()
	turn_label.refresh()
	if log_view != null:
		log_view.refresh()
	if city_production_panel != null:
		city_production_panel.refresh()
	if discovery_action_panel != null:
		discovery_action_panel.refresh()
	if science_panel != null:
		science_panel.refresh()
