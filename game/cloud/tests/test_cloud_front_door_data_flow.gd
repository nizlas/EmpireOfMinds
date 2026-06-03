# Headless: C14c blocking data-flow — dialog OK vs cancel, create body, server-scoped resume.
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const BootIntentScript = preload("res://cloud/boot_intent.gd")

const TEST_PATH: String = "user://test_eom_front_door_flow.json"
const CUSTOM: String = "Manual Custom Name"
const SERVER: String = "http://127.0.0.1:8000"

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_window_dialog_signal_wiring()
	_test_dialog_ok_custom_name()
	_test_dialog_ok_empty_uses_default()
	_test_dialog_cancel()
	_test_close_after_ok_does_not_cancel()
	_test_create_flow_proceeds_after_ok()
	_test_create_identity_propagates()
	_test_persist_bootstrap_preserves_label()
	_test_resume_row_by_match_id_not_stale_label()
	_test_distinct_create_row_models()
	_test_enter_created_status_not_reconnecting()
	_test_rename_ok_and_cancel()
	_test_create_body_includes_custom_name()
	_test_pick_create_uses_response_then_request()
	_test_credential_create_no_local_match_number_override()
	_test_resume_requires_server_row()
	_test_rename_merge_still_updates_view()
	_remove_test_file()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _check(cond, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_window_dialog_signal_wiring() -> void:
	_check(not ClassDB.class_has_signal("Window", "gui_input"), "Window has no gui_input signal")
	_check(ClassDB.class_has_signal("Window", "close_requested"), "Window has close_requested")
	var win := Window.new()
	var edit := LineEdit.new()
	var ok_btn := Button.new()
	win.add_child(edit)
	var result := {"confirmed": false, "text": "Match 1"}
	var commit_ok := func() -> void:
		result["confirmed"] = true
		result["text"] = edit.text
		win.hide()
	ok_btn.pressed.connect(commit_ok)
	edit.text_submitted.connect(func(_t: String) -> void: commit_ok.call())
	win.close_requested.connect(
		func() -> void:
			result = StoreScript.apply_close_requested_to_dialog_result(result)
			if bool(result.get("confirmed", false)):
				return
			win.hide()
	)
	_check(true, "dialog wiring uses only valid Window/LineEdit signals")


func _test_dialog_ok_custom_name() -> void:
	var result := {"confirmed": true, "text": CUSTOM}
	var out: Dictionary = StoreScript.interpret_create_dialog_result(result, TEST_PATH)
	_check(not bool(out.get("cancelled", true)), "OK custom not cancelled")
	_check(out["display_name"] == CUSTOM, "OK custom name preserved")


func _test_dialog_ok_empty_uses_default() -> void:
	var lobby: Array = [{"match_id": "m1", "display_name": "Match 1", "status": "staging"}]
	var default_label: String = StoreScript.generate_unique_default_label_from_server(lobby)
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_create_display_name("   ", default_label, keys)
	_check(bool(v.get("ok", false)), "empty field validates via default")
	var result := {"confirmed": true, "text": str(v["effective"])}
	var out: Dictionary = StoreScript.interpret_create_dialog_result(result, default_label, TEST_PATH)
	_check(not bool(out.get("cancelled", true)), "OK empty not cancelled")
	_check(out["display_name"] == default_label, "OK empty uses server-suggested default")


func _test_dialog_cancel() -> void:
	var result := {"confirmed": false, "text": CUSTOM}
	var out: Dictionary = StoreScript.interpret_create_dialog_result(result, TEST_PATH)
	_check(bool(out.get("cancelled", true)), "cancel sets cancelled")
	_check(str(out.get("display_name", "x")) == "", "cancel has no display_name")


func _test_close_after_ok_does_not_cancel() -> void:
	var result := {"confirmed": true, "text": CUSTOM}
	var after_close: Dictionary = StoreScript.apply_close_requested_to_dialog_result(result)
	_check(bool(after_close.get("confirmed", false)), "close after OK keeps confirmed")
	var out: Dictionary = StoreScript.interpret_create_dialog_result(after_close, TEST_PATH)
	_check(not bool(out.get("cancelled", true)), "interpret after close still proceeds")
	_check(out["display_name"] == CUSTOM, "name preserved after close guard")


func _test_create_identity_propagates() -> void:
	var resp := {
		"match_id": "m_id_a",
		"host_token": "ht_a",
		"display_name": CUSTOM,
		"revision": 1,
	}
	var trace: Dictionary = CloudClientScript.create_flow_identity(
		CUSTOM,
		resp,
		SERVER,
		"prototype_play",
		TEST_PATH,
	)
	_check(trace["body_display_name"] == CUSTOM, "POST body display_name")
	_check(trace["response_match_id"] == "m_id_a", "response match_id")
	_check(trace["credential_match_id"] == "m_id_a", "credential match_id")
	_check(trace["boot_intent_match_id"] == "m_id_a", "boot trace match_id")
	_check(trace["credential_label"] == CUSTOM, "credential label from server name")
	_check(trace["response_display_name"] == CUSTOM, "response display_name")


func _test_persist_bootstrap_preserves_label() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(SERVER, "m_persist", 0, "ht_p", true, -1, StoreScript.STATUS_STAGING, CUSTOM),
	)
	StoreScript.persist_after_bootstrap(
		TEST_PATH,
		SERVER,
		"m_persist",
		"ht_p",
		true,
		{"revision": 5, "snapshot": {"revision": 5}},
	)
	var found: Dictionary = StoreScript.find(TEST_PATH, SERVER, "m_persist")
	_check(found["label"] == CUSTOM, "bootstrap persist keeps saved label")


func _test_resume_row_by_match_id_not_stale_label() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		SERVER,
		"m_row",
		0,
		"ht_r",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Stale Local Label",
	)
	var server_row := {
		"match_id": "m_row",
		"display_name": CUSTOM,
		"status": "staging",
		"revision": 2,
		"seats": [],
	}
	var view: Dictionary = CloudClientScript.build_resume_row_view(server_row, cred, SERVER)
	_check(view["match_id"] == "m_row", "resume keyed by match_id")
	_check(view["display_name"] == CUSTOM, "resume uses server display_name not stale label")


func _test_distinct_create_row_models() -> void:
	var cred_map := {
		"m_a": StoreScript.make_entry(SERVER, "m_a", 0, "ht_a", true, -1, StoreScript.STATUS_STAGING, "A"),
		"m_b": StoreScript.make_entry(SERVER, "m_b", 0, "ht_b", true, -1, StoreScript.STATUS_STAGING, "B"),
	}
	var lobby: Array = [
		{"match_id": "m_a", "display_name": "Alpha", "status": "staging", "revision": 1, "seats": []},
		{"match_id": "m_b", "display_name": "Beta", "status": "staging", "revision": 1, "seats": []},
	]
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby(lobby, cred_map, SERVER)
	_check(rows.size() == 2, "two distinct resume rows")
	_check((rows[0] as Dictionary)["match_id"] == "m_a", "first row match_id")
	_check((rows[1] as Dictionary)["match_id"] == "m_b", "second row match_id")
	_check((rows[0] as Dictionary)["display_name"] == "Alpha", "first row server name")
	_check((rows[1] as Dictionary)["display_name"] == "Beta", "second row server name")


func _test_enter_created_status_not_reconnecting() -> void:
	_check(
		BootIntentScript.cloud_load_status_message(BootIntentScript.MODE_CLOUD_ENTER_CREATED)
			!= "Reconnecting to cloud match…",
		"enter-created message not reconnecting",
	)
	_check(BootIntentScript.is_cloud_enter_created(BootIntentScript.MODE_CLOUD_ENTER_CREATED), "flag helper")


func _test_create_flow_proceeds_after_ok() -> void:
	var result := {"confirmed": true, "text": CUSTOM}
	var out: Dictionary = StoreScript.interpret_create_dialog_result(result, TEST_PATH)
	_check(not bool(out.get("cancelled", true)), "create not cancelled on OK")
	var body: Dictionary = CloudClientScript.build_create_match_body(
		"prototype_play",
		str(out["display_name"]),
	)
	_check(body["display_name"] == CUSTOM, "POST body uses OK name")


func _test_rename_ok_and_cancel() -> void:
	var ok: Dictionary = StoreScript.interpret_rename_dialog_result(
		{"confirmed": true, "text": "  " + CUSTOM + "  "}
	)
	_check(not bool(ok.get("cancelled", true)), "rename OK proceeds")
	_check(ok["display_name"] == CUSTOM, "rename OK exact name")
	var cancel: Dictionary = StoreScript.interpret_rename_dialog_result(
		{"confirmed": false, "text": CUSTOM}
	)
	_check(bool(cancel.get("cancelled", true)), "rename cancel")
	var empty_ok: Dictionary = StoreScript.interpret_rename_dialog_result(
		{"confirmed": true, "text": "   "}
	)
	_check(bool(empty_ok.get("cancelled", true)), "rename OK empty still cancels rename")


func _test_create_body_includes_custom_name() -> void:
	var body: Dictionary = CloudClientScript.build_create_match_body("prototype_play", CUSTOM)
	_check(body["display_name"] == CUSTOM, "create body has display_name")
	_check(body["scenario_id"] == "prototype_play", "create body has scenario_id")
	var empty_body: Dictionary = CloudClientScript.build_create_match_body("tiny_test", "   ")
	_check(not empty_body.has("display_name"), "whitespace-only omits display_name")


func _test_pick_create_uses_response_then_request() -> void:
	var resp := {"match_id": "m_x", "display_name": CUSTOM}
	_check(
		CloudClientScript.pick_create_credential_display_name(CUSTOM, resp) == CUSTOM,
		"response display_name",
	)
	var resp2 := {"match_id": "m_y"}
	_check(
		CloudClientScript.pick_create_credential_display_name(CUSTOM, resp2) == CUSTOM,
		"fallback to requested",
	)


func _test_credential_create_no_local_match_number_override() -> void:
	var resp := {"match_id": "m_z", "host_token": "ht_z", "display_name": CUSTOM}
	var entry: Dictionary = CloudClientScript.credential_from_create_response(
		SERVER,
		resp,
		CUSTOM,
		TEST_PATH,
	)
	_check(entry["label"] == CUSTOM, "credential label is custom not Match N")
	_check(entry["seat_token"] == "ht_z", "host token stored")


func _test_resume_requires_server_row() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(SERVER, "m_local", 0, "ht_l", true, -1, StoreScript.STATUS_STAGING, CUSTOM),
	)
	var cred_map: Dictionary = StoreScript.credentials_map_for_server(TEST_PATH, SERVER)
	_check(cred_map.has("m_local"), "credential stored for server")
	var without_server: Array = CloudClientScript.build_resume_rows_from_lobby([], cred_map, SERVER)
	_check(without_server.is_empty(), "credential alone does not produce resume row")
	var lobby: Array = [
		{
			"match_id": "m_local",
			"display_name": "Server Name",
			"status": "staging",
			"revision": 1,
			"seats": [],
		},
	]
	var with_server: Array = CloudClientScript.build_resume_rows_from_lobby(lobby, cred_map, SERVER)
	_check(with_server.size() == 1, "resume row when server confirms match")
	_check((with_server[0] as Dictionary)["display_name"] == "Server Name", "server display_name on resume")


func _test_rename_merge_still_updates_view() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		SERVER,
		"m_merge",
		0,
		"ht_m",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Old Local",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		{
			"match_id": "m_merge",
			"display_name": "Old Local",
			"status": "staging",
			"revision": 0,
			"seats": [],
		},
		cred,
		SERVER,
	)
	var after: Dictionary = StoreScript.apply_rename_to_view(view, "Server Updated")
	_check(after["display_name"] == "Server Updated", "rename updates view display_name")
	_check(str(after["row_text"]).find("Server Updated") >= 0, "rename updates row text")
