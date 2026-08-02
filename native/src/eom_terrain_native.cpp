#include "eom_terrain_native.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace eom {

void EomTerrainNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("backend_id"), &EomTerrainNative::backend_id);
	ClassDB::bind_method(D_METHOD("probe_float64_sum", "values", "scale"), &EomTerrainNative::probe_float64_sum);
	ClassDB::bind_method(D_METHOD("probe_float64_scale_offset", "values", "scale", "offset"), &EomTerrainNative::probe_float64_scale_offset);
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

} // namespace eom
