# Headless: **main.tscn** — map **Node2D** draw siblings stay **MapView → CitiesView → SelectionView → UnitsView → TerrainForegroundView** (HudCanvas is separate **CanvasLayer**).
# Usage: godot --headless --path game -s res://presentation/tests/test_main_tscn_map_layer_sibling_order.gd
extends SceneTree


func _init() -> void:
	var f = FileAccess.open("res://main.tscn", FileAccess.READ)
	if f == null:
		push_error("FAIL: could not open res://main.tscn")
		call_deferred("quit", 1)
		return
	var text: String = f.get_as_text()
	f.close()
	var key_map = '[node name="MapView"'
	var key_cities = '[node name="CitiesView"'
	var key_sel = '[node name="SelectionView"'
	var key_units = '[node name="UnitsView"'
	var key_tfv = '[node name="TerrainForegroundView"'
	var i_map = text.find(key_map)
	var i_cities = text.find(key_cities)
	var i_sel = text.find(key_sel)
	var i_units = text.find(key_units)
	var i_tfv = text.find(key_tfv)
	if i_map < 0 or i_cities < 0 or i_sel < 0 or i_units < 0 or i_tfv < 0:
		push_error("FAIL: missing expected Main child node declaration in main.tscn")
		call_deferred("quit", 1)
		return
	if not (i_map < i_cities and i_cities < i_sel and i_sel < i_units and i_units < i_tfv):
		push_error(
			(
				"FAIL: map layer sibling order in main.tscn expected MapView < CitiesView < SelectionView < UnitsView < TerrainForegroundView; got indices %s"
				% [str([i_map, i_cities, i_sel, i_units, i_tfv])]
			)
		)
		call_deferred("quit", 1)
		return
	print("PASS main_tscn_map_layer_sibling_order")
	call_deferred("quit", 0)
