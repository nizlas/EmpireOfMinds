#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace eom {

// Native terrain backend scaffold (N3b.1a). Currently only carries the
// float64 boundary probes that prove arguments, return values and
// double-precision data cross the GDScript/C++ boundary intact. The
// TS-08 CG height-solve port (N3b.1b+) will live on this class.
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
};

} // namespace eom
