# Headless: **`UnitsView`** delegates own-canvas markers when **`terrain_foreground_view`** is a valid instance.
# Usage: godot --headless --path game -s res://presentation/tests/test_units_view_foreground_delegation.gd
extends SceneTree

const UnitsViewScript = preload("res://presentation/units_view.gd")


func _init() -> void:
	var uv = UnitsViewScript.new()
	if uv.delegates_unit_markers_to_terrain_foreground():
		push_error("FAIL: expected no delegation when TFV unset")
		call_deferred("quit", 1)
		return
	var host = Node2D.new()
	uv.terrain_foreground_view = host
	if not uv.delegates_unit_markers_to_terrain_foreground():
		push_error("FAIL: expected delegation when TFV node assigned")
		call_deferred("quit", 1)
		return
	uv.terrain_foreground_view = null
	if uv.delegates_unit_markers_to_terrain_foreground():
		push_error("FAIL: expected no delegation after TFV cleared")
		call_deferred("quit", 1)
		return
	host.free()
	print("PASS units_view_foreground_delegation")
	call_deferred("quit", 0)
