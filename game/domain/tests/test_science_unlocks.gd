# Headless: canonical Ancient/Foundation science unlock bundles (content only).
extends SceneTree

const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")
const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

const _BASELINE_UNIT_IDS: Array[String] = [
	"unit_settler",
	"unit_warrior",
]

const _SCIENCE_UNIT_UNLOCK_IDS: Array[String] = [
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

const _ANCIENT_FOUNDATION_IDS: Array[String] = [
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
]

const _SCIENCES_WITH_UNIT_CARD_BULLETS: Dictionary = {
	"stone_tools": ["Worker", "Slinger"],
	"animal_tracking": ["Tracker Scout"],
	"pastoral_herding": ["Mounted Scout"],
	"fishing_methods": ["Reed Boat"],
	"timber_working": ["Archer", "War Canoe"],
	"bronze_alloying": ["Bronze-Armed Warrior"],
	"wheelwrighting": ["Cart Support Unit"],
	"simple_levers": ["Siege Precursor"],
}

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_shape()
	_test_baseline_starting_units()
	_test_science_unit_unlock_ids()
	_test_science_to_unit_mappings()
	_test_raft_removed()
	_test_tech_card_bullets_from_unlocks()
	_test_fishing_naval_rules()
	_test_timber_war_canoe_rule()
	_test_preview_integration()
	await _test_overlay_still_renders()
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


func _unlock_ids_for(science_id: String) -> Array[String]:
	var ids: Array[String] = []
	var unlocks: Array = ScienceUnlocksScript.unlocks_for(science_id)
	var i: int = 0
	while i < unlocks.size():
		ids.append(str((unlocks[i] as Dictionary).get("id", "")))
		i += 1
	return ids


func _unit_ids_for(science_id: String) -> Array[String]:
	var ids: Array[String] = []
	var unlocks: Array = ScienceUnlocksScript.unlocks_for(science_id)
	var i: int = 0
	while i < unlocks.size():
		var unlock: Dictionary = unlocks[i] as Dictionary
		if ScienceUnlocksScript.UNIT_UNLOCK_TYPES.has(str(unlock.get("type", ""))):
			ids.append(str(unlock.get("id", "")))
		i += 1
	return ids


func _has_unlock_type(science_id: String, unlock_type: String) -> bool:
	var unlocks: Array = ScienceUnlocksScript.unlocks_for(science_id)
	var i: int = 0
	while i < unlocks.size():
		var unlock: Dictionary = unlocks[i] as Dictionary
		if str(unlock.get("type", "")) == unlock_type:
			return true
		i += 1
	return false


func _test_registry_shape() -> void:
	_check(ScienceUnlocksScript.ancient_foundation_count() == 20, "twenty Ancient/Foundation sciences")
	var ids: Array[String] = ScienceUnlocksScript.science_ids()
	_check(ids.size() == 21, "twenty-one total science ids including Exoplanet")
	var seen: Dictionary = {}
	var i: int = 0
	while i < _ANCIENT_FOUNDATION_IDS.size():
		var science_id: String = _ANCIENT_FOUNDATION_IDS[i]
		_check(ScienceUnlocksScript.has_science(science_id), "Ancient/Foundation science exists: %s" % science_id)
		_check(not seen.has(science_id), "no duplicate science id: %s" % science_id)
		seen[science_id] = true
		var science: Dictionary = ScienceUnlocksScript.get_science(science_id)
		_check(str(science.get("era", "")) == ScienceUnlocksScript.ERA_ANCIENT_FOUNDATIONS, "era for %s" % science_id)
		_check(ScienceUnlocksScript.unlocks_for(science_id).size() >= 1, "unlocks for %s" % science_id)
		var stored_bullets: Array = science.get("ui_bullets", [])
		_check(stored_bullets.is_empty(), "no stored placeholder ui_bullets for %s" % science_id)
		var card_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for(science_id)
		if _SCIENCES_WITH_UNIT_CARD_BULLETS.has(science_id):
			_check(
				card_bullets == _SCIENCES_WITH_UNIT_CARD_BULLETS[science_id],
				"tech card unit bullets for %s" % science_id,
			)
		else:
			_check(card_bullets.is_empty(), "non-unit science has empty tech card bullets: %s" % science_id)
		i += 1
	_check(ScienceUnlocksScript.has_science("exoplanet_expedition"), "Exoplanet Expedition exists")
	_check(_has_unlock_type("exoplanet_expedition", "victory"), "Exoplanet Expedition has victory unlock")
	var exo: Dictionary = ScienceUnlocksScript.get_science("exoplanet_expedition")
	var exo_bullets: Array = exo.get("ui_bullets", [])
	_check(exo_bullets.size() == 3, "Exoplanet keeps manual ui_bullets")
	_check(
		str(exo_bullets[2]) == "Victory to the first civilization to reach this point",
		"Exoplanet victory bullet preserved",
	)


func _test_baseline_starting_units() -> void:
	_check(StartingUnitsScript.ORDERED_UNIT_IDS.size() == 2, "two baseline units")
	var rows: Array[Dictionary] = StartingUnitsScript.unit_rows()
	_check(rows.size() == 2, "baseline unit rows")
	_check(StartingUnitsScript.has_unit_id("unit_settler"), "baseline has settler id")
	_check(StartingUnitsScript.has_unit_id("unit_warrior"), "baseline has warrior id")
	_check(
		ScienceUnlocksScript.find_unlock("unit_warrior").is_empty(),
		"warrior is not a science unlock",
	)
	_check(
		ScienceUnlocksScript.find_unlock("unit_settler").is_empty(),
		"settler is not a science unlock",
	)
	var i: int = 0
	while i < rows.size():
		var row: Dictionary = rows[i]
		_check(
			str(row.get("science_title", "")) == StartingUnitsScript.BASELINE_SOURCE_LABEL,
			"baseline row source label",
		)
		i += 1


func _test_science_unit_unlock_ids() -> void:
	var i: int = 0
	while i < _SCIENCE_UNIT_UNLOCK_IDS.size():
		var unlock_id: String = _SCIENCE_UNIT_UNLOCK_IDS[i]
		var unlock: Dictionary = ScienceUnlocksScript.find_unlock(unlock_id)
		_check(not unlock.is_empty(), "science unit unlock exists: %s" % unlock_id)
		_check(
			ScienceUnlocksScript.UNIT_UNLOCK_TYPES.has(str(unlock.get("type", ""))),
			"science unit unlock type for %s" % unlock_id,
		)
		i += 1


func _test_science_to_unit_mappings() -> void:
	_check(
		_unit_ids_for("stone_tools") == ["unit_worker", "unit_slinger"],
		"Stone Tools unit unlock ids",
	)
	_check(
		_unit_ids_for("animal_tracking") == ["unit_tracker_scout"],
		"Animal Tracking unit unlock ids",
	)
	_check(
		_unit_ids_for("timber_working") == ["unit_archer", "unit_war_canoe"],
		"Timber Working unit unlock ids",
	)
	_check(
		_unit_ids_for("pastoral_herding") == ["unit_mounted_scout_precursor"],
		"Pastoral Herding unit unlock ids",
	)
	var mounted: Dictionary = ScienceUnlocksScript.find_unlock("unit_mounted_scout_precursor")
	_check(str(mounted.get("name", "")) == "Mounted Scout", "Mounted Scout display name")
	_check(
		ScienceUnlocksScript.find_unlock("unit_mounted_scout").is_empty(),
		"legacy unit_mounted_scout id removed",
	)


func _test_raft_removed() -> void:
	_check(ScienceUnlocksScript.find_unlock("unit_raft").is_empty(), "unit_raft removed from ScienceUnlocks")
	_check(not _unlock_ids_for("timber_working").has("unit_raft"), "Timber Working does not unlock raft")


func _test_tech_card_bullets_from_unlocks() -> void:
	var stone_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for("stone_tools")
	_check(stone_bullets == ["Worker", "Slinger"], "Stone Tools lists worker and slinger")
	_check(not stone_bullets.has("Warrior"), "Stone Tools does not list Warrior")
	var tracking_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for("animal_tracking")
	_check(tracking_bullets == ["Tracker Scout"], "Animal Tracking lists Tracker Scout only")
	_check(not tracking_bullets.has("Archer"), "Animal Tracking does not list Archer")
	var timber_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for("timber_working")
	_check(timber_bullets == ["Archer", "War Canoe"], "Timber Working lists Archer and War Canoe")
	_check(not timber_bullets.has("Raft"), "Timber Working does not list Raft")
	var exo_card_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for("exoplanet_expedition")
	_check(
		exo_card_bullets.has("Victory to the first civilization to reach this point"),
		"Exoplanet tech card keeps manual victory bullet",
	)


func _test_fishing_naval_rules() -> void:
	var unlock_ids: Array[String] = _unlock_ids_for("fishing_methods")
	_check(unlock_ids.has("unit_reed_boat"), "Fishing Methods unlocks unit_reed_boat")
	_check(
		unlock_ids.has("rule_reed_boat_transport_shallow_water"),
		"Fishing Methods includes rule_reed_boat_transport_shallow_water",
	)
	var reed_rule: Dictionary = ScienceUnlocksScript.find_unlock("rule_reed_boat_transport_shallow_water")
	_check(not reed_rule.is_empty(), "reed boat transport rule exists")
	var metadata: Dictionary = reed_rule.get("metadata", {}) as Dictionary
	_check(int(metadata.get("cargo_capacity", -1)) == 1, "reed boat cargo_capacity is 1")


func _test_timber_war_canoe_rule() -> void:
	var unlock_ids: Array[String] = _unlock_ids_for("timber_working")
	_check(unlock_ids.has("unit_war_canoe"), "Timber Working unlocks unit_war_canoe")
	_check(unlock_ids.has("unit_archer"), "Timber Working unlocks unit_archer")
	var war_canoe_rule: Dictionary = ScienceUnlocksScript.find_unlock("rule_war_canoe_no_cargo_v0")
	_check(not war_canoe_rule.is_empty(), "war canoe no-cargo rule exists")
	var metadata: Dictionary = war_canoe_rule.get("metadata", {}) as Dictionary
	_check(int(metadata.get("cargo_capacity", -1)) == 0, "war canoe cargo_capacity is 0")


func _test_preview_integration() -> void:
	var ids: Array[String] = ContentScript.all_tech_ids()
	_check(ids.size() == 21, "preview exposes twenty-one tech ids")
	var i: int = 0
	while i < ids.size():
		var tech_id: String = ids[i]
		_check(ScienceUnlocksScript.has_science(tech_id), "preview tech resolves to science: %s" % tech_id)
		var preview_entry: Dictionary = ContentScript.tech_by_id(tech_id)
		_check(not preview_entry.is_empty(), "preview entry for %s" % tech_id)
		var science: Dictionary = ScienceUnlocksScript.get_science(tech_id)
		_check(
			str(preview_entry.get("title", "")) == str(science.get("title", "")),
			"preview title matches science for %s" % tech_id,
		)
		var expected_bullets: Array = ScienceUnlocksScript.tech_card_bullets_for(tech_id)
		_check(
			preview_entry.get("bullets", []) == expected_bullets,
			"preview bullets match tech_card_bullets_for %s" % tech_id,
		)
		i += 1
	var exo: Dictionary = ContentScript.tech_by_id(ContentScript.EXOPLANET_EXPEDITION_ID)
	_check(bool(exo.get("end_science", false)), "preview exoplanet end_science flag preserved")


func _test_overlay_still_renders() -> void:
	var overlay: TechTreeOverlayScript = TechTreeOverlayScript.new()
	get_root().add_child(overlay)
	for _i in 2:
		await process_frame
	overlay.open_overlay()
	_check(overlay._tech_items.size() == 21, "overlay still renders twenty-one tech items")
	_check(overlay._dependency_lines.polylines.size() > 0, "overlay still draws dependency lines")
	overlay.queue_free()
