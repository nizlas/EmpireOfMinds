# Headless: **TileYieldOverlayView** helpers + **CityYields** integration (no full scene draw).
# Usage: godot --headless --path game -s res://presentation/tests/test_tile_yield_overlay_view.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const TileYieldOverlayViewScript = preload("res://presentation/tile_yield_overlay_view.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var cols1 = TileYieldOverlayViewScript.compute_active_yield_columns(
		{"food": 2, "production": 1, "science": 0, "coin": 0}
	)
	_check(cols1.size() == 2 and str(cols1[0]) == "food" and str(cols1[1]) == "production", "active columns order")
	_check(TileYieldOverlayViewScript.compute_active_yield_columns(CityYieldsScript.empty()).is_empty(), "empty yields")

	var mets = TileYieldOverlayViewScript.compute_icon_metrics(1.0)
	var icon_sz: float = float(mets["icon_size"])
	var expect_nominal: float = clampf(
		HexLayoutScript.SIZE * float(TileYieldOverlayViewScript.YIELD_ICON_HEX_SIZE_RATIO),
		float(TileYieldOverlayViewScript.YIELD_ICON_MIN_PX),
		float(TileYieldOverlayViewScript.YIELD_ICON_MAX_PX)
	)
	_check(is_equal_approx(icon_sz, expect_nominal), "icon_size at pscale 1 (ratio + clamp)")
	_check(
		is_equal_approx(float(mets["column_step_x"]), icon_sz * float(TileYieldOverlayViewScript.YIELD_ICON_COLUMN_STEP_RATIO)),
		"column_step_x tracks icon_size * column ratio"
	)
	_check(
		is_equal_approx(float(mets["row_step_y"]), icon_sz * float(TileYieldOverlayViewScript.YIELD_ICON_ROW_STEP_RATIO)),
		"row_step_y tracks icon_size * row ratio"
	)
	var mets_tiny = TileYieldOverlayViewScript.compute_icon_metrics(0.05)
	_check(
		is_equal_approx(float(mets_tiny["icon_size"]), float(TileYieldOverlayViewScript.YIELD_ICON_MIN_PX)),
		"icon clamps to min px"
	)
	var mets_huge = TileYieldOverlayViewScript.compute_icon_metrics(10.0)
	_check(
		is_equal_approx(float(mets_huge["icon_size"]), float(TileYieldOverlayViewScript.YIELD_ICON_MAX_PX)),
		"icon clamps to max px"
	)
	var ents = TileYieldOverlayViewScript.compute_icon_entries_for_hex(
		Vector2(100.0, 200.0), {"food": 2, "production": 1, "science": 0, "coin": 0}, mets
	)
	_check(ents.size() == 3, "stacked icon count")
	var food_stack: int = 0
	var prod_stack: int = 0
	var fi: int = 0
	while fi < ents.size():
		var d: Dictionary = ents[fi] as Dictionary
		if str(d.get("yield_id", "")) == "food":
			food_stack += 1
		elif str(d.get("yield_id", "")) == "production":
			prod_stack += 1
		fi += 1
	_check(food_stack == 2 and prod_stack == 1, "yield id split")
	var r0: Rect2 = (ents[0] as Dictionary).get("rect", Rect2()) as Rect2
	var r1: Rect2 = (ents[1] as Dictionary).get("rect", Rect2()) as Rect2
	_check(is_equal_approx(r0.position.x, r1.position.x), "food stack same column x")
	_check(r1.position.y > r0.position.y, "food stack increases y")
	var c0: Vector2 = (ents[0] as Dictionary).get("center_pres", Vector2.ZERO) as Vector2
	var c2c: Vector2 = (ents[2] as Dictionary).get("center_pres", Vector2.ZERO) as Vector2
	var mid_cols: float = (c0.x + c2c.x) * 0.5
	_check(is_equal_approx(mid_cols, 100.0), "columns centered on anchor x")
	_check(is_equal_approx(r0.size.x, icon_sz) and is_equal_approx(r0.size.y, icon_sz), "rect uses icon_size")

	var scen_proto = ScenarioScript.make_prototype_play_scenario()
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	cam.vanishing_pres = Vector2(400.0, 300.0)
	var all_e = TileYieldOverlayViewScript.compute_overlay_entries(scen_proto, layout, cam)
	var water_coord = HexCoordScript.new(-1, 0)
	var saw_water: bool = false
	var wi: int = 0
	while wi < all_e.size():
		if (all_e[wi] as Dictionary)["coord"].equals(water_coord):
			saw_water = true
			break
		wi += 1
	_check(not saw_water, "water hex has no yield icons")

	var m_tiny = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var c_cap = CityScript.new(4, 0, HexCoordScript.new(1, -1), null, "", true, ["palace"])
	var scen_cap = ScenarioScript.new(m_tiny, u, [c_cap], 10, 20, null)
	var cap_entries = TileYieldOverlayViewScript.compute_overlay_entries(scen_cap, layout, cam)
	var cap_food: int = 0
	var cap_prod: int = 0
	var cap_sci: int = 0
	var cap_coin: int = 0
	var cap_ci: int = 0
	while cap_ci < cap_entries.size():
		var ed: Dictionary = cap_entries[cap_ci] as Dictionary
		if ed["coord"].equals(c_cap.position):
			match str(ed.get("yield_id", "")):
				"food":
					cap_food += 1
				"production":
					cap_prod += 1
				"science":
					cap_sci += 1
				"coin":
					cap_coin += 1
		cap_ci += 1
	var cen: Dictionary = CityYieldsScript.city_center_yield(m_tiny, c_cap)
	_check(cap_sci == 0 and cap_coin == 0, "map overlay uses center tile only — no palace S/C on city hex")
	_check(cap_food == CityYieldsScript.get_yield(cen, "food"), "center hex food icons match city_center_yield")
	_check(cap_prod == CityYieldsScript.get_yield(cen, "production"), "center hex production icons match city_center_yield")

	_check(TileYieldOverlayViewScript._load_yield_texture("res://__missing__/x.png") == null, "missing texture path")

	var ovr = TileYieldOverlayViewScript.new()
	ovr._configure_texture_filtering()
	_check(ovr.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "texture_filter matches marker views")
	ovr.free()

	var v = TileYieldOverlayViewScript.new()
	v.visible = false
	_check(not v.visible, "script default can be set off before tree add")

	if _any_fail:
		if v != null:
			v.free()
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		if v != null:
			v.free()
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
