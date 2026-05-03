# Headless: **TerrainForegroundView** **`visual_mode` → resolved** isolated / one_hex / suppress_map_back;
# **`MapView._forest_grid_map_back_suppressed`** follows resolved helpers.
# Usage: godot --headless --path game -s res://presentation/tests/test_visual_mode_resolver.gd
extends SceneTree

const MapViewScript = preload("res://presentation/map_view.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")


func _init() -> void:
	var holder = Node2D.new()
	get_root().add_child(holder)

	var tfv = TerrainForegroundViewScript.new()
	holder.add_child(tfv)
	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.PRODUCTION
	tfv.forest_grid_debug_isolated = false
	tfv.forest_grid_debug_isolated_one_hex = true
	tfv.forest_grid_debug_suppress_map_back = false
	tfv.forest_grid_debug_draw_roots = false
	tfv.forest_grid_debug_draw_jitter_circles = false
	tfv.forest_grid_debug_draw_jitter_displacement_vectors = false
	tfv.forest_grid_debug_trace_pipeline = false
	tfv.forest_grid_debug_log_grid_jitter_slots = false
	tfv.forest_grid_debug_draw_slot_labels = false
	tfv.forest_grid_debug_log = false
	if tfv.resolved_forest_grid_debug_isolated():
		push_error("FAIL: PRODUCTION default exports expected resolved isolated=false")
		_fail_quit(holder)
		return
	if tfv.resolved_forest_grid_debug_suppress_map_back():
		push_error("FAIL: PRODUCTION expected resolved suppress_map_back=false")
		_fail_quit(holder)
		return
	if tfv._fg_debug_low_level_exports_enabled():
		push_error(
			"FAIL: PRODUCTION without isolated export should have _fg_debug_low_level_exports_enabled()==false"
		)
		_fail_quit(holder)
		return
	if tfv._fg_effective_draw_jitter_circles():
		push_error("FAIL: PRODUCTION should not enable jitter circles when export off / low-level disabled")
		_fail_quit(holder)
		return

	tfv.forest_grid_debug_isolated = true
	if not tfv._fg_debug_low_level_exports_enabled():
		push_error("FAIL: PRODUCTION with isolated export true should enable low-level exports")
		_fail_quit(holder)
		return
	tfv.forest_grid_debug_isolated = false

	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.FOREST_SINGLE_HEX_DEBUG
	tfv.forest_grid_debug_isolated = false
	if not tfv._fg_debug_low_level_exports_enabled():
		push_error("FAIL: FOREST_SINGLE_HEX_DEBUG should enable low-level export gate (non-PRODUCTION)")
		_fail_quit(holder)
		return
	if not tfv.resolved_forest_grid_debug_isolated():
		push_error("FAIL: FOREST_SINGLE_HEX_DEBUG expected resolved isolated=true")
		_fail_quit(holder)
		return
	if not tfv.resolved_forest_grid_debug_isolated_one_hex():
		push_error("FAIL: FOREST_SINGLE_HEX_DEBUG expected resolved one_hex=true")
		_fail_quit(holder)
		return
	if not tfv.resolved_forest_grid_debug_suppress_map_back():
		push_error("FAIL: FOREST_SINGLE_HEX_DEBUG expected resolved suppress=true")
		_fail_quit(holder)
		return

	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.FOREST_CLUSTER_DEBUG
	if not tfv.resolved_forest_grid_debug_isolated():
		push_error("FAIL: FOREST_CLUSTER_DEBUG expected resolved isolated=true")
		_fail_quit(holder)
		return
	if tfv.resolved_forest_grid_debug_isolated_one_hex():
		push_error("FAIL: FOREST_CLUSTER_DEBUG expected resolved one_hex=false")
		_fail_quit(holder)
		return
	if not tfv.resolved_forest_grid_debug_suppress_map_back():
		push_error("FAIL: FOREST_CLUSTER_DEBUG expected resolved suppress=true")
		_fail_quit(holder)
		return

	var mv = MapViewScript.new()
	holder.add_child(mv)
	mv.terrain_foreground_view = tfv
	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.PRODUCTION
	tfv.forest_grid_debug_isolated = false
	tfv.forest_grid_debug_suppress_map_back = false
	if mv._forest_grid_map_back_suppressed():
		push_error("FAIL: MapView not suppressed when PRODUCTION + isolated off + suppress off")
		_fail_quit(holder)
		return
	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.FOREST_SINGLE_HEX_DEBUG
	if not mv._forest_grid_map_back_suppressed():
		push_error("FAIL: MapView should suppress when FOREST_SINGLE_HEX_DEBUG")
		_fail_quit(holder)
		return
	tfv.visual_mode = TerrainForegroundViewScript.VisualMode.FOREST_CLUSTER_DEBUG
	if not mv._forest_grid_map_back_suppressed():
		push_error("FAIL: MapView should suppress when FOREST_CLUSTER_DEBUG")
		_fail_quit(holder)
		return

	print("PASS test_visual_mode_resolver")
	call_deferred("_pass_quit", holder)


func _fail_quit(holder: Node) -> void:
	holder.queue_free()
	call_deferred("quit", 1)


func _pass_quit(holder: Node) -> void:
	holder.queue_free()
	call_deferred("quit", 0)
