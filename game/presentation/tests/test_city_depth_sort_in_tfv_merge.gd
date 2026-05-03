# Headless: city **`city_effective_depth_presentation`** == bottom-center of **`city_marker_texture_rect_presentation`** (textured path).
# Usage: godot --headless --path game -s res://presentation/tests/test_city_depth_sort_in_tfv_merge.gd
extends SceneTree

const CitiesViewScript = preload("res://presentation/cities_view.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rt: Node = get_root()
	var cv = CitiesViewScript.new()
	rt.add_child(cv)
	await process_frame
	var anchor_pres: Vector2 = Vector2(412.0, 305.0)
	var pscale: float = 1.0
	var rect: Rect2 = cv.city_marker_texture_rect_presentation(anchor_pres, pscale)
	var eff: Vector2 = cv.city_effective_depth_presentation(anchor_pres, pscale)
	rt.remove_child(cv)
	cv.queue_free()
	if rect.size.x <= 0.0:
		push_error("FAIL: city marker texture not loaded — cannot validate effective depth")
		call_deferred("quit", 1)
		return
	var want: Vector2 = Vector2(
		rect.position.x + rect.size.x * 0.5,
		rect.position.y + rect.size.y
	)
	if not eff.is_equal_approx(want):
		push_error("FAIL: effective depth %s want bottom-center %s" % [eff, want])
		call_deferred("quit", 1)
		return
	print("PASS test_city_depth_sort_in_tfv_merge")
	call_deferred("quit", 0)
