# Headless: godot --headless --path game -s res://presentation/tests/test_city_worked_tiles_view.gd
extends SceneTree

const CityWorkedTilesViewScript = preload("res://presentation/city_worked_tiles_view.gd")
const CityViewStateScript = preload("res://presentation/city_view_state.gd")
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
	_check(txt.find("draw_colored_polygon(") < 0, "view must not draw full-hex planning fills (draw_colored_polygon)")
	_check(txt.find("draw_polygon(") < 0, "view must not draw full-hex planning fills (draw_polygon)")
	_check(
		txt.find("TEXTURE_FILTER_LINEAR_WITH_MIPMAPS") < 0,
		"citizen markers must not use LINEAR_WITH_MIPMAPS (edge bleed / banding)"
	)
	var banned: PackedStringArray = PackedStringArray(
		["city_project_definitions", "effective_rules", "legal_actions", "city_production_panel"]
	)
	var bi: int = 0
	while bi < banned.size():
		var sub: String = banned[bi]
		_check(txt.find(sub) < 0, "view source must not contain \"%s\"" % sub)
		bi += 1


func _citizen_marker_imports_disable_mipmaps() -> void:
	var paths: PackedStringArray = PackedStringArray(
		[
			"res://assets/prototype/map_markers/city_citizens/citizen_marker_dim.png.import",
			"res://assets/prototype/map_markers/city_citizens/citizen_marker_worked.png.import",
		]
	)
	var pi: int = 0
	while pi < paths.size():
		var ip: String = paths[pi]
		var itxt: String = FileAccess.get_file_as_string(ip)
		_check(itxt.find("mipmaps/generate=false") >= 0, "%s must set mipmaps/generate=false" % ip)
		_check(itxt.find("mipmaps/generate=true") < 0, "%s must not enable mipmaps" % ip)
		pi += 1


func _init() -> void:
	_forbidden_scan_source()
	_citizen_marker_imports_disable_mipmaps()

	var pst = CityWorkedTilesViewScript.planning_marker_draw_style()
	_check(float(pst.get("citizen_icon_height_ratio", 0.0)) > 0.1, "citizen_icon_height_ratio sane")
	_check(float(pst.get("planning_scale_mul", 0.0)) >= 1.5, "planning_scale_mul stays elevated for PLANNING readability")
	_check(float(pst.get("planning_y_offset_icon_ratio", 0.0)) < 0.0, "planning_y_offset_icon_ratio shifts markers upward")
	_check(float(pst.get("normal_alpha", 0.0)) > 0.0, "normal_alpha sane")

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
	_check(items.size() == 1, "tiny pop1 one non-center owned tile")
	var bd: Dictionary = CityYieldsScript.yield_breakdown_for_city(scen, c_cap) as Dictionary
	var wt: Array = bd.get("worked_tiles", []) as Array
	_check(wt.size() == 1, "breakdown has one worked tile")
	var d0: Dictionary = items[0] as Dictionary
	_check(str(d0.get("kind", "")) == "worked", "ring tile is worked")
	_check((d0.get("coord", null) as Object).equals(wt[0] as Object), "marker coord matches breakdown worked_tiles[0]")

	var cvs_off = CityViewStateScript.new()
	_check(
		CityWorkedTilesViewScript.compute_draw_marker_items(scen, sel_cap, null).is_empty(),
		"draw items empty when city_view_state null"
	)
	_check(
		CityWorkedTilesViewScript.compute_draw_marker_items(scen, sel_cap, cvs_off).is_empty(),
		"draw items empty in NORMAL (hub only, no citizen markers)"
	)
	cvs_off.enter_planning()
	var drawn_plan: Array = CityWorkedTilesViewScript.compute_draw_marker_items(scen, sel_cap, cvs_off)
	_check(drawn_plan.size() == items.size(), "PLANNING draw item count matches logical list")
	_check(_markers_equal_lists(drawn_plan, items), "PLANNING draw list equals compute_worked_marker_items")

	var k_sorted: int = 0
	while k_sorted < items.size() - 1:
		var da: Dictionary = items[k_sorted] as Dictionary
		var db: Dictionary = items[k_sorted + 1] as Dictionary
		var ca: HexCoord = da["coord"] as HexCoord
		var cb: HexCoord = db["coord"] as HexCoord
		var leq: bool = ca.q < cb.q or (ca.q == cb.q and ca.r <= cb.r)
		_check(leq, "deterministic q then r order")
		k_sorted += 1

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
	var items_z: Array = CityWorkedTilesViewScript.compute_worked_marker_items(scen_z, sel_z)
	_check(items_z.size() == 1, "population 0 still shows dim on non-center owned")
	_check(str((items_z[0] as Dictionary).get("kind", "")) == "dim", "population 0 kind dim")

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
	var items_w: Array = CityWorkedTilesViewScript.compute_worked_marker_items(scen_w, sel_w)
	_check(items_w.size() == 1, "water ring tile still listed as dim marker")
	_check(str((items_w[0] as Dictionary).get("kind", "")) == "dim", "zero-yield ring is dim not worked")
	var hxw: HexCoord = (items_w[0] as Dictionary).get("coord") as HexCoord
	_check(hxw.q == -1 and hxw.r == 0, "non-center water coord")

	var ctr2 = HexCoordScript.new(1, -1)
	var owned_two: Array = [ctr2, HexCoordScript.new(0, -1), HexCoordScript.new(1, 0)]
	var c_two = CityScript.new(80, 0, ctr2, null, "TwoRing", false, [], owned_two, 0)
	var scen_two = ScenarioScript.new(scen.map, scen.units(), [c_two], 10, 100, null)
	var sel_two = SelectionStateScript.new()
	sel_two.select_city(80)
	var items_two: Array = CityWorkedTilesViewScript.compute_worked_marker_items(scen_two, sel_two)
	_check(items_two.size() == 2, "two non-center owned")
	var t0: Dictionary = items_two[0] as Dictionary
	var t1: Dictionary = items_two[1] as Dictionary
	var c0: HexCoord = t0["coord"] as HexCoord
	var c1: HexCoord = t1["coord"] as HexCoord
	_check(c0.q == 0 and c0.r == -1 and c1.q == 1 and c1.r == 0, "sorted (0,-1) before (1,0)")
	_check(str(t0.get("kind", "")) == "dim" and str(t1.get("kind", "")) == "dim", "both dim when pop 0")

	var round1 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	var round2 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(_markers_equal_lists(round1, round2), "two calls equal markers")
	round1.append({"coord": HexCoordScript.new(9, 9), "kind": "worked"})
	var round3 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(round3.size() == 1, "mut array append does not leak")
	var d_live: Dictionary = round3[0] as Dictionary
	d_live["kind"] = "broken"
	var round4 = CityWorkedTilesViewScript.compute_worked_marker_items(scen, sel_cap)
	_check(str((round4[0] as Dictionary).get("kind", "")) == "worked", "mut dict does not affect next call")

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
