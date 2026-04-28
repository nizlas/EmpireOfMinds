# Headless: godot --headless --path game -s res://domain/tests/test_set_city_production_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var us = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cs = [CityScript.new(1, 0, HexCoordScript.new(1, -1))]
	var scen = ScenarioScript.new(m, us, cs, 10, 50)
	var gs = GameStateScript.new(scen)

	var bad = gs.try_apply(SetCityProductionScript.make(1, 1, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT))
	_check(
		not bad["accepted"] and bad["reason"] == "not_current_player",
		"wrong player gated"
	)

	var r1 = gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT))
	_check(r1["accepted"], "produce accepted")
	var cty = gs.scenario.city_by_id(1)
	var pr = cty.current_project as Dictionary
	_check(
		pr["project_type"] == "produce_unit" and pr["progress"] == 0 and pr["cost"] == 2,
		"scenario city project"
	)
	_check(gs.scenario.unit_by_id(1) != null, "units preserved")

	_check(gs.log.size() == 1, "one log entry")
	var e0 = gs.log.get_entry(0)
	_check(e0["action_type"] == "set_city_production", "log action_type")
	_check(e0["actor_id"] == 0, "log actor")
	_check(e0["city_id"] == 1, "log city_id")
	_check(e0["project_type"] == SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT, "log project_type")
	_check(e0["result"] == "accepted", "log result")

	var r2 = gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT))
	_check(
		not r2["accepted"] and r2["reason"] == "project_already_set",
		"idempotent produce rejected"
	)

	var r3 = gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_TYPE_NONE))
	_check(r3["accepted"], "clear accepted")
	_check(gs.scenario.city_by_id(1).current_project == null, "cleared")

	var r4 = gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_TYPE_NONE))
	_check(
		not r4["accepted"] and r4["reason"] == "project_already_set",
		"idempotent none rejected"
	)

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
