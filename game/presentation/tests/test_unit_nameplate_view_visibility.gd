# Headless: godot --headless --path game -s res://presentation/tests/test_unit_nameplate_view_visibility.gd
extends SceneTree

const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
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
	var nu: int = base.peek_next_unit_id()
	var u_far = UnitScript.new(nu, 0, HexCoordScript.new(1, 0), "warrior")
	var units2: Array = base.units()
	var ulist: Array = []
	var i: int = 0
	while i < units2.size():
		ulist.append(units2[i])
		i += 1
	ulist.append(u_far)
	var scen = ScenarioScript.new(
		base.map,
		ulist,
		base.cities(),
		nu + 1,
		base.peek_next_city_id(),
		base.lightning_tree_hex
	)
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var rects_open = UnitNameplateViewScript.compute_all_nameplate_rects(scen, layout, cam, null, null)
	_check(rects_open.size() >= 1, "without game_state: nameplates present")
	var vis_min = PlayerVisibilityStateScript.empty_for_players(gs.turn_state.players)
	vis_min = vis_min.with_revealed(0, [HexCoordScript.new(0, 0)])
	gs.visibility_state = vis_min
	var rects_gated = UnitNameplateViewScript.compute_all_nameplate_rects(scen, layout, cam, null, gs)
	var n_at_far: int = 0
	var j: int = 0
	while j < scen.units().size():
		var uu = scen.units()[j]
		if uu.position.q == 1 and uu.position.r == 0 and int(uu.id) == nu:
			n_at_far += 1
		j += 1
	_check(n_at_far == 1, "fixture has warrior at (1,0)")
	_check(rects_gated.size() < rects_open.size(), "gating removes at least one nameplate")

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
