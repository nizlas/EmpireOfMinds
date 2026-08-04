# Headless test: godot --headless --path game -s res://dev/tests/test_terrain_preview_camera.gd
#
# N3c.2 terrain-preview orbit camera and backend selection (dev tool only):
# - initial framing derived from the mesh AABB (strategic preset);
# - unrestricted 360° yaw wrap, bounded pitch, map-relative zoom clamps;
# - camera never passes below the terrain at any clamped state;
# - ground-plane panning with map-relative bounds;
# - deterministic strategic/low-angle presets and reset behavior;
# - preview backend selector semantics (Auto/Native/GDScript, no silent
#   fallback for explicit Native).
extends SceneTree

const OrbitCameraScript = preload("res://presentation/world/orbit_camera.gd")
const TerrainPreviewScript = preload("res://dev/terrain_preview/terrain_preview.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

# Reference-map-like AABB (matches the generated mesh scale).
const TEST_AABB := AABB(Vector3(-0.866, -0.0953, -1.0), Vector3(19.05, 2.19, 24.5))

var _total := 0
var _any_fail := false
var _cameras: Array = []


func _init() -> void:
	_test_initial_framing()
	_test_yaw_wrap()
	_test_pitch_clamp_and_terrain_floor()
	_test_zoom_clamp()
	_test_pan_ground_plane_and_bounds()
	_test_presets_and_reset()
	_test_backend_selection()
	_finish()


func _make_camera() -> Camera3D:
	var camera: Camera3D = OrbitCameraScript.new()
	camera.configure_from_aabb(TEST_AABB)
	_cameras.append(camera)
	return camera


func _extent() -> float:
	return maxf(TEST_AABB.size.x, TEST_AABB.size.z)


func _test_initial_framing() -> void:
	print("--- initial framing from AABB ---")
	var camera := _make_camera()
	var center := TEST_AABB.get_center()
	_check(camera.target.is_equal_approx(center), "target at AABB center")
	_check(
		is_equal_approx(camera.distance, OrbitCameraScript.STRATEGIC_ZOOM_FACTOR * _extent()),
		"strategic distance is 1.1 x extent"
	)
	_check(is_equal_approx(camera.yaw_deg, OrbitCameraScript.STRATEGIC_YAW_DEG), "strategic yaw")
	_check(
		is_equal_approx(camera.pitch_deg, OrbitCameraScript.STRATEGIC_PITCH_DEG),
		"strategic pitch"
	)
	var expected_position: Vector3 = camera.target + Vector3(
		sin(deg_to_rad(camera.yaw_deg)) * cos(deg_to_rad(camera.pitch_deg)),
		sin(deg_to_rad(camera.pitch_deg)),
		cos(deg_to_rad(camera.yaw_deg)) * cos(deg_to_rad(camera.pitch_deg))
	) * camera.distance
	_check(camera.position.is_equal_approx(expected_position), "position from orbit state")
	var forward: Vector3 = -camera.transform.basis.z
	var to_target: Vector3 = (camera.target - camera.position).normalized()
	_check(forward.dot(to_target) > 0.9999, "camera looks at the target")
	_check(camera.far > 4.0 * _extent(), "far plane covers the map")


func _test_yaw_wrap() -> void:
	print("--- unrestricted 360° yaw (wrapped) ---")
	var camera := _make_camera()
	camera.orbit(400.0, 0.0)
	_check(
		is_equal_approx(camera.yaw_deg, fposmod(OrbitCameraScript.STRATEGIC_YAW_DEG + 400.0, 360.0)),
		"yaw wraps above 360°"
	)
	camera.orbit(-1000.0, 0.0)
	_check(camera.yaw_deg >= 0.0 and camera.yaw_deg < 360.0, "yaw stays in [0, 360)")
	var before := camera.position
	camera.orbit(360.0, 0.0)
	_check(camera.position.is_equal_approx(before), "full 360° turn returns to same position")


func _test_pitch_clamp_and_terrain_floor() -> void:
	print("--- bounded pitch; never below terrain ---")
	var camera := _make_camera()
	camera.orbit(0.0, -1000.0)
	_check(
		is_equal_approx(camera.pitch_deg, OrbitCameraScript.MIN_PITCH_DEG),
		"pitch clamps at the low limit"
	)
	_check(
		camera.position.y > TEST_AABB.position.y,
		"low near-side view stays above the terrain's lowest point"
	)
	camera.orbit(0.0, 1000.0)
	_check(
		is_equal_approx(camera.pitch_deg, OrbitCameraScript.MAX_PITCH_DEG),
		"pitch clamps at the high limit"
	)
	# Worst case: minimum pitch at maximum zoom, any yaw.
	camera.orbit(0.0, -1000.0)
	camera.zoom_by(1e9)
	var lowest_y := INF
	for step in 24:
		camera.orbit(15.0, 0.0)
		lowest_y = minf(lowest_y, camera.position.y)
	_check(
		lowest_y > TEST_AABB.position.y,
		"camera above terrain at min pitch / max zoom for all yaw"
	)


func _test_zoom_clamp() -> void:
	print("--- map-relative zoom limits ---")
	var camera := _make_camera()
	camera.zoom_by(1e-9)
	_check(
		is_equal_approx(camera.distance, OrbitCameraScript.MIN_ZOOM_FACTOR * _extent()),
		"zoom-in clamps at 0.15 x extent"
	)
	camera.zoom_by(1e9)
	_check(
		is_equal_approx(camera.distance, OrbitCameraScript.MAX_ZOOM_FACTOR * _extent()),
		"zoom-out clamps at 3.0 x extent"
	)


func _test_pan_ground_plane_and_bounds() -> void:
	print("--- ground-plane panning with bounds ---")
	var camera := _make_camera()
	var y_before: float = camera.target.y
	camera.pan_screen(120.0, -80.0)
	_check(is_equal_approx(camera.target.y, y_before), "pan keeps the target on the ground plane")
	_check(
		not camera.target.is_equal_approx(TEST_AABB.get_center()),
		"pan moves the target"
	)
	var margin: float = OrbitCameraScript.PAN_BOUNDS_MARGIN_FACTOR * _extent()
	for step in 400:
		camera.pan_screen(1000.0, 1000.0)
	_check(
		camera.target.x <= TEST_AABB.end.x + margin + 1e-4
		and camera.target.x >= TEST_AABB.position.x - margin - 1e-4
		and camera.target.z <= TEST_AABB.end.z + margin + 1e-4
		and camera.target.z >= TEST_AABB.position.z - margin - 1e-4,
		"pan target clamps to map bounds plus margin"
	)


func _test_presets_and_reset() -> void:
	print("--- deterministic presets and reset ---")
	var camera := _make_camera()
	var strategic_position: Vector3 = camera.position
	var strategic_state: Dictionary = camera.camera_state()

	camera.preset_low_angle()
	_check(is_equal_approx(camera.pitch_deg, OrbitCameraScript.LOW_ANGLE_PITCH_DEG), "low preset pitch")
	_check(
		is_equal_approx(camera.distance, OrbitCameraScript.LOW_ANGLE_ZOOM_FACTOR * _extent()),
		"low preset distance"
	)
	_check(camera.target.is_equal_approx(TEST_AABB.get_center()), "low preset re-centers target")
	var low_position_a: Vector3 = camera.position
	camera.preset_low_angle()
	_check(camera.position.is_equal_approx(low_position_a), "low preset deterministic")

	# Scramble the state, then reset.
	camera.orbit(123.0, 33.0)
	camera.zoom_by(0.3)
	camera.pan_screen(500.0, -300.0)
	camera.reset_view()
	var reset_state: Dictionary = camera.camera_state()
	_check(camera.position.is_equal_approx(strategic_position), "reset restores strategic position")
	_check(
		is_equal_approx(reset_state["yaw_deg"], strategic_state["yaw_deg"])
		and is_equal_approx(reset_state["pitch_deg"], strategic_state["pitch_deg"])
		and is_equal_approx(reset_state["distance"], strategic_state["distance"])
		and reset_state["target"].is_equal_approx(strategic_state["target"]),
		"reset restores full strategic state"
	)


func _test_backend_selection() -> void:
	print("--- preview backend selection (dev tool only) ---")
	var modes := TerrainPreviewScript.BackendMode

	var auto_native: Dictionary = TerrainPreviewScript.resolve_backend(modes.AUTO, true)
	_check(
		auto_native["ok"] and auto_native["backend"] == Ts08HeightSolver.BACKEND_NATIVE,
		"Auto uses native when available"
	)
	var auto_fallback: Dictionary = TerrainPreviewScript.resolve_backend(modes.AUTO, false)
	_check(
		auto_fallback["ok"] and auto_fallback["backend"] == Ts08HeightSolver.BACKEND_GDSCRIPT,
		"Auto falls back to GDScript when native is unavailable"
	)
	var native_ok: Dictionary = TerrainPreviewScript.resolve_backend(modes.NATIVE, true)
	_check(
		native_ok["ok"] and native_ok["backend"] == Ts08HeightSolver.BACKEND_NATIVE,
		"explicit Native uses native when available"
	)
	var native_missing: Dictionary = TerrainPreviewScript.resolve_backend(modes.NATIVE, false)
	_check(not native_missing["ok"], "explicit Native fails when unavailable (no fallback)")
	_check(
		native_missing["error"] != "" and native_missing["backend"] == "",
		"explicit Native failure carries a clear error and no backend"
	)
	var gd_with_native: Dictionary = TerrainPreviewScript.resolve_backend(modes.GDSCRIPT, true)
	var gd_without_native: Dictionary = TerrainPreviewScript.resolve_backend(modes.GDSCRIPT, false)
	_check(
		gd_with_native["ok"]
		and gd_with_native["backend"] == Ts08HeightSolver.BACKEND_GDSCRIPT
		and gd_without_native["ok"]
		and gd_without_native["backend"] == Ts08HeightSolver.BACKEND_GDSCRIPT,
		"explicit GDScript always available"
	)
	var preset_default: String = TerrainPreviewScript._screenshot_preset_from_args(
		PackedStringArray(["--screenshot"])
	)
	var preset_low: String = TerrainPreviewScript._screenshot_preset_from_args(
		PackedStringArray(["--native", "--screenshot=low"])
	)
	var preset_none: String = TerrainPreviewScript._screenshot_preset_from_args(
		PackedStringArray(["--native"])
	)
	_check(
		preset_default == "strategic" and preset_low == "low" and preset_none == "",
		"screenshot preset argument parsing"
	)


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	for camera in _cameras:
		camera.free()
	_cameras.clear()
	print("Terrain preview camera tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
