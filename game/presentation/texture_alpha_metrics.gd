# Deterministic alpha bounding-box metrics for **RGBA** PNGs (prototype markers / tree symbols).
# Loads **`Texture2D`** via **ResourceLoader** and **`get_image()`**, with **`Image.load`** fallback.
extends RefCounted
class_name TextureAlphaMetrics

const DEFAULT_ALPHA_THRESHOLD: int = 8
## Opaque if **alpha×255 > threshold** (avoids AA fringe counting as content).
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func _alpha_byte(c: Color) -> int:
	return int(clampf(c.a * 255.0, 0.0, 255.0))


## Returns **Dictionary** with **ok**, **width**, **height**, **min_x**, **min_y**, **max_x**, **max_y** (opaque AABB),
## **bottom_padding_px**, **top_padding_px**, **left_padding_px**, **right_padding_px**, or **ok=false** on load failure / no opaque.
static func metrics_for_res_path(
	path: String, alpha_threshold: int = DEFAULT_ALPHA_THRESHOLD
) -> Dictionary:
	if _cache.has(path):
		return _cache[path] as Dictionary
	var out: Dictionary = {"ok": false, "path": path}
	var img: Image = null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		img = (res as Texture2D).get_image()
	if img == null:
		img = Image.new()
		var err_load: Error = img.load(path)
		if err_load != OK:
			out["ok"] = false
			_cache[path] = out
			return out

	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		_cache[path] = out
		return out
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	var yy: int = 0
	while yy < h:
		var xx: int = 0
		while xx < w:
			if _alpha_byte(img.get_pixel(xx, yy)) > alpha_threshold:
				if xx < min_x:
					min_x = xx
				if yy < min_y:
					min_y = yy
				if xx > max_x:
					max_x = xx
				if yy > max_y:
					max_y = yy
			xx += 1
		yy += 1
	if max_x < 0 or max_y < 0:
		out["ok"] = false
		out["width"] = w
		out["height"] = h
		_cache[path] = out
		return out
	out["ok"] = true
	out["width"] = w
	out["height"] = h
	out["min_x"] = min_x
	out["min_y"] = min_y
	out["max_x"] = max_x
	out["max_y"] = max_y
	out["left_padding_px"] = min_x
	out["top_padding_px"] = min_y
	out["right_padding_px"] = w - 1 - max_x
	out["bottom_padding_px"] = h - 1 - max_y
	_cache[path] = out
	return out


## **Quad** height **`side`** (drawn square); scales **`bottom_padding_px / texture_height`** into presentation/world units.
static func scaled_bottom_padding_y(metrics: Dictionary, quad_side: float) -> float:
	if not metrics.get("ok", false):
		return 0.0
	var th: int = int(metrics["height"])
	if th <= 0:
		return 0.0
	return float(int(metrics["bottom_padding_px"])) / float(th) * quad_side
