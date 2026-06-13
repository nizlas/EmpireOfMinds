# Immutable city project definitions registry. See docs/CITIES.md, CONTENT_MODEL.md (steering).
# produces_unit_type values reference UnitDefinitions rows (e.g. warrior) — not enforced at runtime.
class_name CityProjectDefinitions
extends RefCounted

const _UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

const PROJECT_ID_NONE: String = "none"
const PROJECT_TYPE_PRODUCE_UNIT: String = "produce_unit"
const PROJECT_TYPE_BUILD_BUILDING: String = "build_building"
const PROJECT_ID_BUILD_HEARTH: String = "build:hearth"
const BUILDING_ID_HEARTH: String = "hearth"
const PROJECT_ID_BUILD_POTTERY_WORKSHOP: String = "build:pottery_workshop"
const BUILDING_ID_POTTERY_WORKSHOP: String = "pottery_workshop"
const PROJECT_ID_BUILD_STORAGE_HALL: String = "build:storage_hall"
const BUILDING_ID_STORAGE_HALL: String = "storage_hall"
const PROJECT_ID_BUILD_WEAVER_HUT: String = "build:weaver_hut"
const BUILDING_ID_WEAVER_HUT: String = "weaver_hut"
const PROJECT_ID_BUILD_MUDBRICK_HOUSING: String = "build:mudbrick_housing"
const BUILDING_ID_MUDBRICK_HOUSING: String = "mudbrick_housing"
const PROJECT_ID_BUILD_STOREHOUSE_LEDGER: String = "build:storehouse_ledger"
const BUILDING_ID_STOREHOUSE_LEDGER: String = "storehouse_ledger"
const PROJECT_ID_BUILD_ARCHIVE_HUT: String = "build:archive_hut"
const BUILDING_ID_ARCHIVE_HUT: String = "archive_hut"
const PROJECT_ID_BUILD_ARMORY: String = "build:armory"
const BUILDING_ID_ARMORY: String = "armory"

## Deterministic order for LegalActions enumeration and registry `ids()`.
const LEGAL_PROJECT_ORDER: Array = [
	"produce_unit:warrior",
	"produce_unit:settler",
	"build:hearth",
	"build:pottery_workshop",
	"build:storage_hall",
	"build:weaver_hut",
	"build:mudbrick_housing",
	"build:storehouse_ledger",
	"build:archive_hut",
	"build:armory",
]

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
	"produce_unit:settler":
	{
		"id": "produce_unit:settler",
		"display_name": "Train Settler",
		"project_type": "produce_unit",
		"produces_unit_type": "settler",
		"cost": 2,
		"role": "founder_unit_training",
	},
	PROJECT_ID_BUILD_HEARTH:
	{
		"id": PROJECT_ID_BUILD_HEARTH,
		"display_name": "Build Hearth",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_HEARTH,
		"cost": 2,
		"role": "controlled_fire_building",
	},
	PROJECT_ID_BUILD_POTTERY_WORKSHOP:
	{
		"id": PROJECT_ID_BUILD_POTTERY_WORKSHOP,
		"display_name": "Build Pottery Workshop",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_POTTERY_WORKSHOP,
		"cost": 2,
		"role": "pottery_craft_building",
	},
	PROJECT_ID_BUILD_STORAGE_HALL:
	{
		"id": PROJECT_ID_BUILD_STORAGE_HALL,
		"display_name": "Build Storage Hall",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_STORAGE_HALL,
		"cost": 2,
		"role": "seasonal_calendars_building",
	},
	PROJECT_ID_BUILD_WEAVER_HUT:
	{
		"id": PROJECT_ID_BUILD_WEAVER_HUT,
		"display_name": "Build Weaver Hut",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_WEAVER_HUT,
		"cost": 2,
		"role": "textile_work_building",
	},
	PROJECT_ID_BUILD_MUDBRICK_HOUSING:
	{
		"id": PROJECT_ID_BUILD_MUDBRICK_HOUSING,
		"display_name": "Build Mudbrick Housing",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_MUDBRICK_HOUSING,
		"cost": 2,
		"role": "mudbrick_construction_building",
	},
	PROJECT_ID_BUILD_STOREHOUSE_LEDGER:
	{
		"id": PROJECT_ID_BUILD_STOREHOUSE_LEDGER,
		"display_name": "Build Storehouse Ledger",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_STOREHOUSE_LEDGER,
		"cost": 2,
		"role": "counting_marks_building",
	},
	PROJECT_ID_BUILD_ARCHIVE_HUT:
	{
		"id": PROJECT_ID_BUILD_ARCHIVE_HUT,
		"display_name": "Build Archive Hut",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_ARCHIVE_HUT,
		"cost": 2,
		"role": "glyphic_records_building",
	},
	PROJECT_ID_BUILD_ARMORY:
	{
		"id": PROJECT_ID_BUILD_ARMORY,
		"display_name": "Build Armory",
		"project_type": PROJECT_TYPE_BUILD_BUILDING,
		"produces_building_id": BUILDING_ID_ARMORY,
		"cost": 2,
		"role": "bronze_alloying_building",
	},
}


static func has(id: String) -> bool:
	return _DEFINITIONS.has(id)


static func ids() -> Array:
	return (LEGAL_PROJECT_ORDER as Array).duplicate()


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
	return String((_DEFINITIONS[id] as Dictionary).get("produces_unit_type", ""))


static func produces_building_id(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary).get("produces_building_id", ""))


static func is_supported_project_id(id: String) -> bool:
	if id == PROJECT_ID_NONE:
		return false
	return has(id)


static func city_has_building(city, building_id: String) -> bool:
	if city == null or building_id == "":
		return false
	var ids_arr = city.building_ids
	var i: int = 0
	while i < ids_arr.size():
		if str(ids_arr[i]) == building_id:
			return true
		i = i + 1
	return false


static func is_project_blocked_for_city(city, project_id: String) -> bool:
	if city == null or not has(project_id):
		return true
	var ptype: String = project_type(project_id)
	if ptype == PROJECT_TYPE_BUILD_BUILDING:
		return city_has_building(city, produces_building_id(project_id))
	return false


static func is_project_unlocked(progress_state, owner_id: int, project_id: String) -> bool:
	if progress_state == null or not has(project_id):
		return false
	var ptype: String = project_type(project_id)
	if ptype == PROJECT_TYPE_PRODUCE_UNIT:
		return progress_state.has_unlocked_target(owner_id, "city_project", project_id)
	if ptype == PROJECT_TYPE_BUILD_BUILDING:
		var bid: String = produces_building_id(project_id)
		return bid != "" and progress_state.has_unlocked_target(owner_id, "building", bid)
	return false
