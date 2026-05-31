# Headless: editor parses dump script on startup; ensure it reloads cleanly.
# Usage: godot --headless --path game -s res://domain/tests/test_dump_prototype_play_map_script_loads.gd
extends SceneTree


func _init() -> void:
	var scr: GDScript = load("res://domain/tests/dump_prototype_play_map.gd") as GDScript
	if scr == null:
		push_error("FAIL: dump_prototype_play_map.gd did not load")
		call_deferred("quit", 1)
		return
	print("PASS test_dump_prototype_play_map_script_loads")
	call_deferred("quit", 0)
