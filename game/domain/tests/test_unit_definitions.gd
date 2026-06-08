# Headless: canonical unit_* gameplay definitions + legacy settler/warrior gameplay API.
extends SceneTree

const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const ScienceUnlocksScript = preload("res://domain/content/science_unlocks.gd")
const StartingUnitsScript = preload("res://domain/content/starting_units.gd")

const _ACTIVE_UNIT_IDS: Array[String] = [
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

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_canonical_registry()
	_test_key_stats()
	_test_cart_support_profiles()
	_test_siege_precursor_profile()
	_test_raft_absent()
	_test_science_and_baseline_unchanged()
	_test_legacy_gameplay_api()
	_test_enrich_unit_row()
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


func _test_canonical_registry() -> void:
	_check(UnitDefinitionsScript.unit_ids().size() == 12, "twelve canonical unit ids")
	var i: int = 0
	while i < _ACTIVE_UNIT_IDS.size():
		var unit_id: String = _ACTIVE_UNIT_IDS[i]
		_check(UnitDefinitionsScript.has_unit(unit_id), "has_unit %s" % unit_id)
		var unit: Dictionary = UnitDefinitionsScript.get_unit(unit_id)
		_check(not unit.is_empty(), "get_unit %s" % unit_id)
		_check(str(unit.get("name", "")).length() > 0, "name for %s" % unit_id)
		_check(int(unit.get("hp", 0)) == 100, "hp 100 for %s" % unit_id)
		i += 1
	var all_units: Array[Dictionary] = UnitDefinitionsScript.all_units()
	_check(all_units.size() == 12, "all_units count")


func _test_key_stats() -> void:
	var bronze: Dictionary = UnitDefinitionsScript.get_unit("unit_bronze_armed_warrior")
	_check(int(bronze.get("melee_strength", 0)) == 30, "bronze melee 30")
	_check(int(bronze.get("production_cost", 0)) == 75, "bronze cost 75")

	var archer: Dictionary = UnitDefinitionsScript.get_unit("unit_archer")
	_check(int(archer.get("ranged_strength", 0)) == 25, "archer ranged 25")
	_check(int(archer.get("attack_range", 0)) == 2, "archer range 2")

	var slinger: Dictionary = UnitDefinitionsScript.get_unit("unit_slinger")
	_check(int(slinger.get("ranged_strength", 0)) == 15, "slinger ranged 15")
	_check(int(slinger.get("attack_range", 0)) == 1, "slinger range 1")

	var reed: Dictionary = UnitDefinitionsScript.get_unit("unit_reed_boat")
	_check(int(reed.get("cargo_capacity", 0)) == 1, "reed boat cargo 1")
	_check(UnitDefinitionsScript.has_tag("unit_reed_boat", "naval"), "reed naval tag")
	_check(UnitDefinitionsScript.has_tag("unit_reed_boat", "transport"), "reed transport tag")
	_check(UnitDefinitionsScript.has_tag("unit_reed_boat", "cargo"), "reed cargo tag")

	var canoe: Dictionary = UnitDefinitionsScript.get_unit("unit_war_canoe")
	_check(UnitDefinitionsScript.has_tag("unit_war_canoe", "military"), "war canoe military tag")
	_check(UnitDefinitionsScript.has_tag("unit_war_canoe", "naval"), "war canoe naval tag")

	_check(UnitDefinitionsScript.cost_for("unit_settler") == 80, "settler cost api")
	_check(UnitDefinitionsScript.movement_for("unit_tracker_scout") == 3, "tracker movement api")


func _test_cart_support_profiles() -> void:
	var cart: Dictionary = UnitDefinitionsScript.get_unit("unit_cart_support")
	_check(int(cart.get("charges", 0)) == 3, "cart charges 3")
	var aura: Dictionary = cart.get("support_aura", {}) as Dictionary
	_check(int(aura.get("movement_bonus", 0)) == 1, "cart aura +1 movement")
	_check(int(aura.get("radius", 0)) == 1, "cart aura radius 1")
	_check(bool(aura.get("stacks", true)) == false, "cart aura non-stacking")
	var action: Dictionary = cart.get("support_action", {}) as Dictionary
	_check(int(action.get("heal_amount", 0)) == 15, "cart heal 15")
	_check(
		bool(action.get("remove_unit_when_charges_spent", false)),
		"cart removed when charges spent",
	)


func _test_siege_precursor_profile() -> void:
	var siege: Dictionary = UnitDefinitionsScript.get_unit("unit_siege_precursor")
	var profile: Dictionary = siege.get("siege_profile", {}) as Dictionary
	var effective: Array = profile.get("effective_against", [])
	var poor: Array = profile.get("poor_against", [])
	_check(effective.has("palisade"), "effective vs palisade")
	_check(effective.has("barricade"), "effective vs barricade")
	_check(effective.has("field_fortification"), "effective vs field_fortification")
	_check(poor.has("mudbrick_wall"), "poor vs mudbrick_wall")
	_check(poor.has("early_wall"), "poor vs early_wall")
	_check(poor.has("stone_wall"), "poor vs stone_wall")


func _test_raft_absent() -> void:
	_check(not UnitDefinitionsScript.has_unit("unit_raft"), "unit_raft not defined")


func _test_science_and_baseline_unchanged() -> void:
	_check(StartingUnitsScript.has_unit_id("unit_settler"), "baseline settler")
	_check(StartingUnitsScript.has_unit_id("unit_warrior"), "baseline warrior")
	_check(
		ScienceUnlocksScript.find_unlock("unit_worker").get("name", "") == "Worker",
		"science still unlocks worker",
	)
	_check(
		ScienceUnlocksScript.find_unlock("unit_mounted_scout_precursor").get("name", "") == "Mounted Scout",
		"science still unlocks mounted scout precursor",
	)


func _test_legacy_gameplay_api() -> void:
	_check(UnitDefinitionsScript.has("settler"), "legacy has settler")
	_check(UnitDefinitionsScript.has("warrior"), "legacy has warrior")
	_check(not UnitDefinitionsScript.has("worker"), "legacy no worker gameplay type")

	var ds: Dictionary = UnitDefinitionsScript.get_definition("settler") as Dictionary
	_check(ds["id"] == "settler", "legacy settler id")
	_check(ds["display_name"] == "Settler", "legacy settler display_name")
	_check(bool(ds["can_found_city"]), "legacy settler can_found_city")
	_check(int(ds["production_cost"]) == 80, "legacy settler production_cost")
	_check(int(ds["max_movement"]) == 2, "legacy settler movement")
	_check(int(ds["combat_strength"]) == 0, "legacy settler combat_strength")

	var dw: Dictionary = UnitDefinitionsScript.get_definition("warrior") as Dictionary
	_check(int(dw["production_cost"]) == 40, "legacy warrior production_cost")
	_check(int(dw["combat_strength"]) == 20, "legacy warrior combat_strength")
	_check(not bool(dw["can_found_city"]), "legacy warrior cannot found")

	_check(UnitDefinitionsScript.get_definition("nope") == null, "legacy unknown null")
	var dup1: Dictionary = UnitDefinitionsScript.get_definition("settler") as Dictionary
	dup1["display_name"] = "mutated"
	var dup2: Dictionary = UnitDefinitionsScript.get_definition("settler") as Dictionary
	_check(dup2["display_name"] == "Settler", "legacy deep dup independent")

	var ids0: Array = UnitDefinitionsScript.ids() as Array
	_check(ids0.size() == 2 and ids0[0] == "settler" and ids0[1] == "warrior", "legacy ids order")

	_check(UnitDefinitionsScript.can_found_city("settler"), "can_found settler")
	_check(not UnitDefinitionsScript.can_found_city("warrior"), "cannot_found warrior")
	_check(UnitDefinitionsScript.max_movement_for_type("warrior") == 2, "legacy warrior MP")
	_check(UnitDefinitionsScript.max_hp_for_type("warrior") == 100, "legacy warrior max_hp")
	_check(UnitDefinitionsScript.combat_strength_for_type("warrior") == 20, "legacy warrior str")


func _test_enrich_unit_row() -> void:
	var row: Dictionary = {"id": "unit_archer", "name": "Archer", "summary": "Unlock summary."}
	var enriched: Dictionary = UnitDefinitionsScript.enrich_unit_row(row)
	_check(int(enriched.get("ranged_strength", 0)) == 25, "enrich archer ranged")
	_check(int(enriched.get("attack_range", 0)) == 2, "enrich archer range")
	_check(str(enriched.get("summary", "")) == "Unlock summary.", "enrich keeps existing summary")
	var tags: Array = enriched.get("unit_tags", [])
	_check(tags.has("ranged"), "enrich tags include ranged")
