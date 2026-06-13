# Headless: City View prototype overlay content wiring (presentation only).
extends SceneTree

const OverlayScript = preload("res://presentation/city_view_prototype_overlay.gd")
const CityViewBuildingDisplayScript = preload("res://presentation/city_view_building_display.gd")
const CityViewUnitDisplayScript = preload("res://presentation/city_view_unit_display.gd")
const CityHubProductionDisplayScript = preload("res://presentation/city_hub_production_display.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")
const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")
const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_main_scene_wiring()
	_test_available_science_scaffolding()
	_test_tile_improvement_unlock_collection()
	_test_canonical_building_registry_rows()
	_test_locked_buildings_progression()
	_test_canonical_unit_sections()
	_test_unit_details_include_gameplay_stats()
	_test_naval_rule_metadata()
	_test_locked_buildings_section_label()
	_test_unit_section_labels()
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


func _test_tile_improvement_unlock_collection() -> void:
	var science_ids: Array[String] = OverlayScript.PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	var tiles: Array[Dictionary] = OverlayScript.collect_unlock_rows(
		science_ids,
		["tile_improvement"],
	)
	_check(tiles.size() >= 2, "prototype sciences expose tile_improvement unlocks")
	var pi: int = 0
	while pi < tiles.size():
		var row: Dictionary = tiles[pi]
		_check(not str(row.get("name", "")).is_empty(), "tile row has name")
		_check(not str(row.get("type", "")).is_empty(), "tile row has type")
		pi += 1


func _make_founded_capital() -> Dictionary:
	var gs = GameStateScript.make_tiny_test_state()
	var city_id: int = gs.scenario.peek_next_city_id()
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital for building tests")
	var sel = SelectionStateScript.new()
	sel.select_city(city_id)
	return {"gs": gs, "city_id": city_id, "sel": sel}


func _complete_sciences(gs, science_ids: Array) -> void:
	var i: int = 0
	while i < science_ids.size():
		var sid: String = str(science_ids[i])
		_check(gs.try_apply(CompleteProgressScript.make(0, sid))["accepted"], "complete %s" % sid)
		i += 1


func _row_ids(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	var i: int = 0
	while i < rows.size():
		out.append(str(rows[i].get("id", "")))
		i += 1
	return out


func _test_canonical_building_registry_rows() -> void:
	var canonical: Array[String] = CityViewBuildingDisplayScript.canonical_building_ids()
	_check(canonical.size() == 8, "eight canonical enforced Ancient buildings")
	_check(
		CityViewBuildingDisplayScript.science_id_for_building(
			BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL
		)
		== "seasonal_calendars",
		"Storage Hall maps to seasonal_calendars",
	)
	_check(
		CityViewBuildingDisplayScript.science_id_for_building(
			BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP
		)
		== "pottery_craft",
		"Pottery Workshop maps to pottery_craft",
	)

	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var city_id: int = int(setup["city_id"])
	_complete_sciences(
		gs,
		[
			"foraging_systems",
			"stone_tools",
			"controlled_fire",
			"pottery_craft",
			"basic_mining",
			"oral_surveying",
			"timber_working",
			"counting_marks",
			"seasonal_calendars",
			"textile_work",
			"mudbrick_construction",
			"glyphic_records",
			"bronze_alloying",
		],
	)

	var available: Array[Dictionary] = OverlayScript.available_building_rows(gs, sel)
	var available_ids: Array[String] = _row_ids(available)
	_check(available_ids.size() == 8, "all canonical buildings available when unlocked and not built")
	_check(available_ids == canonical, "available uses canonical progression order")
	var ai: int = 0
	while ai < canonical.size():
		_check(available_ids.has(canonical[ai]), "available includes %s" % canonical[ai])
		ai += 1
	_check(not available_ids.has("scout_camp"), "Scout Camp not in available buildings")
	_check(not _blob_contains_scout_camp(available), "available rows exclude Scout Camp names")

	var production: Array[Dictionary] = OverlayScript.production_building_rows(gs, sel)
	_check(production.size() == 8, "production choices list all legal build projects")
	var legal: Array = LegalActionsScript.for_current_player(gs)
	var legal_build_projects: int = 0
	var li: int = 0
	while li < legal.size():
		var action: Dictionary = legal[li] as Dictionary
		if (
			str(action.get("action_type", "")) == SetCityProductionScript.ACTION_TYPE
			and int(action.get("city_id", -1)) == city_id
			and str(action.get("project_id", "")).begins_with("build:")
		):
			legal_build_projects += 1
		li += 1
	_check(production.size() == legal_build_projects, "production buildings mirror LegalActions build projects")
	_check(not _blob_contains_scout_camp(production), "production rows exclude Scout Camp")

	var hearth_row: Dictionary = {}
	var pi: int = 0
	while pi < production.size():
		if str(production[pi].get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_HEARTH:
			hearth_row = production[pi]
		pi += 1
	_check(
		str(hearth_row.get("project_id", "")) == SetCityProductionScript.PROJECT_ID_BUILD_HEARTH,
		"hearth production row uses legal build:hearth project",
	)

	var m = HexMapScript.make_tiny_test_map()
	var city = CityScript.new(
		city_id,
		0,
		HexCoordScript.new(1, 0),
		null,
		"BuiltTest",
		true,
		["palace", BuildingDefinitionsScript.BUILDING_ID_HEARTH, BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP],
	)
	var gs_built = GameStateScript.new(ScenarioScript.new(m, [], [city]))
	var sel_built = SelectionStateScript.new()
	sel_built.select_city(city_id)
	var built: Array[Dictionary] = OverlayScript.built_building_rows(gs_built, sel_built)
	var built_ids: Array[String] = _row_ids(built)
	_check(built_ids.has(BuildingDefinitionsScript.BUILDING_ID_HEARTH), "built list includes hearth from building_ids")
	_check(built_ids.has(BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP), "built list includes pottery workshop")
	_check(built_ids.has(BuildingDefinitionsScript.BUILDING_ID_PALACE), "built list includes palace from building_ids")
	_check(not built_ids.has("scout_camp"), "built list excludes Scout Camp")
	_check(not _blob_contains_scout_camp(built), "built rows exclude Scout Camp names")

	var pottery_row: Dictionary = {}
	var bi: int = 0
	while bi < built.size():
		if str(built[bi].get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP:
			pottery_row = built[bi]
		bi += 1
	_check(str(pottery_row.get("science_id", "")) == "pottery_craft", "built pottery row science_id pottery_craft")
	var pottery_chips: Array = pottery_row.get("effect_chips", [])
	_check(pottery_chips.size() == 1, "pottery built row has one effect chip")
	_check(
		str((pottery_chips[0] as Dictionary).get("key", "")) == "food",
		"pottery chip key from BuildingDefinitions",
	)
	_check(int((pottery_chips[0] as Dictionary).get("value", 0)) == 1, "pottery chip +1 food")

	var storage_available: Dictionary = {}
	var si: int = 0
	while si < available.size():
		if str(available[si].get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL:
			storage_available = available[si]
		si += 1
	_check(str(storage_available.get("science_id", "")) == "seasonal_calendars", "available Storage Hall science_id")
	_check(
		str(storage_available.get("name", "")) == BuildingDefinitionsScript.display_name(
			BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL
		),
		"Storage Hall display name from BuildingDefinitions",
	)
	var storage_chips: Array = CityHubProductionDisplayScript.effect_chips_for_building(
		BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL
	)
	_check(
		CityViewBuildingDisplayScript.format_effect_chips_line(storage_available.get("effect_chips", []))
		== CityViewBuildingDisplayScript.format_effect_chips_line(storage_chips),
		"Storage Hall effect line matches BuildingDefinitions chips",
	)

	var line: String = CityViewBuildingDisplayScript.format_building_row_line(pottery_row)
	_check(line.contains("Pottery Workshop"), "building row line uses canonical name")
	_check(line.contains("Pottery Craft"), "building row line uses science title")
	_check(line.contains("+1"), "building row line shows +N effect")
	_check(line.contains("Food"), "building row line shows yield label")


func _test_locked_buildings_progression() -> void:
	var canonical: Array[String] = CityViewBuildingDisplayScript.canonical_building_ids()
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var city_id: int = int(setup["city_id"])

	var built0: Array[Dictionary] = OverlayScript.built_building_rows(gs, sel)
	var built0_ids: Array[String] = _row_ids(built0)
	_check(built0_ids.has(BuildingDefinitionsScript.BUILDING_ID_PALACE), "new game built includes Palace")
	_check(built0_ids.size() == 1, "new game built is Palace only")
	_check(OverlayScript.available_building_rows(gs, sel).is_empty(), "new game available buildings empty")
	var locked0: Array[Dictionary] = OverlayScript.locked_building_rows(gs, sel)
	var locked0_ids: Array[String] = _row_ids(locked0)
	_check(locked0_ids.size() == 8, "new game locked lists all eight canonical buildings")
	_check(locked0_ids == canonical, "new game locked uses canonical progression order")
	_check(OverlayScript.production_building_rows(gs, sel).is_empty(), "new game production buildings empty")
	_check(not _blob_contains_scout_camp(locked0), "locked rows exclude Scout Camp")

	var hearth_locked: Dictionary = locked0[0]
	_check(
		str(hearth_locked.get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_HEARTH,
		"first locked row is Hearth in canonical order",
	)
	_check(str(hearth_locked.get("science_id", "")) == "controlled_fire", "locked Hearth science controlled_fire")
	_check(
		str(hearth_locked.get("science_title", "")) == "Controlled Fire",
		"locked Hearth shows Controlled Fire science title",
	)
	_check(
		str(hearth_locked.get("effects_line", "")).contains("+1")
		and str(hearth_locked.get("effects_line", "")).contains("Production"),
		"locked Hearth shows +1 Production",
	)

	var storage_locked: Dictionary = {}
	var sli: int = 0
	while sli < locked0.size():
		if str(locked0[sli].get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL:
			storage_locked = locked0[sli]
		sli += 1
	_check(str(storage_locked.get("science_id", "")) == "seasonal_calendars", "locked Storage Hall science_id")
	_check(str(storage_locked.get("science_title", "")) == "Seasonal Calendars", "locked Storage Hall science title")

	var pottery_locked: Dictionary = {}
	var pli: int = 0
	while pli < locked0.size():
		if str(locked0[pli].get("id", "")) == BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP:
			pottery_locked = locked0[pli]
		pli += 1
	_check(str(pottery_locked.get("science_id", "")) == "pottery_craft", "locked Pottery Workshop science_id")

	_check(gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"], "unlock controlled_fire")
	var available_cf: Array[Dictionary] = OverlayScript.available_building_rows(gs, sel)
	var available_cf_ids: Array[String] = _row_ids(available_cf)
	_check(available_cf_ids.has(BuildingDefinitionsScript.BUILDING_ID_HEARTH), "Hearth available after CF")
	_check(available_cf_ids.size() == 1, "only Hearth available after CF")
	var locked_cf_ids: Array[String] = _row_ids(OverlayScript.locked_building_rows(gs, sel))
	_check(locked_cf_ids.size() == 7, "seven locked after CF")
	_check(not locked_cf_ids.has(BuildingDefinitionsScript.BUILDING_ID_HEARTH), "Hearth not locked after CF")
	var production_cf_ids: Array[String] = _row_ids(OverlayScript.production_building_rows(gs, sel))
	_check(
		production_cf_ids.has(BuildingDefinitionsScript.BUILDING_ID_HEARTH),
		"Hearth in production choices after CF",
	)

	var m = HexMapScript.make_tiny_test_map()
	var city_built = CityScript.new(
		city_id,
		0,
		HexCoordScript.new(1, 0),
		null,
		"HearthBuilt",
		true,
		["palace", BuildingDefinitionsScript.BUILDING_ID_HEARTH],
	)
	var gs_built = GameStateScript.new(ScenarioScript.new(m, [], [city_built]))
	gs_built.try_apply(CompleteProgressScript.make(0, "controlled_fire"))
	var sel_built = SelectionStateScript.new()
	sel_built.select_city(city_id)
	var built_h: Array[String] = _row_ids(OverlayScript.built_building_rows(gs_built, sel_built))
	_check(built_h.has(BuildingDefinitionsScript.BUILDING_ID_HEARTH), "built Hearth after construction")
	_check(
		not _row_ids(OverlayScript.available_building_rows(gs_built, sel_built)).has(
			BuildingDefinitionsScript.BUILDING_ID_HEARTH
		),
		"Hearth not available after built",
	)
	_check(
		not _row_ids(OverlayScript.production_building_rows(gs_built, sel_built)).has(
			BuildingDefinitionsScript.BUILDING_ID_HEARTH
		),
		"Hearth not in production after built",
	)
	_check(
		not _row_ids(OverlayScript.locked_building_rows(gs_built, sel_built)).has(
			BuildingDefinitionsScript.BUILDING_ID_HEARTH
		),
		"Hearth not locked after built",
	)
	_check(not _blob_contains_scout_camp(OverlayScript.built_building_rows(gs_built, sel_built)), "built excludes Scout Camp")
	_check(
		not _blob_contains_scout_camp(OverlayScript.available_building_rows(gs_built, sel_built)),
		"available excludes Scout Camp",
	)
	_check(
		not _blob_contains_scout_camp(OverlayScript.production_building_rows(gs_built, sel_built)),
		"production excludes Scout Camp",
	)


func _blob_contains_scout_camp(rows: Array[Dictionary]) -> bool:
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = rows[i]
		if str(row.get("id", "")).find("scout") >= 0:
			return true
		if str(row.get("name", "")).find("Scout Camp") >= 0:
			return true
		i += 1
	return false


func _test_canonical_unit_sections() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]

	var available_ids: Array[String] = _row_ids(OverlayScript.available_unit_rows(gs, sel))
	_check(available_ids.size() == 2, "overlay available units exactly two at new game")
	_check(available_ids[0] == "unit_warrior", "overlay available warrior first")
	_check(available_ids[1] == "unit_settler", "overlay available settler second")
	_check(not available_ids.has("unit_worker"), "overlay available excludes Worker before stone_tools")
	_check(not available_ids.has("unit_slinger"), "overlay available excludes Slinger")

	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "overlay stone_tools complete")
	var after_st_ids: Array[String] = _row_ids(OverlayScript.available_unit_rows(gs, sel))
	_check(after_st_ids.size() == 3, "three available units after stone_tools")
	_check(after_st_ids.has("unit_worker"), "Worker appears after stone_tools unlock")
	_check(after_st_ids[2] == "unit_worker", "Worker follows baseline units in tree order")

	var overlay: OverlayScript = OverlayScript.new()
	overlay._build_ui()
	_check(
		overlay._available_units_list.custom_minimum_size.y
			>= OverlayScript.UNITS_LIST_MIN_HEIGHT_PX,
		"Available Units list has scrollable minimum height",
	)


func _test_unit_details_include_gameplay_stats() -> void:
	var setup: Dictionary = _make_founded_capital()
	var gs = setup["gs"]
	var sel = setup["sel"]
	var rows: Array[Dictionary] = OverlayScript.available_unit_rows(gs, sel)
	var warrior_row: Dictionary = {}
	var ri: int = 0
	while ri < rows.size():
		if str(rows[ri].get("id", "")) == "unit_warrior":
			warrior_row = rows[ri]
		ri += 1
	_check(not warrior_row.is_empty(), "warrior row for details")
	var details: String = OverlayScript._format_details(warrior_row)
	_check(details.contains("HP: 100"), "details show HP")
	_check(details.contains("Melee Strength: 20"), "details show melee")
	_check(details.contains("Cost: 40"), "details show production cost")
	_check(details.contains("baseline"), "details show baseline tag")


func _test_unit_section_labels() -> void:
	var overlay: OverlayScript = OverlayScript.new()
	overlay._build_ui()
	var text_blob: String = ""
	var labels: Array[Label] = []
	_collect_labels(overlay, labels)
	var li: int = 0
	while li < labels.size():
		text_blob += labels[li].text + "\n"
		li += 1
	_check(text_blob.contains("Available Units"), "City View has Available Units section")
	_check(text_blob.find("Locked Units") < 0, "City View has no Locked Units section")
	var has_production_units_section: bool = false
	var li2: int = 0
	while li2 < labels.size():
		if (labels[li2] as Label).text == "Units":
			has_production_units_section = true
		li2 += 1
	_check(not has_production_units_section, "City View has no separate Production Units section")


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


func _test_locked_buildings_section_label() -> void:
	var overlay: OverlayScript = OverlayScript.new()
	overlay._build_ui()
	var text_blob: String = ""
	var labels: Array[Label] = []
	_collect_labels(overlay, labels)
	var li: int = 0
	while li < labels.size():
		text_blob += labels[li].text + "\n"
		li += 1
	_check(text_blob.contains("Locked Buildings"), "City View prototype has Locked Buildings section")
	_check(text_blob.contains("Building Overview"), "City View prototype uses Building Overview panel")


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
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "open overlay test found city")
	sel.select_city(1)
	_check(gs.try_apply(CompleteProgressScript.make(0, "foraging_systems"))["accepted"], "open overlay foraging")
	_check(gs.try_apply(CompleteProgressScript.make(0, "stone_tools"))["accepted"], "open overlay stone_tools")
	_check(gs.try_apply(CompleteProgressScript.make(0, "controlled_fire"))["accepted"], "open overlay CF")
	_check(gs.try_apply(CompleteProgressScript.make(0, "pottery_craft"))["accepted"], "open overlay pottery")
	overlay.bind_session(gs, sel)
	overlay.open_overlay()
	_check(overlay._header_label.text.contains("City"), "header shows city context")
	_check(overlay._available_buildings_list.item_count >= 2, "available buildings listed from registry")
	_check(overlay._locked_buildings_list.item_count >= 1, "locked buildings listed for informational catalog")
	var locked_blob: String = ""
	var lbi: int = 0
	while lbi < overlay._locked_buildings_list.item_count:
		locked_blob += overlay._locked_buildings_list.get_item_text(lbi) + "\n"
		lbi += 1
	_check(not locked_blob.contains("Scout Camp"), "locked list excludes Scout Camp")
	_check(overlay._production_buildings_list.item_count >= 2, "production building choices listed")
	var avail_blob: String = ""
	var abi: int = 0
	while abi < overlay._available_buildings_list.item_count:
		avail_blob += overlay._available_buildings_list.get_item_text(abi) + "\n"
		abi += 1
	_check(avail_blob.contains("Hearth"), "available list shows Hearth")
	_check(avail_blob.contains("Pottery Workshop"), "available list shows Pottery Workshop")
	_check(not avail_blob.contains("Scout Camp"), "available list excludes Scout Camp")
	_check(not avail_blob.contains("Storage —"), "available list excludes stale Storage label")
	_check(overlay._available_units_list.item_count == 3, "available units are Warrior Settler and Worker after stone_tools")
	var unit_blob: String = ""
	var ui: int = 0
	while ui < overlay._available_units_list.item_count:
		unit_blob += overlay._available_units_list.get_item_text(ui) + "\n"
		ui += 1
	_check(unit_blob.contains("Warrior"), "open overlay available shows Warrior")
	_check(unit_blob.contains("Settler"), "open overlay available shows Settler")
	_check(unit_blob.contains("Worker"), "open overlay available shows Worker after stone_tools")
	_check(not unit_blob.contains("Slinger"), "open overlay available excludes Slinger")
	_check(not unit_blob.contains("Tracker"), "open overlay available excludes Tracker before unlock")
	_check(not unit_blob.contains("Cart"), "open overlay available excludes Cart before unlock")
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
