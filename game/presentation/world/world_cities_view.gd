# N8a world-city presentation: renders the authoritative snapshot-v3 cities
# as the existing ancient_village character at the N4 tile anchors.
#
# Contract (locked):
# - The server snapshot is the only gameplay truth: each city row is exactly
#   {"id", "owner_id", "position": [q, r], "name"} and this view reconciles
#   ONE stable Node3D root per city, keyed by exact city id.
# - Placement uses TerrainWorld.tile_anchors verbatim — never an origin
#   fallback, never a recomputed axial/mesh-derived anchor. A city position
#   without an anchor is a contract violation: explicit error, city skipped.
# - Visuals reuse the project's imported ancient_village GLB below a
#   ModelRoot child (scale MODEL_ROOT_SCALE for terrain S=1) with the same
#   locked matte material treatment as world units. No selection, legality,
#   production UI, territory, or new assets here.
class_name WorldCitiesView
extends Node3D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

const MODEL_ROOT_SCALE := 0.5
# Matches the accepted legacy city yaw so the village faces a readable angle
# on the terrain (presentation-only; never gameplay).
const MODEL_YAW_RAD := deg_to_rad(-67.0)

var _tile_anchors: Dictionary = {}
var _anchors_ready := false
var _cities: Array = []
var _cities_ready := false
var _root_by_city_id: Dictionary = {}
var _name_by_city_id: Dictionary = {}
var _city_scene: PackedScene = null
var _city_scene_loaded := false
var _warned_missing_scene := false


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
		else:
			root.position = anchor
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


func _create_city_root(city_id: int) -> Node3D:
	var scene := _load_city_scene()
	if scene == null:
		return null
	var root := Node3D.new()
	root.name = "City_%d" % city_id
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	model_root.scale = Vector3.ONE * MODEL_ROOT_SCALE
	model_root.rotation = Vector3(0.0, MODEL_YAW_RAD, 0.0)
	root.add_child(model_root)
	var instance := scene.instantiate()
	if instance == null:
		push_error("world_cities_view: failed to instantiate city scene for city %d" % city_id)
		root.queue_free()
		return null
	model_root.add_child(instance)
	WorldUnitsViewScript.apply_material_treatment(instance)
	add_child(root)
	_root_by_city_id[city_id] = root
	return root


func _load_city_scene() -> PackedScene:
	if _city_scene_loaded:
		return _city_scene
	_city_scene_loaded = true
	var scene_path: String = Warrior3DExperimentScript.city_scene_path()
	if scene_path.is_empty():
		if not _warned_missing_scene:
			push_error("world_cities_view: no ancient_village city scene registered")
			_warned_missing_scene = true
		return null
	_city_scene = load(scene_path) as PackedScene
	if _city_scene == null and not _warned_missing_scene:
		push_error("world_cities_view: failed to load %s" % scene_path)
		_warned_missing_scene = true
	return _city_scene
