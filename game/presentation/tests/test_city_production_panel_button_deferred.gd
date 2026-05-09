# Headless: godot --headless --path game -s res://presentation/tests/test_city_production_panel_button_deferred.gd
# Ensures production buttons are not cleared synchronously inside pressed handling (Godot locked-object error).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false

var _panel
var _gs
var _sel


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_panel = CityProductionPanelScript.new()
	get_root().add_child(_panel)
	_gs = GameStateScript.make_tiny_test_state()
	_check(_gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found city")
	_sel = SelectionStateScript.new()
	_sel.select_city(1)
	_panel.game_state = _gs
	_panel.selection = _sel
	_panel.refresh()
	var n_before = _panel._btn_container.get_child_count()
	_check(n_before >= 1, "warrior button exists before press")
	var act = SetCityProductionScript.make(
		0,
		1,
		SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
	)
	_panel._on_production_button_pressed(act)
	_check(
		_panel._btn_container.get_child_count() == n_before,
		"pressed handler does not rebuild children synchronously"
	)
	call_deferred("_after_idle")


func _after_idle() -> void:
	var cy = _gs.scenario.city_by_id(1)
	_check(cy != null and cy.current_project != null, "try_apply committed production")
	var vm = CityProductionPanelScript.compute_view_model(_gs, _sel)
	var stb = str(vm.get("status", ""))
	_check(stb.find("Producing") >= 0 or stb.find("/") >= 0, "deferred refresh updates busy status")
	if _panel != null:
		_panel.queue_free()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
