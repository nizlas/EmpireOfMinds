# Headless visual/scale probe for WorldMap city presentation.
# godot --headless --path game -s res://presentation/tests/probe_world_city_scale.gd
#
# Measures the imported ancient_village AABB, compares it with hex spacing and
# unit scale, then composes one city + one Settler on the same tile under a
# normal strategic camera. Asserts the city-specific CITY_MODEL_ROOT_SCALE
# footprint occupies the center of one hex without claiming neighbors.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")
const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % msg)
	else:
		_any_fail = true
		print("FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _aabb_of(node: Node) -> AABB:
	var first := true
	var out := AABB()
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var local := vi.get_aabb()
			var xf := vi.global_transform
			var corners: Array[Vector3] = [
				xf * local.position,
				xf * (local.position + Vector3(local.size.x, 0, 0)),
				xf * (local.position + Vector3(0, local.size.y, 0)),
				xf * (local.position + Vector3(0, 0, local.size.z)),
				xf * (local.position + Vector3(local.size.x, local.size.y, 0)),
				xf * (local.position + Vector3(local.size.x, 0, local.size.z)),
				xf * (local.position + Vector3(0, local.size.y, local.size.z)),
				xf * (local.position + local.size),
			]
			for c in corners:
				if first:
					out = AABB(c, Vector3.ZERO)
					first = false
				else:
					out = out.expand(c)
		for child in n.get_children():
			stack.append(child)
	return out


func _instantiate_scaled(path: String, scale: float, yaw: float = 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	_check(packed != null, "load(%s) returns PackedScene" % path)
	if packed == null:
		return null
	var root := Node3D.new()
	get_root().add_child(root)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	model_root.scale = Vector3.ONE * scale
	model_root.rotation = Vector3(0.0, yaw, 0.0)
	root.add_child(model_root)
	var instance := packed.instantiate()
	model_root.add_child(instance)
	root.force_update_transform()
	model_root.force_update_transform()
	return root


func _run() -> void:
	await process_frame

	var village_path: String = Experiment.city_scene_path()
	var settler_path: String = Experiment.animated_scene_path_for_type("settler")
	var warrior_path: String = Experiment.animated_scene_path_for_type("warrior")
	_check(not village_path.is_empty(), "ancient_village path registered")
	_check(not settler_path.is_empty(), "settler path registered")
	_check(not warrior_path.is_empty(), "warrior path registered")

	var s := HexWorldProjectionScript.S
	var flat_to_flat := s * HexWorldProjectionScript.SQRT3
	var inradius := flat_to_flat * 0.5
	var corner_diameter := 2.0 * s
	print(
		"hex S=%.3f center_to_neighbor=%.3f flat_to_flat=%.3f inradius=%.3f corner_diameter=%.3f"
		% [s, flat_to_flat, flat_to_flat, inradius, corner_diameter]
	)

	var village_raw := _instantiate_scaled(village_path, 1.0)
	var village_raw_aabb := _aabb_of(village_raw)
	print(
		"village imported AABB size=%s footprint=%.3fx%.3f height=%.3f"
		% [
			village_raw_aabb.size,
			village_raw_aabb.size.x,
			village_raw_aabb.size.z,
			village_raw_aabb.size.y,
		]
	)
	_check(village_raw_aabb.size.x > 0.2, "village authored X footprint is centimetre-scale (~0.29)")
	_check(village_raw_aabb.size.y > 0.05, "village authored height is centimetre-scale (~0.12)")
	village_raw.queue_free()

	var settler_unit := _instantiate_scaled(settler_path, WorldUnitsViewScript.MODEL_ROOT_SCALE)
	var warrior_unit := _instantiate_scaled(warrior_path, WorldUnitsViewScript.MODEL_ROOT_SCALE)
	print(
		"unit MODEL_ROOT_SCALE=%s settler_aabb_size=%s warrior_aabb_size=%s (skinned mesh AABB may under-report; unit Head height ~0.72 at scale 0.5)"
		% [
			WorldUnitsViewScript.MODEL_ROOT_SCALE,
			_aabb_of(settler_unit).size,
			_aabb_of(warrior_unit).size,
		]
	)
	settler_unit.queue_free()
	warrior_unit.queue_free()

	_check(
		WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE != WorldUnitsViewScript.MODEL_ROOT_SCALE,
		"city scale must not equal unit scale"
	)

	var city_scale: float = WorldCitiesViewScript.CITY_MODEL_ROOT_SCALE
	var village_city := _instantiate_scaled(village_path, city_scale, WorldCitiesViewScript.MODEL_YAW_RAD)
	var city_aabb := _aabb_of(village_city)
	# True mesh diameter (pre-yaw AABB) scales linearly from the imported footprint.
	var true_diameter := maxf(village_raw_aabb.size.x, village_raw_aabb.size.z) * city_scale
	var true_height := village_raw_aabb.size.y * city_scale
	var frac_flat := true_diameter / flat_to_flat
	var half_extent := true_diameter * 0.5
	print(
		"city scale=%s world_true_footprint_diameter=%.3f height=%.3f frac_of_flat_to_flat=%.3f half_extent=%.3f inradius=%.3f yawed_aabb_size=%s"
		% [city_scale, true_diameter, true_height, frac_flat, half_extent, inradius, city_aabb.size]
	)
	_check(frac_flat >= 0.55, "city footprint occupies a substantial share of one hex (>=55%% of flat-to-flat)")
	_check(frac_flat <= 0.95, "city footprint stays below claiming-neighbors threshold (<=95%% of flat-to-flat)")
	_check(half_extent <= inradius + 0.01, "city half-extent stays inside hex inradius")
	_check(true_height >= 0.35, "city height is readable in strategic/low-angle view")
	village_city.queue_free()

	# Shared-tile composition: city + settler at the same N4 anchor.
	var scene_root := Node3D.new()
	get_root().add_child(scene_root)
	var cities = WorldCitiesViewScript.new()
	scene_root.add_child(cities)
	var units = WorldUnitsViewScript.new()
	scene_root.add_child(units)
	var anchor := Vector3(0.0, 0.0, 0.0)
	cities.set_tile_anchors({Vector2i(0, 0): anchor})
	cities.apply_snapshot_cities([
		{"id": 1, "owner_id": 0, "position": [0, 0], "name": "Capital"},
	])
	units.set_tile_anchors({Vector2i(0, 0): anchor})
	units.apply_snapshot_units([
		{
			"id": 1,
			"owner_id": 0,
			"position": [0, 0],
			"type_id": "settler",
			"current_hp": 100,
			"has_attacked": false,
		},
	])
	await process_frame
	await process_frame

	var city_root: Node3D = cities.root_for_city(1)
	var unit_root: Node3D = units.root_for_unit(1)
	_check(city_root != null, "composed city root exists")
	_check(unit_root != null, "composed unit root exists on the shared tile")
	if city_root != null:
		_check(city_root.position == anchor, "composed city remains grounded at the N4 anchor")
		var model_root: Node3D = city_root.get_node_or_null("ModelRoot") as Node3D
		_check(model_root != null, "composed city has ModelRoot")
		if model_root != null:
			_check(
				model_root.scale == Vector3.ONE * city_scale,
				"composed city ModelRoot uses CITY_MODEL_ROOT_SCALE"
			)
		var composed_city_aabb := _aabb_of(city_root)
		print("composed shared-tile city aabb size=%s" % composed_city_aabb.size)
	if unit_root != null:
		_check(unit_root.position == anchor, "composed unit shares the same tile anchor")
		print("composed shared-tile unit aabb size=%s" % _aabb_of(unit_root).size)

	var cam := Camera3D.new()
	scene_root.add_child(cam)
	cam.position = Vector3(0.0, 4.5, 4.5)
	cam.look_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)
	cam.current = true
	print(
		"strategic_camera pos=%s looking at shared city/unit tile; city_scale=%s unit_scale=%s"
		% [cam.position, city_scale, WorldUnitsViewScript.MODEL_ROOT_SCALE]
	)

	if _any_fail:
		print("probe_world_city_scale: FAILED (%d checks)" % _total)
		quit(1)
	print("probe_world_city_scale: OK (%d checks)" % _total)
	quit(0)
