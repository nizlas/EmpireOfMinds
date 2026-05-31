# Opt-in golden generator: prototype play map cells JSON (sorted) for server parity tests.
# Run from game/ project directory (Godot 4.x):
#   godot --headless -s res://domain/tests/dump_prototype_play_map.gd -- C:/path/to/server/tests/golden/prototype_play_map.gd_v0.json
# Do NOT add this script to scripts/run-godot-tests.ps1.
extends SceneTree

const _HexMap := preload("res://domain/hex_map.gd")
const _TerrainRuleDefinitions := preload("res://domain/content/terrain_rule_definitions.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = ""
	if args.size() > 0:
		out_path = String(args[0]).strip_edges()
	if out_path.is_empty():
		push_error("Usage: godot --headless -s .../dump_prototype_play_map.gd -- <output_json_path>")
		quit(1)
		return

	var m = _HexMap.make_prototype_play_map()
	var coords: Array = m.coords()
	coords.sort_custom(
		func(a, b) -> bool:
			if a.q != b.q:
				return a.q < b.q
			return a.r < b.r
	)

	var cells: Array = []
	for c in coords:
		var lf: int = m.landform_at(c)
		var lf_s := "flat"
		if lf == _HexMap.Landform.HILLS:
			lf_s = "hills"
		cells.append(
			{
				"q": int(c.q),
				"r": int(c.r),
				"terrain": _TerrainRuleDefinitions.terrain_id_for_hex_map_value(m.terrain_at(c)),
				"landform": lf_s,
				"woods": m.has_woods(c),
			}
		)

	var payload := JSON.stringify(cells, "\t", true)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot open for write: %s (%s)" % [out_path, str(FileAccess.get_open_error())])
		quit(2)
		return
	f.store_string(payload)
	f.store_string("\n")
	print("Wrote %d cells to %s" % [cells.size(), out_path])
	quit(0)
