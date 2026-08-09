# Headless: godot --headless --path game -s res://presentation/tests/test_world_cities_view.gd
#
# N8a world-city projection: WorldCitiesView reconciles one stable Node3D
# root per snapshot city (keyed by exact city id), places every root exactly
# at the supplied tile anchor, reuses ancient_village below a city-specific
# CITY_MODEL_ROOT_SCALE ModelRoot (not the humanoid unit scale), waits until
# BOTH snapshot cities and anchors are available, never duplicates on
# reapplied snapshots, and never falls back to the origin.
extends SceneTree

const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

const ANCHORS := {
	Vector2i(1, 1): Vector3(1.5, 2.0, -1.25),
	Vector2i(3, 1): Vector3(4.0, 1.2, -0.5),
}

var _total := 0
var _any_fail := false


func _cities() -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
		{"id": 2, "owner_id": 0, "position": [3, 1], "name": "Settlement 2"},
	]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# City scale is an independent presentation contract — never the unit scale.
	_check(
		WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE != WorldUnitsViewScript.MODEL_ROOT_SCALE,
		"city scale is distinct from humanoid unit MODEL_ROOT_SCALE"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE, 5.0),
		"city CITY_MODEL_ROOT_SCALE is the tuned 5.0 contract"
	)

	var view = WorldCitiesViewScript.new()
	root.add_child(view)
	view.set_tile_anchors(ANCHORS)
	_check(view.city_count() == 0, "anchors alone render nothing")
	view.apply_snapshot_cities(_cities())
	_check(view.city_count() == 2, "both snapshot cities instantiate")
	_check(view.city_ids() == [1, 2], "city ids are exact")
	for row in _cities():
		var city_id: int = int(row["id"])
		var node = view.root_for_city(city_id)
		_check(node != null, "city %d has a root" % city_id)
		if node == null:
			continue
		var anchor: Vector3 = ANCHORS[Vector2i(int(row["position"][0]), int(row["position"][1]))]
		_check(node.position == anchor, "city %d root sits exactly at its tile anchor" % city_id)
		var model_root: Node3D = node.get_node_or_null("ModelRoot") as Node3D
		_check(model_root != null, "city %d has a ModelRoot" % city_id)
		if model_root != null:
			_check(
				model_root.scale == Vector3.ONE * WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE,
				"city %d ModelRoot uses CITY_MODEL_ROOT_SCALE %s"
				% [city_id, str(WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE)]
			)
			_check(
				not is_equal_approx(model_root.scale.x, WorldUnitsViewScript.MODEL_ROOT_SCALE),
				"city %d ModelRoot is not the unit scale 0.5" % city_id
			)
			_check(model_root.get_child_count() == 1, "city %d ModelRoot holds the village" % city_id)
		_check(view.name_for_city(city_id) == str(row["name"]), "city %d name mirrored" % city_id)

	var ids_before := {}
	for city_id in view.city_ids():
		ids_before[city_id] = view.root_for_city(int(city_id)).get_instance_id()
	view.apply_snapshot_cities(_cities())
	await process_frame
	_check(view.city_count() == 2, "reapplied snapshot keeps two cities")
	for city_id in view.city_ids():
		_check(
			view.root_for_city(int(city_id)).get_instance_id() == ids_before[city_id],
			"city %d root identity preserved on reapply" % int(city_id)
		)

	# Snapshot-first then anchors.
	var view2 = WorldCitiesViewScript.new()
	root.add_child(view2)
	view2.apply_snapshot_cities(_cities())
	_check(view2.city_count() == 0, "cities alone render nothing (anchors not yet available)")
	view2.set_tile_anchors(ANCHORS)
	_check(view2.city_count() == 2, "anchors arriving second inject both cities")

	# Removal when a city disappears from the authoritative snapshot.
	view.apply_snapshot_cities([_cities()[0]])
	await process_frame
	_check(view.city_count() == 1, "missing city is removed")
	_check(view.city_ids() == [1], "only Capital remains")
	_check(view.root_for_city(2) == null, "Settlement 2 root freed")

	# Missing anchor is a contract violation — city skipped, others render.
	var view3 = WorldCitiesViewScript.new()
	root.add_child(view3)
	view3.set_tile_anchors({Vector2i(1, 1): Vector3(0, 1, 0)})
	view3.apply_snapshot_cities(_cities())
	_check(view3.city_count() == 1, "city without anchor is skipped")
	_check(view3.city_ids() == [1], "only anchored city renders")

	_finish()


func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % msg)
	else:
		_any_fail = true
		print("FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _finish() -> void:
	if _any_fail:
		print("test_world_cities_view: FAILED (%d checks)" % _total)
		quit(1)
	print("test_world_cities_view: OK (%d checks)" % _total)
	quit(0)
