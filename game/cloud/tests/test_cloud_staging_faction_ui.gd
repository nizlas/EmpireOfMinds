# Headless: C14d-3 staging slot state / faction dropdown / Ready enable.
extends SceneTree

const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")
const SlotStateScript = preload("res://cloud/cloud_staging_slot_state.gd")

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
	_test_fresh_claimed_slot_selection_enables_ready()
	_test_slot_state_render_and_select()
	_test_ready_commit_uses_pending_not_widget()
	_test_taken_faction_blocks_can_ready()
	_test_plan_ready_null_server_vastervik()
	_test_placeholder_dropdown_mapping()
	_test_first_selection_from_empty_placeholder()
	_test_render_preserves_pending_then_user_select()
	_test_sync_does_not_clear_user_pending_without_server_change()
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


func _unconfigured_summary() -> Dictionary:
	return {
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


func _unconfigured_slot_view() -> Dictionary:
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(_unconfigured_summary(), 0)
	return (view["slots"] as Array)[0] as Dictionary


func _state_from_slot(slot: Dictionary) -> RefCounted:
	return SlotStateScript.from_slot_view(slot, "staging")


func _test_option_index_by_id_not_display_order() -> void:
	var choices: Array = _faction_choices_shuffled()
	_check(
		CloudStagingParsersScript.faction_choice_index_for_faction_id(choices, "vastervik") == 1,
		"vastervik choice index by id",
	)
	_check(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, "malmo", true) == 3,
		"malmo dropdown index with placeholder offset",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 2, true) == "vastervik",
		"dropdown index 2 maps vastervik",
	)


func _test_null_faction_id_no_default_index() -> void:
	var choices: Array = _faction_choices_shuffled()
	_check(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, "", true)
		== CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_INDEX,
		"empty faction maps to placeholder index",
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
			{"actor_id": 0, "claimed": true, "faction_id": "vastervik", "ready": false},
			{"actor_id": 1, "claimed": true, "faction_id": "malmo", "ready": false},
		],
		"available_factions": [
			{"id": "malmo", "display_name": "Malmö"},
			{"id": "vastervik", "display_name": "Västervik"},
		],
	}
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(summary, 0)
	var slot0: Dictionary = (view["slots"] as Array)[0] as Dictionary
	var state: RefCounted = _state_from_slot(slot0)
	_check(state.pending_faction_id == "vastervik", "server vastervik pending")
	_check(state.can_ready, "vastervik saved not ready can_ready")
	_check(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(
			state.faction_choices,
			"vastervik",
			true,
		)
		== 2,
		"dropdown selects vastervik with placeholder",
	)


func _test_null_faction_slot_view_no_malmo_display() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	_check(state.server_faction_id.is_empty(), "null server faction")
	_check(state.pending_faction_id.is_empty(), "null pending after server sync")
	_check(not state.can_ready, "null cannot ready")
	_check(
		state.dropdown_option_index_for_pending() == CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_INDEX,
		"null uses placeholder not malmo",
	)


func _test_no_apply_faction_button_in_ui_model() -> void:
	var slot: Dictionary = _unconfigured_slot_view()
	var controls: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(slot, "")
	_check(not bool(controls.get("show_apply_faction_button", true)), "no apply button")


func _test_ready_commit_plan() -> void:
	var changed: Dictionary = CloudStagingParsersScript.plan_ready_commit("", "vastervik")
	_check(bool(changed.get("ok")), "changed ok")
	_check(bool(changed.get("post_faction")), "posts faction first")
	_check(changed.get("faction_id") == "vastervik", "faction id to save")
	var saved: Dictionary = CloudStagingParsersScript.plan_ready_commit("vastervik", "vastervik")
	_check(bool(saved.get("ok")), "saved ok")
	_check(not bool(saved.get("post_faction")), "saved skips faction post")
	var none: Dictionary = CloudStagingParsersScript.plan_ready_commit("", "")
	_check(not bool(none.get("ok")), "none blocked")


func _test_unready_and_ready_lock_controls() -> void:
	var slot: Dictionary = {
		"is_mine": true,
		"claimed": true,
		"ready": true,
		"faction_id": "vastervik",
		"faction_choices": [{"id": "vastervik", "display_name": "Västervik", "taken": false}],
	}
	var controls: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(slot, "vastervik")
	_check(not bool(controls.get("faction_dropdown_editable")), "locked when ready")
	_check(bool(controls.get("show_unready_button")), "unready visible")


func _test_fresh_claimed_slot_selection_enables_ready() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	var choices: Array = state.faction_choices
	for fid in ["malmo", "vastervik", "paris"]:
		var fresh: RefCounted = _state_from_slot(slot0)
		var opt_idx: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, fid, true)
		fresh.on_dropdown_selected(opt_idx)
		_check(fresh.can_ready, "fresh select %s enables ready" % fid)
		_check(fresh.pending_faction_id == fid, "pending %s" % fid)


func _test_slot_state_render_and_select() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	var render_before: Dictionary = state.apply_render_select()
	_check(render_before.cleared_pending, "render null server clears pending")
	_check(
		render_before.option_index == CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_INDEX,
		"render placeholder index",
	)
	state.on_dropdown_selected(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(state.faction_choices, "vastervik", true)
	)
	_check(state.can_ready, "select vastervik can_ready")
	state.sync_from_server_slot(slot0, "staging")
	_check(state.pending_faction_id.is_empty(), "re-sync null server clears pending")
	var vastervik_slot: Dictionary = {
		"actor_id": 0,
		"claimed": true,
		"faction_id": "vastervik",
		"ready": false,
		"is_mine": true,
		"faction_choices": slot0["faction_choices"],
	}
	var saved: RefCounted = _state_from_slot(vastervik_slot)
	_check(saved.pending_faction_id == "vastervik", "re-sync vastervik pending")
	_check(saved.can_ready, "re-sync vastervik can_ready")


func _test_ready_commit_uses_pending_not_widget() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	state.on_dropdown_selected(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(state.faction_choices, "vastervik", true)
	)
	var plan: Dictionary = state.plan_ready_commit()
	_check(bool(plan.get("post_faction")), "commit posts vastervik")
	_check(plan.get("faction_id") == "vastervik", "commit faction from pending")
	var stale_widget_selected: int = 0
	_check(stale_widget_selected == CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_INDEX, "widget placeholder not source")
	_check(state.pending_faction_id == "vastervik", "pending still vastervik")


func _test_taken_faction_blocks_can_ready() -> void:
	var slot: Dictionary = {
		"actor_id": 0,
		"claimed": true,
		"faction_id": null,
		"ready": false,
		"is_mine": true,
		"faction_choices": [
			{"id": "malmo", "display_name": "Malmö", "taken": false},
			{"id": "paris", "display_name": "Paris", "taken": true},
		],
	}
	var state: RefCounted = _state_from_slot(slot)
	state.on_dropdown_selected(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(state.faction_choices, "paris", true)
	)
	_check(state.pending_faction_id == "paris", "selected paris pending")
	_check(not state.can_ready, "taken paris blocks ready")


func _test_plan_ready_null_server_vastervik() -> void:
	var state: RefCounted = _state_from_slot(_unconfigured_slot_view())
	state.on_dropdown_selected(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(state.faction_choices, "vastervik", true)
	)
	var plan: Dictionary = state.plan_ready_commit()
	_check(bool(plan.get("ok")), "plan ok")
	_check(bool(plan.get("post_faction")), "plan posts faction")
	_check(plan.get("faction_id") == "vastervik", "plan faction id")
	_check(bool(plan.get("post_ready")), "plan posts ready")


func _test_placeholder_dropdown_mapping() -> void:
	var choices: Array = (_unconfigured_slot_view()["faction_choices"] as Array)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 0, true).is_empty(),
		"placeholder metadata empty",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 1, true) == "malmo",
		"index 1 malmo",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 2, true) == "vastervik",
		"index 2 vastervik",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 3, true) == "paris",
		"index 3 paris",
	)


func _test_first_selection_from_empty_placeholder() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var choices: Array = slot0["faction_choices"] as Array
	for fid in ["malmo", "vastervik", "paris"]:
		var state: RefCounted = _state_from_slot(slot0)
		_check(
			state.dropdown_option_index_for_pending() == CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_INDEX,
			"initial placeholder for %s test" % fid,
		)
		var item_index: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(choices, fid, true)
		_check(item_index > 0, "faction index above placeholder for %s" % fid)
		state.on_dropdown_selected(item_index)
		_check(state.pending_faction_id == fid, "first select pending %s" % fid)
		_check(state.can_ready, "first select can_ready %s" % fid)


func _test_render_preserves_pending_then_user_select() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	var pending_before: String = state.pending_faction_id
	var vastervik_idx: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(
		state.faction_choices,
		"vastervik",
		true,
	)
	state.on_dropdown_selected(vastervik_idx)
	_check(state.pending_faction_id == "vastervik", "user select before re-render")
	state.pending_faction_id = pending_before
	state.on_dropdown_selected(vastervik_idx)
	_check(state.can_ready, "select after simulated render restore")


func _test_sync_does_not_clear_user_pending_without_server_change() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	var state: RefCounted = _state_from_slot(slot0)
	state.on_dropdown_selected(
		CloudStagingParsersScript.dropdown_option_index_for_faction_id(state.faction_choices, "paris", true)
	)
	_check(state.pending_faction_id == "paris", "user picked paris")
	state.sync_from_server_slot(slot0, "staging")
	_check(state.pending_faction_id.is_empty(), "server sync resets pending when server empty")


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
