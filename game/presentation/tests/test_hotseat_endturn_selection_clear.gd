# Headless: godot --headless --path game -s res://presentation/tests/test_hotseat_endturn_selection_clear.gd
# Phase **5.2.1** — **`EndTurnController.apply_hotseat_clear_after_accepted_end_turn`** (presentation-only; no domain **`EndTurn`**).
extends SceneTree

class PanelStub extends RefCounted:
	var city_view_state = null
	var game_state = null
	var selection = null


const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const CityViewStateScript = preload("res://presentation/city_view_state.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sel_u = SelectionStateScript.new()
	sel_u.select(42)
	var panel_nil = PanelStub.new()
	EndTurnController.apply_hotseat_clear_after_accepted_end_turn(sel_u, panel_nil)
	_check(sel_u.unit_id == SelectionStateScript.NONE, "clear_unit: unit cleared")
	_check(not sel_u.has_city(), "clear_unit path: no city")

	var cvs = CityViewStateScript.new()
	cvs.enter_planning()
	var sel_c = SelectionStateScript.new()
	sel_c.select_city(7)
	var panel = PanelStub.new()
	panel.city_view_state = cvs
	EndTurnController.apply_hotseat_clear_after_accepted_end_turn(sel_c, panel)
	_check(not sel_c.has_city(), "city selection cleared")
	_check(not cvs.is_planning(), "planning exited to NORMAL")

	var gs = GameStateScript.make_tiny_test_state()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "founded city for vm check")
	var sel_g = SelectionStateScript.new()
	sel_g.select_city(1)
	var cvs_g = CityViewStateScript.new()
	cvs_g.enter_planning()
	var stub = PanelStub.new()
	stub.city_view_state = cvs_g
	EndTurnController.apply_hotseat_clear_after_accepted_end_turn(sel_g, stub)
	var vm = CityProductionPanelScript.compute_view_model(gs, sel_g, cvs_g)
	_check(not bool(vm.get("visible", true)), "compute_view_model hides hub without city selection")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message: String) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
