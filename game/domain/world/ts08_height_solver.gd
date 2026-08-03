# TS-08 Stage-2 cut-domain thin-plate CG height solver (N3b). Domain-only.
#
# Inputs: the authoritative WorldMap plus an N3a Ts08CutLattice.BuildResult.
# Never loads N2, Blender data, or any pre-solved terrain file.
#
# Ports the accepted Python reference solvers
# (tools/blender/terrain/eom_terrain_ts08_thin_plate_cg.py,
#  tools/blender/terrain/eom_terrain_ts08_stage2_cut_thin_plate_cg.py)
# per docs/TERRAIN_SURFACE_TARGET.md:
# - normalized umbrella Laplacian  Lz[i] = z[i] - sum(z[j in N(i)]) / degree[i]
# - bending operator B = LtL applied as two CSR passes
# - hard center pins by elimination (pin slots held at zero in all CG vectors)
# - Jacobi-preconditioned Conjugate Gradient, rel tol 1e-8, max 40000 iterations
# - deterministic planar least-squares warm start over all pins
# - component routing: rank 3 -> plain CG (no gauge machinery instantiated);
#   rank 1 -> analytic constant; rank 2 affine-consistent -> analytic plane;
#   rank 2 non-affine collinear -> deflated CG + exact gauge post-projection.
#
# No TPS, FEM, relaxation, membrane regularization, z=0 pull, rim constraints,
# rails, or cross-cliff coupling. All math is float64 scalar on packed arrays.
class_name Ts08HeightSolver
extends RefCounted

const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")

const CG_REL_TOL := 1e-8
const CG_MAX_ITERATIONS := 40000
# Spectral scale for the rank-one deflation term B' = B + sigma * g g^T
# (diag(B) is ~1.2 on this lattice, so 1.0 is well inside the spectrum).
const DEFLATION_SIGMA := 1.0
const AFFINE_CONSISTENCY_EPS := 1e-9

const GAUGE_CG_PLAIN := "cg_plain"
const GAUGE_ANALYTIC_CONSTANT := "analytic_constant"
const GAUGE_ANALYTIC_PLANE := "analytic_plane"
const GAUGE_CG_DEFLATED := "cg_deflated"

# Backend selection (N3b.1b). The GDScript path stays the verified reference
# and default; the native path is explicit opt-in and only accelerates the
# global cg_plain PCG. Census/routing, analytic constant/plane, and deflated
# CG always run in GDScript on every backend. When the native backend is
# requested but the GDExtension is unavailable, solve() fails loudly
# (push_error + null) — it never silently falls back.
const BACKEND_GDSCRIPT := "gdscript"
const BACKEND_NATIVE := "native"
const NATIVE_CLASS_NAME := &"EomTerrainNative"


class SolveResult extends RefCounted:
	var heights := PackedFloat64Array()
	var node_count: int = 0
	var pinned_center_count: int = 0
	var connected_component_count: int = 0
	var deficient_component_count: int = 0
	var cg_iterations: int = 0
	var cg_final_abs_residual: float = 0.0
	var cg_final_rel_residual: float = 0.0
	var energy_initial: float = 0.0
	var energy_final: float = 0.0
	var y_min: float = 0.0
	var y_max: float = 0.0
	var max_center_interpolation_error: float = 0.0
	var max_tent_pole_delta: float = 0.0
	var converged: bool = false
	var component_reports: Array = []
	var gauge_convention_applied_count: int = 0
	# Structural code-path counter: incremented only when deflation machinery
	# is actually instantiated. Must be zero on maps with only rank-3 components.
	var deflation_instantiated_count: int = 0
	var solver_bytes_estimate: int = 0
	var solve_msec: int = 0
	# N3b.1b backend diagnostics.
	var backend := "gdscript"
	# Incremented only when the native kernel actually ran; must stay zero
	# for analytic and deflated routes even when the native backend is
	# requested (they always run in GDScript).
	var native_cg_plain_invocations: int = 0
	var prep_msec: int = 0
	var cg_msec: int = 0
	var native_internal_msec: int = 0
	var native_buffer_bytes: int = 0


static func solve(
	world_map, build, verbose: bool = false, backend: String = BACKEND_GDSCRIPT
) -> SolveResult:
	var started_msec := Time.get_ticks_msec()
	var native_backend: Object = null
	if backend == BACKEND_NATIVE:
		native_backend = _instantiate_native_backend()
		if native_backend == null:
			return null
	elif backend != BACKEND_GDSCRIPT:
		push_error("Ts08HeightSolver: unknown backend '%s'" % backend)
		return null
	var n: int = build.node_count
	var result := SolveResult.new()
	result.node_count = n
	result.backend = backend

	# --- pins (sorted, values in Godot Y / world-height units) ---
	var pinned_idx: Array = build.pinned_world_y.keys()
	pinned_idx.sort()
	var pin_count := pinned_idx.size()
	result.pinned_center_count = pin_count
	var z_pin := PackedFloat64Array()
	z_pin.resize(pin_count)
	for i in pin_count:
		z_pin[i] = float(build.pinned_world_y[pinned_idx[i]])
	var is_pinned := PackedByteArray()
	is_pinned.resize(n)
	for i in pin_count:
		is_pinned[pinned_idx[i]] = 1

	# --- CSR neighbor arrays ---
	var neighbor_ptr := PackedInt32Array()
	neighbor_ptr.resize(n + 1)
	var total_neighbors := 0
	for i in n:
		total_neighbors += (build.adjacency[i] as Array).size()
	var neighbor_idx := PackedInt32Array()
	neighbor_idx.resize(total_neighbors)
	var degrees := PackedFloat64Array()
	degrees.resize(n)
	var cursor := 0
	for i in n:
		neighbor_ptr[i] = cursor
		var neighbors: Array = build.adjacency[i]
		for neighbor in neighbors:
			neighbor_idx[cursor] = neighbor
			cursor += 1
		degrees[i] = maxf(float(neighbors.size()), 1.0)
	neighbor_ptr[n] = cursor
	result.prep_msec = Time.get_ticks_msec() - started_msec

	# --- component census and routing ---
	var component_reports := _build_component_reports(world_map, build)
	result.connected_component_count = component_reports.size()
	for report in component_reports:
		if not report["fully_determined"]:
			result.deficient_component_count += 1

	var z_full := PackedFloat64Array()
	z_full.resize(n)

	var cg_plain_present := false
	for report in component_reports:
		var method: String = report["gauge_method"]
		if method == GAUGE_CG_PLAIN:
			cg_plain_present = true
			continue
		var component_nodes := _component_nodes(build, report["component_id"])
		var pin_nodes: Array = []
		for node_index in component_nodes:
			if is_pinned[node_index] == 1:
				pin_nodes.append(node_index)
		if method == GAUGE_ANALYTIC_CONSTANT:
			_apply_analytic_constant(
				z_full, component_nodes, float(build.pinned_world_y[pin_nodes[0]])
			)
			report["gauge_convention_applied"] = true
			result.gauge_convention_applied_count += 1
		elif method == GAUGE_ANALYTIC_PLANE:
			_apply_analytic_plane(build, z_full, component_nodes, pin_nodes, report)
			report["gauge_convention_applied"] = true
			result.gauge_convention_applied_count += 1
		elif method == GAUGE_CG_DEFLATED:
			result.deflation_instantiated_count += 1
			var deflated_ok := _solve_component_deflated(
				build,
				z_full,
				component_nodes,
				pin_nodes,
				neighbor_idx,
				neighbor_ptr,
				degrees,
				report,
				verbose
			)
			report["gauge_convention_applied"] = true
			result.gauge_convention_applied_count += 1
			if not deflated_ok:
				push_warning("Ts08HeightSolver: deflated CG did not converge on component %d"
					% int(report["component_id"]))
		else:
			push_error("Ts08HeightSolver: unsupported gauge method %s" % method)

	# --- global plain CG over all free nodes (mirrors Python Stage 2) ---
	var all_converged := true
	if cg_plain_present:
		var cg_started_msec := Time.get_ticks_msec()
		var cg: Dictionary
		if native_backend != null:
			cg = _solve_cg_plain_global_native(
				native_backend,
				build,
				n,
				pinned_idx,
				z_pin,
				neighbor_idx,
				neighbor_ptr,
				degrees,
				verbose
			)
			if cg.is_empty():
				push_error("Ts08HeightSolver: native cg_plain kernel rejected its input")
				return null
			result.native_cg_plain_invocations += 1
			result.native_internal_msec = int(cg.get("native_msec", 0))
			result.native_buffer_bytes = int(cg.get("buffer_bytes", 0))
		else:
			cg = _solve_cg_plain_global(
				build,
				n,
				pinned_idx,
				z_pin,
				is_pinned,
				neighbor_idx,
				neighbor_ptr,
				degrees,
				verbose
			)
		result.cg_msec = Time.get_ticks_msec() - cg_started_msec
		result.cg_iterations = cg["iterations"]
		result.cg_final_abs_residual = cg["abs_residual"]
		result.cg_final_rel_residual = cg["rel_residual"]
		result.energy_initial = cg["energy_initial"]
		result.energy_final = cg["energy_final"]
		all_converged = cg["converged"]
		var z_cg: PackedFloat64Array = cg["z_full"]
		for report in component_reports:
			if report["gauge_method"] != GAUGE_CG_PLAIN:
				continue
			for node_index in _component_nodes(build, report["component_id"]):
				z_full[node_index] = z_cg[node_index]
	for report in component_reports:
		if report["gauge_method"] == GAUGE_CG_DEFLATED and not report.get("converged", true):
			all_converged = false
	result.converged = all_converged

	# --- metrics on the assembled surface ---
	var max_center_error := 0.0
	for i in pin_count:
		var error: float = absf(z_full[pinned_idx[i]] - z_pin[i])
		if error > max_center_error:
			max_center_error = error
	result.max_center_interpolation_error = max_center_error

	var max_tent_pole := 0.0
	for i in pin_count:
		var node_index: int = pinned_idx[i]
		var center_z := z_full[node_index]
		for neighbor in build.adjacency[node_index]:
			var delta: float = absf(center_z - z_full[neighbor])
			if delta > max_tent_pole:
				max_tent_pole = delta
	result.max_tent_pole_delta = max_tent_pole

	if n > 0:
		var y_min := z_full[0]
		var y_max := z_full[0]
		for i in range(1, n):
			var value := z_full[i]
			if value < y_min:
				y_min = value
			if value > y_max:
				y_max = value
		result.y_min = y_min
		result.y_max = y_max

	if result.energy_final > result.energy_initial + 1e-9:
		push_warning(
			"Ts08HeightSolver: energy did not decrease: initial=%s final=%s"
			% [
				String.num_scientific(result.energy_initial),
				String.num_scientific(result.energy_final),
			]
		)
	if not all_converged:
		push_warning(
			"Ts08HeightSolver: CG did not converge within %d iterations (rel=%s tol=%s)"
			% [
				CG_MAX_ITERATIONS,
				String.num_scientific(result.cg_final_rel_residual),
				String.num_scientific(CG_REL_TOL),
			]
		)

	result.heights = z_full
	result.component_reports = component_reports
	# CSR ints (idx + ptr) at 4 bytes, degrees + 8 float64 work vectors at 8 bytes.
	result.solver_bytes_estimate = (
		neighbor_idx.size() * 4 + neighbor_ptr.size() * 4 + degrees.size() * 8 + 8 * n * 8
	)
	result.solve_msec = Time.get_ticks_msec() - started_msec
	return result


# ---------------------------------------------------------------------------
# Component census (exact integer axial collinearity; no float epsilon).
# ---------------------------------------------------------------------------


static func _build_component_reports(world_map, build) -> Array:
	var component_count := 0
	for cid in build.component_ids:
		if cid + 1 > component_count:
			component_count = cid + 1

	var pin_hexes_by_component: Dictionary = {}
	for node_index in build.pin_hex_by_node.keys():
		var cid: int = build.component_ids[node_index]
		if not pin_hexes_by_component.has(cid):
			pin_hexes_by_component[cid] = {}
		pin_hexes_by_component[cid][build.pin_hex_by_node[node_index]] = true

	var node_counts := PackedInt32Array()
	node_counts.resize(component_count)
	for cid in build.component_ids:
		node_counts[cid] += 1

	var reports: Array = []
	for component_id in component_count:
		var pin_hexes: Array = []
		if pin_hexes_by_component.has(component_id):
			pin_hexes = pin_hexes_by_component[component_id].keys()
		pin_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Ts08TerrainMathScript.compare_tile_coords(a, b) < 0
		)
		var pin_z: Array = []
		for hex in pin_hexes:
			pin_z.append(Ts08TerrainMathScript.canonical_center_world_y(
				world_map.tile_at(hex.x, hex.y).elevation,
				world_map.elevation_step,
				world_map.elevation_base
			))
		var rank_info := _pin_rank(pin_hexes, pin_z)
		var rank: int = rank_info["rank"]
		var collinear_non_affine: bool = rank_info["collinear_non_affine"]
		reports.append({
			"component_id": component_id,
			"node_count": node_counts[component_id],
			"hex_count": pin_hexes.size(),
			"pin_rank": rank,
			"fully_determined": rank >= 3,
			"collinear_non_affine": collinear_non_affine,
			"gauge_method": _gauge_method_for_rank(rank, collinear_non_affine),
			"gauge_convention_applied": false,
		})
	return reports


static func _axial_cross(a: Vector2i, b: Vector2i, c: Vector2i) -> int:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


static func _pin_rank(hexes: Array, world_y: Array) -> Dictionary:
	if hexes.size() <= 1:
		return {"rank": 1, "collinear_non_affine": false}
	if hexes.size() == 2:
		return {"rank": 2, "collinear_non_affine": false}
	for index in range(2, hexes.size()):
		if _axial_cross(hexes[0], hexes[1], hexes[index]) != 0:
			return {"rank": 3, "collinear_non_affine": false}
	var direction: Vector2i = hexes[1] - hexes[0]
	if direction == Vector2i.ZERO:
		return {"rank": 1, "collinear_non_affine": false}
	var t_values: Array = []
	for hex in hexes:
		var delta: Vector2i = hex - hexes[0]
		t_values.append(delta.x * direction.x + delta.y * direction.y)
	var t_mean := 0.0
	var z_mean := 0.0
	for i in t_values.size():
		t_mean += float(t_values[i])
		z_mean += float(world_y[i])
	t_mean /= float(t_values.size())
	z_mean /= float(t_values.size())
	var num := 0.0
	var den := 0.0
	for i in t_values.size():
		num += (float(t_values[i]) - t_mean) * (float(world_y[i]) - z_mean)
		den += (float(t_values[i]) - t_mean) * (float(t_values[i]) - t_mean)
	var slope := num / den if den != 0.0 else 0.0
	var max_err := 0.0
	for i in t_values.size():
		var fitted := z_mean + slope * (float(t_values[i]) - t_mean)
		max_err = maxf(max_err, absf(float(world_y[i]) - fitted))
	return {"rank": 2, "collinear_non_affine": max_err > AFFINE_CONSISTENCY_EPS}


static func _gauge_method_for_rank(rank: int, collinear_non_affine: bool) -> String:
	if rank >= 3:
		return GAUGE_CG_PLAIN
	if rank == 1:
		return GAUGE_ANALYTIC_CONSTANT
	if collinear_non_affine:
		return GAUGE_CG_DEFLATED
	return GAUGE_ANALYTIC_PLANE


static func _component_nodes(build, component_id: int) -> PackedInt32Array:
	var nodes := PackedInt32Array()
	for index in build.component_ids.size():
		if build.component_ids[index] == component_id:
			nodes.append(index)
	return nodes


# ---------------------------------------------------------------------------
# Analytic deficient-component routes (gauge convention).
# ---------------------------------------------------------------------------


static func _apply_analytic_constant(
	z_full: PackedFloat64Array,
	component_nodes: PackedInt32Array,
	z_value: float
) -> void:
	for node_index in component_nodes:
		z_full[node_index] = z_value


static func _apply_analytic_plane(
	build,
	z_full: PackedFloat64Array,
	component_nodes: PackedInt32Array,
	pin_nodes: Array,
	report: Dictionary
) -> void:
	# Least-squares line fit along the pin line (equals the two-pin plane
	# formula for exactly two pins; exact for affine-consistent pins).
	var x0: float = build.node_plane_x[pin_nodes[0]]
	var y0: float = build.node_plane_y[pin_nodes[0]]
	var xl: float = build.node_plane_x[pin_nodes[pin_nodes.size() - 1]]
	var yl: float = build.node_plane_y[pin_nodes[pin_nodes.size() - 1]]
	var dx := xl - x0
	var dy := yl - y0
	var dist_sq := dx * dx + dy * dy
	if dist_sq <= 0.0:
		for node_index in component_nodes:
			z_full[node_index] = float(build.pinned_world_y[pin_nodes[0]])
		return
	var dist := sqrt(dist_sq)
	var ux := dx / dist
	var uy := dy / dist
	var t_mean := 0.0
	var z_mean := 0.0
	for pin_node in pin_nodes:
		t_mean += (build.node_plane_x[pin_node] - x0) * ux + (build.node_plane_y[pin_node] - y0) * uy
		z_mean += float(build.pinned_world_y[pin_node])
	t_mean /= float(pin_nodes.size())
	z_mean /= float(pin_nodes.size())
	var num := 0.0
	var den := 0.0
	for pin_node in pin_nodes:
		var t: float = (
			(build.node_plane_x[pin_node] - x0) * ux + (build.node_plane_y[pin_node] - y0) * uy
		)
		num += (t - t_mean) * (float(build.pinned_world_y[pin_node]) - z_mean)
		den += (t - t_mean) * (t - t_mean)
	var slope := num / den if den != 0.0 else 0.0
	for node_index in component_nodes:
		var t: float = (
			(build.node_plane_x[node_index] - x0) * ux
			+ (build.node_plane_y[node_index] - y0) * uy
		)
		z_full[node_index] = z_mean + slope * (t - t_mean)
	report["selected_affine_gradient"] = [slope * ux, slope * uy]


# ---------------------------------------------------------------------------
# Operator kernels (CSR, float64). B = LtL with normalized umbrella L.
# ---------------------------------------------------------------------------


static func _apply_L(
	z: PackedFloat64Array,
	out: PackedFloat64Array,
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	n: int
) -> void:
	var ptr0: int = neighbor_ptr[0]
	for i in n:
		var ptr1: int = neighbor_ptr[i + 1]
		var acc := 0.0
		for k in range(ptr0, ptr1):
			acc += z[neighbor_idx[k]]
		out[i] = z[i] - acc / degrees[i]
		ptr0 = ptr1


# Adjacency is symmetric, so LtW can be computed as a gather:
# (LtW)[i] = w[i] - sum(w[j] / degree[j]) over j in N(i).
static func _apply_LT(
	w: PackedFloat64Array,
	out: PackedFloat64Array,
	scaled: PackedFloat64Array,
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	n: int
) -> void:
	for i in n:
		scaled[i] = w[i] / degrees[i]
	var ptr0: int = neighbor_ptr[0]
	for i in n:
		var ptr1: int = neighbor_ptr[i + 1]
		var acc := 0.0
		for k in range(ptr0, ptr1):
			acc += scaled[neighbor_idx[k]]
		out[i] = w[i] - acc
		ptr0 = ptr1


static func _energy(
	z: PackedFloat64Array,
	work: PackedFloat64Array,
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	n: int
) -> float:
	_apply_L(z, work, neighbor_idx, neighbor_ptr, degrees, n)
	var total := 0.0
	for i in n:
		total += work[i] * work[i]
	return total


static func _jacobi_diagonal(
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	n: int
) -> PackedFloat64Array:
	var diag := PackedFloat64Array()
	diag.resize(n)
	var ptr0: int = neighbor_ptr[0]
	for i in n:
		var ptr1: int = neighbor_ptr[i + 1]
		var acc := 1.0
		for k in range(ptr0, ptr1):
			var j: int = neighbor_idx[k]
			acc += 1.0 / (degrees[j] * degrees[j])
		diag[i] = acc
		ptr0 = ptr1
	return diag


# ---------------------------------------------------------------------------
# Native backend (N3b.1b): explicit opt-in acceleration of the global plain
# PCG only. Fails loudly when the GDExtension is not available or stale.
# ---------------------------------------------------------------------------


static func _instantiate_native_backend() -> Object:
	if not ClassDB.can_instantiate(NATIVE_CLASS_NAME):
		push_error(
			"Ts08HeightSolver: native backend requested but EomTerrainNative is not "
			+ "available. Build the GDExtension (scripts/build-native.ps1) so "
			+ "game/bin/eom_native.gdextension exists and is loaded, or use the "
			+ "GDScript backend."
		)
		return null
	var instance: Object = ClassDB.instantiate(NATIVE_CLASS_NAME)
	if instance == null or not instance.has_method("solve_cg_plain_global"):
		push_error(
			"Ts08HeightSolver: EomTerrainNative is stale (missing solve_cg_plain_global); "
			+ "rebuild the GDExtension via scripts/build-native.ps1."
		)
		return null
	return instance


# One GDScript/C++ crossing per solve: packed CSR/pin/warm-start arrays in,
# heights plus convergence diagnostics out. The warm start stays the exact
# deterministic GDScript _planar_warm_start.
static func _solve_cg_plain_global_native(
	native_backend: Object,
	build,
	n: int,
	pinned_idx: Array,
	z_pin: PackedFloat64Array,
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	verbose: bool
) -> Dictionary:
	var pinned_idx_packed := PackedInt32Array()
	pinned_idx_packed.resize(pinned_idx.size())
	for i in pinned_idx.size():
		pinned_idx_packed[i] = pinned_idx[i]
	var z_warm := _planar_warm_start(build, pinned_idx, z_pin, n)
	return native_backend.solve_cg_plain_global(
		neighbor_ptr,
		neighbor_idx,
		degrees,
		pinned_idx_packed,
		z_pin,
		z_warm,
		CG_REL_TOL,
		CG_MAX_ITERATIONS,
		verbose
	)


# ---------------------------------------------------------------------------
# Global plain PCG (pins eliminated by holding pin slots at zero).
# ---------------------------------------------------------------------------


static func _solve_cg_plain_global(
	build,
	n: int,
	pinned_idx: Array,
	z_pin: PackedFloat64Array,
	is_pinned: PackedByteArray,
	neighbor_idx: PackedInt32Array,
	neighbor_ptr: PackedInt32Array,
	degrees: PackedFloat64Array,
	verbose: bool
) -> Dictionary:
	var pin_count := pinned_idx.size()
	var work_l := PackedFloat64Array()
	work_l.resize(n)
	var work_scaled := PackedFloat64Array()
	work_scaled.resize(n)
	var b_out := PackedFloat64Array()
	b_out.resize(n)

	var z_pin_embedded := PackedFloat64Array()
	z_pin_embedded.resize(n)
	for i in pin_count:
		z_pin_embedded[pinned_idx[i]] = z_pin[i]

	# rhs = -B(z_pin_embedded) restricted to free nodes (pin slots zeroed).
	_apply_L(z_pin_embedded, work_l, neighbor_idx, neighbor_ptr, degrees, n)
	_apply_LT(work_l, b_out, work_scaled, neighbor_idx, neighbor_ptr, degrees, n)
	var rhs := PackedFloat64Array()
	rhs.resize(n)
	for i in n:
		rhs[i] = -b_out[i]
	for i in pin_count:
		rhs[pinned_idx[i]] = 0.0
	var rhs_norm_sq := 0.0
	for i in n:
		rhs_norm_sq += rhs[i] * rhs[i]
	var rhs_norm := sqrt(rhs_norm_sq)

	# Deterministic planar least-squares warm start over all pins.
	var z_warm := _planar_warm_start(build, pinned_idx, z_pin, n)
	var energy_initial := _energy(z_warm, work_l, neighbor_idx, neighbor_ptr, degrees, n)

	var x := PackedFloat64Array()
	x.resize(n)
	for i in n:
		x[i] = z_warm[i]
	for i in pin_count:
		x[pinned_idx[i]] = 0.0

	var diag := _jacobi_diagonal(neighbor_idx, neighbor_ptr, degrees, n)
	var precond_inv := PackedFloat64Array()
	precond_inv.resize(n)
	for i in n:
		precond_inv[i] = 1.0 / diag[i]

	# r = rhs - B x (pin slots zeroed)
	var r := PackedFloat64Array()
	r.resize(n)
	_apply_L(x, work_l, neighbor_idx, neighbor_ptr, degrees, n)
	_apply_LT(work_l, b_out, work_scaled, neighbor_idx, neighbor_ptr, degrees, n)
	for i in n:
		r[i] = rhs[i] - b_out[i]
	for i in pin_count:
		r[pinned_idx[i]] = 0.0

	var abs_residual := 0.0
	for i in n:
		abs_residual += r[i] * r[i]
	abs_residual = sqrt(abs_residual)
	var rel_residual := abs_residual / rhs_norm if rhs_norm > 0.0 else 0.0

	var z := PackedFloat64Array()
	z.resize(n)
	var p := PackedFloat64Array()
	p.resize(n)
	for i in n:
		z[i] = precond_inv[i] * r[i]
		p[i] = z[i]
	var rsold := 0.0
	for i in n:
		rsold += r[i] * z[i]

	var iterations := 0
	var converged := rel_residual <= CG_REL_TOL

	if not converged and rhs_norm > 0.0:
		for iteration in CG_MAX_ITERATIONS:
			# Ap = B p (pin slots zeroed)
			_apply_L(p, work_l, neighbor_idx, neighbor_ptr, degrees, n)
			_apply_LT(work_l, b_out, work_scaled, neighbor_idx, neighbor_ptr, degrees, n)
			for i in pin_count:
				b_out[pinned_idx[i]] = 0.0
			var p_ap := 0.0
			for i in n:
				p_ap += p[i] * b_out[i]
			var alpha := rsold / p_ap
			var r_norm_sq := 0.0
			for i in n:
				x[i] += alpha * p[i]
				r[i] -= alpha * b_out[i]
				r_norm_sq += r[i] * r[i]
			abs_residual = sqrt(r_norm_sq)
			rel_residual = abs_residual / rhs_norm
			iterations = iteration + 1
			if verbose and iterations % 200 == 0:
				print(
					"  cg iteration %d rel_residual=%s"
					% [iterations, String.num_scientific(rel_residual)]
				)
			if rel_residual <= CG_REL_TOL:
				converged = true
				break
			var rsnew := 0.0
			for i in n:
				z[i] = precond_inv[i] * r[i]
				rsnew += r[i] * z[i]
			var beta := rsnew / rsold
			for i in n:
				p[i] = z[i] + beta * p[i]
			rsold = rsnew

	var z_full := PackedFloat64Array()
	z_full.resize(n)
	for i in n:
		z_full[i] = z_pin_embedded[i] + x[i]
	var energy_final := _energy(z_full, work_l, neighbor_idx, neighbor_ptr, degrees, n)

	return {
		"z_full": z_full,
		"iterations": iterations,
		"abs_residual": abs_residual,
		"rel_residual": rel_residual,
		"energy_initial": energy_initial,
		"energy_final": energy_final,
		"converged": converged,
	}


static func _planar_warm_start(
	build,
	pinned_idx: Array,
	z_pin: PackedFloat64Array,
	n: int
) -> PackedFloat64Array:
	# Least squares of z ~ c0 + c1*x + c2*y over pins via 3x3 normal equations.
	var ata := [
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
	]
	var atb := [0.0, 0.0, 0.0]
	for i in pinned_idx.size():
		var px: float = build.node_plane_x[pinned_idx[i]]
		var py: float = build.node_plane_y[pinned_idx[i]]
		var pz := z_pin[i]
		var row := [1.0, px, py]
		for a in 3:
			for b in 3:
				ata[a][b] += row[a] * row[b]
			atb[a] += row[a] * pz
	var coeff := _solve_3x3(ata, atb)
	var z_full := PackedFloat64Array()
	z_full.resize(n)
	for i in n:
		z_full[i] = coeff[0] + coeff[1] * build.node_plane_x[i] + coeff[2] * build.node_plane_y[i]
	for i in pinned_idx.size():
		z_full[pinned_idx[i]] = z_pin[i]
	return z_full


static func _solve_3x3(matrix: Array, rhs: Array) -> Array:
	var a := [
		[matrix[0][0], matrix[0][1], matrix[0][2], rhs[0]],
		[matrix[1][0], matrix[1][1], matrix[1][2], rhs[1]],
		[matrix[2][0], matrix[2][1], matrix[2][2], rhs[2]],
	]
	for col in 3:
		var pivot_row := col
		var pivot_abs: float = absf(a[col][col])
		for row in range(col + 1, 3):
			if absf(a[row][col]) > pivot_abs:
				pivot_abs = absf(a[row][col])
				pivot_row = row
		if pivot_row != col:
			var tmp: Array = a[col]
			a[col] = a[pivot_row]
			a[pivot_row] = tmp
		if a[col][col] == 0.0:
			continue
		for row in range(col + 1, 3):
			var factor: float = a[row][col] / a[col][col]
			for k in range(col, 4):
				a[row][k] -= factor * a[col][k]
	var out := [0.0, 0.0, 0.0]
	for col in [2, 1, 0]:
		if a[col][col] == 0.0:
			out[col] = 0.0
			continue
		var acc: float = a[col][3]
		for k in range(col + 1, 3):
			acc -= a[col][k] * out[k]
		out[col] = acc / a[col][col]
	return out


# ---------------------------------------------------------------------------
# Deflated CG route for rank-2 non-affine collinear components.
# Solves the component subsystem with B' = B + sigma * g g^T (g = perpendicular
# affine tilt mode, zero at every pin), then applies exact post-projection so
# the component-mean gradient has zero projection onto the tilt direction.
# ---------------------------------------------------------------------------


static func _solve_component_deflated(
	build,
	z_full: PackedFloat64Array,
	component_nodes: PackedInt32Array,
	pin_nodes: Array,
	global_neighbor_idx: PackedInt32Array,
	global_neighbor_ptr: PackedInt32Array,
	global_degrees: PackedFloat64Array,
	report: Dictionary,
	verbose: bool
) -> bool:
	var m := component_nodes.size()
	var local_of: Dictionary = {}
	for local in m:
		local_of[component_nodes[local]] = local

	# Local CSR (component subgraph; adjacency never crosses components).
	var neighbor_ptr := PackedInt32Array()
	neighbor_ptr.resize(m + 1)
	var neighbor_list := PackedInt32Array()
	var degrees := PackedFloat64Array()
	degrees.resize(m)
	var cursor := 0
	for local in m:
		neighbor_ptr[local] = cursor
		var global_index: int = component_nodes[local]
		for k in range(global_neighbor_ptr[global_index], global_neighbor_ptr[global_index + 1]):
			neighbor_list.append(local_of[global_neighbor_idx[k]])
			cursor += 1
		degrees[local] = global_degrees[global_index]
	neighbor_ptr[m] = cursor

	# Pin line direction u and perpendicular tilt direction nhat (plane XY).
	var p0x: float = build.node_plane_x[pin_nodes[0]]
	var p0y: float = build.node_plane_y[pin_nodes[0]]
	var p1x: float = build.node_plane_x[pin_nodes[pin_nodes.size() - 1]]
	var p1y: float = build.node_plane_y[pin_nodes[pin_nodes.size() - 1]]
	var dx := p1x - p0x
	var dy := p1y - p0y
	var dist := sqrt(dx * dx + dy * dy)
	var ux := dx / dist
	var uy := dy / dist
	var nx := -uy
	var ny := ux

	# Tilt mode g on the component (vanishes at every pin: pins lie on the line).
	var g := PackedFloat64Array()
	g.resize(m)
	for local in m:
		var global_index: int = component_nodes[local]
		g[local] = (
			(build.node_plane_x[global_index] - p0x) * nx
			+ (build.node_plane_y[global_index] - p0y) * ny
		)
	var is_pinned_local := PackedByteArray()
	is_pinned_local.resize(m)
	var pin_locals: Array = []
	var z_pin_local := PackedFloat64Array()
	for pin_node in pin_nodes:
		var local: int = local_of[pin_node]
		is_pinned_local[local] = 1
		pin_locals.append(local)
		z_pin_local.append(float(build.pinned_world_y[pin_node]))
	# Normalize g over free entries (pin entries already ~0; force exact zero).
	for local in pin_locals:
		g[local] = 0.0
	var g_norm_sq := 0.0
	for local in m:
		g_norm_sq += g[local] * g[local]
	var g_norm := sqrt(g_norm_sq)
	if g_norm > 0.0:
		for local in m:
			g[local] /= g_norm

	var work_l := PackedFloat64Array()
	work_l.resize(m)
	var work_scaled := PackedFloat64Array()
	work_scaled.resize(m)
	var b_out := PackedFloat64Array()
	b_out.resize(m)

	var z_pin_embedded := PackedFloat64Array()
	z_pin_embedded.resize(m)
	for i in pin_locals.size():
		z_pin_embedded[pin_locals[i]] = z_pin_local[i]

	var apply_b_deflated := func(vec: PackedFloat64Array, out: PackedFloat64Array) -> void:
		_apply_L(vec, work_l, neighbor_list, neighbor_ptr, degrees, m)
		_apply_LT(work_l, out, work_scaled, neighbor_list, neighbor_ptr, degrees, m)
		var g_dot := 0.0
		for i in m:
			g_dot += g[i] * vec[i]
		var scale := DEFLATION_SIGMA * g_dot
		for i in m:
			out[i] += scale * g[i]
		for local in pin_locals:
			out[local] = 0.0

	apply_b_deflated.call(z_pin_embedded, b_out)
	var rhs := PackedFloat64Array()
	rhs.resize(m)
	for i in m:
		rhs[i] = -b_out[i]
	for local in pin_locals:
		rhs[local] = 0.0
	var rhs_norm_sq := 0.0
	for i in m:
		rhs_norm_sq += rhs[i] * rhs[i]
	var rhs_norm := sqrt(rhs_norm_sq)

	# Warm start: along-line least-squares profile (zero perpendicular tilt).
	var x := PackedFloat64Array()
	x.resize(m)
	_warm_start_along_line(build, component_nodes, pin_nodes, p0x, p0y, ux, uy, x)
	for i in pin_locals.size():
		x[pin_locals[i]] = 0.0

	# Jacobi diagonal of B' = diag(B) + sigma * g^2.
	var precond_inv := PackedFloat64Array()
	precond_inv.resize(m)
	var diag := _jacobi_diagonal(neighbor_list, neighbor_ptr, degrees, m)
	for i in m:
		precond_inv[i] = 1.0 / (diag[i] + DEFLATION_SIGMA * g[i] * g[i])

	var r := PackedFloat64Array()
	r.resize(m)
	apply_b_deflated.call(x, b_out)
	for i in m:
		r[i] = rhs[i] - b_out[i]
	for local in pin_locals:
		r[local] = 0.0
	var abs_residual := 0.0
	for i in m:
		abs_residual += r[i] * r[i]
	abs_residual = sqrt(abs_residual)
	var rel_residual := abs_residual / rhs_norm if rhs_norm > 0.0 else 0.0

	var z := PackedFloat64Array()
	z.resize(m)
	var p := PackedFloat64Array()
	p.resize(m)
	for i in m:
		z[i] = precond_inv[i] * r[i]
		p[i] = z[i]
	var rsold := 0.0
	for i in m:
		rsold += r[i] * z[i]

	var iterations := 0
	var converged := rel_residual <= CG_REL_TOL
	if not converged and rhs_norm > 0.0:
		for iteration in CG_MAX_ITERATIONS:
			apply_b_deflated.call(p, b_out)
			var p_ap := 0.0
			for i in m:
				p_ap += p[i] * b_out[i]
			var alpha := rsold / p_ap
			var r_norm_sq := 0.0
			for i in m:
				x[i] += alpha * p[i]
				r[i] -= alpha * b_out[i]
				r_norm_sq += r[i] * r[i]
			abs_residual = sqrt(r_norm_sq)
			rel_residual = abs_residual / rhs_norm
			iterations = iteration + 1
			if verbose and iterations % 200 == 0:
				print(
					"  deflated cg iteration %d rel_residual=%s"
					% [iterations, String.num_scientific(rel_residual)]
				)
			if rel_residual <= CG_REL_TOL:
				converged = true
				break
			var rsnew := 0.0
			for i in m:
				z[i] = precond_inv[i] * r[i]
				rsnew += r[i] * z[i]
			var beta := rsnew / rsold
			for i in m:
				p[i] = z[i] + beta * p[i]
			rsold = rsnew

	var z_local := PackedFloat64Array()
	z_local.resize(m)
	for i in m:
		z_local[i] = z_pin_embedded[i] + x[i]

	var energy_before := _energy(z_local, work_l, neighbor_list, neighbor_ptr, degrees, m)

	# Exact post-projection: subtract c * g_raw so the component-mean gradient
	# has zero projection onto the tilt direction nhat.
	var mean_gradient := _component_mean_gradient(build, z_full, component_nodes, z_local, local_of)
	var c: float = mean_gradient[0] * nx + mean_gradient[1] * ny
	for i in m:
		var global_index: int = component_nodes[i]
		var g_raw: float = (
			(build.node_plane_x[global_index] - p0x) * nx
			+ (build.node_plane_y[global_index] - p0y) * ny
		)
		z_local[i] -= c * g_raw
	var energy_after := _energy(z_local, work_l, neighbor_list, neighbor_ptr, degrees, m)
	var mean_gradient_after := _component_mean_gradient(
		build, z_full, component_nodes, z_local, local_of
	)

	for i in m:
		z_full[component_nodes[i]] = z_local[i]

	report["converged"] = converged
	report["cg_iterations"] = iterations
	report["cg_final_rel_residual"] = rel_residual
	report["selected_affine_gradient"] = [c * nx, c * ny]
	report["mean_gradient_gauge_projection"] = (
		mean_gradient_after[0] * nx + mean_gradient_after[1] * ny
	)
	report["discrete_bending_energy_pre_projection"] = energy_before
	report["discrete_bending_energy_post_projection"] = energy_after
	return converged


static func _warm_start_along_line(
	build,
	component_nodes: PackedInt32Array,
	pin_nodes: Array,
	p0x: float,
	p0y: float,
	ux: float,
	uy: float,
	out: PackedFloat64Array
) -> void:
	var t_mean := 0.0
	var z_mean := 0.0
	for pin_node in pin_nodes:
		t_mean += (build.node_plane_x[pin_node] - p0x) * ux + (build.node_plane_y[pin_node] - p0y) * uy
		z_mean += float(build.pinned_world_y[pin_node])
	t_mean /= float(pin_nodes.size())
	z_mean /= float(pin_nodes.size())
	var num := 0.0
	var den := 0.0
	for pin_node in pin_nodes:
		var t: float = (
			(build.node_plane_x[pin_node] - p0x) * ux + (build.node_plane_y[pin_node] - p0y) * uy
		)
		num += (t - t_mean) * (float(build.pinned_world_y[pin_node]) - z_mean)
		den += (t - t_mean) * (t - t_mean)
	var slope := num / den if den != 0.0 else 0.0
	for i in component_nodes.size():
		var global_index: int = component_nodes[i]
		var t: float = (
			(build.node_plane_x[global_index] - p0x) * ux
			+ (build.node_plane_y[global_index] - p0y) * uy
		)
		out[i] = z_mean + slope * (t - t_mean)


# Area-weighted mean surface gradient over the component's triangles.
static func _component_mean_gradient(
	build,
	_z_full: PackedFloat64Array,
	component_nodes: PackedInt32Array,
	z_local: PackedFloat64Array,
	local_of: Dictionary
) -> Array:
	var grad_x := 0.0
	var grad_y := 0.0
	var total_area := 0.0
	for tri in build.triangles:
		if not local_of.has(tri[0]):
			continue
		var la: int = local_of[tri[0]]
		var lb: int = local_of[tri[1]]
		var lc: int = local_of[tri[2]]
		var ax: float = build.node_plane_x[tri[0]]
		var ay: float = build.node_plane_y[tri[0]]
		var bx: float = build.node_plane_x[tri[1]]
		var by: float = build.node_plane_y[tri[1]]
		var cx: float = build.node_plane_x[tri[2]]
		var cy: float = build.node_plane_y[tri[2]]
		var det := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if absf(det) < 1e-16:
			continue
		var za := z_local[la]
		var zb := z_local[lb]
		var zc := z_local[lc]
		# Plane gradient through the three vertices.
		var gx := ((zb - za) * (cy - ay) - (zc - za) * (by - ay)) / det
		var gy := ((zc - za) * (bx - ax) - (zb - za) * (cx - ax)) / det
		var area: float = absf(det) * 0.5
		grad_x += gx * area
		grad_y += gy * area
		total_area += area
	if total_area > 0.0:
		grad_x /= total_area
		grad_y /= total_area
	return [grad_x, grad_y]
