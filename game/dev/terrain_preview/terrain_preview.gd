# Development-only interactive terrain-inspection preview (N3b/N3c). NOT
# runtime-world integration.
#
# Real runtime chain, always:
#   WorldMap -> Ts08CutLattice -> Ts08HeightSolver -> Ts08SurfaceGeometry
#   -> dev ArrayMesh
# Never loads N2 heights. The top surface renders with the N3c.3a three-layer
# PBR splatting material (game/presentation/terrain_surface_material.gd);
# cliff walls render with the N3c.3b Stage-3a stone PBR material and
# wall-local UVs (game/presentation/terrain_cliff_wall_material.gd).
# Deterministic static terrain collision (N3c.4) is derived from the same
# geometry (game/presentation/terrain_collision.gd): one TerrainCollision
# StaticBody3D with separate top/wall concave shapes; derived data only.
# Deterministic tile/cliff-edge picking (N3c.5) raycasts left-clicks against
# that collision (game/presentation/terrain_picker.gd) and shows the
# canonical WorldMap identity in the HUD — inspection feedback only, no
# selection state, overlays, or gameplay.
# Basic lighting unchanged.
#
# Run from the Godot editor: open this scene and press F6 (no arguments
# needed; backend selector defaults to Auto). Or from the command line:
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --native
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --screenshot [--native]
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --screenshot=low --native
#   godot --path game res://dev/terrain_preview/terrain_preview.tscn -- --screenshot --stage=ash_mask
#
# Backend selector (dev preview tool behavior only — NOT automatic
# production backend selection):
#   Auto (default) - native when the built extension is available, else GDScript
#   Native         - fails clearly when the extension is unavailable
#   GDScript       - always available (clean-checkout verification)
# `--native` on the command line forces Native.
#
# Material debug stages (N3c.3a): final, ash_mask, stone_mask, albedo.
# `--stage=<name>` selects the stage; the M key cycles stages at runtime.
# Both the top-surface and cliff-wall shaders follow the same stage
# (ash_mask: walls black; stone_mask: walls white; albedo: wall albedo only).
#
# Controls (also shown in the HUD):
#   LMB / RMB drag        orbit (360° yaw, clamped pitch)
#   MMB / Shift+LMB drag  pan the orbit target on the ground plane
#   mouse wheel           zoom (map-relative limits)
#   LMB click             pick tile / cliff edge (result in the HUD)
#   R / Home              reset to the strategic view
#   1 / 2                 strategic / low-angle camera preset
#   M                     cycle material debug stage
extends Node3D

enum BackendMode { AUTO, NATIVE, GDSCRIPT }

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08SurfaceGeometry = preload("res://domain/world/ts08_surface_geometry.gd")
const OrbitCameraScript = preload("res://dev/terrain_preview/orbit_camera.gd")
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")
const TerrainCliffWallMaterial = preload("res://presentation/terrain_cliff_wall_material.gd")
const TerrainCollision = preload("res://presentation/terrain_collision.gd")
const TerrainPicker = preload("res://presentation/terrain_picker.gd")

const SCREENSHOT_PATHS := {
	"strategic": "res://dev/terrain_preview/output/terrain_preview_strategic.png",
	"low": "res://dev/terrain_preview/output/terrain_preview_low.png",
}
# Non-final material stages save under the stage name instead of the preset.
const SCREENSHOT_STAGE_PATH_TEMPLATE := "res://dev/terrain_preview/output/terrain_preview_%s.png"
const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const MATERIAL_STAGE_CYCLE := ["final", "ash_mask", "stone_mask", "albedo"]

## Dev-only backend selector, editable in the inspector. Auto uses the
## native extension when available and falls back to GDScript otherwise.
@export var backend_mode: BackendMode = BackendMode.AUTO

# Populated by _ready for the HUD, tests, and reporting.
var backend_used := ""
var timings: Dictionary = {}
var counts: Dictionary = {}
var material_stage := "final"

var _camera: Camera3D = null
var _hud_camera_label: Label = null
var _hud_material_label: Label = null
var _hud_pick_label: Label = null
var _hud_layer: CanvasLayer = null
var _top_material: ShaderMaterial = null
var _wall_material: ShaderMaterial = null

# N3c.5 picking state (read-only references; the picker never mutates them).
var _world_map = null
var _geometry = null
var _wall_triangle_map := PackedInt32Array()
var _pending_pick_screen_pos := Vector2.ZERO
var _pick_requested := false


# Preview-tool backend resolution (pure; unit-tested). Returns
# {"ok": bool, "backend": String, "error": String}.
static func resolve_backend(mode: BackendMode, native_available: bool) -> Dictionary:
	match mode:
		BackendMode.NATIVE:
			if native_available:
				return {"ok": true, "backend": Ts08HeightSolver.BACKEND_NATIVE, "error": ""}
			return {
				"ok": false,
				"backend": "",
				"error": (
					"Native backend requested but the GDExtension is unavailable; "
					+ "build it first (.\\scripts\\build-native.ps1). No silent fallback."
				),
			}
		BackendMode.GDSCRIPT:
			return {"ok": true, "backend": Ts08HeightSolver.BACKEND_GDSCRIPT, "error": ""}
		_:
			return {
				"ok": true,
				"backend": (
					Ts08HeightSolver.BACKEND_NATIVE
					if native_available
					else Ts08HeightSolver.BACKEND_GDSCRIPT
				),
				"error": "",
			}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := backend_mode
	if "--native" in args:
		mode = BackendMode.NATIVE
	material_stage = _material_stage_from_args(args)

	var native_available := _load_native_extension()
	var resolved := resolve_backend(mode, native_available)
	if not resolved["ok"]:
		push_error("terrain_preview: %s" % resolved["error"])
		get_tree().quit(1)
		return
	backend_used = resolved["backend"]

	print("terrain_preview: loading WorldMap...")
	var world_map = MapContentLoader.load_reference_world_map()
	if world_map == null:
		push_error("terrain_preview: reference WorldMap failed to load")
		get_tree().quit(1)
		return

	print("terrain_preview: building cut lattice...")
	var t0 := Time.get_ticks_msec()
	var build = Ts08CutLattice.build_from_world_map(world_map)
	timings["lattice_msec"] = Time.get_ticks_msec() - t0
	print("terrain_preview: lattice %d ms (%d nodes)" % [timings["lattice_msec"], build.node_count])

	if backend_used == Ts08HeightSolver.BACKEND_NATIVE:
		print("terrain_preview: solving heights (native backend)...")
	else:
		print("terrain_preview: solving heights (GDScript backend, about a minute)...")
	var verbose := backend_used == Ts08HeightSolver.BACKEND_GDSCRIPT
	var solve = Ts08HeightSolver.solve(world_map, build, verbose, backend_used)
	if solve == null:
		push_error("terrain_preview: height solve failed (backend %s)" % backend_used)
		get_tree().quit(1)
		return
	timings["solve_msec"] = solve.solve_msec
	print("terrain_preview: solve %d ms, converged=%s" % [solve.solve_msec, solve.converged])

	print("terrain_preview: building surface geometry...")
	var geometry = Ts08SurfaceGeometry.build(world_map, build, solve.heights)
	if geometry == null:
		push_error("terrain_preview: surface geometry build failed")
		get_tree().quit(1)
		return
	timings["geometry_msec"] = geometry.build_msec

	counts = {
		"nodes": build.node_count,
		"top_triangles": geometry.top_triangles.size() / 3,
		"wall_faces": geometry.wall_faces.size(),
		"wall_quads": geometry.wall_quad_count,
		"wall_triangles": geometry.wall_triangle_count,
	}
	print(
		"terrain_preview: geometry %d ms (%d wall faces: %d quads, %d crack-tip triangles)"
		% [
			geometry.build_msec,
			geometry.wall_faces.size(),
			geometry.wall_quad_count,
			geometry.wall_triangle_count,
		]
	)

	var t_mesh := Time.get_ticks_msec()
	var top_mesh := _build_top_mesh(geometry)
	var top_instance := MeshInstance3D.new()
	top_instance.name = "TopSurface"
	top_instance.mesh = top_mesh
	add_child(top_instance)

	var wall_mesh := _build_wall_mesh(geometry)
	if wall_mesh != null:
		var wall_instance := MeshInstance3D.new()
		wall_instance.name = "CliffWalls"
		wall_instance.mesh = wall_mesh
		add_child(wall_instance)
	timings["mesh_msec"] = Time.get_ticks_msec() - t_mesh

	_world_map = world_map
	_geometry = geometry

	var t_collision := Time.get_ticks_msec()
	var collision_body := TerrainCollision.build_static_body(geometry)
	add_child(collision_body)
	_wall_triangle_map = TerrainPicker.build_wall_triangle_map(geometry)
	timings["collision_msec"] = Time.get_ticks_msec() - t_collision
	var top_shape: ConcavePolygonShape3D = collision_body.get_node(
		TerrainCollision.TOP_SHAPE_NAME
	).shape
	var wall_shape_node := collision_body.get_node_or_null(TerrainCollision.WALL_SHAPE_NAME)
	counts["collision_top_triangles"] = top_shape.get_faces().size() / 3
	counts["collision_wall_triangles"] = (
		wall_shape_node.shape.get_faces().size() / 3 if wall_shape_node != null else 0
	)
	print(
		"terrain_preview: collision %d ms (%d top + %d wall triangles)"
		% [
			timings["collision_msec"],
			counts["collision_top_triangles"],
			counts["collision_wall_triangles"],
		]
	)

	_add_lighting()
	var aabb := top_mesh.get_aabb()
	print("terrain_preview: mesh AABB=%s" % aabb)
	_camera = OrbitCameraScript.new()
	_camera.name = "OrbitCamera"
	add_child(_camera)
	_camera.configure_from_aabb(aabb)
	_camera.current = true

	_build_hud()

	var screenshot_preset := _screenshot_preset_from_args(args)
	if screenshot_preset != "":
		_save_screenshot(screenshot_preset)


func _process(_delta: float) -> void:
	if _camera == null or _hud_camera_label == null:
		return
	var state: Dictionary = _camera.camera_state()
	_hud_camera_label.text = (
		"camera: yaw %.1f°  pitch %.1f°  dist %.2f  target (%.2f, %.2f, %.2f)"
		% [
			state["yaw_deg"],
			state["pitch_deg"],
			state["distance"],
			state["target"].x,
			state["target"].y,
			state["target"].z,
		]
	)


func _load_native_extension() -> bool:
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR_PATH):
		return false
	if not GDExtensionManager.is_extension_loaded(NATIVE_DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(NATIVE_DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			return false
	return ClassDB.can_instantiate(&"EomTerrainNative")


# "--screenshot" -> strategic; "--screenshot=low" / "--screenshot=strategic"
# select a deterministic camera preset. Returns "" when not requested.
static func _screenshot_preset_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--screenshot":
			return "strategic"
		if arg.begins_with("--screenshot="):
			var preset := arg.get_slice("=", 1)
			if SCREENSHOT_PATHS.has(preset):
				return preset
			push_error("terrain_preview: unknown screenshot preset '%s'" % preset)
			return "strategic"
	return ""


# "--stage=<name>" selects a material debug stage (default "final").
static func _material_stage_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--stage="):
			var stage := arg.get_slice("=", 1)
			if TerrainSurfaceMaterial.DEBUG_STAGES.has(stage):
				return stage
			push_error(
				"terrain_preview: unknown material stage '%s' (valid: %s)"
				% [stage, ", ".join(TerrainSurfaceMaterial.DEBUG_STAGES.keys())]
			)
			return "final"
	return "final"


# Deterministic screenshot path: final stage keeps the camera-preset names;
# mask/albedo stages save under the stage name.
static func _screenshot_path(preset: String, stage: String) -> String:
	if stage == "final":
		return SCREENSHOT_PATHS[preset]
	return SCREENSHOT_STAGE_PATH_TEMPLATE % stage


# Top surface from the builder's Y-up oriented triangles and smooth normals,
# with the N3c.3a world-anchored UVs and planar tangents for the splatting
# material. Godot front faces are clockwise, so the index buffer emits each
# triangle in reversed order.
func _build_top_mesh(geometry) -> ArrayMesh:
	var tri_count: int = geometry.top_triangles.size() / 3
	var indices := PackedInt32Array()
	indices.resize(geometry.top_triangles.size())
	var cursor := 0
	for t in tri_count:
		indices[cursor] = geometry.top_triangles[3 * t]
		indices[cursor + 1] = geometry.top_triangles[3 * t + 2]
		indices[cursor + 2] = geometry.top_triangles[3 * t + 1]
		cursor += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geometry.top_positions
	arrays[Mesh.ARRAY_NORMAL] = geometry.top_normals
	arrays[Mesh.ARRAY_TEX_UV] = TerrainSurfaceMaterial.build_world_uv_array(geometry.top_positions)
	arrays[Mesh.ARRAY_TANGENT] = TerrainSurfaceMaterial.build_top_surface_tangents(
		geometry.top_normals
	)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_top_material = TerrainSurfaceMaterial.create_material(material_stage)
	if _top_material == null:
		push_error("terrain_preview: failed to create the terrain surface material")
		return mesh
	mesh.surface_set_material(0, _top_material)
	return mesh


# Wall faces are stored counter-clockwise around the outward normal that
# points toward the lower tile (plane->Godot is a rotation, so the winding
# carries over). Flat shading: fan-triangulate each polygon with duplicated
# vertices and per-face normals (identical vertex output to N3c.1), now with
# the N3c.3b wall-local UVs and per-triangle tangents baked for the Stage-3a
# stone PBR material.
func _build_wall_mesh(geometry) -> ArrayMesh:
	if geometry.wall_faces.is_empty():
		return null
	var wall_arrays: Dictionary = TerrainCliffWallMaterial.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = wall_arrays["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = wall_arrays["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = wall_arrays["uvs"]
	arrays[Mesh.ARRAY_TANGENT] = wall_arrays["tangents"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_wall_material = TerrainCliffWallMaterial.create_material(material_stage)
	if _wall_material == null:
		push_error("terrain_preview: failed to create the cliff-wall material")
		return mesh
	mesh.surface_set_material(0, _wall_material)
	return mesh


func _add_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	light.light_energy = 1.0
	add_child(light)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.15, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.85)
	environment.ambient_light_energy = 0.35
	world_environment.environment = environment
	add_child(world_environment)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	add_child(_hud_layer)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(12, 12)
	_hud_layer.add_child(panel)

	var rows := VBoxContainer.new()
	panel.add_child(rows)

	var mode_names := {
		BackendMode.AUTO: "Auto",
		BackendMode.NATIVE: "Native",
		BackendMode.GDSCRIPT: "GDScript",
	}
	rows.add_child(_hud_label(
		"backend: %s (selector: %s)" % [backend_used, mode_names[backend_mode]]
	))
	rows.add_child(_hud_label(
		"timings: lattice %d ms · solve %d ms · geometry %d ms · mesh %d ms · collision %d ms"
		% [
			timings.get("lattice_msec", -1),
			timings.get("solve_msec", -1),
			timings.get("geometry_msec", -1),
			timings.get("mesh_msec", -1),
			timings.get("collision_msec", -1),
		]
	))
	rows.add_child(_hud_label(
		"topology: %d nodes · %d top tris · %d wall faces (%d quads + %d crack tips)"
		% [
			counts.get("nodes", 0),
			counts.get("top_triangles", 0),
			counts.get("wall_faces", 0),
			counts.get("wall_quads", 0),
			counts.get("wall_triangles", 0),
		]
	))
	_hud_material_label = _hud_label("")
	_update_material_hud()
	rows.add_child(_hud_material_label)
	_hud_camera_label = _hud_label("camera: —")
	rows.add_child(_hud_camera_label)
	_hud_pick_label = _hud_label("pick: — (left-click terrain)")
	rows.add_child(_hud_pick_label)
	rows.add_child(_hud_label(""))
	rows.add_child(_hud_label(
		"LMB click pick · LMB/RMB drag orbit · MMB or Shift+LMB drag pan · wheel zoom"
	))
	rows.add_child(_hud_label(
		"R/Home reset · 1 strategic preset · 2 low-angle preset · M material stage"
	))


func _hud_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	return label


func _update_material_hud() -> void:
	if _hud_material_label != null:
		_hud_material_label.text = "material: %s" % material_stage


# N3c.5: a plain left-click requests a pick raycast (Shift+LMB stays pan;
# the orbit camera keeps seeing the same events). The raycast itself runs in
# _physics_process, where the physics space is safe to query.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed or button.shift_pressed:
		return
	_pending_pick_screen_pos = button.position
	_pick_requested = true


func _physics_process(_delta: float) -> void:
	if not _pick_requested:
		return
	_pick_requested = false
	_show_pick_result(_perform_pick(_pending_pick_screen_pos))


# Raycasts one screen position through the preview camera against the
# terrain collision and resolves the canonical identity via TerrainPicker.
func _perform_pick(screen_pos: Vector2) -> Dictionary:
	if _camera == null or _world_map == null or _geometry == null:
		return {}
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * _camera.far)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	return TerrainPicker.resolve_pick(hit, _world_map, _geometry, _wall_triangle_map)


# Inspection feedback only: show the latest pick result in the HUD.
func _show_pick_result(pick: Dictionary) -> void:
	if _hud_pick_label == null:
		return
	match pick.get("kind", ""):
		TerrainPicker.KIND_TILE:
			_hud_pick_label.text = "pick: Tile: (%d,%d)" % [pick["tile"].x, pick["tile"].y]
		TerrainPicker.KIND_CLIFF:
			_hud_pick_label.text = (
				"pick: Cliff: (%d,%d)–(%d,%d)"
				% [pick["tile_a"].x, pick["tile_a"].y, pick["tile_b"].x, pick["tile_b"].y]
			)
		_:
			_hud_pick_label.text = "pick: No terrain hit"


# M cycles the material debug stage (final -> ash_mask -> stone_mask -> albedo);
# the top-surface and cliff-wall materials stay synchronized on one stage.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M and _top_material != null:
		var index := MATERIAL_STAGE_CYCLE.find(material_stage)
		material_stage = MATERIAL_STAGE_CYCLE[(index + 1) % MATERIAL_STAGE_CYCLE.size()]
		TerrainSurfaceMaterial.set_debug_stage(_top_material, material_stage)
		if _wall_material != null:
			TerrainCliffWallMaterial.set_debug_stage(_wall_material, material_stage)
		_update_material_hud()


func _save_screenshot(preset: String) -> void:
	if preset == "low":
		_camera.preset_low_angle()
	else:
		_camera.preset_strategic()
	# Hide the HUD so review images show terrain only.
	_hud_layer.visible = false
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var global_path := ProjectSettings.globalize_path(_screenshot_path(preset, material_stage))
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var error := image.save_png(global_path)
	if error == OK:
		print(
			"terrain_preview: screenshot (%s, stage %s) saved to %s"
			% [preset, material_stage, global_path]
		)
	else:
		push_error("terrain_preview: failed to save screenshot (%d)" % error)
	get_tree().quit(0 if error == OK else 1)
