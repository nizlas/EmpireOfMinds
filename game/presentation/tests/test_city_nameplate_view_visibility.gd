# Headless: godot --headless --path game -s res://presentation/tests/test_city_nameplate_view_visibility.gd
extends SceneTree

const CityNameplateViewScript = preload("res://presentation/city_nameplate_view.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var base = gs.scenario
	var scen = ScenarioScript.new(
		base.map,
		base.units(),
		[CityScript.new(1, 0, HexCoordScript.new(1, 0), null, "Hiddenburg")],
		base.peek_next_unit_id(),
		2,
		base.lightning_tree_hex
	)
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var rects_open = CityNameplateViewScript.compute_all_city_banner_rects(scen, layout, cam, null, false, null)
	_check(rects_open.size() == 1, "without game_state: one banner rect")
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [HexCoordScript.new(0, 0)])
	gs.visibility_state = vis_min
	var rects_gated = CityNameplateViewScript.compute_all_city_banner_rects(scen, layout, cam, null, false, gs)
	_check(rects_gated.is_empty(), "city on unexplored hex => no rects")

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
