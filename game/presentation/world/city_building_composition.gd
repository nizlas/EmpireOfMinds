# CP1 presentation-only city-building composition for the building parts of
# ONE city. Asset-independent: the caller supplies PackedScene parts and
# deterministic slot data. This component does not consume snapshots,
# reconcile cities, or replace WorldCitiesView.
#
# Contract (locked):
# - Placement starts from a caller-supplied city tile anchor and city yaw.
#   Each slot's local X/Z is rotated by that city yaw, then the existing
#   WorldSurfaceSampler (injected; never created here) samples the rendered
#   top surface at the resulting world X/Z. The part sits at sampled height
#   minus its foundation sink, upright (yaw only — never pitch/roll).
# - Stable child roots are keyed by slot id. Reapplying an identical
#   composition keeps the same roots; removed slots are freed.
# - Invalid slots, a missing sampler, or a failed surface sample fail
#   visibly (push_error) and skip that part — never guess an origin, never
#   invent another terrain sampler, never infer gameplay from collision.
class_name CityBuildingComposition
extends Node3D

# WorldSurfaceSampler-shaped object exposing
# sample(x, z, y_hint) -> {ok, height, normal}. May stay null.
var _surface_sampler = null
var _root_by_slot_id: Dictionary = {}


func set_surface_sampler(sampler) -> void:
	_surface_sampler = sampler


func has_surface_sampler() -> bool:
	return _surface_sampler != null


func part_count() -> int:
	return _root_by_slot_id.size()


func slot_ids() -> Array:
	var ids: Array = _root_by_slot_id.keys()
	ids.sort()
	return ids


func root_for_slot(slot_id: String) -> Node3D:
	return _root_by_slot_id.get(slot_id) as Node3D


# Reconciles building parts for one city. `slots` is an Array of Dictionaries:
#   slot_id (String), local_x (float), local_z (float), yaw (float radians),
#   scale (float, uniform > 0), foundation_sink (float), scene (PackedScene).
# Slot yaw is relative to city_yaw (world yaw = city_yaw + slot yaw).
# The composition node is expected under a world-space identity parent
# (same placement pattern as WorldCitiesView / WorldUnitsView).
func apply_composition(city_anchor: Vector3, city_yaw: float, slots: Array) -> void:
	var active_ids: Dictionary = {}
	var seen_ids: Dictionary = {}
	if typeof(slots) != TYPE_ARRAY:
		push_error("city_building_composition: slots must be an Array")
		_free_stale(active_ids)
		return
	for slot_variant in slots:
		var parsed := _parse_slot(slot_variant, seen_ids)
		if parsed.is_empty():
			continue
		var slot_id: String = parsed["slot_id"]
		seen_ids[slot_id] = true
		if _surface_sampler == null:
			push_error(
				"city_building_composition: missing surface sampler — skip slot '%s'" % slot_id
			)
			continue
		var local_offset := Vector3(float(parsed["local_x"]), 0.0, float(parsed["local_z"]))
		var world_xz: Vector3 = city_anchor + local_offset.rotated(Vector3.UP, city_yaw)
		var sample: Dictionary = _surface_sampler.sample(world_xz.x, world_xz.z, city_anchor.y)
		if not bool(sample.get("ok", false)):
			push_error(
				"city_building_composition: surface sample miss — skip slot '%s' at (%.3f, %.3f)"
				% [slot_id, world_xz.x, world_xz.z]
			)
			continue
		var height := float(sample.get("height", city_anchor.y))
		var sink := float(parsed["foundation_sink"])
		var world_yaw := city_yaw + float(parsed["yaw"])
		var uniform_scale := float(parsed["scale"])
		var root: Node3D = _root_by_slot_id.get(slot_id) as Node3D
		if root == null:
			root = _create_part_root(slot_id, parsed["scene"] as PackedScene)
			if root == null:
				continue
		root.position = Vector3(world_xz.x, height - sink, world_xz.z)
		root.rotation = Vector3(0.0, world_yaw, 0.0)
		root.scale = Vector3.ONE * uniform_scale
		active_ids[slot_id] = true
	_free_stale(active_ids)


func _parse_slot(slot_variant, seen_ids: Dictionary) -> Dictionary:
	if typeof(slot_variant) != TYPE_DICTIONARY:
		push_error("city_building_composition: slot is not an object")
		return {}
	var slot: Dictionary = slot_variant
	if not slot.has("slot_id") or not slot.has("local_x") or not slot.has("local_z"):
		push_error("city_building_composition: malformed slot (missing id/offset keys)")
		return {}
	if not slot.has("yaw") or not slot.has("scale") or not slot.has("foundation_sink"):
		push_error("city_building_composition: malformed slot (missing yaw/scale/sink)")
		return {}
	if not slot.has("scene"):
		push_error("city_building_composition: malformed slot (missing scene)")
		return {}
	var slot_id := str(slot["slot_id"])
	if slot_id.is_empty():
		push_error("city_building_composition: empty slot_id")
		return {}
	if seen_ids.has(slot_id):
		push_error("city_building_composition: duplicate slot_id '%s'" % slot_id)
		return {}
	if typeof(slot["local_x"]) != TYPE_FLOAT and typeof(slot["local_x"]) != TYPE_INT:
		push_error("city_building_composition: slot '%s' local_x is not numeric" % slot_id)
		return {}
	if typeof(slot["local_z"]) != TYPE_FLOAT and typeof(slot["local_z"]) != TYPE_INT:
		push_error("city_building_composition: slot '%s' local_z is not numeric" % slot_id)
		return {}
	if typeof(slot["yaw"]) != TYPE_FLOAT and typeof(slot["yaw"]) != TYPE_INT:
		push_error("city_building_composition: slot '%s' yaw is not numeric" % slot_id)
		return {}
	if typeof(slot["scale"]) != TYPE_FLOAT and typeof(slot["scale"]) != TYPE_INT:
		push_error("city_building_composition: slot '%s' scale is not numeric" % slot_id)
		return {}
	if typeof(slot["foundation_sink"]) != TYPE_FLOAT and typeof(slot["foundation_sink"]) != TYPE_INT:
		push_error("city_building_composition: slot '%s' foundation_sink is not numeric" % slot_id)
		return {}
	var uniform_scale := float(slot["scale"])
	if uniform_scale <= 0.0 or not is_finite(uniform_scale):
		push_error("city_building_composition: slot '%s' scale must be finite and > 0" % slot_id)
		return {}
	var sink := float(slot["foundation_sink"])
	if not is_finite(sink):
		push_error("city_building_composition: slot '%s' foundation_sink is not finite" % slot_id)
		return {}
	var scene = slot["scene"]
	if scene == null or not (scene is PackedScene):
		push_error("city_building_composition: slot '%s' scene is not a PackedScene" % slot_id)
		return {}
	return {
		"slot_id": slot_id,
		"local_x": float(slot["local_x"]),
		"local_z": float(slot["local_z"]),
		"yaw": float(slot["yaw"]),
		"scale": uniform_scale,
		"foundation_sink": sink,
		"scene": scene,
	}


func _create_part_root(slot_id: String, scene: PackedScene) -> Node3D:
	var instance := scene.instantiate()
	if instance == null:
		push_error("city_building_composition: scene.instantiate() returned null for slot '%s'" % slot_id)
		return null
	var root: Node3D
	if instance is Node3D:
		root = instance as Node3D
	else:
		root = Node3D.new()
		root.add_child(instance)
	root.name = "BuildingSlot_%s" % slot_id
	add_child(root)
	_root_by_slot_id[slot_id] = root
	return root


func _free_stale(active_ids: Dictionary) -> void:
	for stale_key in _root_by_slot_id.keys():
		var stale_id := str(stale_key)
		if active_ids.has(stale_id):
			continue
		var stale_root: Node = _root_by_slot_id[stale_id] as Node
		if stale_root != null:
			stale_root.queue_free()
		_root_by_slot_id.erase(stale_id)
