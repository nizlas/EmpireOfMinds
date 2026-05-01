# Loads prototype map marker PNGs; Phase 4.3c — RGB sources without alpha get RGBA + background keyed from top-left (parchment/paper margin).
# See docs/RENDERING.md — not gameplay; presentation only.
class_name MarkerTextureUtil
extends RefCounted

const _COLOR_MATCH_EPS: float = 0.09

static func load_marker_icon(path: String) -> Texture2D:
	var base = load(path) as Texture2D
	if base == null:
		return null
	var img = base.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var bg: Color = img.get_pixel(0, 0)
	var w = img.get_width()
	var h = img.get_height()
	var yy = 0
	while yy < h:
		var xx = 0
		while xx < w:
			var c = img.get_pixel(xx, yy)
			if _matches_bg_rgb(c, bg):
				img.set_pixel(xx, yy, Color(c.r, c.g, c.b, 0.0))
			xx += 1
		yy += 1
	return ImageTexture.create_from_image(img)

static func _matches_bg_rgb(c: Color, bg: Color) -> bool:
	return absf(c.r - bg.r) <= _COLOR_MATCH_EPS and absf(c.g - bg.g) <= _COLOR_MATCH_EPS and absf(c.b - bg.b) <= _COLOR_MATCH_EPS
