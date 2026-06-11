# Presentation-only polygon validation before CanvasItem polygon draws (triangulation guard).
class_name PolygonDrawGuard
extends RefCounted

const POINT_EPSILON_PX: float = 0.5
const MIN_POLY_AREA_SQ_PX: float = 4.0
## Opt-in MapView backstop: skip huge-but-triangulatable projected polygons.
const SUSPICIOUS_MAX_COORD_PX: float = 50000.0
const SUSPICIOUS_MAX_EDGE_PX: float = 8000.0
const SUSPICIOUS_BBOX_VIEWPORT_MULT: float = 4.0


static func sanitize_polygon_with_uvs(
	draw_pts: PackedVector2Array,
	uvs: PackedVector2Array,
	epsilon_px: float = POINT_EPSILON_PX,
) -> Dictionary:
	var out_pts := PackedVector2Array()
	var out_uvs := PackedVector2Array()
	var pi: int = 0
	while pi < draw_pts.size():
		var p: Vector2 = draw_pts[pi]
		if not p.is_finite():
			pi += 1
			continue
		if (
			out_pts.size() > 0
			and out_pts[out_pts.size() - 1].distance_squared_to(p) <= epsilon_px * epsilon_px
		):
			pi += 1
			continue
		out_pts.append(p)
		if pi < uvs.size():
			out_uvs.append(uvs[pi])
		pi += 1
	if (
		out_pts.size() >= 2
		and out_pts[0].distance_squared_to(out_pts[out_pts.size() - 1]) <= epsilon_px * epsilon_px
	):
		out_pts.resize(out_pts.size() - 1)
		if out_uvs.size() > out_pts.size():
			out_uvs.resize(out_pts.size())
	return {"pts": out_pts, "uvs": out_uvs}


static func count_unique_polygon_points(
	pts: PackedVector2Array,
	epsilon_px: float = POINT_EPSILON_PX,
) -> int:
	var unique: int = 0
	var pi: int = 0
	while pi < pts.size():
		var p: Vector2 = pts[pi]
		if not p.is_finite():
			pi += 1
			continue
		var is_dup: bool = false
		var ui: int = 0
		while ui < pi:
			if pts[ui].distance_squared_to(p) <= epsilon_px * epsilon_px:
				is_dup = true
				break
			ui += 1
		if not is_dup:
			unique += 1
		pi += 1
	return unique


static func polygon_area_abs_sq(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 0.0
	var area: float = 0.0
	var i: int = 0
	while i < pts.size():
		var j: int = (i + 1) % pts.size()
		area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
		i += 1
	return abs(area) * 0.5


## Empty string => drawable; otherwise skip reason for throttled diagnostics.
static func polygon_skip_reason(
	draw_pts: PackedVector2Array,
	epsilon_px: float = POINT_EPSILON_PX,
	min_area_sq_px: float = MIN_POLY_AREA_SQ_PX,
) -> String:
	if draw_pts.size() < 3:
		return "too_few_points"
	var pi: int = 0
	while pi < draw_pts.size():
		if not draw_pts[pi].is_finite():
			return "non_finite_point"
		pi += 1
	if count_unique_polygon_points(draw_pts, epsilon_px) < 3:
		return "too_few_unique_points"
	var area_sq: float = polygon_area_abs_sq(draw_pts)
	if area_sq < min_area_sq_px:
		return "near_zero_area"
	if Geometry2D.triangulate_polygon(draw_pts).is_empty():
		return "triangulation_failed"
	return ""


static func polygon_bounding_size(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var min_p: Vector2 = Vector2(INF, INF)
	var max_p: Vector2 = Vector2(-INF, -INF)
	var pi: int = 0
	while pi < pts.size():
		var p: Vector2 = pts[pi]
		if not p.is_finite():
			pi += 1
			continue
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
		pi += 1
	if min_p.x == INF:
		return Vector2.ZERO
	return max_p - min_p


static func polygon_max_edge_length(pts: PackedVector2Array) -> float:
	if pts.size() < 2:
		return 0.0
	var max_len: float = 0.0
	var i: int = 0
	while i < pts.size():
		var j: int = (i + 1) % pts.size()
		if pts[i].is_finite() and pts[j].is_finite():
			max_len = maxf(max_len, pts[i].distance_to(pts[j]))
		i += 1
	return max_len


## Empty string => not suspicious. Opt-in helper for MapView terrain draws only.
static func polygon_suspicious_reason(
	draw_pts: PackedVector2Array,
	viewport_size: Vector2,
) -> String:
	if draw_pts.is_empty():
		return ""
	var pi: int = 0
	while pi < draw_pts.size():
		var p: Vector2 = draw_pts[pi]
		if not p.is_finite():
			return "non_finite_point"
		if absf(p.x) > SUSPICIOUS_MAX_COORD_PX or absf(p.y) > SUSPICIOUS_MAX_COORD_PX:
			return "huge_coord"
		pi += 1
	var max_edge: float = polygon_max_edge_length(draw_pts)
	if max_edge > SUSPICIOUS_MAX_EDGE_PX:
		return "huge_edge"
	var bbox: Vector2 = polygon_bounding_size(draw_pts)
	var vp_diag: float = viewport_size.length()
	if vp_diag > 0.0 and bbox.length() > vp_diag * SUSPICIOUS_BBOX_VIEWPORT_MULT:
		return "huge_bbox"
	return ""


static func points_max_coord_magnitude(pts: PackedVector2Array) -> float:
	var max_mag: float = 0.0
	var pi: int = 0
	while pi < pts.size():
		var p: Vector2 = pts[pi]
		if p.is_finite():
			max_mag = maxf(max_mag, maxf(absf(p.x), absf(p.y)))
		pi += 1
	return max_mag


static func rect_corners(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])


static func rect_suspicious_reason(rect: Rect2, viewport_size: Vector2) -> String:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return ""
	return polygon_suspicious_reason(rect_corners(rect), viewport_size)


static func segment_suspicious_reason(
	p0: Vector2, p1: Vector2, viewport_size: Vector2
) -> String:
	if not p0.is_finite() or not p1.is_finite():
		return "non_finite_point"
	return polygon_suspicious_reason(PackedVector2Array([p0, p1]), viewport_size)
