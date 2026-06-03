# Headless: C14b.1/C14c.2 server display_name helpers and row text.
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_lobby_display_name()
	_test_resolved_display_name()
	_test_rename_parse()
	_test_row_text_no_token()
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


func _test_lobby_display_name() -> void:
	var row := {
		"match_id": "m_lobby1",
		"display_name": "Saturday test",
		"seats": [{"actor_id": 1, "claimed": false}],
	}
	_check(CloudClientScript.display_name_from_lobby_row(row) == "Saturday test", "lobby display_name")
	_check(CloudClientScript.lobby_row_has_no_tokens(row), "lobby row no tokens")
	_check(
		CloudClientScript.lobby_open_row_text(row, 1) == "Join Saturday test as Player 1",
		"open row uses display_name",
	)


func _test_resolved_display_name() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_x",
		0,
		"ht_secret",
		true,
		-1,
		StoreScript.STATUS_STAGING,
		"Old local cache",
	)
	var server_names := {"m_x": "Server Title"}
	_check(
		StoreScript.resolved_display_name(entry, server_names) == "Server Title",
		"server display_name wins",
	)
	_check(
		StoreScript.resolved_display_name(entry, {}) == "Old local cache",
		"local label fallback",
	)
	entry["label"] = ""
	_check(
		StoreScript.full_display_name(entry, {}) == "m_x",
		"full match_id fallback without truncation",
	)


func _test_rename_parse() -> void:
	var ok: Dictionary = CloudClientScript.parse_rename_display_response(
		{"match_id": "m_r", "display_name": "New Title"}
	)
	_check(bool(ok.get("ok", false)), "rename parse ok")
	_check(ok["display_name"] == "New Title", "rename parse name")
	var bad: Dictionary = CloudClientScript.parse_rename_display_response({"_error": "http"})
	_check(not bool(bad.get("ok", false)), "rename parse fail")


func _test_row_text_no_token() -> void:
	var entry: Dictionary = StoreScript.make_entry(
		"http://a",
		"m_row",
		1,
		"st_row_secret_token",
		false,
		-1,
		StoreScript.STATUS_STAGING,
		"cache",
	)
	var row_text: String = StoreScript.format_saved_row_text(entry, {"m_row": "Public Name"})
	_check(row_text.find("Public Name") >= 0, "row shows server name")
	_check(StoreScript.row_text_has_no_token(row_text, entry), "row hides token")
