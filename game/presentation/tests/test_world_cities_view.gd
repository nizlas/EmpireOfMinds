# Headless: godot --headless --path game -s res://presentation/tests/test_world_cities_view.gd
#
# N8a world-city projection: WorldCitiesView reconciles one stable Node3D
# root per snapshot city, LayoutRoot yaw + offset MainBuildingSlot, AABB
# bottom + foundation embed on MainBuilding, entrance facing city center.
extends SceneTree

const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldCityVisualCatalogScript = preload("res://presentation/world/world_city_visual_catalog.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")

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

	_check(
		WorldCityVisualCatalogScript.MAIN_BUILDING_SCENE_PATH.ends_with(
			"ancient_era_city_main_building.glb"
		),
		"production catalog path ends with ancient_era_city_main_building.glb"
	)
	_check(
		not WorldCityVisualCatalogScript.main_building_scene_path().is_empty(),
		"main building scene resolves via catalog"
	)
	var legacy_path: String = Warrior3DExperimentScript.city_scene_path()
	_check(
		legacy_path.ends_with("ancient_village.glb"),
		"legacy city_scene_path still points at ancient_village.glb"
	)

	_check(
		is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SCALE, 0.35 * 0.8),
		"main-building scale is exactly 0.8 × previous 0.35"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SCALE, 0.28),
		"main-building MAIN_BUILDING_SCALE is 0.28"
	)
	_check(
		is_equal_approx(WorldUnitsViewScript.MODEL_ROOT_SCALE, 0.30),
		"warrior MODEL_ROOT_SCALE is exactly 0.30"
	)

	var slot_local := WorldCitiesViewScript.main_building_slot_local_offset()
	_check(
		is_equal_approx(slot_local.x, HexWorldProjectionScript.S * 0.40),
		"MainBuildingSlot offset is exactly 0.40 × hex radius S"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SLOT_OFFSET_FRAC, 0.40),
		"MAIN_BUILDING_SLOT_OFFSET_FRAC is exactly 0.40"
	)
	_check(
		is_equal_approx(slot_local.z, 0.0) and is_equal_approx(slot_local.y, 0.0),
		"MainBuildingSlot base offset is on +X in layout space"
	)

	_check(
		is_equal_approx(WorldCitiesViewScript.deterministic_city_yaw_rad(1), deg_to_rad(0.0)),
		"city id 1 yaw is 0°"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.deterministic_city_yaw_rad(2), deg_to_rad(60.0)),
		"city id 2 yaw is 60°"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.deterministic_city_yaw_rad(3), deg_to_rad(120.0)),
		"city id 3 yaw is 120°"
	)

	var empty_holder := Node3D.new()
	root.add_child(empty_holder)
	_check(
		WorldCitiesViewScript.aggregate_mesh_aabb_local(empty_holder)["ok"] == false,
		"aggregate AABB fails closed with no MeshInstance3D"
	)
	empty_holder.queue_free()

	# Fake surface sampler: returns a raised height at offset samples.
	var fake_sampler := _FakeSurfaceSampler.new()
	fake_sampler.raise_by = 0.35

	var view = WorldCitiesViewScript.new()
	root.add_child(view)
	view.set_surface_sampler(fake_sampler)
	view.set_tile_anchors(ANCHORS)
	_check(view.city_count() == 0, "anchors alone render nothing")
	view.apply_snapshot_cities(_cities())
	_check(view.city_count() == 2, "both snapshot cities instantiate")

	var expected_building_y := NAN
	for row in _cities():
		var city_id: int = int(row["id"])
		var node = view.root_for_city(city_id)
		_check(node != null, "city %d has a root" % city_id)
		if node == null:
			continue
		var key := Vector2i(int(row["position"][0]), int(row["position"][1]))
		var anchor: Vector3 = ANCHORS[key]
		_check(node.position == anchor, "city %d root sits exactly at its tile anchor" % city_id)
		_check(node.rotation == Vector3.ZERO, "city %d root stays upright (no pitch/roll)" % city_id)

		var layout: Node3D = view.layout_root_for_city(city_id)
		_check(layout != null, "city %d has LayoutRoot" % city_id)
		var city_yaw := WorldCitiesViewScript.deterministic_city_yaw_rad(city_id)
		if layout != null:
			_check(
				is_equal_approx(layout.rotation.y, city_yaw),
				"city %d LayoutRoot uses deterministic hex yaw" % city_id
			)
			_check(
				is_equal_approx(layout.rotation.x, 0.0) and is_equal_approx(layout.rotation.z, 0.0),
				"city %d LayoutRoot has no pitch/roll" % city_id
			)

		var slot: Node3D = view.main_building_slot_for_city(city_id)
		_check(slot != null, "city %d has MainBuildingSlot" % city_id)
		if slot != null:
			_check(
				is_equal_approx(slot.position.x, slot_local.x)
				and is_equal_approx(slot.position.z, slot_local.z),
				"city %d MainBuildingSlot keeps layout-local XZ offset" % city_id
			)
			_check(
				not is_equal_approx(slot.position.x, 0.0) or not is_equal_approx(slot.position.z, 0.0),
				"city %d main building is offset from tile center" % city_id
			)
			_check(
				is_equal_approx(slot.position.y, fake_sampler.raise_by),
				"city %d slot Y uses surface height at offset (not center pin alone)" % city_id
			)
			var world_slot_xz: Vector3 = anchor + Vector3(slot.position.x, 0.0, slot.position.z).rotated(
				Vector3.UP, city_yaw
			)
			_check(
				world_slot_xz.distance_to(anchor) > 0.1,
				"city %d offset rotates with LayoutRoot yaw into distinct world XZ" % city_id
			)

		var main_building: Node3D = view.main_building_for_city(city_id)
		_check(main_building != null, "city %d has MainBuilding" % city_id)
		if main_building != null:
			_check(
				main_building.scale == Vector3.ONE * WorldCitiesViewScript.MAIN_BUILDING_SCALE,
				"city %d MainBuilding uses MAIN_BUILDING_SCALE" % city_id
			)
			_check(
				WorldCitiesViewScript.MAIN_BUILDING_ENTRANCE_LOCAL == Vector3(0.0, 0.0, 1.0),
				"city %d authored entrance axis is +Z" % city_id
			)
			_check(
				is_equal_approx(
					main_building.rotation.y, WorldCitiesViewScript.main_building_facing_center_yaw_rad()
				),
				"city %d MainBuilding uses shared facing-center yaw" % city_id
			)
			_check(
				is_equal_approx(main_building.rotation.x, 0.0)
				and is_equal_approx(main_building.rotation.z, 0.0),
				"city %d MainBuilding has no pitch/roll" % city_id
			)
			_check(
				is_equal_approx(layout.rotation.y, city_yaw),
				"city %d LayoutRoot yaw unchanged by asset facing correction" % city_id
			)
			# Geometric: composed entrance world-XZ must aim at city center.
			node.force_update_transform()
			main_building.force_update_transform()
			var to_center := anchor - main_building.global_position
			to_center.y = 0.0
			_check(to_center.length_squared() > 1e-8, "city %d building is offset from center" % city_id)
			to_center = to_center.normalized()
			var entrance := WorldCitiesViewScript.entrance_facing_world_xz(main_building)
			_check(
				entrance.distance_to(to_center) < 1e-4,
				"city %d entrance world-XZ aims at city center (geom)" % city_id
			)
			var bounds: Dictionary = WorldCitiesViewScript.aggregate_mesh_aabb_local(main_building)
			_check(bounds["ok"] == true, "city %d MainBuilding has aggregate mesh AABB" % city_id)
			if bounds["ok"]:
				var aabb: AABB = bounds["aabb"]
				var expect_y := WorldCitiesViewScript.main_building_local_y(
					aabb.position.y,
					WorldCitiesViewScript.MAIN_BUILDING_SCALE,
					WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
				)
				_check(
					is_equal_approx(main_building.position.y, expect_y),
					"city %d MainBuilding Y is AABB-bottom + single foundation embed" % city_id
				)
				var bottom_on_slot := (
					main_building.position.y + WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
				)
				_check(
					is_equal_approx(
						bottom_on_slot, -(aabb.position.y * WorldCitiesViewScript.MAIN_BUILDING_SCALE)
					),
					"city %d scaled AABB bottom aligns to slot ground before embed" % city_id
				)
				if is_nan(expected_building_y):
					expected_building_y = main_building.position.y
				else:
					_check(
						is_equal_approx(main_building.position.y, expected_building_y),
						"city %d yaw does not change MainBuilding local Y" % city_id
					)

	# Different yaws displace the slot differently in world XZ; city roots stay at anchors.
	var root1: Node3D = view.root_for_city(1)
	var root2: Node3D = view.root_for_city(2)
	var slot1: Node3D = view.main_building_slot_for_city(1)
	var slot2: Node3D = view.main_building_slot_for_city(2)
	_check(root1 != null and root2 != null and slot1 != null and slot2 != null, "roots/slots exist")
	if root1 != null and root2 != null and slot1 != null and slot2 != null:
		var w1: Vector3 = root1.position + Vector3(slot1.position.x, 0.0, slot1.position.z).rotated(
			Vector3.UP, view.layout_root_for_city(1).rotation.y
		)
		var w2: Vector3 = root2.position + Vector3(slot2.position.x, 0.0, slot2.position.z).rotated(
			Vector3.UP, view.layout_root_for_city(2).rotation.y
		)
		_check(w1.distance_to(w2) > 0.5, "offset slots land at distinct world positions under yaw")
		_check(root1.position == ANCHORS[Vector2i(1, 1)], "city 1 root remains at center pin")
		_check(root2.position == ANCHORS[Vector2i(3, 1)], "city 2 root remains at center pin")

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

	var view2 = WorldCitiesViewScript.new()
	root.add_child(view2)
	view2.apply_snapshot_cities(_cities())
	_check(view2.city_count() == 0, "cities alone render nothing (anchors not yet available)")
	view2.set_tile_anchors(ANCHORS)
	_check(view2.city_count() == 2, "anchors arriving second inject both cities")

	view.apply_snapshot_cities([_cities()[0]])
	await process_frame
	_check(view.city_count() == 1, "missing city is removed")
	_check(view.root_for_city(2) == null, "Settlement 2 root freed")

	var view3 = WorldCitiesViewScript.new()
	root.add_child(view3)
	view3.set_tile_anchors({Vector2i(1, 1): Vector3(0, 1, 0)})
	view3.apply_snapshot_cities(_cities())
	_check(view3.city_count() == 1, "city without anchor is skipped")

	_finish()


class _FakeSurfaceSampler:
	var raise_by := 0.0

	func sample(_x: float, _z: float, y_hint: float) -> Dictionary:
		return {"ok": true, "height": y_hint + raise_by, "normal": Vector3.UP}


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
