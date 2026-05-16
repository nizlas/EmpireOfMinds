# Headless: godot --headless --path game -s res://presentation/tests/test_terrain_foreground_view_visibility.gd
extends SceneTree

const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tfv = TerrainForegroundViewScript.new()
	var gs = GameStateScript.make_tiny_test_state()
	var hex00 = HexCoordScript.new(0, 0)
	var hex10 = HexCoordScript.new(1, 0)
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [hex00])
	gs.visibility_state = vis_min
	tfv.game_state = gs
	tfv.map = gs.scenario.map
	_check(tfv._should_draw_decoration_for_coord(hex00), "explored hex => decoration allowed")
	_check(not tfv._should_draw_decoration_for_coord(hex10), "unexplored hex => decoration gated")
	tfv.game_state = null
	_check(tfv._should_draw_decoration_for_coord(hex10), "null game_state => no gate (draw)")

	if _any_fail:
		tfv.free()
		call_deferred("quit", 1)
	else:
		tfv.free()
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
