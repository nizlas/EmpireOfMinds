# Headless: Main scene default export avoids http://localhost IPv6 stalls on Windows Godot.
# Usage: godot --headless --path game -s res://cloud/tests/test_main_default_cloud_base_url.gd
extends SceneTree


const MAIN_SCENE_PATH: String = "res://main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("FAIL: could not load %s" % MAIN_SCENE_PATH)
		call_deferred("quit", 1)
		return
	var main: Node = packed.instantiate()
	var u: String = str(main.get("cloud_base_url"))
	main.queue_free()
	if u != "http://127.0.0.1:8000":
		push_error("FAIL: expected default cloud_base_url http://127.0.0.1:8000, got %s" % u)
		call_deferred("quit", 1)
		return
	print("PASS test_main_default_cloud_base_url")
	call_deferred("quit", 0)
