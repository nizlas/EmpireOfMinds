# Registry-driven building reward rows for tech-tree science nodes (presentation only).
class_name TechTreeBuildingRewards
extends RefCounted

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")

const EFFECT_ORDER: Array[String] = ["food", "production", "science", "coin", "housing"]

const YIELD_ICON_PATH_BY_KEY: Dictionary = {
	"food": "res://assets/prototype/yield_icons/food_resource.png",
	"production": "res://assets/prototype/yield_icons/production_resource.png",
	"science": "res://assets/prototype/yield_icons/science_resource.png",
	"coin": "res://assets/prototype/yield_icons/coin_resource.png",
}

## Passive recorded housing — no dedicated art yet; compact glyph fallback in UI.
const HOUSING_FALLBACK_GLYPH: String = "H"


static func building_rewards_for_science(science_id: String) -> Array:
	var key: String = str(science_id).strip_edges()
	if key.is_empty() or not ProgressDefinitionsScript.has(key):
		return []
	var unlocks: Array = ProgressDefinitionsScript.concrete_unlocks(key)
	var out: Array = []
	var ui: int = 0
	while ui < unlocks.size():
		var unlock: Dictionary = unlocks[ui] as Dictionary
		if str(unlock.get("target_type", "")) != "building":
			ui += 1
			continue
		var building_id: String = str(unlock.get("target_id", "")).strip_edges()
		if building_id.is_empty() or not BuildingDefinitionsScript.has(building_id):
			ui += 1
			continue
		var effects: Array = nonzero_effects_for_building(building_id)
		if effects.is_empty():
			ui += 1
			continue
		out.append(
			{
				"building_id": building_id,
				"display_name": BuildingDefinitionsScript.display_name(building_id),
				"effects": effects,
			}
		)
		ui += 1
	return out


static func nonzero_effects_for_building(building_id: String) -> Array:
	var yields: Dictionary = BuildingDefinitionsScript.yield_effects(building_id)
	var out: Array = []
	var ei: int = 0
	while ei < EFFECT_ORDER.size():
		var effect_key: String = EFFECT_ORDER[ei]
		var amount: int = int(yields.get(effect_key, 0))
		if amount > 0:
			out.append({"key": effect_key, "value": amount})
		ei += 1
	return out


static func icon_path_for_effect_key(effect_key: String) -> String:
	if effect_key == "housing":
		return ""
	return str(YIELD_ICON_PATH_BY_KEY.get(effect_key, ""))


static func effect_fallback_glyph(effect_key: String) -> String:
	if effect_key == "housing":
		return HOUSING_FALLBACK_GLYPH
	return ""


static func effect_value_text(value: int) -> String:
	return "+%d" % value
