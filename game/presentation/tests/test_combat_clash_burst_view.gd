# Headless: godot --headless --path game -s res://presentation/tests/test_combat_clash_burst_view.gd
extends SceneTree

const ClashScript = preload("res://presentation/combat_clash_burst_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	var img_probe := Image.new()
	_check(img_probe.load(ClashScript.TEXTURE_PATH) == OK, "clash png readable (Image.load)")
	var raw = ImageTexture.create_from_image(img_probe)
	_check(raw != null, "texture from image")
	var keyed = ClashScript.texture_chroma_flat_magenta(raw)
	_check(keyed != null, "chroma helper returns texture")
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var v = ClashScript.new()
	v.layout = layout
	v.camera = cam
	v._tex = keyed
	v.show_burst_hex_centers(0, 0, 1, 0)
	_check(v._active, "burst activates")
	var acc: float = 0.0
	while acc < 1.05:
		v._process(0.21)
		acc = acc + 0.21
	_check(not v._active, "burst ends after ~1s")
	var v2 = ClashScript.new()
	v2.layout = layout
	v2.camera = cam
	v2._tex = keyed
	v2.show_burst_hex_centers(0, 0, 0, -1)
	v2.show_burst_hex_centers(1, 0, 0, -1)
	_check(v2._active, "second show restarts burst")
	v2._process(ClashScript.DURATION_SEC + 0.05)
	_check(not v2._active, "restart clears on timeout")
	v.free()
	v2.free()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	push_error(line)
	print(line)
