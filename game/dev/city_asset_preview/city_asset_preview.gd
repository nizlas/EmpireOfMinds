# Development-only Ancient Era city-asset visual preview.
#
# Reuses production TerrainWorld (+ lighting/camera), WorldCitiesView, and
# WorldUnitsView for three preview city hexes (main building + centered warrior).
# On each of those hexes, also places preview-only house + storage buildings as a
# compact settlement group under the city's LayoutRoot. House/storage are NOT
# wired into production city placement/catalog.
#
# Run from the Godot editor: open this scene and press F6, or:
#   godot --path game res://dev/city_asset_preview/city_asset_preview.tscn
#
# Optional screenshot (output/ is gitignored):
#   godot --path game res://dev/city_asset_preview/city_asset_preview.tscn -- --screenshot[=low]
extends Node3D

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldCitiesViewScript = preload("res://presentation/world/world_cities_view.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldSurfaceSamplerScript = preload("res://presentation/world/world_surface_sampler.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const SCREENSHOT_DIR := "res://dev/city_asset_preview/output"

# Preview-only synthetic cities. Intentionally cover nearly flat → curved tiles.
# City ids are assigned 1..3 in this order so production
# WorldCitiesView.deterministic_city_yaw_rad matches these exact yaws.
const PREVIEW_TILES: Array[Vector2i] = [
	Vector2i(1, 11),
	Vector2i(2, 7),
	Vector2i(3, 6),
]
const PREVIEW_YAW_DEG_BY_TILE := {
	Vector2i(1, 11): 0.0,
	Vector2i(2, 7): 60.0,
	Vector2i(3, 6): 120.0,
}
# Preview-only warrior ids — presentation scale references, never gameplay.
const PREVIEW_WARRIOR_IDS: Array[int] = [901, 902, 903]

# Preview-only support buildings (not production city content).
const HOUSE_BUILDING_SCENE_PATH := (
	"res://assets/prototype/3d/cities/ancient_era/buildings/house_building/"
	+ "ancient_era_city_house_building.glb"
)
const STORAGE_BUILDING_SCENE_PATH := (
	"res://assets/prototype/3d/cities/ancient_era/buildings/storage_building/"
	+ "ancient_era_city_storage_building.glb"
)
const HOUSE_SLOT_NAME := "PreviewHouseSlot"
const STORAGE_SLOT_NAME := "PreviewStorageSlot"
const HOUSE_BUILDING_NAME := "HouseBuilding"
const STORAGE_BUILDING_NAME := "StorageBuilding"
# Layout-local XZ offsets (wu; hex S=1.0). Main stays on production +X slot
# (0.40, 0, 0). House/storage sit opposite as a compact trio around the center.
const HOUSE_SLOT_LOCAL_OFFSET := Vector3(-0.18, 0.0, 0.34)
const STORAGE_SLOT_LOCAL_OFFSET := Vector3(-0.18, 0.0, -0.34)

var world = null
var cities_view = null
var units_view = null
var anchor_ui = null


func _ready() -> void:
	print("city_asset_preview: loading canonical WorldMap (handdrawn_test_map_full_01)...")
	var world_map = MapContentLoader.load_reference_world_map()
	if world_map == null:
		push_error("city_asset_preview: canonical WorldMap failed to load")
		get_tree().quit(1)
		return

	for tile in PREVIEW_TILES:
		if not world_map.has_tile_coord(tile):
			push_error(
				"city_asset_preview: preview tile (%d, %d) missing from handdrawn_test_map_full_01"
				% [tile.x, tile.y]
			)
			get_tree().quit(1)
			return

	var backend := _auto_backend()
	if backend == Ts08HeightSolver.BACKEND_GDSCRIPT:
		print("city_asset_preview: native extension unavailable; GDScript solve takes about a minute")
	world = TerrainWorldScript.new()
	world.name = "TerrainWorld"
	add_child(world)
	if not world.build(world_map, backend):
		push_error("city_asset_preview: terrain world build failed")
		get_tree().quit(1)
		return

	var sampler = WorldSurfaceSamplerScript.for_terrain_world(world)

	cities_view = WorldCitiesViewScript.new()
	cities_view.name = "WorldCitiesView"
	add_child(cities_view)
	cities_view.set_surface_sampler(sampler)
	cities_view.set_tile_anchors(world.tile_anchors)

	units_view = WorldUnitsViewScript.new()
	units_view.name = "WorldUnitsView"
	add_child(units_view)
	units_view.set_surface_sampler(sampler)
	units_view.set_tile_anchors(world.tile_anchors)

	var preview_city_rows: Array = []
	var preview_unit_rows: Array = []
	var idx := 0
	for tile in PREVIEW_TILES:
		if not world.tile_anchors.has(tile):
			push_error(
				"city_asset_preview: missing N4 tile anchor for (%d, %d) — fail closed"
				% [tile.x, tile.y]
			)
			get_tree().quit(1)
			return
		idx += 1
		preview_city_rows.append(
			{
				"id": idx,
				"owner_id": 0,
				"position": [tile.x, tile.y],
				"name": "Preview Main %d" % idx,
			}
		)
		preview_unit_rows.append(
			{
				"id": PREVIEW_WARRIOR_IDS[idx - 1],
				"owner_id": 0,
				"position": [tile.x, tile.y],
				"type_id": "warrior",
				"current_hp": 100,
				"has_attacked": false,
			}
		)
	cities_view.apply_snapshot_cities(preview_city_rows)
	units_view.apply_snapshot_units(preview_unit_rows)
	print(
		"city_asset_preview: placed %d cities (scale=%.3f) + %d centered warriors (scale=%.3f) via production views"
		% [
			cities_view.city_count(),
			WorldCitiesViewScript.MAIN_BUILDING_SCALE,
			units_view.unit_count(),
			WorldUnitsViewScript.MODEL_ROOT_SCALE,
		]
	)
	var warrior_path: String = Warrior3DExperimentScript.animated_scene_path_for_type("warrior")
	print("city_asset_preview: warrior asset path=%s" % warrior_path)

	if not attach_preview_settlement_buildings(cities_view, sampler, world.tile_anchors):
		get_tree().quit(1)
		return
	if not align_preview_settlement_buildings_vertical(cities_view, sampler):
		get_tree().quit(1)
		return

	for i in range(PREVIEW_TILES.size()):
		var tile: Vector2i = PREVIEW_TILES[i]
		var city_id := i + 1
		var layout: Node3D = cities_view.layout_root_for_city(city_id)
		var yaw_deg := rad_to_deg(layout.rotation.y) if layout != null else NAN
		var slot: Node3D = cities_view.main_building_slot_for_city(city_id)
		var house_slot := preview_house_slot(layout)
		var storage_slot := preview_storage_slot(layout)
		var warrior_id: int = PREVIEW_WARRIOR_IDS[i]
		var warrior_root: Node3D = units_view.root_for_unit(warrior_id)
		print(
			(
				"city_asset_preview: city %d tile (%d, %d) LayoutRoot yaw=%.1f° "
				+ "(expected %.1f°) main_slot=%s house_slot=%s storage_slot=%s warrior_at=%s"
			)
			% [
				city_id,
				tile.x,
				tile.y,
				yaw_deg,
				float(PREVIEW_YAW_DEG_BY_TILE[tile]),
				slot.position if slot != null else Vector3.ZERO,
				house_slot.position if house_slot != null else Vector3.ZERO,
				storage_slot.position if storage_slot != null else Vector3.ZERO,
				warrior_root.position if warrior_root != null else Vector3.ZERO,
			]
		)

	anchor_ui = WorldAnchorUiScript.new()
	anchor_ui.name = "WorldAnchorUi"
	add_child(anchor_ui)
	anchor_ui.attach(world)
	var mid: Vector2i = PREVIEW_TILES[1]
	anchor_ui.focus_tile(mid)
	_frame_preview_cities()

	var args := OS.get_cmdline_user_args()
	var preset := _screenshot_preset_from_args(args)
	if preset != "":
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot(preset)


# Attach preview-only house + storage under each city's LayoutRoot.
# Scale + facing yaw match production helpers; final Y is applied by
# align_preview_settlement_buildings_vertical (world-space lower-bound align).
static func attach_preview_settlement_buildings(
	cities_view_node, sampler, tile_anchors: Dictionary
) -> bool:
	if cities_view_node == null:
		push_error("city_asset_preview: cities_view required for settlement buildings")
		return false
	if not ResourceLoader.exists(HOUSE_BUILDING_SCENE_PATH):
		push_error("city_asset_preview: missing house asset %s" % HOUSE_BUILDING_SCENE_PATH)
		return false
	if not ResourceLoader.exists(STORAGE_BUILDING_SCENE_PATH):
		push_error("city_asset_preview: missing storage asset %s" % STORAGE_BUILDING_SCENE_PATH)
		return false
	var house_scene := load(HOUSE_BUILDING_SCENE_PATH) as PackedScene
	var storage_scene := load(STORAGE_BUILDING_SCENE_PATH) as PackedScene
	if house_scene == null or storage_scene == null:
		push_error("city_asset_preview: house/storage PackedScene failed to load")
		return false

	var attached := 0
	for i in range(PREVIEW_TILES.size()):
		var tile: Vector2i = PREVIEW_TILES[i]
		var city_id := i + 1
		var layout: Node3D = cities_view_node.layout_root_for_city(city_id)
		var city_root: Node3D = cities_view_node.root_for_city(city_id)
		if layout == null or city_root == null:
			continue
		var anchor: Vector3 = city_root.position
		if tile_anchors.has(tile):
			anchor = tile_anchors[tile]
		var city_yaw: float = layout.rotation.y
		if not _spawn_support_building(
			layout,
			HOUSE_SLOT_NAME,
			HOUSE_BUILDING_NAME,
			house_scene,
			HOUSE_SLOT_LOCAL_OFFSET,
			anchor,
			city_yaw,
			sampler,
			city_id
		):
			return false
		if not _spawn_support_building(
			layout,
			STORAGE_SLOT_NAME,
			STORAGE_BUILDING_NAME,
			storage_scene,
			STORAGE_SLOT_LOCAL_OFFSET,
			anchor,
			city_yaw,
			sampler,
			city_id
		):
			return false
		attached += 1
		print(
			(
				"city_asset_preview: city %d settlement group ready — "
				+ "main_offset=%s house_offset=%s storage_offset=%s (preview-only)"
			)
			% [
				city_id,
				WorldCitiesViewScript.main_building_slot_local_offset(),
				HOUSE_SLOT_LOCAL_OFFSET,
				STORAGE_SLOT_LOCAL_OFFSET,
			]
		)
	if attached == 0:
		push_error("city_asset_preview: no preview cities available for settlement buildings")
		return false
	return true


static func preview_house_slot(layout: Node3D) -> Node3D:
	if layout == null:
		return null
	return layout.get_node_or_null(HOUSE_SLOT_NAME) as Node3D


static func preview_storage_slot(layout: Node3D) -> Node3D:
	if layout == null:
		return null
	return layout.get_node_or_null(STORAGE_SLOT_NAME) as Node3D


static func preview_house_building(layout: Node3D) -> Node3D:
	var slot := preview_house_slot(layout)
	if slot == null:
		return null
	return slot.get_node_or_null(HOUSE_BUILDING_NAME) as Node3D


static func preview_storage_building(layout: Node3D) -> Node3D:
	var slot := preview_storage_slot(layout)
	if slot == null:
		return null
	return slot.get_node_or_null(STORAGE_BUILDING_NAME) as Node3D


# Layout-local Y yaw aiming authored +Z entrance at the city center.
static func preview_building_facing_center_yaw_rad(slot_local_xz: Vector3) -> float:
	var to_center := -slot_local_xz
	to_center.y = 0.0
	if to_center.length_squared() < 1e-12:
		return 0.0
	to_center = to_center.normalized()
	return atan2(to_center.x, to_center.z)


# World-space aggregate mesh AABB (true transformed visual bounds).
static func aggregate_mesh_aabb_world(relative_to: Node3D) -> Dictionary:
	if relative_to == null or not relative_to.is_inside_tree():
		return {"ok": false, "aabb": AABB()}
	var first := true
	var out := AABB()
	var stack: Array = [relative_to]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var local := mi.get_aabb()
			var xf := mi.global_transform
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
		for child in node.get_children():
			stack.append(child)
	if first:
		return {"ok": false, "aabb": AABB()}
	return {"ok": true, "aabb": out}


# Support height for a building: max top-surface sample under its final world
# footprint (center + XZ corners). Center-only sampling leaves short buildings
# buried into uphill terrain on sloped hexes even when local AABB*scale math is
# exact at the slot center.
static func preview_support_height_under_building(building: Node3D, sampler) -> Dictionary:
	var bounds: Dictionary = aggregate_mesh_aabb_world(building)
	if not bounds["ok"]:
		return {"ok": false, "height": 0.0, "aabb": AABB(), "center_height": 0.0}
	var aabb: AABB = bounds["aabb"]
	if sampler == null:
		return {
			"ok": true,
			"height": building.global_position.y,
			"aabb": aabb,
			"center_height": building.global_position.y,
		}
	var y_hint := building.global_position.y
	var max_h := -INF
	var center_h := y_hint
	var any := false
	var center_sample = sampler.sample(building.global_position.x, building.global_position.z, y_hint)
	if typeof(center_sample) == TYPE_DICTIONARY and bool(center_sample.get("ok", false)):
		center_h = float(center_sample["height"])
		max_h = center_h
		any = true
	# Dense 3×3 grid over the transformed footprint so interior slope peaks
	# (not only AABB corners) raise the support height.
	for ix in range(3):
		for iz in range(3):
			var x: float = aabb.position.x + aabb.size.x * (float(ix) * 0.5)
			var z: float = aabb.position.z + aabb.size.z * (float(iz) * 0.5)
			var sample_variant = sampler.sample(x, z, y_hint)
			if typeof(sample_variant) != TYPE_DICTIONARY:
				continue
			var sample: Dictionary = sample_variant
			if not bool(sample.get("ok", false)):
				continue
			var h := float(sample["height"])
			if not any or h > max_h:
				max_h = h
			any = true
	if not any:
		return {"ok": false, "height": y_hint, "aabb": aabb, "center_height": center_h}
	return {"ok": true, "height": max_h, "aabb": aabb, "center_height": center_h}


# Place the building's transformed lower visual bound at support_height - embed.
# Adjusts building.position.y only (upright; LayoutRoot yaw leaves Y invariant).
# sampler == null → no-op (keeps provisional local AABB placement).
static func align_preview_building_vertical(building: Node3D, sampler, embed: float) -> Dictionary:
	var miss := {"ok": false, "bottom": 0.0, "support": 0.0, "delta": 0.0}
	if building == null or not building.is_inside_tree():
		return miss
	var bounds_now: Dictionary = aggregate_mesh_aabb_world(building)
	if not bounds_now["ok"]:
		return miss
	var bottom_now: float = (bounds_now["aabb"] as AABB).position.y
	if sampler == null:
		return {
			"ok": true,
			"bottom": bottom_now,
			"support": bottom_now + embed,
			"center_height": bottom_now + embed,
			"delta": 0.0,
			"aabb": bounds_now["aabb"],
		}
	var support_info: Dictionary = preview_support_height_under_building(building, sampler)
	if not support_info["ok"]:
		return miss
	var aabb: AABB = support_info["aabb"]
	var bottom: float = aabb.position.y
	var support: float = float(support_info["height"])
	var target := support - embed
	var delta := target - bottom
	building.position.y += delta
	building.force_update_transform()
	var after: Dictionary = aggregate_mesh_aabb_world(building)
	var after_bottom := bottom + delta
	if after["ok"]:
		after_bottom = (after["aabb"] as AABB).position.y
	return {
		"ok": true,
		"bottom": after_bottom,
		"support": support,
		"center_height": float(support_info["center_height"]),
		"delta": delta,
		"aabb": after["aabb"] if after["ok"] else aabb,
	}


# Preview-only vertical pass for main + house + storage on every preview city.
# Does not modify production WorldCitiesView placement policy.
static func align_preview_settlement_buildings_vertical(cities_view_node, sampler) -> bool:
	if cities_view_node == null:
		return false
	var embed := WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
	var aligned := 0
	for i in range(PREVIEW_TILES.size()):
		var city_id := i + 1
		var layout: Node3D = cities_view_node.layout_root_for_city(city_id)
		if layout == null:
			continue
		var buildings: Array = [
			["main", cities_view_node.main_building_for_city(city_id)],
			["house", preview_house_building(layout)],
			["storage", preview_storage_building(layout)],
		]
		for entry in buildings:
			var label: String = entry[0]
			var building: Node3D = entry[1]
			if building == null:
				push_error("city_asset_preview: missing %s for vertical align city %d" % [label, city_id])
				return false
			var result: Dictionary = align_preview_building_vertical(building, sampler, embed)
			if not result["ok"]:
				push_error(
					"city_asset_preview: vertical align failed for city %d %s" % [city_id, label]
				)
				return false
			aligned += 1
			print(
				(
					"city_asset_preview: city %d %s vertical align "
					+ "support=%.5f center=%.5f bottom=%.5f delta=%.5f embed=%.3f"
				)
				% [
					city_id,
					label,
					float(result["support"]),
					float(result["center_height"]),
					float(result["bottom"]),
					float(result["delta"]),
					embed,
				]
			)
	if aligned == 0:
		push_error("city_asset_preview: no preview buildings available for vertical align")
		return false
	return true


static func _spawn_support_building(
	layout: Node3D,
	slot_name: String,
	building_name: String,
	packed: PackedScene,
	local_xz: Vector3,
	anchor: Vector3,
	city_yaw: float,
	sampler,
	city_id: int
) -> bool:
	if layout.get_node_or_null(slot_name) != null:
		return true

	var slot := Node3D.new()
	slot.name = slot_name
	# Provisional slot Y from center-offset sample (ray y_hint only). Final Y comes
	# from world-space lower-bound alignment after scale/yaw are applied.
	var surface_dy := _preview_surface_delta_at_offset(anchor, local_xz, city_yaw, sampler, city_id)
	slot.position = Vector3(local_xz.x, surface_dy, local_xz.z)
	slot.rotation = Vector3.ZERO
	layout.add_child(slot)

	var building := Node3D.new()
	building.name = building_name
	building.scale = Vector3.ONE
	building.rotation = Vector3(0.0, preview_building_facing_center_yaw_rad(local_xz), 0.0)
	building.position = Vector3.ZERO
	slot.add_child(building)

	var instance := packed.instantiate()
	if instance == null:
		push_error("city_asset_preview: failed to instantiate %s for city %d" % [building_name, city_id])
		slot.queue_free()
		return false
	building.add_child(instance)
	slot.force_update_transform()
	building.force_update_transform()
	if instance is Node3D:
		(instance as Node3D).force_update_transform()

	var bounds: Dictionary = WorldCitiesViewScript.aggregate_mesh_aabb_local(building)
	if not bounds["ok"]:
		push_error(
			"city_asset_preview: %s for city %d has no MeshInstance3D AABB" % [building_name, city_id]
		)
		slot.queue_free()
		return false
	var scale := WorldCitiesViewScript.MAIN_BUILDING_SCALE
	building.scale = Vector3.ONE * scale
	# Provisional local AABB lift (flat-ground equivalent). Vertical align pass
	# replaces this with true transformed lower-bound vs support height.
	var aabb: AABB = bounds["aabb"]
	var embed := WorldCitiesViewScript.MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
	building.position = Vector3(
		0.0, WorldCitiesViewScript.main_building_local_y(aabb.position.y, scale, embed), 0.0
	)
	print(
		(
			"city_asset_preview: city %d %s spawned scale=%.3f yaw_deg=%.1f "
			+ "slot_local_xz=(%.3f, %.3f) provisional_local_y=%.4f"
		)
		% [
			city_id,
			building_name,
			scale,
			rad_to_deg(building.rotation.y),
			local_xz.x,
			local_xz.z,
			building.position.y,
		]
	)
	return true


static func _preview_surface_delta_at_offset(
	anchor: Vector3, local_xz: Vector3, city_yaw: float, sampler, city_id: int
) -> float:
	if sampler == null:
		return 0.0
	var world_xz: Vector3 = anchor + local_xz.rotated(Vector3.UP, city_yaw)
	var sample_variant = sampler.sample(world_xz.x, world_xz.z, anchor.y)
	if typeof(sample_variant) != TYPE_DICTIONARY:
		return 0.0
	var sample: Dictionary = sample_variant
	if not bool(sample.get("ok", false)):
		push_error(
			"city_asset_preview: surface sample miss for city %d support building — using center-pin height"
			% city_id
		)
		return 0.0
	return float(sample["height"]) - anchor.y


static func _screenshot_preset_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--screenshot":
			return "strategic"
		if arg.begins_with("--screenshot="):
			return arg.get_slice("=", 1)
	return ""


func _frame_preview_cities() -> void:
	if world == null or world.camera == null:
		return
	var sum := Vector3.ZERO
	var count := 0
	for tile in PREVIEW_TILES:
		if not world.tile_anchors.has(tile):
			continue
		sum += world.tile_anchors[tile]
		count += 1
	if count == 0:
		return
	var centroid := sum / float(count)
	var max_span := 0.0
	for tile in PREVIEW_TILES:
		if not world.tile_anchors.has(tile):
			continue
		var p: Vector3 = world.tile_anchors[tile]
		max_span = maxf(
			max_span,
			Vector2(p.x - centroid.x, p.z - centroid.z).length()
		)
	world.camera.target = centroid
	world.camera.distance = clampf(max_span * 3.4, 7.0, 20.0)
	world.camera.yaw_deg = 41.5
	world.camera.pitch_deg = 28.0
	world.camera.orbit(0.0, 0.0)


func _save_screenshot(preset: String) -> void:
	if world.camera == null:
		push_error("city_asset_preview: no camera for screenshot")
		get_tree().quit(1)
		return
	if preset == "low":
		world.camera.preset_low_angle()
	else:
		world.camera.preset_strategic()
	_frame_preview_cities()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var global_path := ProjectSettings.globalize_path(
		"%s/city_main_building_%s.png" % [SCREENSHOT_DIR, preset]
	)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("city_asset_preview: screenshot image is null")
		get_tree().quit(1)
		return
	var error := image.save_png(global_path)
	if error == OK:
		print("city_asset_preview: wrote %s" % global_path)
		get_tree().quit(0)
	else:
		push_error("city_asset_preview: failed to save screenshot (%d)" % error)
		get_tree().quit(1)


func _auto_backend() -> String:
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR_PATH):
		return Ts08HeightSolver.BACKEND_GDSCRIPT
	if not GDExtensionManager.is_extension_loaded(NATIVE_DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(NATIVE_DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			return Ts08HeightSolver.BACKEND_GDSCRIPT
	if ClassDB.can_instantiate(&"EomTerrainNative"):
		return Ts08HeightSolver.BACKEND_NATIVE
	return Ts08HeightSolver.BACKEND_GDSCRIPT
