# Debug label text derived from GameState.turn_state. No input.
# See docs/RENDERING.md, docs/TURNS.md
extends Label

const GameStateScript = preload("res://domain/game_state.gd")

var game_state

## Optional chain after **`refresh()`** (e.g. **`TurnStatusPanel`**) — avoids duplicating refresh calls across HUD.
var after_refresh: Callable = Callable()

static func compute_text(a_game_state) -> String:
	if a_game_state == null:
		return ""
	var ts = a_game_state.turn_state
	return "Turn %d — Player %d" % [ts.turn_number, ts.current_player_id()]

func refresh() -> void:
	text = compute_text(game_state)
	if after_refresh.is_valid():
		after_refresh.call()
