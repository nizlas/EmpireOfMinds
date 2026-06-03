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
	_test_no_apply_faction_button_in_ui_model()
	_test_ready_commit_plan()
	_test_unready_and_ready_lock_controls()
	_test_staging_messages_no_secrets()
	_test_can_press_ready_with_null_server_faction()
	_test_unconfigured_slot_selection_enables_ready()
	_test_item_selected_ready_state_update()
	_test_plan_ready_null_server_vastervik()
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


func _mine_slot(ready: bool, faction_id) -> Dictionary:
	return {
		"is_mine": true,
		"claimed": true,
		"ready": ready,
		"faction_id": faction_id,
	}


func _test_no_apply_faction_button_in_ui_model() -> void:
	var slot: Dictionary = _mine_slot(false, "")
	var controls: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(slot, "")
	_check(not bool(controls.get("show_apply_faction_button", true)), "no apply button")
	_check(bool(controls.get("show_faction_row", false)), "faction row when mine")
	_check(bool(controls.get("show_ready_row", false)), "ready row when mine")


func _test_ready_commit_plan() -> void:
	var changed: Dictionary = CloudStagingParsersScript.plan_ready_commit("", "vastervik")
	_check(bool(changed.get("ok")), "changed ok")
	_check(bool(changed.get("post_faction")), "posts faction first")
	_check(changed.get("faction_id") == "vastervik", "faction id to save")
	_check(bool(changed.get("post_ready")), "then ready")
	var saved: Dictionary = CloudStagingParsersScript.plan_ready_commit("vastervik", "vastervik")
	_check(bool(saved.get("ok")), "saved ok")
	_check(not bool(saved.get("post_faction")), "saved skips faction post")
	_check(bool(saved.get("post_ready")), "saved posts ready only")
	var server_only: Dictionary = CloudStagingParsersScript.plan_ready_commit("malmo", "")
	_check(bool(server_only.get("ok")), "server faction ok")
	_check(not bool(server_only.get("post_faction")), "server only no faction post")
	var none: Dictionary = CloudStagingParsersScript.plan_ready_commit("", "")
	_check(not bool(none.get("ok")), "none blocked")
	_check(not bool(none.get("post_ready")), "none no ready post")


func _test_unready_and_ready_lock_controls() -> void:
	var not_ready: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(
		_mine_slot(false, "malmo"),
		"paris",
	)
	_check(bool(not_ready.get("faction_dropdown_editable")), "editable before ready")
	_check(bool(not_ready.get("show_ready_button")), "ready visible")
	_check(not bool(not_ready.get("show_unready_button")), "unready hidden")
	var ready_slot: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(
		_mine_slot(true, "vastervik"),
		"",
	)
	_check(not bool(ready_slot.get("faction_dropdown_editable")), "locked when ready")
	_check(bool(ready_slot.get("show_unready_button")), "unready visible")
	_check(not bool(ready_slot.get("show_ready_button")), "ready hidden when ready")
	var unready_plan: Dictionary = CloudStagingParsersScript.plan_unready_commit()
	_check(bool(unready_plan.get("post_ready")), "unready posts ready")
	_check(unready_plan.get("ready") == false, "unready false")


func _unconfigured_claimed_slot_view() -> Dictionary:
	var summary := {
		"match_id": "m_unconfigured",
		"display_name": "Test",
		"status": "staging",
		"seats": [{"actor_id": 0, "claimed": true, "faction_id": null, "ready": false}],
		"available_factions": [
			{"id": "malmo", "display_name": "Malmö"},
			{"id": "vastervik", "display_name": "Västervik"},
			{"id": "paris", "display_name": "Paris"},
		],
	}
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(summary, 0)
	return (view["slots"] as Array)[0] as Dictionary


func _test_can_press_ready_with_null_server_faction() -> void:
	for fid in ["malmo", "vastervik", "paris"]:
		_check(CloudStagingParsersScript.can_press_ready("", fid), "can_press_ready null server %s" % fid)
		_check(
			CloudStagingParsersScript.can_press_ready(null, fid),
			"can_press_ready null variant server %s" % fid,
		)


func _test_unconfigured_slot_selection_enables_ready() -> void:
	var slot0: Dictionary = _unconfigured_claimed_slot_view()
	var choices: Array = slot0["faction_choices"] as Array
	for fid in ["malmo", "vastervik", "paris"]:
		var controls: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(slot0, fid)
		_check(
			bool(controls.get("ready_button_enabled", false)),
			"unconfigured ready enabled for %s" % fid,
		)
		var opt_idx: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, fid)
		_check(opt_idx >= 0, "dropdown index for %s" % fid)
		_check(
			CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, opt_idx) == fid,
			"dropdown index maps id %s" % fid,
		)


func _test_item_selected_ready_state_update() -> void:
	var slot0: Dictionary = _unconfigured_claimed_slot_view()
	var choices: Array = slot0["faction_choices"] as Array
	var vastervik_idx: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(
		choices,
		"vastervik",
	)
	_check(
		CloudStagingParsersScript.ready_enabled_after_dropdown_select("", choices, vastervik_idx),
		"item_selected vastervik enables ready",
	)
	_check(
		CloudStagingParsersScript.ready_enabled_after_dropdown_select(
			"",
			choices,
			CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, "paris"),
		),
		"item_selected paris enables ready",
	)
	_check(
		not CloudStagingParsersScript.ready_enabled_after_dropdown_select("", choices, -1),
		"no selection does not enable ready",
	)


func _test_plan_ready_null_server_vastervik() -> void:
	var plan: Dictionary = CloudStagingParsersScript.plan_ready_commit(null, "vastervik")
	_check(bool(plan.get("ok")), "plan ok")
	_check(bool(plan.get("post_faction")), "plan posts faction")
	_check(plan.get("faction_id") == "vastervik", "plan faction id")
	_check(bool(plan.get("post_ready")), "plan posts ready")


func _test_staging_messages_no_secrets() -> void:
	var msgs: Array = CloudStagingParsersScript.staging_user_visible_messages()
	var i: int = 0
	while i < msgs.size():
		var m: String = str(msgs[i])
		i += 1
		_check(
			CloudStagingParsersScript.player_visible_text_has_no_secrets(m),
			"staging message safe: %s" % m,
		)
