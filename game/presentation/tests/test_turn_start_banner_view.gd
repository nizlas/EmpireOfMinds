# Headless: Phase **5.2.6** — turn-start banner visibility, copy, dismissal.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnStartBannerViewScript = preload("res://presentation/turn_start_banner_view.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var banner = TurnStartBannerViewScript.new()
	get_root().add_child(banner)
	var gs = GameStateScript.make_tiny_test_state()
	banner.set_game_state(gs)
	banner.show_for_current_player(gs)
	_check(banner.is_visible_banner(), "visible after show opening")
	_check(
		banner.debug_banner_line() == "Your turn, Västerviksjävlarna",
		"copy names playtest P0",
	)
	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end turn")
	banner.show_for_current_player(gs)
	_check(banner.is_visible_banner(), "visible after end turn for next player")
	_check(
		banner.debug_banner_line() == "Your turn, Malmöfubikkarna",
		"copy names playtest P1",
	)
	banner.dismiss()
	_check(not banner.is_visible_banner(), "dismiss hides")
	var evk := InputEventKey.new()
	evk.keycode = KEY_A
	evk.pressed = true
	banner.show_for_current_player(gs)
	banner.on_user_interaction(evk)
	_check(not banner.is_visible_banner(), "first key interaction dismisses")
	var mm := InputEventMouseMotion.new()
	_check(
		not TurnStartBannerViewScript.should_dismiss_for_event_static(mm),
		"plain motion does not dismiss",
	)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	banner.show_for_current_player(gs)
	banner.on_user_interaction(mb)
	_check(not banner.is_visible_banner(), "mouse click dismisses")
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
