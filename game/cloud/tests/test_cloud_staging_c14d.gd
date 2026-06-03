# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_staging_c14d.gd
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")

const TEST_PATH: String = "user://test_eom_cloud_staging_c14d.json"

var _total = 0
var _any_fail = false


func _init() -> void:
	_remove_test_file()
	_test_dual_token_create_then_claim()
	_test_legacy_host_in_seat_token_field()
	_test_gameplay_vs_admin_token_lookup()
	_test_persist_merge_preserves_host()
	_test_boot_staging_intent()
	_test_staging_view_two_slots()
	_test_staging_ongoing_detection()
	_test_resume_button_labels()
	_test_row_text_no_tokens()
	_test_open_join_row_text()
	_test_create_routes_staging_not_enter_created()
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


func _test_dual_token_create_then_claim() -> void:
	_remove_test_file()
	CloudCredentialStoreScript.merge_host_create(
		"http://127.0.0.1:8000",
		"m_dual",
		"ht_host",
		"Alpha",
		0,
		CloudCredentialStoreScript.STATUS_STAGING,
		TEST_PATH,
	)
	CloudCredentialStoreScript.merge_seat_claim(
		"http://127.0.0.1:8000",
		"m_dual",
		"st_seat",
		1,
		"Alpha",
		CloudCredentialStoreScript.STATUS_STAGING,
		TEST_PATH,
	)
	var row: Dictionary = CloudCredentialStoreScript.find(TEST_PATH, "http://127.0.0.1:8000", "m_dual")
	_check(CloudCredentialStoreScript.host_token_from_entry(row) == "ht_host", "host preserved")
	_check(CloudCredentialStoreScript.gameplay_token_from_entry(row) == "st_seat", "seat preserved")
	_check(int(row.get("actor_id", -1)) == 1, "actor from claim")


func _test_legacy_host_in_seat_token_field() -> void:
	_remove_test_file()
	CloudCredentialStoreScript.upsert(
		TEST_PATH,
		{
			"server_url": "http://127.0.0.1:8000",
			"match_id": "m_legacy",
			"seat_token": "ht_oldhost",
			"is_host": true,
			"actor_id": 0,
		},
	)
	var row: Dictionary = CloudCredentialStoreScript.find(TEST_PATH, "http://127.0.0.1:8000", "m_legacy")
	_check(CloudCredentialStoreScript.host_token_from_entry(row) == "ht_oldhost", "legacy ht in seat_token")
	_check(CloudCredentialStoreScript.gameplay_token_from_entry(row).is_empty(), "legacy not gameplay")


func _test_gameplay_vs_admin_token_lookup() -> void:
	var entry: Dictionary = CloudCredentialStoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_tok",
		1,
		"st_play",
		false,
		-1,
		CloudCredentialStoreScript.STATUS_STAGING,
		"",
		"ht_admin",
	)
	_check(CloudCredentialStoreScript.admin_token_from_entry(entry) == "ht_admin", "admin ht")
	_check(CloudCredentialStoreScript.gameplay_token_from_entry(entry) == "st_play", "gameplay st")
	CloudCredentialStoreScript.upsert(TEST_PATH, entry)
	var boot: Dictionary = CloudCredentialStoreScript.resolve_seat_token_for_boot(
		"http://127.0.0.1:8000",
		"m_tok",
		"",
		"",
		TEST_PATH,
	)
	_check(boot["value"] == "st_play", "boot prefers seat")


func _test_persist_merge_preserves_host() -> void:
	_remove_test_file()
	CloudCredentialStoreScript.merge_host_create(
		"http://127.0.0.1:8000",
		"m_persist",
		"ht_p",
		"",
		0,
		CloudCredentialStoreScript.STATUS_STAGING,
		TEST_PATH,
	)
	CloudCredentialStoreScript.persist_after_bootstrap(
		TEST_PATH,
		"http://127.0.0.1:8000",
		"m_persist",
		"st_p",
		false,
		{"revision": 2, "display_name": "Persist"},
		1,
	)
	var row: Dictionary = CloudCredentialStoreScript.find(TEST_PATH, "http://127.0.0.1:8000", "m_persist")
	_check(CloudCredentialStoreScript.host_token_from_entry(row) == "ht_p", "persist keeps host")
	_check(CloudCredentialStoreScript.gameplay_token_from_entry(row) == "st_p", "persist adds seat")


func _test_boot_staging_intent() -> void:
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000",
		"m_stg",
		"ht_h",
		"st_s",
		0,
		"Lobby",
	)
	_check(BootIntentScript.mode == BootIntentScript.MODE_CLOUD_STAGING, "staging mode")
	_check(
		BootIntentScript.cloud_load_status_message(BootIntentScript.MODE_CLOUD_STAGING) == "Entering staging…",
		"staging message",
	)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(snap["mode"] == BootIntentScript.MODE_CLOUD_STAGING, "consume staging")
	_check(snap["host_token"] == "ht_h", "consume host")
	_check(snap["seat_token"] == "st_s", "consume seat")


func _test_staging_view_two_slots() -> void:
	var lobby_row := {
		"match_id": "m_view",
		"display_name": "Test Lobby",
		"status": "staging",
		"ready_to_start": false,
		"seats": [
			{"actor_id": 0, "claimed": true, "faction_id": "malmo", "ready": false},
			{"actor_id": 1, "claimed": false, "faction_id": null, "ready": false},
		],
		"available_factions": [
			{"id": "malmo", "display_name": "Malmöfubikkarna"},
			{"id": "vastervik", "display_name": "Västerviksjävlarna"},
			{"id": "paris", "display_name": "Pajasarna från Paris"},
		],
	}
	var view_mine: Dictionary = CloudStagingParsersScript.build_staging_view(lobby_row, 0)
	_check(bool(view_mine.get("ok")), "view ok")
	var slots_mine: Array = view_mine.get("slots", []) as Array
	_check(slots_mine.size() == 2, "two slots")
	_check(bool((slots_mine[0] as Dictionary).get("is_mine")), "slot0 mine")
	_check(not bool((slots_mine[1] as Dictionary).get("can_claim")), "slot1 not claim when seated")
	var view_open: Dictionary = CloudStagingParsersScript.build_staging_view(lobby_row, -1)
	var slots_open: Array = view_open.get("slots", []) as Array
	_check(bool((slots_open[1] as Dictionary).get("can_claim")), "slot1 claimable when no seat")


func _test_staging_ongoing_detection() -> void:
	_check(
		CloudStagingParsersScript.can_enter_gameplay_from_staging(true, "ongoing"),
		"ongoing + seat",
	)
	_check(
		not CloudStagingParsersScript.can_enter_gameplay_from_staging(false, "ongoing"),
		"ongoing no seat",
	)
	_check(
		CloudStagingParsersScript.host_only_needs_claim(true, false, "ongoing"),
		"host only ongoing",
	)


func _test_resume_button_labels() -> void:
	_check(
		CloudStagingParsersScript.saved_resume_button_label("ongoing", true) == "Resume match",
		"resume ongoing",
	)
	_check(
		CloudStagingParsersScript.saved_resume_button_label("staging", true) == "Continue setup",
		"continue staging seat",
	)
	_check(
		CloudStagingParsersScript.saved_resume_button_label("staging", false) == "Continue setup",
		"continue host only",
	)


func _test_row_text_no_tokens() -> void:
	var entry: Dictionary = CloudCredentialStoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_row",
		0,
		"st_secret",
		false,
		-1,
		CloudCredentialStoreScript.STATUS_STAGING,
		"Visible",
		"ht_secret",
	)
	var view: Dictionary = CloudCredentialStoreScript.build_saved_row_view(entry, "http://127.0.0.1:8000", {})
	_check(CloudCredentialStoreScript.row_text_has_no_token(str(view["row_text"]), entry), "row no token")
	_check(not str(view["row_text"]).contains("(host)"), "row no host suffix")
	_check(not str(view["row_text"]).contains("m_row"), "row no match_id")


func _test_open_join_row_text() -> void:
	var txt: String = CloudStagingParsersScript.open_staging_row_text(
		{"display_name": "Nordic Duel", "match_id": "m_hidden"},
	)
	_check(txt == "Join Nordic Duel", "join label")
	_check(not txt.contains("m_hidden"), "join no match_id")


func _test_create_routes_staging_not_enter_created() -> void:
	var resp := {
		"match_id": "m_new",
		"host_token": "ht_new",
		"display_name": "Fresh",
		"revision": 0,
	}
	BootIntentScript.set_cloud_staging("http://127.0.0.1:8000", "m_new", "ht_new", "", -1, "Fresh")
	_check(BootIntentScript.mode != BootIntentScript.MODE_CLOUD_ENTER_CREATED, "not enter-created")
	_check(BootIntentScript.mode == BootIntentScript.MODE_CLOUD_STAGING, "staging after create")
