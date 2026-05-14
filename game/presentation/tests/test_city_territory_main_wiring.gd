# Headless: **main** + **SelectionController** wire **CityTerritoryView** for manual play. Usage: godot --headless --path game -s res://presentation/tests/test_city_territory_main_wiring.gd
extends SceneTree


func _init() -> void:
	var fm = FileAccess.open("res://main.gd", FileAccess.READ)
	var ft = FileAccess.open("res://main.tscn", FileAccess.READ)
	if fm == null or ft == null:
		push_error("FAIL: could not open main.gd / main.tscn")
		call_deferred("quit", 1)
		return
	var g: String = fm.get_as_text()
	var t: String = ft.get_as_text()
	fm.close()
	ft.close()
	if g.find("city_territory_view.selection = selection") < 0:
		push_error("FAIL: main.gd must assign city_territory_view.selection = selection (same instance as controller)")
		call_deferred("quit", 1)
		return
	if g.find("$CityTerritoryView") < 0 or g.find("queue_redraw()") < 0:
		push_error("FAIL: main.gd should reference $CityTerritoryView and queue_redraw")
		call_deferred("quit", 1)
		return
	if g.find("$CityTerritoryView.queue_redraw()") < 0:
		push_error("FAIL: _redraw_map_layers must include $CityTerritoryView.queue_redraw()")
		call_deferred("quit", 1)
		return
	var i_loop: int = g.find("for n in [")
	if i_loop < 0 or g.find("$CityTerritoryView", i_loop) < 0:
		push_error("FAIL: main.gd MAP_LAYER_ORIGIN loop should include $CityTerritoryView")
		call_deferred("quit", 1)
		return
	var i_ct: int = t.find('[node name="CityTerritoryView"')
	if i_ct < 0:
		push_error("FAIL: main.tscn missing CityTerritoryView node")
		call_deferred("quit", 1)
		return
	var slice_len: int = min(420, t.length() - i_ct)
	var chunk: String = t.substr(i_ct, slice_len)
	if chunk.find("z_index = 0") < 0:
		push_error("FAIL: CityTerritoryView should have z_index = 0 in main.tscn (map surface under foreground)")
		call_deferred("quit", 1)
		return
	if chunk.find("city_territory_view.gd") < 0 and chunk.find("21_cityterritory") < 0:
		push_error("FAIL: CityTerritoryView script resource missing in node block")
		call_deferred("quit", 1)
		return
	var fc = FileAccess.open("res://presentation/selection_controller.gd", FileAccess.READ)
	if fc == null:
		push_error("FAIL: selection_controller.gd")
		call_deferred("quit", 1)
		return
	var sc: String = fc.get_as_text()
	fc.close()
	if sc.find("var city_territory_view") < 0:
		push_error("FAIL: SelectionController needs city_territory_view field")
		call_deferred("quit", 1)
		return
	if sc.find("func _refresh_city_territory_view()") < 0:
		push_error("FAIL: SelectionController needs _refresh_city_territory_view()")
		call_deferred("quit", 1)
		return
	var i_map: int = t.find('[node name="MapView"')
	var i_cities: int = t.find('[node name="CitiesView"')
	if i_map < 0 or not (i_map < i_ct and i_ct < i_cities):
		push_error("FAIL: sibling order MapView < CityTerritoryView < CitiesView in tscn text")
		call_deferred("quit", 1)
		return
	var i_y: int = t.find('[node name="TileYieldOverlayView"')
	if not (i_ct < i_y):
		push_error("FAIL: sibling order CityTerritoryView < TileYieldOverlayView in tscn text")
		call_deferred("quit", 1)
		return
	print("PASS city_territory_main_wiring")
	call_deferred("quit", 0)
