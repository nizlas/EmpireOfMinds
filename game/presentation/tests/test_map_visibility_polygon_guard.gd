# Headless: parchment polygon guards skip degenerate draw polygons.
extends SceneTree

const PolygonDrawGuardScript = preload("res://presentation/polygon_draw_guard.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var valid := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 80), Vector2(0, 80),
	])
	_check(
		PolygonDrawGuardScript.polygon_skip_reason(valid) == "",
		"valid quad drawable"
	)
	var dup := PackedVector2Array([
		Vector2(10, 10), Vector2(10, 10), Vector2(50, 10), Vector2(50, 50), Vector2(10, 50),
	])
	var sanitized: Dictionary = PolygonDrawGuardScript.sanitize_polygon_with_uvs(
		dup, PackedVector2Array()
	)
	var dup_pts: PackedVector2Array = sanitized["pts"] as PackedVector2Array
	_check(dup_pts.size() == 4, "sanitize removes consecutive duplicate")
	_check(
		PolygonDrawGuardScript.polygon_skip_reason(dup_pts) == "",
		"sanitized quad still drawable"
	)
	var line := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	_check(
		PolygonDrawGuardScript.polygon_skip_reason(line) == "near_zero_area",
		"collinear points skipped as near_zero_area"
	)
	var two := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	_check(
		PolygonDrawGuardScript.polygon_skip_reason(two) == "too_few_points",
		"two points skipped"
	)
	var nan_pts := PackedVector2Array([Vector2(0, 0), Vector2(NAN, 0), Vector2(10, 10)])
	_check(
		PolygonDrawGuardScript.polygon_skip_reason(nan_pts) == "non_finite_point",
		"NaN point skipped"
	)
	var collapsed := PackedVector2Array([
		Vector2(50, 50),
		Vector2(50.1, 50),
		Vector2(50, 50.1),
		Vector2(50.05, 50.05),
	])
	var collapsed_reason: String = PolygonDrawGuardScript.polygon_skip_reason(collapsed)
	_check(
		collapsed_reason in ["near_zero_area", "too_few_unique_points", "triangulation_failed"],
		"collapsed sub-pixel hex skipped (%s)" % collapsed_reason
	)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS map_visibility_polygon_guard %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
