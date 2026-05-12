# Headless: **TerrainForegroundView** depth-merge — same-hex **city+unit** orders **city** before **unit**
# (including **microfloat** **sy/sx** splits — **5.1.15c**) so units paint **on top** of city markers.
# Usage: godot --headless --path game -s res://presentation/tests/test_tfv_depth_merge_city_unit_sort_keys.gd
extends SceneTree

const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")
const CityScript = preload("res://domain/city.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")


func _init() -> void:
	var tfv = TerrainForegroundViewScript.new()
	var h = HexCoordScript.new(0, 0)
	var city = CityScript.new(10, 1, h, null)
	var unit = UnitScript.new(20, 1, h, "warrior")
	var sy: float = 12.375
	var sx: float = -4.125
	var items: Array = [
		{"ty": 2, "sy": sy, "sx": sx, "ui": 0, "u": unit},
		{"ty": 1, "sy": sy, "sx": sx, "c": city},
	]
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return tfv._fg_depth_merge_item_lt(a, b)
	)
	if int(items[0]["ty"]) != 1:
		push_error("FAIL: expected city (ty=1) first when merge keys tie")
		tfv.free()
		call_deferred("quit", 1)
		return
	if int(items[1]["ty"]) != 2:
		push_error("FAIL: expected unit (ty=2) second when merge keys tie")
		tfv.free()
		call_deferred("quit", 1)
		return
	items = [
		{"ty": 1, "sy": sy, "sx": sx, "c": city},
		{"ty": 2, "sy": sy, "sx": sx, "ui": 0, "u": unit},
	]
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return tfv._fg_depth_merge_item_lt(a, b)
	)
	if int(items[0]["ty"]) != 1 or int(items[1]["ty"]) != 2:
		push_error("FAIL: sort should be stable for city-first input too")
		tfv.free()
		call_deferred("quit", 1)
		return
	# **5.1.15c:** without same-hex override, a **tiny** `sy` split would put the **unit** first (**behind**).
	items = [
		{"ty": 2, "sy": sy - 0.0004, "sx": sx, "ui": 0, "u": unit},
		{"ty": 1, "sy": sy + 0.0001, "sx": sx + 0.0002, "c": city},
	]
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return tfv._fg_depth_merge_item_lt(a, b)
	)
	if int(items[0]["ty"]) != 1 or int(items[1]["ty"]) != 2:
		push_error("FAIL: same-hex city+unit must sort city before unit despite microfloat sy/sx split")
		tfv.free()
		call_deferred("quit", 1)
		return
	tfv.free()
	print("PASS tfv_depth_merge_city_unit_sort_keys")
	call_deferred("quit", 0)
