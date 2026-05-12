# Headless: **5.1.15e** — runtime-style geometry: shared hex banner stays in normal above-marker band (not detached below marker).
# Usage: godot --headless --path game -s res://presentation/tests/test_city_nameplate_shared_hex_runtime_clearance.gd
extends SceneTree

const CityNameplateViewScript = preload("res://presentation/city_nameplate_view.gd")
const CitiesViewScript = preload("res://presentation/cities_view.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const CityScript = preload("res://domain/city.gd")
const UnitScript = preload("res://domain/unit.gd")

var _total = 0
var _any_fail = false


func _check(c: bool, msg: String) -> void:
	_total += 1
	if c:
		return
	_any_fail = true
	var line = "FAIL: %s" % msg
	print(line)
	push_error(line)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rt: Node = get_root()
	var m = HexMapScript.make_tiny_test_map()
	var h = HexCoordScript.new(1, 0)
	var warrior = UnitScript.new(9, 0, h, "warrior")
	var cty = CityScript.new(4, 0, h, null, "Riverford")
	var sc = ScenarioScript.new(m, [warrior], [cty], -1, -1, null)

	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var layout = HexLayoutScript.new()

	var cities = CitiesViewScript.new()
	cities.scenario = sc
	cities.layout = layout
	cities.camera = cam
	rt.add_child(cities)
	await process_frame

	var units = UnitsViewScript.new()
	units.scenario = sc
	units.layout = layout
	units.camera = cam
	rt.add_child(units)
	await process_frame

	var wc: Vector2 = layout.hex_to_world(h.q, h.r)
	var anchor: Vector2 = cam.to_presentation(wc)
	var pscale: float = cam.perspective_scale_at(wc)

	var top_y = CityNameplateViewScript._marker_top_presentation_y(anchor, pscale, cities)

	var font: Font = ThemeDB.fallback_font
	var fs: int = CityNameplateViewScript.CITY_BANNER_FONT_SIZE
	var label = CityNameplateViewScript.display_label_for_city(cty)

	var banner_r: Rect2 = CityNameplateViewScript.compute_city_banner_rect(
		anchor, top_y, pscale, label, font, fs
	)

	var warrior_rect: Rect2 = units.unit_marker_texture_rect_presentation(anchor, pscale, "warrior")
	_check(warrior_rect.size.x > 0.1, "warrior texture rect loads in test")

	var clearance: float = top_y - (banner_r.position.y + banner_r.size.y)
	_check(clearance > 0.5 and clearance < 6.5, "city banner remains in tight above-marker band")
	_check(
		banner_r.position.y + banner_r.size.y < top_y - 0.25,
		"banner bottom still above marker top (not placed far below city)"
	)

	# Overlap with warrior plate is allowed in **5.1.15e**; TFV draws unit after banner.

	var marker_bottom_approx: float = top_y + HexLayoutScript.SIZE * 2.0 * 0.90 * pscale
	var banner_bottom: float = banner_r.position.y + banner_r.size.y
	_check(
		banner_bottom < marker_bottom_approx + 12.0,
		"banner not shifted down near/past full marker bottom (detached-label guard)"
	)

	rt.remove_child(cities)
	cities.queue_free()
	rt.remove_child(units)
	units.queue_free()

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d city_nameplate_shared_hex_runtime_clearance" % [_total, _total])
		call_deferred("quit", 0)
