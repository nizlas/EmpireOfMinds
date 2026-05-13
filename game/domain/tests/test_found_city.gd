# Headless: godot --headless --path game -s res://domain/tests/test_found_city.gd
extends SceneTree

const FoundCityScript = preload("res://domain/actions/found_city.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	var mk = FoundCityScript.make(0, 1, 0, 0)
	_check(mk["schema_version"] == FoundCityScript.SCHEMA_VERSION, "make schema_version")
	_check(mk["action_type"] == FoundCityScript.ACTION_TYPE, "make action_type")
	_check(mk["actor_id"] == 0 and mk["unit_id"] == 1, "make ids")
	var p_a = mk["position"] as Array
	_check(p_a.size() == 2 and int(p_a[0]) == 0 and int(p_a[1]) == 0, "make position")

	var r0 = FoundCityScript.validate(null, mk)
	_check(not r0["ok"] and r0["reason"] == "scenario_null", "scenario_null")
	var r1 = FoundCityScript.validate(sc, null)
	_check(not r1["ok"] and r1["reason"] == "wrong_action_type", "null action")
	var r1b = FoundCityScript.validate(sc, 7)
	_check(not r1b["ok"] and r1b["reason"] == "wrong_action_type", "not dict")
	var r2 = FoundCityScript.validate(sc, {"foo": 1})
	_check(not r2["ok"] and r2["reason"] == "wrong_action_type", "missing action_type")
	var r3 = FoundCityScript.validate(sc, {"action_type": "move_unit"})
	_check(not r3["ok"] and r3["reason"] == "wrong_action_type", "wrong action_type")
	var r4 = FoundCityScript.validate(sc, {"action_type": FoundCityScript.ACTION_TYPE})
	_check(
		not r4["ok"] and r4["reason"] == "unsupported_schema_version",
		"no schema"
	)
	var r5 = FoundCityScript.validate(
		sc,
		{
			"schema_version": 99,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"position": [0, 0],
		}
	)
	_check(
		not r5["ok"] and r5["reason"] == "unsupported_schema_version",
		"bad schema"
	)
	var r6 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"unit_id": 1,
			"position": [0, 0],
		}
	)
	_check(not r6["ok"] and r6["reason"] == "malformed_action", "missing actor_id")
	var r6b = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": "x",
			"unit_id": 1,
			"position": [0, 0],
		}
	)
	_check(not r6b["ok"] and r6b["reason"] == "malformed_action", "actor_id not int")
	var r7 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"position": [0, 0],
		}
	)
	_check(not r7["ok"] and r7["reason"] == "malformed_action", "missing unit_id")
	var r8 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
		}
	)
	_check(not r8["ok"] and r8["reason"] == "malformed_action", "missing position")
	var r9 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"position": "nope",
		}
	)
	_check(not r9["ok"] and r9["reason"] == "malformed_action", "position not array")
	var r10 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"position": [0, 0, 1],
		}
	)
	_check(not r10["ok"] and r10["reason"] == "malformed_action", "position len")
	var r11 = FoundCityScript.validate(
		sc,
		{
			"schema_version": FoundCityScript.SCHEMA_VERSION,
			"action_type": FoundCityScript.ACTION_TYPE,
			"actor_id": 0,
			"unit_id": 1,
			"position": [0, 1.5],
		}
	)
	_check(not r11["ok"] and r11["reason"] == "malformed_action", "position not int coords")
	var r12 = FoundCityScript.validate(
		sc,
		FoundCityScript.make(0, 99, 0, 0)
	)
	_check(not r12["ok"] and r12["reason"] == "unknown_unit", "unknown_unit")
	var r13 = FoundCityScript.validate(
		sc,
		FoundCityScript.make(1, 1, 0, 0)
	)
	_check(not r13["ok"] and r13["reason"] == "actor_not_owner", "actor_not_owner")
	var r13b = FoundCityScript.validate(
		sc,
		FoundCityScript.make(0, 2, 1, 0)
	)
	_check(
		not r13b["ok"] and r13b["reason"] == "unit_type_cannot_found",
		"unit_type_cannot_found"
	)
	var r14 = FoundCityScript.validate(
		sc,
		FoundCityScript.make(0, 1, 1, 0)
	)
	_check(not r14["ok"] and r14["reason"] == "unit_not_at_position", "unit_not_at_position")

	var sc_nomap = ScenarioScript.make_tiny_test_scenario()
	sc_nomap.map = HexMapScript.new({})
	var r15 = FoundCityScript.validate(
		sc_nomap,
		FoundCityScript.make(0, 1, 0, 0)
	)
	_check(not r15["ok"] and r15["reason"] == "tile_not_on_map", "tile_not_on_map")

	var m_water = HexMapScript.make_tiny_test_map()
	var sc_uw = ScenarioScript.new(
		m_water,
		[UnitScript.new(20, 0, HexCoordScript.new(-1, 0), "settler")],
		[],
		30,
		40
	)
	var r16 = FoundCityScript.validate(
		sc_uw,
		FoundCityScript.make(0, 20, -1, 0)
	)
	_check(not r16["ok"] and r16["reason"] == "tile_is_water", "tile_is_water")

	var existing_c = CityScript.new(50, 0, HexCoordScript.new(1, 0))
	var sc_city = ScenarioScript.new(
		m_water,
		[UnitScript.new(5, 0, HexCoordScript.new(1, 0), "settler")],
		[existing_c],
		10,
		60
	)
	var r175 = FoundCityScript.validate(
		sc_city,
		FoundCityScript.make(0, 5, 1, 0)
	)
	_check(
		not r175["ok"] and r175["reason"] == "tile_already_has_city",
		"tile_already_has_city"
	)

	var ok = FoundCityScript.validate(sc, FoundCityScript.make(0, 1, 0, 0))
	_check(ok["ok"], "legal validate")

	var before_units_n = sc.units().size()
	var before_cities_n = sc.cities().size()
	var before_nu = sc.peek_next_unit_id()
	var old_next_city = sc.peek_next_city_id()
	var sc_before_ref = sc
	var new_sc = FoundCityScript.apply(sc, FoundCityScript.make(0, 1, 0, 0))
	_check(new_sc.unit_by_id(1) == null, "apply removes founder")
	_check(new_sc.units().size() == before_units_n - 1, "apply unit count")
	var nc = new_sc.city_by_id(old_next_city)
	_check(nc != null and nc.owner_id == 0, "append city id")
	_check(nc.position.equals(HexCoordScript.new(0, 0)), "append city position")
	_check(nc.city_name == "Capital", "default founded name")
	_check(nc.is_capital, "first city per owner is capital")
	_check(nc.building_ids.size() == 1 and str(nc.building_ids[0]) == "palace", "capital gets palace")
	var exp_owned: Array = [
		HexCoordScript.new(0, 0),
		HexCoordScript.new(1, 0),
		HexCoordScript.new(1, -1),
		HexCoordScript.new(0, -1),
		HexCoordScript.new(-1, 0),
		HexCoordScript.new(-1, 1),
		HexCoordScript.new(0, 1),
	]
	_check(nc.owned_tiles.size() == exp_owned.size(), "founded city claims center plus radius-1 on tiny map")
	var oi: int = 0
	while oi < exp_owned.size():
		_check(nc.owned_tiles[oi].equals(exp_owned[oi]), "territory axial order idx " + str(oi))
		oi = oi + 1
	var m_ow = HexMapScript.make_tiny_test_map()
	var u_ow = [
		UnitScript.new(101, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(102, 0, HexCoordScript.new(1, -1), "settler"),
	]
	var sc_ow0 = ScenarioScript.new(m_ow, u_ow, [], 200, 210)
	var sc_ow1 = FoundCityScript.apply(sc_ow0, FoundCityScript.make(0, 101, 0, 0))
	var r_ow = FoundCityScript.validate(sc_ow1, FoundCityScript.make(0, 102, 1, -1))
	_check(
		not r_ow["ok"] and r_ow["reason"] == "tile_already_owned",
		"cannot found on hex in another city territory"
	)
	_check(new_sc.peek_next_city_id() == old_next_city + 1, "next_city_id +1")
	_check(new_sc.peek_next_unit_id() == before_nu, "next_unit_id preserved")
	_check(
		new_sc.cities().size() == before_cities_n + 1,
		"city list grew"
	)
	_check(sc_before_ref.units().size() == before_units_n, "orig scenario units unchanged")
	_check(sc_before_ref.cities().size() == before_cities_n, "orig scenario cities unchanged")
	_check(sc_before_ref.peek_next_city_id() == old_next_city, "orig next city id")

	var m2 = HexMapScript.make_tiny_test_map()
	var cu2 = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 0, HexCoordScript.new(1, -1), "settler"),
	]
	var cc_existing = CityScript.new(200, 1, HexCoordScript.new(1, 0))
	var sc2 = ScenarioScript.new(m2, cu2, [cc_existing], 500, 300)
	var old_c2 = sc2.peek_next_city_id()
	var applied2 = FoundCityScript.apply(
		sc2,
		FoundCityScript.make(0, 1, 0, 0)
	)
	_check(applied2.city_by_id(200) != null, "pre-existing city preserved")
	var new_cap2 = applied2.city_by_id(old_c2)
	_check(new_cap2 != null, "new city uses peek id")
	var skips_neighbor_10: bool = true
	var ti: int = 0
	while ti < new_cap2.owned_tiles.size():
		var ot = new_cap2.owned_tiles[ti]
		if ot.q == 1 and ot.r == 0:
			skips_neighbor_10 = false
		ti = ti + 1
	_check(skips_neighbor_10, "new city skips ring tile already owned by older city")
	_check(new_cap2.owned_tiles.size() == 6, "center plus five unowned neighbors on tiny map")
	_check(applied2.peek_next_unit_id() == 500, "counters no spill to units")

	var edge_cells := {Vector2i(0, 0): HexMapScript.Terrain.PLAINS}
	var edge_m = HexMapScript.new(edge_cells)
	var sc_edge = ScenarioScript.new(
		edge_m,
		[UnitScript.new(51, 0, HexCoordScript.new(0, 0), "settler")],
		[],
		60,
		70
	)
	var sc_edge2 = FoundCityScript.apply(sc_edge, FoundCityScript.make(0, 51, 0, 0))
	var cy_edge = sc_edge2.city_by_id(70)
	_check(cy_edge != null and cy_edge.owned_tiles.size() == 1, "single-hex map owns center only")

	var m3 = HexMapScript.make_prototype_play_map()
	var u3 = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(4, 0, HexCoordScript.new(3, -2), "settler"),
	]
	var sc3 = ScenarioScript.new(m3, u3, [], 500, 300)
	var sc3a = FoundCityScript.apply(sc3, FoundCityScript.make(0, 1, 0, 0))
	var cap_id = sc3.peek_next_city_id()
	var cap_ct = sc3a.city_by_id(cap_id)
	_check(cap_ct != null and cap_ct.city_name == "Capital", "prototype two-settler first Capital")
	_check(cap_ct.is_capital and cap_ct.building_ids.size() == 1, "first founded gets palace bundle")
	var sc3b = FoundCityScript.apply(sc3a, FoundCityScript.make(0, 4, 3, -2))
	var sec_id = sc3b.peek_next_city_id() - 1
	var sec_ct = sc3b.city_by_id(sec_id)
	_check(sec_ct != null and sec_ct.city_name == "Settlement 2", "second city numbered")
	_check(not sec_ct.is_capital, "second city not capital")
	_check(sec_ct.building_ids.is_empty(), "second city has no default buildings")
	var overlaps_cap_territory: bool = false
	var si: int = 0
	while si < sec_ct.owned_tiles.size():
		var st = sec_ct.owned_tiles[si]
		var ci2: int = 0
		while ci2 < cap_ct.owned_tiles.size():
			if st.equals(cap_ct.owned_tiles[ci2]):
				overlaps_cap_territory = true
			ci2 = ci2 + 1
		si = si + 1
	_check(not overlaps_cap_territory, "second city territory does not duplicate first city's tiles")

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
