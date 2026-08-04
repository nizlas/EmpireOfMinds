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
# No units, players, selection state, or gameplay here.
#
# Run from the Godot editor: open this scene and press F6, or:
#   godot --path game res://dev/terrain_runtime_harness/terrain_runtime_harness.tscn
extends Node3D

const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")

const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# The runtime world node, exposed for the harness smoke test.
var world = null


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
