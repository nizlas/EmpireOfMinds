# City Hub production option labels + building yield chips (presentation only).
class_name CityHubProductionDisplay
extends RefCounted

const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")

## Stable display order for City Hub production rows.
const EFFECT_ORDER: Array[String] = ["food", "production", "coin", "science", "housing"]

const YIELD_ICON_PATH_BY_KEY: Dictionary = {
	"food": "res://assets/prototype/yield_icons/food_resource.png",
	"production": "res://assets/prototype/yield_icons/production_resource.png",
	"coin": "res://assets/prototype/yield_icons/coin_resource.png",
	"science": "res://assets/prototype/yield_icons/science_resource.png",
}

const HOUSING_FALLBACK_GLYPH: String = "H"
const PRODUCTION_OPTION_ICON_HEIGHT_PX: int = 18
const PRODUCTION_OPTION_CHIP_GAP_PX: int = 6
const PRODUCTION_OPTION_VALUE_GAP_PX: int = 3


static func effect_chips_for_project(project_id: String) -> Array:
	var pid: String = str(project_id).strip_edges()
	if not pid.begins_with("build:"):
		return []
	if not CityProjectDefinitionsScript.has(pid):
		return []
	if (
		CityProjectDefinitionsScript.project_type(pid)
		!= CityProjectDefinitionsScript.PROJECT_TYPE_BUILD_BUILDING
	):
		return []
	var building_id: String = CityProjectDefinitionsScript.produces_building_id(pid)
	if building_id == "":
		return []
	return effect_chips_for_building(building_id)


static func effect_chips_for_building(building_id: String) -> Array:
	var bid: String = str(building_id).strip_edges()
	if bid.is_empty() or not BuildingDefinitionsScript.has(bid):
		return []
	var yields: Dictionary = BuildingDefinitionsScript.yield_effects(bid)
	var out: Array = []
	var ei: int = 0
	while ei < EFFECT_ORDER.size():
		var key: String = EFFECT_ORDER[ei]
		var amount: int = int(yields.get(key, 0))
		if amount > 0:
			out.append(
				{
					"key": key,
					"value": amount,
					"icon_path": icon_path_for_effect_key(key),
					"fallback_glyph": fallback_glyph_for_effect_key(key),
				}
			)
		ei += 1
	return out


static func icon_path_for_effect_key(effect_key: String) -> String:
	if effect_key == "housing":
		return ""
	return str(YIELD_ICON_PATH_BY_KEY.get(effect_key, ""))


static func fallback_glyph_for_effect_key(effect_key: String) -> String:
	if effect_key == "housing":
		return HOUSING_FALLBACK_GLYPH
	return ""


static func effect_value_text(value: int) -> String:
	return "+%d" % value
