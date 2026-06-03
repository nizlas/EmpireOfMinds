# Headless: BootIntent reconnect must use GET path credentials, not POST create (invalid URL strands fast).
# Usage: godot --headless --path game -s res://cloud/tests/test_main_cloud_boot_intent_reconnect.gd
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const MAIN_SCENE_PATH: String = "res://main.tscn"


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	call_deferred("quit", 1)


func _run() -> void:
	BootIntentScript.set_cloud_reconnect("::not-a-url::", "m_boot_only", "ht_boot_only", 0)
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("FAIL: could not load %s" % MAIN_SCENE_PATH)
		return
	var main: Node = packed.instantiate()
	main.set("cloud_match_id", "")
	main.set("cloud_seat_token", "stale_inspector_token")
	get_root().add_child(main)
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	var stranded: bool = false
	while Time.get_ticks_msec() < deadline_ms:
		if bool(main.get("_cloud_boot_stranded")):
			stranded = true
			break
		await process_frame
	if not stranded:
		_fail("FAIL: expected cloud reconnect boot to strand (invalid base URL / transport failure)")
		main.queue_free()
		return
	var overlay_lbl = main.get("_cloud_loading_label")
	var overlay_text: String = str(overlay_lbl.get("text")) if overlay_lbl != null else ""
	if overlay_text.find("start a cloud match") >= 0:
		_fail("FAIL: BootIntent with match_id must not POST /v1/matches (double-create)")
		main.queue_free()
		return
	if overlay_text.find("m_boot_only") < 0 or overlay_text.find("reconnect") < 0:
		_fail("FAIL: expected GET reconnect strand for m_boot_only, got: %s" % overlay_text)
		main.queue_free()
		return
	if CloudClientScript.should_create_match("m_boot_only"):
		_fail("FAIL: test precondition: m_boot_only must not trigger create path")
		main.queue_free()
		return
	if main.get("_play_game_state") != null:
		_fail("FAIL: must not wire local hotseat on failed reconnect")
		main.queue_free()
		return
	main.queue_free()
	print("PASS test_main_cloud_boot_intent_reconnect")
	call_deferred("quit", 0)
