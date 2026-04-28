# Headless: godot --headless --path game -s res://domain/tests/test_end_turn_production_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")

var _total = 0
var _any_fail = false


func _proj(p: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = 2
	return d


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var us = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var c_p0 = CityScript.new(1, 0, HexCoordScript.new(1, -1), _proj(0))
	var c_p1 = CityScript.new(2, 1, HexCoordScript.new(0, -1), _proj(0))
	var scen = ScenarioScript.new(m, us, [c_p1, c_p0], 30, 40)
	var gs = GameStateScript.new(scen)

	var et0 = gs.try_apply(EndTurnScript.make(0))
	_check(et0["accepted"] and et0["index"] == 1, "end turn index is last entry")
	_check(gs.log.size() == 2, "progress + end_turn")
	var lg0 = gs.log.get_entry(0) as Dictionary
	var lg1 = gs.log.get_entry(1) as Dictionary
	_check(lg0["action_type"] == ProductionTickScript.EVENT_TYPE and lg0["city_id"] == 1, "first is production c1")
	_check(lg1["action_type"] == EndTurnScript.ACTION_TYPE, "second is end_turn")
	_check(gs.scenario.city_by_id(1).current_project["progress"] == 1, "p0 city ticked")
	_check(gs.scenario.city_by_id(2).current_project["progress"] == 0, "p1 city not ticked")

	var et1 = gs.try_apply(EndTurnScript.make(1))
	_check(et1["accepted"] and et1["index"] == 3, "second cycle end index")
	_check(gs.log.size() == 4, "two more entries")
	_check(gs.log.get_entry(2)["city_id"] == 2, "p1 production")
	_check(gs.log.get_entry(3)["action_type"] == EndTurnScript.ACTION_TYPE, "end_turn follows")

	var et2 = gs.try_apply(EndTurnScript.make(0))
	_check(et2["accepted"], "p0 end again")
	_check(gs.scenario.city_by_id(1).current_project["progress"] == 2, "p0 second tick")

	var m2 = HexMapScript.make_tiny_test_map()
	var us2 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var ca = CityScript.new(5, 0, HexCoordScript.new(1, 0), _proj(0))
	var cb = CityScript.new(1, 0, HexCoordScript.new(1, -1), _proj(0))
	var sc2 = ScenarioScript.new(m2, us2, [ca, cb], 11, 22)
	var gs2 = GameStateScript.new(sc2)
	var etx = gs2.try_apply(EndTurnScript.make(0))
	_check(etx["index"] == 2, "two progress one end")
	var g0 = gs2.log.get_entry(0) as Dictionary
	var g1 = gs2.log.get_entry(1) as Dictionary
	_check(g0["city_id"] == 1 and g1["city_id"] == 5, "production order by id")

	var bad = gs2.try_apply(EndTurnScript.make(0))
	_check(not bad["accepted"] and bad["reason"] == "not_current_player", "wrong player no tick")
	var sz = gs2.log.size()
	_check(sz == 3, "no log on reject")

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
