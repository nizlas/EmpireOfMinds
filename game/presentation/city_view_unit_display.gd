# City View Available Units from legal produce_unit actions only (presentation).
class_name CityViewUnitDisplay
extends RefCounted

const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const UnitUnlockAssetsScript = preload("res://domain/content/unit_unlock_assets.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")


static func available_unit_rows(p_game_state, p_selection) -> Array[Dictionary]:
	if p_game_state == null:
		return []
	var city = _resolve_city(p_game_state, p_selection)
	if city == null:
		return []
	var city_id: int = int(city.id)
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
		if not project_id.begins_with("produce_unit:"):
			continue
		if seen.has(project_id):
			continue
		var unit_type: String = CityProjectDefinitionsScript.produces_unit_type(project_id)
		var unit_id: String = _unit_id_for_gameplay_type(unit_type)
		if unit_id.is_empty():
			continue
		seen[project_id] = true
		rows.append(
			unit_row(
				unit_id,
				"available_unit",
				"baseline",
				StartingUnitsScript.BASELINE_SOURCE_LABEL,
				project_id,
			)
		)
	_sort_rows_by_project_order(rows)
	return rows


static func production_unit_rows(p_game_state, p_selection) -> Array[Dictionary]:
	return available_unit_rows(p_game_state, p_selection)


static func _enrich_display_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = UnitUnlockAssetsScript.enrich_unlock_row(row)
	return UnitDefinitionsScript.enrich_unit_row(out)


static func unit_row(
	unit_id: String,
	row_type: String,
	science_id: String = "",
	science_title: String = "",
	project_id: String = "",
) -> Dictionary:
	var uid: String = str(unit_id).strip_edges()
	var unit_def: Dictionary = UnitDefinitionsScript.get_unit(uid)
	var display_name: String = str(unit_def.get("name", uid))
	if display_name.is_empty():
		display_name = uid
	var base: Dictionary = {
		"id": uid,
		"name": display_name,
		"type": row_type,
		"science_id": science_id,
		"science_title": science_title,
		"summary": str(unit_def.get("summary", "")),
		"project_id": project_id,
		"metadata": {},
	}
	return _enrich_display_row(base)


static func format_unit_row_line(row: Dictionary) -> String:
	return str(row.get("name", ""))


static func _project_sort_index(project_id: String) -> int:
	var pid: String = str(project_id).strip_edges()
	var order: Array = CityProjectDefinitionsScript.LEGAL_PROJECT_ORDER
	var found: int = order.find(pid)
	if found >= 0:
		return found
	return 1000


static func _sort_rows_by_project_order(rows: Array[Dictionary]) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_idx: int = _project_sort_index(str(a.get("project_id", "")))
		var b_idx: int = _project_sort_index(str(b.get("project_id", "")))
		if a_idx != b_idx:
			return a_idx < b_idx
		return str(a.get("id", "")) < str(b.get("id", ""))
	)


static func _unit_id_for_gameplay_type(gameplay_type: String) -> String:
	match str(gameplay_type).strip_edges():
		"settler":
			return "unit_settler"
		"warrior":
			return "unit_warrior"
		_:
			return ""


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
