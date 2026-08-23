# One-shot: write A1 native .import configs then exit.
# Follow with: godot --path game --import
extends SceneTree


func _initialize() -> void:
	var Native = load(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
	)
	var wrote: Dictionary = Native.write_import_files()
	print("A1_WRITE_IMPORT ", wrote)
	Native.write_notes({"phase": "import_files_written"})
	quit(0 if bool(wrote.get("ok", false)) else 1)
