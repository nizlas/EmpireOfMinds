# Headless: canonical unit_unlock_id → marker asset paths.
extends SceneTree

const UnitUnlockAssetsScript = preload("res://domain/content/unit_unlock_assets.gd")
const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")

const _NEW_ASSET_UNLOCK_IDS: Array[String] = [
	"unit_worker",
	"unit_slinger",
	"unit_bronze_armed_warrior",
	"unit_archer",
	"unit_tracker_scout",
	"unit_mounted_scout_precursor",
	"unit_war_canoe",
	"unit_reed_boat",
	"unit_cart_support",
	"unit_siege_precursor",
]

const _EXPECTED_FILENAMES: Dictionary = {
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

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_paths()
	_test_assets_exist_and_load()
	_test_science_unit_asset_coverage()
	_test_baseline_asset_rows()
	_test_raft_not_registered()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_registry_paths() -> void:
	var i: int = 0
	while i < _NEW_ASSET_UNLOCK_IDS.size():
		var unlock_id: String = _NEW_ASSET_UNLOCK_IDS[i]
		_check(UnitUnlockAssetsScript.has_unlock_id(unlock_id), "registry has %s" % unlock_id)
		_check(
			UnitUnlockAssetsScript.marker_filename_for_unlock_id(unlock_id)
				== str(_EXPECTED_FILENAMES[unlock_id]),
			"filename for %s" % unlock_id,
		)
		var path: String = UnitUnlockAssetsScript.marker_path_for_unlock_id(unlock_id)
		_check(path.begins_with(UnitUnlockAssetsScript.MARKER_DIR), "path under marker dir for %s" % unlock_id)
		i += 1


func _test_assets_exist_and_load() -> void:
	var i: int = 0
	while i < UnitUnlockAssetsScript.ORDERED_UNLOCK_IDS.size():
		var unlock_id: String = UnitUnlockAssetsScript.ORDERED_UNLOCK_IDS[i]
		_check(
			UnitUnlockAssetsScript.marker_exists_for_unlock_id(unlock_id),
			"marker exists for %s" % unlock_id,
		)
		var path: String = UnitUnlockAssetsScript.marker_path_for_unlock_id(unlock_id)
		var tex = load(path)
		_check(tex is Texture2D, "marker loads as texture: %s" % unlock_id)
		i += 1


func _test_science_unit_asset_coverage() -> void:
	var mappings: Dictionary = {
		"stone_tools": ["unit_worker", "unit_slinger"],
		"animal_tracking": ["unit_tracker_scout"],
		"pastoral_herding": ["unit_mounted_scout_precursor"],
		"fishing_methods": ["unit_reed_boat"],
		"timber_working": ["unit_archer", "unit_war_canoe"],
		"bronze_alloying": ["unit_bronze_armed_warrior"],
		"wheelwrighting": ["unit_cart_support"],
		"simple_levers": ["unit_siege_precursor"],
	}
	var science_ids: Array = mappings.keys()
	var si: int = 0
	while si < science_ids.size():
		var science_id: String = str(science_ids[si])
		var expected_ids: Array = mappings[science_id]
		var unlocks: Array = ScienceUnlocksScript.unlocks_for(science_id)
		var found: Array[String] = []
		var ui: int = 0
		while ui < unlocks.size():
			var unlock: Dictionary = unlocks[ui] as Dictionary
			if ScienceUnlocksScript.UNIT_UNLOCK_TYPES.has(str(unlock.get("type", ""))):
				var unlock_id: String = str(unlock.get("id", ""))
				found.append(unlock_id)
				_check(
					UnitUnlockAssetsScript.marker_exists_for_unlock_id(unlock_id),
					"science unit %s has asset (%s)" % [unlock_id, science_id],
				)
			ui += 1
		_check(found == expected_ids, "science unit ids for %s" % science_id)
		si += 1


func _test_baseline_asset_rows() -> void:
	var rows: Array[Dictionary] = StartingUnitsScript.unit_rows()
	_check(rows.size() == 2, "two baseline rows")
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = rows[i]
		var unlock_id: String = str(row.get("id", ""))
		_check(not str(row.get("asset_path", "")).is_empty(), "baseline asset_path for %s" % unlock_id)
		_check(
			UnitUnlockAssetsScript.marker_exists_for_unlock_id(unlock_id),
			"baseline marker exists for %s" % unlock_id,
		)
		i += 1


func _test_raft_not_registered() -> void:
	_check(not UnitUnlockAssetsScript.has_unlock_id("unit_raft"), "unit_raft not in asset registry")
	_check(ScienceUnlocksScript.find_unlock("unit_raft").is_empty(), "unit_raft not in ScienceUnlocks")
