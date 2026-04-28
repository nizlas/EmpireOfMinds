# Headless: godot --headless --path game -s res://domain/tests/test_set_city_production.gd
extends SceneTree

const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _make_scenario_with_cities():
	var m = HexMapScript.make_tiny_test_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0)),
	]
	var cs = [
		CityScript.new(5, 0, HexCoordScript.new(0, -1)),
		CityScript.new(6, 0, HexCoordScript.new(1, -1)),
	]
	return ScenarioScript.new(m, us, cs, 100, 200)


func _init() -> void:
	var sc = _make_scenario_with_cities()
	var mk = SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	_check(mk["schema_version"] == SetCityProductionScript.SCHEMA_VERSION, "make schema")
	_check(mk["action_type"] == SetCityProductionScript.ACTION_TYPE, "make action_type")
	_check(mk["actor_id"] == 0 and mk["city_id"] == 5, "make ids")
	_check(mk["project_type"] == SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT, "make project_type")

	var r0 = SetCityProductionScript.validate(null, mk)
	_check(not r0["ok"] and r0["reason"] == "scenario_null", "scenario_null")
	var r1 = SetCityProductionScript.validate(sc, null)
	_check(not r1["ok"] and r1["reason"] == "wrong_action_type", "null action")
	var r1b = SetCityProductionScript.validate(sc, "x")
	_check(not r1b["ok"] and r1b["reason"] == "wrong_action_type", "not dict")
	var r2 = SetCityProductionScript.validate(sc, {"foo": 1})
	_check(not r2["ok"] and r2["reason"] == "wrong_action_type", "missing action_type")
	var r3 = SetCityProductionScript.validate(sc, {"action_type": "move_unit"})
	_check(not r3["ok"] and r3["reason"] == "wrong_action_type", "wrong action_type")
	var r4 = SetCityProductionScript.validate(sc, {"action_type": SetCityProductionScript.ACTION_TYPE})
	_check(
		not r4["ok"] and r4["reason"] == "unsupported_schema_version",
		"no schema"
	)
	var r5 = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": 99,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
			"project_type": SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT,
		}
	)
	_check(
		not r5["ok"] and r5["reason"] == "unsupported_schema_version",
		"bad schema"
	)
	var r6 = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"city_id": 5,
			"project_type": SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT,
		}
	)
	_check(not r6["ok"] and r6["reason"] == "malformed_action", "missing actor_id")
	var r6b = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": "n",
			"city_id": 5,
			"project_type": SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT,
		}
	)
	_check(not r6b["ok"] and r6b["reason"] == "malformed_action", "actor_id not int")
	var r7 = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": 0,
			"project_type": SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT,
		}
	)
	_check(not r7["ok"] and r7["reason"] == "malformed_action", "missing city_id")
	var r7b = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5.5,
			"project_type": SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT,
		}
	)
	_check(not r7b["ok"] and r7b["reason"] == "malformed_action", "city_id not int")
	var r8 = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
		}
	)
	_check(not r8["ok"] and r8["reason"] == "malformed_action", "missing project_type")
	var r8b = SetCityProductionScript.validate(
		sc,
		{
			"schema_version": SetCityProductionScript.SCHEMA_VERSION,
			"action_type": SetCityProductionScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
			"project_type": 1,
		}
	)
	_check(not r8b["ok"] and r8b["reason"] == "malformed_action", "project_type not string")
	var r9 = SetCityProductionScript.validate(
		sc,
		SetCityProductionScript.make(0, 999, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	_check(not r9["ok"] and r9["reason"] == "unknown_city", "unknown_city")
	var r10 = SetCityProductionScript.validate(
		sc,
		SetCityProductionScript.make(1, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	_check(not r10["ok"] and r10["reason"] == "actor_not_owner", "actor_not_owner")
	var r11 = SetCityProductionScript.validate(
		sc,
		SetCityProductionScript.make(0, 5, "nexus_gate")
	)
	_check(not r11["ok"] and r11["reason"] == "unsupported_project_type", "unsupported type")

	var sc_busy = _make_scenario_with_cities()
	var busy1 = SetCityProductionScript.apply(
		sc_busy,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	var r12 = SetCityProductionScript.validate(
		busy1,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	_check(not r12["ok"] and r12["reason"] == "project_already_set", "produce twice")
	var r13 = SetCityProductionScript.validate(
		sc,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_NONE)
	)
	_check(not r13["ok"] and r13["reason"] == "project_already_set", "none when empty")

	var ok = SetCityProductionScript.validate(
		sc,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	_check(ok["ok"], "legal produce validate")
	var ok_clear = SetCityProductionScript.validate(
		busy1,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_NONE)
	)
	_check(ok_clear["ok"], "legal none after produce")

	var before_nu = sc.peek_next_unit_id()
	var before_nc = sc.peek_next_city_id()
	var nu_before = sc.units().size()
	var c5_before = sc.city_by_id(5)
	var new_sc = SetCityProductionScript.apply(
		sc,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_PRODUCE_UNIT)
	)
	var c5n = new_sc.city_by_id(5)
	_check(c5n != null and c5n.current_project != null, "has project")
	var pr = c5n.current_project as Dictionary
	_check(
		pr["project_type"] == "produce_unit" and pr["progress"] == 0 and pr["cost"] == 2,
		"produce shape"
	)
	_check(new_sc.city_by_id(6) == sc.city_by_id(6), "other city same ref")
	_check(new_sc.peek_next_unit_id() == before_nu and new_sc.peek_next_city_id() == before_nc, "peek preserved")
	_check(new_sc.units().size() == nu_before, "unit count")
	_check(c5_before.current_project == null, "orig city untouched")

	var cleared = SetCityProductionScript.apply(
		new_sc,
		SetCityProductionScript.make(0, 5, SetCityProductionScript.PROJECT_TYPE_NONE)
	)
	_check(cleared.city_by_id(5).current_project == null, "none clears")

	var ext: Dictionary = {}
	ext["project_type"] = "produce_unit"
	ext["progress"] = 0
	ext["cost"] = 2
	var ciso = CityScript.new(7, 0, HexCoordScript.new(0, 0), ext)
	ext["progress"] = 99
	var cpiso = ciso.current_project as Dictionary
	_check(cpiso["progress"] == 0, "city stores deep copy")

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
