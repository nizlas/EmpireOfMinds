# Finite hex map: which cells exist and a minimal terrain tag per cell. No units, no movement, no rendering.
# See docs/MAP_MODEL.md (repo) and res://domain/README.md
class_name HexMap
extends RefCounted

# Parse-time: do not rely on Godot class_name global cache (headless -s may load in any order).
const _HexCoordT = preload("res://domain/hex_coord.gd")
# Same file; avoids self-reference at static scope for `make_tiny_test_map`.
const _HEX_MAP_SCRIPT = preload("res://domain/hex_map.gd")
const _PROTOTYPE_TERRAIN_FEATURES = preload("res://domain/prototype_terrain_features.gd")
const _PrototypePlainsClusters = preload("res://domain/prototype_plains_clusters.gd")

const _PROTO_AX_NEI: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

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
	return _HEX_MAP_SCRIPT.new(c)

static func _proto_axial_dist(q: int, r: int, aq: int, ar: int) -> int:
	return int(abs(q - aq) + abs(r - ar) + abs(q + r - aq - ar)) / 2


## Must match HexLayout.SIZE in `game/presentation/hex_layout.gd` (128.0): world-space padding for the prototype sea shell.
const _PROTO_LAYOUT_HEX_SIZE: float = 128.0
## World-axis-aligned sea frame: ~this many neighbor steps beyond the land AABB (pointy-top spacing on X and Y).
const _PROTO_VIS_WATER_SHELL_PAD_STEPS: int = 3


static func _proto_hex_center_world(q: int, r: int) -> Vector2:
	var x: float = _PROTO_LAYOUT_HEX_SIZE * sqrt(3.0) * (float(q) + float(r) / 2.0)
	var y: float = _PROTO_LAYOUT_HEX_SIZE * 1.5 * float(r)
	return Vector2(x, y)


static func _proto_hex_world_aabb_xy(q: int, r: int) -> Rect2:
	var center: Vector2 = _proto_hex_center_world(q, r)
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var degs: Array = [30, 90, 150, 210, 270, 330]
	var di: int = 0
	while di < 6:
		var rad: float = deg_to_rad(float(degs[di]))
		var px: float = center.x + cos(rad) * _PROTO_LAYOUT_HEX_SIZE
		var py: float = center.y + sin(rad) * _PROTO_LAYOUT_HEX_SIZE
		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
		min_y = minf(min_y, py)
		max_y = maxf(max_y, py)
		di += 1
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


static func _proto_land_world_rect(land: Dictionary) -> Rect2:
	var first: bool = true
	var acc: Rect2 = Rect2()
	for k in land.keys():
		var hb: Rect2 = _proto_hex_world_aabb_xy(k.x, k.y)
		if first:
			acc = hb
			first = false
		else:
			acc = acc.merge(hb)
	return acc


static func _proto_expand_world_rect_pad_hex_steps(r: Rect2, steps: int) -> Rect2:
	var pad_x: float = float(steps) * sqrt(3.0) * _PROTO_LAYOUT_HEX_SIZE
	var pad_y: float = float(steps) * 1.5 * _PROTO_LAYOUT_HEX_SIZE
	return Rect2(
		r.position.x - pad_x,
		r.position.y - pad_y,
		r.size.x + 2.0 * pad_x,
		r.size.y + 2.0 * pad_y,
	)


## Sea shell from **base land** only (Phase **5.2.4l**): fill an **axis-aligned world rectangle** around the land footprint with **real** WATER cells (no presentation filler). Single deterministic pass.
static func _proto_add_world_axis_rect_water_shell(land: Dictionary, c: Dictionary) -> void:
	var inner: Rect2 = _proto_land_world_rect(land)
	var outer: Rect2 = _proto_expand_world_rect_pad_hex_steps(inner, _PROTO_VIS_WATER_SHELL_PAD_STEPS)
	var q_lo: int = 2147483647
	var q_hi: int = -2147483648
	var r_lo: int = 2147483647
	var r_hi: int = -2147483648
	for k in land.keys():
		q_lo = mini(q_lo, k.x)
		q_hi = maxi(q_hi, k.x)
		r_lo = mini(r_lo, k.y)
		r_hi = maxi(r_hi, k.y)
	var span: int = 12 + _PROTO_VIS_WATER_SHELL_PAD_STEPS * 4
	var q: int = q_lo - span
	while q <= q_hi + span:
		var r: int = r_lo - span
		while r <= r_hi + span:
			var kk := Vector2i(q, r)
			if land.has(kk):
				r += 1
				continue
			var hb: Rect2 = _proto_hex_world_aabb_xy(q, r)
			if outer.intersects(hb):
				c[kk] = Terrain.WATER
			r += 1
		q += 1


## Test/support: curated **land** key set for **`make_prototype_play_map()`** before the perimeter WATER shell (same dict as internal flood result).
static func prototype_play_land_key_set() -> Dictionary:
	return _proto_collect_land_keys()


## World-axis target rectangle (**expanded land AABB** + **`_PROTO_VIS_WATER_SHELL_PAD_STEPS`** on X/Y) used for the prototype sea shell — for tests / docs alignment with **HexLayout** space.
static func prototype_play_target_sea_world_rect() -> Rect2:
	return _proto_expand_world_rect_pad_hex_steps(
		_proto_land_world_rect(prototype_play_land_key_set()),
		_PROTO_VIS_WATER_SHELL_PAD_STEPS,
	)


## Phase 5.1.16g.1 lineage: west strait + bay bites (see MAP_MODEL). Keys are **removed** from dry land before the NE/S extensions stitch on.
static func _proto_lake_strait_dict() -> Dictionary:
	var d: Dictionary = {}
	for v in [
		Vector2i(-1, 0),
		Vector2i(-2, 0),
		Vector2i(-2, 1),
		Vector2i(-1, -1),
		Vector2i(-3, 0),
	]:
		d[v] = true
	return d


static func _proto_nw_bay_dict() -> Dictionary:
	var d: Dictionary = {}
	for v in [
		Vector2i(-4, 3),
		Vector2i(-3, 3),
		Vector2i(-2, 3),
		Vector2i(-4, 2),
		Vector2i(-5, 4),
		Vector2i(-4, 4),
		Vector2i(-6, 4),
		Vector2i(-4, 5),
		Vector2i(-5, 3),
		# Extra inlet: keeps NW coast interesting without disconnecting the g.1 core.
		Vector2i(-3, 4),
		Vector2i(-5, 2),
	]:
		d[v] = true
	return d


## Optional shallow chops — **keep empty** unless every key is validated on the flooded island (easy to disconnect extensions).
static func _proto_coastal_chop_dict() -> Dictionary:
	return {}


## Curated **additions** to the axial disk(g.1): NE tongue, E ridge hill chain, SE warmer shelf — explicit coords (no macro blobs).
static func _proto_island_extension_hexes() -> Array[Vector2i]:
	return [
		# E — production ridge / 2nd city seam (connects from core edge (5,0)/(4,-1)…)
		Vector2i(5, -2),
		Vector2i(5, -1),
		Vector2i(6, -2),
		Vector2i(6, -1),
		Vector2i(7, -2),
		Vector2i(7, -1),
		Vector2i(8, -2),
		Vector2i(8, -1),
		Vector2i(4, -2),
		Vector2i(5, -3),
		Vector2i(6, -3),
		Vector2i(7, -3),
		# NE bridge + waist
		Vector2i(5, 1),
		Vector2i(5, 2),
		Vector2i(6, 0),
		Vector2i(6, 1),
		Vector2i(6, 2),
		Vector2i(7, 0),
		Vector2i(7, 1),
		Vector2i(7, 2),
		Vector2i(7, 3),
		Vector2i(8, 1),
		Vector2i(8, 0),
		Vector2i(9, 0),
		Vector2i(9, 1),
		Vector2i(10, 1),
		Vector2i(10, 2),
		Vector2i(11, 2),
		Vector2i(11, 3),
		Vector2i(8, 2),
		Vector2i(8, 3),
		Vector2i(8, 4),
		Vector2i(8, 5),
		Vector2i(8, 6),
		Vector2i(9, 2),
		Vector2i(9, 3),
		Vector2i(9, 4),
		Vector2i(9, 5),
		Vector2i(9, 6),
		Vector2i(9, 7),
		Vector2i(10, 3),
		Vector2i(10, 4),
		Vector2i(10, 5),
		Vector2i(10, 6),
		Vector2i(10, 7),
		Vector2i(11, 4),
		Vector2i(11, 5),
		Vector2i(11, 6),
		Vector2i(11, 7),
		Vector2i(11, 8),
		Vector2i(12, 5),
		Vector2i(12, 6),
		Vector2i(12, 7),
		Vector2i(12, 8),
		Vector2i(13, 6),
		Vector2i(13, 7),
		# Inland NE bowl + tongue shoulder (avoid accidental WATER-only ring coords like **(7,7)**)
		Vector2i(6, 5),
		Vector2i(6, 6),
		Vector2i(6, 7),
		Vector2i(7, 5),
		Vector2i(7, 6),
		Vector2i(7, 7),
		Vector2i(8, 7),
		Vector2i(10, 8),
		Vector2i(9, 8),
		# SE / south agricultural shelf
		Vector2i(4, 2),
		Vector2i(4, 3),
		Vector2i(3, 3),
		Vector2i(3, 4),
		Vector2i(2, 4),
		Vector2i(2, 5),
		Vector2i(1, 4),
		Vector2i(0, 4),
		Vector2i(5, 3),
		Vector2i(5, 4),
		Vector2i(6, 3),
		Vector2i(6, 4),
	]


static func _proto_g1_core_candidates(lake: Dictionary, bay: Dictionary, chop: Dictionary) -> Dictionary:
	var cand: Dictionary = {}
	var q: int = -6
	while q <= 6:
		var r: int = -6
		while r <= 6:
			var k := Vector2i(q, r)
			if _proto_axial_dist(q, r, 0, 0) <= 6:
				# Soft clip: still reads as **g.1 disk lineage**, not a clean R=6 circle.
				if q <= -5 and r >= 5:
					r += 1
					continue
				if q >= 7 and r <= -5:
					r += 1
					continue
				if not lake.has(k) and not bay.has(k) and not chop.has(k):
					cand[k] = true
			r += 1
		q += 1
	return cand


static func _proto_merge_candidates(
	core: Dictionary, ext: Array[Vector2i], chop: Dictionary
) -> Dictionary:
	var cand: Dictionary = core.duplicate()
	var i: int = 0
	while i < ext.size():
		var k: Vector2i = ext[i]
		if not chop.has(k):
			cand[k] = true
		i += 1
	return cand


static func _proto_flood_component(candidates: Dictionary) -> Dictionary:
	var land: Dictionary = {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	if not candidates.has(Vector2i(0, 0)):
		return land
	while stack.size() > 0:
		var cur: Vector2i = stack.pop_back()
		if land.has(cur):
			continue
		if not candidates.has(cur):
			continue
		land[cur] = true
		var ni: int = 0
		while ni < 6:
			stack.append(Vector2i(cur.x + _PROTO_AX_NEI[ni].x, cur.y + _PROTO_AX_NEI[ni].y))
			ni += 1
	return land


## Phase 5.1.16g.2 **corrected:** extend the **5.1.16g.1** curated disk + explicit NE/SE anchors; mixed terrain; **full** perimeter **WATER** (no distance-trimmed “open” coast).
static func _proto_collect_land_keys() -> Dictionary:
	var lake: Dictionary = _proto_lake_strait_dict()
	var bay: Dictionary = _proto_nw_bay_dict()
	var chop: Dictionary = _proto_coastal_chop_dict()
	var core: Dictionary = _proto_g1_core_candidates(lake, bay, chop)
	var ext: Array[Vector2i] = _proto_island_extension_hexes()
	var cand: Dictionary = _proto_merge_candidates(core, ext, chop)
	return _proto_flood_component(cand)


static func _paint_grass_flat(land: Dictionary, c: Dictionary, lf: Dictionary, cells: Array[Vector2i]) -> void:
	for v in cells:
		if land.has(v):
			c[v] = Terrain.GRASSLAND
			lf.erase(v)


static func _paint_grass_hill(land: Dictionary, c: Dictionary, lf: Dictionary, cells: Array[Vector2i]) -> void:
	for v in cells:
		if land.has(v):
			c[v] = Terrain.GRASSLAND
			lf[v] = Landform.HILLS


static func _paint_plains_flat(land: Dictionary, c: Dictionary, lf: Dictionary, cells: Array[Vector2i]) -> void:
	for v in cells:
		if land.has(v):
			c[v] = Terrain.PLAINS
			lf.erase(v)


static func _paint_plains_hill(land: Dictionary, c: Dictionary, lf: Dictionary, cells: Array[Vector2i]) -> void:
	for v in cells:
		if land.has(v):
			c[v] = Terrain.PLAINS
			lf[v] = Landform.HILLS


static func _proto_paint_land_terrain(land: Dictionary, c: Dictionary, lf: Dictionary) -> void:
	# Baseline: **grass-forward** heartland (avoids giant plains carpets).
	for k in land.keys():
		c[k] = Terrain.GRASSLAND
		lf.erase(k)

	# NW / N food-leaning grass **hills** (patchy, not a sector sweep).
	_paint_grass_hill(
		land,
		c,
		lf,
		[
			Vector2i(-4, -1),
			Vector2i(-4, 0),
			Vector2i(-3, -1),
			Vector2i(-3, 0),
			Vector2i(-2, -1),
			Vector2i(-2, 0),
			Vector2i(-1, 1),
			Vector2i(0, 2),
			Vector2i(-1, 2),
			Vector2i(-2, 2),
			Vector2i(-3, 2),
			Vector2i(1, 1),
			Vector2i(1, 2),
			Vector2i(0, 3),
		]
	)

	# **Plains flats** — woods (prototype list, flat cells) + dry pockets + speckle (no sector carpet).
	_paint_plains_flat(
		land,
		c,
		lf,
		[
			Vector2i(-6, 0),
			Vector2i(-5, -1),
			Vector2i(-4, -2),
			Vector2i(-4, 0),
			Vector2i(-5, 1),
			Vector2i(-4, 1),
			Vector2i(-3, -1),
			Vector2i(-3, 1),
			Vector2i(-2, 2),
			Vector2i(0, -3),
			Vector2i(1, -1),
			Vector2i(1, -3),
			Vector2i(1, -2),
			Vector2i(2, -3),
			Vector2i(2, 0),
			Vector2i(3, -1),
			Vector2i(2, 3),
			Vector2i(3, -3),
			Vector2i(3, 2),
			Vector2i(4, -3),
			Vector2i(4, -1),
			Vector2i(2, -2),
			Vector2i(4, -4),
			Vector2i(5, -3),
			Vector2i(5, 3),
			Vector2i(5, 4),
			Vector2i(6, 5),
			Vector2i(0, 4),
			Vector2i(6, 4),
			Vector2i(7, 0),
			Vector2i(7, 1),
			Vector2i(7, 5),
			Vector2i(8, 0),
			Vector2i(8, 1),
			Vector2i(8, 4),
			Vector2i(9, 4),
			Vector2i(4, 1),
			Vector2i(10, 2),
			Vector2i(10, 5),
			Vector2i(10, 6),
			Vector2i(11, 2),
			Vector2i(11, 4),
			Vector2i(11, 5),
			Vector2i(11, 6),
			Vector2i(12, 6),
			Vector2i(12, 8),
			Vector2i(13, 6),
			Vector2i(13, 7),
			Vector2i(0, 5),
			Vector2i(1, 4),
		]
	)

	# **Plains hills** — production-forward **fragments** + woods on **PLAINS·HILLS** (explicit lists only).
	_paint_plains_hill(
		land,
		c,
		lf,
		[
			Vector2i(-4, -1),
			Vector2i(4, -2),
			Vector2i(5, -2),
			Vector2i(6, -2),
			Vector2i(6, -3),
			Vector2i(7, -3),
			Vector2i(7, -2),
			Vector2i(5, -1),
			Vector2i(6, -1),
			Vector2i(7, -1),
			Vector2i(8, -1),
			Vector2i(8, -2),
			Vector2i(10, 3),
			Vector2i(11, 3),
			Vector2i(9, 6),
			Vector2i(9, 7),
			Vector2i(10, 4),
		]
	)

	# SE / tongue grass hills (rolling coastal hinterland; **(7,5)** left **PLAINS** for woods).
	_paint_grass_hill(
		land,
		c,
		lf,
		[
			Vector2i(4, 2),
			Vector2i(4, 3),
			Vector2i(3, 4),
			Vector2i(2, 5),
			Vector2i(5, 3),
			Vector2i(5, 2),
			Vector2i(6, 3),
			Vector2i(7, 3),
			Vector2i(7, 4),
			Vector2i(8, 5),
			Vector2i(8, 6),
			Vector2i(9, 7),
			Vector2i(10, 7),
			Vector2i(11, 7),
			Vector2i(11, 8),
			Vector2i(1, 3),
			Vector2i(2, 2),
			Vector2i(3, 5),
			Vector2i(8, 3),
			Vector2i(9, 3),
			Vector2i(-1, -3),
			Vector2i(2, 1),
			Vector2i(1, 5),
			Vector2i(-1, -2),
		]
	)

	# Anchor specials (capital pocket + tree + P1 arrival bowl).
	var center := Vector2i(0, 0)
	_paint_plains_flat(land, c, lf, [center])
	var cap_e := Vector2i(1, 0)
	_paint_grass_flat(land, c, lf, [cap_e])
	var tree := Vector2i(3, 0)
	_paint_grass_flat(land, c, lf, [tree])
	var p1 := Vector2i(9, 5)
	_paint_grass_flat(land, c, lf, [p1])

	# Coastal **founding** candidate — mostly grass flat near water+bays.
	_paint_grass_flat(land, c, lf, [Vector2i(-1, 3), Vector2i(-2, 4)])

	# Forest-debug review patches must remain **PLAINS** flats (presentation headless tests).
	var dbg: Array[Vector2i] = _PrototypePlainsClusters.all_cluster_hexes_sorted()
	var di: int = 0
	while di < dbg.size():
		var dv: Vector2i = dbg[di]
		if land.has(dv):
			_paint_plains_flat(land, c, lf, [dv])
		di += 1


static func make_prototype_play_map():
	var land: Dictionary = _proto_collect_land_keys()
	var c: Dictionary = {}
	var lf: Dictionary = {}
	_proto_paint_land_terrain(land, c, lf)
	_proto_add_world_axis_rect_water_shell(land, c)
	return _HEX_MAP_SCRIPT.new(c, lf, _PROTOTYPE_TERRAIN_FEATURES.prototype_woods_set())
