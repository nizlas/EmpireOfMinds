# Headless: godot --headless --path game -s res://presentation/tests/test_city_building_composition.gd
#
# CP1 city-building composition: places caller-supplied PackedScene parts from
# deterministic slot data using an injected WorldSurfaceSampler-shaped fake.
# Covers rotated offsets, sampled heights, foundation sink, yaw-only upright
# transforms, uniform scale, stable identity on reapply, scene replacement,
# transform updates, stale-slot removal, and malformed / sample rejection.
extends SceneTree

const CityBuildingCompositionScript = preload("res://presentation/world/city_building_composition.gd")

const CITY_ANCHOR := Vector3(10.0, 2.0, -4.0)
const CITY_YAW := PI * 0.5
# Literal world XZ for CITY_YAW = +90° under Godot's Y-up right-hand rule:
# (x', z') = (local_z, -local_x).
# local (2, 0) -> (10, -6); local (0, 3) -> (13, -4); local (1, 1) -> (11, -5).
const HALL_WORLD_X := 10.0
const HALL_WORLD_Z := -6.0
const SHED_WORLD_X := 13.0
const SHED_WORLD_Z := -4.0
const MISS_WORLD_X := 11.0
const MISS_WORLD_Z := -5.0
const EPS := 1e-4

var _total := 0
var _any_fail := false


class HeightMapSampler:
	extends RefCounted
	var heights: Dictionary = {}
	var miss_keys: Dictionary = {}
	var overrides: Dictionary = {}

	func set_height(x: float, z: float, height: float) -> void:
		heights[_key(x, z)] = height

	func set_miss(x: float, z: float) -> void:
		miss_keys[_key(x, z)] = true

	func set_override(x: float, z: float, sample: Dictionary) -> void:
		overrides[_key(x, z)] = sample

	func sample(x: float, z: float, y_hint: float) -> Dictionary:
		var k := _key(x, z)
		if overrides.has(k):
			return overrides[k]
		if miss_keys.has(k):
			return {"ok": false, "height": y_hint, "normal": Vector3.UP}
		if heights.has(k):
			return {"ok": true, "height": float(heights[k]), "normal": Vector3(0.2, 1.0, -0.1).normalized()}
		return {"ok": false, "height": y_hint, "normal": Vector3.UP}

	func _key(x: float, z: float) -> String:
		return "%.5f|%.5f" % [x, z]


func _dummy_scene(part_name: String = "DummyBuilding") -> PackedScene:
	var root := Node3D.new()
	root.name = part_name
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	_check(err == OK, "dummy PackedScene packs (%s)" % part_name)
	return packed


func _slot(
	slot_id,
	local_x,
	local_z,
	yaw,
	scale,
	foundation_sink,
	scene
) -> Dictionary:
	return {
		"slot_id": slot_id,
		"local_x": local_x,
		"local_z": local_z,
		"yaw": yaw,
		"scale": scale,
		"foundation_sink": foundation_sink,
		"scene": scene,
	}


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	var scene_a := _dummy_scene("HallScene")
	var scene_b := _dummy_scene("ShedScene")
	var scene_c := _dummy_scene("HallSceneV2")
	var sampler := HeightMapSampler.new()
	sampler.set_height(HALL_WORLD_X, HALL_WORLD_Z, 5.5)
	sampler.set_height(SHED_WORLD_X, SHED_WORLD_Z, 1.25)

	var composition = CityBuildingCompositionScript.new()
	root.add_child(composition)
	_check(not composition.has_surface_sampler(), "sampler starts unset")
	composition.set_surface_sampler(sampler)
	_check(composition.has_surface_sampler(), "sampler injects")

	var slot_yaw_a := deg_to_rad(15.0)
	var slot_yaw_b := deg_to_rad(-40.0)
	var sink_a := 0.35
	var sink_b := 0.0
	var scale_a := 1.5
	var scale_b := 0.75
	var slots := [
		_slot("hall", 2.0, 0.0, slot_yaw_a, scale_a, sink_a, scene_a),
		_slot("shed", 0.0, 3.0, slot_yaw_b, scale_b, sink_b, scene_b),
	]
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, slots)
	_check(composition.part_count() == 2, "both valid slots instantiate")
	_check(composition.slot_ids() == ["hall", "shed"], "slot ids are exact and sorted")

	var hall: Node3D = composition.root_for_slot("hall")
	var shed: Node3D = composition.root_for_slot("shed")
	_check(hall != null and shed != null, "both slot roots exist")
	if hall != null:
		_check(_near(hall.position.x, HALL_WORLD_X), "hall X is literal 90-degree rotated offset")
		_check(_near(hall.position.z, HALL_WORLD_Z), "hall Z is literal 90-degree rotated offset")
		_check(_near(hall.position.y, 5.5 - sink_a), "hall Y is sampled height minus foundation sink")
		_check(_near(hall.rotation.x, 0.0), "hall pitch stays zero (upright)")
		_check(_near(hall.rotation.z, 0.0), "hall roll stays zero (upright)")
		_check(_near(hall.rotation.y, CITY_YAW + slot_yaw_a), "hall yaw is city yaw + slot yaw")
		_check(hall.scale.is_equal_approx(Vector3.ONE * scale_a), "hall uniform scale applied")
		_check(hall.name == "BuildingSlot_hall", "hall root name is slot-keyed")
	if shed != null:
		_check(_near(shed.position.x, SHED_WORLD_X), "shed X is literal 90-degree rotated offset")
		_check(_near(shed.position.z, SHED_WORLD_Z), "shed Z is literal 90-degree rotated offset")
		_check(_near(shed.position.y, 1.25 - sink_b), "shed Y uses a different sampled height")
		_check(_near(shed.rotation.x, 0.0) and _near(shed.rotation.z, 0.0), "shed stays upright")
		_check(_near(shed.rotation.y, CITY_YAW + slot_yaw_b), "shed yaw is city yaw + slot yaw")
		_check(shed.scale.is_equal_approx(Vector3.ONE * scale_b), "shed uniform scale applied")

	# Same-scene identity preservation on identical reapply.
	var id_hall := hall.get_instance_id()
	var id_shed := shed.get_instance_id()
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, slots)
	await process_frame
	_check(composition.part_count() == 2, "reapply keeps two parts")
	_check(
		composition.root_for_slot("hall").get_instance_id() == id_hall,
		"hall root identity preserved for same PackedScene"
	)
	_check(
		composition.root_for_slot("shed").get_instance_id() == id_shed,
		"shed root identity preserved for same PackedScene"
	)

	# Changed transforms update the existing same-scene root.
	var moved_slots := [
		_slot("hall", 2.0, 0.0, deg_to_rad(30.0), 2.0, 0.1, scene_a),
		_slot("shed", 0.0, 3.0, slot_yaw_b, scale_b, sink_b, scene_b),
	]
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, moved_slots)
	await process_frame
	hall = composition.root_for_slot("hall")
	_check(hall.get_instance_id() == id_hall, "hall identity preserved across transform update")
	_check(_near(hall.position.y, 5.5 - 0.1), "hall Y updates with new foundation sink")
	_check(_near(hall.rotation.y, CITY_YAW + deg_to_rad(30.0)), "hall yaw updates in place")
	_check(hall.scale.is_equal_approx(Vector3.ONE * 2.0), "hall scale updates in place")
	_check(
		composition.root_for_slot("shed").get_instance_id() == id_shed,
		"shed identity retained while hall transforms update"
	)

	# Changed PackedScene replaces that slot root; other slots keep identity.
	var replaced_slots := [
		_slot("hall", 2.0, 0.0, deg_to_rad(30.0), 2.0, 0.1, scene_c),
		_slot("shed", 0.0, 3.0, slot_yaw_b, scale_b, sink_b, scene_b),
	]
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, replaced_slots)
	await process_frame
	hall = composition.root_for_slot("hall")
	_check(hall != null, "hall root exists after scene change")
	_check(hall.get_instance_id() != id_hall, "hall root replaced when PackedScene changes")
	_check(hall.name == "BuildingSlot_hall", "replaced hall keeps slot-keyed name")
	_check(
		composition.root_for_slot("shed").get_instance_id() == id_shed,
		"shed identity retained across hall scene replacement"
	)
	id_hall = hall.get_instance_id()

	# Stale-slot removal.
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, [replaced_slots[0]])
	await process_frame
	_check(composition.part_count() == 1, "missing slot is removed")
	_check(composition.slot_ids() == ["hall"], "only hall remains")
	_check(composition.root_for_slot("shed") == null, "shed root freed")
	_check(
		composition.root_for_slot("hall").get_instance_id() == id_hall,
		"hall identity survives stale removal of shed"
	)

	# Malformed slot rejection (and no origin guess / no placement).
	var bad = CityBuildingCompositionScript.new()
	root.add_child(bad)
	bad.set_surface_sampler(sampler)
	bad.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[
			{"slot_id": "broken"},
			_slot("", 1.0, 0.0, 0.0, 1.0, 0.0, scene_a),
			_slot(1, 1.0, 0.0, 0.0, 1.0, 0.0, scene_a),
			_slot("neg_scale", 1.0, 0.0, 0.0, -1.0, 0.0, scene_a),
			_slot("neg_sink", 1.0, 0.0, 0.0, 1.0, -0.25, scene_a),
			_slot("inf_x", INF, 0.0, 0.0, 1.0, 0.0, scene_a),
			_slot("nan_yaw", 1.0, 0.0, NAN, 1.0, 0.0, scene_a),
			_slot("no_scene", 1.0, 0.0, 0.0, 1.0, 0.0, null),
			"not-a-dict",
		]
	)
	_check(bad.part_count() == 0, "malformed slots produce no parts")

	# Missing sampler: fail visibly, skip all parts.
	var no_samp = CityBuildingCompositionScript.new()
	root.add_child(no_samp)
	no_samp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[_slot("hall", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a)]
	)
	_check(no_samp.part_count() == 0, "missing sampler skips placement")

	# Sample miss: skip that part; valid neighbors still place.
	sampler.set_miss(MISS_WORLD_X, MISS_WORLD_Z)
	var miss_comp = CityBuildingCompositionScript.new()
	root.add_child(miss_comp)
	miss_comp.set_surface_sampler(sampler)
	miss_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[
			_slot("ok", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a),
			_slot("miss", 1.0, 1.0, 0.0, 1.0, 0.0, scene_b),
		]
	)
	_check(miss_comp.part_count() == 1, "sample miss skips only the failed slot")
	_check(miss_comp.slot_ids() == ["ok"], "only the successful sample remains")
	_check(miss_comp.root_for_slot("miss") == null, "missed slot has no root")

	# ok sample with missing / non-numeric / non-finite height never falls back.
	var height_comp = CityBuildingCompositionScript.new()
	root.add_child(height_comp)
	height_comp.set_surface_sampler(sampler)
	sampler.set_override(HALL_WORLD_X, HALL_WORLD_Z, {"ok": true, "normal": Vector3.UP})
	height_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[_slot("missing_h", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a)]
	)
	_check(height_comp.part_count() == 0, "missing ok-sample height skips placement")
	_check(height_comp.root_for_slot("missing_h") == null, "missing height never places at anchor.y")

	sampler.set_override(
		HALL_WORLD_X, HALL_WORLD_Z, {"ok": true, "height": "2.0", "normal": Vector3.UP}
	)
	height_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[_slot("str_h", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a)]
	)
	_check(height_comp.part_count() == 0, "non-numeric ok-sample height skips placement")

	sampler.set_override(
		HALL_WORLD_X, HALL_WORLD_Z, {"ok": true, "height": INF, "normal": Vector3.UP}
	)
	height_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[_slot("inf_h", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a)]
	)
	_check(height_comp.part_count() == 0, "non-finite ok-sample height skips placement")

	# Restore a valid height and confirm placement still works after rejections.
	sampler.set_height(HALL_WORLD_X, HALL_WORLD_Z, 5.5)
	sampler.overrides.erase("%.5f|%.5f" % [HALL_WORLD_X, HALL_WORLD_Z])
	height_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[_slot("ok_h", 2.0, 0.0, 0.0, 1.0, 0.0, scene_a)]
	)
	_check(height_comp.part_count() == 1, "valid sample height places after prior rejections")
	_check(
		_near(height_comp.root_for_slot("ok_h").position.y, 5.5),
		"valid placement uses sampled height, not city_anchor.y"
	)

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
		print("test_city_building_composition: FAILED (%d checks)" % _total)
		quit(1)
		return
	print("test_city_building_composition: OK (%d checks)" % _total)
	quit(0)
