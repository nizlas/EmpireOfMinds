# Headless: godot --headless --path game -s res://domain/tests/test_city_yields_worked_tiles.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")

var _total = 0
var _any_fail = false


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


func _init() -> void:
	var m_tiny = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var ctr = HexCoordScript.new(1, -1)
	var ring_a = HexCoordScript.new(0, -1)
	var ring_b = HexCoordScript.new(1, 0)
	var owned_ring: Array = [ctr, ring_a, ring_b]
	var c_ring = CityScript.new(40, 0, ctr, null, "", true, ["palace"], owned_ring, 1)
	var scen_ring = ScenarioScript.new(m_tiny, u, [c_ring], 10, 100, null)
	var wt = CityYieldsScript.worked_tiles_for_city(scen_ring, c_ring)
	_check(wt.size() == 1, "population 1 selects one worked tile")
	_check(not (wt[0] as HexCoord).equals(ctr), "city center is never a worked tile")
	_check((wt[0] as HexCoord).equals(ring_a), "tie-break picks lower q among equal plains neighbors")

	var wt_b = CityYieldsScript.worked_tiles_for_city(scen_ring, c_ring)
	_check(_hex_arrays_equal(wt, wt_b), "worked tile order is deterministic across calls")

	var cells_ht := {
		Vector2i(0, 0): HexMapScript.Terrain.PLAINS,
		Vector2i(1, 0): HexMapScript.Terrain.PLAINS,
		Vector2i(1, -1): HexMapScript.Terrain.PLAINS,
		Vector2i(0, -1): HexMapScript.Terrain.PLAINS,
		Vector2i(-1, 0): HexMapScript.Terrain.WATER,
		Vector2i(-1, 1): HexMapScript.Terrain.PLAINS,
		Vector2i(0, 1): HexMapScript.Terrain.PLAINS,
	}
	var lf_ht := {Vector2i(0, -1): HexMapScript.Landform.HILLS}
	var m_ht = HexMapScript.new(cells_ht, lf_ht)
	var c_manual_h = CityScript.new(
		44,
		0,
		ctr,
		null,
		"",
		true,
		["palace"],
		owned_ring,
		1,
		[HexCoordScript.new(0, -1)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_mh = ScenarioScript.new(m_ht, u, [c_manual_h], 14, 100, null)
	var wt_mh = CityYieldsScript.worked_tiles_for_city(scen_mh, c_manual_h)
	_check(wt_mh.size() == 1, "manual pop1 keeps one slot")
	_check((wt_mh[0] as HexCoord).equals(HexCoordScript.new(0, -1)), "manual prefers declared hills ring")

	var c_m2 = CityScript.new(
		45,
		0,
		ctr,
		null,
		"",
		false,
		[],
		owned_ring,
		2,
		[HexCoordScript.new(0, -1)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_m2 = ScenarioScript.new(m_ht, u, [c_m2], 15, 100, null)
	var wt_m2 = CityYieldsScript.worked_tiles_for_city(scen_m2, c_m2)
	_check(wt_m2.size() == 1, "manual mode: only listed citizens work (no auto-fill)")
	_check((wt_m2[0] as HexCoord).equals(HexCoordScript.new(0, -1)), "manual tile only")

	var c_m2_auto = CityScript.new(49, 0, ctr, null, "", false, [], owned_ring, 2)
	var scen_m2a = ScenarioScript.new(m_ht, u, [c_m2_auto], 25, 100, null)
	var wt_m2a = CityYieldsScript.worked_tiles_for_city(scen_m2a, c_m2_auto)
	_check(wt_m2a.size() == 2, "auto mode pop 2 deterministic fill")
	_check((wt_m2a[0] as HexCoord).equals(HexCoordScript.new(1, 0)), "auto prefers higher food when total yield ties")
	_check((wt_m2a[1] as HexCoord).equals(HexCoordScript.new(0, -1)), "auto second slot hills neighbor")

	var c_m2both = CityScript.new(
		48,
		0,
		ctr,
		null,
		"",
		true,
		["palace"],
		owned_ring,
		2,
		[HexCoordScript.new(1, 0), HexCoordScript.new(0, -1)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_m2b = ScenarioScript.new(m_ht, u, [c_m2both], 18, 100, null)
	var wt_m2b = CityYieldsScript.worked_tiles_for_city(scen_m2b, c_m2both)
	_check(wt_m2b.size() == 2, "population 2 with two manuals: no auto-fill slots left")
	_check((wt_m2b[0] as HexCoord).equals(HexCoordScript.new(1, 0)), "first manual order preserved")
	_check((wt_m2b[1] as HexCoord).equals(HexCoordScript.new(0, -1)), "second manual order preserved")

	var c_bad_m = CityScript.new(
		46,
		0,
		ctr,
		null,
		"",
		false,
		[],
		owned_ring,
		1,
		[HexCoordScript.new(9, 9)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_bm = ScenarioScript.new(m_tiny, u, [c_bad_m], 16, 100, null)
	var wt_bm = CityYieldsScript.worked_tiles_for_city(scen_bm, c_bad_m)
	_check(wt_bm.is_empty(), "manual mode: invalid manual yields no worked tiles (no auto fallback)")

	var c_wm = CityScript.new(
		47,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		[],
		[HexCoordScript.new(0, 0), HexCoordScript.new(-1, 0)],
		1,
		[HexCoordScript.new(-1, 0)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_wm = ScenarioScript.new(m_tiny, u, [c_wm], 17, 100, null)
	var wt_wm = CityYieldsScript.worked_tiles_for_city(scen_wm, c_wm)
	_check(wt_wm.is_empty(), "manual water only yields no worked tile")
	var c_water_ring = CityScript.new(
		41,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		[],
		[HexCoordScript.new(0, 0), HexCoordScript.new(-1, 0)],
		3
	)
	var scen_w = ScenarioScript.new(m_tiny, u, [c_water_ring], 11, 100, null)
	var wt_w = CityYieldsScript.worked_tiles_for_city(scen_w, c_water_ring)
	_check(wt_w.is_empty(), "WATER-only owned neighbor yields no worked tiles")

	var c_cap_many = CityScript.new(42, 0, ctr, null, "", true, ["palace"], owned_ring, 10)
	var scen_many = ScenarioScript.new(m_tiny, u, [c_cap_many], 12, 100, null)
	var wt_lim = CityYieldsScript.worked_tiles_for_city(scen_many, c_cap_many)
	_check(wt_lim.size() == 2, "worked count is min(population, eligible non-center tiles)")
	var exp_two: Array = [HexCoordScript.new(0, -1), HexCoordScript.new(1, 0)]
	_check(_hex_arrays_equal(wt_lim, exp_two), "stable tie-break among tied plains flats")

	var c_manual_idle = CityScript.new(
		52,
		0,
		ctr,
		null,
		"",
		false,
		[],
		owned_ring,
		2,
		[],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	var scen_idle = ScenarioScript.new(m_tiny, u, [c_manual_idle], 26, 100, null)
	_check(
		CityYieldsScript.worked_tiles_for_city(scen_idle, c_manual_idle).is_empty(),
		"manual mode empty list: all citizens idle"
	)

	var y_tot = CityYieldsScript.city_total_yield(scen_ring, c_ring)
	_check(int(y_tot["food"]) == 3 and int(y_tot["production"]) == 2, "total includes center floors")
	_check(int(y_tot["science"]) == 1 and int(y_tot["coin"]) == 1, "total includes palace plus worked terrain")

	var sum_parts = CityYieldsScript.add(
		CityYieldsScript.add(
			CityYieldsScript.city_center_yield(m_tiny, c_ring),
			CityYieldsScript.building_yield("palace")
		),
		CityYieldsScript.worked_tiles_yield(scen_ring, c_ring)
	)
	_check(int(sum_parts["food"]) == int(y_tot["food"]), "total matches center + buildings + worked")

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
