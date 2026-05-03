# Headless: **`CitiesView`** skips own-canvas markers when **`terrain_foreground_view`** is valid.
# Usage: godot --headless --path game -s res://presentation/tests/test_cities_view_foreground_delegation.gd
extends SceneTree

const CitiesViewScript = preload("res://presentation/cities_view.gd")


func _init() -> void:
	var cv = CitiesViewScript.new()
	if cv.delegates_city_markers_to_terrain_foreground():
		push_error("FAIL: expected no delegation when TFV unset")
		call_deferred("quit", 1)
		return
	var host = Node2D.new()
	cv.terrain_foreground_view = host
	if not cv.delegates_city_markers_to_terrain_foreground():
		push_error("FAIL: expected delegation when TFV node assigned")
		call_deferred("quit", 1)
		return
	cv.terrain_foreground_view = null
	if cv.delegates_city_markers_to_terrain_foreground():
		push_error("FAIL: expected no delegation after TFV cleared")
		call_deferred("quit", 1)
		return
	host.free()
	print("PASS cities_view_foreground_delegation")
	call_deferred("quit", 0)
