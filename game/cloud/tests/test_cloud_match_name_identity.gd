# Headless: C14c.3 match-name identity — row text, duplicates, server default names.
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const CUSTOM: String = "Saturday Campaign"
const TOKEN: String = "ht_secret_token_xyz"
const MID: String = "m_abc123456789"

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_resume_row_text_display_name_only()
	_test_open_row_text_no_match_id()
	_test_row_text_hides_match_id_and_token()
	_test_create_duplicate_case_insensitive()
	_test_create_whitespace_duplicate()
	_test_create_empty_uses_default()
	_test_rename_allows_own_name()
	_test_rename_blocks_other_duplicate()
	_test_rename_whitespace_same_name()
	_test_server_default_match_4()
	_test_server_default_not_duplicate()
	_test_create_identity_still_uses_match_id_internally()
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


func _lobby(match_id: String, display_name: String) -> Dictionary:
	return {
		"match_id": match_id,
		"display_name": display_name,
		"status": "staging",
		"revision": 1,
		"seats": [{"actor_id": 0, "claimed": true}, {"actor_id": 1, "claimed": false}],
	}


func _test_resume_row_text_display_name_only() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		"http://a",
		MID,
		0,
		TOKEN,
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"cache",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		_lobby(MID, CUSTOM),
		cred,
		"http://a",
	)
	_check(view["row_text"] == CUSTOM + " (host)", "resume host row is name only")
	_check(view["match_id"] == MID, "internal match_id retained")


func _test_open_row_text_no_match_id() -> void:
	var row: Dictionary = _lobby(MID, CUSTOM)
	var text: String = CloudClientScript.lobby_open_row_text(row, 1)
	_check(text.find(CUSTOM) >= 0, "open row shows display_name")
	_check(not text.contains(MID), "open row hides match_id")


func _test_row_text_hides_match_id_and_token() -> void:
	var cred: Dictionary = StoreScript.make_entry(
		"http://a",
		MID,
		1,
		TOKEN,
		false,
		-1,
		StoreScript.STATUS_STAGING,
		"",
	)
	var view: Dictionary = CloudClientScript.build_resume_row_view(_lobby(MID, CUSTOM), cred, "http://a")
	_check(StoreScript.row_text_hides_match_id(str(view["row_text"]), MID), "row hides match_id")
	_check(StoreScript.row_text_has_no_token(str(view["row_text"]), cred), "row hides token")


func _test_create_duplicate_case_insensitive() -> void:
	var lobby: Array = [_lobby("m1", "Test Match")]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_create_display_name("TEST MATCH", "Match 9", keys)
	_check(not bool(v.get("ok", true)), "duplicate blocks OK")
	_check(v["message"] == StoreScript.MSG_DUPLICATE_DISPLAY_NAME, "duplicate message")


func _test_create_whitespace_duplicate() -> void:
	var lobby: Array = [_lobby("m1", "Test Match")]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_create_display_name("  test match  ", "Match 9", keys)
	_check(not bool(v.get("ok", true)), "trimmed duplicate blocks OK")


func _test_create_empty_uses_default() -> void:
	var lobby: Array = [_lobby("m1", "Alpha")]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var default_label: String = StoreScript.generate_unique_default_label_from_server(lobby)
	var v: Dictionary = StoreScript.validate_create_display_name("   ", default_label, keys)
	_check(bool(v.get("ok", false)), "empty uses unique default")
	_check(v["effective"] == default_label, "effective is default label")


func _test_rename_allows_own_name() -> void:
	var lobby: Array = [_lobby("m_own", CUSTOM)]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_rename_display_name(CUSTOM, "m_own", keys)
	_check(bool(v.get("ok", false)), "same match name allowed")
	var v2: Dictionary = StoreScript.validate_rename_display_name("  " + CUSTOM + "  ", "m_own", keys)
	_check(bool(v2.get("ok", false)), "same name different spacing allowed")


func _test_rename_blocks_other_duplicate() -> void:
	var lobby: Array = [_lobby("m_a", "Alpha"), _lobby("m_b", "Beta")]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_rename_display_name("beta", "m_a", keys)
	_check(not bool(v.get("ok", true)), "rename duplicate other match blocked")


func _test_rename_whitespace_same_name() -> void:
	var lobby: Array = [_lobby("m_x", "My Game")]
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_rename_display_name("my game", "m_x", keys)
	_check(bool(v.get("ok", false)), "case-only change on own match allowed")


func _test_server_default_match_4() -> void:
	var lobby: Array = [
		_lobby("m1", "Match 1"),
		_lobby("m3", "Match 3"),
		_lobby("m9", "Custom Nine"),
	]
	var suggested: String = StoreScript.generate_unique_default_label_from_server(lobby)
	_check(suggested == "Match 4", "Match 1 and 3 -> suggest Match 4")


func _test_server_default_not_duplicate() -> void:
	var lobby: Array = [_lobby("m1", "Match 1"), _lobby("m2", "Match 2")]
	var suggested: String = StoreScript.generate_unique_default_label_from_server(lobby)
	var keys: Dictionary = StoreScript.display_name_key_map_from_lobby(lobby)
	var v: Dictionary = StoreScript.validate_create_display_name(suggested, suggested, keys)
	_check(bool(v.get("ok", false)), "generated default is not duplicate")


func _test_create_identity_still_uses_match_id_internally() -> void:
	var resp := {"match_id": "m_new", "host_token": "ht_n", "display_name": CUSTOM}
	var trace: Dictionary = CloudClientScript.create_flow_identity(
		CUSTOM,
		resp,
		"http://a",
		"prototype_play",
		"user://test_c14c3_identity.json",
	)
	_check(trace["response_match_id"] == "m_new", "trace match_id")
	_check(trace["body_display_name"] == CUSTOM, "POST uses custom name")
	var rows: Array = CloudClientScript.build_resume_rows_from_lobby(
		[_lobby("m_new", CUSTOM)],
		{"m_new": CloudClientScript.credential_from_create_response("http://a", resp, CUSTOM)},
		"http://a",
	)
	_check((rows[0] as Dictionary)["row_text"] == CUSTOM + " (host)", "resume shows name not id")
