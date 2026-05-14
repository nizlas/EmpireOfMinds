# Domain: fixed disjoint PLAINS forest-cluster hexes for the prototype play map (see MAP_MODEL / phase 5.1.16g.2).
# Axial (q, r) per docs/HEX_COORDINATES.md. Shared by **`HexMap._proto_paint_land_terrain`** (keep clusters PLAINS) and presentation (**`ForestDebugClusters`** wraps these APIs).
extends RefCounted
class_name PrototypePlainsClusters

const CANONICAL_WATER_Q: int = -1
const CANONICAL_WATER_R: int = 0


## Clusters of sizes **1, 2, 3, 5, 10** — each internally contiguous; mutually disjoint;
## min pairwise hex distance between clusters **≥ 2**; all on **`HexMap.make_prototype_play_map()`** (5.1.16g.2 **corrected**: **g.1** curated core + explicit extensions).
static func cluster_groups() -> Array:
	return [
		[Vector2i(0, -1)],
		[Vector2i(2, -2), Vector2i(3, -2)],
		[Vector2i(5, 0), Vector2i(6, 0), Vector2i(5, 1)],
		[
			Vector2i(-1, 2),
			Vector2i(0, 2),
			Vector2i(1, 2),
			Vector2i(0, 3),
			Vector2i(1, 3),
		],
		[
			Vector2i(6, 2),
			Vector2i(6, 3),
			Vector2i(7, 3),
			Vector2i(8, 2),
			Vector2i(8, 3),
			Vector2i(9, 2),
			Vector2i(9, 3),
			Vector2i(9, 4),
			Vector2i(10, 3),
			Vector2i(10, 4),
		],
	]


static func axial_hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)


static func all_cluster_hexes_sorted() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	var groups: Array = cluster_groups()
	var gi: int = 0
	while gi < groups.size():
		var cells = groups[gi] as Array
		var ci: int = 0
		while ci < cells.size():
			var v: Vector2i = cells[ci]
			var key: String = "%d,%d" % [v.x, v.y]
			if not seen.has(key):
				seen[key] = true
				out.append(v)
			ci += 1
		gi += 1
	out.sort_custom(
		func(va: Vector2i, vb: Vector2i) -> bool:
			if va.x != vb.x:
				return va.x < vb.x
			return va.y < vb.y
	)
	return out


static func is_cluster_hex(q: int, r: int) -> bool:
	var groups: Array = cluster_groups()
	var gi: int = 0
	while gi < groups.size():
		var cells = groups[gi] as Array
		var ci: int = 0
		while ci < cells.size():
			var v: Vector2i = cells[ci]
			if v.x == q and v.y == r:
				return true
			ci += 1
		gi += 1
	return false

