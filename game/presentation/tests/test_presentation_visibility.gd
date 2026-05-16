# Headless: godot --headless --path game -s res://presentation/tests/test_presentation_visibility.gd
extends SceneTree

const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hex00 = HexCoordScript.new(0, 0)
	var hex10 = HexCoordScript.new(1, 0)
	_check(
		PresentationVisibilityScript.is_coord_explored_for_current_player(null, hex00),
		"null game_state => explored true (preserve draw)"
	)
	var gs0 = GameStateScript.make_tiny_test_state()
	gs0.visibility_state = null
	_check(
		PresentationVisibilityScript.should_draw_map_detail_for_current_player(gs0, hex10),
		"null visibility_state => draw detail"
	)
	var gs = GameStateScript.make_tiny_test_state()
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [hex00])
	gs.visibility_state = vis_min
	_check(int(gs.turn_state.current_player_id()) == 0, "starts P0")
	_check(
		PresentationVisibilityScript.is_coord_explored_for_current_player(gs, hex00),
		"P0 explored (0,0)"
	)
	_check(
		not PresentationVisibilityScript.is_coord_explored_for_current_player(gs, hex10),
		"P0 not explored (1,0) in minimal vis"
	)
	_check(
		PresentationVisibilityScript.should_draw_map_detail_for_current_player(gs, hex00),
		"draw detail on explored"
	)
	_check(
		not PresentationVisibilityScript.should_draw_map_detail_for_current_player(gs, hex10),
		"omit detail on unexplored"
	)
	gs.turn_state = gs.turn_state.advance()
	_check(int(gs.turn_state.current_player_id()) == 1, "advance to P1 without domain visibility refresh")
	_check(
		not PresentationVisibilityScript.is_coord_explored_for_current_player(gs, hex00),
		"P1 minimal vis: (0,0) not explored"
	)
	_check(
		not PresentationVisibilityScript.is_coord_explored_for_current_player(gs, hex10),
		"P1 minimal vis: (1,0) not explored"
	)

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
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
