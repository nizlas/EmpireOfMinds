# Headless: C14d-3 faction dropdown / ready body regression (Västervik revert bug).
extends SceneTree

const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_option_index_by_id_not_display_order()
	_test_null_faction_id_no_default_index()
	_test_vastervik_mapping_shuffled_order()
	_test_build_faction_and_ready_bodies()
	_test_ready_response_renders_vastervik()
	_test_null_faction_slot_view_no_malmo_display()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _faction_choices_shuffled() -> Array:
	return [
		{"id": "paris", "display_name": "Paris", "taken": false},
		{"id": "vastervik", "display_name": "Västervik", "taken": false},
		{"id": "malmo", "display_name": "Malmö", "taken": false},
	]


func _test_option_index_by_id_not_display_order() -> void:
	var choices: Array = _faction_choices_shuffled()
	_check(
		CloudStagingParsersScript.option_index_for_faction_id(choices, "vastervik") == 1,
		"vastervik index by id",
	)
	_check(
		CloudStagingParsersScript.option_index_for_faction_id(choices, "malmo") == 2,
		"malmo index by id not zero when shuffled",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_choice_index(choices, 1) == "vastervik",
		"index 1 id",
	)


func _test_null_faction_id_no_default_index() -> void:
	var choices: Array = _faction_choices_shuffled()
	_check(
		CloudStagingParsersScript.option_index_for_faction_id(choices, "") == -1,
		"empty faction no selection index",
	)
	_check(
		CloudStagingParsersScript.normalize_seat_faction_id(null).is_empty(),
		"null normalizes empty",
	)


func _test_vastervik_mapping_shuffled_order() -> void:
	var body: Dictionary = CloudStagingParsersScript.build_faction_post_body("vastervik")
	_check(body["faction_id"] == "vastervik", "faction body vastervik")
	_check(not body.has("ready"), "faction body no ready")


func _test_build_faction_and_ready_bodies() -> void:
	var ready_body: Dictionary = CloudStagingParsersScript.build_ready_post_body(true)
	_check(ready_body == {"ready": true}, "ready body only ready")
	_check(not ready_body.has("faction_id"), "ready body no faction_id")


func _test_ready_response_renders_vastervik() -> void:
	var summary := {
		"match_id": "m_r",
		"display_name": "Test",
		"status": "staging",
		"seats": [
			{"actor_id": 0, "claimed": true, "faction_id": "vastervik", "ready": true},
			{"actor_id": 1, "claimed": true, "faction_id": "malmo", "ready": false},
		],
		"available_factions": [
			{"id": "malmo", "display_name": "Malmö"},
			{"id": "vastervik", "display_name": "Västervik"},
		],
	}
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(summary, 0)
	var slot0: Dictionary = (view["slots"] as Array)[0] as Dictionary
	_check(slot0["faction_id"] == "vastervik", "view faction_id")
	_check(slot0["faction_display"] == "Västervik", "view display")
	_check(
		CloudStagingParsersScript.option_index_for_faction_id(
			slot0["faction_choices"] as Array,
			"vastervik",
		)
		== 1,
		"dropdown index for vastervik",
	)
	_check(
		CloudStagingParsersScript.seat_faction_id_from_summary(summary, 0) == "vastervik",
		"summary parse actor0",
	)


func _test_null_faction_slot_view_no_malmo_display() -> void:
	var summary := {
		"match_id": "m_null",
		"display_name": "Test",
		"status": "staging",
		"seats": [{"actor_id": 0, "claimed": true, "faction_id": null, "ready": false}],
		"available_factions": [
			{"id": "malmo", "display_name": "Malmö"},
			{"id": "vastervik", "display_name": "Västervik"},
		],
	}
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(summary, 0)
	var slot0: Dictionary = (view["slots"] as Array)[0] as Dictionary
	_check(slot0["faction_id"].is_empty(), "null stored as empty id")
	_check(slot0["faction_display"].is_empty(), "null no display default")
	_check(
		CloudStagingParsersScript.option_index_for_faction_id(
			slot0["faction_choices"] as Array,
			"",
		)
		== -1,
		"null no default malmo index",
	)
