# Headless: C14c blocking data-flow — dialog OK vs close, create body, server-scoped resume.
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const TEST_PATH: String = "user://test_eom_front_door_flow.json"
const CUSTOM: String = "Manual Custom Name"
const SERVER: String = "http://127.0.0.1:8000"

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_dialog_ok_not_reverted_by_close()
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


func _test_dialog_ok_not_reverted_by_close() -> void:
	var prefill := "Match 4"
	var edited := CUSTOM
	var ok_result: String = StoreScript.finalize_dialog_text(edited, prefill, true, true)
	_check(ok_result == CUSTOM, "OK keeps custom text not prefill")
	var cancel_result: String = StoreScript.finalize_dialog_text(edited, prefill, false, true)
	_check(cancel_result == prefill, "cancel uses prefill when configured")
	var rename_ok: String = StoreScript.finalize_dialog_text("Manual Renamed Match", "Old", true, false)
	_check(rename_ok == "Manual Renamed Match", "rename OK not cleared")


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
