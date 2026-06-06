# Prototype tech-tree preview item content (presentation only).
class_name TechTreePreviewContent
extends RefCounted

const NodeLayoutScript = preload("res://presentation/tech_tree_node_layout.gd")

const ICON_DIR: String = "res://assets/prototype/tech_tree/"
const STONE_TOOLS_ID: String = "stone_tools"
const EXOPLANET_EXPEDITION_ID: String = "exoplanet_expedition"

const TECH_BY_ID: Dictionary = {
	STONE_TOOLS_ID: {
		"id": STONE_TOOLS_ID,
		"title": "Stone Tools",
		"icon_path": ICON_DIR + "stone_tools.png",
		"bullets": [
			"Basic stoneworking",
			"Worker enablement",
			"Quarry / mine precursor",
			"Production from hills & stone",
		],
	},
	"foraging_systems": {
		"id": "foraging_systems",
		"title": "Foraging Systems",
		"icon_path": ICON_DIR + "Foraging Systems.png",
		"bullets": [
			"Wild food gathering",
			"Scout / forager bonus",
			"Survival outside cities",
			"Faster field healing",
		],
	},
	"controlled_fire": {
		"id": "controlled_fire",
		"title": "Controlled Fire",
		"icon_path": ICON_DIR + "Controlled Fire.png",
		"bullets": [
			"Hearth",
			"Camp clearing",
			"Health & survival bonus",
			"New settlement support",
		],
	},
	"animal_tracking": {
		"id": "animal_tracking",
		"title": "Animal Tracking",
		"icon_path": ICON_DIR + "Animal Tracking.png",
		"bullets": [
			"Tracker / scout bonus",
			"Hunting camp",
			"Reveal animals",
			"Better pursuit and hunting",
		],
	},
	"pottery_craft": {
		"id": "pottery_craft",
		"title": "Pottery Craft",
		"icon_path": ICON_DIR + "Pottery Craft.png",
		"bullets": [
			"Storage vessels",
			"Pottery workshop",
			"Growth / food buffer",
			"Preserved supplies",
		],
	},
	"basic_mining": {
		"id": "basic_mining",
		"title": "Basic Mining",
		"icon_path": ICON_DIR + "Basic Mining.png",
		"bullets": [
			"Mines",
			"Ore awareness",
			"Hill production",
			"Early extraction",
		],
	},
	"textile_work": {
		"id": "textile_work",
		"title": "Textile Work",
		"icon_path": ICON_DIR + "Textile Work.png",
		"bullets": [
			"Weaver hut",
			"Rope production",
			"Tents for mobile units",
			"Rough weather movement",
		],
	},
	"agrarian_practice": {
		"id": "agrarian_practice",
		"title": "Agrarian Practice",
		"icon_path": ICON_DIR + "Agrarian Practice.png",
		"bullets": [
			"Farm improvement",
			"Farmer specialist",
			"Settler support bonus",
			"Stable food production",
		],
	},
	"pastoral_herding": {
		"id": "pastoral_herding",
		"title": "Pastoral Herding",
		"icon_path": ICON_DIR + "Pastoral Herding.png",
		"bullets": [
			"Pasture improvement",
			"Herder action",
			"Mounted scout precursor",
			"Livestock food + production",
		],
	},
	"river_irrigation": {
		"id": "river_irrigation",
		"title": "River Irrigation",
		"icon_path": ICON_DIR + "River Irrigation.png",
		"bullets": [
			"Irrigated farm",
			"Canal ditch",
			"Food near rivers",
			"Drought resistance",
		],
	},
	"fishing_methods": {
		"id": "fishing_methods",
		"title": "Fishing Methods",
		"icon_path": ICON_DIR + "Fishing Methods.png",
		"bullets": [
			"Fishing boats",
			"Coastal village",
			"Food from coast/lakes",
			"Early naval scout",
		],
	},
	"oral_surveying": {
		"id": "oral_surveying",
		"title": "Oral Surveying",
		"icon_path": ICON_DIR + "Oral Surveying.png",
		"bullets": [
			"Landmark markers",
			"Map notes",
			"Scout memory bonus",
			"Revisit movement bonus",
		],
	},
	"seasonal_calendars": {
		"id": "seasonal_calendars",
		"title": "Seasonal Calendars",
		"icon_path": ICON_DIR + "Seasonal Calendars.png",
		"bullets": [
			"Seasonal harvest timing",
			"Planting cycle bonus",
			"Planting windows",
			"Natural year cycles",
		],
	},
	"timber_working": {
		"id": "timber_working",
		"title": "Timber Working",
		"icon_path": ICON_DIR + "Timber Working.png",
		"bullets": [
			"Woodwright shop",
			"Wood production bonus",
			"Timber frames",
			"Structural carpentry",
		],
	},
	"mudbrick_construction": {
		"id": "mudbrick_construction",
		"title": "Mudbrick Construction",
		"icon_path": ICON_DIR + "Mudbrick Construction.png",
		"bullets": [
			"Mudbrick walls",
			"City durability bonus",
			"Sun-dried bricks",
			"Simple civic structures",
		],
	},
	"counting_marks": {
		"id": "counting_marks",
		"title": "Counting Marks",
		"icon_path": ICON_DIR + "Counting Marks.png",
		"bullets": [
			"Tally ledger",
			"Allocation marks",
			"Administrative memory",
			"Corruption resistance",
		],
	},
	"glyphic_records": {
		"id": "glyphic_records",
		"title": "Glyphic Records",
		"icon_path": ICON_DIR + "Glyphic Records.png",
		"bullets": [
			"Archive hut",
			"Monument inscriptions",
			"Science from administration",
			"Written orders",
		],
	},
	"bronze_alloying": {
		"id": "bronze_alloying",
		"title": "Bronze Alloying",
		"icon_path": ICON_DIR + "Bronze Alloying.png",
		"bullets": [
			"Bronze tools",
			"Armory",
			"Bronze-armed warriors",
			"Improved mine production",
		],
	},
	"wheelwrighting": {
		"id": "wheelwrighting",
		"title": "Wheelwrighting",
		"icon_path": ICON_DIR + "Wheelwrighting.png",
		"bullets": [
			"Cart support unit",
			"Road cargo bonus",
			"Faster road movement",
			"Trade capacity",
		],
	},
	"simple_levers": {
		"id": "simple_levers",
		"title": "Simple Levers",
		"icon_path": ICON_DIR + "Simple Levers.png",
		"bullets": [
			"Stone-lifting project",
			"Faster monuments",
			"Siege precursor",
			"Construction efficiency",
		],
	},
	EXOPLANET_EXPEDITION_ID: {
		"id": EXOPLANET_EXPEDITION_ID,
		"title": "Exoplanet Expedition",
		"icon_path": ICON_DIR + "Expoplanet Expedition.png",
		"special": "minimatch_end_science",
		"end_science": true,
		"bullets": [
			"Final horizon mission",
			"Launch beyond the known world",
			"Victory to the first civilization to reach this point",
		],
	},
}


static func prototype_nodes() -> Array[Dictionary]:
	return NodeLayoutScript.prototype_nodes(TECH_BY_ID)


static func tech_by_id(tech_id: String) -> Dictionary:
	var key: String = str(tech_id).strip_edges()
	if TECH_BY_ID.has(key):
		return TECH_BY_ID[key]
	return {}


static func node_layout_for_tech_id(tech_id: String) -> Dictionary:
	return NodeLayoutScript.layout_for_tech_id(tech_id, TECH_BY_ID)


static func body_text_from_content(content: Dictionary) -> String:
	var bullets: Array = content.get("bullets", [])
	var lines: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i < bullets.size():
		lines.append("• " + str(bullets[i]))
		i += 1
	return "\n".join(lines)


static func total_item_count() -> int:
	return NodeLayoutScript.total_node_count()


static func all_placements() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var nodes: Array[Dictionary] = prototype_nodes()
	var i: int = 0
	while i < nodes.size():
		var node: Dictionary = nodes[i]
		out.append(Vector3i(int(node["column"]), int(node["row"]), 0))
		i += 1
	return out


static func content_for_grid(column: int, row: int) -> Dictionary:
	var nodes: Array[Dictionary] = prototype_nodes()
	var i: int = 0
	while i < nodes.size():
		var node: Dictionary = nodes[i]
		if int(node["column"]) == column and int(node["row"]) == row:
			return node["content"] as Dictionary
		i += 1
	return {}


static func stone_tools_placement() -> Vector3i:
	var layout: Dictionary = NodeLayoutScript.layout_for_title("Stone Tools")
	return Vector3i(int(layout["column"]), int(layout["row"]), 0)


static func exoplanet_placement() -> Vector3i:
	var layout: Dictionary = NodeLayoutScript.layout_for_title("Exoplanet Expedition")
	return Vector3i(int(layout["column"]), int(layout["row"]), 0)


static func all_tech_ids() -> Array[String]:
	var ids: Array[String] = []
	var keys: Array = TECH_BY_ID.keys()
	keys.sort()
	var i: int = 0
	while i < keys.size():
		ids.append(str(keys[i]))
		i += 1
	return ids


static func all_icon_paths() -> Array[String]:
	var paths: Array[String] = []
	var ids: Array[String] = all_tech_ids()
	var i: int = 0
	while i < ids.size():
		var entry: Dictionary = tech_by_id(ids[i])
		paths.append(str(entry.get("icon_path", "")))
		i += 1
	return paths
