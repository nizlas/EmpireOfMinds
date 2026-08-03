# TS-08 terrain-surface geometry builder (N3c.1). Domain-only.
#
# Consumes the N3a Ts08CutLattice.BuildResult plus N3b solved heights and
# emits packed geometry data and wall-face records. No ArrayMesh, materials,
# or scene nodes here — presentation/dev-preview code owns those.
#
# Top surface: solver heights on the existing lattice nodes, triangles
# oriented Y-up (counter-clockwise seen from above, mirroring the N2
# exporter's _orient_upward_triangle_y_up), smooth area-weighted normals.
#
# Cliff walls: port of the accepted Stage-3a contract in
# tools/blender/terrain/eom_terrain_ts08_cliff_walls.py:
# - walls exist only along authoritative WorldMap cliff edges;
# - seam chains use the duplicated lattice nodes on the two seam sides via
#   tile_pos_to_node;
# - one wall polygon per non-degenerate seam segment (quads; crack-tip
#   segments collapse to triangles; fully merged segments are skipped);
# - deterministic face orientation toward the lower tile (Newell normal in
#   plane coordinates);
# - no new wall-height rules, offsets, rails, or cross-cliff coupling.
#
# Wall polygons stay separately identifiable (WallFace records) so later
# wall materials and collision can consume them without inferring cliffs
# from slope.
class_name Ts08SurfaceGeometry
extends RefCounted

const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")
const Ts08CutLatticeScript = preload("res://domain/world/ts08_cut_lattice.gd")

const WALL_FACE_AREA_EPSILON := 1e-15


class WallFace extends RefCounted:
	var tile_a: Vector2i
	var tile_b: Vector2i
	var segment_index: int = 0
	# Oriented polygon (3 or 4 node indices into the shared lattice/top
	# vertex array), counter-clockwise around the outward normal that points
	# from the higher tile toward the lower tile (accepted Python order).
	var vertex_indices := PackedInt32Array()
	var height_delta: float = 0.0


class GeometryResult extends RefCounted:
	var top_vertex_count: int = 0
	# Godot world space: (x, solved_y, z) per lattice node index.
	var top_positions := PackedVector3Array()
	# Flattened Y-up oriented triangles (CCW seen from above). Presentation
	# reverses per-triangle order for Godot's clockwise front faces.
	var top_triangles := PackedInt32Array()
	var top_normals := PackedVector3Array()
	var wall_faces: Array = []
	var wall_segment_count: int = 0
	var wall_skipped_segment_count: int = 0
	var wall_quad_count: int = 0
	var wall_triangle_count: int = 0
	var wall_heights := PackedFloat64Array()
	var build_msec: int = 0


static func build(
	world_map,
	lattice,
	heights: PackedFloat64Array,
	subdiv: int = Ts08TerrainMathScript.DEFAULT_SURFACE_SUBDIVISIONS,
	radius: float = Ts08TerrainMathScript.DEFAULT_HEX_RADIUS
) -> GeometryResult:
	var started_msec := Time.get_ticks_msec()
	if heights.size() != lattice.node_count:
		push_error(
			"Ts08SurfaceGeometry: heights size %d != node count %d"
			% [heights.size(), lattice.node_count]
		)
		return null
	var result := GeometryResult.new()
	_build_top_surface(lattice, heights, result)
	if not _build_cliff_walls(world_map, lattice, heights, subdiv, radius, result):
		return null
	result.build_msec = Time.get_ticks_msec() - started_msec
	return result


# ---------------------------------------------------------------------------
# Top surface (accepted N3b presentation contract, moved from the preview).
# ---------------------------------------------------------------------------


static func _build_top_surface(lattice, heights: PackedFloat64Array, result: GeometryResult) -> void:
	var n: int = lattice.node_count
	var positions := PackedVector3Array()
	positions.resize(n)
	for i in n:
		var xz: Vector2 = lattice.node_godot_xz[i]
		positions[i] = Vector3(xz.x, heights[i], xz.y)

	var triangles := PackedInt32Array()
	triangles.resize(lattice.triangles.size() * 3)
	var normals := PackedVector3Array()
	normals.resize(n)
	var cursor := 0
	for tri in lattice.triangles:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		var pa := positions[a]
		var pb := positions[b]
		var pc := positions[c]
		# Orient counter-clockwise seen from above (+Y), mirroring the N2
		# exporter; the raw lattice stores its two barycentric families with
		# opposite plane orientation.
		var ny := (pb.z - pa.z) * (pc.x - pa.x) - (pb.x - pa.x) * (pc.z - pa.z)
		if ny < 0.0:
			var swap := b
			b = c
			c = swap
			var swap_p := pb
			pb = pc
			pc = swap_p
		var face_normal := (pb - pa).cross(pc - pa)
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal
		triangles[cursor] = a
		triangles[cursor + 1] = b
		triangles[cursor + 2] = c
		cursor += 3
	for i in n:
		if normals[i].length_squared() > 0.0:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	result.top_vertex_count = n
	result.top_positions = positions
	result.top_triangles = triangles
	result.top_normals = normals


# ---------------------------------------------------------------------------
# Cliff walls (port of eom_terrain_ts08_cliff_walls.build_cliff_wall_faces).
# ---------------------------------------------------------------------------


static func _build_cliff_walls(
	world_map,
	lattice,
	heights: PackedFloat64Array,
	subdiv: int,
	radius: float,
	result: GeometryResult
) -> bool:
	var cliff_pairs: Dictionary = Ts08CutLatticeScript._build_cliff_neighbor_pairs(world_map)
	var sorted_pairs: Array = []
	for key in cliff_pairs.keys():
		var parts: PackedStringArray = key.split("|")
		var a_parts: PackedStringArray = parts[0].split(",")
		var b_parts: PackedStringArray = parts[1].split(",")
		sorted_pairs.append([
			Vector2i(int(a_parts[0]), int(a_parts[1])),
			Vector2i(int(b_parts[0]), int(b_parts[1])),
		])
	sorted_pairs.sort_custom(func(pair_a: Array, pair_b: Array) -> bool:
		var first := Ts08TerrainMathScript.compare_tile_coords(pair_a[0], pair_b[0])
		if first != 0:
			return first < 0
		return Ts08TerrainMathScript.compare_tile_coords(pair_a[1], pair_b[1]) < 0
	)

	var expected_keys: Dictionary = {}
	for pair in sorted_pairs:
		var tile_a: Vector2i = pair[0]
		var tile_b: Vector2i = pair[1]
		var chain := _extract_cliff_seam_chain(lattice, tile_a, tile_b, subdiv, radius)
		if chain.is_empty():
			return false

		for seg in range(chain.size() - 1):
			result.wall_segment_count += 1
			var sample_a0: Array = chain[seg]
			var sample_a1: Array = chain[seg + 1]
			var candidate := _candidate_wall_face(
				sample_a0[0], sample_a1[0], sample_a1[1], sample_a0[1]
			)
			if candidate.is_empty():
				result.wall_skipped_segment_count += 1
				continue

			var face := _orient_wall_face(
				candidate, lattice, heights, world_map, tile_a, tile_b, radius
			)
			var dedupe_key := _face_dedupe_key(face)
			if expected_keys.has(dedupe_key):
				continue
			expected_keys[dedupe_key] = true

			var z_min: float = heights[face[0]]
			var z_max: float = z_min
			for index in face:
				var z: float = heights[index]
				z_min = minf(z_min, z)
				z_max = maxf(z_max, z)
			var height_delta := z_max - z_min

			var record := WallFace.new()
			record.tile_a = tile_a
			record.tile_b = tile_b
			record.segment_index = seg
			record.vertex_indices = face
			record.height_delta = height_delta
			result.wall_faces.append(record)
			result.wall_heights.append(height_delta)
			if face.size() == 3:
				result.wall_triangle_count += 1
			else:
				result.wall_quad_count += 1
	return true


# Returns [[node_a, node_b], ...] per seam sample, or [] on lookup failure.
static func _extract_cliff_seam_chain(
	lattice,
	tile_a: Vector2i,
	tile_b: Vector2i,
	subdiv: int,
	radius: float
) -> Array:
	var edge_a: int = Ts08CutLatticeScript._physical_edge_for_neighbor_direction(
		Ts08CutLatticeScript._neighbor_direction_between(tile_a, tile_b)
	)
	var edge_b: int = Ts08CutLatticeScript._physical_edge_for_neighbor_direction(
		Ts08CutLatticeScript._neighbor_direction_between(tile_b, tile_a)
	)

	var baseline_a := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_a.x, tile_a.y)
	var baseline_b := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_b.x, tile_b.y)
	var cx_a := Ts08TerrainMathScript.axial_to_world_x(baseline_a.x, baseline_a.y, radius)
	var cy_a := Ts08TerrainMathScript.axial_to_world_y(baseline_a.x, baseline_a.y, radius)
	var cx_b := Ts08TerrainMathScript.axial_to_world_x(baseline_b.x, baseline_b.y, radius)
	var cy_b := Ts08TerrainMathScript.axial_to_world_y(baseline_b.x, baseline_b.y, radius)

	var samples: Array = []
	for k in range(subdiv + 1):
		var si_a := subdiv - k
		var sj_a := k
		var lx_a := Ts08TerrainMathScript.sector_barycentric_x(edge_a, si_a, sj_a, subdiv, radius)
		var ly_a := Ts08TerrainMathScript.sector_barycentric_y(edge_a, si_a, sj_a, subdiv, radius)
		var pk_parts: Array = Ts08TerrainMathScript.pos_key_parts(cx_a + lx_a, cy_a + ly_a)

		var step_k_b := subdiv - k
		var si_b := subdiv - step_k_b
		var sj_b := step_k_b
		var lx_b := Ts08TerrainMathScript.sector_barycentric_x(edge_b, si_b, sj_b, subdiv, radius)
		var ly_b := Ts08TerrainMathScript.sector_barycentric_y(edge_b, si_b, sj_b, subdiv, radius)
		var pk_parts_b: Array = Ts08TerrainMathScript.pos_key_parts(cx_b + lx_b, cy_b + ly_b)
		if pk_parts[0] != pk_parts_b[0] or pk_parts[1] != pk_parts_b[1]:
			push_error(
				"Ts08SurfaceGeometry: cliff seam position mismatch between %s and %s at k=%d"
				% [tile_a, tile_b, k]
			)
			return []

		var pk := Vector2(float(pk_parts[0]), float(pk_parts[1]))
		var node_a := _lookup_tile_node(lattice, pk, tile_a)
		var node_b := _lookup_tile_node(lattice, pk, tile_b)
		if node_a < 0 or node_b < 0:
			return []
		samples.append([node_a, node_b])
	return samples


static func _lookup_tile_node(lattice, pk: Vector2, tile: Vector2i) -> int:
	var key: String = Ts08CutLatticeScript._tile_pos_key(pk, tile)
	if not lattice.tile_pos_to_node.has(key):
		push_error("Ts08SurfaceGeometry: tile_pos_to_node miss at pos=%s tile=%s" % [pk, tile])
		return -1
	return lattice.tile_pos_to_node[key]


# Dedupe consecutive duplicates, then keep first occurrences in order;
# fewer than 3 unique indices means a fully merged (skipped) segment.
static func _candidate_wall_face(a0: int, a1: int, b1: int, b0: int) -> PackedInt32Array:
	var ordered: Array = []
	for index in [a0, a1, b1, b0]:
		if ordered.is_empty() or ordered[ordered.size() - 1] != index:
			ordered.append(index)
	var unique := PackedInt32Array()
	var seen: Dictionary = {}
	for index in ordered:
		if seen.has(index):
			continue
		seen[index] = true
		unique.append(index)
	if unique.size() < 3:
		return PackedInt32Array()
	return unique


# Newell normal in plane coordinates (x = plane x, y = plane y, z = height).
static func _newell_normal(
	face: PackedInt32Array,
	lattice,
	heights: PackedFloat64Array
) -> Array:
	var nx := 0.0
	var ny := 0.0
	var nz := 0.0
	var count := face.size()
	for i in count:
		var i0: int = face[i]
		var i1: int = face[(i + 1) % count]
		var x0: float = lattice.node_plane_x[i0]
		var y0: float = lattice.node_plane_y[i0]
		var z0: float = heights[i0]
		var x1: float = lattice.node_plane_x[i1]
		var y1: float = lattice.node_plane_y[i1]
		var z1: float = heights[i1]
		nx += (y0 - y1) * (z0 + z1)
		ny += (z0 - z1) * (x0 + x1)
		nz += (x0 - x1) * (y0 + y1)
	return [nx, ny, nz]


static func wall_face_area(
	face: PackedInt32Array,
	lattice,
	heights: PackedFloat64Array
) -> float:
	if face.size() < 3:
		return 0.0
	var normal := _newell_normal(face, lattice, heights)
	var nx: float = normal[0]
	var ny: float = normal[1]
	var nz: float = normal[2]
	return 0.5 * sqrt(nx * nx + ny * ny + nz * nz)


static func _orient_wall_face(
	face: PackedInt32Array,
	lattice,
	heights: PackedFloat64Array,
	world_map,
	tile_a: Vector2i,
	tile_b: Vector2i,
	radius: float
) -> PackedInt32Array:
	var area := wall_face_area(face, lattice, heights)
	if area <= WALL_FACE_AREA_EPSILON:
		return face

	var normal := _newell_normal(face, lattice, heights)
	var nx: float = normal[0]
	var ny: float = normal[1]

	var baseline_a := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_a.x, tile_a.y)
	var baseline_b := Ts08TerrainMathScript.handdrawn_to_baseline_axial(tile_b.x, tile_b.y)
	var cx_a := Ts08TerrainMathScript.axial_to_world_x(baseline_a.x, baseline_a.y, radius)
	var cy_a := Ts08TerrainMathScript.axial_to_world_y(baseline_a.x, baseline_a.y, radius)
	var cx_b := Ts08TerrainMathScript.axial_to_world_x(baseline_b.x, baseline_b.y, radius)
	var cy_b := Ts08TerrainMathScript.axial_to_world_y(baseline_b.x, baseline_b.y, radius)
	var elev_a: int = world_map.tile_at(tile_a.x, tile_a.y).elevation
	var elev_b: int = world_map.tile_at(tile_b.x, tile_b.y).elevation

	var high_x: float
	var high_y: float
	var low_x: float
	var low_y: float
	if elev_a >= elev_b:
		high_x = cx_a
		high_y = cy_a
		low_x = cx_b
		low_y = cy_b
	else:
		high_x = cx_b
		high_y = cy_b
		low_x = cx_a
		low_y = cy_a

	var dir_x := low_x - high_x
	var dir_y := low_y - high_y
	var dir_len := sqrt(dir_x * dir_x + dir_y * dir_y)
	if dir_len <= 1e-12:
		return face
	dir_x /= dir_len
	dir_y /= dir_len

	var normal_xy_len := sqrt(nx * nx + ny * ny)
	if normal_xy_len <= 1e-12:
		return face
	if (nx / normal_xy_len) * dir_x + (ny / normal_xy_len) * dir_y < 0.0:
		var reversed_face := PackedInt32Array()
		reversed_face.resize(face.size())
		for i in face.size():
			reversed_face[i] = face[face.size() - 1 - i]
		return reversed_face
	return face


# Quads are keyed by their sorted index set; triangles by the oriented tuple
# (mirrors the Python helper exactly).
static func _face_dedupe_key(face: PackedInt32Array) -> String:
	if face.size() == 4:
		var sorted_indices: Array = []
		for index in face:
			sorted_indices.append(index)
		sorted_indices.sort()
		return "%d,%d,%d,%d" % sorted_indices
	var parts: Array = []
	for index in face:
		parts.append(str(index))
	return ",".join(parts)
