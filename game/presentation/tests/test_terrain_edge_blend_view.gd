# Headless: godot --headless --path game -s res://presentation/tests/test_terrain_edge_blend_view.gd
extends SceneTree

const TerrainEdgeBlendViewScript = preload("res://presentation/terrain_edge_blend_view.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
var _total: int = 0
var _any_fail: bool = false


func _item_key(d: Dictionary) -> String:
	return "%d,%d-%d,%d" % [int(d["aq"]), int(d["ar"]), int(d["bq"]), int(d["br"])]


func _lists_equal_determinism(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var i: int = 0
	while i < a.size():
		if _item_key(a[i] as Dictionary) != _item_key(b[i] as Dictionary):
			return false
		i += 1
	return true


func _forbidden_scan_source() -> void:
	var fp: String = "res://presentation/terrain_edge_blend_view.gd"
	var txt: String = FileAccess.get_file_as_string(fp)
	_check(txt.find("Scenario") < 0, "blend view source must not name Scenario")
	_check(txt.find("SelectionState") < 0, "blend view source must not name SelectionState")
	_check(txt.find("CityYields") < 0, "blend view source must not name CityYields")
	_check(txt.find("LegalActions") < 0, "blend view source must not name LegalActions")
	_check(txt.find("EffectiveRules") < 0, "blend view source must not name EffectiveRules")
	_check(txt.find("terrain_foreground_view") < 0, "blend view must not reference TFV")
	_check(txt.find("TerrainForegroundView") < 0, "blend view must not name TerrainForegroundView")
	_check(txt.find("randomize") < 0, "no randomize")
	_check(txt.find("randf") < 0, "no randf")
	_check(txt.find("randi") < 0, "no randi")


func _init() -> void:
	_forbidden_scan_source()

	var tiny_plains: Variant = HexMapScript.make_tiny_test_map()
	var items_plains: Array = TerrainEdgeBlendViewScript.compute_blend_items(tiny_plains)
	var gr_count: int = 0
	var coords_p: Array = tiny_plains.coords()
	var pi: int = 0
	while pi < coords_p.size():
		if int(tiny_plains.terrain_at(coords_p[pi])) == HexMapScript.Terrain.GRASSLAND:
			gr_count += 1
		pi += 1
	_check(gr_count == 0, "tiny map has no grassland fixture")
	_check(items_plains.size() == 0, "uniform plains adjacencies (plus water) yield no PLAINS-GRASSLAND blend edges")

	var two_grass: Dictionary = {
		Vector2i(0, 0): HexMapScript.Terrain.GRASSLAND,
		Vector2i(1, 0): HexMapScript.Terrain.GRASSLAND,
	}
	var map_two_grass = HexMapScript.new(two_grass)
	_check(TerrainEdgeBlendViewScript.compute_blend_items(map_two_grass).size() == 0, "uniform grassland: no blend items")

	var pg: Dictionary = {
		Vector2i(0, 0): HexMapScript.Terrain.PLAINS,
		Vector2i(1, 0): HexMapScript.Terrain.GRASSLAND,
	}
	var map_pg = HexMapScript.new(pg)
	var items_pg: Array = TerrainEdgeBlendViewScript.compute_blend_items(map_pg)
	_check(items_pg.size() == 1, "single shared plains-grassland edge")
	var d0: Dictionary = items_pg[0] as Dictionary
	_check(int(d0["aq"]) == 0 and int(d0["ar"]) == 0 and int(d0["bq"]) == 1 and int(d0["br"]) == 0, "edge lex order")

	var pw: Dictionary = {
		Vector2i(0, 0): HexMapScript.Terrain.PLAINS,
		Vector2i(1, 0): HexMapScript.Terrain.WATER,
	}
	var map_pw = HexMapScript.new(pw)
	_check(TerrainEdgeBlendViewScript.compute_blend_items(map_pw).size() == 0, "water adjacency excluded from v1")

	var again: Array = TerrainEdgeBlendViewScript.compute_blend_items(map_pg)
	_check(_lists_equal_determinism(items_pg, again), "deterministic repeated compute_blend_items")

	_check(TerrainEdgeBlendViewScript.compute_blend_items(null).size() == 0, "null map empty")

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
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
