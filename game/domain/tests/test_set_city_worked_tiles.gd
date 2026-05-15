# Headless: godot --headless --path game -s res://domain/tests/test_set_city_worked_tiles.gd
extends SceneTree

const SetCityWorkedTilesScript = preload("res://domain/actions/set_city_worked_tiles.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _base_city_scen():
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var ctr = HexCoordScript.new(1, -1)
	var ring_a = HexCoordScript.new(0, -1)
	var ring_b = HexCoordScript.new(1, 0)
	var owned: Array = [ctr, ring_a, ring_b]
	var city = CityScript.new(5, 0, ctr, null, "", false, [], owned, 1)
	var scen = ScenarioScript.new(m, u, [city], 10, 20, null)
	return {"map": m, "units": u, "owned": owned, "ctr": ctr, "city": city, "scen": scen}


func _init() -> void:
	var B = _base_city_scen()
	var m = B["map"]
	var u = B["units"]
	var owned: Array = B["owned"]
	var ctr = B["ctr"]
	var city = B["city"]
	var scen: Variant = B["scen"]

	var a_ok = SetCityWorkedTilesScript.make(0, 5, [[0, -1]])
	var v_ok = SetCityWorkedTilesScript.validate(scen, a_ok)
	_check(bool(v_ok["ok"]), "happy path validates")
	var scen2 = SetCityWorkedTilesScript.apply(scen, a_ok)
	var c2 = scen2.city_by_id(5)
	_check(c2.manual_worked_tiles.size() == 1, "apply stores one manual hex")
	_check((c2.manual_worked_tiles[0] as HexCoord).q == 0 and (c2.manual_worked_tiles[0] as HexCoord).r == -1, "apply coord")

	var gs_b = GameStateScript.new(ScenarioScript.new(m, u, [city], 10, 20, null))
	var r1 = gs_b.try_apply(SetCityWorkedTilesScript.make(0, 5, [[0, -1]]))
	_check(r1["accepted"], "try_apply set manual")
	var r_clear = gs_b.try_apply(SetCityWorkedTilesScript.make(0, 5, []))
	_check(r_clear["accepted"], "clear-to-auto accepts")
	_check(gs_b.scenario.city_by_id(5).manual_worked_tiles.is_empty(), "manual cleared")

	var bad_scen = SetCityWorkedTilesScript.validate(null, a_ok)
	_check(bad_scen["reason"] == "scenario_null", "scenario_null")

	var bad_type = SetCityWorkedTilesScript.validate(scen, {"action_type": "nope"})
	_check(bad_type["reason"] == "wrong_action_type", "wrong_action_type")

	var bad_ver = SetCityWorkedTilesScript.validate(
		scen,
		{
			"schema_version": 99,
			"action_type": SetCityWorkedTilesScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
			"tiles": [],
		}
	)
	_check(bad_ver["reason"] == "unsupported_schema_version", "unsupported_schema_version")

	var bad_mal = SetCityWorkedTilesScript.validate(
		scen,
		{
			"schema_version": SetCityWorkedTilesScript.SCHEMA_VERSION,
			"action_type": SetCityWorkedTilesScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
		}
	)
	_check(bad_mal["reason"] == "malformed_action", "malformed missing tiles")

	var uk = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(0, 999, [[0, -1]]))
	_check(uk["reason"] == "unknown_city", "unknown_city")

	var no_own = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(1, 5, [[0, -1]]))
	_check(no_own["reason"] == "actor_not_owner", "actor_not_owner")

	var mal_tiles = SetCityWorkedTilesScript.validate(
		scen,
		{
			"schema_version": SetCityWorkedTilesScript.SCHEMA_VERSION,
			"action_type": SetCityWorkedTilesScript.ACTION_TYPE,
			"actor_id": 0,
			"city_id": 5,
			"tiles": "broken",
		}
	)
	_check(mal_tiles["reason"] == "malformed_action", "malformed tiles type")

	var mal_pair = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(0, 5, [[0]]))
	_check(mal_pair["reason"] == "malformed_action", "malformed pair size")

	var not_owned = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(0, 5, [[-1, 1]]))
	_check(not_owned["reason"] == "tile_not_owned", "tile_not_owned")

	var center_bad = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(0, 5, [[1, -1]]))
	_check(center_bad["reason"] == "tile_is_center", "tile_is_center")

	var c_water = CityScript.new(
		6,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		[],
		[HexCoordScript.new(0, 0), HexCoordScript.new(-1, 0)],
		2
	)
	var scen_w = ScenarioScript.new(m, u, [c_water], 11, 21, null)
	var zy = SetCityWorkedTilesScript.validate(scen_w, SetCityWorkedTilesScript.make(0, 6, [[-1, 0]]))
	_check(zy["reason"] == "tile_zero_yield", "tile_zero_yield")

	var scen_dups = ScenarioScript.new(m, u, [CityScript.new(5, 0, ctr, null, "", false, [], owned, 2)], 10, 20, null)
	var dup = SetCityWorkedTilesScript.validate(scen_dups, SetCityWorkedTilesScript.make(0, 5, [[0, -1], [0, -1]]))
	_check(dup["reason"] == "duplicate_tile", "duplicate_tile")

	var c_two_pop1 = CityScript.new(7, 0, ctr, null, "", false, [], owned, 1)
	var scen_one = ScenarioScript.new(m, u, [c_two_pop1], 12, 22, null)
	var too = SetCityWorkedTilesScript.validate(
		scen_one,
		SetCityWorkedTilesScript.make(0, 7, [[0, -1], [1, 0]])
	)
	_check(too["reason"] == "too_many_tiles", "too_many_tiles")

	var same = SetCityWorkedTilesScript.validate(scen, SetCityWorkedTilesScript.make(0, 5, []))
	_check(same["reason"] == "assignment_unchanged", "assignment_unchanged empty to empty")

	var city_m = CityScript.new(8, 0, ctr, null, "", false, [], owned, 1, [HexCoordScript.new(0, -1)])
	var scen_m = ScenarioScript.new(m, u, [city_m], 13, 23, null)
	var unch = SetCityWorkedTilesScript.validate(scen_m, SetCityWorkedTilesScript.make(0, 8, [[0, -1]]))
	_check(unch["reason"] == "assignment_unchanged", "assignment_unchanged same manual")

	var gs_wrong = GameStateScript.new(scen)
	var bad_actor = gs_wrong.try_apply(SetCityWorkedTilesScript.make(1, 5, [[0, -1]]))
	_check(not bad_actor["accepted"] and str(bad_actor["reason"]) == "not_current_player", "try_apply rejects wrong actor")

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
