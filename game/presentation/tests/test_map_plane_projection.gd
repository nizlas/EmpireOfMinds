# Headless: godot --headless --path game -s res://presentation/tests/test_map_plane_projection.gd
extends SceneTree
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var p = MapPlaneProjectionScript.new()
	p.plane_y_scale = 0.90
	p.depth_strength = 0.0004
	p.near_world_y = 192.0
	p.vanishing_pres = Vector2(800.0, 322.0)
	var samples = [
		Vector2(0, 0),
		Vector2(200.0, -192.0),
		Vector2(-100.0, 192.0),
		Vector2(111.1, 333.3),
	]
	var i = 0
	while i < samples.size():
		var w = samples[i]
		var s = p.to_presentation(w)
		var back = p.to_layout(s)
		_check(
			back.is_equal_approx(w),
			"to_layout(to_presentation) round-trip for %s" % w
		)
		var ww = 1.0 + p.depth_strength * (p.near_world_y - w.y)
		var expect_sc = 1.0 / ww
		_check(
			is_equal_approx(p.perspective_scale_at(w), expect_sc),
			"perspective_scale_at matches 1/w for %s" % w
		)
		i = i + 1
	_check(p.plane_y_scale != 0.0, "plane_y_scale non-zero")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
