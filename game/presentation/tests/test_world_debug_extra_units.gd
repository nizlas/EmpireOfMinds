# Headless: godot --headless --path game -s res://presentation/tests/test_world_debug_extra_units.gd
extends SceneTree

const WorldDebugExtraUnitsScript = preload("res://presentation/world/world_debug_extra_units.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

const ANCHORS := {
	Vector2i(1, 1): Vector3(1.5, 2.0, -1.25),
	Vector2i(2, 1): Vector3(3.25, 1.6, -0.75),
	Vector2i(0, 1): Vector3(0.0, 1.9, -1.0),
	Vector2i(3, 1): Vector3(4.5, 1.7, -0.9),
	Vector2i(2, 0): Vector3(3.0, 1.5, 0.2),
	Vector2i(2, 14): Vector3(2.75, 0.4, 12.5),
	Vector2i(2, 13): Vector3(2.5, 0.8, 11.25),
}

var _total := 0
var _any_fail := false


func _base_units() -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler"},
		{"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior"},
		{"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler"},
		{"id": 4, "owner_id": 1, "position": [2, 13], "type_id": "warrior"},
	]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	OS.set_environment(Warrior3DExperimentScript.ENV_DEBUG_EXTRA_3D_CHARACTERS, "")
	_check(
		WorldDebugExtraUnitsScript.merge_into_units(_base_units(), ANCHORS).size() == 4,
		"env off leaves unit count unchanged"
	)

	OS.set_environment(Warrior3DExperimentScript.ENV_DEBUG_EXTRA_3D_CHARACTERS, "1")
	# Snapshot without generated_warrior → client fallback adds him + niclas + bronze.
	var merged_fallback: Array = WorldDebugExtraUnitsScript.merge_into_units(
		_base_units(), ANCHORS
	)
	_check(merged_fallback.size() == 7, "fallback adds niclas+bronze+generated_warrior")
	var fallback_types: Dictionary = {}
	for row in merged_fallback:
		fallback_types[str(row["type_id"])] = true
	_check(fallback_types.has("generated_warrior"), "fallback includes generated_warrior")
	_check(fallback_types.has("niclas"), "fallback includes niclas")
	_check(fallback_types.has("warrior"), "production warrior still present")

	# Snapshot already has server generated_warrior → no duplicate.
	var with_server: Array = _base_units()
	with_server.append(
		{"id": 5, "owner_id": 0, "position": [2, 0], "type_id": "generated_warrior"}
	)
	var merged_server: Array = WorldDebugExtraUnitsScript.merge_into_units(
		with_server, ANCHORS
	)
	_check(merged_server.size() == 7, "server generated_warrior + niclas + bronze only")
	var gw_count := 0
	for row in merged_server:
		if str(row["type_id"]) == "generated_warrior":
			gw_count += 1
	_check(gw_count == 1, "generated_warrior is not duplicated when server already has it")
	_check(int(merged_server[4]["id"]) == 5, "server generated_warrior id retained")

	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_tile_anchors(ANCHORS)
	view.apply_snapshot_units(merged_server)
	_check(view.type_id_for_unit(5) == "generated_warrior", "generated_warrior renders")
	_check(view.type_id_for_unit(2) == "warrior", "production warrior still renders")

	OS.set_environment(Warrior3DExperimentScript.ENV_DEBUG_EXTRA_3D_CHARACTERS, "")
	view.queue_free()
	_finish()


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print("test_world_debug_extra_units: %d checks, %s" % [_total, "FAIL" if _any_fail else "OK"])
	quit(1 if _any_fail else 0)
