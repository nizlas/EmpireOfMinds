# Headless: isolated forest grid must not enqueue debug overlays unless explicit draw/trace flags are on.
# Usage: godot --headless --path game -s res://presentation/tests/test_tfv_overlay_gating.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")


func _reset_overlay_flush_statics() -> void:
	TerrainForegroundViewScript.debug_last_overlay_flush_roots = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_circles = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_vectors = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_labels = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_tree_effective = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_unit_raw = -1
	TerrainForegroundViewScript.debug_last_overlay_flush_unit_effective = -1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_reset_overlay_flush_statics()
	var rt: Node = get_root()
	var tfv = TerrainForegroundViewScript.new()
	rt.add_child(tfv)
	tfv.map = HexMapScript.make_tiny_test_map()
	tfv.layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	tfv.camera = cam
	tfv.scenario = null
	tfv.forest_density_ratio = 1.0
	tfv.use_forest_symbol_scatter = true
	tfv.forest_grid_debug_isolated = true
	tfv.forest_grid_debug_isolated_one_hex = true
	tfv.forest_grid_debug_suppress_map_back = true
	tfv.forest_grid_debug_perfect = false
	tfv.forest_grid_debug_log = false
	tfv.forest_grid_debug_draw_roots = false
	tfv.forest_grid_debug_draw_jitter_circles = false
	tfv.forest_grid_debug_draw_jitter_displacement_vectors = false
	tfv.forest_grid_debug_trace_pipeline = false
	tfv.forest_grid_debug_log_grid_jitter_slots = false
	tfv.forest_grid_debug_draw_slot_labels = false
	tfv.forest_grid_debug_exaggerated_layout_probe = false
	tfv.debug_draw_effective_depth_points = false
	tfv.debug_draw_unit_png_bottom_center = false
	tfv.debug_unit_tree_draw_ownership = false
	TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn = -1
	await process_frame
	tfv.queue_redraw()
	await process_frame
	var sym: int = TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn
	rt.remove_child(tfv)
	tfv.queue_free()
	if sym != TerrainForegroundViewScript.forest_grid_slot_count():
		push_error(
			"FAIL: overlay gating expected %d grid symbols in isolated mode got %d"
			% [TerrainForegroundViewScript.forest_grid_slot_count(), sym]
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_roots != 0:
		push_error(
			"FAIL: expected flush roots=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_roots
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_circles != 0:
		push_error(
			"FAIL: expected flush circles=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_circles
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_vectors != 0:
		push_error(
			"FAIL: expected flush vectors=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_vectors
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_labels != 0:
		push_error(
			"FAIL: expected flush labels=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_labels
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_tree_effective != 0:
		push_error(
			"FAIL: expected flush tree_effective=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_tree_effective
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_unit_raw != 0:
		push_error(
			"FAIL: expected flush unit_raw=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_unit_raw
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_overlay_flush_unit_effective != 0:
		push_error(
			"FAIL: expected flush unit_effective=0 got %d"
			% TerrainForegroundViewScript.debug_last_overlay_flush_unit_effective
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_isolated_grid_root_markers_drawn != 0:
		push_error(
			"FAIL: expected grid root markers drawn=0 got %d"
			% TerrainForegroundViewScript.debug_last_isolated_grid_root_markers_drawn
		)
		call_deferred("quit", 1)
		return
	print("PASS tfv_overlay_gating")
	call_deferred("quit", 0)
