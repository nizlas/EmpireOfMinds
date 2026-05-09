# Headless: godot --headless --path game -s res://domain/tests/test_settler_production_flow.gd
# Phase 5.1.3: proof-only — existing ProductionTick / ProductionDelivery + try_apply; no production code changes.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _last_production_progress_for_city(gs, city_id: int):
	var n = gs.log.size()
	var i = n - 1
	while i >= 0:
		var e = gs.log.get_entry(i) as Dictionary
		if str(e.get("action_type", "")) == ProductionTickScript.EVENT_TYPE and int(e.get("city_id", -1)) == city_id:
			return e
		i = i - 1
	return null


func _has_unit_produced_for(gs, unit_id: int, city_id: int) -> bool:
	var n = gs.log.size()
	var j = 0
	while j < n:
		var e = gs.log.get_entry(j) as Dictionary
		if (
			str(e.get("action_type", "")) == ProductionDeliveryScript.EVENT_TYPE
			and int(e.get("unit_id", -1)) == unit_id
			and int(e.get("city_id", -1)) == city_id
		):
			return true
		j = j + 1
	return false


func _init() -> void:
	_check(SetCityProductionScript.SCHEMA_VERSION == 2, "set_city_production schema unchanged")
	_check(CompleteProgressScript.SCHEMA_VERSION == 1, "complete_progress schema unchanged")

	var gs = GameStateScript.make_tiny_test_state()
	var city_id = gs.scenario.peek_next_city_id()
	var expected_settler_unit_id = gs.scenario.peek_next_unit_id()
	_check(city_id == 1 and expected_settler_unit_id == 4, "canonical tiny_test next ids")

	var r_fc = gs.try_apply(FoundCityScript.make(0, 1, 0, 0))
	_check(r_fc["accepted"], "found first city")
	var city_a = gs.scenario.city_by_id(city_id)
	_check(city_a != null and city_a.owner_id == 0, "city A owner")
	_check(city_a.position.equals(HexCoordScript.new(0, 0)), "city A at 0,0")
	_check(gs.scenario.unit_by_id(1) == null, "founder consumed")

	var r_cp = gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(r_cp["accepted"], "controlled_fire complete")
	_check(
		gs.progress_state.has_unlocked_target(0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"settler project unlocked"
	)

	var r_sp = gs.try_apply(
		SetCityProductionScript.make(0, city_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER)
	)
	_check(r_sp["accepted"], "set settler production")
	var pr_a = (gs.scenario.city_by_id(city_id).current_project as Dictionary)
	_check(str(pr_a["project_type"]) == "produce_unit", "project type")
	_check(str(pr_a["project_id"]) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER, "project id")
	_check(int(pr_a["progress"]) == 0 and int(pr_a["cost"]) == 2 and pr_a.get("ready", false) == false, "initial progress")

	var et1 = gs.try_apply(EndTurnScript.make(0))
	_check(et1["accepted"], "end turn P0 first")
	var pp1 = _last_production_progress_for_city(gs, city_id)
	_check(pp1 != null, "tick after et1 present")
	_check(int((pp1 as Dictionary)["progress_after"]) == 1, "tick 0 to 1")
	_check(
		bool((gs.scenario.city_by_id(city_id).current_project as Dictionary).get("ready", false)) == false,
		"not ready after one tick"
	)
	_check(gs.scenario.unit_by_id(expected_settler_unit_id) == null, "no delivery yet")

	var et2 = gs.try_apply(EndTurnScript.make(1))
	_check(et2["accepted"], "end turn P1 first")
	_check(int((gs.scenario.city_by_id(city_id).current_project as Dictionary)["progress"]) == 1, "P1 turn no P0 tick")
	_check(not _has_unit_produced_for(gs, expected_settler_unit_id, city_id), "still no unit_produced")

	var et3 = gs.try_apply(EndTurnScript.make(0))
	_check(et3["accepted"], "end turn P0 second")
	var pp3 = _last_production_progress_for_city(gs, city_id)
	_check(pp3 != null, "tick after et3 present")
	_check(int((pp3 as Dictionary)["progress_after"]) == 2, "tick 1 to 2")
	_check(
		bool((gs.scenario.city_by_id(city_id).current_project as Dictionary).get("ready", false)),
		"ready pending delivery"
	)
	_check(gs.scenario.unit_by_id(expected_settler_unit_id) == null, "delivery when P0 next current")

	var et4 = gs.try_apply(EndTurnScript.make(1))
	_check(et4["accepted"], "end turn P1 second")
	_check(gs.scenario.city_by_id(city_id).current_project == null, "city project cleared after delivery")
	_check(_has_unit_produced_for(gs, expected_settler_unit_id, city_id), "unit_produced logged")
	_check(gs.scenario.peek_next_unit_id() == expected_settler_unit_id + 1, "next unit id bumped")

	var u_new = gs.scenario.unit_by_id(expected_settler_unit_id)
	_check(u_new != null, "delivered unit exists")
	_check(u_new.owner_id == 0 and u_new.type_id == "settler", "settler owner and type")
	_check(u_new.position.equals(HexCoordScript.new(0, 0)), "delivered at city A hex")

	var r_mv = gs.try_apply(MoveUnitScript.make(0, expected_settler_unit_id, 0, 0, 1, -1))
	_check(r_mv["accepted"], "move settler to 1,-1")
	var u_m = gs.scenario.unit_by_id(expected_settler_unit_id)
	_check(u_m != null and u_m.position.equals(HexCoordScript.new(1, -1)), "settler moved")

	var r_fc2 = gs.try_apply(FoundCityScript.make(0, expected_settler_unit_id, 1, -1))
	_check(r_fc2["accepted"], "found second city")
	_check(gs.scenario.cities_owned_by(0).size() == 2, "P0 owns two cities")
	_check(gs.scenario.unit_by_id(expected_settler_unit_id) == null, "settler consumed founding")
	_check(gs.scenario.city_by_id(city_id).current_project == null, "original city still no project")

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
