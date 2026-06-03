# Headless: C14d-4a front door / staging auto-poll policy and lobby list refresh semantics.
extends SceneTree

const PollScript = preload("res://cloud/cloud_lobby_poll.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")
const SlotStateScript = preload("res://cloud/cloud_staging_slot_state.gd")

const FRONT_DOOR_POLL_INTERVAL_SEC: float = 2.0
const STAGING_POLL_INTERVAL_SEC: float = 1.0

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_poll_interval_constants()
	_test_front_door_poll_policy()
	_test_staging_poll_policy()
	_test_open_staging_list_updates_without_manual_refresh()
	_test_resume_list_server_filtered_by_credentials()
	_test_staging_poll_updates_other_player_slot()
	_test_pending_faction_preserved_on_poll()
	_test_ongoing_poll_stops_and_enters_gameplay()
	_test_manual_refresh_not_blocked_by_poll_in_flight_only()
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


func _test_poll_interval_constants() -> void:
	var fd := load("res://cloud/cloud_front_door.gd") as GDScript
	var st := load("res://cloud/cloud_staging.gd") as GDScript
	_check(fd.get_script_constant_map().get("FRONT_DOOR_POLL_INTERVAL_SEC") == 2.0, "front door interval")
	_check(st.get_script_constant_map().get("STAGING_POLL_INTERVAL_SEC") == 1.0, "staging interval")


func _test_front_door_poll_policy() -> void:
	_check(
		PollScript.front_door_should_run_poll(false, false, false),
		"front door poll runs when active",
	)
	_check(
		not PollScript.front_door_should_run_poll(true, false, false),
		"front door poll stopped",
	)
	_check(
		not PollScript.front_door_should_run_poll(false, true, false),
		"front door skip when fetch in flight",
	)
	_check(
		not PollScript.front_door_should_run_poll(false, false, true),
		"front door skip when ui busy",
	)
	_check(PollScript.front_door_should_begin_fetch(false), "front door fetch can start")
	_check(not PollScript.front_door_should_begin_fetch(true), "front door fetch no overlap")


func _test_staging_poll_policy() -> void:
	_check(
		PollScript.staging_should_run_poll(false, false, false, "staging"),
		"staging poll while staging",
	)
	_check(
		not PollScript.staging_should_run_poll(false, false, false, "ongoing"),
		"staging poll stops on ongoing",
	)
	_check(
		not PollScript.staging_should_run_poll(false, true, false, "staging"),
		"staging skip when refresh in flight",
	)
	_check(
		not PollScript.staging_should_run_poll(false, false, true, "staging"),
		"staging skip when ui busy",
	)
	_check(PollScript.staging_stop_poll_on_status("ongoing"), "staging stop flag ongoing")
	_check(not PollScript.staging_stop_poll_on_status("staging"), "staging stop flag not staging")


func _staging_lobby_row(match_id: String, display_name: String, open_seats: int = 2) -> Dictionary:
	var seats: Array = []
	var si: int = 0
	while si < 2:
		seats.append({"actor_id": si, "claimed": si >= open_seats})
		si += 1
	return {
		"match_id": match_id,
		"display_name": display_name,
		"status": "staging",
		"seats": seats,
	}


func _test_open_staging_list_updates_without_manual_refresh() -> void:
	var matches_before: Array = [_staging_lobby_row("m_old", "Old")]
	var resume_ids: Dictionary = {}
	var before: Array = CloudClientScript.build_open_staging_join_targets(matches_before, resume_ids)
	_check(before.size() == 1, "one open match before")
	var matches_after: Array = matches_before.duplicate(true)
	matches_after.append(_staging_lobby_row("m_new", "New From A"))
	var after: Array = CloudClientScript.build_open_staging_join_targets(matches_after, resume_ids)
	_check(after.size() == 2, "new open staging match appears after server poll data")
	var found_new: bool = false
	var ai: int = 0
	while ai < after.size():
		if str((after[ai] as Dictionary).get("match_id", "")) == "m_new":
			found_new = true
			break
		ai += 1
	_check(found_new, "new match id in join targets")


func _test_resume_list_server_filtered_by_credentials() -> void:
	var matches: Array = [
		{"match_id": "m1", "display_name": "One", "status": "staging"},
		{"match_id": "m2", "display_name": "Two", "status": "ongoing"},
		{"match_id": "m3", "display_name": "Three", "status": "staging"},
	]
	var cred_map: Dictionary = {
		"m1": CloudCredentialStoreScript.make_entry("http://127.0.0.1:8000", "m1", 0, "ht_a", true),
		"m3": CloudCredentialStoreScript.make_entry("http://127.0.0.1:8000", "m3", 1, "st_c", false),
	}
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby(matches, cred_map, "http://127.0.0.1:8000")
	_check(rows.size() == 2, "resume only credentialed server rows")
	var ids: Array = []
	var i: int = 0
	while i < rows.size():
		ids.append(str((rows[i] as Dictionary).get("match_id", "")))
		i += 1
	_check(ids.has("m1") and ids.has("m3"), "resume ids from cred map")
	_check(not ids.has("m2"), "no resume without credential")


func _test_staging_poll_updates_other_player_slot() -> void:
	var row_before: Dictionary = {
		"match_id": "m_stg",
		"status": "staging",
		"available_factions": [{"id": "malmo"}, {"id": "vastervik"}],
		"seats": [
			{"actor_id": 0, "claimed": true, "faction_id": "malmo", "ready": true},
			{"actor_id": 1, "claimed": false, "faction_id": null, "ready": false},
		],
	}
	var view_before: Dictionary = CloudStagingParsersScript.build_staging_view(row_before, 0)
	var slot1_before: Dictionary = (view_before.get("slots", []) as Array)[1] as Dictionary
	_check(not bool(slot1_before.get("claimed", false)), "seat1 unclaimed before")
	var row_after: Dictionary = row_before.duplicate(true)
	var seats: Array = (row_after["seats"] as Array).duplicate(true)
	var seat1: Dictionary = (seats[1] as Dictionary).duplicate(true)
	seat1["claimed"] = true
	seat1["faction_id"] = "vastervik"
	seat1["ready"] = true
	seats[1] = seat1
	row_after["seats"] = seats
	var view_after: Dictionary = CloudStagingParsersScript.build_staging_view(row_after, 0)
	var slot1_after: Dictionary = (view_after.get("slots", []) as Array)[1] as Dictionary
	_check(bool(slot1_after.get("claimed", false)), "seat1 claimed after poll data")
	_check(
		CloudStagingParsersScript.normalize_seat_faction_id(slot1_after.get("faction_id")) == "vastervik",
		"seat1 faction after poll data",
	)
	_check(bool(slot1_after.get("ready", false)), "seat1 ready after poll data")


func _test_pending_faction_preserved_on_poll() -> void:
	var state: RefCounted = SlotStateScript.from_slot_view(
		{
			"actor_id": 0,
			"is_mine": true,
			"claimed": true,
			"faction_id": null,
			"ready": false,
			"faction_choices": [
				{"id": "malmo", "display_name": "Malmöfubikkarna", "taken": false},
				{"id": "vastervik", "display_name": "Västerviksjävlarna", "taken": false},
			],
		},
		"staging",
		0,
	)
	state.on_dropdown_selected(2)
	_check(state.pending_faction_id == "vastervik", "local pending set")
	state.sync_from_server_slot_preserving_local_pending(
		{
			"actor_id": 0,
			"is_mine": true,
			"claimed": true,
			"faction_id": null,
			"ready": false,
			"faction_choices": [
				{"id": "malmo", "display_name": "Malmöfubikkarna", "taken": false},
				{"id": "vastervik", "display_name": "Västerviksjävlarna", "taken": false},
			],
		},
		"staging",
		0,
	)
	_check(state.pending_faction_id == "vastervik", "pending preserved on poll")
	state.sync_from_server_slot_preserving_local_pending(
		{
			"actor_id": 0,
			"is_mine": true,
			"claimed": true,
			"faction_id": "vastervik",
			"ready": false,
			"faction_choices": [
				{"id": "malmo", "display_name": "Malmöfubikkarna", "taken": true},
				{"id": "vastervik", "display_name": "Västerviksjävlarna", "taken": false},
			],
		},
		"staging",
		0,
	)
	_check(state.server_faction_id == "vastervik", "server confirmed faction wins")


func _test_ongoing_poll_stops_and_enters_gameplay() -> void:
	_check(
		CloudStagingParsersScript.can_enter_gameplay_from_staging(true, "ongoing"),
		"seat token enters on ongoing",
	)
	_check(
		not CloudStagingParsersScript.can_enter_gameplay_from_staging(false, "ongoing"),
		"no seat token blocks gameplay",
	)
	_check(
		CloudStagingParsersScript.host_only_needs_claim(true, false, "ongoing"),
		"host-only ongoing message",
	)
	_check(PollScript.staging_stop_poll_on_status("ongoing"), "poll stops before gameplay transition")


func _test_manual_refresh_not_blocked_by_poll_in_flight_only() -> void:
	_check(
		PollScript.staging_should_begin_refresh(false),
		"manual refresh allowed when not in flight",
	)
	_check(
		not PollScript.staging_should_begin_refresh(true),
		"manual refresh blocked while in flight",
	)
	_check(
		PollScript.front_door_should_begin_fetch(false),
		"manual lobby refresh allowed when not in flight",
	)
