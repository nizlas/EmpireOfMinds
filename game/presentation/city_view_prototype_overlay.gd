# Programmer-drawn City View prototype (presentation only). Content inspection, not gameplay.
class_name CityViewPrototypeOverlay
extends Control

const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")
const UnitUnlockAssetsScript = preload("res://domain/content/unit_unlock_assets.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")

## Temporary display scaffolding when no completed science IDs exist on ProgressState yet.
const PROTOTYPE_AVAILABLE_SCIENCE_IDS: Array[String] = [
	"foraging_systems",
	"stone_tools",
	"controlled_fire",
	"pottery_craft",
	"basic_mining",
]

const UNIT_PRODUCTION_UNLOCK_TYPES: Array[String] = [
	"unit",
	"support_unit",
	"naval_unit",
]

const PRODUCTION_UNLOCK_TYPES: Array[String] = [
	"unit",
	"support_unit",
	"naval_unit",
	"city_building",
	"project",
]

const UNITS_LIST_MIN_HEIGHT_PX: int = 148

const BUILT_BUILDING_STUB_IDS: Array[String] = [
	"building_hearth",
]

var game_state = null
var selection = null

var _header_label: Label
var _yields_label: Label
var _built_list: ItemList
var _available_buildings_list: ItemList
var _production_units_list: ItemList
var _production_buildings_list: ItemList
var _production_projects_list: ItemList
var _tile_improvements_list: ItemList
var _details_label: Label
var _row_catalog: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func bind_session(p_game_state, p_selection) -> void:
	game_state = p_game_state
	selection = p_selection


func open_overlay() -> void:
	_refresh_content()
	visible = true


func close_overlay() -> void:
	visible = false


func is_open() -> bool:
	return visible


static func available_science_ids_for_display(p_game_state) -> Array[String]:
	if p_game_state == null or p_game_state.progress_state == null:
		return PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	var owner_id: int = p_game_state.turn_state.current_player_id()
	var completed: Array = p_game_state.progress_state.completed_progress_ids_for(owner_id)
	var out: Array[String] = []
	var i: int = 0
	while i < completed.size():
		var science_id: String = str(completed[i])
		if ScienceUnlocksScript.has_science(science_id):
			out.append(science_id)
		i += 1
	if out.is_empty():
		return PROTOTYPE_AVAILABLE_SCIENCE_IDS.duplicate()
	return out


static func _enrich_unit_rows(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = UnitUnlockAssetsScript.enrich_unlock_row(rows[i])
		out.append(UnitDefinitionsScript.enrich_unit_row(row))
		i += 1
	return out


static func collect_unlock_rows(
	science_ids: Array[String],
	allowed_types: Array[String],
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var si: int = 0
	while si < science_ids.size():
		var science_id: String = science_ids[si]
		var science: Dictionary = ScienceUnlocksScript.get_science(science_id)
		if science.is_empty():
			si += 1
			continue
		var unlocks: Array = science.get("unlocks", [])
		var ui: int = 0
		while ui < unlocks.size():
			var unlock: Dictionary = unlocks[ui] as Dictionary
			var unlock_type: String = str(unlock.get("type", ""))
			if allowed_types.has(unlock_type):
				var row: Dictionary = {
					"id": str(unlock.get("id", "")),
					"name": str(unlock.get("name", "")),
					"type": unlock_type,
					"science_id": science_id,
					"science_title": str(science.get("title", "")),
					"summary": str(unlock.get("summary", "")),
					"metadata": unlock.get("metadata", {}),
				}
				rows.append(row)
			ui += 1
		si += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: String = str(a.get("type", ""))
		var tb: String = str(b.get("type", ""))
		if ta != tb:
			return ta < tb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return _enrich_unit_rows(rows)


static func collect_baseline_unit_rows() -> Array[Dictionary]:
	return _enrich_unit_rows(StartingUnitsScript.unit_rows())


static func collect_unit_display_rows(science_ids: Array[String]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = collect_baseline_unit_rows()
	var science_rows: Array[Dictionary] = collect_unlock_rows(
		science_ids,
		UNIT_PRODUCTION_UNLOCK_TYPES,
	)
	var seen: Dictionary = {}
	var i: int = 0
	while i < rows.size():
		seen[str(rows[i].get("id", ""))] = true
		i += 1
	var si: int = 0
	while si < science_rows.size():
		var row: Dictionary = science_rows[si]
		var row_id: String = str(row.get("id", ""))
		if not seen.has(row_id):
			rows.append(row)
			seen[row_id] = true
		si += 1
	return rows


static func built_building_rows(p_game_state, p_selection) -> Array[Dictionary]:
	var city = _resolve_city(p_game_state, p_selection)
	var ids: Array[String] = []
	if city != null:
		var i: int = 0
		while i < city.building_ids.size():
			ids.append(str(city.building_ids[i]))
			i += 1
	if ids.is_empty():
		ids = BUILT_BUILDING_STUB_IDS.duplicate()
	var rows: Array[Dictionary] = []
	var bi: int = 0
	while bi < ids.size():
		var building_id: String = ids[bi]
		var unlock: Dictionary = ScienceUnlocksScript.find_unlock(building_id)
		var name: String = str(unlock.get("name", building_id))
		var summary: String = str(unlock.get("summary", "Built building placeholder."))
		rows.append({
			"id": building_id,
			"name": name,
			"type": "built_city_building",
			"science_id": str(unlock.get("science_id", "")),
			"science_title": _science_title_for_id(str(unlock.get("science_id", ""))),
			"summary": summary,
			"metadata": {},
		})
		bi += 1
	return rows


static func _science_title_for_id(science_id: String) -> String:
	if science_id.is_empty():
		return ""
	var science: Dictionary = ScienceUnlocksScript.get_science(science_id)
	return str(science.get("title", ""))


static func _resolve_city(p_game_state, p_selection):
	if p_game_state == null or p_game_state.scenario == null:
		return null
	if p_selection != null and p_selection.has_city():
		return p_game_state.scenario.city_by_id(p_selection.city_id)
	var owner_id: int = p_game_state.turn_state.current_player_id()
	var cities: Array = p_game_state.scenario.cities()
	var i: int = 0
	while i < cities.size():
		var city = cities[i]
		if city != null and int(city.owner_id) == owner_id:
			return city
		i += 1
	if cities.size() > 0:
		return cities[0]
	return null


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	root.add_child(top_row)

	_header_label = _make_heading_label("City View (prototype)")
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_header_label)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close_overlay)
	top_row.add_child(close_btn)

	_yields_label = _make_body_label("Yields: —")
	root.add_child(_yields_label)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	var left_panel := _make_panel("Built / Available Buildings")
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_panel)
	var left_vbox: VBoxContainer = left_panel.get_child(0) as VBoxContainer
	left_vbox.add_child(_make_section_label("Built Buildings"))
	_built_list = _make_item_list()
	left_vbox.add_child(_built_list)
	left_vbox.add_child(_make_section_label("Available Buildings"))
	_available_buildings_list = _make_item_list()
	left_vbox.add_child(_available_buildings_list)

	var right_panel := _make_panel("Production Choices")
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_panel)
	var right_vbox: VBoxContainer = right_panel.get_child(0) as VBoxContainer
	right_vbox.add_child(_make_section_label("Units"))
	_production_units_list = _make_item_list(UNITS_LIST_MIN_HEIGHT_PX)
	right_vbox.add_child(_production_units_list)
	right_vbox.add_child(_make_section_label("Buildings"))
	_production_buildings_list = _make_item_list()
	right_vbox.add_child(_production_buildings_list)
	right_vbox.add_child(_make_section_label("Projects"))
	_production_projects_list = _make_item_list()
	right_vbox.add_child(_production_projects_list)

	var bottom_panel := _make_panel("Tile Improvements / Worked Tiles")
	root.add_child(bottom_panel)
	var bottom_vbox: VBoxContainer = bottom_panel.get_child(0) as VBoxContainer
	bottom_vbox.add_child(
		_make_body_label("Worked tile assignment not implemented yet.")
	)
	_tile_improvements_list = _make_item_list()
	bottom_vbox.add_child(_tile_improvements_list)

	var details_panel := _make_panel("Selected Item Details")
	root.add_child(details_panel)
	var details_vbox: VBoxContainer = details_panel.get_child(0) as VBoxContainer
	_details_label = _make_body_label("Select a row to inspect unlock metadata.")
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_vbox.add_child(_details_label)

	_connect_list(_built_list)
	_connect_list(_available_buildings_list)
	_connect_list(_production_units_list)
	_connect_list(_production_buildings_list)
	_connect_list(_production_projects_list)
	_connect_list(_tile_improvements_list)


func _make_panel(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	style.border_color = Color(0.35, 0.35, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	vbox.add_child(_make_section_label(title_text))
	return panel


func _make_section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	label.add_theme_font_size_override("font_size", 16)
	return label


func _make_heading_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_font_size_override("font_size", 20)
	return label


func _make_body_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.74))
	label.add_theme_font_size_override("font_size", 14)
	return label


static func format_unit_row_line(row: Dictionary) -> String:
	return "%s · %s · %s  [%s]" % [
		str(row.get("name", "")),
		str(row.get("type", "")),
		str(row.get("science_title", "")),
		str(row.get("id", "")),
	]


func _make_item_list(min_height_px: int = 88) -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, min_height_px)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	list.same_column_width = true
	return list


func _connect_list(list: ItemList) -> void:
	list.item_selected.connect(func(index: int) -> void:
		_on_row_selected(list, index)
	)


func _refresh_content() -> void:
	_row_catalog.clear()
	_populate_header()
	var science_ids: Array[String] = available_science_ids_for_display(game_state)
	var built_rows: Array[Dictionary] = built_building_rows(game_state, selection)
	_fill_list(_built_list, built_rows, "built")
	var available_buildings: Array[Dictionary] = collect_unlock_rows(
		science_ids,
		["city_building"],
	)
	_fill_list(_available_buildings_list, available_buildings, "available_building")
	var unit_rows: Array[Dictionary] = collect_unit_display_rows(science_ids)
	var production_rows: Array[Dictionary] = collect_unlock_rows(
		science_ids,
		PRODUCTION_UNLOCK_TYPES,
	)
	var building_rows: Array[Dictionary] = []
	var project_rows: Array[Dictionary] = []
	var pi: int = 0
	while pi < production_rows.size():
		var row: Dictionary = production_rows[pi]
		var unlock_type: String = str(row.get("type", ""))
		if unlock_type == "city_building":
			building_rows.append(row)
		elif unlock_type == "project":
			project_rows.append(row)
		pi += 1
	_fill_unit_list(_production_units_list, unit_rows, "production_unit")
	_fill_list(_production_buildings_list, building_rows, "production_building")
	_fill_list(_production_projects_list, project_rows, "production_project")
	var tile_rows: Array[Dictionary] = collect_unlock_rows(
		science_ids,
		["tile_improvement"],
	)
	_fill_list(_tile_improvements_list, tile_rows, "tile_improvement")
	_details_label.text = "Select a row to inspect unlock metadata."


func _populate_header() -> void:
	var city = _resolve_city(game_state, selection)
	var city_name: String = "Prototype City"
	var pop: int = 1
	if city != null:
		var raw_name: String = str(city.city_name).strip_edges()
		if not raw_name.is_empty():
			city_name = raw_name
		pop = int(city.population)
	_header_label.text = "%s · Pop %d  [City View prototype]" % [city_name, pop]
	if game_state != null and selection != null:
		var vm: Dictionary = CityProductionPanelScript.compute_view_model(
			game_state,
			selection,
			null,
		)
		if bool(vm.get("show_yields", false)):
			var y: Dictionary = vm.get("yields", {}) as Dictionary
			_yields_label.text = (
				"Food %d · Production %d · Science %d · Gold %d"
				% [
					int(y.get("food", 0)),
					int(y.get("production", 0)),
					int(y.get("science", 0)),
					int(y.get("coin", 0)),
				]
			)
			return
	_yields_label.text = "Food — · Production — · Science — · Gold —"


func _fill_unit_list(list: ItemList, rows: Array[Dictionary], catalog_prefix: String) -> void:
	list.clear()
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = rows[i]
		var line: String = format_unit_row_line(row)
		list.add_item(line)
		var catalog_row: Dictionary = row.duplicate(true)
		catalog_row["catalog_key"] = "%s:%d" % [catalog_prefix, i]
		catalog_row["display_line"] = line
		_row_catalog.append(catalog_row)
		i += 1
	if rows.is_empty():
		list.add_item("(none)")
		list.set_item_disabled(0, true)


func _fill_list(list: ItemList, rows: Array[Dictionary], catalog_prefix: String) -> void:
	list.clear()
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = rows[i]
		var line: String = "[%s] %s — %s" % [
			str(row.get("type", "")),
			str(row.get("name", "")),
			str(row.get("science_title", "")),
		]
		list.add_item(line)
		var catalog_row: Dictionary = row.duplicate(true)
		catalog_row["catalog_key"] = "%s:%d" % [catalog_prefix, i]
		_row_catalog.append(catalog_row)
		i += 1
	if rows.is_empty():
		list.add_item("(none)")
		list.set_item_disabled(0, true)


func _on_row_selected(list: ItemList, index: int) -> void:
	if index < 0 or list.get_item_text(index) == "(none)":
		return
	var text: String = list.get_item_text(index)
	var i: int = 0
	while i < _row_catalog.size():
		var row: Dictionary = _row_catalog[i]
		var line: String = str(row.get("display_line", ""))
		if line.is_empty():
			line = "[%s] %s — %s" % [
				str(row.get("type", "")),
				str(row.get("name", "")),
				str(row.get("science_title", "")),
			]
		if line == text:
			_details_label.text = _format_details(row)
			return
		i += 1


static func _format_details(row: Dictionary) -> String:
	var metadata: Dictionary = row.get("metadata", {}) as Dictionary
	var meta_line: String = ""
	if not metadata.is_empty():
		meta_line = "\nMetadata: %s" % str(metadata)
	var asset_line: String = ""
	var asset_path: String = str(row.get("asset_path", ""))
	if not asset_path.is_empty():
		asset_line = "\nAsset: %s" % asset_path
	var stats_line: String = _format_unit_stats_block(row)
	return (
		"Name: %s\nType: %s\nScience: %s (%s)\nSummary: %s\nID: %s%s%s%s"
		% [
			str(row.get("name", "")),
			str(row.get("type", "")),
			str(row.get("science_title", "")),
			str(row.get("science_id", "")),
			str(row.get("summary", "")),
			str(row.get("id", "")),
			stats_line,
			meta_line,
			asset_line,
		]
	)


static func _format_unit_stats_block(row: Dictionary) -> String:
	if not row.has("hp"):
		return ""
	var lines: PackedStringArray = PackedStringArray([
		"\nCategory: %s" % str(row.get("category", "")),
		"HP: %d" % int(row.get("hp", 0)),
		"Cost: %d" % int(row.get("production_cost", 0)),
		"Movement: %d" % int(row.get("movement", 0)),
		"Melee Strength: %d" % int(row.get("melee_strength", 0)),
		"Ranged Strength: %d" % int(row.get("ranged_strength", 0)),
		"Range: %d" % int(row.get("attack_range", 0)),
		"Cargo: %d" % int(row.get("cargo_capacity", 0)),
	])
	if row.has("charges"):
		lines.append("Charges: %d" % int(row.get("charges", 0)))
	var tags: Array = row.get("unit_tags", [])
	if not tags.is_empty():
		lines.append("Tags: %s" % ", ".join(tags))
	return "\n".join(lines) + "\n"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_ESCAPE:
			close_overlay()
			get_viewport().set_input_as_handled()
