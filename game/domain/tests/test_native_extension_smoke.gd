# Headless test: godot --headless --path game -s res://domain/tests/test_native_extension_smoke.gd
#
# N3b.1a native GDExtension build-and-load smoke test. Requires the native
# library to be built first (from repo root): .\scripts\build-native.ps1
# See native/README.md. Verifies:
#   - the extension descriptor loads without errors;
#   - EomTerrainNative is registered and instantiable;
#   - the float64 probes return bit-identical results to the same
#     float64 arithmetic performed in GDScript (no f32 truncation at
#     the GDScript/C++ boundary).
extends SceneTree

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

var _total := 0
var _any_fail := false


func _init() -> void:
	_check(
		FileAccess.file_exists(DESCRIPTOR_PATH),
		"descriptor exists at %s (build first: .\\scripts\\build-native.ps1)" % DESCRIPTOR_PATH
	)
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_finish()
		return

	if GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		_check(true, "extension already loaded at startup")
	else:
		var status := GDExtensionManager.load_extension(DESCRIPTOR_PATH)
		_check(status == GDExtensionManager.LOAD_STATUS_OK, "extension loads (status %d)" % status)
	_check(GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH), "extension reported loaded")

	_check(ClassDB.class_exists(&"EomTerrainNative"), "EomTerrainNative class registered")
	_check(ClassDB.can_instantiate(&"EomTerrainNative"), "EomTerrainNative instantiable")
	if not ClassDB.can_instantiate(&"EomTerrainNative"):
		_finish()
		return

	var backend: Object = ClassDB.instantiate(&"EomTerrainNative")
	_check(backend != null, "EomTerrainNative instance created")
	if backend == null:
		_finish()
		return
	_check(backend.backend_id() == "eom_terrain_native", "backend_id() returns expected id")

	# Probe values chosen to be exact in float64 but not representable in
	# float32 (0.1, 1 + 2^-40, 1e-9, a 17-significant-digit value), so any
	# accidental f32 truncation at the boundary breaks exact equality.
	var values := PackedFloat64Array([0.1, 1.0 + pow(2.0, -40), -12345.678901234567, 1e-9, 0.0])
	var scale := 3.0
	var offset := 1.0 / 3.0

	var expected_sum := 0.0
	for v in values:
		expected_sum += v * scale
	var native_sum: float = backend.probe_float64_sum(values, scale)
	_check(native_sum == expected_sum, "probe_float64_sum bit-identical to GDScript f64 loop")

	var expected := PackedFloat64Array()
	for v in values:
		expected.append(v * scale + offset)
	var native_out: PackedFloat64Array = backend.probe_float64_scale_offset(values, scale, offset)
	_check(native_out.size() == values.size(), "probe_float64_scale_offset returns same-size array")
	var exact := native_out.size() == expected.size()
	for i in range(expected.size()):
		if native_out[i] != expected[i]:
			exact = false
	_check(exact, "probe_float64_scale_offset bit-identical per element")
	# f32 sentinel: (1 + 2^-40) collapses to 1.0 in float32; the result for
	# that element must differ from the collapsed value.
	if native_out.size() >= 2:
		_check(native_out[1] != 1.0 * scale + offset, "double precision preserved (no f32 collapse)")

	_finish()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Native extension smoke tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
