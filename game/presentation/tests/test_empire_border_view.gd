# Headless: **EmpireBorderView** owner **union** perimeter topology helper tests (no layout draw path).
# Usage: godot --headless --path game -s res://presentation/tests/test_empire_border_view.gd
extends SceneTree

const EmpireBorderViewScript = preload("res://presentation/empire_border_view.gd")
const CityTerritoryViewScript = preload("res://presentation/city_territory_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const CityScript = preload("res://domain/city.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")

var _total := 0
var _any_fail := false


func _init() -> void:
	_guard_empire_border_source_imports()

	_check(
		is_equal_approx(EmpireBorderViewScript.EMPIRE_OUTER_ALPHA, CityTerritoryViewScript._OUTER_ALPHA),
		"empire outer alpha matches CityTerritoryView rim (selection-independent parity)"
	)
	_check(
		is_equal_approx(EmpireBorderViewScript.EMPIRE_INNER_ALPHA, CityTerritoryViewScript._INNER_ALPHA),
		"empire inner alpha matches CityTerritoryView rim"
	)
	_check(
		is_equal_approx(EmpireBorderViewScript.EMPIRE_INNER_WIDTH_FRAC, CityTerritoryViewScript._INNER_WIDTH_FRAC),
		"empire inner width frac matches CityTerritoryView"
	)

	var fp_empty = EmpireBorderViewScript.empire_topology_fingerprint(null)
	_check(fp_empty == "", "null scenario fingerprint empty")

	var m0 = HexMapScript.make_tiny_test_map()
	var sc_no_cities = ScenarioScript.new(m0, [], [], 80, 90, null)
	_check(EmpireBorderViewScript.distinct_sorted_owner_ids(sc_no_cities).is_empty(), "no cities no owners")

	var gs_t = GameStateScript.make_tiny_test_state()
	_check(gs_t.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found city for empire tests")
	var scen_one = gs_t.scenario
	var n0 = EmpireBorderViewScript.empire_border_half_edge_count_for_owner(scen_one, 0)
	_check(n0 > 0, "one city owner 0 has outer perimeter half-edges")

	var uu: Array = []
	var c_left = CityScript.new(1, 0, HexCoordScript.new(0, 0), null, "L", true, ["palace"])
	var c_right = CityScript.new(2, 0, HexCoordScript.new(1, 0), null, "R", false, [])
	var scen_touch = ScenarioScript.new(m0, uu, [c_left, c_right], 80, 90, null)
	var n_union_touch = EmpireBorderViewScript.empire_border_half_edge_count_for_owner(scen_touch, 0)
	var n_a = CityTerritoryViewScript.territory_border_edge_count(c_left.owned_tiles)
	var n_b = CityTerritoryViewScript.territory_border_edge_count(c_right.owned_tiles)
	_check(n_union_touch < n_a + n_b, "merged same-owner adjacent unions suppress internal edges")
	_check(n_union_touch == 10 and n_a == 6 and n_b == 6, "tiny adjacent pair perimeter counts pinned")

	var c_p0 = CityScript.new(1, 0, HexCoordScript.new(0, 0), null, "P0", true, ["palace"])
	var c_p1 = CityScript.new(2, 1, HexCoordScript.new(1, 0), null, "P1", false, [])
	var scen_two_owners = ScenarioScript.new(m0, uu, [c_p0, c_p1], 80, 90, null)
	var e0 = EmpireBorderViewScript.empire_border_half_edge_count_for_owner(scen_two_owners, 0)
	var e1 = EmpireBorderViewScript.empire_border_half_edge_count_for_owner(scen_two_owners, 1)
	_check(e0 == 6 and e1 == 6, "touching different owners each keeps full hex perimeter")

	var fp_a = EmpireBorderViewScript.empire_topology_fingerprint(scen_touch)
	var fp_b = EmpireBorderViewScript.empire_topology_fingerprint(scen_touch)
	_check(fp_a == fp_b, "topology fingerprint deterministic")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _guard_empire_border_source_imports() -> void:
	var path = "res://presentation/empire_border_view.gd"
	var f = FileAccess.open(path, FileAccess.READ)
	_check(f != null, "open empire_border_view.gd")
	var txt = f.get_as_text()
	var forbidden: PackedStringArray = [
		"legal_actions",
		"effective_rules",
		"city_yields",
		"city_project_definitions",
		"city_production_panel",
		"HudCanvas",
		"selection_state",
	]
	var fi: int = 0
	while fi < forbidden.size():
		var tok: String = str(forbidden[fi]).to_lower()
		_check(not txt.to_lower().contains(tok), "empire_border_view must not reference %s" % forbidden[fi])
		fi += 1


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
