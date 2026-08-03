#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace eom {

// Native terrain backend. N3b.1a added the float64 boundary probes; N3b.1b
// ports the rank-3/plain-PCG hot path of Ts08HeightSolver (the accepted
// GDScript reference, which remains the fallback). The math must stay a
// line-for-line port of _solve_cg_plain_global in ts08_height_solver.gd:
// identical operators, preconditioner, convergence criterion, and
// deterministic sequential accumulation order, all in double precision.
class EomTerrainNative : public godot::RefCounted {
	GDCLASS(EomTerrainNative, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	godot::String backend_id() const;

	// Sequential sum of values[i] * scale in index order; must be
	// bit-identical to the same float64 loop written in GDScript.
	double probe_float64_sum(const godot::PackedFloat64Array &p_values, double p_scale) const;

	// Element-wise values[i] * scale + offset; must be bit-identical to
	// the same float64 expression written in GDScript.
	godot::PackedFloat64Array probe_float64_scale_offset(const godot::PackedFloat64Array &p_values, double p_scale, double p_offset) const;

	// Global plain Jacobi-preconditioned CG over all free nodes with hard
	// pins by elimination (pin slots held at zero). One GDScript/C++
	// boundary crossing per solve: all inputs arrive packed, every
	// operator application / iteration / reduction runs natively, and one
	// Dictionary returns heights plus convergence diagnostics.
	//
	// Inputs mirror Ts08HeightSolver._solve_cg_plain_global:
	//   neighbor_ptr  CSR row pointers, size n + 1
	//   neighbor_idx  CSR neighbor indices (symmetric adjacency)
	//   degrees       max(neighbor count, 1) per node, size n
	//   pinned_idx    sorted pinned node indices
	//   z_pin         pin heights (Godot Y units), aligned with pinned_idx
	//   z_warm        deterministic planar warm start, size n, pins embedded
	//   rel_tol       relative residual tolerance (1e-8)
	//   max_iterations iteration cap (40000)
	// Returns keys: z_full, iterations, abs_residual, rel_residual,
	// energy_initial, energy_final, converged, native_msec, buffer_bytes.
	// Returns an empty Dictionary on inconsistent input sizes.
	godot::Dictionary solve_cg_plain_global(
			const godot::PackedInt32Array &p_neighbor_ptr,
			const godot::PackedInt32Array &p_neighbor_idx,
			const godot::PackedFloat64Array &p_degrees,
			const godot::PackedInt32Array &p_pinned_idx,
			const godot::PackedFloat64Array &p_z_pin,
			const godot::PackedFloat64Array &p_z_warm,
			double p_rel_tol,
			int64_t p_max_iterations,
			bool p_verbose) const;
};

} // namespace eom
