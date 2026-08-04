# Development-only interactive terrain-inspection preview (N3b/N3c). NOT
# runtime-world integration itself — since N3c.6 it is a thin dev shell
# around the shared runtime terrain world component
# (game/presentation/world/terrain_world.gd), which owns the one real chain:
#   WorldMap -> Ts08CutLattice -> Ts08HeightSolver -> Ts08SurfaceGeometry
#   -> ArrayMesh + N3c.3a/3b materials -> N3c.4 collision -> orbit camera
#   -> N3c.5 tile/cliff picking
# Never loads N2 heights. There is no second terrain implementation here:
# the preview only adds dev-only concerns — HUD, screenshot mode, material
# stage cycling, and the backend selector.
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
# production backend selection; the runtime world keeps the backend
# caller-supplied):
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
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")

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

# Mirrored from the runtime world by _ready for the HUD, tests, and
# reporting.
var backend_used := ""
var timings: Dictionary = {}
var counts: Dictionary = {}
var material_stage := "final"

var _world = null
var _camera: Camera3D = null
var _hud_camera_label: Label = null
var _hud_material_label: Label = null
var _hud_pick_label: Label = null
var _hud_layer: CanvasLayer = null


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

	print("terrain_preview: loading WorldMap...")
	var world_map = MapContentLoader.load_reference_world_map()
	if world_map == null:
		push_error("terrain_preview: reference WorldMap failed to load")
		get_tree().quit(1)
		return

	var verbose: bool = resolved["backend"] == Ts08HeightSolver.BACKEND_GDSCRIPT
	if verbose:
		print("terrain_preview: solving heights (GDScript backend, about a minute)...")
	_world = TerrainWorldScript.new()
	_world.name = "TerrainWorld"
	add_child(_world)
	if not _world.build(world_map, resolved["backend"], material_stage, verbose):
		push_error("terrain_preview: terrain world build failed")
		get_tree().quit(1)
		return

	backend_used = _world.backend_used
	timings = _world.timings
	counts = _world.counts
	_camera = _world.camera
	_world.terrain_picked.connect(_show_pick_result)
	print(
		"terrain_preview: mesh AABB=%s"
		% _world.get_node("TopSurface").mesh.get_aabb()
	)

	_build_hud()

	var screenshot_preset := _screenshot_preset_from_args(args)
	if screenshot_preset != "":
		_save_screenshot(
			screenshot_preset,
			_screenshot_yaw_from_args(args),
			_screenshot_pitch_from_args(args)
		)


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


# "--shot-yaw=<degrees>" / "--shot-pitch=<degrees>" (dev diagnostics)
# override the preset camera angles for one screenshot, e.g. to verify sky
# content at another azimuth or an intermediate pitch. Return NAN when not
# requested.
static func _screenshot_yaw_from_args(args: PackedStringArray) -> float:
	return _screenshot_angle_from_args(args, "--shot-yaw=")


static func _screenshot_pitch_from_args(args: PackedStringArray) -> float:
	return _screenshot_angle_from_args(args, "--shot-pitch=")


static func _screenshot_angle_from_args(args: PackedStringArray, prefix: String) -> float:
	for arg in args:
		if arg.begins_with(prefix):
			return float(arg.get_slice("=", 1))
	return NAN


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


# Inspection feedback only: show the latest pick from the runtime world
# (terrain_picked signal) in the HUD.
func _show_pick_result(pick: Dictionary) -> void:
	if _hud_pick_label == null:
		return
	match pick.get("kind", ""):
		"tile":
			_hud_pick_label.text = "pick: Tile: (%d,%d)" % [pick["tile"].x, pick["tile"].y]
		"cliff":
			_hud_pick_label.text = (
				"pick: Cliff: (%d,%d)–(%d,%d)"
				% [pick["tile_a"].x, pick["tile_a"].y, pick["tile_b"].x, pick["tile_b"].y]
			)
		_:
			_hud_pick_label.text = "pick: No terrain hit"


# M cycles the material debug stage (final -> ash_mask -> stone_mask -> albedo);
# the runtime world keeps both terrain shaders synchronized on one stage.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M and _world != null:
		var index := MATERIAL_STAGE_CYCLE.find(material_stage)
		material_stage = MATERIAL_STAGE_CYCLE[(index + 1) % MATERIAL_STAGE_CYCLE.size()]
		_world.set_material_stage(material_stage)
		_update_material_hud()


func _save_screenshot(preset: String, yaw_override := NAN, pitch_override := NAN) -> void:
	if preset == "low":
		_camera.preset_low_angle()
	else:
		_camera.preset_strategic()
	var path := _screenshot_path(preset, material_stage)
	if not is_nan(yaw_override):
		_camera.yaw_deg = yaw_override
		path = path.get_basename() + ("_yaw%d.png" % int(roundf(yaw_override)))
	if not is_nan(pitch_override):
		_camera.pitch_deg = pitch_override
		path = path.get_basename() + ("_pitch%d.png" % int(roundf(pitch_override)))
	if not (is_nan(yaw_override) and is_nan(pitch_override)):
		_camera.orbit(0.0, 0.0)
	# Hide the HUD so review images show terrain only.
	_hud_layer.visible = false
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var global_path := ProjectSettings.globalize_path(path)
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
