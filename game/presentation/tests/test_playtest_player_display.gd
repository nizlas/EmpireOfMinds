# Headless: Phase **5.2.6a** — prototype seat **display** names from **`FactionDefinitions`** debug rows.
extends SceneTree

const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnStartBannerViewScript = preload("res://presentation/turn_start_banner_view.gd")

const NAME_0: String = "Västerviksjävlarna"
const NAME_1: String = "Malmöfubikkarna"

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(0) == NAME_0,
		"P0 display is Västerviksjävlarna",
	)
	_check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(1) == NAME_1,
		"P1 display is Malmöfubikkarna",
	)
	_check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(2) == "Player 2",
		"unknown id stays numeric fallback",
	)
	var gs = GameStateScript.make_tiny_test_state()
	_check(int(gs.turn_state.current_player_id()) == 0, "domain id 0 unchanged")
	var banner = TurnStartBannerViewScript.new()
	get_root().add_child(banner)
	banner.show_for_current_player(gs)
	_check(
		banner.debug_banner_line() == "Your turn, %s" % NAME_0,
		"banner P0",
	)
	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end turn")
	_check(gs.turn_state.current_player_id() == 1, "domain id 1 unchanged")
	banner.show_for_current_player(gs)
	_check(
		banner.debug_banner_line() == "Your turn, %s" % NAME_1,
		"banner P1",
	)
	banner.queue_free()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
