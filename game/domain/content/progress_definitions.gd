# Immutable progress (knowledge / science) definitions registry. Phase 5.1.12b: cost + prerequisites on sciences.
# See docs/PROGRESSION_MODEL.md. No preloads of other registries.
class_name ProgressDefinitions
extends RefCounted

## Curated column order (Ancient tree); `ids()` returns this order. `ScienceAvailability.available_for` preserves it for auto-target.
const _ORDERED_IDS: Array = [
	"foraging_systems",
	"stone_tools",
	"controlled_fire",
	"oral_surveying",
	"animal_tracking",
	"seasonal_calendars",
	"pottery_craft",
	"textile_work",
	"basic_mining",
	"timber_working",
	"agrarian_practice",
	"counting_marks",
	"mudbrick_construction",
	"simple_levers",
	"pastoral_herding",
	"river_irrigation",
	"bronze_alloying",
	"wheelwrighting",
	"glyphic_records",
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
		"cost": 6,
		"prerequisites": [],
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
		"cost": 6,
		"prerequisites": [],
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
		"cost": 6,
		"prerequisites": [],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "hearth"},
			{"target_type": "action", "target_id": "camp_clearing"},
			{"target_type": "modifier", "target_id": "controlled_fire_practice"},
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
		"cost": 6,
		"prerequisites": [],
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
		"cost": 10,
		"prerequisites": ["foraging_systems", "oral_surveying"],
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
	"seasonal_calendars":
	{
		"id": "seasonal_calendars",
		"display_name": "Seasonal Calendars",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "timekeeping_planting_cycles",
		"description": "Tracking seasons, planting windows, and recurring natural cycles.",
		"cost": 10,
		"prerequisites": ["foraging_systems", "controlled_fire"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "storage_hall"},
			{"target_type": "modifier", "target_id": "seasonal_harvest_timing"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "planting_cycle_efficiency"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "astronomy"},
		],
	},
	"pottery_craft":
	{
		"id": "pottery_craft",
		"display_name": "Pottery Craft",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "storage_cooking_containers",
		"description": "Fired clay vessels for storage, cooking, and trade goods.",
		"cost": 10,
		"prerequisites": ["controlled_fire"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "pottery_workshop"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "granary_capacity_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "glazing"},
		],
	},
	"textile_work":
	{
		"id": "textile_work",
		"display_name": "Textile Work",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "fiber_cordage_travel_gear",
		"description": "Fibers, cordage, and simple fabrics for gear and travel.",
		"cost": 10,
		"prerequisites": ["foraging_systems"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "weaver_hut"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "travel_fatigue_reduction"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "dyeing"},
		],
	},
	"basic_mining":
	{
		"id": "basic_mining",
		"display_name": "Basic Mining",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "surface_ore_extraction",
		"description": "Surface pits, soft ore gathering, and early stone flux.",
		"cost": 10,
		"prerequisites": ["stone_tools"],
		"concrete_unlocks": [
			{"target_type": "tile_improvement", "target_id": "surface_mine"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "ore_yield_small_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "deep_mining"},
		],
	},
	"timber_working":
	{
		"id": "timber_working",
		"display_name": "Timber Working",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "wood_frame_tools",
		"description": "Carpentry, timber frames, and structural wood use.",
		"cost": 10,
		"prerequisites": ["stone_tools", "controlled_fire"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "woodwright_shop"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "wood_production_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "shipbuilding"},
		],
	},
	"agrarian_practice":
	{
		"id": "agrarian_practice",
		"display_name": "Agrarian Practice",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "sedentary_farming",
		"description": "Field preparation, staple crops, and village-scale farming.",
		"cost": 14,
		"prerequisites": ["pottery_craft", "seasonal_calendars"],
		"concrete_unlocks": [
			{"target_type": "tile_improvement", "target_id": "grain_field"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "food_surplus_growth"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "irrigation_engineering"},
		],
	},
	"counting_marks":
	{
		"id": "counting_marks",
		"display_name": "Counting Marks",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "tally_admin_records",
		"description": "Tallies, allocation marks, and early administrative memory.",
		"cost": 14,
		"prerequisites": ["pottery_craft", "oral_surveying"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "storehouse_ledger"},
			{"target_type": "action", "target_id": "tally_ledger"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "corruption_resistance_small"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "glyphic_records"},
		],
	},
	"mudbrick_construction":
	{
		"id": "mudbrick_construction",
		"display_name": "Mudbrick Construction",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "cheap_structures",
		"description": "Sun-dried bricks and simple civic structures.",
		"cost": 14,
		"prerequisites": ["timber_working"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "mudbrick_housing"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "city_hp_small_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "stonemasonry"},
		],
	},
	"simple_levers":
	{
		"id": "simple_levers",
		"display_name": "Simple Levers",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "mechanical_advantage",
		"description": "Leverage, wedges, and simple machines for labor.",
		"cost": 14,
		"prerequisites": ["stone_tools"],
		"concrete_unlocks": [
			{"target_type": "modifier", "target_id": "construction_speed_small"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "carry_capacity_edge"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "geared_devices"},
		],
	},
	"pastoral_herding":
	{
		"id": "pastoral_herding",
		"display_name": "Pastoral Herding",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "mobile_livestock",
		"description": "Herd movement, grazing circuits, and mobile pastoralism.",
		"cost": 18,
		"prerequisites": ["animal_tracking"],
		"concrete_unlocks": [
			{"target_type": "unit", "target_id": "herder"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "pasture_yield_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "animal_husbandry"},
		],
	},
	"river_irrigation":
	{
		"id": "river_irrigation",
		"display_name": "River Irrigation",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "channel_water_field",
		"description": "Channels, shaduf-style lifts, and river-adjacent fields.",
		"cost": 18,
		"prerequisites": ["seasonal_calendars"],
		"concrete_unlocks": [
			{"target_type": "tile_improvement", "target_id": "irrigation_ditch"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "arid_crop_resilience"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "aqueducts"},
		],
	},
	"bronze_alloying":
	{
		"id": "bronze_alloying",
		"display_name": "Bronze Alloying",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "copper_tin_working",
		"description": "Charcoal smelting, ore blending, and early bronze implements.",
		"cost": 18,
		"prerequisites": ["basic_mining"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "armory"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "melee_unit_small_bonus"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "iron_working"},
		],
	},
	"wheelwrighting":
	{
		"id": "wheelwrighting",
		"display_name": "Wheelwrighting",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "wheels_axles",
		"description": "Wheel hubs, axles, and draft-ready carts.",
		"cost": 18,
		"prerequisites": ["timber_working"],
		"concrete_unlocks": [
			{"target_type": "unit", "target_id": "cart"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "land_trade_range_small"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "cavalry_tack"},
		],
	},
	"glyphic_records":
	{
		"id": "glyphic_records",
		"display_name": "Glyphic Records",
		"category": "science",
		"era_bucket": "ancient_foundations",
		"role": "formal_records_symbols",
		"description": "Symbolic marks, tablets, and durable external memory.",
		"cost": 18,
		"prerequisites": ["counting_marks"],
		"concrete_unlocks": [
			{"target_type": "building", "target_id": "archive_hut"},
		],
		"systemic_effects": [
			{"target_type": "modifier", "target_id": "science_cost_small_discount"},
		],
		"future_dependencies": [
			{"target_type": "science", "target_id": "law_codes"},
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


static func is_science(id: String) -> bool:
	return has(id) and category(id) == "science"


static func cost(id: String) -> int:
	if not _DEFINITIONS.has(id):
		return 6
	var row: Dictionary = _DEFINITIONS[id]
	if not row.has("cost"):
		return 6
	var c = row["cost"]
	if typeof(c) != TYPE_INT:
		c = int(c)
	c = int(c)
	if c < 1:
		return 6
	return c


static func prerequisites(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	if not row.has("prerequisites"):
		return []
	var p = row["prerequisites"]
	if typeof(p) != TYPE_ARRAY:
		return []
	var out: Array = []
	var i = 0
	while i < p.size():
		out.append(str(p[i]))
		i = i + 1
	return out


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
