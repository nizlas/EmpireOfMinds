# Headless: godot --headless --path game -s res://domain/tests/test_movement_rules.gd
extends SceneTree
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const TerrainRuleDefinitionsScript = preload("res://domain/content/terrain_rule_definitions.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	_check(
		MovementRulesScript.legal_destinations(null, 1).size() == 0,
		"null scenario should yield no destinations"
	)
	_check(
		MovementRulesScript.legal_destinations(sc, 99).size() == 0,
		"unknown unit id should yield no destinations"
	)
	var d1 = MovementRulesScript.legal_destinations(sc, 1)
	_check(d1.size() == 3, "unit 1 should have 3 legal destinations")
	_check(_contains_coord(d1, HexCoordScript.new(1, -1)), "should contain (1,-1)")
	_check(_contains_coord(d1, HexCoordScript.new(-1, 1)), "should contain (-1,1)")
	_check(_contains_coord(d1, HexCoordScript.new(0, 1)), "should contain (0,1)")
	_check(
		not _contains_coord(d1, HexCoordScript.new(-1, 0)),
		"should not include WATER (-1,0)"
	)
	_check(
		not _contains_coord(d1, HexCoordScript.new(1, 0)),
		"should not include occupied (1,0)"
	)
	_check(
		not _contains_coord(d1, HexCoordScript.new(0, -1)),
		"should not include occupied (0,-1)"
	)
	_check(
		not TerrainRuleDefinitionsScript.is_passable_hex_map_value(
			sc.map.terrain_at(HexCoordScript.new(-1, 0))
		),
		"TerrainRuleDefinitions marks water (-1,0) impassable"
	)
	var d2 = MovementRulesScript.legal_destinations(sc, 2)
	_check(d2.size() == 2, "unit 2 should have 2 legal destinations")
	_check(_contains_coord(d2, HexCoordScript.new(1, -1)), "unit 2 should reach (1,-1)")
	_check(_contains_coord(d2, HexCoordScript.new(0, 1)), "unit 2 should reach (0,1)")
	_check(
		not _contains_coord(d2, HexCoordScript.new(0, 0)),
		"unit 2 should not step onto occupied (0,0)"
	)
	var d3 = MovementRulesScript.legal_destinations(sc, 3)
	_check(d3.size() == 1, "unit 3 should have 1 legal destination")
	_check(_contains_coord(d3, HexCoordScript.new(1, -1)), "unit 3 should reach (1,-1)")
	_check(
		not _contains_coord(d3, HexCoordScript.new(-1, 0)),
		"unit 3 should not include WATER (-1,0)"
	)
	_check(
		not _contains_coord(d3, HexCoordScript.new(0, 0)),
		"unit 3 should not include occupied (0,0)"
	)
	_assert_all_invariants(sc, d1)
	_assert_all_invariants(sc, d2)
	_assert_all_invariants(sc, d3)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _contains_coord(coords, coord) -> bool:
	var i = 0
	while i < coords.size():
		if coords[i].equals(coord):
			return true
		i = i + 1
	return false

func _assert_all_invariants(sc, coords) -> void:
	var i = 0
	while i < coords.size():
		var c = coords[i]
		_check(sc.map.has(c), "every destination must be on the map")
		_check(
			sc.map.terrain_at(c) != HexMapScript.Terrain.WATER,
			"every destination must not be WATER"
		)
		_check(
			sc.units_at(c).size() == 0,
			"every destination must be unoccupied"
		)
		i = i + 1

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
