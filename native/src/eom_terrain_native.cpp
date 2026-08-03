#include "eom_terrain_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <vector>

using namespace godot;

namespace eom {

void EomTerrainNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("backend_id"), &EomTerrainNative::backend_id);
	ClassDB::bind_method(D_METHOD("probe_float64_sum", "values", "scale"), &EomTerrainNative::probe_float64_sum);
	ClassDB::bind_method(D_METHOD("probe_float64_scale_offset", "values", "scale", "offset"), &EomTerrainNative::probe_float64_scale_offset);
	ClassDB::bind_method(
			D_METHOD("solve_cg_plain_global", "neighbor_ptr", "neighbor_idx", "degrees", "pinned_idx", "z_pin", "z_warm", "rel_tol", "max_iterations", "verbose"),
			&EomTerrainNative::solve_cg_plain_global);
}

String EomTerrainNative::backend_id() const {
	return String("eom_terrain_native");
}

double EomTerrainNative::probe_float64_sum(const PackedFloat64Array &p_values, double p_scale) const {
	const double *ptr = p_values.ptr();
	const int64_t count = p_values.size();
	double acc = 0.0;
	for (int64_t i = 0; i < count; ++i) {
		acc += ptr[i] * p_scale;
	}
	return acc;
}

PackedFloat64Array EomTerrainNative::probe_float64_scale_offset(const PackedFloat64Array &p_values, double p_scale, double p_offset) const {
	const double *ptr = p_values.ptr();
	const int64_t count = p_values.size();
	PackedFloat64Array out;
	out.resize(count);
	double *out_ptr = out.ptrw();
	for (int64_t i = 0; i < count; ++i) {
		out_ptr[i] = ptr[i] * p_scale + p_offset;
	}
	return out;
}

// ---------------------------------------------------------------------------
// CSR kernels — line-for-line ports of Ts08HeightSolver (same accumulation
// order; sequential, deterministic, double precision).
// ---------------------------------------------------------------------------

namespace {

// Lz[i] = z[i] - sum(z[j in N(i)]) / degree[i]
void apply_l(const double *z, double *out, const int32_t *neighbor_idx, const int32_t *neighbor_ptr, const double *degrees, int64_t n) {
	int64_t ptr0 = neighbor_ptr[0];
	for (int64_t i = 0; i < n; ++i) {
		const int64_t ptr1 = neighbor_ptr[i + 1];
		double acc = 0.0;
		for (int64_t k = ptr0; k < ptr1; ++k) {
			acc += z[neighbor_idx[k]];
		}
		out[i] = z[i] - acc / degrees[i];
		ptr0 = ptr1;
	}
}

// Adjacency is symmetric, so LtW is a gather:
// (LtW)[i] = w[i] - sum(w[j] / degree[j]) over j in N(i).
void apply_lt(const double *w, double *out, double *scaled, const int32_t *neighbor_idx, const int32_t *neighbor_ptr, const double *degrees, int64_t n) {
	for (int64_t i = 0; i < n; ++i) {
		scaled[i] = w[i] / degrees[i];
	}
	int64_t ptr0 = neighbor_ptr[0];
	for (int64_t i = 0; i < n; ++i) {
		const int64_t ptr1 = neighbor_ptr[i + 1];
		double acc = 0.0;
		for (int64_t k = ptr0; k < ptr1; ++k) {
			acc += scaled[neighbor_idx[k]];
		}
		out[i] = w[i] - acc;
		ptr0 = ptr1;
	}
}

double energy(const double *z, double *work, const int32_t *neighbor_idx, const int32_t *neighbor_ptr, const double *degrees, int64_t n) {
	apply_l(z, work, neighbor_idx, neighbor_ptr, degrees, n);
	double total = 0.0;
	for (int64_t i = 0; i < n; ++i) {
		total += work[i] * work[i];
	}
	return total;
}

void jacobi_diagonal(double *diag, const int32_t *neighbor_idx, const int32_t *neighbor_ptr, const double *degrees, int64_t n) {
	int64_t ptr0 = neighbor_ptr[0];
	for (int64_t i = 0; i < n; ++i) {
		const int64_t ptr1 = neighbor_ptr[i + 1];
		double acc = 1.0;
		for (int64_t k = ptr0; k < ptr1; ++k) {
			const int64_t j = neighbor_idx[k];
			acc += 1.0 / (degrees[j] * degrees[j]);
		}
		diag[i] = acc;
		ptr0 = ptr1;
	}
}

} // namespace

Dictionary EomTerrainNative::solve_cg_plain_global(
		const PackedInt32Array &p_neighbor_ptr,
		const PackedInt32Array &p_neighbor_idx,
		const PackedFloat64Array &p_degrees,
		const PackedInt32Array &p_pinned_idx,
		const PackedFloat64Array &p_z_pin,
		const PackedFloat64Array &p_z_warm,
		double p_rel_tol,
		int64_t p_max_iterations,
		bool p_verbose) const {
	const auto started = std::chrono::steady_clock::now();

	const int64_t n = p_degrees.size();
	const int64_t pin_count = p_pinned_idx.size();
	if (p_neighbor_ptr.size() != n + 1 || p_z_warm.size() != n || p_z_pin.size() != pin_count || n <= 0) {
		ERR_PRINT("EomTerrainNative.solve_cg_plain_global: inconsistent input sizes.");
		return Dictionary();
	}

	// Zero-copy reads of the packed inputs.
	const int32_t *neighbor_ptr = p_neighbor_ptr.ptr();
	const int32_t *neighbor_idx = p_neighbor_idx.ptr();
	const double *degrees = p_degrees.ptr();
	const int32_t *pinned_idx = p_pinned_idx.ptr();
	const double *z_pin = p_z_pin.ptr();
	const double *z_warm = p_z_warm.ptr();

	for (int64_t i = 0; i < pin_count; ++i) {
		if (pinned_idx[i] < 0 || pinned_idx[i] >= n) {
			ERR_PRINT("EomTerrainNative.solve_cg_plain_global: pin index out of range.");
			return Dictionary();
		}
	}

	// Reusable native work buffers (allocated once per solve, never per
	// iteration; no Variant/Dictionary/copy-on-write inside the loop).
	std::vector<double> work_l(n), work_scaled(n), b_out(n);
	std::vector<double> z_pin_embedded(n, 0.0), rhs(n), x(n), precond_inv(n), r(n), z(n), p(n);

	for (int64_t i = 0; i < pin_count; ++i) {
		z_pin_embedded[pinned_idx[i]] = z_pin[i];
	}

	// rhs = -B(z_pin_embedded) restricted to free nodes (pin slots zeroed).
	apply_l(z_pin_embedded.data(), work_l.data(), neighbor_idx, neighbor_ptr, degrees, n);
	apply_lt(work_l.data(), b_out.data(), work_scaled.data(), neighbor_idx, neighbor_ptr, degrees, n);
	for (int64_t i = 0; i < n; ++i) {
		rhs[i] = -b_out[i];
	}
	for (int64_t i = 0; i < pin_count; ++i) {
		rhs[pinned_idx[i]] = 0.0;
	}
	double rhs_norm_sq = 0.0;
	for (int64_t i = 0; i < n; ++i) {
		rhs_norm_sq += rhs[i] * rhs[i];
	}
	const double rhs_norm = std::sqrt(rhs_norm_sq);

	const double energy_initial = energy(z_warm, work_l.data(), neighbor_idx, neighbor_ptr, degrees, n);

	for (int64_t i = 0; i < n; ++i) {
		x[i] = z_warm[i];
	}
	for (int64_t i = 0; i < pin_count; ++i) {
		x[pinned_idx[i]] = 0.0;
	}

	jacobi_diagonal(precond_inv.data(), neighbor_idx, neighbor_ptr, degrees, n);
	for (int64_t i = 0; i < n; ++i) {
		precond_inv[i] = 1.0 / precond_inv[i];
	}

	// r = rhs - B x (pin slots zeroed)
	apply_l(x.data(), work_l.data(), neighbor_idx, neighbor_ptr, degrees, n);
	apply_lt(work_l.data(), b_out.data(), work_scaled.data(), neighbor_idx, neighbor_ptr, degrees, n);
	for (int64_t i = 0; i < n; ++i) {
		r[i] = rhs[i] - b_out[i];
	}
	for (int64_t i = 0; i < pin_count; ++i) {
		r[pinned_idx[i]] = 0.0;
	}

	double abs_residual = 0.0;
	for (int64_t i = 0; i < n; ++i) {
		abs_residual += r[i] * r[i];
	}
	abs_residual = std::sqrt(abs_residual);
	double rel_residual = rhs_norm > 0.0 ? abs_residual / rhs_norm : 0.0;

	for (int64_t i = 0; i < n; ++i) {
		z[i] = precond_inv[i] * r[i];
		p[i] = z[i];
	}
	double rsold = 0.0;
	for (int64_t i = 0; i < n; ++i) {
		rsold += r[i] * z[i];
	}

	int64_t iterations = 0;
	bool converged = rel_residual <= p_rel_tol;

	if (!converged && rhs_norm > 0.0) {
		for (int64_t iteration = 0; iteration < p_max_iterations; ++iteration) {
			// Ap = B p (pin slots zeroed)
			apply_l(p.data(), work_l.data(), neighbor_idx, neighbor_ptr, degrees, n);
			apply_lt(work_l.data(), b_out.data(), work_scaled.data(), neighbor_idx, neighbor_ptr, degrees, n);
			for (int64_t i = 0; i < pin_count; ++i) {
				b_out[pinned_idx[i]] = 0.0;
			}
			double p_ap = 0.0;
			for (int64_t i = 0; i < n; ++i) {
				p_ap += p[i] * b_out[i];
			}
			const double alpha = rsold / p_ap;
			double r_norm_sq = 0.0;
			for (int64_t i = 0; i < n; ++i) {
				x[i] += alpha * p[i];
				r[i] -= alpha * b_out[i];
				r_norm_sq += r[i] * r[i];
			}
			abs_residual = std::sqrt(r_norm_sq);
			rel_residual = abs_residual / rhs_norm;
			iterations = iteration + 1;
			if (p_verbose && iterations % 200 == 0) {
				UtilityFunctions::print(String("  native cg iteration ") + String::num_int64(iterations) + String(" rel_residual=") + String::num_scientific(rel_residual));
			}
			if (rel_residual <= p_rel_tol) {
				converged = true;
				break;
			}
			double rsnew = 0.0;
			for (int64_t i = 0; i < n; ++i) {
				z[i] = precond_inv[i] * r[i];
				rsnew += r[i] * z[i];
			}
			const double beta = rsnew / rsold;
			for (int64_t i = 0; i < n; ++i) {
				p[i] = z[i] + beta * p[i];
			}
			rsold = rsnew;
		}
	}

	PackedFloat64Array z_full;
	z_full.resize(n);
	double *z_full_ptr = z_full.ptrw();
	for (int64_t i = 0; i < n; ++i) {
		z_full_ptr[i] = z_pin_embedded[i] + x[i];
	}
	const double energy_final = energy(z_full_ptr, work_l.data(), neighbor_idx, neighbor_ptr, degrees, n);

	const auto finished = std::chrono::steady_clock::now();
	const int64_t native_msec = std::chrono::duration_cast<std::chrono::milliseconds>(finished - started).count();
	// 10 native double work vectors + the returned z_full.
	const int64_t buffer_bytes = 11 * n * static_cast<int64_t>(sizeof(double));

	Dictionary out;
	out["z_full"] = z_full;
	out["iterations"] = iterations;
	out["abs_residual"] = abs_residual;
	out["rel_residual"] = rel_residual;
	out["energy_initial"] = energy_initial;
	out["energy_final"] = energy_final;
	out["converged"] = converged;
	out["native_msec"] = native_msec;
	out["buffer_bytes"] = buffer_bytes;
	return out;
}

} // namespace eom
