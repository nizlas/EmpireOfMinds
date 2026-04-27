# Finite hex map: which cells exist and a minimal terrain tag per cell. No units, no movement, no rendering.
# See docs/MAP_MODEL.md (repo) and res://domain/README.md
class_name HexMap
extends RefCounted

# Parse-time: do not rely on Godot class_name global cache (headless -s may load in any order).
const _HexCoordT = preload("res://domain/hex_coord.gd")
# Same file; avoids self-reference to global class name HexMap in static make_tiny_test_map.
const _HEX_MAP_SCRIPT = preload("res://domain/hex_map.gd")

## Tag only in Phase 1.2 — no movement cost, visibility, or resources.
enum Terrain { PLAINS, WATER }

var _cells: Dictionary

func _init(cells: Dictionary = {}) -> void:
	# Shallow copy: caller cannot mutate the map after construction via the same dict reference.
	_cells = cells.duplicate()

func has(coord: _HexCoordT) -> bool:
	return _cells.has(Vector2i(coord.q, coord.r))

func terrain_at(coord: _HexCoordT) -> int:
	assert(has(coord), "terrain_at called for missing coordinate")
	return _cells[Vector2i(coord.q, coord.r)]

func size() -> int:
	return _cells.size()

## All hex coordinates in this map. Public API is HexCoord only; internal keys remain Vector2i. Iteration order is unspecified; do not rely on order unless a future phase documents it.
func coords() -> Array:
	var out: Array = []
	for k in _cells:
		var vi: Vector2i = k
		out.append(_HexCoordT.new(vi.x, vi.y))
	return out

static func make_tiny_test_map():
	# 7 cells: center and six neighbors; one WATER tile. Canonical fixture for tests and later phases.
	var c := {
		Vector2i(0, 0): Terrain.PLAINS,
		Vector2i(1, 0): Terrain.PLAINS, # E
		Vector2i(1, -1): Terrain.PLAINS, # NE
		Vector2i(0, -1): Terrain.PLAINS, # NW
		Vector2i(-1, 0): Terrain.WATER, # W
		Vector2i(-1, 1): Terrain.PLAINS, # SW
		Vector2i(0, 1): Terrain.PLAINS, # SE
	}
	# new(c) is not available from static in GDScript; self-preload avoids global "HexMap" at compile time.
	return _HEX_MAP_SCRIPT.new(c)
