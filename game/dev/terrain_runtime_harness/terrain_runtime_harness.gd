# Development-only terrain runtime harness (N3c.6). Visual/runtime
# integration harness for the shared runtime terrain world
# (game/presentation/world/terrain_world.gd) — nothing more.
#
# It loads the canonical test map (handdrawn_test_map_full_01) DIRECTLY,
# which is acceptable only because this is a dev harness. It is explicitly
# NOT the future one-PC gameplay debug mode: the locked direction is that
# the one-PC mode runs against a LOCALLY RUNNING authoritative server and
# uses the same client-server APIs, actions, validation, and authoritative
# rule path as remote cloud multiplayer — both feed the same runtime world.
# That server-fed WorldMap path is N7 and is deliberately not implemented
# here. The cloud front door (res://cloud/cloud_front_door.tscn) stays the
# main scene; the legacy playable path is untouched.
#
# N4: the harness displays the shared projected screen-space anchor UI
# (game/presentation/world/world_anchor_ui.gd) — left-clicking a terrain
# tile shows the provisional marker/label at that tile's projected world
# anchor. Presentation focus only; no units, players, gameplay selection,
# or gameplay state here.
#
# Run from the Godot editor: open this scene and press F6, or:
#   godot --path game res://dev/terrain_runtime_harness/terrain_runtime_harness.tscn
#
# Dev screenshot mode (review images; output/ is gitignored):
#   --select=q,r            focus one canonical tile before the shot
#   --screenshot[=low]      strategic (default) or low-angle preset, save, quit
#   --shot-yaw=<degrees>    override the preset yaw (proves anchor tracking)
extends Node3D

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")

const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const SCREENSHOT_DIR := "res://dev/terrain_runtime_harness/output"

# The runtime world and anchor UI nodes, exposed for the harness smoke test.
var world = null
var anchor_ui = null


func _ready() -> void:
	print("terrain_runtime_harness: loading canonical WorldMap (handdrawn_test_map_full_01)...")
	var world_map = MapContentLoader.load_reference_world_map()
	if world_map == null:
		push_error("terrain_runtime_harness: canonical WorldMap failed to load")
		get_tree().quit(1)
		return

	var backend := _auto_backend()
	if backend == Ts08HeightSolver.BACKEND_GDSCRIPT:
		print("terrain_runtime_harness: native extension unavailable; GDScript solve takes about a minute")
	world = TerrainWorldScript.new()
	world.name = "TerrainWorld"
	add_child(world)
	if not world.build(world_map, backend):
		push_error("terrain_runtime_harness: terrain world build failed")
		get_tree().quit(1)
		return
	print(
		"terrain_runtime_harness: world ready (map %s, backend %s)"
		% [world_map.identity.map_id, world.backend_used]
	)

	# N4: shared projected screen-space anchor UI (presentation component).
	anchor_ui = WorldAnchorUiScript.new()
	anchor_ui.name = "WorldAnchorUi"
	add_child(anchor_ui)
	anchor_ui.attach(world)

	var args := OS.get_cmdline_user_args()
	var select = _select_from_args(args)  # Variant: null or Vector2i
	if select is Vector2i:
		if not anchor_ui.focus_tile(select):
			push_error("terrain_runtime_harness: --select tile %s has no anchor" % str(select))
			get_tree().quit(1)
			return
	var preset := _screenshot_preset_from_args(args)
	if preset != "":
		_save_screenshot(preset, _screenshot_yaw_from_args(args))


# "--select=q,r" focuses one canonical tile (dev screenshot support).
# Returns null when not requested.
static func _select_from_args(args: PackedStringArray):
	for arg in args:
		if arg.begins_with("--select="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				return Vector2i(int(parts[0]), int(parts[1]))
			push_error("terrain_runtime_harness: --select expects q,r")
	return null


# "--screenshot" -> strategic; "--screenshot=low" -> low-angle preset.
static func _screenshot_preset_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--screenshot":
			return "strategic"
		if arg.begins_with("--screenshot="):
			return arg.get_slice("=", 1)
	return ""


# "--shot-yaw=<degrees>" overrides the preset yaw for one screenshot (proves
# the marker follows the same world anchor from a changed camera position).
static func _screenshot_yaw_from_args(args: PackedStringArray) -> float:
	for arg in args:
		if arg.begins_with("--shot-yaw="):
			return float(arg.get_slice("=", 1))
	return NAN


func _save_screenshot(preset: String, yaw_override := NAN) -> void:
	if preset == "low":
		world.camera.preset_low_angle()
	else:
		world.camera.preset_strategic()
	var suffix := ""
	if not is_nan(yaw_override):
		world.camera.yaw_deg = yaw_override
		world.camera.orbit(0.0, 0.0)
		suffix = "_yaw%d" % int(roundf(yaw_override))
	if anchor_ui.focused_tile != null:
		suffix += "_tile_%d_%d" % [anchor_ui.focused_tile.x, anchor_ui.focused_tile.y]
	var path := "%s/harness_%s%s.png" % [SCREENSHOT_DIR, preset, suffix]
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var error := image.save_png(global_path)
	if error == OK:
		print("terrain_runtime_harness: screenshot (%s) saved to %s" % [preset, global_path])
	else:
		push_error("terrain_runtime_harness: failed to save screenshot (%d)" % error)
	get_tree().quit(0 if error == OK else 1)


# Same Auto policy as the dev preview (dev-harness behavior only — this is
# deliberately NOT a production backend-selection policy; the runtime world
# itself keeps the backend caller-supplied): native when the built extension
# is available, otherwise the GDScript reference backend.
func _auto_backend() -> String:
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR_PATH):
		return Ts08HeightSolver.BACKEND_GDSCRIPT
	if not GDExtensionManager.is_extension_loaded(NATIVE_DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(NATIVE_DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			return Ts08HeightSolver.BACKEND_GDSCRIPT
	if ClassDB.can_instantiate(&"EomTerrainNative"):
		return Ts08HeightSolver.BACKEND_NATIVE
	return Ts08HeightSolver.BACKEND_GDSCRIPT
