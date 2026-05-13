# Headless: godot --headless --path game -s res://domain/tests/test_city_yields.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var pm = HexMapScript.make_prototype_play_map()
	var h_woods = HexCoordScript.new(1, -1)
	var y_raw = CityYieldsScript.raw_terrain_yield(pm, h_woods)
	_check(int(y_raw["food"]) == 1 and int(y_raw["production"]) == 2, "woods PLAINS raw yield")
	var h_clear = HexCoordScript.new(0, 0)
	var y_clear = CityYieldsScript.raw_terrain_yield(pm, h_clear)
	_check(int(y_clear["food"]) == 1 and int(y_clear["production"]) == 1, "prototype (0,0) PLAINS flat raw")

	var m_tiny = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var c_plain = CityScript.new(3, 0, HexCoordScript.new(1, -1))
	var scen_plain = ScenarioScript.new(m_tiny, u, [c_plain], 10, 20, null)
	var tot_plain = CityYieldsScript.city_total_yield(scen_plain, c_plain)
	_check(
		int(tot_plain["food"]) == 2 and int(tot_plain["production"]) == 1 and int(tot_plain["science"]) == 0,
		"city off PLAINS flat without palace"
	)
	var c_cap = CityScript.new(4, 0, HexCoordScript.new(1, -1), null, "", true, ["palace"])
	var scen_cap = ScenarioScript.new(m_tiny, u, [c_cap], 10, 20, null)
	_check(CityYieldsScript.science_for_player(scen_cap, 0) == 1, "palace adds science per capital")
	var c2 = CityScript.new(5, 0, HexCoordScript.new(0, -1))
	var scen_two = ScenarioScript.new(m_tiny, u, [c_cap, c2], 10, 20, null)
	_check(CityYieldsScript.science_for_player(scen_two, 0) == 1, "only palace city contributes science")
	var c_pal_prod = CityScript.new(8, 0, HexCoordScript.new(1, -1), null, "", true, ["palace"])
	var sc_pprod = ScenarioScript.new(m_tiny, u, [c_pal_prod], 10, 20, null)
	var y_pprod = CityYieldsScript.city_total_yield(sc_pprod, c_pal_prod)
	_check(int(y_pprod["production"]) == 1, "palace does not add production to city total")

	# Phase 5.1.16g — territory must not change city_total_yield (worked tiles deferred to 5.1.16h).
	var center_reg = HexCoordScript.new(1, -1)
	var ring_reg = HexCoordScript.new(0, -1)
	var owned_extra: Array = [center_reg, ring_reg]
	var c_reg = CityScript.new(12, 0, center_reg, null, "", false, [], owned_extra)
	var sc_reg = ScenarioScript.new(m_tiny, u, [c_reg], 10, 25, null)
	var y_reg = CityYieldsScript.city_total_yield(sc_reg, c_reg)
	_check(
		int(y_reg["food"]) == 2 and int(y_reg["production"]) == 1,
		"regression: productive owned ring tiles do not add to food/production total"
	)
	_check(
		int(y_reg["science"]) == 0 and int(y_reg["coin"]) == 0,
		"regression: owned ring does not add science/coin"
	)

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
