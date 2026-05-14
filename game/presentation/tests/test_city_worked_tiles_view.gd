# Headless: godot --headless --path game -s res://presentation/tests/test_city_worked_tiles_view.gd
extends SceneTree

const CityWorkedTilesViewScript = preload("res://presentation/city_worked_tiles_view.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false


func _markers_equal_lists(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var i = 0
	while i < a.size():
		var dai = a[i]
		var dbi = b[i]
		if typeof(dai) != TYPE_DICTIONARY or typeof(dbi) != TYPE_DICTIONARY:
			return false
		var da: Dictionary = dai as Dictionary
		var db: Dictionary = dbi as Dictionary
		if str(da.get("kind", "")) != str(db.get("kind", "")):
			return false
		var ca = da.get("coord", null)
		var cb = db.get("coord", null)
		if ca == null or cb == null:
			return false
		if not (ca as Object).equals(cb):
			return false
		i += 1
	return true


func _tiny_pop1_capital_scenario():
	var m_tiny = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var ctr = HexCoordScript.new(1, -1)
	var ring_a = HexCoordScript.new(0, -1)
	var owned_ring: Array = [ctr, ring_a]
	var c_cap = CityScript.new(77, 0, ctr, null, "CapTiny", true, ["palace"], owned_ring, 1)
	var scen = ScenarioScript.new(m_tiny, u, [c_cap], 10, 100, null)
	return {"scenario": scen, "city": c_cap}


func _forbidden_scan_source() -> void:
	var fp: String = "res://presentation/city_worked_tiles_view.gd"
	var txt: String = FileAccess.get_file_as_string(fp)
	_check(txt.find("yield_breakdown_for_city") >= 0, "view source references yield_breakdown_for_city")
	_check(txt.find("set_deferred(\"z_index\")") < 0, "no deferred z_index workaround in view")
	_check(txt.find("worked_tiles_for_city") < 0, "view source must not name worked_tiles_for_city")
	var banned: PackedStringArray = PackedStringArray(
		["city_project_definitions", "effective_rules", "legal_actions", "city_production_panel"]
	)
	var bi: int = 0
	while bi < banned.size():
		var sub: String = banned[bi]
		_check(txt.find(sub) < 0, "view source must not contain \"%s\"" % sub)
		bi += 1


func _init() -> void:
	_forbidden_scan_source()

	var sel_none = SelectionStateScript.new()
	var tiny = _tiny_pop1_capital_scenario()
	var scen: Variant = tiny["scenario"]
	var c_cap: Variant = tiny["city"]

	_check(CityWorkedTilesViewScript.compute_worked_marker_items(null, sel_none).size() == 0, "null scenario returns empty")

	var sel_unit_only = SelectionStateScript.new()
	sel_unit_only.select(1)
	_check(CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_unit_only).size() == 0, "no city selection empty")

	_check(CityWorkedTilesViewScript.compute_worked_marker_items(scen, null).size() == 0, "null selection empty")
	var sel_bad = SelectionStateScript.new()
	sel_bad.select_city(-999999)
	_check(CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_bad).size() == 0, "unknown city empty")

	var sel_cap = SelectionStateScript.new()
	sel_cap.select_city(77)
	var items: Array = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(items.size() == 1, "tiny pop1 yields one marker")

	var wt: Array = (CityYieldsScript.yield_breakdown_for_city(scen, c_cap) as Dictionary).get(
		"worked_tiles", []
	) as Array
	_check(items.size() == wt.size(), "markers count matches breakdown worked_tiles")
	var eo: int = 0
	while eo < items.size():
		var d: Dictionary = items[eo] as Dictionary
		_check(str(d.get("kind", "")) == "auto_worked", "kind auto_worked")
		var coo = d.get("coord", null)
		var wt_h = wt[eo]
		_check(coo != null and wt_h != null and (coo as Object).equals(wt_h as Object), "coord + order matches breakdown worked_tiles")
		eo += 1

	var c_z = CityScript.new(
		78,
		0,
		c_cap.position,
		null,
		"",
		false,
		[],
		c_cap.owned_tiles,
		0
	)
	var scen_z = ScenarioScript.new(scen.map, scen.units(), [c_z], 10, 100, null)
	var sel_z = SelectionStateScript.new()
	sel_z.select_city(78)
	_check(CityWorkedTilesViewScript.compute_worked_marker_items(scen_z, sel_z).is_empty(), "population 0 empty")

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
	var scen_w = ScenarioScript.new(scen.map, scen.units(), [c_water], 10, 100, null)
	var sel_w = SelectionStateScript.new()
	sel_w.select_city(79)
	_check(CityWorkedTilesViewScript.compute_worked_marker_items(scen_w, sel_w).is_empty(), "water/zero-yield ring empty")

	var round1 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	var round2 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(_markers_equal_lists(round1, round2), "two calls equal markers")
	round1.append({"coord": HexCoordScript.new(9, 9), "kind": "auto_worked"})
	var round3 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(round3.size() == 1, "mut array append does not leak")
	var d_live: Dictionary = round3[0] as Dictionary
	d_live["kind"] = "broken"
	var round4 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(str((round4[0] as Dictionary).get("kind", "")) == "auto_worked", "mut dict does not affect next call")

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
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
