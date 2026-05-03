# Headless: MapView suppresses back-forest when TerrainForegroundView.forest_grid_debug_isolated is on.
# Usage: godot --headless --path game -s res://presentation/tests/test_forest_grid_isolated_map_back.gd
extends SceneTree

const MapViewScript = preload("res://presentation/map_view.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")


func _init() -> void:
	var mv = MapViewScript.new()
	var tfv = TerrainForegroundViewScript.new()
	tfv.forest_grid_debug_isolated = false
	tfv.forest_grid_debug_perfect = false
	tfv.forest_grid_debug_suppress_map_back = false
	mv.terrain_foreground_view = tfv
	if mv._forest_grid_map_back_suppressed():
		push_error("FAIL: back should not suppress when isolated/off and no env")
		call_deferred("quit", 1)
		return
	tfv.forest_grid_debug_isolated = true
	mv.terrain_foreground_view = tfv
	if not mv._forest_grid_map_back_suppressed():
		push_error("FAIL: back should suppress when forest_grid_debug_isolated")
		call_deferred("quit", 1)
		return
	tfv.forest_grid_debug_isolated = false
	tfv.forest_grid_debug_perfect = true
	mv.terrain_foreground_view = tfv
	if not mv._forest_grid_map_back_suppressed():
		push_error(
			"FAIL: back should suppress when forest_grid_debug_perfect export (inspector), without env"
		)
		call_deferred("quit", 1)
		return
	print("PASS forest_grid_isolated_map_back")
	call_deferred("quit", 0)
