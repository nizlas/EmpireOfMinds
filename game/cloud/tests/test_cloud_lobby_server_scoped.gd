# Headless: C14c server-target-scoped resume/open lobby lists (no offline resume).
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const TEST_PATH: String = "user://test_eom_lobby_server_scoped.json"
const CLOUD_URL: String = "https://cloud.thewizardsapprentice.org"
const LOCAL_URL: String = "http://127.0.0.1:8000"
const CUSTOM: String = "Manual Custom Name"

var _total = 0
var _any_fail = false


func _init() -> void:
	_remove_test_file()
	_test_resume_from_server_filtered_by_credentials()
	_test_credential_absent_from_server_not_in_resume()
	_test_server_error_yields_empty_resume()
	_test_server_display_name_wins_over_stale_label()
	_test_resume_merges_actor_and_host_from_credential()
	_test_row_text_hides_token()
	_test_server_url_scoping_cloud_vs_local()
	_test_open_staging_excludes_resume_matches()
	_test_open_staging_distinct_from_resume()
	_test_create_credential_label_cache_only()
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


func _lobby_row(match_id: String, display_name: String, status: String = "staging") -> Dictionary:
	return {
		"match_id": match_id,
		"display_name": display_name,
		"status": status,
		"revision": 3,
		"seats": [
			{"actor_id": 0, "claimed": true},
			{"actor_id": 1, "claimed": false},
		],
	}


func _test_resume_from_server_filtered_by_credentials() -> void:
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(CLOUD_URL, "m_on_server", 0, "ht_a", true, -1, StoreScript.STATUS_STAGING, "Local A"),
	)
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(CLOUD_URL, "m_only_local", 1, "ht_b", false, -1, StoreScript.STATUS_STAGING, "Local B"),
	)
	var matches: Array = [
		_lobby_row("m_on_server", "Server Alpha"),
		_lobby_row("m_other", "Other Match"),
	]
	var cred_map: Dictionary = StoreScript.credentials_map_for_server(TEST_PATH, CLOUD_URL)
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby(matches, cred_map, CLOUD_URL)
	_check(rows.size() == 1, "one resume row when one cred on server list")
	var view: Dictionary = rows[0] as Dictionary
	_check(view["match_id"] == "m_on_server", "resume match id")
	_check(view["display_name"] == "Server Alpha", "name from server summary")
	_check(view["seat_token"] == "ht_a", "token from credential")
	_check(view["is_host"] == true, "host from credential")


func _test_credential_absent_from_server_not_in_resume() -> void:
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(CLOUD_URL, "m_gone", 0, "ht_gone", true, -1, StoreScript.STATUS_STAGING, "Gone"),
	)
	var cred_map: Dictionary = StoreScript.credentials_map_for_server(TEST_PATH, CLOUD_URL)
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby([], cred_map, CLOUD_URL)
	_check(rows.is_empty(), "no resume rows when server list empty")


func _test_server_error_yields_empty_resume() -> void:
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response({"_error": "network"})
	_check(parsed.has("_error"), "parse reports error")
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby(
		parsed.get("matches", []) as Array,
		{"m_x": StoreScript.make_entry(CLOUD_URL, "m_x", 0, "ht_x", true)},
		CLOUD_URL,
	)
	_check(rows.is_empty(), "error response matches empty — no playable resume rows")


func _test_server_display_name_wins_over_stale_label() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		CLOUD_URL,
		"m_stale",
		0,
		"ht_s",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Old Local Cache",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		_lobby_row("m_stale", CUSTOM),
		cred,
		CLOUD_URL,
	)
	_check(view["display_name"] == CUSTOM, "server display_name wins")
	_check(str(view["row_text"]).find(CUSTOM) >= 0, "row text uses server name")


func _test_resume_merges_actor_and_host_from_credential() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		CLOUD_URL,
		"m_merge",
		2,
		"seat_tok_2",
		false,
		-1,
		StoreScript.STATUS_STAGING,
		"",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		_lobby_row("m_merge", "Merged"),
		cred,
		CLOUD_URL,
	)
	_check(int(view["actor_id"]) == 2, "actor from credential")
	_check(view["is_host"] == false, "is_host from credential")
	_check(str(view["seat_token"]) == "seat_tok_2", "seat token from credential")


func _test_row_text_hides_token() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		CLOUD_URL,
		"m_tok",
		0,
		"secret_host_token_xyz",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Title",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		_lobby_row("m_tok", "Title"),
		cred,
		CLOUD_URL,
	)
	_check(
		StoreScript.row_text_has_no_token(str(view["row_text"]), cred),
		"resume row text never shows token",
	)


func _test_server_url_scoping_cloud_vs_local() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(CLOUD_URL, "m_cloud", 0, "ht_c", true, -1, StoreScript.STATUS_STAGING, "Cloud"),
	)
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry(LOCAL_URL, "m_local", 0, "ht_l", true, -1, StoreScript.STATUS_STAGING, "Local"),
	)
	var cloud_map: Dictionary = StoreScript.credentials_map_for_server(TEST_PATH, CLOUD_URL)
	var local_map: Dictionary = StoreScript.credentials_map_for_server(TEST_PATH, LOCAL_URL)
	_check(cloud_map.size() == 1 and cloud_map.has("m_cloud"), "cloud map only cloud cred")
	_check(local_map.size() == 1 and local_map.has("m_local"), "local map only local cred")
	var cloud_rows: Array = CloudClientScript.build_resume_rows_from_lobby(
		[_lobby_row("m_cloud", "C"), _lobby_row("m_local", "L")],
		cloud_map,
		CLOUD_URL,
	)
	_check(cloud_rows.size() == 1, "cloud resume excludes local-only cred match")
	_check((cloud_rows[0] as Dictionary)["match_id"] == "m_cloud", "cloud resume is cloud match")


func _test_open_staging_excludes_resume_matches() -> void:
	var matches: Array = [
		_lobby_row("m_resume", "Resume Match"),
		_lobby_row("m_open", "Open Match"),
	]
	var resume_ids: Dictionary = {"m_resume": true}
	var targets: Array = CloudClientScript.build_open_staging_claim_targets(matches, resume_ids)
	var mids: Array = []
	var i: int = 0
	while i < targets.size():
		mids.append(str((targets[i] as Dictionary).get("match_id", "")))
		i += 1
	_check(not mids.has("m_resume"), "open list skips resume match")
	_check(mids.has("m_open"), "open list includes other staging match")


func _test_open_staging_distinct_from_resume() -> void:
	var matches: Array = [_lobby_row("m_both", "Both")]
	var cred: Dictionary = StoreScript.make_entry(
		CLOUD_URL,
		"m_both",
		0,
		"ht_both",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"",
	)
	var resume: Array = CloudClientScript.build_resume_rows_from_lobby(
		matches,
		{"m_both": cred},
		CLOUD_URL,
	)
	var resume_ids: Dictionary = CloudClientScript.resume_match_id_set(resume)
	var open_targets: Array = CloudClientScript.build_open_staging_claim_targets(matches, resume_ids)
	_check(resume.size() == 1, "resume has credentialed match")
	_check(open_targets.is_empty(), "open list empty when match already in resume")


func _test_create_credential_label_cache_only() -> void:
	var resp := {"match_id": "m_new", "host_token": "ht_new", "display_name": CUSTOM}
	var entry: Dictionary = CloudClientScript.credential_from_create_response(
		CLOUD_URL,
		resp,
		CUSTOM,
		TEST_PATH,
	)
	_check(entry["label"] == CUSTOM, "local label cached from create")
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby([], {"m_new": entry}, CLOUD_URL)
	_check(rows.is_empty(), "create cred alone does not populate resume without server row")
	var rows2: Array = CloudClientScript.build_resume_rows_from_lobby(
		[_lobby_row("m_new", "Server Authoritative")],
		{"m_new": entry},
		CLOUD_URL,
	)
	_check((rows2[0] as Dictionary)["display_name"] == "Server Authoritative", "server name after list confirms match")
