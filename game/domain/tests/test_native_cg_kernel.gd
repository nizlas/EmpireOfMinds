# Headless test: godot --headless --path game -s res://domain/tests/test_native_cg_kernel.gd
#
# N3b.1b focused native-kernel tests on small synthetic WorldMaps:
# - the native cg_plain kernel matches the GDScript reference bit-for-bit
#   on a tiny rank-3 component (heights, iterations, residuals, energies);
# - two native solves are deterministic;
# - the native backend fails loudly on bad input and unknown backends;
# - the native backend is never applied to analytic or deflated routes
#   (structural proof via native_cg_plain_invocations).
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const WorldMapScript = preload("res://domain/world/world_map.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

const ELEVATION_STEP := 0.4
const ELEVATION_BASE := 0
const CLIFF_THRESHOLD := 1

var _total := 0
var _any_fail := false


func _init() -> void:
	if not _require_native_extension():
		_finish()
		return
	_test_kernel_matches_gdscript_rank3()
	_test_kernel_determinism()
	_test_kernel_rejects_bad_input()
	_test_unknown_backend_rejected()
	_test_native_not_applied_rank1()
	_test_native_not_applied_deflated()
	_test_native_applied_once_mixed()
	_finish()


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(
			false,
			"native extension descriptor missing at %s — build it first (.\\scripts\\build-native.ps1); this test must not silently fall back to GDScript" % DESCRIPTOR_PATH
		)
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		var status := GDExtensionManager.load_extension(DESCRIPTOR_PATH)
		_check(status == GDExtensionManager.LOAD_STATUS_OK, "extension loads (status %d)" % status)
		if status != GDExtensionManager.LOAD_STATUS_OK:
			return false
	_check(ClassDB.can_instantiate(&"EomTerrainNative"), "EomTerrainNative available")
	return ClassDB.can_instantiate(&"EomTerrainNative")


func _make_world_map(tiles_elevation: Dictionary):
	var tiles_dict: Dictionary = {}
	for coord: Vector2i in tiles_elevation.keys():
		tiles_dict[coord] = WorldMapScript.WorldTile.new(
			coord.x, coord.y, tiles_elevation[coord]
		)
	var edges: Dictionary = {}
	for coord: Vector2i in tiles_dict.keys():
		for offset: Vector2i in HexCoordScript.DIRECTIONS:
			var neighbor := coord + offset
			if not tiles_dict.has(neighbor):
				continue
			var edge_key := WorldMapScript.normalized_edge_key(coord, neighbor)
			if edges.has(edge_key):
				continue
			var delta: int = absi(
				tiles_dict[coord].elevation - tiles_dict[neighbor].elevation
			)
			var transition := WorldMapScript.EDGE_SMOOTH
			if delta > CLIFF_THRESHOLD:
				transition = WorldMapScript.EDGE_CLIFF
			var pair: Array = WorldMapScript.parse_edge_key(edge_key)
			edges[edge_key] = WorldMapScript.WorldEdge.new(pair[0], pair[1], transition)
	var identity = MapIdentityScript.new("synthetic_native_kernel_test", 1, "synthetic")
	return WorldMapScript.new(
		identity, ELEVATION_STEP, ELEVATION_BASE, CLIFF_THRESHOLD, tiles_dict, edges
	)


func _solve_both(tiles_elevation: Dictionary) -> Array:
	var world_map = _make_world_map(tiles_elevation)
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var gd = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_GDSCRIPT)
	var native = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	return [world_map, build, gd, native]


func _max_abs_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var max_diff := 0.0
	for i in a.size():
		max_diff = maxf(max_diff, absf(a[i] - b[i]))
	return max_diff


const RANK3_TILES := {
	Vector2i(0, 0): 0,
	Vector2i(1, 0): 1,
	Vector2i(0, 1): 1,
}


func _test_kernel_matches_gdscript_rank3() -> void:
	print("--- native kernel vs GDScript reference on tiny rank-3 map ---")
	var parts := _solve_both(RANK3_TILES)
	var gd = parts[2]
	var native = parts[3]
	_check(gd != null and native != null, "both backends solved")
	if gd == null or native == null:
		return
	_check(native.backend == Ts08HeightSolver.BACKEND_NATIVE, "native result labeled native")
	_check(native.native_cg_plain_invocations == 1, "native kernel invoked exactly once")
	_check(gd.native_cg_plain_invocations == 0, "gdscript run never touched native")
	_check(native.converged, "native converged")
	_check(
		native.cg_iterations == gd.cg_iterations,
		"iteration count identical (native %d vs gd %d)" % [native.cg_iterations, gd.cg_iterations]
	)
	var diff := _max_abs_diff(native.heights, gd.heights)
	_check(
		native.heights == gd.heights,
		"heights bit-identical to GDScript reference (max diff %s)" % String.num_scientific(diff)
	)
	_check(
		native.cg_final_abs_residual == gd.cg_final_abs_residual
		and native.cg_final_rel_residual == gd.cg_final_rel_residual,
		"residuals bit-identical"
	)
	_check(
		native.energy_initial == gd.energy_initial and native.energy_final == gd.energy_final,
		"energies bit-identical"
	)
	_check(native.max_center_interpolation_error <= 1e-12, "native pins exact")


func _test_kernel_determinism() -> void:
	print("--- native kernel determinism (two independent solves) ---")
	var world_map = _make_world_map(RANK3_TILES)
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var a = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	var b = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(a != null and b != null, "both native solves completed")
	if a == null or b == null:
		return
	_check(a.heights == b.heights, "deterministic native rerun (bit-identical heights)")
	_check(a.cg_iterations == b.cg_iterations, "deterministic native iteration count")


func _test_kernel_rejects_bad_input() -> void:
	print("--- native kernel rejects inconsistent input sizes ---")
	var backend: Object = ClassDB.instantiate(&"EomTerrainNative")
	# neighbor_ptr must have degrees.size() + 1 entries; pass a wrong size.
	print("(expected native error output below)")
	var out: Dictionary = backend.solve_cg_plain_global(
		PackedInt32Array([0, 0]),
		PackedInt32Array(),
		PackedFloat64Array([1.0, 1.0]),
		PackedInt32Array([0]),
		PackedFloat64Array([0.5]),
		PackedFloat64Array([0.5, 0.0]),
		1e-8,
		10,
		false
	)
	_check(out.is_empty(), "inconsistent sizes -> empty Dictionary (fail-loud)")


func _test_unknown_backend_rejected() -> void:
	print("--- unknown backend string rejected ---")
	var world_map = _make_world_map(RANK3_TILES)
	var build = Ts08CutLattice.build_from_world_map(world_map)
	print("(expected solver error output below)")
	var result = Ts08HeightSolver.solve(world_map, build, false, "bogus")
	_check(result == null, "unknown backend -> null (fail-loud, no fallback)")


func _test_native_not_applied_rank1() -> void:
	print("--- native backend requested on rank-1 map: kernel must not run ---")
	var parts := _solve_both({Vector2i(0, 0): 2})
	var gd = parts[2]
	var native = parts[3]
	_check(gd != null and native != null, "rank1: both backends solved")
	if gd == null or native == null:
		return
	_check(
		native.native_cg_plain_invocations == 0,
		"rank1: native kernel never invoked (analytic route stays GDScript)"
	)
	_check(native.gauge_convention_applied_count == 1, "rank1: gauge convention applied once")
	_check(native.heights == gd.heights, "rank1: heights identical across backends")


func _test_native_not_applied_deflated() -> void:
	print("--- native backend requested on deflated map: kernel must not run ---")
	var tiles := {
		Vector2i(0, 0): 0,
		Vector2i(1, 0): 1,
		Vector2i(2, 0): 0,
		Vector2i(3, 0): 1,
	}
	var parts := _solve_both(tiles)
	var gd = parts[2]
	var native = parts[3]
	_check(gd != null and native != null, "deflated: both backends solved")
	if gd == null or native == null:
		return
	_check(
		native.native_cg_plain_invocations == 0,
		"deflated: native kernel never invoked (deflated route stays GDScript)"
	)
	_check(native.deflation_instantiated_count == 1, "deflated: deflation ran in GDScript once")
	_check(native.heights == gd.heights, "deflated: heights identical across backends")


func _test_native_applied_once_mixed() -> void:
	print("--- mixed map: native kernel runs once, analytic component untouched ---")
	var tiles := {
		Vector2i(0, 0): 0,
		Vector2i(1, 0): 1,
		Vector2i(0, 1): 1,
		Vector2i(4, 0): 3,
	}
	var parts := _solve_both(tiles)
	var build = parts[1]
	var gd = parts[2]
	var native = parts[3]
	_check(gd != null and native != null, "mixed: both backends solved")
	if gd == null or native == null:
		return
	_check(native.native_cg_plain_invocations == 1, "mixed: native kernel invoked exactly once")
	_check(native.gauge_convention_applied_count == 1, "mixed: analytic route still GDScript")
	_check(native.heights == gd.heights, "mixed: heights identical across backends")
	# The isolated rank-1 hex must be exactly constant despite the native CG.
	var rank1_component := -1
	for report in native.component_reports:
		if report["pin_rank"] == 1:
			rank1_component = int(report["component_id"])
	_check(rank1_component >= 0, "mixed: rank-1 component present")
	var expected: float = Ts08TerrainMathScript.canonical_center_world_y(
		3, ELEVATION_STEP, ELEVATION_BASE
	)
	var max_error := 0.0
	for i in build.node_count:
		if build.component_ids[i] == rank1_component:
			max_error = maxf(max_error, absf(native.heights[i] - expected))
	_check(max_error == 0.0, "mixed: isolated component exactly constant under native backend")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Native CG kernel tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
