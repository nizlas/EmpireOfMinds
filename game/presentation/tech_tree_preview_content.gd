# Prototype tech-tree preview item content (presentation only).
class_name TechTreePreviewContent
extends RefCounted

const NodeLayoutScript = preload("res://presentation/tech_tree_node_layout.gd")
const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")

const ICON_DIR: String = "res://assets/prototype/tech_tree/"
const STONE_TOOLS_ID: String = "stone_tools"
const EXOPLANET_EXPEDITION_ID: String = "exoplanet_expedition"

const TECH_ICON_PATH_BY_ID: Dictionary = {
	STONE_TOOLS_ID: ICON_DIR + "stone_tools.png",
	"foraging_systems": ICON_DIR + "Foraging Systems.png",
	"controlled_fire": ICON_DIR + "Controlled Fire.png",
	"animal_tracking": ICON_DIR + "Animal Tracking.png",
	"pottery_craft": ICON_DIR + "Pottery Craft.png",
	"basic_mining": ICON_DIR + "Basic Mining.png",
	"textile_work": ICON_DIR + "Textile Work.png",
	"agrarian_practice": ICON_DIR + "Agrarian Practice.png",
	"pastoral_herding": ICON_DIR + "Pastoral Herding.png",
	"river_irrigation": ICON_DIR + "River Irrigation.png",
	"fishing_methods": ICON_DIR + "Fishing Methods.png",
	"oral_surveying": ICON_DIR + "Oral Surveying.png",
	"seasonal_calendars": ICON_DIR + "Seasonal Calendars.png",
	"timber_working": ICON_DIR + "Timber Working.png",
	"mudbrick_construction": ICON_DIR + "Mudbrick Construction.png",
	"counting_marks": ICON_DIR + "Counting Marks.png",
	"glyphic_records": ICON_DIR + "Glyphic Records.png",
	"bronze_alloying": ICON_DIR + "Bronze Alloying.png",
	"wheelwrighting": ICON_DIR + "Wheelwrighting.png",
	"simple_levers": ICON_DIR + "Simple Levers.png",
	EXOPLANET_EXPEDITION_ID: ICON_DIR + "Expoplanet Expedition.png",
}


static func prototype_nodes() -> Array[Dictionary]:
	return NodeLayoutScript.prototype_nodes(tech_registry_for_layout())


static func tech_registry_for_layout() -> Dictionary:
	var out: Dictionary = {}
	var ids: Array[String] = ScienceUnlocksScript.science_ids()
	var i: int = 0
	while i < ids.size():
		var tech_id: String = ids[i]
		var entry: Dictionary = tech_by_id(tech_id)
		if not entry.is_empty():
			out[tech_id] = entry
		i += 1
	return out


static func tech_by_id(tech_id: String) -> Dictionary:
	var key: String = str(tech_id).strip_edges()
	if not ScienceUnlocksScript.has_science(key):
		return {}
	if not TECH_ICON_PATH_BY_ID.has(key):
		return {}
	var science: Dictionary = ScienceUnlocksScript.get_science(key)
	var out: Dictionary = {
		"id": key,
		"title": str(science.get("title", "")),
		"icon_path": str(TECH_ICON_PATH_BY_ID[key]),
		"bullets": (science.get("ui_bullets", []) as Array).duplicate(),
	}
	var flags: Dictionary = science.get("flags", {}) as Dictionary
	var fi: int = 0
	var flag_keys: Array = flags.keys()
	while fi < flag_keys.size():
		var flag_key: String = str(flag_keys[fi])
		out[flag_key] = flags[flag_key]
		fi += 1
	return out


static func node_layout_for_tech_id(tech_id: String) -> Dictionary:
	return NodeLayoutScript.layout_for_tech_id(tech_id, tech_registry_for_layout())


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
	return ScienceUnlocksScript.science_ids()


static func all_icon_paths() -> Array[String]:
	var paths: Array[String] = []
	var ids: Array[String] = all_tech_ids()
	var i: int = 0
	while i < ids.size():
		var entry: Dictionary = tech_by_id(ids[i])
		paths.append(str(entry.get("icon_path", "")))
		i += 1
	return paths
