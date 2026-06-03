# Headless: C14c.1 local match labels and saved-list display helpers.
# Usage: godot --headless --path game -s res://cloud/tests/test_cloud_match_labels.gd
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const TEST_PATH: String = "user://test_eom_cloud_match_labels_c14c1.json"

var _total = 0
var _any_fail = false


func _init() -> void:
	_remove_test_file()
	_test_default_label_generation()
	_test_resolve_label_for_save()
	_test_display_and_row_text()
	_test_entries_for_server_local_only()
	_test_rename_preserves_credential_fields()
	_test_create_claim_default_labels()
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


func _test_default_label_generation() -> void:
	_remove_test_file()
	_check(StoreScript.generate_default_label(TEST_PATH) == "Match 1", "first default Match 1")
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://a", "m1", 0, "st1", true, -1, StoreScript.STATUS_STAGING, "Match 1"),
	)
	_check(StoreScript.generate_default_label(TEST_PATH) == "Match 2", "second default Match 2")
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://a", "m3", 1, "st3", false, -1, StoreScript.STATUS_STAGING, "Match 3"),
	)
	_check(StoreScript.generate_default_label(TEST_PATH) == "Match 4", "max Match N + 1 is Match 4")
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://a", "m_custom", 2, "stc", false, -1, StoreScript.STATUS_STAGING, "Saturday test"),
	)
	_check(StoreScript.generate_default_label(TEST_PATH) == "Match 4", "custom label does not consume number")


func _test_resolve_label_for_save() -> void:
	_remove_test_file()
	_check(StoreScript.resolve_label_for_save("My lobby", TEST_PATH) == "My lobby", "custom label kept")
	_check(StoreScript.resolve_label_for_save("  ", TEST_PATH) == "Match 1", "empty custom uses default")
	_check(StoreScript.resolve_label_for_save("", TEST_PATH) == "Match 1", "blank uses default")


func _test_display_and_row_text() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_abcdefghijklmnop",
		0,
		"ht_secret_token_value",
		true,
		5,
		StoreScript.STATUS_STAGING,
		"Saturday test",
	)
	_check(StoreScript.display_label(entry) == "Saturday test", "display uses custom label")
	entry["label"] = ""
	_check(
		StoreScript.display_label(entry) == StoreScript.short_match_id(entry),
		"display falls back to short match id",
	)
	entry["label"] = "Match 2"
	var row_text: String = StoreScript.format_saved_row_text(entry)
	_check(row_text.find("Match 2") >= 0, "row shows label")
	_check(row_text.find("actor 0") >= 0, "row shows actor")
	_check(row_text.find("(host)") >= 0, "row shows host")
	_check(StoreScript.row_text_has_no_token(row_text, entry), "row text hides token")
	var lobby_line: String = "Join m_abcdefghijklmnop as Player 1"
	_check(row_text != lobby_line, "saved row is not server lobby row text")


func _test_entries_for_server_local_only() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://a", "m_ok", 0, "st_ok", true, -1, StoreScript.STATUS_STAGING, "Match 1"),
	)
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://a", "m_no_tok", 1, "", false),
	)
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://b", "m_other", 0, "st_b", false),
	)
	var rows: Array = StoreScript.entries_for_server(TEST_PATH, "http://a")
	_check(rows.size() == 1, "saved list only credentialed local rows for server")
	_check(str((rows[0] as Dictionary).get("match_id", "")) == "m_ok", "saved row is local credential")


func _test_rename_preserves_credential_fields() -> void:
	_remove_test_file()
	var before: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_ren",
		2,
		"st_keep",
		false,
		9,
		StoreScript.STATUS_STAGING,
		"Old name",
	)
	before["updated_at"] = "2020-01-01T00:00:00"
	StoreScript.upsert(TEST_PATH, before)
	_check(StoreScript.rename_entry(TEST_PATH, "http://a", "m_ren", "New name"), "rename ok")
	var after: Dictionary = StoreScript.find(TEST_PATH, "http://a", "m_ren")
	_check(str(after.get("label", "")) == "New name", "label updated")
	_check(str(after.get("match_id", "")) == "m_ren", "match_id preserved")
	_check(StoreScript.normalize_server_url(str(after.get("server_url", ""))) == "http://a", "server preserved")
	_check(int(after.get("actor_id", -1)) == 2, "actor_id preserved")
	_check(str(after.get("seat_token", "")) == "st_keep", "seat_token preserved")
	_check(after.get("is_host") == false, "is_host preserved")
	_check(int(after.get("last_seen_revision", -2)) == 9, "revision preserved")
	_check(str(after.get("last_seen_status", "")) == StoreScript.STATUS_STAGING, "status preserved")
	_check(str(after.get("updated_at", "")) == "2020-01-01T00:00:00", "updated_at preserved on rename")


func _test_create_claim_default_labels() -> void:
	_remove_test_file()
	var create_resp := {"match_id": "m_new", "host_token": "ht_x", "revision": 1}
	var create_entry: Dictionary = CloudClientScript.credential_from_create_response(
		"http://a",
		create_resp,
		"",
		TEST_PATH,
	)
	_check(str(create_entry.get("label", "")) == "Match 1", "create credential default label")
	var claim_parsed := {
		"ok": true,
		"match_id": "m_c",
		"actor_id": 1,
		"seat_token": "st_y",
		"status": "staging",
	}
	var claim_entry: Dictionary = CloudClientScript.credential_from_claim_response(
		"http://a",
		claim_parsed,
		"Player two",
		TEST_PATH,
	)
	_check(str(claim_entry.get("label", "")) == "Player two", "claim custom label")
	var claim_default: Dictionary = CloudClientScript.credential_from_claim_response(
		"http://a",
		claim_parsed,
		"",
		TEST_PATH,
	)
	_check(str(claim_default.get("label", "")) == "Match 1", "claim empty uses Match 1 on empty store")
