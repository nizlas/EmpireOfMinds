# Headless: godot --headless --path game -s res://domain/tests/test_settler_unlock_flow.gd
# Phase 5.1.12d — Train Settler is baseline; Controlled Fire does not unlock settler production.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")

var _total = 0
var _any_fail = false


func _has_settler_sp(L: Array) -> bool:
	var i = 0
	while i < L.size():
		var e = L[i] as Dictionary
		if e["action_type"] == SetCityProductionScript.ACTION_TYPE:
			if str(e["project_id"]) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER:
				return true
		i = i + 1
	return false


func _sp_block_for_city(L: Array, city_id: int) -> Array:
	var out: Array = []
	var i = 0
	while i < L.size():
		var e = L[i] as Dictionary
		if e["action_type"] == SetCityProductionScript.ACTION_TYPE and int(e["city_id"]) == city_id:
			out.append(e)
		i = i + 1
	return out


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler")]
	var city = CityScript.new(5, 0, HexCoordScript.new(1, -1), null)
	var sc = ScenarioScript.new(m, u, [city], 10, 20)
	var gs = GameStateScript.new(sc)

	_check(
		gs.progress_state.has_unlocked_target(0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"baseline settler unlock in progress_state"
	)

	var L0 = LegalActionsScript.for_current_player(gs)
	_check(_has_settler_sp(L0), "legal list includes settler from turn 1")
	var blk0 = _sp_block_for_city(L0, city.id)
	_check(blk0.size() == 2, "warrior and settler actions for empty city")
	_check(
		str((blk0[0] as Dictionary)["project_id"]) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR,
		"warrior first"
	)
	_check(
		str((blk0[1] as Dictionary)["project_id"]) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER,
		"settler second"
	)

	var pre_sp = SetCityProductionScript.make(
		0,
		city.id,
		SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER
	)
	var r_pre = gs.try_apply(pre_sp)
	_check(r_pre["accepted"], "settler production accepted without controlled_fire")

	var r_cp = gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	_check(r_cp["accepted"], "controlled_fire accepted")
	_check(
		gs.progress_state.has_unlocked_target(0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"settler remains available after CF"
	)
	_check(gs.progress_state.has_unlocked_target(0, "building", "hearth"), "cf unlocks hearth")
	var log_e = gs.log.get_entry(r_cp["index"]) as Dictionary
	var ut = log_e["unlocked_targets"] as Array
	var saw_settler_unlock = false
	var ui = 0
	while ui < ut.size():
		var row = ut[ui] as Dictionary
		if str(row["target_type"]) == "city_project" and str(row["target_id"]) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER:
			saw_settler_unlock = true
		ui = ui + 1
	_check(not saw_settler_unlock, "complete_progress log omits produce_unit:settler")

	var gs2 = GameStateScript.new(sc)
	var L1 = LegalActionsScript.for_current_player(gs2)
	var blk1 = _sp_block_for_city(L1, city.id)
	_check(blk1.size() == 2, "two sp before any science")

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
