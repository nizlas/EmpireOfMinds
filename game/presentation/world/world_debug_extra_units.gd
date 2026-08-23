# When EOM_DEBUG_EXTRA_3D_CHARACTERS=1, merge debug characters into the array
# passed to WorldUnitsView (presentation). Never mutates the authoritative
# snapshot / WorldInteractionState.
#
# - niclas / bronze_armed_warrior: presentation-only (not selectable).
# - generated_warrior: preferred from the server spawn under the same env flag
#   (move/attack). If the server match was created without the flag, a client
#   fallback row is added so the figure is still visible + equippable — with a
#   warning that actions need the server env on a fresh match.
extends RefCounted

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")

# Reserved high ids so server allocations (small ascending ints) never collide.
const DEBUG_UNIT_ID_BASE: int = 900001

const PRESENTATION_ONLY_DEBUG_TYPE_IDS: Array = ["niclas", "bronze_armed_warrior"]
# Only injected when the authoritative snapshot does not already carry one.
const GENERATED_WARRIOR_TYPE_ID: String = "generated_warrior"

# Preferred tiles on handdrawn_test_map_full_01 near P0 spawn (1,1)/(2,1).
# (2,0) matches the server debug spawn for generated_warrior.
const PREFERRED_TILE_BY_TYPE: Dictionary = {
	"niclas": Vector2i(0, 1),
	"bronze_armed_warrior": Vector2i(3, 1),
	"generated_warrior": Vector2i(2, 0),
}


static func env_enabled() -> bool:
	return Warrior3DExperimentScript.env_debug_extra_3d_characters_enabled()


## Returns a new array: authoritative units first, then debug extras (if any).
## `tile_anchors` is TerrainWorld.tile_anchors (Vector2i -> Vector3).
static func merge_into_units(units: Array, tile_anchors: Dictionary) -> Array:
	var merged: Array = units.duplicate(true)
	if not env_enabled():
		return merged
	var occupied: Dictionary = {}
	var seen_types: Dictionary = {}
	for row_variant in merged:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		seen_types[str(row.get("type_id", ""))] = true
		var pos_variant = row.get("position", null)
		if typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
			continue
		var pos: Array = pos_variant
		occupied[Vector2i(int(pos[0]), int(pos[1]))] = true
	var next_id: int = DEBUG_UNIT_ID_BASE
	var to_place: Array = PRESENTATION_ONLY_DEBUG_TYPE_IDS.duplicate()
	if not seen_types.has(GENERATED_WARRIOR_TYPE_ID):
		to_place.append(GENERATED_WARRIOR_TYPE_ID)
		push_warning(
			(
				"world_debug_extra_units: snapshot has no generated_warrior — "
				+ "client fallback spawn for visibility. For move/attack, restart "
				+ "the server with EOM_DEBUG_EXTRA_3D_CHARACTERS=1 and create a NEW match."
			)
		)
	for type_id in to_place:
		var tid: String = str(type_id)
		if Warrior3DExperimentScript.animated_scene_path_for_type(tid).is_empty():
			continue
		var tile: Variant = _pick_tile(tid, tile_anchors, occupied)
		if tile == null:
			push_warning(
				"world_debug_extra_units: no free anchor tile for %s — skipped" % tid
			)
			continue
		var key: Vector2i = tile
		occupied[key] = true
		merged.append(
			{
				"id": next_id,
				"owner_id": 0,
				"position": [key.x, key.y],
				"type_id": tid,
			}
		)
		next_id += 1
	return merged


static func _pick_tile(
	type_id: String, tile_anchors: Dictionary, occupied: Dictionary
) -> Variant:
	var preferred: Vector2i = PREFERRED_TILE_BY_TYPE.get(type_id, Vector2i(0, 1))
	if _is_free_anchor(preferred, tile_anchors, occupied):
		return preferred
	var seeds: Array[Vector2i] = [preferred, Vector2i(2, 1), Vector2i(1, 1)]
	for seed in seeds:
		var found: Variant = _search_ring(seed, tile_anchors, occupied, 4)
		if found != null:
			return found
	var keys: Array = tile_anchors.keys()
	keys.sort_custom(func(a, b): return _axial_key(a) < _axial_key(b))
	for key_variant in keys:
		var key: Vector2i = key_variant
		if not occupied.has(key):
			return key
	return null


static func _search_ring(
	center: Vector2i, tile_anchors: Dictionary, occupied: Dictionary, max_radius: int
) -> Variant:
	for radius in range(1, max_radius + 1):
		for dq in range(-radius, radius + 1):
			for dr in range(-radius, radius + 1):
				if maxi(absi(dq), maxi(absi(dr), absi(-dq - dr))) != radius:
					continue
				var cand := Vector2i(center.x + dq, center.y + dr)
				if _is_free_anchor(cand, tile_anchors, occupied):
					return cand
	return null


static func _is_free_anchor(
	tile: Vector2i, tile_anchors: Dictionary, occupied: Dictionary
) -> bool:
	return tile_anchors.has(tile) and not occupied.has(tile)


static func _axial_key(tile: Vector2i) -> int:
	return tile.x * 100000 + tile.y
