# Orbit camera for the shared runtime terrain world (N3c.2; moved out of
# game/dev/ in N3c.6 so the runtime world does not depend on dev code).
# Same accepted N3c.2 behavior; production camera polish is a later slice.
# No gameplay integration.
#
# Orbit state is (target, yaw, pitch, distance) around a ground-plane target:
# - unrestricted 360° yaw (wrapped);
# - pitch clamped to [MIN_PITCH_DEG, MAX_PITCH_DEG]: the camera stays above
#   the target's ground plane, so very low near-side views never pass below
#   the terrain;
# - map-relative zoom limits derived from the generated mesh AABB;
# - ground-plane panning of the orbit target, clamped to the map bounds
#   (plus margin);
# - deterministic strategic and low-angle presets; reset returns to the
#   strategic view.
extends Camera3D

const MIN_PITCH_DEG := 2.0
const MAX_PITCH_DEG := 85.0
const MIN_ZOOM_FACTOR := 0.15
const MAX_ZOOM_FACTOR := 3.0
const PAN_BOUNDS_MARGIN_FACTOR := 0.25

# Strategic preset reproduces the accepted fixed N3c.1 framing:
# direction (0.62, 0.78, 0.70).normalized() at distance 1.1 x extent.
const STRATEGIC_YAW_DEG := 41.5
const STRATEGIC_PITCH_DEG := 51.3
const STRATEGIC_ZOOM_FACTOR := 1.1

const LOW_ANGLE_YAW_DEG := 41.5
const LOW_ANGLE_PITCH_DEG := 8.0
const LOW_ANGLE_ZOOM_FACTOR := 0.55

const ORBIT_SPEED_DEG_PER_PX := 0.35
const PAN_SPEED_PER_PX := 0.0015
const ZOOM_STEP_FACTOR := 1.12

var target := Vector3.ZERO
var yaw_deg := STRATEGIC_YAW_DEG
var pitch_deg := STRATEGIC_PITCH_DEG
var distance := 1.0

var _map_center := Vector3.ZERO
var _map_extent := 1.0
var _min_distance := MIN_ZOOM_FACTOR
var _max_distance := MAX_ZOOM_FACTOR
var _pan_bounds := AABB()


# Initial framing derived from the generated mesh AABB; ends in the
# strategic preset.
func configure_from_aabb(aabb: AABB) -> void:
	_map_center = aabb.get_center()
	_map_extent = maxf(maxf(aabb.size.x, aabb.size.z), 1e-3)
	_min_distance = MIN_ZOOM_FACTOR * _map_extent
	_max_distance = MAX_ZOOM_FACTOR * _map_extent
	var margin := PAN_BOUNDS_MARGIN_FACTOR * _map_extent
	_pan_bounds = aabb.grow(margin)
	far = 4.0 * _map_extent + 100.0
	preset_strategic()


func preset_strategic() -> void:
	target = _map_center
	yaw_deg = STRATEGIC_YAW_DEG
	pitch_deg = STRATEGIC_PITCH_DEG
	distance = STRATEGIC_ZOOM_FACTOR * _map_extent
	_apply_clamps()
	_apply_transform()


func preset_low_angle() -> void:
	target = _map_center
	yaw_deg = LOW_ANGLE_YAW_DEG
	pitch_deg = LOW_ANGLE_PITCH_DEG
	distance = LOW_ANGLE_ZOOM_FACTOR * _map_extent
	_apply_clamps()
	_apply_transform()


func reset_view() -> void:
	preset_strategic()


func orbit(delta_yaw_deg: float, delta_pitch_deg: float) -> void:
	yaw_deg += delta_yaw_deg
	pitch_deg += delta_pitch_deg
	_apply_clamps()
	_apply_transform()


func zoom_by(factor: float) -> void:
	distance *= factor
	_apply_clamps()
	_apply_transform()


# Ground-plane panning: the target keeps its height; movement follows the
# camera's flattened right/forward axes and is clamped to the map bounds.
func pan_screen(dx_px: float, dy_px: float) -> void:
	var yaw_rad := deg_to_rad(yaw_deg)
	var flat_forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))
	var flat_right := flat_forward.cross(Vector3.UP)
	var pan_scale := distance * PAN_SPEED_PER_PX
	target += (-flat_right * dx_px + flat_forward * dy_px) * pan_scale
	_apply_clamps()
	_apply_transform()


func camera_state() -> Dictionary:
	return {
		"yaw_deg": yaw_deg,
		"pitch_deg": pitch_deg,
		"distance": distance,
		"target": target,
		"position": position,
	}


func _apply_clamps() -> void:
	yaw_deg = fposmod(yaw_deg, 360.0)
	pitch_deg = clampf(pitch_deg, MIN_PITCH_DEG, MAX_PITCH_DEG)
	distance = clampf(distance, _min_distance, _max_distance)
	if _pan_bounds.size != Vector3.ZERO:
		target.x = clampf(target.x, _pan_bounds.position.x, _pan_bounds.end.x)
		target.z = clampf(target.z, _pan_bounds.position.z, _pan_bounds.end.z)
	target.y = _map_center.y


func _apply_transform() -> void:
	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)
	var direction := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	)
	position = target + direction * distance
	# Basis.looking_at instead of look_at: works outside the scene tree
	# (headless camera tests) and never depends on global transforms.
	transform.basis = Basis.looking_at((target - position).normalized(), Vector3.UP)


# --- desktop input (dev tool only) ---


var _orbiting := false
var _panning := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if button.button_index == MOUSE_BUTTON_LEFT and button.shift_pressed:
					_panning = button.pressed
					_orbiting = false
				else:
					_orbiting = button.pressed
					_panning = false
			MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_by(1.0 / ZOOM_STEP_FACTOR)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_by(ZOOM_STEP_FACTOR)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			pan_screen(motion.relative.x, motion.relative.y)
		elif _orbiting:
			orbit(
				-motion.relative.x * ORBIT_SPEED_DEG_PER_PX,
				motion.relative.y * ORBIT_SPEED_DEG_PER_PX
			)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_R, KEY_HOME:
				reset_view()
			KEY_1:
				preset_strategic()
			KEY_2:
				preset_low_angle()
