# Finite hex map: which cells exist and a minimal terrain tag per cell. No units, no movement, no rendering.
# See docs/MAP_MODEL.md (repo) and res://domain/README.md
class_name HexMap
extends RefCounted

# Parse-time: do not rely on Godot class_name global cache (headless -s may load in any order).
const _HexCoordT = preload("res://domain/hex_coord.gd")
# Same file; avoids self-reference to global class name HexMap in static make_tiny_test_map.
const _HEX_MAP_SCRIPT = preload("res://domain/hex_map.gd")
const _PROTOTYPE_TERRAIN_FEATURES = preload("res://domain/prototype_terrain_features.gd")

## Tag only in Phase 1.2 — no movement cost, visibility, or resources.
## Append-only: existing enum values stay stable.
enum Terrain { PLAINS, WATER, GRASSLAND }

## Visual / data only — not interpreted by movement rules in the current slice.
enum Landform { FLAT, HILLS }

var _cells: Dictionary
var _landforms: Dictionary
## Phase 5.1.16c — axial `Vector2i` keys with **woods** overlay (v0 yields); not a Terrain enum value.
var _woods: Dictionary


func _init(cells: Dictionary = {}, landforms: Dictionary = {}, woods: Dictionary = {}) -> void:
	# Shallow copy: caller cannot mutate the map after construction via the same dict reference.
	_cells = cells.duplicate()
	_landforms = landforms.duplicate()
	_woods = woods.duplicate()

func has(coord: _HexCoordT) -> bool:
	return _cells.has(Vector2i(coord.q, coord.r))

func terrain_at(coord: _HexCoordT) -> int:
	assert(has(coord), "terrain_at called for missing coordinate")
	return _cells[Vector2i(coord.q, coord.r)]

func landform_at(coord: _HexCoordT) -> int:
	assert(has(coord), "landform_at called for missing coordinate")
	var k: Vector2i = Vector2i(coord.q, coord.r)
	if not _landforms.has(k):
		return Landform.FLAT
	return int(_landforms[k])


func has_woods(coord: _HexCoordT) -> bool:
	assert(has(coord), "has_woods called for missing coordinate")
	return _woods.has(Vector2i(coord.q, coord.r))


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

## Phase 4.5l — larger axial disk for editor pan / perspective testing. Tests keep `make_tiny_test_map` (7 cells).
## R = 7 → 169 cells. Hand-authored sectors; (-1,0) and a small lake are WATER; (0,0) PLAINS + FLAT.
static func make_prototype_play_map():
	var R: int = 7
	var lake: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(-2, 0),
		Vector2i(-2, 1),
		Vector2i(-1, -1),
		Vector2i(-3, 0),
	]
	var lake_set: Dictionary = {}
	for h in lake:
		lake_set[h] = true
	var c: Dictionary = {}
	var lf: Dictionary = {}
	var q: int = -R
	while q <= R:
		var r: int = -R
		while r <= R:
			var dist: int = (abs(q) + abs(r) + abs(q + r)) / 2
			if dist <= R:
				if q == 0 and r == 0:
					c[Vector2i(q, r)] = Terrain.PLAINS
				elif lake_set.has(Vector2i(q, r)):
					c[Vector2i(q, r)] = Terrain.WATER
				elif q + r > 0 and q >= 0:
					c[Vector2i(q, r)] = Terrain.GRASSLAND
				elif q + r < 0 and q <= 0:
					c[Vector2i(q, r)] = Terrain.PLAINS
				elif q > 0 and q + r <= 0:
					c[Vector2i(q, r)] = Terrain.PLAINS
					lf[Vector2i(q, r)] = Landform.HILLS
				elif q < 0 and q + r >= 0:
					c[Vector2i(q, r)] = Terrain.GRASSLAND
					lf[Vector2i(q, r)] = Landform.HILLS
				else:
					c[Vector2i(q, r)] = Terrain.PLAINS
			r = r + 1
		q = q + 1
	return _HEX_MAP_SCRIPT.new(c, lf, _PROTOTYPE_TERRAIN_FEATURES.prototype_woods_set())
