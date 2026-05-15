# Headless: **main.tscn** keeps **CityTerritoryView** in the map stack for wiring parity (**selection** shared with **SelectionController**); **`_draw`** is **dormant** — **no** selected-city border rim (**empire outline is **`EmpireBorderView`** only). Forward UX: city-owned tiles → **citizen/head** markers (not perimeter strokes).
# Loads **PackedScene** + instantiates **Main** under tree so **`_ready`** runs (matches manual play wiring).
# Usage: godot --headless --path game -s res://presentation/tests/test_city_territory_main_wiring.gd
extends SceneTree


const MAIN_SCENE_PATH: String = "res://main.tscn"
const CITY_TERRITORY_SCRIPT_END: String = "city_territory_view.gd"


func _init() -> void:
	call_deferred("_run_load_scene")


func _fail(message: String) -> void:
	push_error(message)
	call_deferred("quit", 1)


func _run_load_scene() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("FAIL: could not load %s as PackedScene" % MAIN_SCENE_PATH)
		return
	var main_root: Node = packed.instantiate()
	var map_idx: int = -1
	var em_idx: int = -1
	var ct_idx: int = -1
	var cities_idx: int = -1
	var yield_idx: int = -1
	if main_root.has_node(NodePath("MapView")):
		map_idx = main_root.get_node(NodePath("MapView")).get_index()
	if main_root.has_node(NodePath("EmpireBorderView")):
		em_idx = main_root.get_node(NodePath("EmpireBorderView")).get_index()
	if main_root.has_node(NodePath("CityTerritoryView")):
		ct_idx = main_root.get_node(NodePath("CityTerritoryView")).get_index()
	if main_root.has_node(NodePath("CitiesView")):
		cities_idx = main_root.get_node(NodePath("CitiesView")).get_index()
	if main_root.has_node(NodePath("TileYieldOverlayView")):
		yield_idx = main_root.get_node(NodePath("TileYieldOverlayView")).get_index()
	if em_idx < 0:
		main_root.free()
		_fail("FAIL: EmpireBorderView missing under Main")
		return
	if ct_idx < 0:
		main_root.free()
		_fail("FAIL: CityTerritoryView missing under Main")
		return
	if map_idx < 0 or not (map_idx < em_idx and em_idx < ct_idx and ct_idx < cities_idx):
		main_root.free()
		_fail(
			(
				"FAIL: sibling order MapView (%d) < EmpireBorderView (%d) < CityTerritoryView (%d) < CitiesView (%d)"
				% [map_idx, em_idx, ct_idx, cities_idx]
			)
		)
		return
	if not (ct_idx < yield_idx):
		main_root.free()
		_fail(
			"FAIL: sibling order CityTerritoryView (%d) < TileYieldOverlayView (%d)" % [ct_idx, yield_idx]
		)
		return

	var ctv_packed: CanvasItem = main_root.get_node(NodePath("CityTerritoryView")) as CanvasItem
	if int(ctv_packed.z_index) != 0:
		main_root.free()
		_fail("FAIL: CityTerritoryView z_index expected 0 in scene packed state")
		return
	var ct_script = ctv_packed.get_script()
	if ct_script == null:
		main_root.free()
		_fail("FAIL: CityTerritoryView has no script on packed instance")
		return
	var sp: String = (ct_script as Script).resource_path
	if not String(sp).ends_with(CITY_TERRITORY_SCRIPT_END):
		main_root.free()
		_fail("FAIL: CityTerritoryView script path expected *%s, got %s" % [CITY_TERRITORY_SCRIPT_END, sp])
		return

	get_root().add_child(main_root)
	call_deferred("_run_after_ready", main_root)


func _run_after_ready(main_root: Node) -> void:
	var ctv: Node = main_root.get_node(NodePath("CityTerritoryView"))
	var selCtl: Node = main_root.get_node(NodePath("SelectionController"))
	var city_tv_field = selCtl.get("city_territory_view")
	if city_tv_field != ctv:
		main_root.queue_free()
		_fail(
			"FAIL: SelectionController.city_territory_view must be the scene CityTerritoryView node instance"
		)
		return
	var selCtl_sel = selCtl.get("selection")
	var ctv_sel = ctv.get("selection")
	if selCtl_sel == null or ctv_sel == null or selCtl_sel != ctv_sel:
		main_root.queue_free()
		_fail("FAIL: CityTerritoryView.selection must match SelectionController.selection (same instance)")
		return
	if not selCtl.has_method(&"_refresh_city_territory_view"):
		main_root.queue_free()
		_fail("FAIL: SelectionController must define _refresh_city_territory_view")
		return

	if int((ctv as CanvasItem).z_index) != 0:
		main_root.queue_free()
		_fail("FAIL: CityTerritoryView z_index expected 0 after Main._ready")
		return
	var overlay = main_root.get_node(NodePath("TileYieldOverlayView")) as CanvasItem
	if int(overlay.z_index) <= int((ctv as CanvasItem).z_index):
		main_root.queue_free()
		_fail("FAIL: TileYieldOverlayView z_index expected above CityTerritoryView after Main._ready")
		return

	main_root.queue_free()
	print("PASS city_territory_main_wiring")
	call_deferred("quit", 0)
