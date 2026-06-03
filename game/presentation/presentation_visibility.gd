# Phase 5.2.4k — per-viewing-player explored gating for map-detail presentation (yields, decorations, banners).
# Hotseat: [TurnState.current_player_id]. Cloud (C14d-4c): [viewing_player_id_override] = local seat actor_id.
# Presentation-only; null-safe defaults preserve prior draw-all behavior when visibility is not wired.
class_name PresentationVisibility
extends RefCounted

## Cloud ongoing: local seat perspective. **-1** = use turn_state.current_player_id() (hotseat).
static var viewing_player_id_override: int = -1


static func effective_viewing_player_id(game_state) -> int:
	if viewing_player_id_override >= 0:
		return viewing_player_id_override
	if game_state == null or game_state.turn_state == null:
		return 0
	return int(game_state.turn_state.current_player_id())


static func is_coord_explored_for_viewing_player(game_state, coord) -> bool:
	if game_state == null or coord == null:
		return true
	if game_state.turn_state == null or game_state.visibility_state == null:
		return true
	var pid: int = effective_viewing_player_id(game_state)
	return game_state.visibility_state.is_explored(pid, coord)


static func is_coord_explored_for_current_player(game_state, coord) -> bool:
	return is_coord_explored_for_viewing_player(game_state, coord)


static func should_draw_map_detail_for_current_player(game_state, coord) -> bool:
	return is_coord_explored_for_viewing_player(game_state, coord)
