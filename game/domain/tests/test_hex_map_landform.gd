# Headless: godot --headless --path game -s res://domain/tests/test_hex_map_landform.gd
extends SceneTree
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var cells = {
		Vector2i(0, 0): HexMapScript.Terrain.PLAINS,
		Vector2i(1, 0): HexMapScript.Terrain.WATER,
	}
	var lf = {Vector2i(1, 0): HexMapScript.Landform.HILLS}
	var m = HexMapScript.new(cells, lf)
	_check(m.landform_at(HexCoordScript.new(0, 0)) == HexMapScript.Landform.FLAT, "omitted key is FLAT")
	_check(m.landform_at(HexCoordScript.new(1, 0)) == HexMapScript.Landform.HILLS, "WATER may still carry landform storage")
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
