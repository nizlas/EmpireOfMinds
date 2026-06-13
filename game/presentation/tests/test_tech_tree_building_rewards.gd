# Headless: godot --headless --path game -s res://presentation/tests/test_tech_tree_building_rewards.gd
extends SceneTree

const RewardsScript = preload("res://presentation/tech_tree_building_rewards.gd")
const ContentScript = preload("res://presentation/tech_tree_preview_content.gd")
const OverlayScript = preload("res://presentation/tech_tree_preview_overlay.gd")
const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")

var _total = 0
var _any_fail = false


func _reward_at(science_id: String, index: int = 0) -> Dictionary:
	var rows: Array = RewardsScript.building_rewards_for_science(science_id)
	if index < 0 or index >= rows.size():
		return {}
	return rows[index] as Dictionary


func _effect_at(reward: Dictionary, index: int = 0) -> Dictionary:
	var effects: Array = reward.get("effects", [])
	if index < 0 or index >= effects.size():
		return {}
	return effects[index] as Dictionary


func _init() -> void:
	_test_controlled_fire_hearth()
	_test_textile_work_weaver_hut()
	_test_mudbrick_housing()
	_test_no_fake_reward_for_non_registry_building()
	_test_content_wires_registry_rewards()
	_test_icon_paths()
	_test_compact_reward_icon_size()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _test_controlled_fire_hearth() -> void:
	var reward: Dictionary = _reward_at("controlled_fire")
	_check(str(reward.get("display_name", "")) == "Hearth", "CF shows Hearth")
	_check(str(reward.get("building_id", "")) == "hearth", "CF building id hearth")
	var effect: Dictionary = _effect_at(reward)
	_check(str(effect.get("key", "")) == "production", "CF effect production")
	_check(int(effect.get("value", 0)) == 1, "CF production +1")


func _test_textile_work_weaver_hut() -> void:
	var reward: Dictionary = _reward_at("textile_work")
	_check(str(reward.get("display_name", "")) == "Weaver Hut", "textile shows Weaver Hut")
	var effect: Dictionary = _effect_at(reward)
	_check(str(effect.get("key", "")) == "coin", "textile effect coin")
	_check(int(effect.get("value", 0)) == 2, "textile coin +2")


func _test_mudbrick_housing() -> void:
	var reward: Dictionary = _reward_at("mudbrick_construction")
	_check(str(reward.get("display_name", "")) == "Mudbrick Housing", "mudbrick shows Mudbrick Housing")
	var effect: Dictionary = _effect_at(reward)
	_check(str(effect.get("key", "")) == "housing", "mudbrick effect housing")
	_check(int(effect.get("value", 0)) == 2, "mudbrick housing +2")
	_check(RewardsScript.icon_path_for_effect_key("housing") == "", "housing has no icon path")
	_check(RewardsScript.effect_fallback_glyph("housing") == "H", "housing glyph fallback")


func _test_no_fake_reward_for_non_registry_building() -> void:
	var foraging: Array = RewardsScript.building_rewards_for_science("foraging_systems")
	_check(foraging.is_empty(), "foraging has no BuildingDefinitions reward row")
	var timber: Array = RewardsScript.building_rewards_for_science("timber_working")
	_check(timber.is_empty(), "timber woodwright not in BuildingDefinitions")


func _test_content_wires_registry_rewards() -> void:
	var cf: Dictionary = ContentScript.tech_by_id("controlled_fire")
	var rewards: Array = cf.get("building_rewards", [])
	_check(rewards.size() == 1, "content includes CF reward")
	var registry_name: String = BuildingDefinitionsScript.display_name("hearth")
	_check(str((rewards[0] as Dictionary).get("display_name", "")) == registry_name, "content uses registry name")


func _test_icon_paths() -> void:
	_check(
		RewardsScript.icon_path_for_effect_key("food").ends_with("food_resource.png"),
		"food icon path"
	)
	_check(
		RewardsScript.icon_path_for_effect_key("production").ends_with("production_resource.png"),
		"production icon path"
	)
	_check(
		RewardsScript.icon_path_for_effect_key("science").ends_with("science_resource.png"),
		"science icon path"
	)
	_check(
		RewardsScript.icon_path_for_effect_key("coin").ends_with("coin_resource.png"),
		"coin icon path"
	)
	_check(RewardsScript.effect_value_text(2) == "+2", "value text +2")


func _test_compact_reward_icon_size() -> void:
	var item_h: float = 120.0
	var layout: Dictionary = OverlayScript.tech_reward_box_layout(Vector2(80.0, item_h))
	_check(float(layout["icon_height"]) >= item_h * 0.08, "reward icon height scaled up for readability")
	_check(
		OverlayScript.measured_reward_text_width("Armory", 8)
			< OverlayScript.measured_reward_text_width("Pottery Workshop", 8),
		"measured text width grows with building name length"
	)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
