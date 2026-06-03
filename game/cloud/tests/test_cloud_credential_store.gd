# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_credential_store.gd
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")

const TEST_PATH: String = "user://test_eom_cloud_credential_store_c14a.json"

var _total = 0
var _any_fail = false


func _init() -> void:
	_remove_test_file()
	_test_missing_file()
	_test_round_trip()
	_test_upsert_dedupe()
	_test_find()
	_test_corrupt_file()
	_test_resolve_conservative()
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


func _test_missing_file() -> void:
	var s: Dictionary = StoreScript.load_store(TEST_PATH)
	_check(int(s.get("version", 0)) == StoreScript.STORE_VERSION, "missing version")
	_check((s["matches"] as Array).is_empty(), "missing file empty matches")


func _test_round_trip() -> void:
	_remove_test_file()
	var entry: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_round",
		0,
		"ht_abc",
		true,
		3,
		StoreScript.STATUS_UNKNOWN,
	)
	StoreScript.upsert(TEST_PATH, entry)
	var loaded: Dictionary = StoreScript.load_store(TEST_PATH)
	var matches: Array = loaded["matches"] as Array
	_check(matches.size() == 1, "round-trip one row")
	var row: Dictionary = matches[0] as Dictionary
	_check(row["match_id"] == "m_round", "round-trip match_id")
	_check(row["seat_token"] == "ht_abc", "round-trip token")


func _test_upsert_dedupe() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://127.0.0.1:8000/", "m_dup", 0, "ht_one", true, 1),
	)
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://127.0.0.1:8000", "m_dup", 1, "st_two", false, 2),
	)
	var loaded: Dictionary = StoreScript.load_store(TEST_PATH)
	_check((loaded["matches"] as Array).size() == 1, "dedupe single row")
	var row: Dictionary = (loaded["matches"] as Array)[0] as Dictionary
	_check(row["seat_token"] == "st_two", "dedupe latest token")
	_check(int(row["actor_id"]) == 1, "dedupe latest actor_id")
	_check(int(row["last_seen_revision"]) == 2, "dedupe latest revision")


func _test_find() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("http://127.0.0.1:8000", "m_dup", 1, "st_two", false, 2),
	)
	var hit: Dictionary = StoreScript.find(TEST_PATH, "http://127.0.0.1:8000", "m_dup")
	_check(not hit.is_empty(), "find hit")
	_check(hit["match_id"] == "m_dup", "find match_id")
	var miss: Dictionary = StoreScript.find(TEST_PATH, "http://other", "m_dup")
	_check(miss.is_empty(), "find wrong server")


func _test_corrupt_file() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	var s: Dictionary = StoreScript.load_store(TEST_PATH)
	_check((s["matches"] as Array).is_empty(), "corrupt returns empty")


func _test_resolve_conservative() -> void:
	_remove_test_file()
	StoreScript.upsert(
		TEST_PATH,
		StoreScript.make_entry("https://cloud.example.org", "m_saved", 0, "st_saved", false, 0),
	)
	var env_wins: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"m_saved",
		"ht_env",
		"st_inspector",
		TEST_PATH,
	)
	_check(env_wins["value"] == "ht_env", "env token wins")
	_check(env_wins["source"] == "EOM_CLOUD_SEAT_TOKEN", "env source")
	var boot_wins: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"m_saved",
		"",
		"st_inspector",
		TEST_PATH,
		"ht_boot",
	)
	_check(boot_wins["value"] == "ht_boot", "boot token beats inspector")
	_check(boot_wins["source"] == "BootIntent", "boot source")
	var insp_wins: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"m_saved",
		"",
		"st_inspector",
		TEST_PATH,
	)
	_check(insp_wins["value"] == "st_inspector", "inspector token wins")
	_check(insp_wins["source"] == "Main.cloud_seat_token", "inspector source")
	var store_wins: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"m_saved",
		"",
		"",
		TEST_PATH,
	)
	_check(store_wins["value"] == "st_saved", "saved token when match_id known")
	_check(store_wins["source"] == "cloud_credential_store", "store source")
	var no_mid: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"",
		"",
		"",
		TEST_PATH,
	)
	_check(no_mid["value"] == "", "no match_id no store lookup")
	var unknown_mid: Dictionary = StoreScript.resolve_seat_token_for_boot(
		"https://cloud.example.org",
		"m_unknown",
		"",
		"",
		TEST_PATH,
	)
	_check(unknown_mid["value"] == "", "unknown match_id no token")
