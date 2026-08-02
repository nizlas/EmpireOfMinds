# TS-08 Stage-0 cut-lattice topology (N3a). Domain-only; input is WorldMap.
# Spec: docs/TERRAIN_SURFACE_TARGET.md, content/terrain/reference/README.md
class_name Ts08CutLattice
extends RefCounted

const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")
const WorldMapScript = preload("res://domain/world/world_map.gd")

const EXPECTED_HEX_COUNT := 168
const EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT := 74129
const EXPECTED_CENTER_PIN_COUNT := 168
const EXPECTED_CLIFF_EDGE_COUNT := 78
const EXPECTED_TRIANGLE_COUNT := 145152
const EXPECTED_DUPLICATED_CLIFF_LINE_NODES := 861


class CornerRecord extends RefCounted:
	var world_xy_key: String
	var world_xy: Vector2
	var tiles: Array[Vector2i] = []
	var neighbor_pairs: Array = []
	var pair_deltas: Array[int] = []
	var cliff_incident_count: int = 0
	var case_id: int = -1
	var is_interior: bool = false
	var case1_cliff_delta: int = 0


class BuildResult extends RefCounted:
	var node_count: int = 0
	var adjacency: Array = []
	var node_keys: Array = []
	var node_sheet_ids: Array[int] = []
	var node_pos_keys: Array[Vector2] = []
	var node_plane_xy: Array[Vector2] = []
	var node_godot_xz: Array[Vector2] = []
	var pinned_world_y: Dictionary = {}
	var pin_hex_by_node: Dictionary = {}
	var component_ids: Array[int] = []
	var corner_sample_nodes: Dictionary = {}
	var tile_pos_to_node: Dictionary = {}
	var triangles: Array = []


static func build_from_world_map(
	world_map,
	subdiv: int = Ts08TerrainMathScript.DEFAULT_SURFACE_SUBDIVISIONS,
	radius: float = Ts08TerrainMathScript.DEFAULT_HEX_RADIUS
) -> BuildResult:
	var cliff_pairs := _build_cliff_neighbor_pairs(world_map)
	var cliff_physical := _build_cliff_physical_edges_by_tile(cliff_pairs)
	var sheet_lookup := _build_sheet_lookup(world_map)
	var corner_registry := _build_corner_registry(world_map, cliff_pairs, radius)
	var smooth_adjacency := _build_smooth_adjacency(world_map)
	var corner_smooth_components := _build_corner_smooth_component_lookup(
		corner_registry,
		smooth_adjacency
	)
	return _build_cut_lattice_topology(
		world_map,
		corner_registry,
		cliff_physical,
		sheet_lookup,
		cliff_pairs,
		corner_smooth_components,
		subdiv,
		radius
	)


static func audit_topology(build: BuildResult, cliff_pairs: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if build.node_count != EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT:
		failures.append(
			"node_count %d != %d" % [build.node_count, EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT]
		)
	if build.triangles.size() != EXPECTED_TRIANGLE_COUNT:
		failures.append(
			"triangle_count %d != %d" % [build.triangles.size(), EXPECTED_TRIANGLE_COUNT]
		)
	if build.pinned_world_y.size() != EXPECTED_CENTER_PIN_COUNT:
		failures.append(
			"center_pin_count %d != %d" % [build.pinned_world_y.size(), EXPECTED_CENTER_PIN_COUNT]
		)
	var duplicated := _count_duplicated_cliff_line_nodes(build)
	if duplicated != EXPECTED_DUPLICATED_CLIFF_LINE_NODES:
		failures.append(
			"duplicated_cliff_line_nodes %d != %d" % [duplicated, EXPECTED_DUPLICATED_CLIFF_LINE_NODES]
		)
	var cross_cliff := _audit_adjacency_cross_cliff(build)
	if cross_cliff > 0:
		failures.append("adjacency_cross_cliff_violations %d != 0" % cross_cliff)
	return {
		"passed": failures.is_empty(),
		"failures": failures,
		"duplicated_cliff_line_nodes": duplicated,
		"adjacency_cross_cliff_violations": cross_cliff,
	}


static func orient_triangle_y_up(
	positions: Array,
	a: int,
	b: int,
	c: int
) -> Array:
	var ax: float = positions[a].x
	var ay: float = positions[a].y
	var az: float = positions[a].z
	var bx: float = positions[b].x
	var by: float = positions[b].y
	var bz: float = positions[b].z
	var cx: float = positions[c].x
	var cy: float = positions[c].y
	var cz: float = positions[c].z
	var ab := Vector3(bx - ax, by - ay, bz - az)
	var ac := Vector3(cx - ax, cy - ay, cz - az)
	var ny: float = ab.z * ac.x - ab.x * ac.z
	if absf(ny) < 1e-12:
		return [a, b, c]
	if ny < 0.0:
		return [a, c, b]
	return [a, b, c]


static func encode_node_key(key: Variant) -> Array:
	if key is Array:
		var encoded: Array = []
		for part in key:
			if part is Vector2:
				encoded.append([part.x, part.y])
			elif part is Array and part.size() == 2 and (part[0] is float or part[0] is int):
				encoded.append([float(part[0]), float(part[1])])
			else:
				encoded.append(part)
		return encoded
	return [key]


static func _build_cliff_neighbor_pairs(world_map) -> Dictionary:
	var pairs: Dictionary = {}
	for edge in world_map.all_edges():
		if edge.transition != WorldMapScript.EDGE_CLIFF:
			continue
		var delta := absi(
			world_map.tile_at(edge.tile_a.x, edge.tile_a.y).elevation
			- world_map.tile_at(edge.tile_b.x, edge.tile_b.y).elevation
		)
		if delta > world_map.cliff_threshold:
			pairs[Ts08TerrainMathScript.cliff_pair_key(edge.tile_a, edge.tile_b)] = true
	return pairs


static func _build_cliff_physical_edges_by_tile(cliff_pairs: Dictionary) -> Dictionary:
	var by_tile: Dictionary = {}
	for key in cliff_pairs.keys():
		var parts: PackedStringArray = key.split("|")
		var a_parts: PackedStringArray = parts[0].split(",")
		var b_parts: PackedStringArray = parts[1].split(",")
		var tile_a := Vector2i(int(a_parts[0]), int(a_parts[1]))
		var tile_b := Vector2i(int(b_parts[0]), int(b_parts[1]))
		var edge_a := _physical_edge_for_neighbor_direction(
			_neighbor_direction_between(tile_a, tile_b)
		)
		var edge_b := _physical_edge_for_neighbor_direction(
			_neighbor_direction_between(tile_b, tile_a)
		)
		if not by_tile.has(tile_a):
			by_tile[tile_a] = {}
		if not by_tile.has(tile_b):
			by_tile[tile_b] = {}
		by_tile[tile_a][edge_a] = true
		by_tile[tile_b][edge_b] = true
	return by_tile


static func _build_sheet_lookup(world_map) -> Dictionary:
	var parent: Dictionary = {}
	for coord in world_map.tile_coords():
		parent[coord] = coord

	var find := func(start: Vector2i) -> Vector2i:
		var coord := start
		while parent[coord] != coord:
			parent[coord] = parent[parent[coord]]
			coord = parent[coord]
		return coord

	for edge in world_map.all_edges():
		if edge.transition != WorldMapScript.EDGE_SMOOTH:
			continue
		var ra: Vector2i = find.call(edge.tile_a)
		var rb: Vector2i = find.call(edge.tile_b)
		if ra != rb:
			parent[rb] = ra

	var groups: Dictionary = {}
	for coord in world_map.tile_coords():
		var root: Vector2i = find.call(coord)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(coord)

	var sorted_roots: Array = groups.keys()
	sorted_roots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Ts08TerrainMathScript.compare_tile_coords(a, b) < 0
	)
	var lookup: Dictionary = {}
	for domain_id in sorted_roots.size():
		for coord in groups[sorted_roots[domain_id]]:
			lookup[coord] = domain_id
	return lookup


static func _shared_hex_edge_endpoints(
	tile_a: Vector2i,
	tile_b: Vector2i,
	radius: float
) -> Array:
	var direction := _neighbor_direction_between(tile_a, tile_b)
	var edge_index := _physical_edge_for_neighbor_direction(direction)
	var c0 := edge_index
	var c1 := Ts08TerrainMathScript.positive_mod(edge_index + 1, 6)
	return [
		Ts08TerrainMathScript.pos_key_id(
			Ts08TerrainMathScript.handdrawn_corner_world_x(tile_a.x, tile_a.y, c0, radius),
			Ts08TerrainMathScript.handdrawn_corner_world_y(tile_a.x, tile_a.y, c0, radius)
		),
		Ts08TerrainMathScript.pos_key_id(
			Ts08TerrainMathScript.handdrawn_corner_world_x(tile_a.x, tile_a.y, c1, radius),
			Ts08TerrainMathScript.handdrawn_corner_world_y(tile_a.x, tile_a.y, c1, radius)
		),
	]


static func _build_corner_registry(world_map, cliff_pairs: Dictionary, radius: float) -> Array:
	var corner_tiles: Dictionary = {}
	for coord in world_map.tile_coords():
		for corner_index in range(6):
			var wx := Ts08TerrainMathScript.handdrawn_corner_world_x(
				coord.x, coord.y, corner_index, radius
			)
			var wy := Ts08TerrainMathScript.handdrawn_corner_world_y(
				coord.x, coord.y, corner_index, radius
			)
			var key := Ts08TerrainMathScript.pos_key_id(wx, wy)
			if not corner_tiles.has(key):
				corner_tiles[key] = {}
			corner_tiles[key][coord] = true

	var records: Array = []
	var sorted_keys: Array = corner_tiles.keys()
	sorted_keys.sort()
	for world_xy_key in sorted_keys:
		var tile_set: Dictionary = corner_tiles[world_xy_key]
		var tiles: Array[Vector2i] = []
		for coord in tile_set.keys():
			tiles.append(coord)
		tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Ts08TerrainMathScript.compare_tile_coords(a, b) < 0
		)
		var neighbor_pairs := _neighbor_pairs_at_corner(tiles, world_xy_key, radius)
		var pair_deltas: Array[int] = []
		var cliff_count := 0
		var case1_cliff_delta := 0
		for pair in neighbor_pairs:
			var ea: int = world_map.tile_at(pair[0].x, pair[0].y).elevation
			var eb: int = world_map.tile_at(pair[1].x, pair[1].y).elevation
			var delta := absi(ea - eb)
			pair_deltas.append(delta)
			if delta > world_map.cliff_threshold:
				cliff_count += 1
				case1_cliff_delta = delta
		var record := CornerRecord.new()
		record.world_xy_key = world_xy_key
		record.world_xy = Ts08TerrainMathScript.pos_key_from_id(world_xy_key)
		record.tiles = tiles
		record.neighbor_pairs = neighbor_pairs
		record.pair_deltas = pair_deltas
		record.cliff_incident_count = cliff_count
		record.is_interior = tiles.size() == 3 and neighbor_pairs.size() == 3
		record.case_id = cliff_count if record.is_interior else -1
		record.case1_cliff_delta = case1_cliff_delta if cliff_count == 1 else 0
		records.append(record)
	return records


static func _neighbor_pairs_at_corner(
	tiles: Array[Vector2i],
	corner_xy_key: String,
	radius: float
) -> Array:
	var tile_set: Dictionary = {}
	for tile in tiles:
		tile_set[tile] = true
	var pairs: Array = []
	var seen: Dictionary = {}
	for i in tiles.size():
		for j in tiles.size():
			if i >= j:
				continue
			var tile_a: Vector2i = tiles[i]
			var tile_b: Vector2i = tiles[j]
			if not _is_neighbor(tile_a, tile_b):
				continue
			var endpoints := _shared_hex_edge_endpoints(tile_a, tile_b, radius)
			var pk0: String = endpoints[0]
			var pk1: String = endpoints[1]
			if corner_xy_key != pk0 and corner_xy_key != pk1:
				continue
			var pair_key := Ts08TerrainMathScript.cliff_pair_key(tile_a, tile_b)
			if seen.has(pair_key):
				continue
			seen[pair_key] = true
			pairs.append([tile_a, tile_b])
	return pairs


static func _build_smooth_adjacency(world_map) -> Dictionary:
	var adjacency: Dictionary = {}
	for coord in world_map.tile_coords():
		adjacency[coord] = {}
	for edge in world_map.all_edges():
		if edge.transition != WorldMapScript.EDGE_SMOOTH:
			continue
		adjacency[edge.tile_a][edge.tile_b] = true
		adjacency[edge.tile_b][edge.tile_a] = true
	return adjacency


static func _build_corner_smooth_component_lookup(
	corner_registry: Array,
	smooth_adjacency: Dictionary
) -> Dictionary:
	var lookup: Dictionary = {}
	for corner in corner_registry:
		if not corner.is_interior or corner.case_id not in [2, 3]:
			continue
		var tile_to_component: Dictionary = {}
		var seen_tiles: Dictionary = {}
		var component_index := 0
		for tile in corner.tiles:
			if seen_tiles.has(tile):
				continue
			var component := _smooth_component_at_corner(tile, corner.tiles, smooth_adjacency)
			for member in component:
				tile_to_component[member] = component_index
				seen_tiles[member] = true
			component_index += 1
		lookup[corner.world_xy_key] = tile_to_component
	return lookup


static func _build_cut_lattice_topology(
	world_map,
	corner_registry: Array,
	cliff_physical: Dictionary,
	sheet_lookup: Dictionary,
	cliff_pairs: Dictionary,
	corner_smooth_components: Dictionary,
	subdiv: int,
	radius: float
) -> BuildResult:
	var corner_by_pos: Dictionary = {}
	for corner in corner_registry:
		corner_by_pos[corner.world_xy_key] = corner

	var merge_map: Dictionary = {}
	var merge_owner: Dictionary = {}
	var node_keys: Array = []
	var node_sheet_ids: Array[int] = []
	var node_pos_keys: Array[Vector2] = []
	var node_plane_xy: Array[Vector2] = []
	var adjacency_sets: Array = []
	var pinned: Dictionary = {}
	var pin_hex_by_node: Dictionary = {}
	var corner_sample_nodes: Dictionary = {}
	var tile_pos_to_node: Dictionary = {}
	var triangles: Array = []

	var hex_coords: Array[Vector2i] = world_map.tile_coords()

	var tiles_are_cliff_neighbors := func(tile_a: Vector2i, tile_b: Vector2i) -> bool:
		if tile_a == tile_b:
			return false
		return cliff_pairs.has(Ts08TerrainMathScript.cliff_pair_key(tile_a, tile_b))

	var create_node := func(
		key: Variant,
		pk_parts: Array,
		sheet_id: int,
		wx: float,
		wy: float
	) -> int:
		var index := adjacency_sets.size()
		merge_map[key] = index
		node_keys.append(key)
		node_sheet_ids.append(sheet_id)
		node_pos_keys.append(Vector2(float(pk_parts[0]), float(pk_parts[1])))
		node_plane_xy.append(Vector2(wx, wy))
		adjacency_sets.append({})
		return index

	var record_tile_lookup := func(index: int, pk_parts: Array, tile: Vector2i) -> int:
		var pk := Vector2(float(pk_parts[0]), float(pk_parts[1]))
		tile_pos_to_node[_tile_pos_key(pk, tile)] = index
		return index

	var node_id_for := func(
		wx: float,
		wy: float,
		q: int,
		r: int,
		sector: int,
		at_corner: bool,
		on_cliff_boundary: bool,
		_si: int,
		_sj: int
	) -> int:
		var tile := Vector2i(q, r)
		var sheet_id: int = sheet_lookup[tile]
		var pk_parts: Array = Ts08TerrainMathScript.pos_key_parts(wx, wy)
		var pk := Vector2(float(pk_parts[0]), float(pk_parts[1]))
		var corner_key := Ts08TerrainMathScript.pos_key_id(wx, wy)
		var corner: CornerRecord = corner_by_pos.get(corner_key)

		if at_corner and corner != null and corner.is_interior and corner.case_id == 1:
			var crack_key := ["crack_tip", pk_parts]
			if merge_map.has(crack_key):
				var existing: int = merge_map[crack_key]
				_add_corner_sample(corner_sample_nodes, pk, existing)
				return record_tile_lookup.call(existing, pk_parts, tile)
			var crack_index: int = create_node.call(crack_key, pk_parts, sheet_id, wx, wy)
			_add_corner_sample(corner_sample_nodes, pk, crack_index)
			return record_tile_lookup.call(crack_index, pk_parts, tile)

		if at_corner and corner != null and corner.is_interior and corner.case_id in [2, 3]:
			var component_id: int = corner_smooth_components[corner.world_xy_key][tile]
			var split_key := ["corner_split", pk_parts, component_id]
			if merge_map.has(split_key):
				var existing_split: int = merge_map[split_key]
				_add_corner_sample(corner_sample_nodes, pk, existing_split)
				return record_tile_lookup.call(existing_split, pk_parts, tile)
			var split_index: int = create_node.call(split_key, pk_parts, sheet_id, wx, wy)
			_add_corner_sample(corner_sample_nodes, pk, split_index)
			return record_tile_lookup.call(split_index, pk_parts, tile)

		if on_cliff_boundary:
			var cliff_key := ["cliff_line", pk_parts, sheet_id, q, r]
			if merge_map.has(cliff_key):
				return record_tile_lookup.call(merge_map[cliff_key], pk_parts, tile)
			var cliff_index: int = create_node.call(cliff_key, pk_parts, sheet_id, wx, wy)
			return record_tile_lookup.call(cliff_index, pk_parts, tile)

		var merge_key := [pk_parts, sheet_id]
		var tile_key: Variant
		if at_corner:
			tile_key = [pk_parts, sheet_id, q, r, sector]
		else:
			tile_key = [pk_parts, sheet_id, q, r]

		if merge_map.has(tile_key):
			var cached_tile: int = merge_map[tile_key]
			if at_corner:
				_add_corner_sample(corner_sample_nodes, pk, cached_tile)
			return record_tile_lookup.call(cached_tile, pk_parts, tile)

		if merge_map.has(merge_key):
			var cached_merge: int = merge_map[merge_key]
			var owner_key := _pos_sheet_key(pk, sheet_id)
			var owner: Vector2i = merge_owner.get(owner_key, Vector2i.ZERO)
			var allow_merge: bool = owner == Vector2i.ZERO or not tiles_are_cliff_neighbors.call(tile, owner)
			if allow_merge:
				merge_map[tile_key] = cached_merge
				if at_corner:
					_add_corner_sample(corner_sample_nodes, pk, cached_merge)
				return record_tile_lookup.call(cached_merge, pk_parts, tile)

		var index := adjacency_sets.size()
		merge_map[tile_key] = index
		node_keys.append(tile_key)
		node_sheet_ids.append(sheet_id)
		node_pos_keys.append(Vector2(float(pk_parts[0]), float(pk_parts[1])))
		node_plane_xy.append(Vector2(wx, wy))
		adjacency_sets.append({})
		if not merge_map.has(merge_key):
			merge_map[merge_key] = index
			merge_owner[_pos_sheet_key(pk, sheet_id)] = tile
		if at_corner:
			_add_corner_sample(corner_sample_nodes, pk, index)
		return record_tile_lookup.call(index, pk_parts, tile)

	for coord in hex_coords:
		var q_h := coord.x
		var r_h := coord.y
		var baseline := Ts08TerrainMathScript.handdrawn_to_baseline_axial(q_h, r_h)
		var cx := Ts08TerrainMathScript.axial_to_world_x(baseline.x, baseline.y, radius)
		var cy := Ts08TerrainMathScript.axial_to_world_y(baseline.x, baseline.y, radius)
		for sector in range(6):
			var grid: Dictionary = {}
			for si in range(subdiv + 1):
				var sj := 0
				while sj <= subdiv - si:
					var wx := cx + Ts08TerrainMathScript.sector_barycentric_x(
						sector, si, sj, subdiv, radius
					)
					var wy := cy + Ts08TerrainMathScript.sector_barycentric_y(
						sector, si, sj, subdiv, radius
					)
					var at_corner := (si == subdiv and sj == 0) or (si == 0 and sj == subdiv)
					var at_outer := si + sj == subdiv
					var on_cliff := _sample_on_cliff_boundary(
						coord,
						sector,
						at_outer,
						at_corner,
						si,
						sj,
						subdiv,
						cliff_physical
					)
					var nid: int = node_id_for.call(
						wx, wy, q_h, r_h, sector, at_corner, on_cliff, si, sj
					)
					grid[Vector2i(si, sj)] = nid
					if si == 0 and sj == 0:
						pinned[nid] = Ts08TerrainMathScript.canonical_center_world_y(
							world_map.tile_at(q_h, r_h).elevation,
							world_map.elevation_step,
							world_map.elevation_base
						)
						pin_hex_by_node[nid] = coord
					sj += 1

			for si in range(subdiv):
				var sj_tri := 0
				while sj_tri <= subdiv - si - 1:
					var v00: int = grid[Vector2i(si, sj_tri)]
					var v10: int = grid[Vector2i(si + 1, sj_tri)]
					var v01: int = grid[Vector2i(si, sj_tri + 1)]
					_add_undirected_edge(adjacency_sets, v00, v10)
					_add_undirected_edge(adjacency_sets, v10, v01)
					_add_undirected_edge(adjacency_sets, v00, v01)
					triangles.append([v00, v10, v01])
					if sj_tri + 1 <= subdiv - (si + 1):
						var v11: int = grid[Vector2i(si + 1, sj_tri + 1)]
						_add_undirected_edge(adjacency_sets, v10, v11)
						_add_undirected_edge(adjacency_sets, v01, v11)
						triangles.append([v10, v01, v11])
					sj_tri += 1

	var adjacency: Array = []
	for neighbors in adjacency_sets:
		var sorted_neighbors: Array = neighbors.keys()
		sorted_neighbors.sort()
		adjacency.append(sorted_neighbors)

	var component_ids := _connected_components(adjacency)
	var godot_xz: Array[Vector2] = []
	for plane in node_plane_xy:
		godot_xz.append(Ts08TerrainMathScript.plane_xy_to_godot_xz(plane))

	var result := BuildResult.new()
	result.node_count = adjacency.size()
	result.adjacency = adjacency
	result.node_keys = node_keys
	result.node_sheet_ids = node_sheet_ids
	result.node_pos_keys = node_pos_keys
	result.node_plane_xy = node_plane_xy
	result.node_godot_xz = godot_xz
	result.pinned_world_y = pinned
	result.pin_hex_by_node = pin_hex_by_node
	result.component_ids = component_ids
	result.corner_sample_nodes = corner_sample_nodes
	result.tile_pos_to_node = tile_pos_to_node
	result.triangles = triangles
	return result


static func _count_duplicated_cliff_line_nodes(build: BuildResult) -> int:
	var cliff_nodes_by_pos: Dictionary = {}
	for index in build.node_keys.size():
		var key = build.node_keys[index]
		if not (key is Array and key.size() > 0 and key[0] is String):
			continue
		if key[0] != "cliff_line":
			continue
		var pk: Vector2 = build.node_pos_keys[index]
		if not cliff_nodes_by_pos.has(pk):
			cliff_nodes_by_pos[pk] = []
		cliff_nodes_by_pos[pk].append(index)
	var duplicated := 0
	for pk in cliff_nodes_by_pos.keys():
		var indices: Array = cliff_nodes_by_pos[pk]
		if indices.size() > 1:
			duplicated += indices.size() - 1
	return duplicated


static func _audit_adjacency_cross_cliff(build: BuildResult) -> int:
	var violations := 0
	for node_index in build.adjacency.size():
		var sheet_a: int = build.node_sheet_ids[node_index]
		var pos_a: Vector2 = build.node_pos_keys[node_index]
		for neighbor in build.adjacency[node_index]:
			if neighbor <= node_index:
				continue
			var sheet_b: int = build.node_sheet_ids[neighbor]
			var pos_b: Vector2 = build.node_pos_keys[neighbor]
			if sheet_a == sheet_b:
				continue
			if pos_a != pos_b:
				continue
			violations += 1
	return violations


static func _connected_components(adjacency: Array) -> Array[int]:
	var component_ids: Array[int] = []
	component_ids.resize(adjacency.size())
	for i in component_ids.size():
		component_ids[i] = -1
	var component_index := 0
	for start in adjacency.size():
		if component_ids[start] >= 0:
			continue
		var queue: Array = [start]
		component_ids[start] = component_index
		var head := 0
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			for neighbor in adjacency[current]:
				if component_ids[neighbor] >= 0:
					continue
				component_ids[neighbor] = component_index
				queue.append(neighbor)
		component_index += 1
	return component_ids


static func _add_undirected_edge(adjacency_sets: Array, a: int, b: int) -> void:
	if a == b:
		return
	adjacency_sets[a][b] = true
	adjacency_sets[b][a] = true


static func _add_corner_sample(corner_sample_nodes: Dictionary, pk: Vector2, index: int) -> void:
	if not corner_sample_nodes.has(pk):
		corner_sample_nodes[pk] = {}
	corner_sample_nodes[pk][index] = true


static func _pos_sheet_key(pk: Vector2, sheet_id: int) -> String:
	return "%f,%f|%d" % [pk.x, pk.y, sheet_id]


static func _tile_pos_key(pk: Vector2, tile: Vector2i) -> String:
	return "%f,%f|%d,%d" % [pk.x, pk.y, tile.x, tile.y]


static func _physical_edge_for_neighbor_direction(direction: int) -> int:
	return Ts08TerrainMathScript.positive_mod(5 - direction, 6)


static func _neighbor_direction_between(tile_a: Vector2i, tile_b: Vector2i) -> int:
	var baseline_a := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_a.x, tile_a.y)
	var baseline_b := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_b.x, tile_b.y)
	var dq := baseline_b.x - baseline_a.x
	var dr := baseline_b.y - baseline_a.y
	for index in Ts08TerrainMathScript.NEIGHBOR_DELTAS.size():
		var delta: Vector2i = Ts08TerrainMathScript.NEIGHBOR_DELTAS[index]
		if delta.x == dq and delta.y == dr:
			return index
	push_error("Ts08CutLattice: %s is not a neighbor of %s" % [tile_b, tile_a])
	return 0


static func _is_neighbor(tile_a: Vector2i, tile_b: Vector2i) -> bool:
	for delta in Ts08TerrainMathScript.NEIGHBOR_DELTAS:
		if tile_a.x + delta.x == tile_b.x and tile_a.y + delta.y == tile_b.y:
			return true
	return false


static func _incident_physical_edges_at_sample(
	sector: int,
	at_corner: bool,
	si: int,
	sj: int,
	subdiv: int
) -> Array:
	if not at_corner:
		return []
	if si == subdiv and sj == 0:
		return [
			Ts08TerrainMathScript.positive_mod(sector - 1, 6),
			sector,
		]
	return [sector, Ts08TerrainMathScript.positive_mod(sector + 1, 6)]


static func _sample_on_cliff_boundary(
	tile: Vector2i,
	sector: int,
	at_sector_outer_edge: bool,
	at_corner: bool,
	si: int,
	sj: int,
	subdiv: int,
	cliff_physical: Dictionary
) -> bool:
	if not cliff_physical.has(tile):
		return false
	var cliff_edges: Dictionary = cliff_physical[tile]
	if at_sector_outer_edge and cliff_edges.has(sector):
		return true
	if at_corner:
		for edge in _incident_physical_edges_at_sample(sector, true, si, sj, subdiv):
			if cliff_edges.has(edge):
				return true
	return false


static func _smooth_component_at_corner(
	start: Vector2i,
	corner_tiles: Array[Vector2i],
	smooth_adjacency: Dictionary
) -> Array[Vector2i]:
	var allowed: Dictionary = {}
	for tile in corner_tiles:
		allowed[tile] = true
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if not smooth_adjacency.has(current):
			continue
		for neighbor in smooth_adjacency[current].keys():
			if allowed.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	var out: Array[Vector2i] = []
	for tile in seen.keys():
		out.append(tile)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Ts08TerrainMathScript.compare_tile_coords(a, b) < 0
	)
	return out
