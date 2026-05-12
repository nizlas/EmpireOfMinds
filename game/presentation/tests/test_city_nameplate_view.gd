# Headless: godot --headless --path game -s res://presentation/tests/test_city_nameplate_view.gd
extends SceneTree

const CityNameplateViewScript = preload("res://presentation/city_nameplate_view.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const CityScript = preload("res://domain/city.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var c_named = CityScript.new(3, 0, HexCoordScript.new(0, 0), null, "Riverford")
	_check(CityNameplateViewScript.display_label_for_city(c_named) == "Riverford", "uses city_name")
	var c_blank = CityScript.new(7, 1, HexCoordScript.new(1, 0), null, "")
	_check(CityNameplateViewScript.display_label_for_city(c_blank) == "City 7", "fallback id label")
	_check(CityNameplateViewScript.display_label_for_city(null) == "", "null city")
	_check(
		is_equal_approx(
			CityNameplateViewScript.owner_strip_width_px(),
			UnitNameplateViewScript.owner_strip_width_px()
		),
		"city strip width matches unit nameplates"
	)
	_check(int(CityNameplateViewScript.CITY_BANNER_FONT_SIZE) > 12, "city font larger than unit nameplates")
	var font = ThemeDB.fallback_font
	var fs: int = int(CityNameplateViewScript.CITY_BANNER_FONT_SIZE)
	var anchor = Vector2(220.0, 410.0)
	var marker_top: float = 360.0
	var pscale: float = 1.0
	var r: Rect2 = CityNameplateViewScript.compute_city_banner_rect(
		anchor,
		marker_top,
		pscale,
		"Capital",
		font,
		fs
	)
	var sw: float = CityNameplateViewScript.owner_strip_width_px()
	var bw: float = 1.0
	var inner_w: float = r.size.x - 2.0 * bw
	_check(inner_w >= sw + 16.0, "banner inner fits strip plus padding")
	var banner_bottom: float = r.position.y + r.size.y
	var clearance: float = marker_top - banner_bottom
	_check(clearance > 0.5 and clearance < 6.5, "5.1.15b tight gap above marker")
	# Prior band was ~10px at **pscale** 1.0 — stay materially closer.
	_check(clearance < 7.0, "closer than legacy ~8–10px gap")
	_check(r.position.y + r.size.y < marker_top - 0.25, "banner above marker top")
	_check(abs(r.position.x + r.size.x * 0.5 - anchor.x) < 0.01, "centered on anchor x")

	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var layout = HexLayoutScript.new()
	var sc0 = ScenarioScript.make_tiny_test_scenario()
	_check(CityNameplateViewScript.compute_all_city_banner_rects(sc0, layout, cam, null).is_empty(), "no cities")
	var sc1 = ScenarioScript.new(
		sc0.map,
		sc0.units(),
		[CityScript.new(1, 0, HexCoordScript.new(0, 0), null, "A")],
		sc0.peek_next_unit_id(),
		2,
		sc0.lightning_tree_hex
	)
	var rects = CityNameplateViewScript.compute_all_city_banner_rects(sc1, layout, cam, null)
	_check(rects.size() == 1, "one rect per city")

	var packed = load("res://main.tscn") as PackedScene
	var root = packed.instantiate()
	var cnv = root.get_node_or_null("CityNameplateView")
	_check(cnv != null, "main.tscn CityNameplateView node")
	_check(cnv.get_script() == CityNameplateViewScript, "CityNameplateView script")
	var un = root.get_node_or_null("UnitNameplateView")
	_check(un != null, "UnitNameplateView node")
	var i_c = cnv.get_index()
	var i_u = un.get_index()
	_check(i_c < i_u, "city nameplate before unit nameplate for draw layering")
	root.free()

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
	print(line)
	push_error(line)
