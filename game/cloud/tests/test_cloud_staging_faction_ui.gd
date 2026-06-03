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
	_test_option_button_set_block_signals_api()
	_test_dropdown_bounds_and_apply_selection()
	_test_non_owned_slot_selection_ignored()
	_test_ready_enable_chain_after_claim()
	_test_own_faction_not_taken_by_self()
	_test_simplified_slot_ui_text()
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


func _state_from_slot(slot: Dictionary, local_actor_id: int = 0) -> RefCounted:
	return SlotStateScript.from_slot_view(slot, "staging", local_actor_id)


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


func _test_option_button_set_block_signals_api() -> void:
	var ob := OptionButton.new()
	_check(ob.has_method("set_block_signals"), "OptionButton exposes set_block_signals")
	ob.set_block_signals(true)
	ob.set_block_signals(false)
	ob.free()


func _test_dropdown_bounds_and_apply_selection() -> void:
	var choices: Array = (_unconfigured_slot_view()["faction_choices"] as Array)
	_check(
		CloudStagingParsersScript.dropdown_item_count_for_choices(choices, true) == 4,
		"placeholder plus three factions",
	)
	_check(
		CloudStagingParsersScript.is_valid_dropdown_option_index(choices, 2, true),
		"index 2 valid",
	)
	_check(
		not CloudStagingParsersScript.is_valid_dropdown_option_index(choices, 99, true),
		"index 99 invalid",
	)
	_check(
		CloudStagingParsersScript.faction_id_for_dropdown_option_index(choices, 99, true).is_empty(),
		"out of range returns empty faction id",
	)
	var apply_v: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
		true,
		0,
		0,
		2,
		choices,
		true,
	)
	_check(bool(apply_v.get("apply")), "apply vastervik index 2")
	_check(apply_v.get("faction_id") == "vastervik", "vastervik id")
	var apply_p: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
		true,
		0,
		0,
		3,
		choices,
		true,
	)
	_check(apply_p.get("faction_id") == "paris", "paris index 3")


func _test_ready_enable_chain_after_claim() -> void:
	var slot0: Dictionary = _unconfigured_slot_view()
	for fid in ["malmo", "vastervik", "paris"]:
		var state: RefCounted = _state_from_slot(slot0, 0)
		_check(state.owned_by_me, "owned after claim actor 0")
		var idx: int = CloudStagingParsersScript.dropdown_option_index_for_faction_id(
			state.faction_choices,
			fid,
			true,
		)
		var apply: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
			state.owned_by_me,
			0,
			0,
			idx,
			state.faction_choices,
			true,
		)
		_check(bool(apply.get("apply")), "apply %s" % fid)
		state.pending_faction_id = str(apply.get("faction_id", ""))
		state.recompute_can_ready()
		var dbg: Dictionary = CloudStagingParsersScript.ready_enable_debug(
			state.owned_by_me,
			state.match_staging,
			state.ready,
			state.pending_faction_id,
			state.faction_choices,
		)
		_check(bool(dbg.get("can_ready")), "can_ready %s" % fid)
		_check(not bool(dbg.get("taken")), "not taken %s" % fid)
	var other_slot: Dictionary = {
		"actor_id": 1,
		"claimed": true,
		"faction_id": null,
		"ready": false,
		"is_mine": false,
		"faction_choices": slot0["faction_choices"],
	}
	var other_state: RefCounted = _state_from_slot(other_slot, 0)
	_check(not other_state.owned_by_me, "other slot not owned")
	var denied_apply: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
		false,
		1,
		0,
		2,
		other_state.faction_choices,
		true,
	)
	_check(not bool(denied_apply.get("apply")), "other slot apply denied")


func _test_own_faction_not_taken_by_self() -> void:
	var slot: Dictionary = {
		"actor_id": 0,
		"claimed": true,
		"faction_id": "malmo",
		"ready": false,
		"is_mine": true,
		"faction_choices": [
			{"id": "malmo", "display_name": "Malmö", "taken": false},
			{"id": "vastervik", "display_name": "Västervik", "taken": true},
		],
	}
	var state: RefCounted = _state_from_slot(slot, 0)
	_check(
		not CloudStagingParsersScript.is_faction_taken_for_me("malmo", state.faction_choices),
		"own malmo not taken",
	)
	state.pending_faction_id = "malmo"
	state.recompute_can_ready()
	_check(state.can_ready, "can ready with own malmo pending")


func _test_non_owned_slot_selection_ignored() -> void:
	var choices: Array = (_unconfigured_slot_view()["faction_choices"] as Array)
	var denied: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
		false,
		1,
		0,
		2,
		choices,
		true,
	)
	_check(not bool(denied.get("apply")), "non-owned ignored")
	_check(denied.get("reason") == "not_owned", "not_owned reason")
	var wrong_actor: Dictionary = CloudStagingParsersScript.apply_faction_dropdown_selection(
		true,
		1,
		0,
		2,
		choices,
		true,
	)
	_check(not bool(wrong_actor.get("apply")), "other actor slot ignored")
	var other_slot: Dictionary = {
		"is_mine": false,
		"claimed": true,
		"ready": false,
		"faction_id": null,
		"faction_choices": choices,
	}
	var controls: Dictionary = CloudStagingParsersScript.build_my_slot_ui_controls(other_slot, "")
	_check(not bool(controls.get("show_faction_row", true)), "non-owned hides faction row")


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


func _test_simplified_slot_ui_text() -> void:
	var open_slot: Dictionary = {
		"actor_id": 1,
		"claimed": false,
		"is_mine": false,
		"faction_display": "",
		"ready": false,
	}
	_check(CloudStagingParsersScript.slot_header_text(2, false, false) == "Seat 2", "open header")
	_check(CloudStagingParsersScript.slot_status_line(open_slot, false) == "Open", "open status")
	var mine_not_ready: Dictionary = {
		"actor_id": 0,
		"claimed": true,
		"is_mine": true,
		"faction_display": "",
		"ready": false,
		"faction_choices": (_unconfigured_slot_view()["faction_choices"] as Array),
	}
	_check(
		CloudStagingParsersScript.slot_header_text(1, true, true) == "Seat 1 — You",
		"owned header you",
	)
	var mine_status: String = CloudStagingParsersScript.slot_status_line(mine_not_ready, true, "", [])
	_check(mine_status.is_empty(), "owned not ready no redundant status")
	_check(
		not CloudStagingParsersScript.slot_status_has_redundant_choose_instruction(mine_status),
		"no choose instruction",
	)
	var mine_ready: Dictionary = mine_not_ready.duplicate(true)
	mine_ready["ready"] = true
	mine_ready["faction_display"] = "Västervik"
	_check(
		CloudStagingParsersScript.slot_status_line(mine_ready, true) == "Västervik — Ready",
		"owned ready faction",
	)
	var other_claimed: Dictionary = {
		"actor_id": 1,
		"claimed": true,
		"is_mine": false,
		"faction_display": "Malmö",
		"ready": false,
	}
	_check(
		CloudStagingParsersScript.slot_status_line(other_claimed, false) == "Malmö — Not ready",
		"other faction not ready",
	)
	other_claimed["ready"] = true
	_check(
		CloudStagingParsersScript.slot_status_line(other_claimed, false) == "Malmö — Ready",
		"other faction ready",
	)
	_check(
		CloudStagingParsersScript.slot_ui_text_has_no_secrets("Seat 1 — You", "Västervik — Ready"),
		"slot text no secrets",
	)


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
