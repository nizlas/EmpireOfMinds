# Immutable bundle of HexMap, units, and cities. Optional monotonic id counters for replay (explicit pass-forward on rebuild).
# Not a Node, not an autoload; not global game state. See docs/UNITS.md, docs/CITIES.md
class_name Scenario
extends RefCounted

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const _SCENARIO_SCRIPT = preload("res://domain/scenario.gd")

var map
var _units: Array
var _cities: Array
var _next_unit_id: int
var _next_city_id: int


static func _max_unit_id(units: Array) -> int:
	var mx = 0
	var i = 0
	while i < units.size():
		var u = units[i]
		if u.id > mx:
			mx = u.id
		i = i + 1
	return mx


static func _max_city_id(cities: Array) -> int:
	var mx = 0
	var i = 0
	while i < cities.size():
		var c = cities[i]
		if c.id > mx:
			mx = c.id
		i = i + 1
	return mx


func _init(
	p_map,
	p_units: Array,
	p_cities: Array = [],
	p_next_unit_id: int = -1,
	p_next_city_id: int = -1
) -> void:
	assert(p_map != null, "Scenario requires a map")
	var seen_u = {}
	var i = 0
	while i < p_units.size():
		var u = p_units[i]
		assert(u != null, "Scenario units must not be null")
		assert(p_map.has(u.position), "Unit position must be on the map")
		assert(not seen_u.has(u.id), "Unit ids must be unique within a scenario")
		seen_u[u.id] = true
		i = i + 1
	var seen_c = {}
	var seen_city_hex = {}
	var ci = 0
	while ci < p_cities.size():
		var cty = p_cities[ci]
		assert(cty != null, "Scenario cities must not be null")
		assert(p_map.has(cty.position), "City position must be on the map")
		assert(
			p_map.terrain_at(cty.position) != HexMapScript.Terrain.WATER,
			"City cannot be placed on WATER"
		)
		assert(not seen_c.has(cty.id), "City ids must be unique within a scenario")
		seen_c[cty.id] = true
		var hk = Vector2i(cty.position.q, cty.position.r)
		assert(not seen_city_hex.has(hk), "At most one city per hex")
		seen_city_hex[hk] = true
		ci = ci + 1
	map = p_map
	_units = p_units.duplicate()
	_cities = p_cities.duplicate()
	if p_next_unit_id < 0:
		_next_unit_id = _max_unit_id(p_units) + 1
	else:
		assert(
			p_next_unit_id > _max_unit_id(p_units),
			"next_unit_id must stay above all existing unit ids (replay-safe)"
		)
		_next_unit_id = p_next_unit_id
	if p_next_city_id < 0:
		_next_city_id = _max_city_id(p_cities) + 1
	else:
		assert(
			p_next_city_id > _max_city_id(p_cities),
			"next_city_id must stay above all existing city ids (replay-safe)"
		)
		_next_city_id = p_next_city_id


func peek_next_unit_id() -> int:
	return _next_unit_id


func peek_next_city_id() -> int:
	return _next_city_id


func units() -> Array:
	return _units.duplicate()


func unit_by_id(p_id: int):
	for u in _units:
		if u.id == p_id:
			return u
	return null


func units_at(coord) -> Array:
	var out = []
	var u = 0
	while u < _units.size():
		if _units[u].position.equals(coord):
			out.append(_units[u])
		u = u + 1
	return out


func units_owned_by(owner_id: int) -> Array:
	var out = []
	var u = 0
	while u < _units.size():
		if _units[u].owner_id == owner_id:
			out.append(_units[u])
		u = u + 1
	return out


func cities() -> Array:
	return _cities.duplicate()


func city_by_id(p_id: int):
	for c in _cities:
		if c.id == p_id:
			return c
	return null


func cities_at(coord) -> Array:
	var out = []
	var k = 0
	while k < _cities.size():
		if _cities[k].position.equals(coord):
			out.append(_cities[k])
		k = k + 1
	return out


func cities_owned_by(owner_id: int) -> Array:
	var out = []
	var k = 0
	while k < _cities.size():
		if _cities[k].owner_id == owner_id:
			out.append(_cities[k])
		k = k + 1
	return out


static func make_tiny_test_scenario():
	var m = HexMapScript.make_tiny_test_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0), "warrior"),
		UnitScript.new(3, 1, HexCoordScript.new(0, -1), "settler"),
	]
	return _SCENARIO_SCRIPT.new(m, us)
