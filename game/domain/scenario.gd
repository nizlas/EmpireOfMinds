# Immutable bundle of a HexMap and a fixed unit list. Not a Node, not an autoload; not global game state.
# See docs/UNITS.md
class_name Scenario
extends RefCounted

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const _SCENARIO_SCRIPT = preload("res://domain/scenario.gd")

var map
var _units: Array

func _init(p_map, p_units: Array) -> void:
	assert(p_map != null, "Scenario requires a map")
	var seen_ids = {}
	var i = 0
	while i < p_units.size():
		var u = p_units[i]
		assert(u != null, "Scenario units must not be null")
		assert(p_map.has(u.position), "Unit position must be on the map")
		assert(not seen_ids.has(u.id), "Unit ids must be unique within a scenario")
		seen_ids[u.id] = true
		i = i + 1
	map = p_map
	_units = p_units.duplicate()

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

static func make_tiny_test_scenario():
	var m = HexMapScript.make_tiny_test_map()
	var us = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0)),
		UnitScript.new(3, 1, HexCoordScript.new(0, -1)),
	]
	return _SCENARIO_SCRIPT.new(m, us)
