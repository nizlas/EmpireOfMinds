# Headless: godot --headless --path game -s res://presentation/tests/test_tile_yield_overlay_view_visibility.gd
extends SceneTree

const TileYieldOverlayViewScript = preload("res://presentation/tile_yield_overlay_view.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _coord_in_entries(entries: Array, q: int, r: int) -> bool:
	var i: int = 0
	while i < entries.size():
		var d: Dictionary = entries[i] as Dictionary
		var c = d.get("coord", null)
		if c != null and (c as HexCoord).q == q and (c as HexCoord).r == r:
			return true
		i += 1
	return false


func _run() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var scen = gs.scenario
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var hex00 = HexCoordScript.new(0, 0)
	var hex10 = HexCoordScript.new(1, 0)
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [hex00])
	gs.visibility_state = vis_min
	var e_all = TileYieldOverlayViewScript.compute_overlay_entries(scen, layout, cam, null)
	_check(_coord_in_entries(e_all, 1, 0), "null game_state retains entries for (1,0)")
	var e_gated = TileYieldOverlayViewScript.compute_overlay_entries(scen, layout, cam, gs)
	_check(_coord_in_entries(e_gated, 0, 0), "gated: explored (0,0) still has yield entries")
	_check(not _coord_in_entries(e_gated, 1, 0), "gated: unexplored (1,0) omitted")

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
