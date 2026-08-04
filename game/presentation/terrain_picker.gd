# N3c.5 presentation/integration-side deterministic terrain picker.
#
# Resolves Godot physics raycast results against the named N3c.4
# TerrainCollision body into canonical WorldMap identities:
# - top-surface hit  -> {"kind": "tile", "tile": Vector2i(q, r)} — resolved
#   from the hit X/Z through HexWorldProjection.world_xz_to_axial and
#   validated against WorldMap;
# - cliff-wall hit   -> {"kind": "cliff", "edge_key": String,
#   "tile_a": Vector2i, "tile_b": Vector2i} — the normalized WorldMap edge
#   key plus BOTH adjacent tiles in normalized order. Locked cliff-picking
#   rule (docs/MAP_MODEL.md): a cliff hit identifies the authoritative edge
#   and its two adjacent tiles; never silently the lower or upper tile.
#   Gameplay legality keeps using WorldMap edge data.
# - miss, foreign collider, or invalid/missing face index -> {} (no pick;
#   never guessed from position, normal, nearest geometry, or elevation).
#
# Wall identity comes from deterministic metadata aligned one-to-one with
# the wall collision triangles: the same fan triangulation order as
# rendering/collision (quads emit 2 triangles that share one source
# WallFace; crack tips emit 1), so the physics face_index is only a
# presentation lookup index — the returned identity is always the WallFace's
# authoritative tile pair validated against WorldMap.
#
# Read-only over WorldMap, geometry, and collision. Inspection/selection
# state, overlays, and gameplay stay out of scope.
extends RefCounted

const WorldMapScript = preload("res://domain/world/world_map.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")
const TerrainCollisionScript = preload("res://presentation/terrain_collision.gd")

const KIND_TILE := "tile"
const KIND_CLIFF := "cliff"


# One entry per wall collision triangle (reference map: 1,852): the index of
# the source WallFace record in geometry.wall_faces. Deterministic: pure
# function of the accepted wall-face record order and sizes.
static func build_wall_triangle_map(geometry) -> PackedInt32Array:
	var map := PackedInt32Array()
	for face_index in geometry.wall_faces.size():
		var vertex_count: int = geometry.wall_faces[face_index].vertex_indices.size()
		for _t in vertex_count - 2:
			map.append(face_index)
	return map


# Resolves one raycast result (as returned by
# PhysicsDirectSpaceState3D.intersect_ray) into a pick dictionary, or {}
# when there is nothing to pick.
static func resolve_pick(
	ray_hit: Dictionary,
	world_map,
	geometry,
	wall_triangle_map: PackedInt32Array
) -> Dictionary:
	if ray_hit.is_empty():
		return {}
	var collider = ray_hit.get("collider")
	if not (collider is StaticBody3D):
		return {}
	if collider.name != StringName(TerrainCollisionScript.BODY_NAME):
		return {}
	var shape_index := int(ray_hit.get("shape", -1))
	if shape_index < 0:
		return {}
	var owner_id: int = collider.shape_find_owner(shape_index)
	var shape_node = collider.shape_owner_get_owner(owner_id)
	if shape_node == null:
		return {}
	match String(shape_node.name):
		TerrainCollisionScript.TOP_SHAPE_NAME:
			return _resolve_tile_pick(ray_hit, world_map)
		TerrainCollisionScript.WALL_SHAPE_NAME:
			return _resolve_cliff_pick(ray_hit, world_map, geometry, wall_triangle_map)
	return {}


static func _resolve_tile_pick(ray_hit: Dictionary, world_map) -> Dictionary:
	if not ray_hit.has("position"):
		return {}
	var position: Vector3 = ray_hit["position"]
	var coord: Vector2i = HexWorldProjectionScript.world_xz_to_axial(position.x, position.z)
	if not world_map.has_tile_coord(coord):
		return {}
	return {"kind": KIND_TILE, "tile": coord}


static func _resolve_cliff_pick(
	ray_hit: Dictionary,
	world_map,
	geometry,
	wall_triangle_map: PackedInt32Array
) -> Dictionary:
	var face_index := int(ray_hit.get("face_index", -1))
	if face_index < 0 or face_index >= wall_triangle_map.size():
		return {}
	var record = geometry.wall_faces[wall_triangle_map[face_index]]
	if not world_map.has_edge_between(record.tile_a, record.tile_b):
		return {}
	var edge = world_map.edge_between(record.tile_a, record.tile_b)
	if edge.transition != WorldMapScript.EDGE_CLIFF:
		return {}
	var edge_key: String = WorldMapScript.normalized_edge_key(record.tile_a, record.tile_b)
	var tiles: Array = WorldMapScript.parse_edge_key(edge_key)
	return {
		"kind": KIND_CLIFF,
		"edge_key": edge_key,
		"tile_a": tiles[0],
		"tile_b": tiles[1],
	}
