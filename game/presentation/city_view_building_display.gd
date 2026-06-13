# City View prototype building rows from canonical project/building registries (presentation only).
class_name CityViewBuildingDisplay
extends RefCounted

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const CityHubProductionDisplayScript = preload("res://presentation/city_hub_production_display.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

## Gameplay-enforced Ancient city buildings (stable display order).
const CANONICAL_ENFORCED_BUILDING_IDS: Array[String] = [
	BuildingDefinitionsScript.BUILDING_ID_HEARTH,
	BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP,
	BuildingDefinitionsScript.BUILDING_ID_STOREHOUSE_LEDGER,
	BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL,
	BuildingDefinitionsScript.BUILDING_ID_WEAVER_HUT,
	BuildingDefinitionsScript.BUILDING_ID_MUDBRICK_HOUSING,
	BuildingDefinitionsScript.BUILDING_ID_ARCHIVE_HUT,
	BuildingDefinitionsScript.BUILDING_ID_ARMORY,
]


static func canonical_building_ids() -> Array[String]:
	return (CANONICAL_ENFORCED_BUILDING_IDS as Array).duplicate()


static func science_id_for_building(building_id: String) -> String:
	var bid: String = str(building_id).strip_edges()
	if bid.is_empty():
		return ""
	var science_ids: Array = ProgressDefinitionsScript.ids()
	var si: int = 0
	while si < science_ids.size():
		var science_id: String = str(science_ids[si])
		var unlocks: Array = ProgressDefinitionsScript.concrete_unlocks(science_id)
		var ui: int = 0
		while ui < unlocks.size():
			var unlock: Dictionary = unlocks[ui] as Dictionary
			if (
				str(unlock.get("target_type", "")) == "building"
				and str(unlock.get("target_id", "")) == bid
			):
				return science_id
			ui += 1
		si += 1
	return ""


static func science_title_for_building(building_id: String) -> String:
	var science_id: String = science_id_for_building(building_id)
	if science_id.is_empty() or not ProgressDefinitionsScript.has(science_id):
		return ""
	var row: Dictionary = ProgressDefinitionsScript.get_definition(science_id) as Dictionary
	return str(row.get("display_name", ""))


static func project_id_for_building(building_id: String) -> String:
	var bid: String = str(building_id).strip_edges()
	if bid.is_empty():
		return ""
	var project_ids: Array = CityProjectDefinitionsScript.ids()
	var pi: int = 0
	while pi < project_ids.size():
		var project_id: String = str(project_ids[pi])
		if CityProjectDefinitionsScript.produces_building_id(project_id) == bid:
			return project_id
		pi += 1
	return ""


static func format_effect_chips_line(chips: Array) -> String:
	if typeof(chips) != TYPE_ARRAY or chips.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var ci: int = 0
	while ci < chips.size():
		var chip: Dictionary = chips[ci] as Dictionary
		var key: String = str(chip.get("key", ""))
		var value: int = int(chip.get("value", 0))
		parts.append(
			"%s %s"
			% [
				CityHubProductionDisplayScript.effect_value_text(value),
				_effect_key_label(key),
			]
		)
		ci += 1
	return " · ".join(parts)


static func _effect_key_label(effect_key: String) -> String:
	match effect_key:
		"food":
			return "Food"
		"production":
			return "Production"
		"coin":
			return "Coin"
		"science":
			return "Science"
		"housing":
			return "Housing"
		_:
			return effect_key.capitalize()


static func building_row(
	building_id: String,
	row_type: String,
	project_id: String = "",
) -> Dictionary:
	var bid: String = str(building_id).strip_edges()
	var chips: Array = CityHubProductionDisplayScript.effect_chips_for_building(bid)
	var science_id: String = science_id_for_building(bid)
	var display_name: String = BuildingDefinitionsScript.display_name(bid)
	if display_name.is_empty():
		display_name = bid
	var effects_line: String = format_effect_chips_line(chips)
	var science_title: String = science_title_for_building(bid)
	var summary: String = effects_line
	if summary.is_empty():
		summary = "No registered yield effects."
	return {
		"id": bid,
		"name": display_name,
		"type": row_type,
		"science_id": science_id,
		"science_title": science_title,
		"summary": summary,
		"effect_chips": chips,
		"effects_line": effects_line,
		"project_id": project_id if project_id != "" else project_id_for_building(bid),
		"metadata": {},
	}


static func format_building_row_line(row: Dictionary) -> String:
	var name: String = str(row.get("name", ""))
	var science_title: String = str(row.get("science_title", ""))
	var effects_line: String = str(row.get("effects_line", ""))
	if science_title.is_empty():
		if effects_line.is_empty():
			return name
		return "%s · %s" % [name, effects_line]
	if effects_line.is_empty():
		return "%s — %s" % [name, science_title]
	return "%s — %s · %s" % [name, science_title, effects_line]


static func _building_sort_index(building_id: String) -> int:
	var bid: String = str(building_id).strip_edges()
	if bid == BuildingDefinitionsScript.BUILDING_ID_PALACE:
		return -1
	var found: int = CANONICAL_ENFORCED_BUILDING_IDS.find(bid)
	if found >= 0:
		return found
	return 1000


static func _sort_rows_by_canonical_order(rows: Array[Dictionary]) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id: String = str(a.get("id", ""))
		var b_id: String = str(b.get("id", ""))
		var a_idx: int = _building_sort_index(a_id)
		var b_idx: int = _building_sort_index(b_id)
		if a_idx != b_idx:
			return a_idx < b_idx
		return a_id < b_id
	)


static func built_building_rows(p_game_state, p_selection) -> Array[Dictionary]:
	var city = _resolve_city(p_game_state, p_selection)
	if city == null:
		return []
	var rows: Array[Dictionary] = []
	var i: int = 0
	while i < city.building_ids.size():
		var building_id: String = str(city.building_ids[i])
		if BuildingDefinitionsScript.has(building_id):
			rows.append(building_row(building_id, "built_city_building"))
		i += 1
	_sort_rows_by_canonical_order(rows)
	return rows


static func available_building_rows(p_game_state, p_selection) -> Array[Dictionary]:
	if p_game_state == null or p_game_state.progress_state == null:
		return []
	var city = _resolve_city(p_game_state, p_selection)
	var built: Dictionary = {}
	if city != null:
		var bi: int = 0
		while bi < city.building_ids.size():
			built[str(city.building_ids[bi])] = true
			bi += 1
	var owner_id: int = p_game_state.turn_state.current_player_id()
	var rows: Array[Dictionary] = []
	var ci: int = 0
	while ci < CANONICAL_ENFORCED_BUILDING_IDS.size():
		var building_id: String = CANONICAL_ENFORCED_BUILDING_IDS[ci]
		if built.has(building_id):
			ci += 1
			continue
		if not p_game_state.progress_state.has_unlocked_target(owner_id, "building", building_id):
			ci += 1
			continue
		rows.append(building_row(building_id, "available_building"))
		ci += 1
	return rows


static func locked_building_rows(p_game_state, p_selection) -> Array[Dictionary]:
	if p_game_state == null or p_game_state.progress_state == null:
		return []
	var owner_id: int = p_game_state.turn_state.current_player_id()
	var rows: Array[Dictionary] = []
	var ci: int = 0
	while ci < CANONICAL_ENFORCED_BUILDING_IDS.size():
		var building_id: String = CANONICAL_ENFORCED_BUILDING_IDS[ci]
		if p_game_state.progress_state.has_unlocked_target(owner_id, "building", building_id):
			ci += 1
			continue
		rows.append(building_row(building_id, "locked_building"))
		ci += 1
	return rows


static func production_building_rows(p_game_state, p_selection) -> Array[Dictionary]:
	if p_game_state == null or p_selection == null or not p_selection.has_city():
		return []
	var city_id: int = int(p_selection.city_id)
	var legal: Array = LegalActionsScript.for_current_player(p_game_state)
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var li: int = 0
	while li < legal.size():
		var action = legal[li]
		li += 1
		if typeof(action) != TYPE_DICTIONARY:
			continue
		var ad: Dictionary = action as Dictionary
		if str(ad.get("action_type", "")) != SetCityProductionScript.ACTION_TYPE:
			continue
		if int(ad.get("city_id", -1)) != city_id:
			continue
		var project_id: String = str(ad.get("project_id", ""))
		if not project_id.begins_with("build:"):
			continue
		if seen.has(project_id):
			continue
		var building_id: String = CityProjectDefinitionsScript.produces_building_id(project_id)
		if building_id.is_empty() or not BuildingDefinitionsScript.has(building_id):
			continue
		seen[project_id] = true
		rows.append(building_row(building_id, "production_building", project_id))
	_sort_rows_by_canonical_order(rows)
	return rows


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
