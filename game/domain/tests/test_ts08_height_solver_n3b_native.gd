# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_height_solver_n3b_native.gd
#
# N3b.1b: full native parity, determinism, and benchmark on the reference map.
# - two independent native solves (deterministic, bit-identical);
# - native heights vs the N3b binary height golden (all 74,129 nodes);
# - one native-versus-GDScript comparison (max/mean/RMS difference,
#   iterations, residuals, energies, Y range) — the GDScript path is already
#   parity-locked by test_ts08_height_solver_n3b.gd, so it runs once here;
# - benchmark: lattice build, CSR prep, native PCG, total solve, GDScript
#   reference time, speedup factor, native working memory.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const GOLDEN_BIN_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3b_heights_v1.bin"
const GOLDEN_SIDECAR_PATH := "res://domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3b_heights_v1.json"
const REFERENCE_MAP_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
const N2_CONTENT_HASH := "4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce"

# Reference-map golden values (test-owned).
const EXPECTED_NODE_COUNT := 74129
const EXPECTED_CENTER_PIN_COUNT := 168
const EXPECTED_COMPONENT_COUNT := 1
const EXPECTED_CG_ITERATIONS := 1526
const GOLDEN_Y_MIN := -0.0953001335506
const GOLDEN_Y_MAX := 2.09155970068
const N2_MAX_TENT_POLE := 0.028821815457

# Acceptance limits.
const MAX_ABS_ERROR_LIMIT := 1e-5
const RMS_ERROR_LIMIT := 1e-6
const CENTER_PIN_ERROR_LIMIT := 1e-12
const REL_RESIDUAL_LIMIT := 1e-8
const MIN_SPEEDUP := 5.0

var _total := 0
var _any_fail := false


func _init() -> void:
	if not _require_native_extension():
		_finish()
		return

	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "reference WorldMap loads")
	if world_map == null:
		_finish()
		return
	_check(world_map.identity.content_hash == REFERENCE_MAP_HASH, "reference map hash")

	var t0 := Time.get_ticks_msec()
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var build_msec := Time.get_ticks_msec() - t0
	print("lattice build: %d ms (%d nodes)" % [build_msec, build.node_count])
	_check(build.node_count == EXPECTED_NODE_COUNT, "node count golden")

	# --- native solve A ---
	print("native solve A starting...")
	var native_a = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(native_a != null, "native solve A completed")
	if native_a == null:
		_finish()
		return
	print(
		"native solve A: total %d ms (prep %d ms, cg call %d ms, native internal %d ms)"
		% [native_a.solve_msec, native_a.prep_msec, native_a.cg_msec, native_a.native_internal_msec]
	)
	print(
		"native cg_iterations=%d abs_residual=%s rel_residual=%s"
		% [
			native_a.cg_iterations,
			String.num_scientific(native_a.cg_final_abs_residual),
			String.num_scientific(native_a.cg_final_rel_residual),
		]
	)
	print(
		"native energy_initial=%.12f energy_final=%.12f"
		% [native_a.energy_initial, native_a.energy_final]
	)
	print("native y_min=%.12f y_max=%.12f" % [native_a.y_min, native_a.y_max])
	print(
		"native working memory: %d bytes native buffers + %d bytes GDScript-side arrays"
		% [native_a.native_buffer_bytes, native_a.solver_bytes_estimate]
	)

	_check(native_a.backend == Ts08HeightSolver.BACKEND_NATIVE, "result labeled native")
	_check(native_a.native_cg_plain_invocations == 1, "native kernel invoked exactly once")
	_check(native_a.pinned_center_count == EXPECTED_CENTER_PIN_COUNT, "center pin count")
	_check(native_a.connected_component_count == EXPECTED_COMPONENT_COUNT, "single component")
	_check(native_a.converged, "native CG converged")
	_check(native_a.cg_final_rel_residual <= REL_RESIDUAL_LIMIT, "relative residual <= 1e-8")
	_check(
		native_a.cg_iterations == EXPECTED_CG_ITERATIONS,
		"expected reference-map iteration count %d (measured %d)"
		% [EXPECTED_CG_ITERATIONS, native_a.cg_iterations]
	)
	_check(native_a.energy_final < native_a.energy_initial, "final energy below initial")
	_check(
		native_a.max_center_interpolation_error <= CENTER_PIN_ERROR_LIMIT,
		"center pin error <= 1e-12 (solver)"
	)
	_check(
		native_a.max_tent_pole_delta <= N2_MAX_TENT_POLE + 1e-6,
		"no tent-pole regression"
	)
	_check(absf(native_a.y_min - GOLDEN_Y_MIN) <= MAX_ABS_ERROR_LIMIT, "y_min near golden")
	_check(absf(native_a.y_max - GOLDEN_Y_MAX) <= MAX_ABS_ERROR_LIMIT, "y_max near golden")

	# --- native solve B: determinism ---
	print("native solve B starting...")
	var native_b = Ts08HeightSolver.solve(world_map, build, false, Ts08HeightSolver.BACKEND_NATIVE)
	_check(native_b != null, "native solve B completed")
	if native_b != null:
		print("native solve B: total %d ms" % native_b.solve_msec)
		_check(native_a.heights == native_b.heights, "deterministic native rerun (bit-identical)")
		_check(
			native_a.cg_iterations == native_b.cg_iterations,
			"deterministic native iteration count"
		)

	# --- golden parity (native heights, every node) ---
	_compare_against_golden(build, native_a)

	# --- one GDScript reference comparison + benchmark ---
	print("gdscript reference solve starting (progress every 200 CG iterations)...")
	var gd = Ts08HeightSolver.solve(world_map, build, true, Ts08HeightSolver.BACKEND_GDSCRIPT)
	_check(gd != null, "gdscript solve completed")
	if gd == null:
		_finish()
		return
	print("gdscript solve: total %d ms (prep %d ms, cg %d ms)" % [gd.solve_msec, gd.prep_msec, gd.cg_msec])
	_check(gd.native_cg_plain_invocations == 0, "gdscript run never touched native")

	var max_diff := 0.0
	var sum_diff := 0.0
	var sum_sq := 0.0
	for i in gd.heights.size():
		var diff: float = absf(native_a.heights[i] - gd.heights[i])
		max_diff = maxf(max_diff, diff)
		sum_diff += diff
		sum_sq += diff * diff
	var mean_diff := sum_diff / float(gd.heights.size())
	var rms_diff := sqrt(sum_sq / float(gd.heights.size()))
	print(
		"native vs gdscript: max=%s mean=%s rms=%s"
		% [
			String.num_scientific(max_diff),
			String.num_scientific(mean_diff),
			String.num_scientific(rms_diff),
		]
	)
	print(
		"native vs gdscript iterations: %d vs %d; rel_residual %s vs %s"
		% [
			native_a.cg_iterations,
			gd.cg_iterations,
			String.num_scientific(native_a.cg_final_rel_residual),
			String.num_scientific(gd.cg_final_rel_residual),
		]
	)
	print(
		"native vs gdscript energies: initial %.12f vs %.12f, final %.12f vs %.12f"
		% [native_a.energy_initial, gd.energy_initial, native_a.energy_final, gd.energy_final]
	)
	print(
		"native vs gdscript Y range: [%.12f, %.12f] vs [%.12f, %.12f]"
		% [native_a.y_min, native_a.y_max, gd.y_min, gd.y_max]
	)
	_check(
		native_a.heights == gd.heights,
		"native heights bit-identical to GDScript reference (max diff %s)"
		% String.num_scientific(max_diff)
	)
	_check(native_a.cg_iterations == gd.cg_iterations, "iteration count matches GDScript")

	# --- benchmark summary ---
	var speedup := float(gd.solve_msec) / float(native_a.solve_msec)
	var cg_speedup := float(gd.cg_msec) / float(maxi(native_a.cg_msec, 1))
	print("=== N3b.1b benchmark (reference map, Release DLL) ===")
	print("lattice build:            %d ms" % build_msec)
	print("CSR/pin prep (in solve):  %d ms" % native_a.prep_msec)
	print("native PCG (internal):    %d ms" % native_a.native_internal_msec)
	print("native cg call (wall):    %d ms" % native_a.cg_msec)
	print("native solve total:       %d ms" % native_a.solve_msec)
	print("gdscript solve total:     %d ms (cg %d ms)" % [gd.solve_msec, gd.cg_msec])
	print("speedup (solve total):    %.1fx" % speedup)
	print("speedup (cg path only):   %.1fx" % cg_speedup)
	print("native working memory:    %d bytes (~%.1f MB)" % [
		native_a.native_buffer_bytes, float(native_a.native_buffer_bytes) / 1048576.0
	])
	print("build + native solve:     %d ms (sub-10s target: %s)" % [
		build_msec + native_a.solve_msec,
		"reached" if build_msec + native_a.solve_msec < 10000 else "not reached",
	])
	_check(
		speedup >= MIN_SPEEDUP,
		"native speedup >= %.0fx over GDScript (measured %.1fx)" % [MIN_SPEEDUP, speedup]
	)

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


func _compare_against_golden(build, solve) -> void:
	_check(FileAccess.file_exists(GOLDEN_BIN_PATH), "binary golden exists")
	_check(FileAccess.file_exists(GOLDEN_SIDECAR_PATH), "golden sidecar exists")
	if not FileAccess.file_exists(GOLDEN_BIN_PATH) or not FileAccess.file_exists(GOLDEN_SIDECAR_PATH):
		return

	var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_SIDECAR_PATH))
	_check(sidecar is Dictionary, "sidecar JSON parses")
	if not sidecar is Dictionary:
		return
	_check(sidecar.get("source_n2_content_hash", "") == N2_CONTENT_HASH, "sidecar N2 hash lock")

	var raw := FileAccess.get_file_as_bytes(GOLDEN_BIN_PATH)
	_check(
		MapContentLoader.sha256_hex_lower(raw) == str(sidecar.get("binary_sha256", "")),
		"binary golden SHA-256 matches sidecar"
	)
	var golden := raw.to_float64_array()
	_check(golden.size() == EXPECTED_NODE_COUNT, "golden decodes to node count")
	if golden.size() != solve.heights.size():
		_check(false, "height count mismatch vs golden")
		return

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
		"native parity vs N2 golden: max_abs=%s (node %d) mean_abs=%s rms=%s"
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
	_check(rms <= RMS_ERROR_LIMIT, "RMS error <= 1e-6 (measured %s)" % String.num_scientific(rms))

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
		"native center pins: error vs canonical=%s, vs golden=%s"
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
	print("Ts08HeightSolver N3b native tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
