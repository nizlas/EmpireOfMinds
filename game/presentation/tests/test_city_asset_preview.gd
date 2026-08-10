# Headless: godot --headless --path game -s res://presentation/tests/test_city_asset_preview.gd
#
# Dev city-asset preview contract (no terrain build): three preview tiles,
# LayoutRoot yaws, offset main buildings, and centered preview-only warriors
# via production WorldUnitsView — never gameplay/server state.
extends SceneTree

const CityAssetPreviewScript = preload("res://dev/city_asset_preview/city_asset_preview.gd")
const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldCityVisualCatalogScript = preload("res://presentation/world/world_city_visual_catalog.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	var expected: Array[Vector2i] = [
		Vector2i(1, 11),
		Vector2i(2, 7),
		Vector2i(3, 6),
	]
	_check(CityAssetPreviewScript.PREVIEW_TILES.size() == 3, "preview harness exposes exactly three tiles")
	for i in range(expected.size()):
		_check(
			CityAssetPreviewScript.PREVIEW_TILES[i] == expected[i],
			"preview tile[%d] is exactly (%d, %d)" % [i, expected[i].x, expected[i].y]
		)

	_check(
		is_equal_approx(float(CityAssetPreviewScript.PREVIEW_YAW_DEG_BY_TILE[Vector2i(1, 11)]), 0.0),
		"preview yaw for (1, 11) is 0°"
	)
	_check(
		is_equal_approx(float(CityAssetPreviewScript.PREVIEW_YAW_DEG_BY_TILE[Vector2i(2, 7)]), 60.0),
		"preview yaw for (2, 7) is 60°"
	)
	_check(
		is_equal_approx(float(CityAssetPreviewScript.PREVIEW_YAW_DEG_BY_TILE[Vector2i(3, 6)]), 120.0),
		"preview yaw for (3, 6) is 120°"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SCALE, 0.35 * 0.8),
		"preview uses production main-building scale (0.8 × prior)"
	)
	_check(
		is_equal_approx(WorldUnitsViewScript.MODEL_ROOT_SCALE, 0.30),
		"preview warriors use production MODEL_ROOT_SCALE 0.30"
	)
	_check(
		is_equal_approx(WorldCitiesViewScript.MAIN_BUILDING_SLOT_OFFSET_FRAC, 0.40),
		"preview building offset frac is exactly 0.40"
	)
	var warrior_path: String = Warrior3DExperimentScript.animated_scene_path_for_type("warrior")
	_check(not warrior_path.is_empty(), "production warrior asset path resolves")
	_check(warrior_path.contains("warrior"), "production warrior asset path is the warrior GLB path")

	# Preview settlement support assets (house/storage are preview-only).
	_check(
		ResourceLoader.exists(WorldCityVisualCatalogScript.MAIN_BUILDING_SCENE_PATH),
		"main building GLB exists for preview cities"
	)
	_check(
		ResourceLoader.exists(CityAssetPreviewScript.HOUSE_BUILDING_SCENE_PATH),
		"house building GLB exists for preview settlement"
	)
	_check(
		ResourceLoader.exists(CityAssetPreviewScript.STORAGE_BUILDING_SCENE_PATH),
		"storage building GLB exists for preview settlement"
	)
	_check(
		load(CityAssetPreviewScript.HOUSE_BUILDING_SCENE_PATH) is PackedScene,
		"house building PackedScene loads"
	)
	_check(
		load(CityAssetPreviewScript.STORAGE_BUILDING_SCENE_PATH) is PackedScene,
		"storage building PackedScene loads"
	)
	var main_off := WorldCitiesViewScript.main_building_slot_local_offset()
	var house_off: Vector3 = CityAssetPreviewScript.HOUSE_SLOT_LOCAL_OFFSET
	var storage_off: Vector3 = CityAssetPreviewScript.STORAGE_SLOT_LOCAL_OFFSET
	_check(
		house_off.distance_to(Vector3.ZERO) > 0.05
		and storage_off.distance_to(Vector3.ZERO) > 0.05
		and main_off.distance_to(Vector3.ZERO) > 0.05,
		"all three settlement offsets leave the hex center clear"
	)
	_check(
		house_off.distance_to(main_off) > 0.2
		and storage_off.distance_to(main_off) > 0.2
		and house_off.distance_to(storage_off) > 0.2,
		"settlement offsets keep buildings separated (no shared slot)"
	)
	_check(
		is_equal_approx(house_off.x, -0.18)
		and is_equal_approx(house_off.z, 0.34),
		"house layout-local offset is exactly (-0.18, 0, 0.34)"
	)
	_check(
		is_equal_approx(storage_off.x, -0.18)
		and is_equal_approx(storage_off.z, -0.34),
		"storage layout-local offset is exactly (-0.18, 0, -0.34)"
	)

	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "canonical handdrawn_test_map_full_01 loads")
	if world_map != null:
		for tile in CityAssetPreviewScript.PREVIEW_TILES:
			_check(
				world_map.has_tile_coord(tile),
				"preview tile (%d, %d) exists on handdrawn_test_map_full_01" % [tile.x, tile.y]
			)

	var anchors := {
		Vector2i(1, 11): Vector3(1.0, 0.5, -1.0),
		Vector2i(2, 7): Vector3(2.0, 1.0, -2.0),
		Vector2i(3, 6): Vector3(3.0, 1.5, -3.0),
	}
	var cities = WorldCitiesViewScript.new()
	root.add_child(cities)
	cities.set_tile_anchors(anchors)
	var units = WorldUnitsViewScript.new()
	root.add_child(units)
	units.set_tile_anchors(anchors)

	var city_rows: Array = []
	var unit_rows: Array = []
	for i in range(CityAssetPreviewScript.PREVIEW_TILES.size()):
		var tile: Vector2i = CityAssetPreviewScript.PREVIEW_TILES[i]
		var city_id := i + 1
		var warrior_id: int = CityAssetPreviewScript.PREVIEW_WARRIOR_IDS[i]
		city_rows.append(
			{
				"id": city_id,
				"owner_id": 0,
				"position": [tile.x, tile.y],
				"name": "Preview Main %d" % city_id,
			}
		)
		unit_rows.append(
			{
				"id": warrior_id,
				"owner_id": 0,
				"position": [tile.x, tile.y],
				"type_id": "warrior",
				"current_hp": 100,
				"has_attacked": false,
			}
		)
	cities.apply_snapshot_cities(city_rows)
	units.apply_snapshot_units(unit_rows)
	_check(cities.city_count() == 3, "three preview cities via production WorldCitiesView")
	_check(units.unit_count() == 3, "three preview warriors via production WorldUnitsView")
	_check(
		CityAssetPreviewScript.attach_preview_settlement_buildings(cities, null, anchors),
		"preview settlement buildings attach under each city LayoutRoot"
	)

	var slot_local := WorldCitiesViewScript.main_building_slot_local_offset()
	for i in range(CityAssetPreviewScript.PREVIEW_TILES.size()):
		var tile: Vector2i = CityAssetPreviewScript.PREVIEW_TILES[i]
		var city_id := i + 1
		var warrior_id: int = CityAssetPreviewScript.PREVIEW_WARRIOR_IDS[i]
		var city_root: Node3D = cities.root_for_city(city_id)
		var warrior_root: Node3D = units.root_for_unit(warrior_id)
		_check(city_root != null, "preview city %d has a root" % city_id)
		_check(warrior_root != null, "preview warrior %d has a root" % warrior_id)
		if city_root == null or warrior_root == null:
			continue
		_check(city_root.position == anchors[tile], "preview city %d root at tile center" % city_id)
		_check(
			warrior_root.position == anchors[tile],
			"preview warrior %d remains exactly at tile center" % warrior_id
		)
		_check(
			city_root.rotation == Vector3.ZERO and warrior_root.rotation == Vector3.ZERO,
			"preview city/warrior roots stay upright at tile %d" % city_id
		)

		var layout: Node3D = cities.layout_root_for_city(city_id)
		var expect_yaw := deg_to_rad(float(CityAssetPreviewScript.PREVIEW_YAW_DEG_BY_TILE[tile]))
		_check(
			layout != null and is_equal_approx(layout.rotation.y, expect_yaw),
			"preview city %d LayoutRoot yaw is exactly %.0f°" % [city_id, float(CityAssetPreviewScript.PREVIEW_YAW_DEG_BY_TILE[tile])]
		)

		var slot: Node3D = cities.main_building_slot_for_city(city_id)
		_check(slot != null, "preview city %d has MainBuildingSlot" % city_id)
		var house_slot: Node3D = CityAssetPreviewScript.preview_house_slot(layout)
		var storage_slot: Node3D = CityAssetPreviewScript.preview_storage_slot(layout)
		var house_building: Node3D = CityAssetPreviewScript.preview_house_building(layout)
		var storage_building: Node3D = CityAssetPreviewScript.preview_storage_building(layout)
		_check(house_slot != null, "preview city %d has PreviewHouseSlot on same hex" % city_id)
		_check(storage_slot != null, "preview city %d has PreviewStorageSlot on same hex" % city_id)
		_check(house_building != null, "preview city %d has HouseBuilding on same hex" % city_id)
		_check(storage_building != null, "preview city %d has StorageBuilding on same hex" % city_id)
		_check(
			house_slot != null and house_slot.get_parent() == layout,
			"preview city %d house slot is parented under LayoutRoot (same hex group)" % city_id
		)
		_check(
			storage_slot != null and storage_slot.get_parent() == layout,
			"preview city %d storage slot is parented under LayoutRoot (same hex group)" % city_id
		)
		if house_slot != null:
			_check(
				is_equal_approx(house_slot.position.x, house_off.x)
				and is_equal_approx(house_slot.position.z, house_off.z),
				"preview city %d house uses settlement local XZ offset" % city_id
			)
		if storage_slot != null:
			_check(
				is_equal_approx(storage_slot.position.x, storage_off.x)
				and is_equal_approx(storage_slot.position.z, storage_off.z),
				"preview city %d storage uses settlement local XZ offset" % city_id
			)
		if slot != null and layout != null:
			_check(
				is_equal_approx(slot.position.x, slot_local.x)
				and is_equal_approx(slot.position.z, slot_local.z),
				"preview city %d main building is offset from center" % city_id
			)
			var world_building_xz: Vector3 = city_root.position + Vector3(
				slot.position.x, 0.0, slot.position.z
			).rotated(Vector3.UP, layout.rotation.y)
			_check(
				world_building_xz.distance_to(warrior_root.position) > 0.1,
				"preview city %d offset main building does not sit on centered warrior" % city_id
			)
			# City yaw must not rotate/displace the warrior (separate unit root).
			_check(
				warrior_root.get_parent() != layout,
				"preview warrior %d is not parented under LayoutRoot" % warrior_id
			)

		var model: Node3D = warrior_root.get_node_or_null("ModelRoot") as Node3D
		_check(model != null, "preview warrior %d uses production ModelRoot" % warrior_id)
		if model != null:
			_check(
				model.scale == Vector3.ONE * WorldUnitsViewScript.MODEL_ROOT_SCALE,
				"preview warrior %d uses shared production MODEL_ROOT_SCALE" % warrior_id
			)

		var main_building: Node3D = cities.main_building_for_city(city_id)
		_check(main_building != null, "preview city %d has MainBuilding" % city_id)
		if main_building != null:
			_check(
				main_building.scale == Vector3.ONE * WorldCitiesViewScript.MAIN_BUILDING_SCALE,
				"preview city %d uses shared production main-building scale" % city_id
			)
			_check(
				is_equal_approx(
					main_building.rotation.y, WorldCitiesViewScript.main_building_facing_center_yaw_rad()
				),
				"preview city %d uses shared production facing-center yaw" % city_id
			)
			_check(
				is_equal_approx(main_building.rotation.x, 0.0)
				and is_equal_approx(main_building.rotation.z, 0.0),
				"preview city %d MainBuilding pitch/roll stay zero" % city_id
			)
			_check(
				slot != null
				and is_equal_approx(slot.position.x, slot_local.x)
				and is_equal_approx(slot.position.z, slot_local.z),
				"preview city %d slot XZ unchanged by facing correction" % city_id
			)
			_check(
				is_equal_approx(main_building.position.x, 0.0)
				and is_equal_approx(main_building.position.z, 0.0),
				"preview city %d MainBuilding stays at slot origin (no compensatory move)" % city_id
			)
			_check(
				is_equal_approx(layout.rotation.y, expect_yaw),
				"preview city %d LayoutRoot yaw unchanged by asset orientation correction" % city_id
			)
			city_root.force_update_transform()
			main_building.force_update_transform()
			var to_center := city_root.global_position - main_building.global_position
			to_center.y = 0.0
			to_center = to_center.normalized()
			var entrance := WorldCitiesViewScript.entrance_facing_world_xz(main_building)
			_check(
				entrance.distance_to(to_center) < 1e-4,
				"preview city %d entrance world-XZ aims at city center / warrior" % city_id
			)

		if house_building != null:
			_check(
				house_building.scale == Vector3.ONE * WorldCitiesViewScript.MAIN_BUILDING_SCALE,
				"preview city %d house uses shared building scale" % city_id
			)
			_check(
				is_equal_approx(
					house_building.rotation.y,
					CityAssetPreviewScript.preview_building_facing_center_yaw_rad(house_off)
				),
				"preview city %d house faces city center" % city_id
			)
		if storage_building != null:
			_check(
				storage_building.scale == Vector3.ONE * WorldCitiesViewScript.MAIN_BUILDING_SCALE,
				"preview city %d storage uses shared building scale" % city_id
			)
			_check(
				is_equal_approx(
					storage_building.rotation.y,
					CityAssetPreviewScript.preview_building_facing_center_yaw_rad(storage_off)
				),
				"preview city %d storage faces city center" % city_id
			)

		# All three building types share one city hex / LayoutRoot — not separate hexes.
		_check(
			main_building != null and house_building != null and storage_building != null,
			"preview city %d group contains main + house + storage on the same hex" % city_id
		)

	# Preview warriors are presentation rows only — applying empty units clears them
	# without implying any domain/server mutation API was used.
	units.apply_snapshot_units([])
	await process_frame
	_check(units.unit_count() == 0, "clearing preview unit rows removes warrior roots (presentation only)")
	_check(cities.city_count() == 3, "clearing warriors does not modify city presentation rows")
	for city_id in [1, 2, 3]:
		var layout_after: Node3D = cities.layout_root_for_city(city_id)
		_check(
			CityAssetPreviewScript.preview_house_building(layout_after) != null
			and CityAssetPreviewScript.preview_storage_building(layout_after) != null,
			"clearing warriors keeps city %d settlement house+storage" % city_id
		)

	# --- Vertical alignment on a sloped preview tile (no terrain build) ---
	# Center-only local AABB*scale placement matches terrain at the slot center,
	# but short house/storage footprints still sink into uphill terrain. The
	# world-space aligner must put each building's lower bound at
	# max(footprint support) - embed.
	var slope_tile := Vector2i(2, 7)
	var slope_anchor: Vector3 = anchors[slope_tile]
	var slope_sampler := PreviewSlopeSampler.new(
		slope_anchor, Vector2(0.45, 0.35)
	)
	var slope_cities = WorldCitiesViewScript.new()
	root.add_child(slope_cities)
	slope_cities.set_tile_anchors({slope_tile: slope_anchor})
	slope_cities.apply_snapshot_cities(
		[{"id": 2, "owner_id": 0, "position": [slope_tile.x, slope_tile.y], "name": "Slope Preview"}]
	)
	_check(
		CityAssetPreviewScript.attach_preview_settlement_buildings(
			slope_cities, slope_sampler, {slope_tile: slope_anchor}
		),
		"sloped preview city attaches settlement buildings"
	)
	await process_frame

	# Defect catcher: before world-space footprint align, center-only placement
	# leaves the house lower bound below max footprint support by more than embed.
	var slope_layout: Node3D = slope_cities.layout_root_for_city(2)
	var house_before: Node3D = CityAssetPreviewScript.preview_house_building(slope_layout)
	var support_before: Dictionary = CityAssetPreviewScript.preview_support_height_under_building(
		house_before, slope_sampler
	)
	_check(support_before["ok"], "sloped house reports footprint support before align")
	var bottom_before := (support_before["aabb"] as AABB).position.y
	var max_support_before := float(support_before["height"])
	var center_before := float(support_before["center_height"])
	var embed := WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
	var center_only_gap := max_support_before - (bottom_before + embed)
	_check(
		center_before < max_support_before - 0.04,
		"sloped preview tile (2,7) has meaningful footprint height delta"
	)
	_check(
		center_only_gap > embed,
		(
			"center-only AABB placement deeply buries house on slope "
			+ "(gap=%.3f > embed=%.3f) — the bug this aligner must fix"
		)
		% [center_only_gap, embed]
	)

	_check(
		CityAssetPreviewScript.align_preview_settlement_buildings_vertical(
			slope_cities, slope_sampler
		),
		"sloped preview settlement vertical align succeeds"
	)
	await process_frame

	var align_tol := 0.02
	for label_building in [
		["main", slope_cities.main_building_for_city(2)],
		["house", CityAssetPreviewScript.preview_house_building(slope_layout)],
		["storage", CityAssetPreviewScript.preview_storage_building(slope_layout)],
	]:
		var label: String = label_building[0]
		var building: Node3D = label_building[1]
		_check(building != null, "sloped preview %s exists after align" % label)
		if building == null:
			continue
		_check(
			is_equal_approx(building.rotation.x, 0.0)
			and is_equal_approx(building.rotation.z, 0.0),
			"sloped preview %s stays upright (no slope tilt)" % label
		)
		var support_after: Dictionary = CityAssetPreviewScript.preview_support_height_under_building(
			building, slope_sampler
		)
		_check(support_after["ok"], "sloped preview %s support sample ok" % label)
		var bottom_after := (support_after["aabb"] as AABB).position.y
		var support_h := float(support_after["height"])
		var err: float = absf(bottom_after - (support_h - embed))
		_check(
			err <= align_tol,
			(
				"sloped preview %s lower bound matches support-embed "
				+ "(bottom=%.4f support=%.4f embed=%.3f err=%.4f)"
			)
			% [label, bottom_after, support_h, embed, err]
		)
		var top_after := bottom_after + (support_after["aabb"] as AABB).size.y
		_check(
			top_after > support_h + 0.02,
			"sloped preview %s is not roof-only above support terrain" % label
		)

	_finish()


# Deterministic plane sampler for headless slope alignment tests (no TerrainWorld).
class PreviewSlopeSampler:
	var _origin: Vector3
	var _grad: Vector2

	func _init(origin: Vector3, grad_xz: Vector2) -> void:
		_origin = origin
		_grad = grad_xz

	func sample(x: float, z: float, _y_hint: float) -> Dictionary:
		var height := (
			_origin.y + _grad.x * (x - _origin.x) + _grad.y * (z - _origin.z)
		)
		return {"ok": true, "height": height, "normal": Vector3.UP}


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
		print("test_city_asset_preview: FAILED (%d checks)" % _total)
		quit(1)
	print("test_city_asset_preview: OK (%d checks)" % _total)
	quit(0)
