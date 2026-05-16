# Phase 5.2.4k — per-current-player explored gating for map-detail presentation (yields, decorations, banners).
# Same semantics as [MapVisibilityView]: [TurnState.current_player_id] + [PlayerVisibilityState.is_explored].
# Presentation-only; null-safe defaults preserve prior draw-all behavior when visibility is not wired.
class_name PresentationVisibility
extends RefCounted


static func is_coord_explored_for_current_player(game_state, coord) -> bool:
	if game_state == null or coord == null:
		return true
	if game_state.turn_state == null or game_state.visibility_state == null:
		return true
	var pid: int = int(game_state.turn_state.current_player_id())
	return game_state.visibility_state.is_explored(pid, coord)


static func should_draw_map_detail_for_current_player(game_state, coord) -> bool:
	return is_coord_explored_for_current_player(game_state, coord)
