# Presentation-only: fixed disjoint PLAINS forest clusters for **FOREST_CLUSTER_DEBUG** mode.
# Axial (q, r) per [docs/HEX_COORDINATES.md](docs/HEX_COORDINATES.md). Not domain gameplay state.
extends RefCounted
class_name ForestDebugClusters

const CANONICAL_WATER_Q: int = -1
const CANONICAL_WATER_R: int = 0

## Clusters of sizes **1, 2, 3, 5, 10** — each internally contiguous; mutually disjoint;
## min pairwise hex distance between clusters **≥ 2**; all in **`HexMap.make_prototype_play_map()`** (R=5).
static func cluster_groups() -> Array:
	return [
		[Vector2i(0, -4)],
		[Vector2i(3, -4), Vector2i(4, -4)],
		[Vector2i(-3, -2), Vector2i(-2, -2), Vector2i(-3, -1)],
		[Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 0), Vector2i(4, -1), Vector2i(3, 1)],
		[
			Vector2i(0, 3),
			Vector2i(1, 3),
			Vector2i(-1, 3),
			Vector2i(1, 2),
			Vector2i(-1, 4),
			Vector2i(0, 2),
			Vector2i(0, 4),
			Vector2i(-1, 2),
			Vector2i(-2, 4),
			Vector2i(1, 4),
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


static func cluster_cell_count_total() -> int:
	return all_cluster_hexes_sorted().size()


## **True** when every cluster is connected via axial neighbors (6 directions).
static func each_cluster_is_contiguous() -> bool:
	var neigh: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
	]
	var groups: Array = cluster_groups()
	var gi: int = 0
	while gi < groups.size():
		var cells = groups[gi] as Array
		if cells.size() <= 1:
			gi += 1
			continue
		var cell_set: Dictionary = {}
		var ci: int = 0
		while ci < cells.size():
			var v: Vector2i = cells[ci]
			cell_set["%d,%d" % [v.x, v.y]] = true
			ci += 1
		var start: Vector2i = cells[0]
		var visited: Dictionary = {}
		var stack: Array[Vector2i] = [start]
		while stack.size() > 0:
			var cur: Vector2i = stack.pop_back()
			var ck: String = "%d,%d" % [cur.x, cur.y]
			if visited.has(ck):
				continue
			visited[ck] = true
			var ni: int = 0
			while ni < 6:
				var nxt: Vector2i = Vector2i(cur.x + neigh[ni].x, cur.y + neigh[ni].y)
				if cell_set.has("%d,%d" % [nxt.x, nxt.y]) and not visited.has("%d,%d" % [nxt.x, nxt.y]):
					stack.append(nxt)
				ni += 1
		if visited.size() != cells.size():
			return false
		gi += 1
	return true


static func clusters_are_disjoint() -> bool:
	var seen: Dictionary = {}
	var groups: Array = cluster_groups()
	var gi: int = 0
	while gi < groups.size():
		var cells = groups[gi] as Array
		var ci: int = 0
		while ci < cells.size():
			var v: Vector2i = cells[ci]
			var key: String = "%d,%d" % [v.x, v.y]
			if seen.has(key):
				return false
			seen[key] = true
			ci += 1
		gi += 1
	return true


## Minimum axial distance between any hex in cluster **i** and any hex in cluster **j**, **i < j**.
static func min_distance_between_distinct_clusters() -> int:
	var groups: Array = cluster_groups()
	var best: int = 999999
	var i: int = 0
	while i < groups.size():
		var ci = groups[i] as Array
		var j: int = i + 1
		while j < groups.size():
			var cj = groups[j] as Array
			var ai: int = 0
			while ai < ci.size():
				var v_a: Vector2i = ci[ai]
				var bj: int = 0
				while bj < cj.size():
					var v_b: Vector2i = cj[bj]
					var d: int = axial_hex_distance(v_a, v_b)
					if d < best:
						best = d
					bj += 1
				ai += 1
			j += 1
		i += 1
	return best
