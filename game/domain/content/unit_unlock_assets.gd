# Canonical unit_unlock_id → prototype map marker asset paths (content/presentation only).
class_name UnitUnlockAssets
extends RefCounted

const MARKER_DIR: String = "res://assets/prototype/map_markers/"

## unit_unlock_id → marker filename under MARKER_DIR (snake_case ids, filenames from asset drop).
const MARKER_FILENAME_BY_UNLOCK_ID: Dictionary = {
	"unit_worker": "worker.png",
	"unit_slinger": "slinger.png",
	"unit_bronze_armed_warrior": "bronze_armed_warrior.png",
	"unit_archer": "archer.png",
	"unit_tracker_scout": "tracker_scout.png",
	"unit_mounted_scout_precursor": "mounted_scout.png",
	"unit_war_canoe": "war_canoe.png",
	"unit_reed_boat": "reed_boat.png",
	"unit_cart_support": "cart_support_unit.png",
	"unit_siege_precursor": "siege_precursor.png",
	"unit_settler": "unit_settler_marker.png",
	"unit_warrior": "unit_warrior_marker.png",
}

const ORDERED_UNLOCK_IDS: Array[String] = [
	"unit_settler",
	"unit_warrior",
	"unit_worker",
	"unit_slinger",
	"unit_tracker_scout",
	"unit_mounted_scout_precursor",
	"unit_reed_boat",
	"unit_archer",
	"unit_war_canoe",
	"unit_bronze_armed_warrior",
	"unit_cart_support",
	"unit_siege_precursor",
]


static func has_unlock_id(unlock_id: String) -> bool:
	return MARKER_FILENAME_BY_UNLOCK_ID.has(str(unlock_id).strip_edges())


static func marker_filename_for_unlock_id(unlock_id: String) -> String:
	var key: String = str(unlock_id).strip_edges()
	if not MARKER_FILENAME_BY_UNLOCK_ID.has(key):
		return ""
	return str(MARKER_FILENAME_BY_UNLOCK_ID[key])


static func marker_path_for_unlock_id(unlock_id: String) -> String:
	var filename: String = marker_filename_for_unlock_id(unlock_id)
	if filename.is_empty():
		return ""
	return MARKER_DIR + filename


static func marker_exists_for_unlock_id(unlock_id: String) -> bool:
	var path: String = marker_path_for_unlock_id(unlock_id)
	if path.is_empty():
		return false
	return ResourceLoader.exists(path)


static func enrich_unlock_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = row.duplicate(true)
	var unlock_id: String = str(out.get("id", ""))
	var path: String = marker_path_for_unlock_id(unlock_id)
	if not path.is_empty():
		out["asset_path"] = path
	return out
