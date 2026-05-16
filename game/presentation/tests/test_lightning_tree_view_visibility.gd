# Headless: godot --headless --path game -s res://presentation/tests/test_lightning_tree_view_visibility.gd
extends SceneTree

const LightningTreeViewScript = preload("res://presentation/lightning_tree_view.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
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
	LightningTreeViewScript.debug_clear_stump_texture_cache()
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var tiny = ScenarioScript.make_tiny_test_scenario()
	var tree_hex = HexCoordScript.new(1, 0)
	var scen_tree = ScenarioScript.new(
		tiny.map,
		tiny.units(),
		tiny.cities(),
		tiny.peek_next_unit_id(),
		tiny.peek_next_city_id(),
		tree_hex
	)
	var gs = GameStateScript.make_tiny_test_state()
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [HexCoordScript.new(0, 0)])
	gs.visibility_state = vis_min
	_check(
		PresentationVisibilityScript.should_draw_map_detail_for_current_player(gs, HexCoordScript.new(0, 0)),
		"explored center allows detail"
	)
	_check(
		not PresentationVisibilityScript.should_draw_map_detail_for_current_player(gs, tree_hex),
		"tree hex (1,0) unexplored in minimal vis — gate predicate"
	)
	var lv = LightningTreeViewScript.new()
	lv.layout = layout
	lv.camera = cam
	lv.scenario = scen_tree
	lv.game_state = gs
	lv.draw_fallback_shape_when_texture_missing = true
	get_root().add_child(lv)
	lv.queue_redraw()
	_check(true, "lightning tree view instantiates with visibility-gated game_state")

	if _any_fail:
		lv.queue_free()
		call_deferred("quit", 1)
	else:
		lv.queue_free()
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
