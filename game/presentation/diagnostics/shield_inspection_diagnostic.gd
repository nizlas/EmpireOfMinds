# C1 shield inspection diagnostic (F6-runnable, presentation-only).
#
# Purpose: let a human answer the questions the cloud validator is NOT allowed to
# answer — is there a real rigid handgrip, and is there room for a hand behind it.
# The structural report from `python -m tools.assetgen validate-shield` supplies
# the measurements; this scene shows the geometry those numbers came from so the
# numbers can be believed or rejected.
#
# This is a DIAGNOSTIC scene. It deliberately implements no hand pose, no grip
# solve and no attachment: nothing here may become a runtime dependency.
#
# Controls
#   Left drag / arrows  orbit          Right drag / WASD  pan
#   Wheel / +,-         zoom           F                  frame the asset
#   1..6                preset views (front, back, left, right, top, grazing rear)
#   M                   toggle suggested marker gizmos
#   C                   toggle the clearance measuring probe
#   X                   toggle a cutaway that slices through the grip
#   W                   toggle wireframe
#   R                   toggle slow auto-rotate
#   H                   toggle this help overlay
extends Node3D

## Shield GLB under inspection. Override with --shield-glb=<res-or-user path>.
const DEFAULT_SHIELD_GLB := "res://assets/prototype/3d/equipment/wooden_shield/wooden_shield.glb"

## Optional structural report produced by the cloud validator. When present its
## suggested markers and measurements are displayed; when absent the scene still
## works and simply says so, because the geometry is the primary evidence.
const DEFAULT_REPORT_PATH := "res://../artifacts/assetgen/shield/wooden_shield_structural.json"

const ORBIT_SPEED := 0.010
const PAN_SPEED := 0.0022
const ZOOM_STEP := 1.12
const MIN_DISTANCE := 0.05
const MAX_DISTANCE := 40.0
const AUTO_ROTATE_DEG_PER_SEC := 18.0

## Anthropometric reference figures, shown next to the measured values so the
## reviewer compares against a hand rather than against nothing. Adult male
## 50th percentile, in metres.
const HAND_BREADTH_M := 0.090
const HAND_THICKNESS_M := 0.034
const COMFORT_GRIP_DIAMETER_M := 0.035
const MIN_FINGER_CLEARANCE_M := 0.045

var _shield_path := DEFAULT_SHIELD_GLB
var _report: Dictionary = {}
var _report_source := ""

var _pivot := Vector3.ZERO
var _yaw := 0.0
var _pitch := -0.15
var _distance := 1.0
var _asset_radius := 0.5
var _asset_aabb := AABB()

var _camera: Camera3D
var _asset_root: Node3D
var _marker_root: Node3D
var _probe_root: Node3D
var _help_label: RichTextLabel
var _readout_label: RichTextLabel

var _markers_visible := true
var _probe_visible := true
var _cutaway := false
var _wireframe := false
var _auto_rotate := false
var _help_visible := true
var _orbiting := false
var _panning := false


func _ready() -> void:
	_parse_command_line()
	_build_environment()
	_load_report()
	_load_asset()
	_build_markers()
	_build_probe()
	_build_overlay()
	_frame_asset()
	_apply_camera()
	_refresh_readout()


# ------------------------------------------------------------------ setup


func _parse_command_line() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shield-glb="):
			_shield_path = argument.substr("--shield-glb=".length())
		elif argument.begins_with("--report="):
			_report_source = argument.substr("--report=".length())


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.11, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.64, 0.68)
	# High ambient on purpose: a dark band must mean a real gap in the geometry,
	# not a shadow. Judging clearance under dramatic lighting is how a painted
	# groove gets mistaken for a grip.
	environment.ambient_light_energy = 1.25
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	for direction in [Vector3(-0.4, -0.7, -0.6), Vector3(0.6, -0.3, 0.7), Vector3(0.0, 0.9, -0.2)]:
		var light := DirectionalLight3D.new()
		light.light_energy = 1.1
		light.shadow_enabled = false
		light.look_at_from_position(Vector3.ZERO, direction.normalized(), Vector3.UP)
		add_child(light)

	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.near = 0.001
	_camera.fov = 45.0
	add_child(_camera)


func _load_report() -> void:
	var candidates: Array[String] = []
	if _report_source != "":
		candidates.append(_report_source)
	candidates.append(DEFAULT_REPORT_PATH)
	candidates.append(
		ProjectSettings.globalize_path("res://").path_join(
			"../artifacts/assetgen/shield/wooden_shield_structural.json"
		)
	)
	for candidate in candidates:
		var text := ""
		if FileAccess.file_exists(candidate):
			text = FileAccess.get_file_as_string(candidate)
		if text == "":
			continue
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_report = parsed
			_report_source = candidate
			return


func _load_asset() -> void:
	_asset_root = Node3D.new()
	_asset_root.name = "ShieldUnderInspection"
	add_child(_asset_root)

	var resource: Resource = load(_shield_path)
	if resource == null:
		push_error("shield_inspection_diagnostic: could not load %s" % _shield_path)
		return
	var instance: Node = null
	if resource is PackedScene:
		instance = (resource as PackedScene).instantiate()
	elif resource is Mesh:
		var holder := MeshInstance3D.new()
		holder.mesh = resource as Mesh
		instance = holder
	if instance == null:
		push_error("shield_inspection_diagnostic: %s is not a scene or mesh" % _shield_path)
		return
	_asset_root.add_child(instance)
	_asset_aabb = _world_aabb(_asset_root)
	_asset_radius = maxf(_asset_aabb.size.length() * 0.5, 0.01)


func _world_aabb(root: Node) -> AABB:
	var combined := AABB()
	var seen := false
	for mesh_instance in _collect_mesh_instances(root):
		var local := mesh_instance.get_aabb()
		var transform := mesh_instance.global_transform
		var box := AABB(transform * local.position, Vector3.ZERO)
		for corner_index in range(8):
			box = box.expand(transform * (local.position + local.size * _corner(corner_index)))
		if seen:
			combined = combined.merge(box)
		else:
			combined = box
			seen = true
	return combined


func _corner(index: int) -> Vector3:
	return Vector3(
		1.0 if (index & 1) != 0 else 0.0,
		1.0 if (index & 2) != 0 else 0.0,
		1.0 if (index & 4) != 0 else 0.0
	)


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_collect_mesh_instances(child))
	return found


# ----------------------------------------------------------------- gizmos


func _build_markers() -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "SuggestedMarkers"
	add_child(_marker_root)

	var markers: Dictionary = _report.get("suggested_markers", {}) as Dictionary
	if markers.is_empty():
		return

	# Suggested markers are DIAGNOSTICS, not runtime truth. They are drawn so a
	# reviewer can see whether the validator's guess lands on real geometry.
	_add_point_gizmo("shield_grip", markers, Color(0.20, 0.95, 0.45))
	_add_point_gizmo("forearm_contact", markers, Color(0.35, 0.65, 1.00))
	_add_axis_gizmo("shield_forward", markers, Color(1.00, 0.75, 0.20))


func _add_point_gizmo(key: String, markers: Dictionary, colour: Color) -> void:
	var entry: Dictionary = markers.get(key, {}) as Dictionary
	var raw: Variant = entry.get("origin", entry.get("position", []))
	if not _has_vector(raw):
		return
	var origin := _vector_from(raw)
	var sphere := SphereMesh.new()
	sphere.radius = _asset_radius * 0.035
	sphere.height = sphere.radius * 2.0
	var node := MeshInstance3D.new()
	node.name = key
	node.mesh = sphere
	node.material_override = _unshaded(colour)
	node.position = origin
	_marker_root.add_child(node)

	var label := Label3D.new()
	label.text = key
	label.font_size = 48
	label.pixel_size = _asset_radius * 0.0016
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = colour
	label.position = origin + Vector3.UP * _asset_radius * 0.08
	_marker_root.add_child(label)


func _add_axis_gizmo(key: String, markers: Dictionary, colour: Color) -> void:
	var entry: Dictionary = markers.get(key, {}) as Dictionary
	var raw: Variant = entry.get("direction", entry.get("axis", []))
	if not _has_vector(raw):
		return
	var direction := _vector_from(raw)
	if direction.length() < 0.0001:
		return
	var origin := _vector_from(entry.get("origin", []), _asset_aabb.get_center())
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(origin)
	immediate.surface_add_vertex(origin + direction.normalized() * _asset_radius * 1.1)
	immediate.surface_end()
	var node := MeshInstance3D.new()
	node.name = key
	node.mesh = immediate
	node.material_override = _unshaded(colour)
	_marker_root.add_child(node)

	var label := Label3D.new()
	label.text = key
	label.font_size = 48
	label.pixel_size = _asset_radius * 0.0016
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = colour
	label.position = origin + direction.normalized() * _asset_radius * 1.15
	_marker_root.add_child(label)


func _build_probe() -> void:
	# A physical yardstick: a box the size of a real hand's cross-section. If it
	# does not fit behind the grip, no grip pose will either, whatever a number
	# in a report says.
	_probe_root = Node3D.new()
	_probe_root.name = "HandClearanceProbe"
	add_child(_probe_root)

	var box := BoxMesh.new()
	box.size = Vector3(HAND_BREADTH_M, HAND_BREADTH_M, HAND_THICKNESS_M)
	var probe := MeshInstance3D.new()
	probe.name = "HandCrossSection"
	probe.mesh = box
	probe.material_override = _unshaded(Color(0.20, 0.95, 0.45, 0.35), true)
	_probe_root.add_child(probe)

	var markers: Dictionary = _report.get("suggested_markers", {}) as Dictionary
	var grip: Dictionary = markers.get("shield_grip", {}) as Dictionary
	_probe_root.position = _vector_from(
		grip.get("origin", grip.get("position", [])), _asset_aabb.get_center()
	)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = COMFORT_GRIP_DIAMETER_M * 0.5
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = _asset_radius * 0.6
	var reference_grip := MeshInstance3D.new()
	reference_grip.name = "ReferenceGripDiameter"
	reference_grip.mesh = cylinder
	reference_grip.material_override = _unshaded(Color(1.0, 0.4, 0.4, 0.5), true)
	_probe_root.add_child(reference_grip)


func _unshaded(colour: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# ---------------------------------------------------------------- overlay


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_readout_label = RichTextLabel.new()
	_readout_label.bbcode_enabled = true
	_readout_label.fit_content = true
	_readout_label.scroll_active = false
	_readout_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_readout_label.offset_left = 16.0
	_readout_label.offset_top = 12.0
	_readout_label.custom_minimum_size = Vector2(760.0, 0.0)
	layer.add_child(_readout_label)

	_help_label = RichTextLabel.new()
	_help_label.bbcode_enabled = true
	_help_label.fit_content = true
	_help_label.scroll_active = false
	_help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help_label.offset_left = 16.0
	_help_label.offset_top = -240.0
	_help_label.offset_bottom = -12.0
	_help_label.custom_minimum_size = Vector2(760.0, 0.0)
	_help_label.text = _help_text()
	layer.add_child(_help_label)


func _help_text() -> String:
	return (
		"[b]Controls[/b]\n"
		+ "drag / arrows orbit  ·  right-drag / WASD pan  ·  wheel zoom  ·  F frame\n"
		+ "1 front  2 back  3 left  4 right  5 top  6 grazing rear\n"
		+ "M markers  ·  C hand-clearance probe  ·  X cutaway  ·  W wireframe  ·  R auto-rotate  ·  H help"
	)


func _refresh_readout() -> void:
	var lines: Array[String] = []
	lines.append("[b]C1 shield inspection diagnostic[/b]  (no hand pose implemented)")
	lines.append("asset: %s" % _shield_path)
	lines.append(
		"bounds: %.3f x %.3f x %.3f m" % [_asset_aabb.size.x, _asset_aabb.size.y, _asset_aabb.size.z]
	)
	if _report.is_empty():
		lines.append(
			"[color=#ffb14a]no structural report found[/color] — run "
			+ "python -m tools.assetgen validate-shield <glb> --out artifacts/assetgen/shield/<name>.json"
		)
	else:
		lines.append("report: %s" % _report_source)
		lines.append(
			"classification: [b]%s[/b]" % str(_report.get("classification", "UNKNOWN"))
		)
		lines.append("reason: %s" % str(_report.get("classification_reason", "")))
		lines.append(
			"triangles: %s   components: %s"
			% [
				str(_report.get("triangle_count", "?")),
				str(_report.get("disconnected_component_count", "?")),
			]
		)
		var best: Variant = _report.get("best_handle_candidate")
		if best is Dictionary:
			var candidate := best as Dictionary
			lines.append(
				"measured clearance ratio %.4f · grip diameter ratio %.4f · elongation %.2f"
				% [
					float(candidate.get("clearance_ratio", 0.0)),
					float(candidate.get("handle_diameter_ratio", 0.0)),
					float(candidate.get("elongation", 0.0)),
				]
			)
		else:
			lines.append("[color=#ff7a7a]no handle candidate was measured[/color]")
	lines.append(
		"reference: hand breadth %.0f mm · thickness %.0f mm · comfortable grip Ø %.0f mm · min finger clearance %.0f mm"
		% [
			HAND_BREADTH_M * 1000.0,
			HAND_THICKNESS_M * 1000.0,
			COMFORT_GRIP_DIAMETER_M * 1000.0,
			MIN_FINGER_CLEARANCE_M * 1000.0,
		]
	)
	lines.append("")
	lines.append("[b]Judge by eye, then decide:[/b]")
	for item in visual_checklist():
		lines.append("  · %s" % item)
	_readout_label.text = "\n".join(lines)


## The questions no automated check may answer on the user's behalf.
static func visual_checklist() -> Array[String]:
	return [
		"is there a rigid handgrip that is real geometry, not a painted or embossed ridge",
		"is there genuine empty space between grip and shield body",
		"does a hand with curled fingers fit in that space (toggle C)",
		"is the grip diameter holdable rather than a slab or a wire",
		"is the grip on the side that faces the arm, opposite the outer face",
		"is there a usable forearm-contact region or strap",
		"did the 1k remesh keep the grip separate from the plate",
		"is the outer face silhouette and material still the intended design",
	]


# ------------------------------------------------------------------ camera


func _frame_asset() -> void:
	_pivot = _asset_aabb.get_center()
	_distance = clampf(_asset_radius * 2.6, MIN_DISTANCE, MAX_DISTANCE)


func _apply_camera() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	_camera.position = _pivot + offset
	_camera.look_at(_pivot, Vector3.UP)


func _preset_view(index: int) -> void:
	match index:
		1:
			_yaw = 0.0
			_pitch = 0.0
		2:
			_yaw = PI
			_pitch = 0.0
		3:
			_yaw = -PI * 0.5
			_pitch = 0.0
		4:
			_yaw = PI * 0.5
			_pitch = 0.0
		5:
			_yaw = 0.0
			_pitch = 1.45
		6:
			# Grazing rear: the angle that makes a shallow relief look shallow.
			_yaw = PI
			_pitch = 0.42
	_apply_camera()


# ------------------------------------------------------------------- input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = button.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom(1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(ZOOM_STEP)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			_orbit(-motion.relative.x * ORBIT_SPEED, -motion.relative.y * ORBIT_SPEED)
		elif _panning:
			_pan(-motion.relative.x, motion.relative.y)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_handle_key((event as InputEventKey).keycode)


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_F:
			_frame_asset()
			_apply_camera()
		KEY_M:
			_markers_visible = not _markers_visible
			_marker_root.visible = _markers_visible
		KEY_C:
			_probe_visible = not _probe_visible
			_probe_root.visible = _probe_visible
		KEY_X:
			_cutaway = not _cutaway
			_apply_cutaway()
		KEY_W:
			_wireframe = not _wireframe
			_apply_wireframe()
		KEY_R:
			_auto_rotate = not _auto_rotate
		KEY_H:
			_help_visible = not _help_visible
			_help_label.visible = _help_visible
			_readout_label.visible = _help_visible
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_preset_view(keycode - KEY_0)
		KEY_EQUAL, KEY_KP_ADD:
			_zoom(1.0 / ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom(ZOOM_STEP)


func _process(delta: float) -> void:
	var yaw_input := 0.0
	var pitch_input := 0.0
	if Input.is_key_pressed(KEY_LEFT):
		yaw_input += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		yaw_input -= 1.0
	if Input.is_key_pressed(KEY_UP):
		pitch_input += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pitch_input -= 1.0
	if yaw_input != 0.0 or pitch_input != 0.0:
		_orbit(yaw_input * delta * 1.6, pitch_input * delta * 1.6)

	var pan_x := 0.0
	var pan_y := 0.0
	if Input.is_key_pressed(KEY_A):
		pan_x += 1.0
	if Input.is_key_pressed(KEY_D):
		pan_x -= 1.0
	if Input.is_key_pressed(KEY_S):
		pan_y += 1.0
	if Input.is_key_pressed(KEY_W) and not _wireframe:
		pan_y -= 1.0
	if pan_x != 0.0 or pan_y != 0.0:
		_pan(pan_x * 240.0 * delta, pan_y * 240.0 * delta)

	if _auto_rotate:
		_orbit(deg_to_rad(AUTO_ROTATE_DEG_PER_SEC) * delta, 0.0)


func _orbit(delta_yaw: float, delta_pitch: float) -> void:
	_yaw = wrapf(_yaw + delta_yaw, -PI, PI)
	_pitch = clampf(_pitch + delta_pitch, -1.55, 1.55)
	_apply_camera()


func _pan(delta_x: float, delta_y: float) -> void:
	var scale := _distance * PAN_SPEED
	var basis := _camera.global_transform.basis
	_pivot += basis.x * delta_x * scale + basis.y * delta_y * scale
	_apply_camera()


func _zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply_camera()


# ---------------------------------------------------------------- display


func _apply_wireframe() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.debug_draw = (
		Viewport.DEBUG_DRAW_WIREFRAME if _wireframe else Viewport.DEBUG_DRAW_DISABLED
	)
	RenderingServer.set_debug_generate_wireframes(_wireframe)


func _apply_cutaway() -> void:
	# Front-face culling turns the shell inside out, which is the cheapest honest
	# way to see whether a "handle" is a separate bar or just a bump on the plate.
	for mesh_instance in _collect_mesh_instances(_asset_root):
		var count := mesh_instance.get_surface_override_material_count()
		for index in range(count):
			var material := mesh_instance.get_active_material(index)
			if material is BaseMaterial3D:
				var clone := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				clone.cull_mode = (
					BaseMaterial3D.CULL_FRONT if _cutaway else BaseMaterial3D.CULL_BACK
				)
				mesh_instance.set_surface_override_material(index, clone)


## True when the report entry actually carries a 3-component vector. Kept
## separate from _vector_from so a missing marker is never silently drawn at the
## origin, which would put a green "shield_grip" dot on geometry that has none.
func _has_vector(value: Variant) -> bool:
	if value is Array:
		return (value as Array).size() >= 3
	return value is Vector3


func _vector_from(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	if value is Vector3:
		return value as Vector3
	return fallback
