# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_credential_profile.gd
# Slice c14d-dev: EOM_CLOUD_PROFILE credential store paths.
extends SceneTree

const StoreScript = preload("res://cloud/cloud_credential_store.gd")

const TEST_ISOLATE_A: String = "user://test_cloud_profile_isolate_a.json"
const TEST_ISOLATE_B: String = "user://test_cloud_profile_isolate_b.json"
const TEST_ISOLATE_DEFAULT: String = "user://test_cloud_profile_isolate_default.json"
const TEST_NO_PROFILE: String = "user://test_cloud_profile_no_profile_behavior.json"

var _total = 0
var _any_fail = false
var _saved_profile_env: String = ""


func _init() -> void:
	_saved_profile_env = OS.get_environment(StoreScript.PROFILE_ENV_VAR)
	_cleanup_isolate_files()
	_test_sanitize_and_paths()
	_test_resolved_path_from_environment()
	_test_unsafe_chars_cannot_escape_user()
	_test_store_isolation()
	_test_no_profile_explicit_path_unchanged()
	_set_profile_env(_saved_profile_env)
	_cleanup_isolate_files()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _set_profile_env(value: String) -> void:
	OS.set_environment(StoreScript.PROFILE_ENV_VAR, value)


func _cleanup_isolate_files() -> void:
	for p in [TEST_ISOLATE_A, TEST_ISOLATE_B, TEST_ISOLATE_DEFAULT, TEST_NO_PROFILE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_sanitize_and_paths() -> void:
	_check(StoreScript.sanitize_profile_name("") == "", "empty profile")
	_check(
		StoreScript.store_path_for_profile_name("") == StoreScript.DEFAULT_PATH,
		"no profile -> default path",
	)
	_check(
		StoreScript.store_path_for_profile_name("A") == "user://cloud_matches_A.json",
		"profile A path",
	)
	_check(
		StoreScript.store_path_for_profile_name("B") == "user://cloud_matches_B.json",
		"profile B path",
	)
	_check(StoreScript.sanitize_profile_name(" test ") == "test", "trim spaces")
	_check(
		StoreScript.store_path_for_profile_name(" test ")
			== "user://cloud_matches_test.json",
		"trimmed profile path",
	)
	_check(
		StoreScript.store_path_for_profile_name("local-1")
			== "user://cloud_matches_local-1.json",
		"hyphen profile path",
	)


func _test_resolved_path_from_environment() -> void:
	_set_profile_env("")
	_check(
		StoreScript.resolved_store_path() == StoreScript.DEFAULT_PATH,
		"resolved default when env missing",
	)
	_set_profile_env("A")
	_check(
		StoreScript.resolved_store_path() == "user://cloud_matches_A.json",
		"resolved profile A",
	)
	_set_profile_env("B")
	_check(
		StoreScript.resolved_store_path() == "user://cloud_matches_B.json",
		"resolved profile B",
	)


func _test_unsafe_chars_cannot_escape_user() -> void:
	var raw: String = " ../evil\\path "
	var sanitized: String = StoreScript.sanitize_profile_name(raw)
	_check(not sanitized.contains("/"), "sanitize no slash")
	_check(not sanitized.contains("\\"), "sanitize no backslash")
	_check(not sanitized.contains(".."), "sanitize no dotdot")
	var path: String = StoreScript.store_path_for_profile_name(raw)
	_check(path.begins_with("user://cloud_matches_"), "profile path stays under user://")
	var filename: String = path.replace("user://", "")
	_check(not filename.contains("/"), "profile filename no slash")
	_check(not filename.contains("\\"), "profile filename no backslash")
	_check(not filename.contains(".."), "profile filename no dotdot")


func _test_store_isolation() -> void:
	_cleanup_isolate_files()
	var path_a: String = StoreScript.store_path_for_profile_name("A")
	var path_b: String = StoreScript.store_path_for_profile_name("B")
	var entry_a: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_profile_a_only",
		0,
		"ht_a_only",
		true,
		1,
		StoreScript.STATUS_STAGING,
		"Match A",
	)
	var entry_b: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_profile_b_only",
		1,
		"st_b_only",
		false,
		2,
		StoreScript.STATUS_STAGING,
		"Match B",
	)
	var entry_default: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_profile_default_only",
		0,
		"ht_default_only",
		true,
		3,
		StoreScript.STATUS_STAGING,
		"Match Default",
	)
	StoreScript.upsert(TEST_ISOLATE_A, entry_a)
	StoreScript.upsert(TEST_ISOLATE_B, entry_b)
	StoreScript.upsert(TEST_ISOLATE_DEFAULT, entry_default)
	_check(
		StoreScript.find(TEST_ISOLATE_B, "http://127.0.0.1:8000", "m_profile_a_only").is_empty(),
		"A entry not in B file",
	)
	_check(
		not StoreScript.find(TEST_ISOLATE_A, "http://127.0.0.1:8000", "m_profile_a_only").is_empty(),
		"A entry in A file",
	)
	_check(
		not StoreScript.find(
			TEST_ISOLATE_DEFAULT,
			"http://127.0.0.1:8000",
			"m_profile_default_only",
		).is_empty(),
		"default entry in default file",
	)
	_check(
		StoreScript.find(TEST_ISOLATE_A, "http://127.0.0.1:8000", "m_profile_default_only").is_empty(),
		"default entry not in A file",
	)
	# Naming convention matches profile-specific production paths (separate files).
	_check(path_a == "user://cloud_matches_A.json", "isolate A naming")
	_check(path_b == "user://cloud_matches_B.json", "isolate B naming")


func _test_no_profile_explicit_path_unchanged() -> void:
	_set_profile_env("")
	_cleanup_isolate_files()
	var entry: Dictionary = StoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m_explicit_test_path",
		0,
		"ht_explicit",
		true,
		1,
		StoreScript.STATUS_STAGING,
	)
	StoreScript.upsert(TEST_NO_PROFILE, entry)
	var loaded: Dictionary = StoreScript.load_store(TEST_NO_PROFILE)
	var matches: Array = loaded["matches"] as Array
	_check(matches.size() == 1, "explicit path round-trip when no profile env")
	_check(
		not StoreScript.find(
			TEST_NO_PROFILE,
			"http://127.0.0.1:8000",
			"m_explicit_test_path",
		).is_empty(),
		"explicit path find when no profile env",
	)
