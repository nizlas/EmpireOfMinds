# Baseline producerable units at game start (content only; not production rules).
class_name StartingUnits
extends RefCounted

const BASELINE_SOURCE_LABEL: String = "Baseline"

const ORDERED_UNIT_IDS: Array[String] = [
	"unit_settler",
	"unit_warrior",
]

const _ROWS: Array[Dictionary] = [
	{
		"id": "unit_settler",
		"name": "Settler",
		"type": "unit",
		"science_id": "baseline",
		"science_title": BASELINE_SOURCE_LABEL,
		"summary": "Default producerable settler at game start.",
		"metadata": {"default_city_project": "produce_unit:settler"},
	},
	{
		"id": "unit_warrior",
		"name": "Warrior",
		"type": "unit",
		"science_id": "baseline",
		"science_title": BASELINE_SOURCE_LABEL,
		"summary": "Default producerable warrior at game start.",
		"metadata": {"default_city_project": "produce_unit:warrior"},
	},
]


static func unit_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i: int = 0
	while i < _ROWS.size():
		out.append((_ROWS[i] as Dictionary).duplicate(true))
		i += 1
	return out


static func has_unit_id(unit_id: String) -> bool:
	var key: String = str(unit_id).strip_edges()
	var i: int = 0
	while i < ORDERED_UNIT_IDS.size():
		if ORDERED_UNIT_IDS[i] == key:
			return true
		i += 1
	return false
