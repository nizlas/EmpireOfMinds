# Headless: godot --headless --path game -s res://domain/tests/test_terrain_rule_definitions.gd
extends SceneTree

const TerrainRuleDefinitionsScript = preload("res://domain/content/terrain_rule_definitions.gd")
const HexMapScript = preload("res://domain/hex_map.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(TerrainRuleDefinitionsScript.has("plains"), "has plains")
	_check(TerrainRuleDefinitionsScript.has("water"), "has water")
	_check(not TerrainRuleDefinitionsScript.has("forest"), "no forest")

	var ids0 = TerrainRuleDefinitionsScript.ids() as Array
	_check(ids0.size() == 2 and ids0[0] == "plains" and ids0[1] == "water", "ids order")

	ids0.append("bogus")
	var ids1 = TerrainRuleDefinitionsScript.ids() as Array
	_check(
		ids1.size() == 2 and ids1[0] == "plains" and ids1[1] == "water",
		"ids duplicate safe"
	)

	var dp = TerrainRuleDefinitionsScript.get_definition("plains") as Dictionary
	_check(dp["id"] == "plains", "plains id")
	_check(dp["display_name"] == "Plains", "plains display_name")
	_check(bool(dp["passable"]), "plains passable")
	_check(int(dp["movement_cost"]) == 1, "plains movement_cost")
	_check(dp["role"] == "default_land", "plains role")

	var dw = TerrainRuleDefinitionsScript.get_definition("water") as Dictionary
	_check(dw["id"] == "water", "water id")
	_check(dw["display_name"] == "Water", "water display_name")
	_check(not bool(dw["passable"]), "water passable")
	_check(int(dw["movement_cost"]) == 999, "water movement_cost")
	_check(dw["role"] == "blocked", "water role")

	_check(TerrainRuleDefinitionsScript.get_definition("nope") == null, "unknown null")

	var dup1 = TerrainRuleDefinitionsScript.get_definition("plains") as Dictionary
	dup1["display_name"] = "mutated"
	var dup2 = TerrainRuleDefinitionsScript.get_definition("plains") as Dictionary
	_check(dup2["display_name"] == "Plains", "deep dup independent")

	_check(TerrainRuleDefinitionsScript.is_passable("plains"), "is_passable plains")
	_check(not TerrainRuleDefinitionsScript.is_passable("water"), "is_passable water")
	_check(not TerrainRuleDefinitionsScript.is_passable("nope"), "is_passable unknown")

	_check(TerrainRuleDefinitionsScript.movement_cost("plains") == 1, "cost plains")
	_check(TerrainRuleDefinitionsScript.movement_cost("water") == 999, "cost water")
	_check(TerrainRuleDefinitionsScript.movement_cost("nope") == 999, "cost unknown")

	_check(
		TerrainRuleDefinitionsScript.terrain_id_for_hex_map_value(HexMapScript.Terrain.PLAINS)
		== "plains",
		"enum plains id"
	)
	_check(
		TerrainRuleDefinitionsScript.terrain_id_for_hex_map_value(HexMapScript.Terrain.WATER)
		== "water",
		"enum water id"
	)
	_check(TerrainRuleDefinitionsScript.terrain_id_for_hex_map_value(99) == "", "unknown enum id")

	_check(
		TerrainRuleDefinitionsScript.is_passable_hex_map_value(HexMapScript.Terrain.PLAINS),
		"hex passable plains"
	)
	_check(
		not TerrainRuleDefinitionsScript.is_passable_hex_map_value(HexMapScript.Terrain.WATER),
		"hex passable water"
	)
	_check(
		not TerrainRuleDefinitionsScript.is_passable_hex_map_value(99),
		"hex passable unknown enum"
	)

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
