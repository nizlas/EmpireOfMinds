# Headless: Slice **C9** — reconnect bootstrap must not wire local hotseat when GET fails.
# Usage: godot --headless --path game -s res://cloud/tests/test_main_cloud_reconnect_get_match.gd
extends SceneTree

const MAIN_SCENE_PATH: String = "res://main.tscn"


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	call_deferred("quit", 1)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("FAIL: could not load %s" % MAIN_SCENE_PATH)
		return
	var main: Node = packed.instantiate()
	main.set("use_cloud_server", true)
	main.set("cloud_base_url", "::not-a-url::")
	main.set("cloud_match_id", "m_does_not_exist")
	main.set("cloud_scenario_id", "prototype_play")
	get_root().add_child(main)
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		if bool(main.get("_cloud_boot_stranded")):
			break
		await process_frame
	if not bool(main.get("_cloud_boot_stranded")):
		_fail("FAIL: expected cloud reconnect boot to strand (invalid base URL / transport failure)")
		if is_instance_valid(main):
			main.queue_free()
		return
	if main.get("_play_game_state") != null:
		_fail("FAIL: _play_game_state must stay null when cloud reconnect fails without snapshot")
		main.queue_free()
		return
	var mv: Node = main.get_node_or_null("MapView")
	if mv != null and mv.get("map") != null:
		_fail("FAIL: MapView.map must stay null until server snapshot wires session")
		main.queue_free()
		return
	var selv: Node = main.get_node_or_null("SelectionView")
	if selv != null and selv.get("scenario") != null:
		_fail("FAIL: SelectionView.scenario must stay null until server wire")
		main.queue_free()
		return
	main.queue_free()
	print("PASS test_main_cloud_reconnect_get_match")
	call_deferred("quit", 0)
