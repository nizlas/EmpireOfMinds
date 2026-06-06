# Dependency line layer for tech-tree preview (presentation only).
class_name TechTreeDependencyLines
extends Control

var polylines: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_polylines(entries: Array) -> void:
	polylines = entries
	queue_redraw()


func _draw() -> void:
	var i: int = 0
	while i < polylines.size():
		var entry: Dictionary = polylines[i] as Dictionary
		var points: PackedVector2Array = entry.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2:
			i += 1
			continue
		var width: float = float(entry.get("width", 4.0))
		draw_polyline(points, Color(0.04, 0.04, 0.05, 1.0), width, true)
		i += 1
