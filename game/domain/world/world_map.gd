# Sole canonical logical map authority (N1 foundation). Domain-only.
# Spec: docs/MAP_MODEL.md, docs/WORLD_COORDINATES.md
class_name WorldMap
extends RefCounted

const EDGE_SMOOTH := "smooth"
const EDGE_CLIFF := "cliff"

const HexCoordScript = preload("res://domain/hex_coord.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")


class WorldTile extends RefCounted:
	var q: int
	var r: int
	var elevation: int

	func _init(p_q: int, p_r: int, p_elevation: int) -> void:
		q = p_q
		r = p_r
		elevation = p_elevation

	func coord() -> Vector2i:
		return Vector2i(q, r)


class WorldEdge extends RefCounted:
	var tile_a: Vector2i
	var tile_b: Vector2i
	var transition: String

	func _init(p_tile_a: Vector2i, p_tile_b: Vector2i, p_transition: String) -> void:
		tile_a = p_tile_a
		tile_b = p_tile_b
		transition = p_transition


var identity
var elevation_step: float
var elevation_base: int
var cliff_threshold: int
var _tiles: Dictionary = {}
var _edges: Dictionary = {}
var _bounds_q_min: int = 0
var _bounds_q_max: int = 0
var _bounds_r_min: int = 0
var _bounds_r_max: int = 0


func _init(
	p_identity,
	p_elevation_step: float,
	p_elevation_base: int,
	p_cliff_threshold: int,
	p_tiles: Dictionary,
	p_edges: Dictionary
) -> void:
	identity = p_identity
	elevation_step = p_elevation_step
	elevation_base = p_elevation_base
	cliff_threshold = p_cliff_threshold
	_tiles = p_tiles
	_edges = p_edges
	_recompute_bounds()


static func compare_tile_coords(a: Vector2i, b: Vector2i) -> int:
	if a.x < b.x:
		return -1
	if a.x > b.x:
		return 1
	if a.y < b.y:
		return -1
	if a.y > b.y:
		return 1
	return 0


static func normalized_edge_key(a: Vector2i, b: Vector2i) -> String:
	var min_tile := a
	var max_tile := b
	if compare_tile_coords(a, b) > 0:
		min_tile = b
		max_tile = a
	return "%d,%d|%d,%d" % [min_tile.x, min_tile.y, max_tile.x, max_tile.y]


static func parse_edge_key(key: String) -> Array:
	var parts := key.split("|")
	if parts.size() != 2:
		push_error("invalid edge key: %s" % key)
		return []
	var a_parts := parts[0].split(",")
	var b_parts := parts[1].split(",")
	if a_parts.size() != 2 or b_parts.size() != 2:
		push_error("invalid edge key: %s" % key)
		return []
	return [Vector2i(int(a_parts[0]), int(a_parts[1])), Vector2i(int(b_parts[0]), int(b_parts[1]))]


func _recompute_bounds() -> void:
	if _tiles.is_empty():
		_bounds_q_min = 0
		_bounds_q_max = 0
		_bounds_r_min = 0
		_bounds_r_max = 0
		return
	var first := true
	for key in _tiles.keys():
		var coord: Vector2i = key
		if first:
			_bounds_q_min = coord.x
			_bounds_q_max = coord.x
			_bounds_r_min = coord.y
			_bounds_r_max = coord.y
			first = false
		else:
			_bounds_q_min = mini(_bounds_q_min, coord.x)
			_bounds_q_max = maxi(_bounds_q_max, coord.x)
			_bounds_r_min = mini(_bounds_r_min, coord.y)
			_bounds_r_max = maxi(_bounds_r_max, coord.y)


func has_tile(q: int, r: int) -> bool:
	return _tiles.has(Vector2i(q, r))


func has_tile_coord(coord: Vector2i) -> bool:
	return _tiles.has(coord)


func tile_at(q: int, r: int):
	var coord := Vector2i(q, r)
	if not _tiles.has(coord):
		push_error("WorldMap.tile_at: missing tile (%d,%d)" % [q, r])
		return null
	return _tiles[coord]


func tile_elevation(q: int, r: int) -> int:
	return tile_at(q, r).elevation


func tile_count() -> int:
	return _tiles.size()


func tile_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in _tiles.keys():
		out.append(key)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return compare_tile_coords(a, b) < 0
	)
	return out


func bounds_q() -> Vector2i:
	return Vector2i(_bounds_q_min, _bounds_q_max)


func bounds_r() -> Vector2i:
	return Vector2i(_bounds_r_min, _bounds_r_max)


func elevation_range() -> Vector2i:
	var min_e := 2147483647
	var max_e := -2147483648
	for tile in _tiles.values():
		min_e = mini(min_e, tile.elevation)
		max_e = maxi(max_e, tile.elevation)
	return Vector2i(min_e, max_e)


func has_edge_between(a: Vector2i, b: Vector2i) -> bool:
	return _edges.has(normalized_edge_key(a, b))


func edge_between(a: Vector2i, b: Vector2i):
	var key := normalized_edge_key(a, b)
	if not _edges.has(key):
		push_error("WorldMap.edge_between: missing edge")
		return null
	return _edges[key]


func edge_at_key(edge_key: String):
	if not _edges.has(edge_key):
		push_error("WorldMap.edge_at_key: missing edge %s" % edge_key)
		return null
	return _edges[edge_key]


func edge_count() -> int:
	return _edges.size()


func cliff_edge_count() -> int:
	var count := 0
	for edge in _edges.values():
		if edge.transition == EDGE_CLIFF:
			count += 1
	return count


func smooth_edge_count() -> int:
	return edge_count() - cliff_edge_count()


func edges_for_tile(q: int, r: int) -> Array:
	var coord := Vector2i(q, r)
	var out: Array = []
	for edge in _edges.values():
		if edge.tile_a == coord or edge.tile_b == coord:
			out.append(edge)
	out.sort_custom(func(a, b) -> bool:
		return normalized_edge_key(a.tile_a, a.tile_b) < normalized_edge_key(b.tile_a, b.tile_b)
	)
	return out


func all_edges() -> Array:
	var out: Array = []
	for edge in _edges.values():
		out.append(edge)
	out.sort_custom(func(a, b) -> bool:
		return normalized_edge_key(a.tile_a, a.tile_b) < normalized_edge_key(b.tile_a, b.tile_b)
	)
	return out
