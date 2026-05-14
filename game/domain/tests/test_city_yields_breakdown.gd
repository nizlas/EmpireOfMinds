# Headless: godot --headless --path game -s res://domain/tests/test_city_yields_breakdown.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

var _total = 0
var _any_fail = false


func _yield_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		CityYieldsScript.get_yield(a, "food") == CityYieldsScript.get_yield(b, "food")
		and CityYieldsScript.get_yield(a, "production") == CityYieldsScript.get_yield(b, "production")
		and CityYieldsScript.get_yield(a, "science") == CityYieldsScript.get_yield(b, "science")
		and CityYieldsScript.get_yield(a, "coin") == CityYieldsScript.get_yield(b, "coin")
	)


func _hex_arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var i = 0
	while i < a.size():
		var ha = a[i]
		var hb = b[i]
		if ha == null or hb == null:
			return false
		if not ha.equals(hb):
			return false
		i += 1
	return true


func _keys_exactly_5(d: Dictionary) -> bool:
	return d.has("center") and d.has("buildings") and d.has("worked") and d.has("worked_tiles") and d.has("total") and d.size() == 5


func _init() -> void:
	var m_tiny = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var ctr = HexCoordScript.new(1, -1)
	var ring_a = HexCoordScript.new(0, -1)
	var owned_ring: Array = [ctr, ring_a]
	var c_cap_pal = CityScript.new(
		77,
		0,
		ctr,
		null,
		"CapTiny",
		true,
		["palace"],
		owned_ring,
		1
	)
	var scen = ScenarioScript.new(m_tiny, u, [c_cap_pal], 10, 100, null)
	var bd = CityYieldsScript.yield_breakdown_for_city(scen, c_cap_pal)
	_check(_keys_exactly_5(bd), "breakdown has exactly five keys")
	var tot_expect = CityYieldsScript.city_total_yield(scen, c_cap_pal)
	_check(
		_yield_dicts_equal(bd["total"] as Dictionary, tot_expect),
		"breakdown total matches city_total_yield"
	)
	var wt_expect = CityYieldsScript.worked_tiles_for_city(scen, c_cap_pal)
	_check(_hex_arrays_equal(bd["worked_tiles"] as Array, wt_expect), "breakdown worked_tiles matches helper")
	var bld_sum = CityYieldsScript.empty()
	bld_sum = CityYieldsScript.add(bld_sum, CityYieldsScript.building_yield("palace"))
	_check(
		_yield_dicts_equal(bd["buildings"] as Dictionary, bld_sum),
		"palace yield is under buildings only"
	)
	_check(CityYieldsScript.get_yield(bd["center"] as Dictionary, "science") == 0, "center has no science")
	_check(CityYieldsScript.get_yield(bd["worked"] as Dictionary, "science") == 0, "worked raw has no science")

	var c_z = CityScript.new(78, 0, ctr, null, "", false, [], owned_ring, 0)
	var bd_z = CityYieldsScript.yield_breakdown_for_city(scen, c_z)
	_check((bd_z["worked_tiles"] as Array).is_empty(), "population 0 empty worked_tiles")
	_check(
		_yield_dicts_equal(bd_z["worked"] as Dictionary, CityYieldsScript.empty()),
		"population 0 empty worked yield"
	)

	var c_water = CityScript.new(
		79,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		[],
		[HexCoordScript.new(0, 0), HexCoordScript.new(-1, 0)],
		3
	)
	var bd_w = CityYieldsScript.yield_breakdown_for_city(scen, c_water)
	_check((bd_w["worked_tiles"] as Array).is_empty(), "water-only ring empty worked_tiles")
	_check(
		_yield_dicts_equal(bd_w["worked"] as Dictionary, CityYieldsScript.empty()),
		"water-only ring empty worked yield"
	)

	var b1 = CityYieldsScript.yield_breakdown_for_city(scen, c_cap_pal)
	var b2 = CityYieldsScript.yield_breakdown_for_city(scen, c_cap_pal)
	_check(_yield_dicts_equal(b1["total"] as Dictionary, b2["total"] as Dictionary), "two calls equal total")
	(b1["total"] as Dictionary)["food"] = 99999
	var b3 = CityYieldsScript.yield_breakdown_for_city(scen, c_cap_pal)
	_check(CityYieldsScript.get_yield(b3["total"] as Dictionary, "food") != 99999, "mutate first total does not leak")
	(b1["worked_tiles"] as Array).append(HexCoordScript.new(9, 9))
	_check(
		(b3["worked_tiles"] as Array).size() == (b2["worked_tiles"] as Array).size(),
		"mutate worked_tiles array does not affect next call"
	)

	var bd_null = CityYieldsScript.yield_breakdown_for_city(null, c_cap_pal)
	_check(_keys_exactly_5(bd_null), "null scenario still five keys")
	_check(
		_yield_dicts_equal(bd_null["total"] as Dictionary, CityYieldsScript.empty()),
		"null scenario empty total"
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
