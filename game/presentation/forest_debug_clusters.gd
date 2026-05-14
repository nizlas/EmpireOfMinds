# Presentation: fixed disjoint PLAINS forest clusters for **FOREST_CLUSTER_DEBUG** mode.
# Axial (q, r) per [docs/HEX_COORDINATES.md](docs/HEX_COORDINATES.md). Hex lists are authored in **`PrototypePlainsClusters`** (domain); this class forwards primitives and keeps presentation/debug **geometry diagnostics** unchanged.
extends RefCounted
class_name ForestDebugClusters

const Proto = preload("res://domain/prototype_plains_clusters.gd")

const CANONICAL_WATER_Q: int = Proto.CANONICAL_WATER_Q
const CANONICAL_WATER_R: int = Proto.CANONICAL_WATER_R


static func cluster_groups() -> Array:
	return Proto.cluster_groups()


static func axial_hex_distance(a: Vector2i, b: Vector2i) -> int:
	return Proto.axial_hex_distance(a, b)


static func all_cluster_hexes_sorted() -> Array[Vector2i]:
	return Proto.all_cluster_hexes_sorted()


static func is_cluster_hex(q: int, r: int) -> bool:
	return Proto.is_cluster_hex(q, r)


static func cluster_cell_count_total() -> int:
	return Proto.all_cluster_hexes_sorted().size()


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
