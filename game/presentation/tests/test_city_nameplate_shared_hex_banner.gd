# Headless: **CityNameplateView** **5.1.15e** — shared hex uses normal banner geometry; TFV draws that banner under unit markers.
# Usage: godot --headless --path game -s res://presentation/tests/test_city_nameplate_shared_hex_banner.gd
extends SceneTree

const CityNameplateViewScript = preload("res://presentation/city_nameplate_view.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
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


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)


func _init() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(CityNameplateViewScript.CITY_BANNER_FONT_SIZE)
	var anchor = Vector2(400.0, 520.0)
	var marker_top: float = 470.0
	var pscale: float = 1.0
	var label = "Riverford"
	var r_one: Rect2 = CityNameplateViewScript.compute_city_banner_rect(
		anchor, marker_top, pscale, label, font, fs
	)
	var r_two: Rect2 = CityNameplateViewScript.compute_city_banner_rect(
		anchor, marker_top, pscale, label, font, fs
	)
	_check(r_one == r_two, "banner rect path is unique (no shared-hex geometry fork)")
	_check(
		is_equal_approx(r_one.get_center().x, anchor.x),
		"banner centered on anchor x"
	)
	var clearance: float = marker_top - (r_one.position.y + r_one.size.y)
	_check(clearance > 0.5 and clearance < 6.5, "banner stays just above marker top (not pushed far below)")
	var dist_marker_to_banner: float = abs((r_one.position.y + r_one.size.y * 0.5) - marker_top)
	_check(dist_marker_to_banner < 80.0, "banner vertical center not far below city marker top")

	var sw: float = CityNameplateViewScript.owner_strip_width_px()
	_check(
		is_equal_approx(sw, UnitNameplateViewScript.owner_strip_width_px()),
		"owner strip width still matches unit nameplates"
	)
	_check(fs == 16, "CITY_BANNER_FONT_SIZE unchanged for readability")

	var m = HexMapScript.make_tiny_test_map()
	var h = HexCoordScript.new(0, 0)
	var warrior = UnitScript.new(1, 0, h, "warrior")
	var cty = CityScript.new(1, 0, h, null, "Cap")
	var sc_shared = ScenarioScript.new(m, [warrior], [cty], -1, -1, null)
	_check(
		CityNameplateViewScript.city_hex_has_units(sc_shared, cty),
		"city_hex_has_units true when unit shares hex"
	)
	var sc_no_u = ScenarioScript.new(m, [], [cty], -1, -1, null)
	_check(
		not CityNameplateViewScript.city_hex_has_units(sc_no_u, cty),
		"city_hex_has_units false without units"
	)

	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var layout = HexLayoutScript.new()
	var rects_shared_all = CityNameplateViewScript.compute_all_city_banner_rects(
		sc_shared, layout, cam, null, false
	)
	var rects_shared_omit = CityNameplateViewScript.compute_all_city_banner_rects(
		sc_shared, layout, cam, null, true
	)
	var rects_no = CityNameplateViewScript.compute_all_city_banner_rects(sc_no_u, layout, cam, null, false)
	_check(rects_shared_all.size() == 1, "compute_all include shared: one rect")
	_check(rects_shared_omit.is_empty(), "compute_all omit shared-hex cities when unit present")
	_check(rects_no.size() == 1, "one banner rect when city alone")
	var r_all = rects_shared_all[0] as Rect2
	var r_solo = rects_no[0] as Rect2
	_check(
		is_equal_approx(r_all.position.y, r_solo.position.y),
		"shared vs solo same banner row when geometry matches"
	)

	var tfv_txt: String = FileAccess.get_file_as_string(
		"res://presentation/terrain_foreground_view.gd"
	)
	_check(
		tfv_txt.find("CityNameplateView.draw_city_banner_on_canvas_item") >= 0,
		"TFV calls CityNameplateView.draw_city_banner_on_canvas_item"
	)
	var i_sort: int = tfv_txt.find("items.sort_custom(_fg_depth_merge_item_lt)")
	var i_detail: int = tfv_txt.find("# **Detail** grid summary: match legacy", i_sort)
	_check(i_sort >= 0 and i_detail > i_sort, "TFV depth-merge body found for ordering asserts")
	var merge_body: String = tfv_txt.substr(i_sort, i_detail - i_sort)
	var i_mkr: int = merge_body.find("draw_city_marker_at")
	var i_bnr: int = merge_body.find("draw_city_banner_on_canvas_item")
	var i_um: int = merge_body.find("units_view.draw_unit_marker_at")
	_check(i_mkr >= 0 and i_bnr >= 0 and i_um >= 0, "depth-merge body contains marker/banner/unit draw calls")
	_check(i_mkr < i_bnr, "depth-merge: city marker before city banner")
	_check(i_bnr < i_um, "depth-merge: city banner before unit marker draw")

	var i_p2: int = tfv_txt.find("# Phase **4.6p — pass 2:** city markers, then units")
	_check(i_p2 >= 0, "TFV pass2 anchor comment found")
	var i_p2u: int = tfv_txt.find(
		"if units_view != null and scenario != null and not do_forest_unit_depth_merge:", i_p2
	)
	_check(i_p2u > i_p2, "TFV pass2 unit pass follows city pass")
	var pass2_body: String = tfv_txt.substr(i_p2, i_p2u - i_p2)
	var p2_m: int = pass2_body.find("draw_city_marker_at")
	var p2_b: int = pass2_body.find("draw_city_banner_on_canvas_item")
	_check(p2_m >= 0 and p2_b >= 0, "pass2 body contains marker and banner draw")
	_check(p2_m < p2_b, "pass2: city marker then shared-hex banner in same city loop")

	var mn_txt: String = FileAccess.get_file_as_string("res://main.gd")
	_check(
		mn_txt.find("city_nameplate_view.terrain_foreground_view = terrain_foreground") >= 0,
		"main wires CityNameplateView.terrain_foreground_view for TFV delegation"
	)

	_check(
		mn_txt.find("$TerrainForegroundView.z_index = 1") >= 0
		and mn_txt.find("$CityNameplateView.z_index = 2") >= 0,
		"main.gd keeps TFV z_index 1 and CityNameplateView z_index 2 for parchment vs nameplate stack"
	)

	var packed = load("res://main.tscn") as PackedScene
	var root = packed.instantiate()
	var cnv = root.get_node_or_null("CityNameplateView")
	var un = root.get_node_or_null("UnitNameplateView")
	var _tfv = root.get_node_or_null("TerrainForegroundView")
	_check(cnv != null and un != null and _tfv != null, "main.tscn map nodes")
	_check(cnv.get_index() < un.get_index(), "city nameplate still before unit for draw top-stack")
	root.free()

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d city_nameplate_shared_hex_banner" % [_total, _total])
		call_deferred("quit", 0)
