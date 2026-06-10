# Presentation-only polygon validation before CanvasItem polygon draws (triangulation guard).
class_name PolygonDrawGuard
extends RefCounted

const POINT_EPSILON_PX: float = 0.5
const MIN_POLY_AREA_SQ_PX: float = 4.0


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
