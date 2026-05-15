# Headless: godot --headless --path game -s res://domain/tests/test_food_growth_tick.gd
extends SceneTree

const FoodGrowthTickScript = preload("res://domain/food_growth_tick.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _proj_stub() -> Dictionary:
	return {
		"project_type": "produce_unit",
		"project_id": "produce_unit:warrior",
		"progress": 0,
		"cost": 10,
		"ready": false,
	}


func _city_pair_scenario():
	# Two disjoint 2-hex footprints on **make_tiny_test_map**; pop 1 → 3 food each → surplus 1.
	var m = HexMapScript.make_tiny_test_map()
	var o1: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)]
	var o2: Array = [HexCoordScript.new(1, -1), HexCoordScript.new(0, -1)]
	var c2 = CityScript.new(
		2,
		0,
		HexCoordScript.new(1, -1),
		_proj_stub(),
		"B",
		false,
		["palace"],
		o2,
		1,
		[],
		0
	)
	var c1 = CityScript.new(
		1,
		0,
		HexCoordScript.new(0, 0),
		_proj_stub(),
		"A",
		true,
		["palace"],
		o1,
		1,
		[],
		0
	)
	return ScenarioScript.new(m, [], [c2, c1], 5, 9, null)


func _init() -> void:
	_check(FoodGrowthTickScript.growth_threshold(1) == 15, "threshold pop=1 -> 15")
	_check(FoodGrowthTickScript.growth_threshold(2) == 24, "threshold pop=2 -> 24")
	_check(FoodGrowthTickScript.growth_threshold(3) == 33, "threshold pop=3 -> 33")
	_check(FoodGrowthTickScript.growth_threshold(4) == 44, "threshold pop=4 -> 44")
	var m0 = HexMapScript.make_tiny_test_map()
	var own1: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)]
	var cx = CityScript.new(
		1,
		0,
		HexCoordScript.new(0, 0),
		_proj_stub(),
		"X",
		true,
		["palace"],
		own1,
		1,
		[],
		0
	)
	var sc0 = ScenarioScript.new(m0, [], [cx], 5, 9, null)
	var r0 = FoodGrowthTickScript.apply_for_player(sc0, 0)
	_check(r0["scenario"] != sc0, "scenario rebuilds on food progress")
	_check((r0["events"] as Array).size() == 1, "one progress event")
	var e0 = (r0["events"] as Array)[0] as Dictionary
	_check(e0["action_type"] == FoodGrowthTickScript.EVENT_TYPE_PROGRESS, "progress type")
	_check(e0["food_stored_after"] == 1, "surplus 1 accumulates")
	var c_after = r0["scenario"].city_by_id(1)
	_check(c_after.population == 1, "no growth below threshold")
	_check(c_after.food_stored == 1, "stored matches event")

	var m1 = HexMapScript.make_tiny_test_map()
	var c_g = CityScript.new(
		3,
		0,
		HexCoordScript.new(0, 0),
		_proj_stub(),
		"G",
		true,
		["palace"],
		own1,
		1,
		[],
		14
	)
	var sc1 = ScenarioScript.new(m1, [], [c_g], 5, 10, null)
	var r1 = FoodGrowthTickScript.apply_for_player(sc1, 0)
	var ev1 = r1["events"] as Array
	_check(ev1.size() == 2, "progress then city_grew")
	_check((ev1[0] as Dictionary)["action_type"] == FoodGrowthTickScript.EVENT_TYPE_PROGRESS, "progress first")
	_check((ev1[1] as Dictionary)["action_type"] == FoodGrowthTickScript.EVENT_TYPE_GREW, "grew second")
	var c_g2 = r1["scenario"].city_by_id(3)
	_check(c_g2.population == 2, "population increased")
	_check(c_g2.food_stored == 0, "spent threshold")

	var m2 = HexMapScript.make_tiny_test_map()
	var c_rem = CityScript.new(
		4,
		0,
		HexCoordScript.new(0, 0),
		_proj_stub(),
		"R",
		true,
		["palace"],
		own1,
		1,
		[],
		15
	)
	var sc2 = ScenarioScript.new(m2, [], [c_rem], 5, 11, null)
	var r2 = FoodGrowthTickScript.apply_for_player(sc2, 0)
	var c_rem_after = r2["scenario"].city_by_id(4)
	_check(c_rem_after.population == 2, "one growth with stored headroom")
	_check(c_rem_after.food_stored == 1, "carries remainder after threshold")

	var m3 = HexMapScript.make_tiny_test_map()
	var o_center: Array = [HexCoordScript.new(1, -1)]
	var c_starve = CityScript.new(8, 0, HexCoordScript.new(1, -1), null, "", false, [], o_center, 1, [], 5)
	var sc3 = ScenarioScript.new(m3, [], [c_starve], 5, 20, null)
	var scen_ref = sc3
	var r3 = FoodGrowthTickScript.apply_for_player(sc3, 0)
	_check((r3["events"] as Array).is_empty(), "surplus<=0 no events")
	_check(r3["scenario"] == scen_ref, "no scenario rebuild")
	_check(r3["scenario"].city_by_id(8).food_stored == 5, "stored unchanged")

	var sc_pair = _city_pair_scenario()
	var rp = FoodGrowthTickScript.apply_for_player(sc_pair, 0)
	var evp = rp["events"] as Array
	_check(evp.size() == 2, "two cities progress")
	_check((evp[0] as Dictionary)["city_id"] == 1, "lower id first")
	_check((evp[1] as Dictionary)["city_id"] == 2, "higher id second")

	var m4 = HexMapScript.make_tiny_test_map()
	var man: Array = [HexCoordScript.new(1, 0)]
	var c_keep = CityScript.new(
		9,
		0,
		HexCoordScript.new(0, 0),
		_proj_stub(),
		"K",
		true,
		["palace", "hearth"],
		own1,
		1,
		man,
		3
	)
	var sc4 = ScenarioScript.new(m4, [], [c_keep], 5, 30, null)
	var r4 = FoodGrowthTickScript.apply_for_player(sc4, 0)
	var ck = r4["scenario"].city_by_id(9)
	_check(ck.manual_worked_tiles.size() == c_keep.manual_worked_tiles.size(), "manual size")
	_check((ck.manual_worked_tiles[0] as HexCoord).equals(man[0]), "manual tile")
	_check(ck.owned_tiles.size() == c_keep.owned_tiles.size(), "owned preserved")
	_check(ck.building_ids.size() == 2 and ck.building_ids[1] == "hearth", "buildings preserved")
	var cp = ck.current_project as Dictionary
	_check(cp["progress"] == 0 and str(cp["project_id"]).find("warrior") >= 0, "project preserved")

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
