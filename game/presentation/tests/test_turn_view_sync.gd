# Headless: godot --headless --path game -s res://presentation/tests/test_turn_view_sync.gd
extends SceneTree

const TurnViewSyncScript = preload("res://presentation/turn_view_sync.gd")
const GameStateScript = preload("res://domain/game_state.gd")


class ScenarioViewStub extends Node:
	var redraws := 0
	var _scenario = null

	var scenario:
		get:
			return _scenario
		set(value):
			_scenario = value

	func queue_redraw() -> void:
		redraws += 1


class TerrainViewStub extends ScenarioViewStub:
	var map_writes := 0
	var _map_ref = null

	var map:
		get:
			return _map_ref
		set(value):
			_map_ref = value
			map_writes += 1


class RefreshStub extends Node:
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1


var _total := 0
var _any_fail := false


func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var scen = gs.scenario
	_check(scen != null, "scenario from tiny GameState")

	## sync_terrain_related_views
	var tf = TerrainViewStub.new()
	var un = ScenarioViewStub.new()
	var cn = ScenarioViewStub.new()
	var yo = ScenarioViewStub.new()
	var ct = ScenarioViewStub.new()
	var eb = ScenarioViewStub.new()
	TurnViewSyncScript.sync_terrain_related_views(scen, tf, un, cn, yo, ct, null, eb)
	_check(tf.map_writes == 1, "terrain map assignment once")
	_check(tf.redraws == 1 and un.redraws == 1 and cn.redraws == 1, "terrain+name redraws once each")
	_check(yo.redraws == 1 and ct.redraws == 1 and eb.redraws == 1, "yield+territory+empire redraw once")

	## refresh_map_views_and_hud_after_try_apply_turn_controllers
	var sel = ScenarioViewStub.new()
	var uv = ScenarioViewStub.new()
	var tl = RefreshStub.new()
	var lv = RefreshStub.new()
	var cpp = RefreshStub.new()
	var dap = RefreshStub.new()
	var sp = RefreshStub.new()

	var tf2 = TerrainViewStub.new()
	var unp2 = ScenarioViewStub.new()
	var cnp2 = ScenarioViewStub.new()
	var yov2 = ScenarioViewStub.new()
	var ctv2 = ScenarioViewStub.new()
	var eb2 = ScenarioViewStub.new()

	TurnViewSyncScript.refresh_map_views_and_hud_after_try_apply_turn_controllers(
		gs,
		sel,
		uv,
		tf2,
		unp2,
		cnp2,
		yov2,
		ctv2,
		tl,
		lv,
		cpp,
		dap,
		sp,
		null,
		eb2,
	)
	_check(sel.scenario == scen and uv.scenario == scen, "selection/units wired to scenario")
	_check(sel.redraws == 1 and uv.redraws == 1, "selection/units redraw once")
	_check(tf2.map_writes == 1 and tf2.redraws == 1, "turn-style terrain assign+redraw")
	_check(
		unp2.redraws == 1 and cnp2.redraws == 1 and yov2.redraws == 1 and ctv2.redraws == 1 and eb2.redraws == 1,
		"each overlay-style view redraw once (incl empire)"
	)
	_check(tl.refreshes == 1 and lv.refreshes == 1, "turn label + log refresh once")
	_check(cpp.refreshes == 1 and dap.refreshes == 1 and sp.refreshes == 1, "HUD panels refreshed once")

	var redraw_tot: int = (
		sel.redraws
		+ uv.redraws
		+ tf2.redraws
		+ unp2.redraws
		+ cnp2.redraws
		+ yov2.redraws
		+ ctv2.redraws
		+ eb2.redraws
	)
	TurnViewSyncScript.refresh_map_views_and_hud_after_try_apply_turn_controllers(
		null,
		sel,
		uv,
		tf2,
		unp2,
		cnp2,
		yov2,
		ctv2,
		tl,
		lv,
		cpp,
		dap,
		sp,
		null,
		eb2,
	)
	var redraw_after: int = (
		sel.redraws
			+ uv.redraws
			+ tf2.redraws
			+ unp2.redraws
			+ cnp2.redraws
			+ yov2.redraws
			+ ctv2.redraws
			+ eb2.redraws
	)
	_check(redraw_after == redraw_tot, "null GameState skips all view redraws")

	for n in [tf, un, cn, yo, ct, eb, sel, uv, tl, lv, cpp, dap, sp, tf2, unp2, cnp2, yov2, ctv2, eb2]:
		if is_instance_valid(n) and n is Node:
			n.free()

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
