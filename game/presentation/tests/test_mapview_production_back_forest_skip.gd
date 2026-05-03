# Headless: MapView skips decorated-plains **back** forest when **TerrainForegroundView** is wired.
# Usage: godot --headless --path game -s res://presentation/tests/test_mapview_production_back_forest_skip.gd
extends SceneTree

const MapViewScript = preload("res://presentation/map_view.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")


func _init() -> void:
	var mv = MapViewScript.new()
	var tfv = TerrainForegroundViewScript.new()
	mv.terrain_foreground_view = null
	if mv._mapview_skip_back_forest_overlay():
		push_error("FAIL: skip should be false when TFV unwired")
		call_deferred("quit", 1)
		return
	mv.terrain_foreground_view = tfv
	if not mv._mapview_skip_back_forest_overlay():
		push_error("FAIL: skip should be true when TFV wired")
		call_deferred("quit", 1)
		return
	tfv.forest_grid_debug_isolated = true
	mv.terrain_foreground_view = tfv
	if not mv._forest_grid_map_back_suppressed():
		push_error("FAIL: isolated TFV should suppress via _forest_grid_map_back_suppressed")
		call_deferred("quit", 1)
		return
	tfv.forest_grid_debug_isolated = false
	if mv._forest_grid_map_back_suppressed():
		push_error("FAIL: plain TFV should not hit debug suppression with defaults")
		call_deferred("quit", 1)
		return
	print("PASS test_mapview_production_back_forest_skip")
	call_deferred("quit", 0)
