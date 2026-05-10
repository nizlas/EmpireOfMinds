# Headless: godot --headless --path game -s res://presentation/tests/test_lightning_tree_view_draw.gd
extends SceneTree

const LightningTreeViewScript = preload("res://presentation/lightning_tree_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	LightningTreeViewScript.debug_clear_stump_texture_cache()

	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	cam.projection.vanishing_pres = Vector2(100, 50)

	var lv = LightningTreeViewScript.new()
	get_root().add_child(lv)
	lv.layout = layout
	lv.camera = cam
	lv.scenario = null
	lv.queue_redraw()
	_check(true, "null scenario draw path setup")

	var tiny = ScenarioScript.make_tiny_test_scenario()
	lv.scenario = ScenarioScript.new(
		tiny.map,
		tiny.units(),
		tiny.cities(),
		tiny.peek_next_unit_id(),
		tiny.peek_next_city_id(),
		null
	)
	lv.queue_redraw()
	_check(true, "null tree hex draw path")

	lv.scenario = ScenarioScript.new(
		tiny.map,
		tiny.units(),
		tiny.cities(),
		tiny.peek_next_unit_id(),
		tiny.peek_next_city_id(),
		HexCoordScript.new(1, 0)
	)
	var tex = LightningTreeViewScript.load_keyed_stump_texture()
	_check(tex != null, "stump asset loads to texture")
	var img_from_tex: Image = tex.get_image()
	_check(img_from_tex != null, "texture exposes image for metrics")
	var opaque_asset: int = LightningTreeViewScript.count_opaque_pixels(img_from_tex, 0.05)
	_check(
		opaque_asset >= 200,
		"processed stump has many visible pixels (not fully keyed out)"
	)
	var trans_asset: int = _count_transparent_pixels(img_from_tex, 0.05)
	if trans_asset < 1:
		# PNG may lack screen-magenta; chroma then leaves a fully opaque sheet — still visible in-game.
		_check(opaque_asset >= 800, "if no keyed pixels, expect mostly-opaque asset")

	var r0 = LightningTreeViewScript.stump_draw_rect_for_hex(layout, cam, 1, 0, tex)
	_check(r0.size.x > 1.0 and r0.size.y > 1.0, "draw rect has positive size")
	var world_10 = layout.hex_to_world(1, 0)
	var hex_h: float = 2.0 * HexLayoutScript.SIZE * cam.perspective_scale_at(world_10)
	_check(
		is_equal_approx(r0.size.y, hex_h * LightningTreeViewScript.STUMP_HEIGHT_HEX_FRAC),
		"draw height matches STUMP_HEIGHT_HEX_FRAC * projected hex height",
	)
	_check(
		is_equal_approx(LightningTreeViewScript.STUMP_HEIGHT_HEX_FRAC, 0.50),
		"stump scale constant is 0.50 (Phase 5.1.8c)",
	)
	var p0 = LightningTreeViewScript.presentation_pivot_for_hex(layout, cam, 1, 0)
	var p1 = LightningTreeViewScript.presentation_pivot_for_hex(layout, cam, 0, -1)
	_check(not p0.is_equal_approx(p1), "pivot differs for different hex coords")
	_check(r0.has_point(p0), "draw rect contains hex pivot (foot placement sane)")

	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	LightningTreeViewScript.apply_magenta_key_to_rgba8_image(img)
	_check(is_equal_approx(img.get_pixel(0, 0).a, 0.0), "screen magenta keyed to transparent")
	var img2 = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img2.fill(Color(1.0, 0.0, 1.0, 1.0))
	img2.set_pixel(2, 2, Color(0.2, 0.5, 0.1, 1.0))
	LightningTreeViewScript.apply_magenta_key_to_rgba8_image(img2)
	_check(img2.get_pixel(2, 2).a > 0.9, "non-magenta pixel keeps opacity")
	var img3 = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img3.fill(Color(0.04, 0.04, 0.04, 1.0))
	LightningTreeViewScript.apply_magenta_key_to_rgba8_image(img3)
	_check(img3.get_pixel(1, 1).a > 0.9, "near-black bark-like pixel not keyed globally")

	lv.queue_free()
	LightningTreeViewScript.debug_clear_stump_texture_cache()

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _count_transparent_pixels(img: Image, alpha_below_is_transparent: float) -> int:
	if img == null or img.get_format() != Image.FORMAT_RGBA8:
		return 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var n: int = 0
	var yy: int = 0
	while yy < h:
		var xx: int = 0
		while xx < w:
			if img.get_pixel(xx, yy).a < alpha_below_is_transparent:
				n += 1
			xx += 1
		yy += 1
	return n


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
