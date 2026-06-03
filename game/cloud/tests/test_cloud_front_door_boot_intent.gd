# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_front_door_boot_intent.gd
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	BootIntentScript.clear()
	_test_local_hotseat_intent()
	_test_create_response_boot_intent()
	_test_reconnect_intent()
	_test_consume_clears()
	_test_front_door_scene_loads()
	_test_create_saves_credential()
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


func _test_local_hotseat_intent() -> void:
	BootIntentScript.set_local_hotseat()
	_check(BootIntentScript.mode == BootIntentScript.MODE_LOCAL_HOTSEAT, "local mode")
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(snap["mode"] == BootIntentScript.MODE_LOCAL_HOTSEAT, "local consume")


func _test_create_response_boot_intent() -> void:
	var resp := {"match_id": "m_created", "host_token": "ht_created", "revision": 1}
	BootIntentScript.set_cloud_play_from_create_response("http://127.0.0.1:8000", resp, "tiny_test")
	_check(
		BootIntentScript.mode == BootIntentScript.MODE_CLOUD_ENTER_CREATED,
		"create response uses enter-created mode",
	)
	_check(BootIntentScript.match_id == "m_created", "create response match_id")
	_check(BootIntentScript.seat_token == "ht_created", "create response host_token")
	_check(
		BootIntentScript.cloud_load_status_message(BootIntentScript.MODE_CLOUD_ENTER_CREATED)
			== "Connecting to new cloud match…",
		"enter-created status message",
	)
	_check(
		BootIntentScript.cloud_load_status_message(BootIntentScript.MODE_CLOUD_RECONNECT)
			== "Reconnecting to cloud match…",
		"reconnect status message",
	)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(snap["match_id"] == "m_created", "create consume match_id")
	_check(snap["seat_token"] == "ht_created", "create consume seat_token")
	_check(snap["mode"] == BootIntentScript.MODE_CLOUD_ENTER_CREATED, "create consume enter-created mode")


func _test_reconnect_intent() -> void:
	BootIntentScript.set_cloud_reconnect("https://cloud.example.org", "m_x", "st_y", 1)
	_check(BootIntentScript.mode == BootIntentScript.MODE_CLOUD_RECONNECT, "reconnect mode")
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(snap["match_id"] == "m_x", "reconnect match_id")
	_check(snap["seat_token"] == "st_y", "reconnect token")
	_check(int(snap["actor_id"]) == 1, "reconnect actor")


func _test_consume_clears() -> void:
	BootIntentScript.set_local_hotseat()
	BootIntentScript.consume_for_main()
	_check(BootIntentScript.mode == BootIntentScript.MODE_NONE, "consume clears")


func _test_front_door_scene_loads() -> void:
	var packed: PackedScene = load("res://cloud/cloud_front_door.tscn") as PackedScene
	_check(packed != null, "front door scene loads")
	var node: Node = packed.instantiate()
	_check(node != null, "front door instantiates")
	node.free()


func _test_create_saves_credential() -> void:
	var path := "user://test_eom_front_door_c14c.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var resp := {
		"match_id": "m_fd",
		"host_token": "ht_fd",
		"revision": 2,
	}
	CloudCredentialStoreScript.upsert(
		path,
		CloudClientScript.credential_from_create_response("http://127.0.0.1:8000", resp),
	)
	var found: Dictionary = CloudCredentialStoreScript.find(path, "http://127.0.0.1:8000", "m_fd")
	_check(
		CloudCredentialStoreScript.host_token_from_entry(found) == "ht_fd",
		"create credential saved host",
	)
	_check(CloudCredentialStoreScript.gameplay_token_from_entry(found).is_empty(), "create no seat yet")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
