# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_lobby_parsers.gd
extends SceneTree

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_list_parse_no_tokens()
	_test_list_rejects_error()
	_test_claim_parse()
	_test_credential_from_create()
	_test_credential_from_claim()
	_test_entries_for_server()
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


func _test_list_parse_no_tokens() -> void:
	var raw := {
		"matches": [
			{
				"match_id": "m_a",
				"status": "staging",
				"seats": [{"actor_id": 0, "claimed": false}, {"actor_id": 1, "claimed": true}],
				"open_seat_count": 1,
			},
			{
				"match_id": "m_bad",
				"host_token": "ht_secret",
				"seats": [{"actor_id": 0, "token": "st_x", "claimed": false}],
			},
		],
	}
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	var rows: Array = parsed["matches"] as Array
	_check(rows.size() == 1, "leaky row stripped")
	_check(CloudClientScript.lobby_row_has_no_tokens(rows[0] as Dictionary), "row token-free")


func _test_list_rejects_error() -> void:
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response({"_error": "http"})
	_check(parsed.has("_error"), "list error preserved")
	_check((parsed["matches"] as Array).is_empty(), "list error empty")


func _test_claim_parse() -> void:
	var ok: Dictionary = CloudClientScript.parse_claim_response(
		{
			"match_id": "m_c",
			"actor_id": 1,
			"seat_token": "st_claimed",
			"status": "staging",
		}
	)
	_check(bool(ok.get("ok")), "claim ok")
	_check(ok["seat_token"] == "st_claimed", "claim token")
	var bad: Dictionary = CloudClientScript.parse_claim_response({"_error": "http"})
	_check(not bool(bad.get("ok")), "claim fail")


func _test_credential_from_create() -> void:
	var resp := {
		"match_id": "m_new",
		"host_token": "ht_host",
		"revision": 0,
		"snapshot": {"revision": 0},
	}
	var entry: Dictionary = CloudClientScript.credential_from_create_response(
		"http://127.0.0.1:8000",
		resp,
	)
	_check(entry["is_host"] == true, "create is_host")
	_check(entry["seat_token"] == "ht_host", "create token")


func _test_credential_from_claim() -> void:
	var parsed := {
		"ok": true,
		"match_id": "m_c",
		"actor_id": 1,
		"seat_token": "st_p1",
		"status": "staging",
	}
	var entry: Dictionary = CloudClientScript.credential_from_claim_response(
		"https://cloud.example.org",
		parsed,
	)
	_check(entry["is_host"] == false, "claim not host")
	_check(int(entry["actor_id"]) == 1, "claim actor")


func _test_entries_for_server() -> void:
	var path := "user://test_eom_lobby_parsers_c14c.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	CloudCredentialStoreScript.upsert(
		path,
		CloudCredentialStoreScript.make_entry("http://a", "m1", 0, "st_a", false),
	)
	CloudCredentialStoreScript.upsert(
		path,
		CloudCredentialStoreScript.make_entry("http://b", "m2", 1, "st_b", false),
	)
	var rows: Array = CloudCredentialStoreScript.entries_for_server(path, "http://a")
	_check(rows.size() == 1, "entries filtered by server")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
