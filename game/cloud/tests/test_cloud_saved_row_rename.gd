# Headless: C14c.2 saved row view + rename prefill/submit/refresh (no truncated sources).
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const TEST_PATH: String = "user://test_eom_saved_row_rename_c14c2.json"
const LONG_NAME: String = "Saturday Evening Campaign With Friends"

var _total = 0
var _any_fail = false


func _init() -> void:
	_remove_test_file()
	_test_prefill_uses_full_display_name_not_truncated()
	_test_row_text_primary_not_truncated()
	_test_rename_submit_body_exact()
	_test_apply_rename_updates_view_and_cache()
	_test_server_name_wins_over_stale_label()
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


func _test_prefill_uses_full_display_name_not_truncated() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_verylongmatchid123456",
		0,
		"ht_host",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"",
	)
	var server_names := {"m_verylongmatchid123456": LONG_NAME}
	var view: Dictionary = StoreScript.build_saved_row_view(entry, "http://a", server_names)
	_check(view["display_name"] == LONG_NAME, "prefill field is full server name")
	_check(view["display_name"] != StoreScript.short_match_id(entry), "prefill not short_match_id")
	var rendered: String = str(view.get("row_text", ""))
	_check(rendered.find(LONG_NAME) >= 0, "rendered row includes full name")


func _test_row_text_primary_not_truncated() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_row",
		0,
		"ht_x",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		LONG_NAME,
	)
	var view: Dictionary = StoreScript.build_saved_row_view(entry, "http://a", {})
	_check(view["row_text"] == LONG_NAME + " (host)", "row is display name only")
	_check(StoreScript.row_text_hides_match_id(str(view["row_text"]), "m_row"), "row hides match_id")


func _test_rename_submit_body_exact() -> void:
	_check(
		StoreScript.rename_submit_body("  " + LONG_NAME + "  ") == LONG_NAME,
		"rename submit strips only whitespace",
	)


func _test_apply_rename_updates_view_and_cache() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_ren",
		0,
		"ht_ren",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Old Title",
	)
	StoreScript.upsert(TEST_PATH, entry)
	var view: Dictionary = StoreScript.build_saved_row_view(entry, "http://a", {"m_ren": "Old Title"})
	var updated: Dictionary = StoreScript.apply_rename_to_view(view, LONG_NAME)
	_check(updated["display_name"] == LONG_NAME, "view display_name updated")
	_check(str(updated["row_text"]).find(LONG_NAME) >= 0, "view row_text updated")
	StoreScript.update_label_cache(TEST_PATH, "http://a", "m_ren", LONG_NAME)
	var reloaded: Dictionary = StoreScript.build_saved_row_view(
		StoreScript.find(TEST_PATH, "http://a", "m_ren"),
		"http://a",
		{"m_ren": "Stale Server"},
	)
	_check(reloaded["display_name"] == "Stale Server", "server map wins on reload")
	_check(
		StoreScript.full_display_name(StoreScript.find(TEST_PATH, "http://a", "m_ren"), {"m_ren": "Stale Server"})
			== "Stale Server",
		"full_display_name prefers server map",
	)


func _test_server_name_wins_over_stale_label() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_stale",
		0,
		"ht_s",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Old Local Cache",
	)
	var view: Dictionary = StoreScript.build_saved_row_view(
		entry,
		"http://a",
		{"m_stale": LONG_NAME},
	)
	_check(view["display_name"] == LONG_NAME, "server display_name beats stale local label")
	var row_text: String = str(view["row_text"])
	_check(StoreScript.row_text_has_no_token(row_text, entry), "row text hides token")
