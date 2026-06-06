# Canonical v0 Ancient/Foundation science unlock bundles (content references only).
# See docs/CONTENT_MODEL.md. No gameplay interpretation in this slice.
class_name ScienceUnlocks
extends RefCounted

const ERA_ANCIENT_FOUNDATIONS: String = "ancient_foundations"

const ORDERED_SCIENCE_IDS: Array[String] = [
	"foraging_systems",
	"stone_tools",
	"controlled_fire",
	"oral_surveying",
	"animal_tracking",
	"seasonal_calendars",
	"pottery_craft",
	"textile_work",
	"agrarian_practice",
	"pastoral_herding",
	"river_irrigation",
	"fishing_methods",
	"basic_mining",
	"timber_working",
	"mudbrick_construction",
	"counting_marks",
	"glyphic_records",
	"bronze_alloying",
	"wheelwrighting",
	"simple_levers",
	"exoplanet_expedition",
]

static var _SCIENCES: Dictionary = {}

const UNIT_UNLOCK_TYPES: Array[String] = [
	"unit",
	"support_unit",
	"naval_unit",
]

const EXOPLANET_EXPEDITION_ID: String = "exoplanet_expedition"


static func _registry() -> Dictionary:
	if not _SCIENCES.is_empty():
		return _SCIENCES
	_SCIENCES = {
	"foraging_systems": _science(
		"foraging_systems",
		"Foraging Systems",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_scout_camp", "Scout Camp", "Early scouting post outside the city."),
			_u(
				"tile_improvement",
				"improvement_foraging_camp",
				"Foraging Camp",
				"Light camp for gathering food from wilderness tiles.",
			),
			_u(
				"modifier",
				"modifier_wilderness_food_bonus",
				"Wilderness Food",
				"+food from wilderness, forest, and berries.",
			),
		],
	),
	"stone_tools": _science(
		"stone_tools",
		"Stone Tools",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("unit", "unit_worker", "Worker", "Basic worker unit for improvements and extraction."),
			_u("unit", "unit_slinger", "Slinger", "Primitive ranged unit using thrown stones."),
			_u("tile_improvement", "improvement_quarry", "Quarry", "Extract stone from hills."),
			_u(
				"modifier",
				"modifier_stone_hill_production",
				"Stone Production",
				"+production from stone and hills.",
			),
		],
	),
	"controlled_fire": _science(
		"controlled_fire",
		"Controlled Fire",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_hearth", "Hearth", "City hearth for warmth and settlement life."),
			_u("action", "action_camp_clearing", "Camp Clearing", "Clear campsites in the field."),
			_u(
				"modifier",
				"modifier_hearth_healing_growth",
				"Hearth Support",
				"Faster healing and small city growth support.",
			),
		],
	),
	"oral_surveying": _science(
		"oral_surveying",
		"Oral Surveying",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u(
				"city_building",
				"building_landmark_post",
				"Landmark Post",
				"Map-room precursor for remembered routes.",
			),
			_u("action", "action_place_landmark", "Place Landmark", "Mark landmarks and map notes in the field."),
			_u(
				"modifier",
				"modifier_scout_map_memory",
				"Scout Memory",
				"Scout sight memory and faster revisits.",
			),
		],
	),
	"animal_tracking": _science(
		"animal_tracking",
		"Animal Tracking",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("unit", "unit_tracker_scout", "Tracker Scout", "Scout focused on trails and pursuit."),
			_u("tile_improvement", "improvement_hunting_camp", "Hunting Camp", "Camp for hunters and game trails."),
			_u(
				"modifier",
				"modifier_animal_reveal_ambush",
				"Animal Awareness",
				"Reveal animal resources and ambush detection.",
			),
		],
	),
	"seasonal_calendars": _science(
		"seasonal_calendars",
		"Seasonal Calendars",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u(
				"city_building",
				"building_granary_precursor",
				"Granary Precursor",
				"Early granary planning structure.",
			),
			_u("project", "project_harvest_planning", "Harvest Planning", "City project to align harvest timing."),
			_u(
				"modifier",
				"modifier_food_stability",
				"Food Stability",
				"Food stability and reduced famine risk.",
			),
		],
	),
	"pottery_craft": _science(
		"pottery_craft",
		"Pottery Craft",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_pottery_workshop", "Pottery Workshop", "Craft and fire storage vessels."),
			_u("city_building", "building_storage", "Storage", "City storage for surplus goods."),
			_u(
				"modifier",
				"modifier_storage_growth",
				"Storage Growth",
				"Storage-based growth support.",
			),
		],
	),
	"textile_work": _science(
		"textile_work",
		"Textile Work",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_weaver_hut", "Weaver Hut", "Spin rope and rough textiles."),
			_u("material", "material_rope", "Rope", "Rope for tents and early rigging."),
			_u("material", "material_textiles", "Textiles", "Cloth for tents and weather gear."),
			_u(
				"modifier",
				"modifier_textile_weather_movement",
				"Textile Mobility",
				"Rough-weather movement; enables fishing support.",
			),
		],
	),
	"agrarian_practice": _science(
		"agrarian_practice",
		"Agrarian Practice",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_farm", "Farm", "Worked farm tiles for stable food."),
			_u("specialist", "specialist_farmer", "Farmer", "Farmer specialist for worked farms."),
			_u(
				"modifier",
				"modifier_stable_food_production",
				"Stable Farms",
				"Stable food production from farms.",
			),
		],
	),
	"pastoral_herding": _science(
		"pastoral_herding",
		"Pastoral Herding",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_pasture", "Pasture", "Pasture tiles for livestock."),
			_u("unit", "unit_mounted_scout", "Mounted Scout", "Early mounted scout capability."),
			_u(
				"modifier",
				"modifier_livestock_yield",
				"Livestock Yield",
				"Food and production from livestock.",
			),
		],
	),
	"river_irrigation": _science(
		"river_irrigation",
		"River Irrigation",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_irrigated_farm", "Irrigated Farm", "Farm boosted by river water."),
			_u("tile_improvement", "improvement_canal_ditch", "Canal Ditch", "Small canal works near rivers."),
			_u(
				"modifier",
				"modifier_river_food_drought",
				"River Food",
				"+food near rivers and drought resistance.",
			),
		],
	),
	"fishing_methods": _science(
		"fishing_methods",
		"Fishing Methods",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_fishing_boats", "Fishing Boats", "Boats for coastal and lake food."),
			_u("tile_improvement", "improvement_coastal_village", "Coastal Village", "Settlement pattern on coasts."),
			_u("naval_unit", "unit_reed_boat", "Reed Boat", "Early reed boat for shallow water."),
			_u(
				"rule",
				"rule_all_water_is_shallow_v0",
				"Shallow Water v0",
				"All water is shallow water in v0.",
			),
			_u(
				"rule",
				"rule_land_units_need_transport_for_water_v0",
				"Land Units Need Transport",
				"Land units cannot enter water by themselves.",
			),
			_u(
				"rule",
				"rule_reed_boat_transport_shallow_water",
				"Reed Boat Transport",
				"Reed Boat carries exactly one land unit across shallow water.",
				{"cargo_capacity": 1},
			),
			_u(
				"modifier",
				"modifier_coastal_food",
				"Coastal Food",
				"+food from coasts and lakes.",
			),
		],
	),
	"basic_mining": _science(
		"basic_mining",
		"Basic Mining",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_mine", "Mine", "Mine hills for ore and stone."),
			_u("specialist", "specialist_miner", "Miner", "Miner specialist for extraction."),
			_u(
				"modifier",
				"modifier_hill_mine_production",
				"Hill Mining",
				"+production from hills.",
			),
		],
	),
	"timber_working": _science(
		"timber_working",
		"Timber Working",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("tile_improvement", "improvement_lumber_camp", "Lumber Camp", "Camp for timber extraction."),
			_u("city_building", "building_palisade", "Palisade", "Early wooden city defense."),
			_u("unit", "unit_archer", "Archer", "Primitive bow-armed ranged unit."),
			_u("naval_unit", "unit_war_canoe", "War Canoe", "Early offensive canoe; no cargo."),
			_u(
				"rule",
				"rule_war_canoe_no_cargo_v0",
				"War Canoe No Cargo",
				"War Canoe has no cargo capacity in v0.",
				{"cargo_capacity": 0},
			),
			_u(
				"modifier",
				"modifier_faster_early_buildings",
				"Timber Construction",
				"Faster early buildings and frames.",
			),
		],
	),
	"mudbrick_construction": _science(
		"mudbrick_construction",
		"Mudbrick Construction",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_mudbrick_housing", "Mudbrick Housing", "Sun-dried brick housing."),
			_u("city_building", "building_storage_hall", "Storage Hall", "Civic storage from mudbrick."),
			_u("city_building", "building_early_walls", "Early Walls", "Early city walls from mudbrick."),
			_u(
				"modifier",
				"modifier_housing_capacity",
				"Housing Capacity",
				"+housing and urban capacity.",
			),
		],
	),
	"counting_marks": _science(
		"counting_marks",
		"Counting Marks",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_storehouse_ledger", "Storehouse Ledger", "Tally ledger for stored goods."),
			_u(
				"system",
				"system_inventory_accounting",
				"Inventory Accounting",
				"Track surplus and allocations.",
			),
			_u(
				"modifier",
				"modifier_admin_from_surplus",
				"Administrative Surplus",
				"+gold and administration from surplus.",
			),
		],
	),
	"glyphic_records": _science(
		"glyphic_records",
		"Glyphic Records",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("city_building", "building_archive_hut", "Archive Hut", "Store inscriptions and orders."),
			_u("system", "system_written_orders", "Written Orders", "Written orders from administration."),
			_u(
				"modifier",
				"modifier_science_from_administration",
				"Administrative Science",
				"+science and culture from administration.",
			),
		],
	),
	"bronze_alloying": _science(
		"bronze_alloying",
		"Bronze Alloying",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("unit", "unit_bronze_armed_warrior", "Bronze-Armed Warrior", "Warrior equipped with bronze arms."),
			_u("city_building", "building_armory", "Armory", "City armory for bronze gear."),
			_u("material", "material_bronze_tools", "Bronze Tools", "Bronze tools for mines and workshops."),
			_u(
				"modifier",
				"modifier_bronze_mine_melee",
				"Bronze Power",
				"Improved mine production and stronger melee.",
			),
		],
	),
	"wheelwrighting": _science(
		"wheelwrighting",
		"Wheelwrighting",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("support_unit", "unit_cart_support", "Cart Support Unit", "Cart support for settlers and cargo."),
			_u(
				"modifier",
				"modifier_road_cargo_trade",
				"Road Cargo",
				"Road cargo bonus and trade capacity.",
			),
			_u(
				"modifier",
				"modifier_road_settler_movement",
				"Road Movement",
				"Faster settler movement on roads.",
			),
		],
	),
	"simple_levers": _science(
		"simple_levers",
		"Simple Levers",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u("project", "project_stone_lifting", "Stone-Lifting Project", "Lever project for heavy stone work."),
			_u("unit", "unit_siege_precursor", "Siege Precursor", "Early siege engineering precursor."),
			_u(
				"modifier",
				"modifier_construction_efficiency",
				"Construction Efficiency",
				"Faster walls, monuments, and construction.",
			),
		],
	),
	"exoplanet_expedition": _science(
		"exoplanet_expedition",
		"Exoplanet Expedition",
		ERA_ANCIENT_FOUNDATIONS,
		[
			_u(
				"project",
				"project_final_horizon_mission",
				"Final Horizon Mission",
				"Launch beyond the known world.",
			),
			_u(
				"victory",
				"victory_first_to_complete",
				"First To Complete",
				"First civilization to complete this science wins.",
			),
		],
		{"end_science": true, "special": "minimatch_end_science"},
		[
			"Final horizon mission",
			"Launch beyond the known world",
			"Victory to the first civilization to reach this point",
		],
	),
	}
	return _SCIENCES


static func _u(
	type: String,
	id: String,
	name: String,
	summary: String,
	metadata: Dictionary = {},
) -> Dictionary:
	var row: Dictionary = {
		"type": type,
		"id": id,
		"name": name,
		"summary": summary,
	}
	if not metadata.is_empty():
		row["metadata"] = metadata.duplicate()
	return row


static func _science(
	id: String,
	title: String,
	era: String,
	unlocks: Array,
	flags: Dictionary = {},
	ui_bullets: Array = [],
) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"era": era,
		"unlocks": unlocks,
		"ui_bullets": ui_bullets,
		"flags": flags,
	}


static func science_ids() -> Array[String]:
	return ORDERED_SCIENCE_IDS.duplicate()


static func all_sciences() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i: int = 0
	while i < ORDERED_SCIENCE_IDS.size():
		out.append(get_science(ORDERED_SCIENCE_IDS[i]))
		i += 1
	return out


static func has_science(science_id: String) -> bool:
	return _registry().has(str(science_id).strip_edges())


static func get_science(science_id: String) -> Dictionary:
	var key: String = str(science_id).strip_edges()
	var registry: Dictionary = _registry()
	if not registry.has(key):
		return {}
	return (registry[key] as Dictionary).duplicate(true)


static func unlocks_for(science_id: String) -> Array:
	var science: Dictionary = get_science(science_id)
	if science.is_empty():
		return []
	return (science.get("unlocks", []) as Array).duplicate(true)


static func ui_bullets_for(science_id: String) -> Array:
	return tech_card_bullets_for(science_id)


## Tech-tree card bullets: unit/support/naval display names only; Exoplanet keeps manual ui_bullets.
static func tech_card_bullets_for(science_id: String) -> Array:
	var key: String = str(science_id).strip_edges()
	if key == EXOPLANET_EXPEDITION_ID:
		var science: Dictionary = get_science(key)
		if science.is_empty():
			return []
		return (science.get("ui_bullets", []) as Array).duplicate()
	return _unit_unlock_names_from_science(get_science(key))


static func _unit_unlock_names_from_science(science: Dictionary) -> Array:
	if science.is_empty():
		return []
	var unlocks: Array = science.get("unlocks", [])
	var out: Array = []
	var ui: int = 0
	while ui < unlocks.size():
		var unlock: Dictionary = unlocks[ui] as Dictionary
		if UNIT_UNLOCK_TYPES.has(str(unlock.get("type", ""))):
			var name: String = str(unlock.get("name", "")).strip_edges()
			if not name.is_empty():
				out.append(name)
		ui += 1
	return out


static func find_unlock(unlock_id: String) -> Dictionary:
	var target: String = str(unlock_id).strip_edges()
	var i: int = 0
	while i < ORDERED_SCIENCE_IDS.size():
		var science_id: String = ORDERED_SCIENCE_IDS[i]
		var unlocks: Array = unlocks_for(science_id)
		var ui: int = 0
		while ui < unlocks.size():
			var unlock: Dictionary = unlocks[ui] as Dictionary
			if str(unlock.get("id", "")) == target:
				var out: Dictionary = unlock.duplicate(true)
				out["science_id"] = science_id
				return out
			ui += 1
		i += 1
	return {}


static func ancient_foundation_count() -> int:
	return ORDERED_SCIENCE_IDS.size() - 1
