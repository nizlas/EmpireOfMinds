# Registry-defined yield effects for completed city buildings. Domain-only; no presentation imports.
# Science/build gating lives in ProgressDefinitions + CityProjectDefinitions — this file is yields only.
# See docs/CONTENT_MODEL.md
class_name BuildingDefinitions
extends RefCounted

const BUILDING_ID_PALACE: String = "palace"
const BUILDING_ID_HEARTH: String = "hearth"
const BUILDING_ID_POTTERY_WORKSHOP: String = "pottery_workshop"
const BUILDING_ID_STORAGE_HALL: String = "storage_hall"
const BUILDING_ID_WEAVER_HUT: String = "weaver_hut"
const BUILDING_ID_MUDBRICK_HOUSING: String = "mudbrick_housing"
const BUILDING_ID_STOREHOUSE_LEDGER: String = "storehouse_ledger"
const BUILDING_ID_ARCHIVE_HUT: String = "archive_hut"
const BUILDING_ID_ARMORY: String = "armory"

const _ORDERED_IDS: Array = [
	BUILDING_ID_PALACE,
	BUILDING_ID_HEARTH,
	BUILDING_ID_POTTERY_WORKSHOP,
	BUILDING_ID_STORAGE_HALL,
	BUILDING_ID_WEAVER_HUT,
	BUILDING_ID_MUDBRICK_HOUSING,
	BUILDING_ID_STOREHOUSE_LEDGER,
	BUILDING_ID_ARCHIVE_HUT,
	BUILDING_ID_ARMORY,
]

const _DEFINITIONS: Dictionary = {
	BUILDING_ID_PALACE:
	{
		"id": BUILDING_ID_PALACE,
		"display_name": "Palace",
		"yield_effects": {"food": 0, "production": 0, "science": 1, "coin": 1, "housing": 0},
	},
	BUILDING_ID_HEARTH:
	{
		"id": BUILDING_ID_HEARTH,
		"display_name": "Hearth",
		"yield_effects": {"food": 0, "production": 1, "science": 0, "coin": 0, "housing": 0},
	},
	BUILDING_ID_POTTERY_WORKSHOP:
	{
		"id": BUILDING_ID_POTTERY_WORKSHOP,
		"display_name": "Pottery Workshop",
		"yield_effects": {"food": 1, "production": 0, "science": 0, "coin": 0, "housing": 0},
	},
	BUILDING_ID_STORAGE_HALL:
	{
		"id": BUILDING_ID_STORAGE_HALL,
		"display_name": "Storage Hall",
		"yield_effects": {"food": 1, "production": 0, "science": 0, "coin": 0, "housing": 0},
	},
	BUILDING_ID_WEAVER_HUT:
	{
		"id": BUILDING_ID_WEAVER_HUT,
		"display_name": "Weaver Hut",
		"yield_effects": {"food": 0, "production": 0, "science": 0, "coin": 2, "housing": 0},
	},
	BUILDING_ID_MUDBRICK_HOUSING:
	{
		"id": BUILDING_ID_MUDBRICK_HOUSING,
		"display_name": "Mudbrick Housing",
		"yield_effects": {"food": 0, "production": 0, "science": 0, "coin": 0, "housing": 2},
	},
	BUILDING_ID_STOREHOUSE_LEDGER:
	{
		"id": BUILDING_ID_STOREHOUSE_LEDGER,
		"display_name": "Storehouse Ledger",
		"yield_effects": {"food": 0, "production": 0, "science": 0, "coin": 2, "housing": 0},
	},
	BUILDING_ID_ARCHIVE_HUT:
	{
		"id": BUILDING_ID_ARCHIVE_HUT,
		"display_name": "Archive Hut",
		"yield_effects": {"food": 0, "production": 0, "science": 2, "coin": 0, "housing": 0},
	},
	BUILDING_ID_ARMORY:
	{
		"id": BUILDING_ID_ARMORY,
		"display_name": "Armory",
		"yield_effects": {"food": 0, "production": 1, "science": 0, "coin": 0, "housing": 0},
	},
}


static func _empty_yield() -> Dictionary:
	return {"food": 0, "production": 0, "science": 0, "coin": 0, "housing": 0}


static func has(building_id: String) -> bool:
	return _DEFINITIONS.has(building_id)


static func ids() -> Array:
	return (_ORDERED_IDS as Array).duplicate()


static func get_definition(building_id: String):
	if not _DEFINITIONS.has(building_id):
		return null
	return (_DEFINITIONS[building_id] as Dictionary).duplicate(true)


static func display_name(building_id: String) -> String:
	if not _DEFINITIONS.has(building_id):
		return ""
	return str((_DEFINITIONS[building_id] as Dictionary).get("display_name", ""))


static func yield_effects(building_id: String) -> Dictionary:
	if not _DEFINITIONS.has(building_id):
		return _empty_yield()
	var raw = (_DEFINITIONS[building_id] as Dictionary).get("yield_effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return _empty_yield()
	var y: Dictionary = raw as Dictionary
	return {
		"food": int(y.get("food", 0)),
		"production": int(y.get("production", 0)),
		"science": int(y.get("science", 0)),
		"coin": int(y.get("coin", 0)),
		"housing": int(y.get("housing", 0)),
	}
