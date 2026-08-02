# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_height_solver_n3b.gd
#
# N3b numerical parity: Godot-native TS-08 Stage-2 cut-domain thin-plate CG
# height solve from WorldMap + N3a lattice, compared against the test-only
# binary height golden derived from N2 (every node, no sampling).
# Golden generator: tools/blender/terrain/generate_ts08_n3b_height_golden.py
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

var _total := 0
var _any_fail := false

const GOLDEN_BIN_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3b_heights_v1.bin"
const GOLDEN_SIDECAR_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3b_heights_v1.json"
const REFERENCE_MAP_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const N2_CONTENT_HASH := "4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce"

# Reference-map golden values (test-owned).
const EXPECTED_NODE_COUNT := 74129
const EXPECTED_TRIANGLE_COUNT := 145152
const EXPECTED_CENTER_PIN_COUNT := 168
const EXPECTED_COMPONENT_COUNT := 1
const EXPECTED_DEFICIENT_COUNT := 0
const GOLDEN_Y_MIN := -0.0953001335506
const GOLDEN_Y_MAX := 2.09155970068
const N2_MAX_TENT_POLE := 0.028821815457

# Acceptance limits (upper bounds; measured values reported below).
const MAX_ABS_ERROR_LIMIT := 1e-5
const RMS_ERROR_LIMIT := 1e-6
const CENTER_PIN_ERROR_LIMIT := 1e-12


func _init() -> void:
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	_check(world_map.identity.content_hash == REFERENCE_MAP_HASH, "reference map hash")

	var t0 := Time.get_ticks_msec()
	var build_a := Ts08CutLattice.build_from_world_map(world_map)
	var build_msec_a := Time.get_ticks_msec() - t0
	print("lattice build A: %d ms (%d nodes)" % [build_msec_a, build_a.node_count])
	_check(build_a.node_count == EXPECTED_NODE_COUNT, "node count golden")
	_check(build_a.triangles.size() == EXPECTED_TRIANGLE_COUNT, "triangle count golden")

	var audit := Ts08CutLattice.audit_topology(build_a)
	_check(audit["adjacency_cross_cliff_violations"] == 0, "zero cross-cliff adjacency")

	print("solve A starting (progress every 200 CG iterations)...")
	var solve_a := Ts08HeightSolver.solve(world_map, build_a, true)
	print("solve A: %d ms" % solve_a.solve_msec)
	print(
		"cg_iterations=%d abs_residual=%s rel_residual=%s"
		% [
			solve_a.cg_iterations,
			String.num_scientific(solve_a.cg_final_abs_residual),
			String.num_scientific(solve_a.cg_final_rel_residual),
		]
	)
	print(
		"energy_initial=%.12f energy_final=%.12f"
		% [solve_a.energy_initial, solve_a.energy_final]
	)
	print("y_min=%.12f y_max=%.12f" % [solve_a.y_min, solve_a.y_max])
	print(
		"max_center_error=%s max_tent_pole_delta=%.12f"
		% [
			String.num_scientific(solve_a.max_center_interpolation_error),
			solve_a.max_tent_pole_delta,
		]
	)
	print("solver array memory estimate: %d bytes" % solve_a.solver_bytes_estimate)

	_check(solve_a.pinned_center_count == EXPECTED_CENTER_PIN_COUNT, "center pin count")
	_check(solve_a.connected_component_count == EXPECTED_COMPONENT_COUNT, "single connected component")
	_check(solve_a.deficient_component_count == EXPECTED_DEFICIENT_COUNT, "zero deficient components")
	_check(solve_a.converged, "CG converged")
	_check(solve_a.cg_final_rel_residual <= 1e-8, "relative residual <= 1e-8")
	_check(solve_a.energy_final < solve_a.energy_initial, "final bending energy below initial")
	_check(
		solve_a.max_center_interpolation_error <= CENTER_PIN_ERROR_LIMIT,
		"center pin error <= 1e-12 (solver)"
	)
	_check(
		solve_a.max_tent_pole_delta <= N2_MAX_TENT_POLE + 1e-6,
		"no tent-pole regression (max delta %.12f vs N2 %.12f)"
		% [solve_a.max_tent_pole_delta, N2_MAX_TENT_POLE]
	)
	_check(
		solve_a.gauge_convention_applied_count == 0,
		"gauge convention untouched on rank-3 reference map"
	)
	_check(
		solve_a.deflation_instantiated_count == 0,
		"deflation machinery never instantiated on rank-3 reference map"
	)
	_check(absf(solve_a.y_min - GOLDEN_Y_MIN) <= MAX_ABS_ERROR_LIMIT, "y_min near golden range")
	_check(absf(solve_a.y_max - GOLDEN_Y_MAX) <= MAX_ABS_ERROR_LIMIT, "y_max near golden range")

	# Second independent full build + solve for determinism.
	var t1 := Time.get_ticks_msec()
	var build_b := Ts08CutLattice.build_from_world_map(world_map)
	var build_msec_b := Time.get_ticks_msec() - t1
	print("lattice build B: %d ms" % build_msec_b)
	print("solve B starting...")
	var solve_b := Ts08HeightSolver.solve(world_map, build_b, false)
	print("solve B: %d ms" % solve_b.solve_msec)
	_check(solve_a.heights.size() == solve_b.heights.size(), "deterministic height count")
	_check(solve_a.heights == solve_b.heights, "deterministic rerun (bit-identical heights)")
	_check(solve_a.cg_iterations == solve_b.cg_iterations, "deterministic iteration count")

	_compare_against_golden(world_map, build_a, solve_a)
	print(
		"total: build A %d ms + solve A %d ms = %d ms"
		% [build_msec_a, solve_a.solve_msec, build_msec_a + solve_a.solve_msec]
	)
	_finish()


func _compare_against_golden(world_map, build, solve) -> void:
	_check(FileAccess.file_exists(GOLDEN_BIN_PATH), "binary golden exists")
	_check(FileAccess.file_exists(GOLDEN_SIDECAR_PATH), "golden sidecar exists")
	if not FileAccess.file_exists(GOLDEN_BIN_PATH) or not FileAccess.file_exists(GOLDEN_SIDECAR_PATH):
		return

	var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_SIDECAR_PATH))
	_check(sidecar is Dictionary, "sidecar JSON parses")
	if not sidecar is Dictionary:
		return
	_check(sidecar.get("source_n2_content_hash", "") == N2_CONTENT_HASH, "sidecar N2 hash lock")
	_check(int(sidecar.get("node_count", -1)) == EXPECTED_NODE_COUNT, "sidecar node count")

	var raw := FileAccess.get_file_as_bytes(GOLDEN_BIN_PATH)
	_check(
		MapContentLoader.sha256_hex_lower(raw) == str(sidecar.get("binary_sha256", "")),
		"binary golden SHA-256 matches sidecar"
	)
	_check(raw.size() == int(sidecar.get("binary_byte_size", -1)), "binary golden byte size")
	var golden := raw.to_float64_array()
	_check(golden.size() == EXPECTED_NODE_COUNT, "golden decodes to node count")
	if golden.size() != solve.heights.size():
		_check(false, "height count mismatch vs golden")
		return

	# Full numerical parity over every node — no sampling.
	var max_abs := 0.0
	var sum_abs := 0.0
	var sum_sq := 0.0
	var max_abs_index := -1
	for i in golden.size():
		var error: float = absf(solve.heights[i] - golden[i])
		if error > max_abs:
			max_abs = error
			max_abs_index = i
		sum_abs += error
		sum_sq += error * error
	var mean_abs := sum_abs / float(golden.size())
	var rms := sqrt(sum_sq / float(golden.size()))
	print(
		"parity vs N2 golden: max_abs=%s (node %d) mean_abs=%s rms=%s"
		% [
			String.num_scientific(max_abs),
			max_abs_index,
			String.num_scientific(mean_abs),
			String.num_scientific(rms),
		]
	)
	_check(
		max_abs <= MAX_ABS_ERROR_LIMIT,
		"max abs error <= 1e-5 (measured %s)" % String.num_scientific(max_abs)
	)
	_check(
		rms <= RMS_ERROR_LIMIT,
		"RMS error <= 1e-6 (measured %s)" % String.num_scientific(rms)
	)

	# Center pins: exact canonical heights, and golden agreement within 1e-12.
	var max_pin_error_golden := 0.0
	var max_pin_error_canonical := 0.0
	for node_index in build.pinned_world_y.keys():
		var canonical: float = float(build.pinned_world_y[node_index])
		max_pin_error_canonical = maxf(
			max_pin_error_canonical, absf(solve.heights[node_index] - canonical)
		)
		max_pin_error_golden = maxf(
			max_pin_error_golden, absf(solve.heights[node_index] - golden[node_index])
		)
	print(
		"center pins: error vs canonical=%s, vs golden=%s"
		% [
			String.num_scientific(max_pin_error_canonical),
			String.num_scientific(max_pin_error_golden),
		]
	)
	_check(
		max_pin_error_canonical <= CENTER_PIN_ERROR_LIMIT,
		"center pin error vs canonical <= 1e-12"
	)
	_check(max_pin_error_golden <= CENTER_PIN_ERROR_LIMIT, "center pin error vs golden <= 1e-12")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Ts08HeightSolver N3b tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
