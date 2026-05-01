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
	# --- Phase 4.5n: zoom ---
	var pz = MapPlaneProjectionScript.new()
	pz.plane_y_scale = p.plane_y_scale
	pz.depth_strength = p.depth_strength
	pz.near_world_y = p.near_world_y
	pz.vanishing_pres = p.vanishing_pres
	var cam_z = MapCameraScript.new()
	cam_z.projection = pz
	cam_z.camera_world_offset = Vector2(12.0, -7.0)
	cam_z.set_zoom_clamped(1.35)
	var zi = 0
	while zi < samples.size():
		var wz = samples[zi]
		var back_z = cam_z.to_layout(cam_z.to_presentation(wz))
		# Zoom path stacks two affines around projective projection; allow small FP slack vs. exact world.
		_check(
			back_z.distance_squared_to(wz) < 1e-6,
			"4.5n round-trip zoom+offset for %s" % wz
		)
		var exp_ps = pz.perspective_scale_at(wz - cam_z.camera_world_offset) * cam_z.zoom
		_check(
			is_equal_approx(cam_z.perspective_scale_at(wz), exp_ps),
			"4.5n perspective_scale_at = projection * zoom for %s" % wz
		)
		zi += 1
	# Center-anchored invariant: center_local == vanishing_pres (world under center stable; offset delta ~0)
	var cam_c0 = MapCameraScript.new()
	var pc0 = MapPlaneProjectionScript.new()
	pc0.plane_y_scale = p.plane_y_scale
	pc0.depth_strength = p.depth_strength
	pc0.near_world_y = p.near_world_y
	pc0.vanishing_pres = Vector2(800.0, 322.0)
	cam_c0.projection = pc0
	cam_c0.camera_world_offset = Vector2(20.0, -15.0)
	cam_c0.set_zoom_clamped(1.0)
	var cen_eq_v: Vector2 = pc0.vanishing_pres
	var wb0: Vector2 = cam_c0.to_layout(cen_eq_v)
	var old_z0: float = cam_c0.zoom
	cam_c0.set_zoom_clamped(cam_c0.zoom * 1.25)
	if not is_equal_approx(cam_c0.zoom, old_z0):
		var wa0: Vector2 = cam_c0.to_layout(cen_eq_v)
		if wb0.is_finite() and wa0.is_finite():
			cam_c0.camera_world_offset += wb0 - wa0
	_check(
		cam_c0.to_presentation(wb0).is_equal_approx(cen_eq_v),
		"4.5n center anchor when center_local == vanishing_pres"
	)
	# Center_local != vanishing_pres
	var cam_c1 = MapCameraScript.new()
	var pc1 = MapPlaneProjectionScript.new()
	pc1.plane_y_scale = p.plane_y_scale
	pc1.depth_strength = p.depth_strength
	pc1.near_world_y = p.near_world_y
	pc1.vanishing_pres = Vector2(800.0, 322.0)
	cam_c1.projection = pc1
	cam_c1.camera_world_offset = Vector2(5.0, 8.0)
	cam_c1.set_zoom_clamped(1.0)
	var cen_off: Vector2 = Vector2(920.0, 410.0)
	var wb1: Vector2 = cam_c1.to_layout(cen_off)
	var old_z1: float = cam_c1.zoom
	cam_c1.set_zoom_clamped(cam_c1.zoom * 1.15)
	if not is_equal_approx(cam_c1.zoom, old_z1):
		var wa1: Vector2 = cam_c1.to_layout(cen_off)
		if wb1.is_finite() and wa1.is_finite():
			cam_c1.camera_world_offset += wb1 - wa1
	_check(
		cam_c1.to_presentation(wb1).is_equal_approx(cen_off),
		"4.5n center anchor when center_local != vanishing_pres"
	)
	# Clamp
	var cam_cl = MapCameraScript.new()
	var pcl = MapPlaneProjectionScript.new()
	pcl.plane_y_scale = p.plane_y_scale
	pcl.depth_strength = p.depth_strength
	pcl.near_world_y = p.near_world_y
	pcl.vanishing_pres = p.vanishing_pres
	cam_cl.projection = pcl
	cam_cl.set_zoom_clamped(100.0)
	_check(is_equal_approx(cam_cl.zoom, cam_cl.max_zoom), "4.5n clamp huge to max_zoom")
	cam_cl.set_zoom_clamped(0.01)
	_check(is_equal_approx(cam_cl.zoom, cam_cl.min_zoom), "4.5n clamp tiny to min_zoom")
	cam_cl.set_zoom_clamped(1.42)
	_check(is_equal_approx(cam_cl.zoom, 1.42), "4.5n clamp preserves in-range value")
	# Pan invariant at zoom 1.7
	var cam_pz = MapCameraScript.new()
	var ppz = MapPlaneProjectionScript.new()
	ppz.plane_y_scale = p.plane_y_scale
	ppz.depth_strength = p.depth_strength
	ppz.near_world_y = p.near_world_y
	ppz.vanishing_pres = p.vanishing_pres
	cam_pz.projection = ppz
	cam_pz.camera_world_offset = Vector2(10.0, 20.0)
	cam_pz.set_zoom_clamped(1.7)
	var pl_a = Vector2(401.2, 300.8)
	var pl_b = Vector2(431.2, 300.8)
	var pwa = cam_pz.to_layout(pl_a)
	var pwb = cam_pz.to_layout(pl_b)
	var pbefore = cam_pz.to_presentation(pwa)
	cam_pz.camera_world_offset += pwa - pwb
	_check(
		cam_pz.to_presentation(pwa).is_equal_approx(pl_b),
		"4.5n drag invariance at zoom 1.7"
	)
	_check(pbefore.is_equal_approx(pl_a), "4.5n before pan at zoom 1.7")
	# Safe zoom: direct zoom=0 must not break to_layout for typical local point
	var cam_bad = MapCameraScript.new()
	var pbad = MapPlaneProjectionScript.new()
	pbad.plane_y_scale = p.plane_y_scale
	pbad.depth_strength = p.depth_strength
	pbad.near_world_y = p.near_world_y
	pbad.vanishing_pres = p.vanishing_pres
	cam_bad.projection = pbad
	cam_bad.zoom = 0.0
	var lay_bad: Vector2 = cam_bad.to_layout(Vector2(760.0, 340.0))
	_check(lay_bad.is_finite(), "4.5n safe_zoom: to_layout finite when zoom==0 direct")

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
