# Headless: godot --headless --path game -s res://presentation/tests/test_unit_nameplate_view.gd
extends SceneTree

const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(
		UnitNameplateViewScript.display_name_for_type_id("warrior") == "Warrior",
		"warrior display"
	)
	_check(
		UnitNameplateViewScript.display_name_for_type_id("settler") == "Settler",
		"settler display"
	)
	_check(
		UnitNameplateViewScript.display_name_for_type_id("sentry_golem") == "Sentry Golem",
		"humanize unknown id"
	)
	_check(UnitNameplateViewScript.display_name_for_type_id("") == "Unit", "empty id")
	var c0a = UnitNameplateViewScript.owner_nameplate_accent_color(0)
	var c0b = UnitNameplateViewScript.owner_nameplate_accent_color(0)
	var c1 = UnitNameplateViewScript.owner_nameplate_accent_color(1)
	var c2 = UnitNameplateViewScript.owner_nameplate_accent_color(2)
	var c7a = UnitNameplateViewScript.owner_nameplate_accent_color(7)
	var c7b = UnitNameplateViewScript.owner_nameplate_accent_color(7)
	_check(c0a.is_equal_approx(c0b), "owner 0 stable")
	_check(c7a.is_equal_approx(c7b), "fallback owner stable")
	_check(not c0a.is_equal_approx(c1), "0 vs 1 differ")
	_check(not c1.is_equal_approx(c2), "1 vs 2 differ")
	_check(c0a.r < 0.55 and c0a.b > 0.55, "player 0 biased teal (muted blue)")
	_check(c1.r > 0.5 and c1.g < 0.4, "player 1 biased burgundy")
	var sw: float = UnitNameplateViewScript.owner_strip_width_px()
	_check(sw >= 22.0 and sw <= 28.0, "owner strip width in 22–28 px band")
	var font = ThemeDB.fallback_font
	var fs: int = 12
	var anchor = Vector2(200.0, 400.0)
	var marker_top: float = 350.0
	var r: Rect2 = UnitNameplateViewScript.compute_nameplate_rect(
		anchor,
		marker_top,
		1.0,
		"Warrior",
		font,
		fs
	)
	var bw: float = 1.0
	var inner_w: float = r.size.x - 2.0 * bw
	_check(inner_w >= sw + 16.0, "banner inner fits strip plus text padding")
	_check(r.size.x > 10.0 and r.size.y > 8.0, "non-degenerate rect")
	_check(abs(r.position.x + r.size.x * 0.5 - anchor.x) < 0.01, "centered on anchor x")
	_check(r.position.y + r.size.y < marker_top - 1.0, "banner sits above marker top")
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	var layout = HexLayoutScript.new()
	var sc = ScenarioScript.make_tiny_test_scenario()
	var rects = UnitNameplateViewScript.compute_all_nameplate_rects(sc, layout, cam, null)
	_check(rects.size() == sc.units().size(), "one rect per unit")
	_check(
		UnitNameplateViewScript.compute_all_nameplate_rects(null, layout, cam, null).is_empty(),
		"null scenario"
	)
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
