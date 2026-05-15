# Headless: **main.tscn** map **Node2D** siblings under **Main** preserve **Main** subtree order contract:
# MapView → TerrainEdgeBlendView → EmpireBorderView → CityTerritoryView → CitiesView → SelectionView → UnitsView → TerrainForegroundView →
# LightningTreeView → TileYieldOverlayView → CityWorkedTilesView → CityNameplateView → UnitNameplateView → SelectionController,
# ignoring other **Main** children (HudCanvas, labels, controllers after SelectionController).
# **EmpireBorderView** (**5.1.17h**, strength **5.1.17h.1**): **`z_index` 0**, sibling **after** **`TerrainEdgeBlendView`**, **before** **`CityTerritoryView`** — always-on owner **union** realm outline (**dual** **`Line2D`** rim). **`CityTerritoryView`** stays **later** sibling but **dormant** (**no** selected-city border rim; forward UX uses **citizen/head** markers on tiles, not a second **`Line2D`** perimeter).
# **CityWorkedTilesView** (**5.1.17e**): **`z_index` 1**, **after** **`TileYieldOverlayView`** (same **`z_index`**) — **PLANNING** citizen markers **above** yield icons; **before** nameplates (**`z_index` 2**). Layering set in **[main.gd](../game/main.gd)** **`_ready`**.
# **CityTerritoryView** (**`z_index` 0**): slot retained **above** **EmpireBorderView** for wiring/helpers; **does not** draw a visible rim — realm border stays **selection-independent**.
# Phase **5.1.15b:** **CityNameplateView** sibling **before** **UnitNameplateView** (**`z_index` 2**) so units paint above city banners.
# Usage: godot --headless --path game -s res://presentation/tests/test_main_tscn_map_layer_sibling_order.gd
extends SceneTree


const MAIN_SCENE_PATH: String = "res://main.tscn"

## Order must match **Main** direct children in **main.tscn** (map stack through **SelectionController**).
var _map_layer_names: Array[String] = [
	"MapView",
	"TerrainEdgeBlendView",
	"EmpireBorderView",
	"CityTerritoryView",
	"CitiesView",
	"SelectionView",
	"UnitsView",
	"TerrainForegroundView",
	"LightningTreeView",
	"TileYieldOverlayView",
	"CityWorkedTilesView",
	"CityNameplateView",
	"UnitNameplateView",
	"SelectionController",
]


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	call_deferred("quit", 1)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("FAIL: could not load %s as PackedScene" % MAIN_SCENE_PATH)
		return
	var main_root: Node = packed.instantiate()
	var prev: int = -1
	var i: int = 0
	while i < _map_layer_names.size():
		var nm: String = _map_layer_names[i]
		if not main_root.has_node(NodePath(nm)):
			main_root.free()
			_fail("FAIL: missing expected Main child node \"%s\"" % nm)
			return
		var ch: Node = main_root.get_node(NodePath(nm))
		var parent: Node = ch.get_parent()
		if parent != main_root:
			main_root.free()
			_fail("FAIL: \"%s\" must be direct child of Main (Main root \"%s\")" % [nm, main_root.name])
			return
		var sx: int = ch.get_index()
		if sx <= prev:
			var prev_nm: String = _map_layer_names[i - 1] if i > 0 else "(none)"
			main_root.free()
			_fail(
				(
					"FAIL: map layer sibling order must be strictly increasing on Main children; \"%s\" index=%d is not after \"%s\" index=%d"
					% [nm, sx, prev_nm, prev]
				)
			)
			return
		prev = sx
		i += 1

	var mv: Node = main_root.get_node(NodePath("MapView"))
	var teb: CanvasItem = main_root.get_node(NodePath("TerrainEdgeBlendView")) as CanvasItem
	var ebv: CanvasItem = main_root.get_node(NodePath("EmpireBorderView")) as CanvasItem
	if mv.get_index() >= teb.get_index() or teb.get_index() >= ebv.get_index():
		main_root.free()
		_fail("FAIL: TerrainEdgeBlendView must be after MapView and before EmpireBorderView")
		return
	if int(teb.z_index) != 0:
		main_root.free()
		_fail("FAIL: TerrainEdgeBlendView z_index expected 0 in scene (PackedScene.instantiate)")
		return

	var ctv = main_root.get_node(NodePath("CityTerritoryView")) as CanvasItem
	if int(ctv.z_index) != 0:
		main_root.free()
		_fail("FAIL: CityTerritoryView z_index expected 0 in scene (PackedScene.instantiate)")
		return
	if int(ebv.z_index) != 0:
		main_root.free()
		_fail("FAIL: EmpireBorderView z_index expected 0 in scene (PackedScene.instantiate)")
		return
	var cwv = main_root.get_node(NodePath("CityWorkedTilesView")) as CanvasItem
	if int(cwv.z_index) != 1:
		main_root.free()
		_fail("FAIL: CityWorkedTilesView z_index expected 1 in scene (PackedScene.instantiate)")
		return

	var tyo = main_root.get_node(NodePath("TileYieldOverlayView")) as CanvasItem
	var cnv = main_root.get_node(NodePath("CityNameplateView")) as CanvasItem
	var unp = main_root.get_node(NodePath("UnitNameplateView")) as CanvasItem
	if tyo.get_index() >= cwv.get_index():
		main_root.free()
		_fail("FAIL: TileYieldOverlayView must be before CityWorkedTilesView (sibling order)")
		return
	if cwv.get_index() >= cnv.get_index() or cwv.get_index() >= unp.get_index():
		main_root.free()
		_fail("FAIL: CityWorkedTilesView must be before CityNameplateView and UnitNameplateView")
		return
	if int(tyo.z_index) != 1:
		main_root.free()
		_fail("FAIL: TileYieldOverlayView z_index expected 1 in scene (PackedScene.instantiate)")
		return

	main_root.free()
	print("PASS main_tscn_map_layer_sibling_order")
	call_deferred("quit", 0)
