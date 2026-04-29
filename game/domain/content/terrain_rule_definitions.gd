# Immutable terrain rule definitions for movement legality. See docs/CONTENT_MODEL.md, docs/MAP_MODEL.md.
# HexMap stores enum tags; this registry maps them to passability and future movement_cost (range unchanged in 3.2).
class_name TerrainRuleDefinitions
extends RefCounted

const _HexMapScript = preload("res://domain/hex_map.gd")

const TERRAIN_ID_UNKNOWN: String = ""

const _ORDERED_IDS: Array = ["plains", "water"]

const _DEFINITIONS: Dictionary = {
	"plains":
	{
		"id": "plains",
		"display_name": "Plains",
		"passable": true,
		"movement_cost": 1,
		"role": "default_land",
	},
	"water":
	{
		"id": "water",
		"display_name": "Water",
		"passable": false,
		"movement_cost": 999,
		"role": "blocked",
	},
}


static func has(id: String) -> bool:
	return _DEFINITIONS.has(id)


static func ids() -> Array:
	return _ORDERED_IDS.duplicate()


static func get_definition(id: String):
	if not _DEFINITIONS.has(id):
		return null
	var src = _DEFINITIONS[id] as Dictionary
	return src.duplicate(true)


static func is_passable(id: String) -> bool:
	if not _DEFINITIONS.has(id):
		return false
	var d = _DEFINITIONS[id] as Dictionary
	return bool(d.get("passable", false))


static func movement_cost(id: String) -> int:
	if not _DEFINITIONS.has(id):
		return 999
	return int((_DEFINITIONS[id] as Dictionary).get("movement_cost", 999))


static func terrain_id_for_hex_map_value(value: int) -> String:
	if value == _HexMapScript.Terrain.PLAINS:
		return "plains"
	if value == _HexMapScript.Terrain.WATER:
		return "water"
	return TERRAIN_ID_UNKNOWN


static func is_passable_hex_map_value(value: int) -> bool:
	return is_passable(terrain_id_for_hex_map_value(value))
