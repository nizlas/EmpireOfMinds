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
# - Stable child roots are keyed by slot id. Reapplying the same slot id with
#   the same PackedScene keeps the root; a changed PackedScene replaces that
#   slot's root; removed slots are freed. Other slots keep their identities.
# - Invalid slots, a missing sampler, a failed surface sample, or an ok
#   sample without a numeric finite height fail visibly (push_error) and skip
#   that part — never fall back to city_anchor.y, never guess an origin,
#   never invent another terrain sampler, never infer gameplay from collision.
class_name CityBuildingComposition
extends Node3D

# WorldSurfaceSampler-shaped object exposing
# sample(x, z, y_hint) -> {ok, height, normal}. May stay null.
var _surface_sampler = null
var _root_by_slot_id: Dictionary = {}
var _scene_by_slot_id: Dictionary = {}


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
#   scale (float, uniform > 0), foundation_sink (float >= 0), scene (PackedScene).
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
		var sample_variant = _surface_sampler.sample(world_xz.x, world_xz.z, city_anchor.y)
		if typeof(sample_variant) != TYPE_DICTIONARY:
			push_error(
				"city_building_composition: surface sample is not an object — skip slot '%s'"
				% slot_id
			)
			continue
		var sample: Dictionary = sample_variant
		if not bool(sample.get("ok", false)):
			push_error(
				"city_building_composition: surface sample miss — skip slot '%s' at (%.3f, %.3f)"
				% [slot_id, world_xz.x, world_xz.z]
			)
			continue
		var height_result := _parse_sample_height(sample, slot_id)
		if not bool(height_result.get("ok", false)):
			continue
		var height := float(height_result["height"])
		var sink := float(parsed["foundation_sink"])
		var world_yaw := city_yaw + float(parsed["yaw"])
		var uniform_scale := float(parsed["scale"])
		var scene: PackedScene = parsed["scene"] as PackedScene
		var root: Node3D = _root_by_slot_id.get(slot_id) as Node3D
		var prior_scene: PackedScene = _scene_by_slot_id.get(slot_id) as PackedScene
		if root != null and prior_scene != scene:
			# Free immediately so the replacement can reuse the slot-keyed
			# node name in this same apply (queue_free would collide).
			remove_child(root)
			root.free()
			_root_by_slot_id.erase(slot_id)
			_scene_by_slot_id.erase(slot_id)
			root = null
		if root == null:
			root = _create_part_root(slot_id, scene)
			if root == null:
				continue
		root.position = Vector3(world_xz.x, height - sink, world_xz.z)
		root.rotation = Vector3(0.0, world_yaw, 0.0)
		root.scale = Vector3.ONE * uniform_scale
		active_ids[slot_id] = true
	_free_stale(active_ids)


func _parse_sample_height(sample: Dictionary, slot_id: String) -> Dictionary:
	if not sample.has("height"):
		push_error(
			"city_building_composition: ok sample missing height — skip slot '%s'" % slot_id
		)
		return {"ok": false}
	var height_variant = sample["height"]
	if typeof(height_variant) != TYPE_FLOAT and typeof(height_variant) != TYPE_INT:
		push_error(
			"city_building_composition: ok sample height is not numeric — skip slot '%s'" % slot_id
		)
		return {"ok": false}
	var height := float(height_variant)
	if not is_finite(height):
		push_error(
			"city_building_composition: ok sample height is not finite — skip slot '%s'" % slot_id
		)
		return {"ok": false}
	return {"ok": true, "height": height}


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
	if typeof(slot["slot_id"]) != TYPE_STRING:
		push_error("city_building_composition: slot_id is not a String")
		return {}
	var slot_id: String = slot["slot_id"]
	if slot_id.is_empty():
		push_error("city_building_composition: empty slot_id")
		return {}
	if seen_ids.has(slot_id):
		push_error("city_building_composition: duplicate slot_id '%s'" % slot_id)
		return {}
	var local_x_result := _parse_finite_number(slot["local_x"], slot_id, "local_x")
	if not bool(local_x_result.get("ok", false)):
		return {}
	var local_z_result := _parse_finite_number(slot["local_z"], slot_id, "local_z")
	if not bool(local_z_result.get("ok", false)):
		return {}
	var yaw_result := _parse_finite_number(slot["yaw"], slot_id, "yaw")
	if not bool(yaw_result.get("ok", false)):
		return {}
	var scale_result := _parse_finite_number(slot["scale"], slot_id, "scale")
	if not bool(scale_result.get("ok", false)):
		return {}
	var sink_result := _parse_finite_number(slot["foundation_sink"], slot_id, "foundation_sink")
	if not bool(sink_result.get("ok", false)):
		return {}
	var uniform_scale := float(scale_result["value"])
	if uniform_scale <= 0.0:
		push_error("city_building_composition: slot '%s' scale must be > 0" % slot_id)
		return {}
	var sink := float(sink_result["value"])
	if sink < 0.0:
		push_error("city_building_composition: slot '%s' foundation_sink must be >= 0" % slot_id)
		return {}
	var scene = slot["scene"]
	if scene == null or not (scene is PackedScene):
		push_error("city_building_composition: slot '%s' scene is not a PackedScene" % slot_id)
		return {}
	return {
		"slot_id": slot_id,
		"local_x": float(local_x_result["value"]),
		"local_z": float(local_z_result["value"]),
		"yaw": float(yaw_result["value"]),
		"scale": uniform_scale,
		"foundation_sink": sink,
		"scene": scene,
	}


func _parse_finite_number(value, slot_id: String, field: String) -> Dictionary:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		push_error("city_building_composition: slot '%s' %s is not numeric" % [slot_id, field])
		return {"ok": false}
	var number := float(value)
	if not is_finite(number):
		push_error("city_building_composition: slot '%s' %s is not finite" % [slot_id, field])
		return {"ok": false}
	return {"ok": true, "value": number}


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
	_scene_by_slot_id[slot_id] = scene
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
		_scene_by_slot_id.erase(stale_id)
