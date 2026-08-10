# Headless visual/scale probe for WorldMap city presentation.
# godot --headless --path game -s res://presentation/tests/probe_world_city_scale.gd
#
# Measures the imported Ancient Era main-building AABB, compares it with hex
# spacing and unit scale, then composes one city + one Settler on the same tile
# under a normal strategic camera. Asserts MAIN_BUILDING_SCALE footprint is a
# modular fraction of one hex (not a whole-village marker) and that the legacy
# ancient_village path remains registered for the frozen HexMap renderer.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")
const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldCityVisualCatalogScript = preload("res://presentation/world/world_city_visual_catalog.gd")

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


func _instantiate_scaled(path: String, scale: float, yaw: float = 0.0, embed_y: float = 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	_check(packed != null, "load(%s) returns PackedScene" % path)
	if packed == null:
		return null
	var root := Node3D.new()
	get_root().add_child(root)
	var holder := Node3D.new()
	holder.name = "MainBuilding"
	holder.scale = Vector3.ONE * scale
	holder.rotation = Vector3(0.0, yaw, 0.0)
	holder.position = Vector3(0.0, embed_y, 0.0)
	root.add_child(holder)
	var instance := packed.instantiate()
	holder.add_child(instance)
	root.force_update_transform()
	holder.force_update_transform()
	return root


func _run() -> void:
	await process_frame

	var main_path: String = WorldCityVisualCatalogScript.main_building_scene_path()
	var village_path: String = Experiment.city_scene_path()
	var settler_path: String = Experiment.animated_scene_path_for_type("settler")
	_check(not main_path.is_empty(), "production main building path resolves")
	_check(
		main_path.ends_with("ancient_era_city_main_building.glb"),
		"production path is ancient_era_city_main_building.glb"
	)
	_check(not village_path.is_empty(), "legacy ancient_village path still registered")
	_check(
		village_path.ends_with("ancient_village.glb"),
		"legacy city_scene_path still points at ancient_village.glb"
	)
	_check(not settler_path.is_empty(), "settler path registered")

	var s := HexWorldProjectionScript.S
	var flat_to_flat := s * HexWorldProjectionScript.SQRT3
	var inradius := flat_to_flat * 0.5
	print(
		"hex S=%.3f flat_to_flat=%.3f inradius=%.3f"
		% [s, flat_to_flat, inradius]
	)

	var main_raw := _instantiate_scaled(main_path, 1.0)
	var main_raw_aabb := _aabb_of(main_raw)
	print(
		"main_building imported AABB position=%s size=%s diameter_xz=%.3f height=%.3f min.y=%.3f"
		% [
			main_raw_aabb.position,
			main_raw_aabb.size,
			maxf(main_raw_aabb.size.x, main_raw_aabb.size.z),
			main_raw_aabb.size.y,
			main_raw_aabb.position.y,
		]
	)
	_check(main_raw_aabb.size.x > 0.5, "main building authored X extent is metre-scale (~1)")
	_check(main_raw_aabb.size.y > 0.5, "main building authored height is metre-scale (~1)")
	_check(main_raw_aabb.position.y < -0.2, "main building foundation extends below pivot")
	main_raw.queue_free()

	_check(
		not is_equal_approx(
			WorldCitiesViewScript.MAIN_BUILDING_SCALE, WorldUnitsViewScript.MODEL_ROOT_SCALE
		),
		"city scale must not equal unit scale"
	)
	_check(
		not is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SCALE, 5.0),
		"city scale must not reuse old village scale 5.0"
	)

	var city_scale: float = WorldCitiesViewScript.MAIN_BUILDING_SCALE
	var embed_depth: float = WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
	var bottom_y := WorldCitiesViewScript.main_building_local_y(
		main_raw_aabb.position.y, city_scale, embed_depth
	)
	var main_city := _instantiate_scaled(main_path, city_scale, 0.0, bottom_y)
	var true_diameter := maxf(main_raw_aabb.size.x, main_raw_aabb.size.z) * city_scale
	var true_height := main_raw_aabb.size.y * city_scale
	var frac_flat := true_diameter / flat_to_flat
	print(
		"city scale=%s foundation_embed_depth=%.3f local_y=%.3f world_footprint_diameter=%.3f height=%.3f frac_of_flat_to_flat=%.3f"
		% [city_scale, embed_depth, bottom_y, true_diameter, true_height, frac_flat]
	)
	# Modular main building: readable, but leaves room for future city assets.
	_check(frac_flat >= 0.20, "main building footprint is readable (>=20%% of flat-to-flat)")
	_check(frac_flat <= 0.50, "main building does not fill the hex like a village marker (<=50%%)")
	_check(
		is_equal_approx(city_scale, 0.35 * 0.8),
		"main building scale is exactly 0.8 × the prior 0.35 contract"
	)
	_check(
		is_equal_approx(WorldUnitsViewScript.MODEL_ROOT_SCALE, 0.30),
		"unit MODEL_ROOT_SCALE is exactly 0.30"
	)
	_check(true_diameter * 0.5 <= inradius + 0.01, "main building half-extent stays inside hex inradius")
	main_city.queue_free()

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
		_check(city_root.rotation == Vector3.ZERO, "composed city root stays upright")
		var main_building: Node3D = cities.main_building_for_city(1)
		_check(main_building != null, "composed city has MainBuilding")
		if main_building != null:
			_check(
				main_building.scale == Vector3.ONE * city_scale,
				"composed city MainBuilding uses MAIN_BUILDING_SCALE"
			)
			var layout: Node3D = cities.layout_root_for_city(1)
			_check(layout != null, "composed city has LayoutRoot")
			if layout != null:
				_check(
					is_equal_approx(layout.rotation.y, WorldCitiesViewScript.deterministic_city_yaw_rad(1)),
					"composed city LayoutRoot uses deterministic yaw"
				)
			var slot: Node3D = cities.main_building_slot_for_city(1)
			_check(slot != null, "composed city has MainBuildingSlot")
			if slot != null:
				_check(
					slot.position.x != 0.0 or slot.position.z != 0.0,
					"composed MainBuildingSlot is offset from center"
				)
			_check(
				is_equal_approx(
					main_building.rotation.y, WorldCitiesViewScript.main_building_facing_center_yaw_rad()
				),
				"composed MainBuilding uses shared facing-center yaw"
			)
			city_root.force_update_transform()
			main_building.force_update_transform()
			var to_center := city_root.global_position - main_building.global_position
			to_center.y = 0.0
			to_center = to_center.normalized()
			var entrance := WorldCitiesViewScript.entrance_facing_world_xz(main_building)
			_check(
				entrance.distance_to(to_center) < 1e-4,
				"composed entrance world-XZ aims at city center"
			)
		print("composed shared-tile city aabb size=%s" % _aabb_of(city_root).size)
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
