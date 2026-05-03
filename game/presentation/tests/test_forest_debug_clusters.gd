# Headless: **ForestDebugClusters** geometry vs **`HexMap.make_prototype_play_map`**. [Phase B]
# Usage: godot --headless --path game -s res://presentation/tests/test_forest_debug_clusters.gd
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ForestDebugClustersScript = preload("res://presentation/forest_debug_clusters.gd")


func _init() -> void:
	var groups: Array = ForestDebugClustersScript.cluster_groups()
	var expect_sizes: Array[int] = [1, 2, 3, 5, 10]
	if groups.size() != expect_sizes.size():
		push_error("FAIL: cluster group count")
		call_deferred("quit", 1)
		return
	var gi: int = 0
	while gi < groups.size():
		var cells = groups[gi] as Array
		if cells.size() != expect_sizes[gi]:
			push_error(
				"FAIL: cluster %d size expected %d got %d"
				% [gi, expect_sizes[gi], cells.size()]
			)
			call_deferred("quit", 1)
			return
		gi += 1
	if ForestDebugClustersScript.cluster_cell_count_total() != 21:
		push_error("FAIL: total cluster hexes expected 21")
		call_deferred("quit", 1)
		return
	if not ForestDebugClustersScript.each_cluster_is_contiguous():
		push_error("FAIL: cluster not contiguous")
		call_deferred("quit", 1)
		return
	if not ForestDebugClustersScript.clusters_are_disjoint():
		push_error("FAIL: clusters overlap")
		call_deferred("quit", 1)
		return
	var min_d: int = ForestDebugClustersScript.min_distance_between_distinct_clusters()
	if min_d < 2:
		push_error("FAIL: min inter-cluster distance expected >=2 got %d" % min_d)
		call_deferred("quit", 1)
		return

	var pmap = HexMapScript.make_prototype_play_map()
	var wq: int = ForestDebugClustersScript.CANONICAL_WATER_Q
	var wr: int = ForestDebugClustersScript.CANONICAL_WATER_R
	var all_k: Array[Vector2i] = ForestDebugClustersScript.all_cluster_hexes_sorted()
	var ai: int = 0
	while ai < all_k.size():
		var v: Vector2i = all_k[ai]
		var hc = HexCoordScript.new(v.x, v.y)
		if not pmap.has(hc):
			push_error("FAIL: cluster hex (%d,%d) not on prototype map" % [v.x, v.y])
			call_deferred("quit", 1)
			return
		if int(pmap.terrain_at(hc)) != HexMapScript.Terrain.PLAINS:
			push_error("FAIL: cluster hex (%d,%d) must be PLAINS" % [v.x, v.y])
			call_deferred("quit", 1)
			return
		if v.x == wq and v.y == wr:
			push_error("FAIL: cluster must not use water tile")
			call_deferred("quit", 1)
			return
		ai += 1

	print("PASS test_forest_debug_clusters")
	call_deferred("quit", 0)
