# N8a world-city presentation: renders authoritative snapshot-v3 cities at
# the N4 tile anchors using the modular Ancient Era city visual catalog.
#
# Contract (locked):
# - The server snapshot is the only gameplay truth: each city row is exactly
#   {"id", "owner_id", "position": [q, r], "name"} (+ optional current_project
#   after N8b) and this view reconciles ONE stable Node3D root per city,
#   keyed by exact city id.
# - The city root stays exactly at TerrainWorld.tile_anchors[tile] (center pin).
#   Never an origin fallback, never a recomputed axial anchor, never a
#   raycast for the city root. Missing anchors fail closed (city skipped).
# - Hierarchy:
#     City_<id>                         (at tile center; upright)
#       LayoutRoot                      (deterministic hex-aligned yaw)
#         MainBuildingSlot              (offset XZ; local Y = surface Δ)
#           MainBuilding                (scale + AABB-bottom + embed;
#                                        entrance faces city center)
#             imported GLB
# - MainBuildingSlot offset rotates with LayoutRoot. Vertical placement keeps
#   AABB-bottom + foundation embed, with terrain height sampled at the
#   offset world XZ (injected WorldSurfaceSampler) — not at the tile center.
# - Visual assets come from WorldCityVisualCatalog — NOT from
#   warrior_3d_unit_experiment / ancient_village. Authored GLB textures are
#   preserved. No selection, legality, production UI, or gameplay changes.
class_name WorldCitiesView
extends Node3D

const WorldCityVisualCatalogScript = preload("res://presentation/world/world_city_visual_catalog.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")

# Previous tuned scale was 0.35; keep exactly 80% of that value.
const MAIN_BUILDING_SCALE := 0.35 * 0.8
# Positive depth sunk below the offset-slot ground AFTER AABB-bottom alignment.
const MAIN_BUILDING_FOUNDATION_EMBED_DEPTH := 0.055
# Offset from city center in LayoutRoot local XZ — 40% of hex radius S.
const MAIN_BUILDING_SLOT_OFFSET_FRAC := 0.40
# Six hex-aligned yaw steps (degrees) for deterministic production facing.
const HEX_YAW_STEP_DEG := 60.0
# Authored entrance axis (import root + Mesh1_0 are identity). Mesh shell
# occupancy shows a mid-band doorway recess on the +Z AABB face; the facade
# therefore faces +Z. Slot sits on +X, so layout-local center is −X and the
# Y-yaw that maps +Z → −X is −π/2 (see main_building_facing_center_yaw_rad).
const MAIN_BUILDING_ENTRANCE_LOCAL := Vector3(0.0, 0.0, 1.0)

const LAYOUT_ROOT_NAME := "LayoutRoot"
const MAIN_BUILDING_SLOT_NAME := "MainBuildingSlot"
const MAIN_BUILDING_NAME := "MainBuilding"

var _tile_anchors: Dictionary = {}
var _anchors_ready := false
var _cities: Array = []
var _cities_ready := false
var _root_by_city_id: Dictionary = {}
var _name_by_city_id: Dictionary = {}
var _main_building_scene: PackedScene = null
var _main_building_scene_loaded := false
var _warned_missing_scene := false
var _logged_placement_once := false
var _surface_sampler = null


func set_surface_sampler(sampler) -> void:
	_surface_sampler = sampler
	_reconcile()


func has_surface_sampler() -> bool:
	return _surface_sampler != null


func set_tile_anchors(anchors: Dictionary) -> void:
	_tile_anchors = anchors
	_anchors_ready = not anchors.is_empty()
	_reconcile()


func apply_snapshot_cities(cities: Array) -> void:
	_cities = cities.duplicate(true)
	_cities_ready = true
	_reconcile()


func city_count() -> int:
	return _root_by_city_id.size()


func city_ids() -> Array:
	var ids: Array = _root_by_city_id.keys()
	ids.sort()
	return ids


func root_for_city(city_id: int) -> Node3D:
	return _root_by_city_id.get(city_id) as Node3D


func name_for_city(city_id: int) -> String:
	return str(_name_by_city_id.get(city_id, ""))


func layout_root_for_city(city_id: int) -> Node3D:
	var root := root_for_city(city_id)
	if root == null:
		return null
	return root.get_node_or_null(LAYOUT_ROOT_NAME) as Node3D


# Compatibility alias — LayoutRoot is the city yaw / modular layout root.
func visual_root_for_city(city_id: int) -> Node3D:
	return layout_root_for_city(city_id)


func main_building_slot_for_city(city_id: int) -> Node3D:
	var layout := layout_root_for_city(city_id)
	if layout == null:
		return null
	return layout.get_node_or_null(MAIN_BUILDING_SLOT_NAME) as Node3D


func main_building_for_city(city_id: int) -> Node3D:
	var slot := main_building_slot_for_city(city_id)
	if slot == null:
		return null
	return slot.get_node_or_null(MAIN_BUILDING_NAME) as Node3D


static func main_building_slot_local_offset() -> Vector3:
	var offset := HexWorldProjectionScript.S * MAIN_BUILDING_SLOT_OFFSET_FRAC
	return Vector3(offset, 0.0, 0.0)


# Layout-local Y yaw that aims MAIN_BUILDING_ENTRANCE_LOCAL at the city
# center (slot origin ← building). Shared by preview and production.
static func main_building_facing_center_yaw_rad() -> float:
	var to_center := -main_building_slot_local_offset()
	to_center.y = 0.0
	if to_center.length_squared() < 1e-12:
		return 0.0
	to_center = to_center.normalized()
	# rotate_y(yaw) * (0,0,1) = (sin(yaw), 0, cos(yaw)) → match to_center.xz
	return atan2(to_center.x, to_center.z)


# World-XZ unit vector of the authored entrance after the MainBuilding basis.
static func entrance_facing_world_xz(main_building: Node3D) -> Vector3:
	if main_building == null:
		return Vector3.ZERO
	var basis := main_building.global_transform.basis.orthonormalized()
	var facing: Vector3 = basis * MAIN_BUILDING_ENTRANCE_LOCAL
	facing.y = 0.0
	if facing.length_squared() < 1e-12:
		return Vector3.ZERO
	return facing.normalized()


# Stable hex-aligned yaw from city id (0/60/120/180/240/300°). No randomness.
static func deterministic_city_yaw_rad(city_id: int) -> float:
	var step := posmod(city_id - 1, 6)
	return deg_to_rad(float(step) * HEX_YAW_STEP_DEG)


# MainBuilding local Y: scaled AABB bottom on the slot ground, then embed.
# Scale is owned by MainBuilding — multiply aabb_min_y by scale exactly once.
static func main_building_local_y(aabb_min_y: float, scale: float, embed_depth: float) -> float:
	return -(aabb_min_y * scale) - embed_depth


# Aggregate AABB of all MeshInstance3D descendants in `relative_to` local space
# (uses the child transform chain only — does not apply relative_to.scale).
# Returns {"ok": bool, "aabb": AABB}. ok=false when no mesh bounds exist.
static func aggregate_mesh_aabb_local(relative_to: Node3D) -> Dictionary:
	var first := true
	var out := AABB()
	var stack: Array = []
	for child in relative_to.get_children():
		stack.append({"node": child, "xf": Transform3D.IDENTITY})
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		var node: Node = entry["node"]
		var parent_xf: Transform3D = entry["xf"]
		var xf := parent_xf
		if node is Node3D:
			xf = parent_xf * (node as Node3D).transform
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var local := mi.get_aabb()
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
		for child2 in node.get_children():
			stack.append({"node": child2, "xf": xf})
	if first:
		return {"ok": false, "aabb": AABB()}
	return {"ok": true, "aabb": out}


func _reconcile() -> void:
	if not _anchors_ready or not _cities_ready:
		return
	var active_ids: Dictionary = {}
	for row_variant in _cities:
		if typeof(row_variant) != TYPE_DICTIONARY:
			push_error("world_cities_view: snapshot city row is not an object")
			continue
		var row: Dictionary = row_variant
		var city_id := int(row.get("id", -1))
		var pos_variant = row.get("position", null)
		if city_id < 0 or typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
			push_error("world_cities_view: malformed snapshot city row (id=%d)" % city_id)
			continue
		var pos: Array = pos_variant
		var key := Vector2i(int(pos[0]), int(pos[1]))
		if not _tile_anchors.has(key):
			push_error(
				"world_cities_view: no tile anchor for city %d at (%d, %d) — snapshot/anchor contract violation, city not rendered"
				% [city_id, key.x, key.y]
			)
			continue
		var anchor: Vector3 = _tile_anchors[key]
		var root: Node3D = _root_by_city_id.get(city_id) as Node3D
		if root == null:
			root = _create_city_root(city_id)
			if root == null:
				continue
		root.position = anchor
		# Keep the city root upright — never inherit terrain pitch/roll.
		root.rotation = Vector3.ZERO
		_apply_layout_placement(root, city_id, anchor)
		_name_by_city_id[city_id] = str(row.get("name", ""))
		active_ids[city_id] = true
	for stale_key in _root_by_city_id.keys():
		var stale_id := int(stale_key)
		if active_ids.has(stale_id):
			continue
		var stale_root: Node = _root_by_city_id[stale_id] as Node
		if stale_root != null:
			stale_root.queue_free()
		_root_by_city_id.erase(stale_id)
		_name_by_city_id.erase(stale_id)


func _apply_layout_placement(root: Node3D, city_id: int, anchor: Vector3) -> void:
	var layout := root.get_node_or_null(LAYOUT_ROOT_NAME) as Node3D
	var slot := main_building_slot_for_city(city_id) if layout != null else null
	if layout == null or slot == null:
		return
	var city_yaw := deterministic_city_yaw_rad(city_id)
	layout.rotation = Vector3(0.0, city_yaw, 0.0)
	var local_xz := main_building_slot_local_offset()
	var surface_dy := _surface_delta_at_offset(anchor, local_xz, city_yaw, city_id)
	slot.position = Vector3(local_xz.x, surface_dy, local_xz.z)
	slot.rotation = Vector3.ZERO


func _surface_delta_at_offset(
	anchor: Vector3, local_xz: Vector3, city_yaw: float, city_id: int
) -> float:
	if _surface_sampler == null:
		return 0.0
	var world_xz: Vector3 = anchor + local_xz.rotated(Vector3.UP, city_yaw)
	var sample_variant = _surface_sampler.sample(world_xz.x, world_xz.z, anchor.y)
	if typeof(sample_variant) != TYPE_DICTIONARY:
		push_error(
			"world_cities_view: surface sample is not an object for city %d — using center-pin height"
			% city_id
		)
		return 0.0
	var sample: Dictionary = sample_variant
	if not bool(sample.get("ok", false)):
		push_error(
			"world_cities_view: surface sample miss for city %d at (%.3f, %.3f) — using center-pin height"
			% [city_id, world_xz.x, world_xz.z]
		)
		return 0.0
	var height_variant = sample.get("height", null)
	if typeof(height_variant) != TYPE_FLOAT and typeof(height_variant) != TYPE_INT:
		push_error(
			"world_cities_view: surface sample height missing for city %d — using center-pin height"
			% city_id
		)
		return 0.0
	var height := float(height_variant)
	if not is_finite(height):
		push_error(
			"world_cities_view: non-finite surface height for city %d — using center-pin height"
			% city_id
		)
		return 0.0
	return height - anchor.y


func _create_city_root(city_id: int) -> Node3D:
	var scene := _load_main_building_scene()
	if scene == null:
		return null
	var root := Node3D.new()
	root.name = "City_%d" % city_id
	root.rotation = Vector3.ZERO

	var layout_root := Node3D.new()
	layout_root.name = LAYOUT_ROOT_NAME
	layout_root.rotation = Vector3(0.0, deterministic_city_yaw_rad(city_id), 0.0)
	root.add_child(layout_root)

	var slot := Node3D.new()
	slot.name = MAIN_BUILDING_SLOT_NAME
	var local_xz := main_building_slot_local_offset()
	slot.position = Vector3(local_xz.x, 0.0, local_xz.z)
	slot.rotation = Vector3.ZERO
	layout_root.add_child(slot)

	var main_building := Node3D.new()
	main_building.name = MAIN_BUILDING_NAME
	# Scale applied after AABB measurement so min_y is not scaled twice.
	main_building.scale = Vector3.ONE
	main_building.rotation = Vector3(0.0, main_building_facing_center_yaw_rad(), 0.0)
	main_building.position = Vector3.ZERO
	slot.add_child(main_building)

	var instance := scene.instantiate()
	if instance == null:
		push_error("world_cities_view: failed to instantiate main building for city %d" % city_id)
		root.queue_free()
		return null
	main_building.add_child(instance)
	# Must be in-tree for transform updates before measuring child AABBs.
	add_child(root)
	root.force_update_transform()
	main_building.force_update_transform()
	if instance is Node3D:
		(instance as Node3D).force_update_transform()

	var bounds: Dictionary = aggregate_mesh_aabb_local(main_building)
	if not bounds["ok"]:
		push_error(
			"world_cities_view: main building for city %d has no MeshInstance3D AABB — refusing origin-based placement"
			% city_id
		)
		root.queue_free()
		return null
	var aabb: AABB = bounds["aabb"]
	var scaled_bottom_offset := -(aabb.position.y * MAIN_BUILDING_SCALE)
	var local_y := main_building_local_y(
		aabb.position.y, MAIN_BUILDING_SCALE, MAIN_BUILDING_FOUNDATION_EMBED_DEPTH
	)
	main_building.scale = Vector3.ONE * MAIN_BUILDING_SCALE
	main_building.position = Vector3(0.0, local_y, 0.0)
	# Preserve authored GLB textures — do not apply unit matte retreatment.
	if not _logged_placement_once:
		_logged_placement_once = true
		print(
			"world_cities_view: main building aggregate AABB position=%s size=%s min.y=%.6f scaled_bottom_offset=%.6f foundation_embed_depth=%.6f final_local_y=%.6f scale=%.3f slot_offset=%.3f"
			% [
				aabb.position,
				aabb.size,
				aabb.position.y,
				scaled_bottom_offset,
				MAIN_BUILDING_FOUNDATION_EMBED_DEPTH,
				local_y,
				MAIN_BUILDING_SCALE,
				local_xz.x,
			]
		)
	_root_by_city_id[city_id] = root
	return root


func _load_main_building_scene() -> PackedScene:
	if _main_building_scene_loaded:
		return _main_building_scene
	_main_building_scene_loaded = true
	var scene_path: String = WorldCityVisualCatalogScript.main_building_scene_path()
	if scene_path.is_empty():
		if not _warned_missing_scene:
			push_error(
				"world_cities_view: main building scene missing at %s"
				% WorldCityVisualCatalogScript.MAIN_BUILDING_SCENE_PATH
			)
			_warned_missing_scene = true
		return null
	_main_building_scene = WorldCityVisualCatalogScript.load_main_building_scene()
	if _main_building_scene == null and not _warned_missing_scene:
		push_error("world_cities_view: failed to load %s" % scene_path)
		_warned_missing_scene = true
	return _main_building_scene
