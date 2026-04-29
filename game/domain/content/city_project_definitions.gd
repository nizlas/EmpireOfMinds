# Immutable city project definitions registry. See docs/CITIES.md, CONTENT_MODEL.md (steering).
# produces_unit_type values reference UnitDefinitions rows (e.g. warrior) — not enforced at runtime.
class_name CityProjectDefinitions
extends RefCounted

const _UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

const PROJECT_ID_NONE: String = "none"

const _ORDERED_IDS: Array = ["produce_unit:warrior"]

const _DEFINITIONS: Dictionary = {
	"produce_unit:warrior":
	{
		"id": "produce_unit:warrior",
		"display_name": "Train Warrior",
		"project_type": "produce_unit",
		"produces_unit_type": "warrior",
		"cost": 2,
		"role": "basic_unit_training",
	},
}


static func has(id: String) -> bool:
	return _DEFINITIONS.has(id)


static func ids() -> Array:
	return (_ORDERED_IDS as Array).duplicate()


static func get_definition(id: String):
	if not _DEFINITIONS.has(id):
		return null
	var src: Dictionary = _DEFINITIONS[id]
	return src.duplicate(true)


static func project_type(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["project_type"])


static func cost(id: String) -> int:
	if not _DEFINITIONS.has(id):
		return 0
	return int((_DEFINITIONS[id] as Dictionary)["cost"])


static func produces_unit_type(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["produces_unit_type"])


static func is_supported_project_id(id: String) -> bool:
	if id == PROJECT_ID_NONE:
		return false
	return has(id)
