# City View Available Units — empire-level unlocked unit catalog (presentation/debug).
class_name CityViewUnitDisplay
extends RefCounted

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const UnitUnlockAssetsScript = preload("res://domain/content/unit_unlock_assets.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")

## Baseline empire units (stable display order: Warrior, then Settler).
const BASELINE_UNIT_IDS: Array[String] = [
	"unit_warrior",
	"unit_settler",
]

const _BASELINE_PROJECT_BY_UNIT_ID: Dictionary = {
	"unit_warrior": "produce_unit:warrior",
	"unit_settler": "produce_unit:settler",
}

## Progress `target_id` (target_type unit) → canonical `UnitDefinitions` id.
const _UNIT_ID_BY_PROGRESS_TARGET: Dictionary = {
	"worker": "unit_worker",
	"tracker": "unit_tracker_scout",
	"cart": "unit_cart_support",
}


static func available_unit_rows(p_game_state, _p_selection) -> Array[Dictionary]:
	if p_game_state == null:
		return []
	var owner_id: int = p_game_state.turn_state.current_player_id()
	var progress_state = p_game_state.progress_state
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var bi: int = 0
	while bi < BASELINE_UNIT_IDS.size():
		var unit_id: String = BASELINE_UNIT_IDS[bi]
		seen[unit_id] = true
		rows.append(
			unit_row(
				unit_id,
				"available_unit",
				"baseline",
				StartingUnitsScript.BASELINE_SOURCE_LABEL,
				str(_BASELINE_PROJECT_BY_UNIT_ID.get(unit_id, "")),
			)
		)
		bi += 1
	var science_ids: Array = ProgressDefinitionsScript.ids()
	var si: int = 0
	while si < science_ids.size():
		var science_id: String = str(science_ids[si])
		var unlocks: Array = ProgressDefinitionsScript.concrete_unlocks(science_id)
		var ui: int = 0
		while ui < unlocks.size():
			var unlock: Dictionary = unlocks[ui] as Dictionary
			ui += 1
			if str(unlock.get("target_type", "")) != "unit":
				continue
			var target_id: String = str(unlock.get("target_id", "")).strip_edges()
			if target_id.is_empty() or target_id == "slinger":
				continue
			if progress_state == null or not progress_state.has_unlocked_target(
				owner_id, "unit", target_id
			):
				continue
			var unit_id_unlock: String = _unit_id_for_progress_target(target_id)
			if unit_id_unlock.is_empty() or seen.has(unit_id_unlock):
				continue
			if not UnitDefinitionsScript.has_unit(unit_id_unlock):
				continue
			seen[unit_id_unlock] = true
			var science_title: String = _science_display_name(science_id)
			rows.append(
				unit_row(
					unit_id_unlock,
					"available_unit",
					science_id,
					science_title,
					_project_id_for_unit_if_exists(unit_id_unlock),
				)
			)
		si += 1
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


static func _science_display_name(science_id: String) -> String:
	if not ProgressDefinitionsScript.has(science_id):
		return science_id
	var row: Dictionary = ProgressDefinitionsScript.get_definition(science_id) as Dictionary
	return str(row.get("display_name", science_id))


static func _unit_id_for_progress_target(target_id: String) -> String:
	var tid: String = str(target_id).strip_edges()
	if _UNIT_ID_BY_PROGRESS_TARGET.has(tid):
		return str(_UNIT_ID_BY_PROGRESS_TARGET[tid])
	var candidate: String = "unit_%s" % tid
	if UnitDefinitionsScript.has_unit(candidate):
		return candidate
	return ""


static func _project_id_for_unit_if_exists(unit_id: String) -> String:
	var uid: String = str(unit_id).strip_edges()
	if uid.is_empty():
		return ""
	var project_ids: Array = CityProjectDefinitionsScript.ids()
	var pi: int = 0
	while pi < project_ids.size():
		var project_id: String = str(project_ids[pi])
		if CityProjectDefinitionsScript.produces_unit_type(project_id) == _gameplay_type_for_unit(uid):
			return project_id
		pi += 1
	return ""


static func _gameplay_type_for_unit(unit_id: String) -> String:
	var unit: Dictionary = UnitDefinitionsScript.get_unit(unit_id)
	var gameplay_type: String = str(unit.get("gameplay_type_id", "")).strip_edges()
	if not gameplay_type.is_empty():
		return gameplay_type
	match unit_id:
		"unit_settler":
			return "settler"
		"unit_warrior":
			return "warrior"
		"unit_worker":
			return "worker"
		_:
			return ""
