# Headless: cloud turn-start banner only on player change (not every snapshot refresh).
# Usage: godot --headless --path game -s res://cloud/tests/test_cloud_turn_banner.gd
extends SceneTree

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const TurnStartBannerViewScript = preload("res://presentation/turn_start_banner_view.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	_check(
		CloudClientScript.should_show_turn_start_banner(null, 0),
		"initial bootstrap shows banner for opening player",
	)
	_check(
		not CloudClientScript.should_show_turn_start_banner(0, 0),
		"same player after move_unit does not show banner",
	)
	_check(
		not CloudClientScript.should_show_turn_start_banner(1, 1),
		"same player after found_city does not show banner",
	)
	_check(
		CloudClientScript.should_show_turn_start_banner(0, 1),
		"end_turn player change shows banner",
	)
	_check(
		not CloudClientScript.should_show_turn_start_banner(0, -1),
		"invalid new player id never shows banner",
	)
	var gs = GameStateScript.make_tiny_test_state()
	var banner = TurnStartBannerViewScript.new()
	get_root().add_child(banner)
	banner.set_game_state(gs)
	banner.dismiss()
	_check(not banner.is_visible_banner(), "banner starts hidden for sim")
	if CloudClientScript.should_show_turn_start_banner(0, 0):
		banner.show_for_current_player(gs)
	_check(not banner.is_visible_banner(), "same-player gate prevents show after move_unit sim")
	if CloudClientScript.should_show_turn_start_banner(0, 1):
		banner.show_for_current_player(gs)
	_check(banner.is_visible_banner(), "player-change gate allows show after end_turn sim")
	gs.try_apply(EndTurnScript.make(0))
	if CloudClientScript.should_show_turn_start_banner(0, int(gs.turn_state.current_player_id())):
		banner.show_for_current_player(gs)
	_check(
		banner.is_visible_banner() and int(gs.turn_state.current_player_id()) == 1,
		"end_turn in tiny state advances player and banner can show",
	)
	banner.dismiss()
	if CloudClientScript.should_show_turn_start_banner(0, 0):
		banner.show_for_current_player(gs)
	_check(
		not CloudClientScript.should_show_turn_start_banner(0, 0),
		"rejected/no-op same player still false after end_turn back sim",
	)
	_check(str(MoveUnitScript.ACTION_TYPE) == "move_unit", "move_unit type unchanged (no server payload edits)")
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
