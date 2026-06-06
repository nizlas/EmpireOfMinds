# One-shot: write reference slot catalog JSON (presentation only).
# Run from game/: godot --headless --path . --script res://presentation/export_tech_tree_slot_catalog.gd
extends SceneTree

const OUTPUT_PATH: String = "res://presentation/tech_tree_slot_catalog.reference.json"
const GridScript = preload("res://presentation/tech_tree_grid_layout.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var json_text: String = GridScript.export_slot_catalog_json()
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(json_text)
	file.close()
	print("Wrote %s (%d bytes)" % [OUTPUT_PATH, json_text.length()])
	quit(0)
