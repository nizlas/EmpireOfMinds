# Headless: godot --headless --path game -s res://domain/tests/test_prototype_play_map_distribution.gd
extends SceneTree
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var R: int = 7
	var exp_n: int = 1 + 3 * R * (R + 1)
	var m = HexMapScript.make_prototype_play_map()
	_check(m.size() == exp_n, "prototype disk cell count")
	var c00 = HexCoordScript.new(0, 0)
	var cw = HexCoordScript.new(-1, 0)
	_check(m.terrain_at(c00) == HexMapScript.Terrain.PLAINS, "(0,0) PLAINS")
	_check(m.landform_at(c00) == HexMapScript.Landform.FLAT, "(0,0) FLAT")
	_check(m.terrain_at(cw) == HexMapScript.Terrain.WATER, "(-1,0) WATER")
	var n_water = 0
	var n_pf = 0
	var n_ph = 0
	var n_gf = 0
	var n_gh = 0
	for c in m.coords():
		var t: int = m.terrain_at(c)
		var lf: int = m.landform_at(c)
		if t == HexMapScript.Terrain.WATER:
			n_water += 1
		elif t == HexMapScript.Terrain.PLAINS and lf == HexMapScript.Landform.FLAT:
			n_pf += 1
		elif t == HexMapScript.Terrain.PLAINS and lf == HexMapScript.Landform.HILLS:
			n_ph += 1
		elif t == HexMapScript.Terrain.GRASSLAND and lf == HexMapScript.Landform.FLAT:
			n_gf += 1
		elif t == HexMapScript.Terrain.GRASSLAND and lf == HexMapScript.Landform.HILLS:
			n_gh += 1
	_check(n_water >= 4, "enough WATER")
	_check(n_pf >= 8, "enough PLAINS+FLAT")
	_check(n_ph >= 8, "enough PLAINS+HILLS")
	_check(n_gf >= 8, "enough GRASSLAND+FLAT")
	_check(n_gh >= 8, "enough GRASSLAND+HILLS")
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
