# Headless: godot --headless --path game -s res://presentation/tests/test_map_camera.gd
extends SceneTree
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var p = MapPlaneProjectionScript.new()
	p.plane_y_scale = 0.90
	p.depth_strength = 0.0004
	p.near_world_y = 192.0
	p.vanishing_pres = Vector2(800.0, 322.0)
	var cam0 = MapCameraScript.new()
	cam0.projection = p
	cam0.camera_world_offset = Vector2.ZERO
	var samples = [
		Vector2(0, 0),
		Vector2(200.0, -192.0),
		Vector2(-100.0, 192.0),
		Vector2(111.1, 333.3),
	]
	var i = 0
	while i < samples.size():
		var w = samples[i]
		_check(
			cam0.to_presentation(w).is_equal_approx(p.to_presentation(w)),
			"zero offset to_presentation matches projection for %s" % w
		)
		var s = p.to_presentation(w)
		_check(
			cam0.to_layout(s).is_equal_approx(p.to_layout(s)),
			"zero offset to_layout matches projection for pres from %s" % w
		)
		var ww = 1.0 + p.depth_strength * (p.near_world_y - w.y)
		var expect_sc = 1.0 / ww
		_check(
			is_equal_approx(cam0.perspective_scale_at(w), expect_sc),
			"zero offset perspective_scale_at matches 1/w for %s" % w
		)
		i += 1
	var p2 = MapPlaneProjectionScript.new()
	p2.plane_y_scale = p.plane_y_scale
	p2.depth_strength = p.depth_strength
	p2.near_world_y = p.near_world_y
	p2.vanishing_pres = p.vanishing_pres
	var off = Vector2(55.5, -33.3)
	var cam1 = MapCameraScript.new()
	cam1.projection = p2
	cam1.camera_world_offset = off
	var j = 0
	while j < samples.size():
		var w2 = samples[j]
		var s1 = cam1.to_presentation(w2)
		var back = cam1.to_layout(s1)
		_check(
			back.is_equal_approx(w2),
			"non-zero offset to_layout(to_presentation) round-trip for %s" % w2
		)
		_check(
			is_equal_approx(cam1.perspective_scale_at(w2), p2.perspective_scale_at(w2 - off)),
			"perspective_scale_at uses world - offset for %s" % w2
		)
		j += 1
	var cam_d = MapCameraScript.new()
	var pd = MapPlaneProjectionScript.new()
	pd.plane_y_scale = p.plane_y_scale
	pd.depth_strength = p.depth_strength
	pd.near_world_y = p.near_world_y
	pd.vanishing_pres = p.vanishing_pres
	cam_d.projection = pd
	cam_d.camera_world_offset = Vector2(10.0, 20.0)
	var prev_local = Vector2(401.2, 300.8)
	var cur_local = Vector2(431.2, 300.8)
	var prev_world = cam_d.to_layout(prev_local)
	var cur_world = cam_d.to_layout(cur_local)
	var before = cam_d.to_presentation(prev_world)
	# Keep world point under cursor: new offset so prev_world projects to cur_local.
	cam_d.camera_world_offset += prev_world - cur_world
	_check(
		cam_d.to_presentation(prev_world).is_equal_approx(cur_local),
		"drag invariance: after pan, prev_world projects to cur_local"
	)
	_check(
		before.is_equal_approx(prev_local),
		"drag invariance: before pan, prev_world projected to prev_local"
	)
	var cam_s = MapCameraScript.new()
	var ps = MapPlaneProjectionScript.new()
	ps.plane_y_scale = p.plane_y_scale
	ps.depth_strength = p.depth_strength
	ps.near_world_y = p.near_world_y
	ps.vanishing_pres = p.vanishing_pres
	cam_s.projection = ps
	cam_s.camera_world_offset = Vector2(5.0, 5.0)
	var pl0 = Vector2(400.0, 310.0)
	var pl1 = Vector2(430.0, 310.0)
	var pw0 = cam_s.to_layout(pl0)
	var pw1 = cam_s.to_layout(pl1)
	cam_s.camera_world_offset += pw0 - pw1
	var dx_off = cam_s.camera_world_offset.x - 5.0
	_check(
		not is_equal_approx(dx_off, 0.0),
		"sign sanity: horizontal-only drag should change camera_world_offset.x"
	)

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
