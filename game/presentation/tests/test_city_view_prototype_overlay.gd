# Headless: City View prototype overlay content wiring (presentation only).
extends SceneTree

const OverlayScript = preload("res://presentation/city_view_prototype_overlay.gd")
const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_main_scene_wiring()
	_test_available_science_scaffolding()
	_test_unlock_collection()
	_test_units_list_content()
	_test_primitive_troop_units_in_prototype()
	_test_naval_rule_metadata()
	_test_no_locked_sections_in_ui_copy()
	await _test_open_close_escape()
	await _test_tech_tree_still_works()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _test_main_scene_wiring() -> void:
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var hud = root.get_node_or_null("HudCanvas")
	_check(hud != null, "HudCanvas exists")
	var btn = hud.get_node_or_null("CityViewButton") if hud != null else null
	_check(btn is Button, "CityViewButton exists")
	if btn is Button:
		_check((btn as Button).text == "City View", "City View button label")
	var overlay = hud.get_node_or_null("CityViewPrototypeOverlay") if hud != null else null
	_check(overlay != null, "CityViewPrototypeOverlay exists")
	if overlay != null:
		_check(not overlay.visible, "city view overlay hidden by default")
	root.free()


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_available_science_scaffolding() -> void:
	var ids: Array[String] = OverlayScript.available_science_ids_for_display(null)
	_check(ids.size() == 5, "prototype science scaffold count")
	_check(ids.has("stone_tools"), "prototype includes stone_tools")
	var scenario = ScenarioScript.make_tiny_test_scenario()
	var gs = GameStateScript.new(scenario)
	var gs_ids: Array[String] = OverlayScript.available_science_ids_for_display(gs)
	_check(gs_ids == OverlayScript.PROTOTYPE_AVAILABLE_SCIENCE_IDS, "empty progress uses prototype scaffold")


func _test_unlock_collection() -> void:
	var science_ids: Array[String] = OverlayScript.PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	var buildings: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		science_ids,
		["city_building"],
	)
	_check(buildings.size() >= 3, "prototype sciences expose city_building unlocks")
	var production: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		science_ids,
		OverlayScript.PRODUCTION_UNLOCK_TYPES,
	)
	_check(production.size() >= 2, "prototype sciences expose production unlocks")
	var tiles: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		science_ids,
		["tile_improvement"],
	)
	_check(tiles.size() >= 2, "prototype sciences expose tile_improvement unlocks")
	var pi: int = 0
	while pi < buildings.size():
		var row: Dictionary = buildings[pi]
		_check(not str(row.get("name", "")).is_empty(), "building row has name")
		_check(not str(row.get("type", "")).is_empty(), "building row has type")
		_check(not str(row.get("science_title", "")).is_empty(), "building row has science title")
		_check(not str(row.get("summary", "")).is_empty(), "building row has summary")
		pi += 1


func _test_units_list_content() -> void:
	var science_ids: Array[String] = OverlayScript.PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	var unit_rows: Array[Dictionary] = OverlayScript.collect_unit_display_rows(science_ids)
	_check(unit_rows.size() >= 3, "baseline plus prototype science unit rows")
	var has_worker: bool = false
	var i: int = 0
	while i < unit_rows.size():
		var row: Dictionary = unit_rows[i]
		_check(not str(row.get("name", "")).is_empty(), "unit row has name")
		_check(
			OverlayScript.UNIT_PRODUCTION_UNLOCK_TYPES.has(str(row.get("type", ""))),
			"unit row has unit production type",
		)
		_check(not str(row.get("science_title", "")).is_empty(), "unit row has science title")
		var line: String = OverlayScript.format_unit_row_line(row)
		_check(line.contains(" · "), "unit row line uses minimal separators")
		_check(line.contains(str(row.get("id", ""))), "unit row line includes debug id")
		if str(row.get("id", "")) == "unit_worker":
			has_worker = true
		i += 1
	_check(has_worker, "prototype unit list includes Worker from Stone Tools")
	var overlay: OverlayScript = OverlayScript.new()
	overlay._build_ui()
	_check(
		overlay._production_units_list.custom_minimum_size.y
			>= OverlayScript.UNITS_LIST_MIN_HEIGHT_PX,
		"Units list has scrollable minimum height",
	)


func _test_primitive_troop_units_in_prototype() -> void:
	var science_ids: Array[String] = OverlayScript.PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	var unit_rows: Array[Dictionary] = OverlayScript.collect_unit_display_rows(science_ids)
	var ids_seen: Dictionary = {}
	var sources: Dictionary = {}
	var i: int = 0
	while i < unit_rows.size():
		var row: Dictionary = unit_rows[i]
		var row_id: String = str(row.get("id", ""))
		ids_seen[row_id] = true
		sources[row_id] = str(row.get("science_title", ""))
		i += 1
	_check(ids_seen.has("unit_settler"), "units list includes baseline Settler")
	_check(ids_seen.has("unit_warrior"), "units list includes baseline Warrior")
	_check(
		sources.get("unit_warrior", "") == StartingUnitsScript.BASELINE_SOURCE_LABEL,
		"Warrior source is Baseline not Stone Tools",
	)
	_check(ids_seen.has("unit_worker"), "prototype units include Worker")
	_check(ids_seen.has("unit_slinger"), "prototype units include Slinger")
	_check(not ids_seen.has("unit_raft"), "units list excludes Raft")
	var timber_rows: Array[Dictionary] = OverlayScript.collect_unit_display_rows(["timber_working"])
	var timber_ids: Dictionary = {}
	var ti: int = 0
	while ti < timber_rows.size():
		timber_ids[str(timber_rows[ti].get("id", ""))] = str(timber_rows[ti].get("science_title", ""))
		ti += 1
	_check(timber_ids.has("unit_archer"), "Archer appears when Timber Working is available")
	_check(
		timber_ids.get("unit_archer", "") == "Timber Working",
		"Archer source is Timber Working",
	)
	_check(not timber_ids.has("unit_raft"), "Timber Working does not expose Raft")


func _test_naval_rule_metadata() -> void:
	var fishing_ids: Array[String] = ["fishing_methods"]
	var fishing_rows: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		fishing_ids,
		["naval_unit", "rule"],
	)
	var has_reed_boat: bool = false
	var i: int = 0
	while i < fishing_rows.size():
		if str(fishing_rows[i].get("id", "")) == "unit_reed_boat":
			has_reed_boat = true
		i += 1
	_check(has_reed_boat, "Fishing Methods unlocks unit_reed_boat")
	var reed_rule: Dictionary = ScienceUnlocksScript.find_unlock("rule_reed_boat_transport_shallow_water")
	_check(not reed_rule.is_empty(), "reed boat transport rule exists")
	var reed_meta: Dictionary = reed_rule.get("metadata", {}) as Dictionary
	_check(int(reed_meta.get("cargo_capacity", -1)) == 1, "reed boat cargo_capacity is 1")
	var timber_ids: Array[String] = ["timber_working"]
	_check(timber_ids.size() == 1, "timber working id prepared")
	timber_rows_setup(timber_ids)


func timber_rows_setup(timber_ids: Array[String]) -> void:
	var timber_rows: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		timber_ids,
		["naval_unit", "rule"],
	)
	var has_war_canoe: bool = false
	var j: int = 0
	while j < timber_rows.size():
		if str(timber_rows[j].get("id", "")) == "unit_war_canoe":
			has_war_canoe = true
		j += 1
	_check(has_war_canoe, "Timber Working unlocks unit_war_canoe")
	var war_rule: Dictionary = ScienceUnlocksScript.find_unlock("rule_war_canoe_no_cargo_v0")
	_check(not war_rule.is_empty(), "war canoe no-cargo rule exists")
	var war_meta: Dictionary = war_rule.get("metadata", {}) as Dictionary
	_check(int(war_meta.get("cargo_capacity", -1)) == 0, "war canoe cargo_capacity is 0")


func _test_no_locked_sections_in_ui_copy() -> void:
	var overlay: OverlayScript = OverlayScript.new()
	overlay._build_ui()
	var text_blob: String = ""
	var labels: Array[Label] = []
	_collect_labels(overlay, labels)
	var li: int = 0
	while li < labels.size():
		text_blob += labels[li].text + "\n"
		li += 1
	_check(text_blob.find("Locked") < 0, "City View prototype has no Locked section label")


func _collect_labels(node: Node, out: Array[Label]) -> void:
	if node is Label:
		out.append(node as Label)
	var i: int = 0
	while i < node.get_child_count():
		_collect_labels(node.get_child(i), out)
		i += 1


func _test_open_close_escape() -> void:
	var overlay: OverlayScript = OverlayScript.new()
	get_root().add_child(overlay)
	for _i in 2:
		await process_frame
	_check(not overlay.visible, "hidden by default")
	overlay.open_overlay()
	_check(overlay.visible, "open_overlay shows City View")
	overlay.close_overlay()
	_check(not overlay.visible, "close_overlay hides City View")
	overlay.open_overlay()
	_check(overlay.visible, "re-open works")
	overlay._unhandled_input(InputEventKey.new())
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)
	_check(not overlay.visible, "Escape closes City View")
	var scenario = ScenarioScript.make_tiny_test_scenario()
	var gs = GameStateScript.new(scenario)
	var sel = SelectionStateScript.new()
	overlay.bind_session(gs, sel)
	overlay.open_overlay()
	_check(overlay._header_label.text.contains("City"), "header shows city context")
	_check(overlay._available_buildings_list.item_count > 0, "available buildings listed")
	_check(overlay._production_units_list.item_count >= 4, "production units listed with baseline rows")
	var unit_blob: String = ""
	var ui: int = 0
	while ui < overlay._production_units_list.item_count:
		unit_blob += overlay._production_units_list.get_item_text(ui) + "\n"
		ui += 1
	_check(unit_blob.contains(" · "), "open overlay unit rows use minimal display")
	_check(unit_blob.contains("Baseline"), "open overlay includes baseline source label")
	_check(unit_blob.contains("unit_settler"), "open overlay unit rows include Settler id")
	_check(unit_blob.contains("unit_warrior"), "open overlay unit rows include Warrior id")
	_check(unit_blob.contains("unit_worker"), "open overlay unit rows include Worker id")
	_check(unit_blob.contains("unit_slinger"), "open overlay unit rows include Slinger id")
	_check(not unit_blob.contains("unit_raft"), "open overlay unit rows exclude Raft")
	_check(overlay._tile_improvements_list.item_count > 0, "tile improvements listed")
	var exo_rows: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		["exoplanet_expedition"],
		["victory"],
	)
	_check(exo_rows.size() >= 1, "Exoplanet Expedition has victory unlock")
	overlay.queue_free()


func _test_tech_tree_still_works() -> void:
	var tech_overlay: TechTreeOverlayScript = TechTreeOverlayScript.new()
	get_root().add_child(tech_overlay)
	for _i in 2:
		await process_frame
	tech_overlay.open_overlay()
	_check(tech_overlay.visible, "tech tree overlay still opens")
	_check(tech_overlay._tech_items.size() == 21, "tech tree still renders twenty-one items")
	tech_overlay.queue_free()
