# Headless: **main.tscn** — map **Node2D** draw siblings stay **MapView → CityTerritoryView → CitiesView → SelectionView → UnitsView → TerrainForegroundView → LightningTreeView → TileYieldOverlayView → CityNameplateView → UnitNameplateView** (then **SelectionController**; **HudCanvas** is separate **CanvasLayer**).
# **CityTerritoryView** (**`z_index` 0**) is **on the base map** under cities, units, foreground trees / lightning, yields, and nameplates (**presentation polish**, union border only).
# Phase **5.1.15b:** **CityNameplateView** is **before** **UnitNameplateView** (same **`z_index` 2**) so **unit** nameplates paint **above** city banners on shared hexes.
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
	var key_territory = '[node name="CityTerritoryView"'
	var key_cities = '[node name="CitiesView"'
	var key_sel = '[node name="SelectionView"'
	var key_units = '[node name="UnitsView"'
	var key_tfv = '[node name="TerrainForegroundView"'
	var key_lightning = '[node name="LightningTreeView"'
	var key_yield = '[node name="TileYieldOverlayView"'
	var key_cn = '[node name="CityNameplateView"'
	var key_un = '[node name="UnitNameplateView"'
	var key_selctl = '[node name="SelectionController"'
	var i_map = text.find(key_map)
	var i_territory = text.find(key_territory)
	var i_cities = text.find(key_cities)
	var i_sel = text.find(key_sel)
	var i_units = text.find(key_units)
	var i_tfv = text.find(key_tfv)
	var i_lightning = text.find(key_lightning)
	var i_yield = text.find(key_yield)
	var i_cn = text.find(key_cn)
	var i_un = text.find(key_un)
	var i_selctl = text.find(key_selctl)
	if (
		i_map < 0
		or i_territory < 0
		or i_cities < 0
		or i_sel < 0
		or i_units < 0
		or i_tfv < 0
		or i_lightning < 0
		or i_yield < 0
		or i_cn < 0
		or i_un < 0
		or i_selctl < 0
	):
		push_error("FAIL: missing expected Main child node declaration in main.tscn")
		call_deferred("quit", 1)
		return
	if not (
		i_map < i_territory
		and i_territory < i_cities
		and i_cities < i_sel
		and i_sel < i_units
		and i_units < i_tfv
		and i_tfv < i_lightning
		and i_lightning < i_yield
		and i_yield < i_cn
		and i_cn < i_un
		and i_un < i_selctl
	):
		push_error(
			(
				"FAIL: map layer sibling order in main.tscn expected MapView < CityTerritoryView < CitiesView < SelectionView < UnitsView < TerrainForegroundView < LightningTreeView < TileYieldOverlayView < CityNameplateView < UnitNameplateView < SelectionController; got indices %s"
				% [str([i_map, i_territory, i_cities, i_sel, i_units, i_tfv, i_lightning, i_yield, i_cn, i_un, i_selctl])]
			)
		)
		call_deferred("quit", 1)
		return
	print("PASS main_tscn_map_layer_sibling_order")
	call_deferred("quit", 0)
