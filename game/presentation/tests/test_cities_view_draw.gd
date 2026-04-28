# Headless: godot --headless --path game -s res://presentation/tests/test_cities_view_draw.gd
extends SceneTree
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)),
	]
	var cs = [
		CityScript.new(5, 0, HexCoordScript.new(1, -1)),
		CityScript.new(6, 1, HexCoordScript.new(0, 1)),
	]
	var sc = ScenarioScript.new(m, us, cs)
	var layout = HexLayoutScript.new()
	var items = CitiesViewScript.compute_marker_items(sc, layout)
	_check(items.size() == 2, "two city marker items")
	var id_seen = {}
	var i = 0
	while i < items.size():
		var it = items[i]
		var cid = it["city_id"]
		if not id_seen.has(cid):
			id_seen[cid] = 0
		id_seen[cid] = id_seen[cid] + 1
		_check(sc.map.has(it["coord"]), "marker coord on map")
		_check(
			sc.map.terrain_at(it["coord"]) != HexMapScript.Terrain.WATER,
			"city markers not on WATER in this fixture"
		)
		var exp_w = layout.hex_to_world(it["coord"].q, it["coord"].r)
		_check(
			(it["world"] as Vector2).is_equal_approx(exp_w),
			"world position matches layout"
		)
		i = i + 1
	_check(id_seen.get(5, 0) == 1 and id_seen.get(6, 0) == 1, "each city id once")
	var c0: Color
	var c0_set = false
	var c1: Color
	var c1_set = false
	var m2 = 0
	while m2 < items.size():
		var it2 = items[m2]
		if it2["owner_id"] == 0:
			if not c0_set:
				c0 = it2["color"]
				c0_set = true
			_check(
				(it2["color"] as Color).is_equal_approx(c0),
				"owner 0 cities share color"
			)
		if it2["owner_id"] == 1:
			if not c1_set:
				c1 = it2["color"]
				c1_set = true
		m2 = m2 + 1
	_check(c0_set and c1_set, "both owners represented")
	_check(
		not (c1 as Color).is_equal_approx(c0),
		"owner colors differ"
	)
	_check(CitiesViewScript.compute_marker_items(null, layout).size() == 0, "null scenario")
	_check(CitiesViewScript.compute_marker_items(sc, null).size() == 0, "null layout")
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
