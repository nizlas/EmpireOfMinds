# N4 world anchors (presentation/integration-side derived data).
#
# One deterministic world-space anchor per WorldMap tile, taken from that
# tile's ACTUAL center-pin node on the solver-generated terrain: the N3a
# lattice records exactly one center node per hex (pin_hex_by_node) and the
# N3b solver hard-pins its height, so the anchor is the same position the
# rendered top surface uses at the tile center
# (== geometry.top_positions[center_node]).
#
# Authority boundary (permanent N4 rule): anchors are DERIVED PRESENTATION
# DATA — a projection convenience for screen-space UI. WorldMap stays the
# sole logical authority; gameplay rules must never read positions, heights,
# or tile identity from anchors. Never recompute anchors from the axial
# formula, mesh raycasts, or nearest geometry — the center pin is the one
# source. No legacy HexMap / Unit3DWorldView / City3DWorldView anchor path.
extends RefCounted


# Builds { Vector2i(q, r) -> Vector3 anchor } from the lattice center pins
# and the solved heights. Fails loudly (push_error + {}) when coverage is
# incomplete — every WorldMap tile must have exactly one center pin.
static func build_tile_anchors(world_map, lattice, heights: PackedFloat64Array) -> Dictionary:
	var anchors: Dictionary = {}
	for node_id in lattice.pin_hex_by_node:
		var tile: Vector2i = lattice.pin_hex_by_node[node_id]
		if anchors.has(tile):
			push_error("terrain_anchors: duplicate center pin for tile %s" % str(tile))
			return {}
		var xz: Vector2 = lattice.node_godot_xz[node_id]
		anchors[tile] = Vector3(xz.x, heights[node_id], xz.y)
	if anchors.size() != world_map.tile_count():
		push_error(
			"terrain_anchors: %d anchors != %d WorldMap tiles"
			% [anchors.size(), world_map.tile_count()]
		)
		return {}
	for coord in world_map.tile_coords():
		if not anchors.has(coord):
			push_error("terrain_anchors: tile %s has no center-pin anchor" % str(coord))
			return {}
	return anchors
