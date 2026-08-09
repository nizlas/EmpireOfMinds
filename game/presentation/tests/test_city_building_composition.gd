# Headless: godot --headless --path game -s res://presentation/tests/test_city_building_composition.gd
#
# CP1 city-building composition: places caller-supplied PackedScene parts from
# deterministic slot data using an injected WorldSurfaceSampler-shaped fake.
# Covers rotated offsets, sampled heights, foundation sink, yaw-only upright
# transforms, uniform scale, stable identity on reapply, stale-slot removal,
# and malformed / sample-miss rejection.
extends SceneTree

const CityBuildingCompositionScript = preload("res://presentation/world/city_building_composition.gd")

const CITY_ANCHOR := Vector3(10.0, 2.0, -4.0)
const CITY_YAW := PI * 0.5
const EPS := 1e-4

var _total := 0
var _any_fail := false


class HeightMapSampler:
	extends RefCounted
	var heights: Dictionary = {}
	var miss_keys: Dictionary = {}

	func set_height(x: float, z: float, height: float) -> void:
		heights[_key(x, z)] = height

	func set_miss(x: float, z: float) -> void:
		miss_keys[_key(x, z)] = true

	func sample(x: float, z: float, y_hint: float) -> Dictionary:
		var k := _key(x, z)
		if miss_keys.has(k):
			return {"ok": false, "height": y_hint, "normal": Vector3.UP}
		if heights.has(k):
			return {"ok": true, "height": float(heights[k]), "normal": Vector3(0.2, 1.0, -0.1).normalized()}
		return {"ok": false, "height": y_hint, "normal": Vector3.UP}

	func _key(x: float, z: float) -> String:
		return "%.5f|%.5f" % [x, z]


func _dummy_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "DummyBuilding"
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	_check(err == OK, "dummy PackedScene packs")
	return packed


func _slot(
	slot_id: String,
	local_x: float,
	local_z: float,
	yaw: float,
	scale: float,
	foundation_sink: float,
	scene: PackedScene
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


func _rotated_world(local_x: float, local_z: float) -> Vector3:
	return CITY_ANCHOR + Vector3(local_x, 0.0, local_z).rotated(Vector3.UP, CITY_YAW)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	var scene_a := _dummy_scene()
	var scene_b := _dummy_scene()
	var sampler := HeightMapSampler.new()

	var local_a := Vector2(2.0, 0.0)
	var local_b := Vector2(0.0, 3.0)
	var world_a := _rotated_world(local_a.x, local_a.y)
	var world_b := _rotated_world(local_b.x, local_b.y)
	sampler.set_height(world_a.x, world_a.z, 5.5)
	sampler.set_height(world_b.x, world_b.z, 1.25)

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
		_slot("hall", local_a.x, local_a.y, slot_yaw_a, scale_a, sink_a, scene_a),
		_slot("shed", local_b.x, local_b.y, slot_yaw_b, scale_b, sink_b, scene_b),
	]
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, slots)
	_check(composition.part_count() == 2, "both valid slots instantiate")
	_check(composition.slot_ids() == ["hall", "shed"], "slot ids are exact and sorted")

	var hall: Node3D = composition.root_for_slot("hall")
	var shed: Node3D = composition.root_for_slot("shed")
	_check(hall != null and shed != null, "both slot roots exist")
	if hall != null:
		_check(_near(hall.position.x, world_a.x), "hall X uses city-yaw-rotated local offset")
		_check(_near(hall.position.z, world_a.z), "hall Z uses city-yaw-rotated local offset")
		_check(_near(hall.position.y, 5.5 - sink_a), "hall Y is sampled height minus foundation sink")
		_check(_near(hall.rotation.x, 0.0), "hall pitch stays zero (upright)")
		_check(_near(hall.rotation.z, 0.0), "hall roll stays zero (upright)")
		_check(_near(hall.rotation.y, CITY_YAW + slot_yaw_a), "hall yaw is city yaw + slot yaw")
		_check(hall.scale.is_equal_approx(Vector3.ONE * scale_a), "hall uniform scale applied")
	if shed != null:
		_check(_near(shed.position.x, world_b.x), "shed X uses city-yaw-rotated local offset")
		_check(_near(shed.position.z, world_b.z), "shed Z uses city-yaw-rotated local offset")
		_check(_near(shed.position.y, 1.25 - sink_b), "shed Y uses a different sampled height")
		_check(_near(shed.rotation.x, 0.0) and _near(shed.rotation.z, 0.0), "shed stays upright")
		_check(_near(shed.rotation.y, CITY_YAW + slot_yaw_b), "shed yaw is city yaw + slot yaw")
		_check(shed.scale.is_equal_approx(Vector3.ONE * scale_b), "shed uniform scale applied")

	# Stable identity on identical reapply.
	var id_hall := hall.get_instance_id()
	var id_shed := shed.get_instance_id()
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, slots)
	await process_frame
	_check(composition.part_count() == 2, "reapply keeps two parts")
	_check(
		composition.root_for_slot("hall").get_instance_id() == id_hall,
		"hall root identity preserved on reapply"
	)
	_check(
		composition.root_for_slot("shed").get_instance_id() == id_shed,
		"shed root identity preserved on reapply"
	)

	# Stale-slot removal.
	composition.apply_composition(CITY_ANCHOR, CITY_YAW, [slots[0]])
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
			_slot("neg_scale", 1.0, 0.0, 0.0, -1.0, 0.0, scene_a),
			_slot("no_scene", 1.0, 0.0, 0.0, 1.0, 0.0, null),
			"not-a-dict",
		]
	)
	_check(bad.part_count() == 0, "malformed slots produce no parts")

	# Missing sampler: fail visibly, skip all parts.
	var no_samp = CityBuildingCompositionScript.new()
	root.add_child(no_samp)
	no_samp.apply_composition(CITY_ANCHOR, CITY_YAW, [slots[0]])
	_check(no_samp.part_count() == 0, "missing sampler skips placement")

	# Sample miss: skip that part; valid neighbors still place.
	var miss_world := _rotated_world(1.0, 1.0)
	sampler.set_miss(miss_world.x, miss_world.z)
	var miss_comp = CityBuildingCompositionScript.new()
	root.add_child(miss_comp)
	miss_comp.set_surface_sampler(sampler)
	miss_comp.apply_composition(
		CITY_ANCHOR,
		CITY_YAW,
		[
			_slot("ok", local_a.x, local_a.y, 0.0, 1.0, 0.0, scene_a),
			_slot("miss", 1.0, 1.0, 0.0, 1.0, 0.0, scene_b),
		]
	)
	_check(miss_comp.part_count() == 1, "sample miss skips only the failed slot")
	_check(miss_comp.slot_ids() == ["ok"], "only the successful sample remains")
	_check(miss_comp.root_for_slot("miss") == null, "missed slot has no root")

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
	print("test_city_building_composition: OK (%d checks)" % _total)
	quit(0)
