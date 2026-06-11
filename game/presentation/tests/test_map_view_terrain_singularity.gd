# Headless: terrain fake-perspective singularity skip + suspicious polygon classifier.
extends SceneTree

const MapViewScript = preload("res://presentation/map_view.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PolygonDrawGuardScript = preload("res://presentation/polygon_draw_guard.gd")

const DEPTH_STRENGTH: float = 0.0004
const NEAR_WORLD_Y: float = 192.0
const MIN_W: float = 0.15

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sane_corners: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			sane_corners, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "",
		"sane shifted.y≈0 not flagged",
	)

	var near_singular: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2500.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			near_singular, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "min_ww",
		"near-singular corner y=2500 flagged min_ww",
	)

	# Captured terrain_water offender: min_ww≈0.104, huge projected bbox.
	var offender_corners: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2432.0)])
	var offender_ww: float = MapViewScript.corner_perspective_w(
		DEPTH_STRENGTH, NEAR_WORLD_Y, 2432.0, 0.0
	)
	_check(
		absf(offender_ww - 0.104) < 0.002,
		"offender fixture min_ww≈0.104 (got %.4f)" % offender_ww,
	)
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			offender_corners, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "min_ww",
		"captured offender min_ww≈0.104 hard-skipped at threshold 0.15",
	)

	var sane_south: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2200.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			sane_south, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "",
		"sane south row y=2200 not hard-skipped",
	)

	var singular: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2692.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			singular, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "non_positive_ww",
		"singular corner y=2692 flagged non_positive_ww",
	)

	var negative_region: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2800.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			negative_region, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "non_positive_ww",
		"negative ww region y=2800 flagged non_positive_ww",
	)

	var mixed: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 3000.0)])
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			mixed, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "non_positive_ww",
		"mixed-sign hex corners flagged (non_positive wins)",
	)

	var layout = HexLayoutScript.new()
	var world_center: Vector2 = layout.hex_to_world(0, 0)
	var hex_corners: PackedVector2Array = layout.hex_corners(world_center)
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			hex_corners, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "",
		"reference hex at pan=0 not flagged",
	)

	var projection = MapPlaneProjectionScript.new()
	projection.depth_strength = DEPTH_STRENGTH
	projection.near_world_y = NEAR_WORLD_Y
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	map_camera.camera_world_offset = Vector2(0.0, -500.0)
	var southern_center: Vector2 = layout.hex_to_world(0, 12)
	var southern_corners: PackedVector2Array = layout.hex_corners(southern_center)
	var southern_skip: String = MapViewScript.hex_perspective_skip_reason_for_corners(
		southern_corners,
		DEPTH_STRENGTH,
		NEAR_WORLD_Y,
		map_camera.camera_world_offset.y,
		MIN_W,
	)
	_check(
		southern_skip != "",
		"southern row with pan.y=-500 flagged (%s)" % southern_skip,
	)

	var huge: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(60000.0, 0.0),
		Vector2(60000.0, 60000.0),
		Vector2(0.0, 60000.0),
	])
	_check(
		PolygonDrawGuardScript.polygon_suspicious_reason(huge, Vector2(1920.0, 1080.0))
		== "huge_coord",
		"huge coordinate polygon flagged",
	)

	var long_edge: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(9000.0, 0.0),
		Vector2(9000.0, 100.0),
		Vector2(0.0, 100.0),
	])
	_check(
		PolygonDrawGuardScript.polygon_suspicious_reason(long_edge, Vector2(1920.0, 1080.0))
		== "huge_edge",
		"huge edge polygon flagged",
	)

	var ok_poly: PackedVector2Array = PackedVector2Array([
		Vector2(100.0, 100.0),
		Vector2(300.0, 100.0),
		Vector2(300.0, 250.0),
		Vector2(100.0, 250.0),
	])
	_check(
		PolygonDrawGuardScript.polygon_suspicious_reason(ok_poly, Vector2(1920.0, 1080.0)) == "",
		"normal on-screen polygon not suspicious",
	)

	var ww_stats: Dictionary = MapViewScript.hex_ww_stats_for_corners(
		sane_corners, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0
	)
	_check(
		float(ww_stats["min_ww"]) > MIN_W and not bool(ww_stats["mixed_sign"]),
		"ww stats sane for reference corner",
	)

	var huge_rect: Rect2 = Rect2(Vector2(0.0, 0.0), Vector2(60000.0, 60000.0))
	_check(
		PolygonDrawGuardScript.rect_suspicious_reason(huge_rect, Vector2(1920.0, 1080.0))
		== "huge_coord",
		"huge texture rect flagged",
	)
	_check(
		PolygonDrawGuardScript.segment_suspicious_reason(
			Vector2(0.0, 0.0), Vector2(10000.0, 0.0), Vector2(1920.0, 1080.0)
		)
		== "huge_edge",
		"huge projected line segment flagged",
	)

	var vp: Vector2 = Vector2(1920.0, 1080.0)
	var small_p0: Vector2 = Vector2(500.0, 400.0)
	var small_p1: Vector2 = Vector2(518.8, 406.0)
	_check(
		MapViewScript.segment_drawn_suspicion_reason(small_p0, small_p1, vp) == "",
		"small detail line segment not DRAWN_SUSPICIOUS",
	)
	_check(
		MapViewScript.drawn_suspicion_reason(PackedVector2Array([small_p0, small_p1]), vp)
		== "",
		"small segment with pscale context not DRAWN_SUSPICIOUS",
	)
	_check(
		MapViewScript.low_priority_pscale_probe_reason(
			PackedVector2Array([small_p0, small_p1]), vp, 2.1626
		)
		== "probe_pscale",
		"pscale-only maps to low-priority probe_pscale",
	)
	_check(
		not MapViewScript.smear_reason_is_immediate("probe_pscale"),
		"probe_pscale is not immediate offender",
	)
	_check(
		MapViewScript.smear_reason_is_immediate("huge_edge"),
		"huge_edge is immediate offender",
	)
	_check(
		MapViewScript.segment_drawn_suspicion_reason(Vector2(0.0, 0.0), Vector2(10000.0, 0.0), vp)
		== "huge_edge",
		"huge detail line is DRAWN_SUSPICIOUS",
	)

	# Captured terrain_water: min_ww≈0.18 passes hex ww skip, but giant projected bbox must skip.
	var ww_018_corners: PackedVector2Array = PackedVector2Array([Vector2(0.0, 2242.0)])
	var ww_018: float = MapViewScript.corner_perspective_w(DEPTH_STRENGTH, NEAR_WORLD_Y, 2242.0, 0.0)
	_check(
		absf(ww_018 - 0.18) < 0.002,
		"fixture min_ww≈0.18 (got %.4f)" % ww_018,
	)
	_check(
		MapViewScript.hex_perspective_skip_reason_for_corners(
			ww_018_corners, DEPTH_STRENGTH, NEAR_WORLD_Y, 0.0, MIN_W
		)
		== "",
		"min_ww≈0.18 not skipped by hex ww threshold alone",
	)
	var huge_bbox_poly: PackedVector2Array = PackedVector2Array([
		Vector2(-3306.0, -1890.7),
		Vector2(3306.0, -1890.7),
		Vector2(3306.0, 1890.7),
		Vector2(-3306.0, 1890.7),
	])
	var bbox_skip: String = MapViewScript.terrain_polygon_hard_skip_reason(huge_bbox_poly, vp)
	_check(
		bbox_skip == "probe_bbox",
		"huge bbox≈6600×3800 terrain polygon hard-skipped (%s)" % bbox_skip,
	)
	_check(
		MapViewScript.TERRAIN_HARD_SKIP_PROBE_BBOX,
		"terrain_hard_skip_probe_bbox enabled in normal rendering",
	)
	_check(
		MapViewScript.TERRAIN_HARD_SKIP_PROBE_EDGE,
		"terrain_hard_skip_probe_edge enabled in normal rendering",
	)
	_check(
		MapViewScript.TERRAIN_HARD_SKIP_PROBE_COORD,
		"terrain_hard_skip_probe_coord enabled in normal rendering",
	)
	_check(
		MapViewScript.is_terrain_polygon_draw_kind("terrain_water"),
		"terrain_water uses terrain polygon hard-skip path",
	)
	_check(
		MapViewScript.terrain_polygon_hard_skip_on_point_sets(vp, [huge_bbox_poly])
		== "probe_bbox",
		"hard skip checks projected point sets for terrain polygons",
	)

	var mv: Node2D = MapViewScript.new()
	var root: Window = get_root() as Window
	root.add_child(mv)
	var offender_coord = HexCoordScript.new(-15, 11)
	var world_corners: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 2242.0),
		Vector2(64.0, 2242.0),
		Vector2(32.0, 2298.0),
	])
	var drawn_huge: bool = mv._draw_guarded_colored_polygon(
		huge_bbox_poly,
		Color.WHITE,
		PackedVector2Array(),
		null,
		offender_coord,
		"terrain_water",
		world_corners,
	)
	_check(not drawn_huge, "MapView._draw_guarded_colored_polygon skips terrain_water huge bbox")
	mv.queue_free()

	if _failures > 0:
		push_error("test_map_view_terrain_singularity: %d failures / %d checks" % [_failures, _checks])
		quit(1)
		return
	print("test_map_view_terrain_singularity: %d checks, all ok" % _checks)
	quit(0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
