# Immutable progress (knowledge / science) definitions registry. Metadata only — no enforcement. See docs/PROGRESSION_MODEL.md.
# Target IDs may reference future systems; Phase 3.4b does not validate cross-registry links. No preloads.
class_name ProgressDefinitions
extends RefCounted

const _ORDERED_IDS: Array = [
	"foraging_systems",
	"stone_tools",
	"controlled_fire",
	"oral_surveying",
	"animal_tracking",
]

const _DEFINITIONS: Dictionary = {
	"foraging_systems":
	{
		"id": "foraging_systems",
		"display_name": "Foraging Systems",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "early_food_scouting_survival",
		"description": "Early food gathering, camps, and simple survival practices.",
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "scout_camp"},
			{"target_type": "specialist", "target_id": "forager"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "forest_food_bonus"},
			{"target_type": "modifier", "target_id": "outside_borders_healing"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "survival_knowledge"},
			{"target_type": "science", "target_id": "woodland_logistics"},
		],
	},
	"stone_tools":
	{
		"id": "stone_tools",
		"display_name": "Stone Tools",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "early_tools_stoneworking_production",
		"description": "Basic tools, stone working, and early production.",
		"concrete_unlocks": [
			{"target_type": "unit", "target_id": "worker"},
			{"target_type": "tile_improvement", "target_id": "quarry"},
			{"target_type": "unit_upgrade", "target_id": "basic_melee_equipment"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "stone_production_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "masonry"},
			{"target_type": "science", "target_id": "mining"},
			{"target_type": "science", "target_id": "toolmaking"},
		],
	},
	"controlled_fire":
	{
		"id": "controlled_fire",
		"display_name": "Controlled Fire",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "settlement_survival_growth_material_handling",
		"description": "Fire control for food, shelter, warmth, and early material handling.",
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "hearth"},
			{"target_type": "action", "target_id": "camp_clearing"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "cold_terrain_growth_bonus"},
			{"target_type": "modifier", "target_id": "small_health_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "pottery"},
			{"target_type": "science", "target_id": "metallurgy"},
			{"target_type": "science", "target_id": "settlement_comfort"},
		],
	},
	"oral_surveying":
	{
		"id": "oral_surveying",
		"display_name": "Oral Surveying",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "terrain_memory_mapping_landmarks",
		"description": "Oral map knowledge, landmarks, and remembered terrain.",
		"concrete_unlocks": [
			{"target_type": "map_feature", "target_id": "landmark_markers"},
			{"target_type": "action", "target_id": "map_notes"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "improved_scout_sight_memory"},
			{"target_type": "modifier", "target_id": "revisit_terrain_movement_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "cartography"},
			{"target_type": "science", "target_id": "administration"},
			{"target_type": "science", "target_id": "writing"},
		],
	},
	"animal_tracking":
	{
		"id": "animal_tracking",
		"display_name": "Animal Tracking",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "hunting_observation_detection",
		"description": "Tracking, hunting, and observing animal movement patterns.",
		"concrete_unlocks": [
			{"target_type": "unit", "target_id": "tracker"},
			{"target_type": "tile_improvement", "target_id": "hunting_camp"},
		],
		"systemic_effects": [
			{"target_type": "resource_visibility", "target_id": "reveal_animal_resources"},
			{"target_type": "modifier", "target_id": "ambush_detection_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "animal_domestication"},
			{"target_type": "science", "target_id": "riding"},
			{"target_type": "science", "target_id": "hunting_traditions"},
		],
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


static func category(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["category"])


static func era_bucket(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["era_bucket"])


static func concrete_unlocks(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["concrete_unlocks"] as Array).duplicate(true)


static func systemic_effects(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["systemic_effects"] as Array).duplicate(true)


static func future_dependencies(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["future_dependencies"] as Array).duplicate(true)
