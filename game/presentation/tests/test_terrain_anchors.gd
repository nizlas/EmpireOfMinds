# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_anchors.gd
#
# N4 world anchors (game/presentation/world/terrain_anchors.gd):
# - complete coverage: exactly one anchor per canonical WorldMap tile,
#   both directions (every tile has an anchor; no anchor without a tile);
# - anchors ARE the actual center pins: each anchor equals its tile's
#   center-pin lattice node position with the solved height, the solved
#   height equals the hard-pinned canonical value exactly, and the anchor
#   equals the rendered top-surface vertex at that node (same position the
#   mesh bakes);
# - canonical identity preserved: every anchor's X/Z round-trips through
#   HexWorldProjection.world_xz_to_axial back to its own tile id, and the
#   anchor height matches the canonical rules height for the tile
#   elevation;
# - non-flat coverage: the reference map spans multiple elevations, so
#   anchors must span multiple heights;
# - deterministic across two independent lattice+solve builds.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
extends SceneTree

const TerrainAnchors = preload("res://presentation/world/terrain_anchors.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")
const HexWorldProjectionScript = preload("res://domain/world/hex_world_projection.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	if not _require_native_extension():
		_finish()
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return

	var lattice = Ts08CutLattice.build_from_world_map(world_map)
	var solve = Ts08HeightSolver.solve(world_map, lattice, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(solve != null and solve.converged, "native height solve converges")
	if solve == null or not solve.converged:
		_finish()
		return
	var anchors: Dictionary = TerrainAnchors.build_tile_anchors(world_map, lattice, solve.heights)

	# --- complete tile-id <-> anchor coverage ---
	_check(
		anchors.size() == world_map.tile_count(),
		"exactly one anchor per WorldMap tile (%d)" % world_map.tile_count()
	)
	var coords: Array[Vector2i] = world_map.tile_coords()
	var all_tiles_covered := true
	for coord in coords:
		if not anchors.has(coord):
			all_tiles_covered = false
	_check(all_tiles_covered, "every canonical tile id has an anchor")
	var no_foreign_anchor := true
	for tile in anchors:
		if not world_map.has_tile_coord(tile):
			no_foreign_anchor = false
	_check(no_foreign_anchor, "no anchor exists without a canonical tile")

	# --- anchors match the actual center pins on the solved terrain ---
	var node_by_tile: Dictionary = {}
	for node_id in lattice.pin_hex_by_node:
		node_by_tile[lattice.pin_hex_by_node[node_id]] = node_id
	_check(
		node_by_tile.size() == anchors.size(),
		"lattice records exactly one center-pin node per tile"
	)
	var pins_match := true
	var solved_equals_pin := true
	for tile in anchors:
		var node_id: int = node_by_tile[tile]
		var xz: Vector2 = lattice.node_godot_xz[node_id]
		if anchors[tile] != Vector3(xz.x, solve.heights[node_id], xz.y):
			pins_match = false
		if solve.heights[node_id] != float(lattice.pinned_world_y[node_id]):
			solved_equals_pin = false
	_check(pins_match, "every anchor equals its center-pin node position with the solved height")
	_check(solved_equals_pin, "solved center heights equal the hard-pinned canonical values exactly")

	var geometry = Ts08SurfaceGeometry.build(world_map, lattice, solve.heights)
	var on_rendered_surface := true
	for tile in anchors:
		if anchors[tile] != geometry.top_positions[node_by_tile[tile]]:
			on_rendered_surface = false
	_check(
		on_rendered_surface,
		"every anchor equals the rendered top-surface vertex at its center node (bit-identical)"
	)

	# --- canonical identity preserved ---
	var round_trips := true
	var heights_canonical := true
	for tile in anchors:
		var anchor: Vector3 = anchors[tile]
		if HexWorldProjectionScript.world_xz_to_axial(anchor.x, anchor.z) != tile:
			round_trips = false
		var expected_y := HexWorldProjectionScript.elevation_to_world_y(
			world_map.tile_elevation(tile.x, tile.y),
			world_map.elevation_step,
			world_map.elevation_base
		)
		if absf(anchor.y - expected_y) > 1e-5:
			heights_canonical = false
	_check(round_trips, "every anchor X/Z round-trips to its own canonical tile id")
	_check(heights_canonical, "every anchor height matches the canonical rules height")

	var distinct_heights: Dictionary = {}
	for tile in anchors:
		distinct_heights[anchors[tile].y] = true
	_check(
		distinct_heights.size() > 1,
		"anchors span multiple elevations (%d distinct heights)" % distinct_heights.size()
	)

	# --- deterministic across two independent builds ---
	var lattice_b = Ts08CutLattice.build_from_world_map(world_map)
	var solve_b = Ts08HeightSolver.solve(
		world_map, lattice_b, false, Ts08HeightSolver.BACKEND_NATIVE
	)
	var anchors_b: Dictionary = TerrainAnchors.build_tile_anchors(
		world_map, lattice_b, solve_b.heights
	)
	_check(anchors_b == anchors, "anchors deterministic across two independent builds")

	_finish()


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(false, "native GDExtension descriptor present (build it first)")
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			_check(false, "native GDExtension loads")
			return false
	if not ClassDB.can_instantiate(&"EomTerrainNative"):
		_check(false, "EomTerrainNative instantiable")
		return false
	return true


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainAnchors tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
