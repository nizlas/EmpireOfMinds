# Headless: canonical Ancient/Foundation science unlock bundles (content only).
extends SceneTree

const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")
const TechTreeOverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")

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

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_shape()
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
		var bullets: Array = science.get("ui_bullets", [])
		_check(bullets.size() >= 1, "ui bullets for %s" % science_id)
		i += 1
	_check(ScienceUnlocksScript.has_science("exoplanet_expedition"), "Exoplanet Expedition exists")
	_check(_has_unlock_type("exoplanet_expedition", "victory"), "Exoplanet Expedition has victory unlock")


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
		_check(
			(preview_entry.get("bullets", []) as Array).size() >= 1,
			"preview bullets from science for %s" % tech_id,
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
