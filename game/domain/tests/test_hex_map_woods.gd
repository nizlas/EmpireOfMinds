# Headless: godot --headless --path game -s res://domain/tests/test_hex_map_woods.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PrototypeTerrainFeaturesScript = preload("res://domain/prototype_terrain_features.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var tiny = HexMapScript.make_tiny_test_map()
	_check(not tiny.has_woods(HexCoordScript.new(0, 0)), "tiny map center no woods")
	var pm = HexMapScript.make_prototype_play_map()
	_check(
		pm.has_woods(HexCoordScript.new(1, -1)),
		"prototype woods includes canonical smoke cell (1,-1)"
	)
	_check(not pm.has_woods(HexCoordScript.new(0, 0)), "start hex not woods")
	var woods_n: int = 0
	for c in pm.coords():
		if pm.has_woods(c):
			woods_n += 1
	_check(
		woods_n == PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES.size(),
		"woods count matches prototype list"
	)
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
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
