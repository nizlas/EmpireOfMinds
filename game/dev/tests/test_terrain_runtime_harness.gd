# Headless test: godot --headless --path game -s res://dev/tests/test_terrain_runtime_harness.gd
#
# N3c.6 dev terrain runtime harness smoke test: the development-only
# visual/runtime integration harness loads the canonical test map directly
# and displays the shared runtime terrain world. It is NOT the future
# one-PC gameplay debug mode (that mode runs against a locally running
# authoritative server through the same client-server API/action path as
# remote multiplayer — N7). No units, player switching, gameplay state, or
# legacy HexMap here, and the cloud front door stays the project main scene.
#
# N4: the harness owns exactly one instance of the shared projected
# screen-space anchor UI (game/presentation/world/world_anchor_ui.gd)
# attached to the runtime world — picks drive the presentation-only tile
# focus, the marker sits at the projected world anchor, and no legacy
# HexMap / Unit3DWorldView / City3DWorldView anchor path is involved.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
extends SceneTree

const HARNESS_SCENE_PATH := "res://dev/terrain_runtime_harness/terrain_runtime_harness.tscn"
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const EXPECTED_MAP_ID := "handdrawn_test_map_full_01"

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene")) ==
			"res://cloud/cloud_front_door.tscn",
		"cloud front door stays the project main scene"
	)

	var scene: PackedScene = load(HARNESS_SCENE_PATH)
	_check(scene != null, "harness scene loads")
	if scene == null:
		_finish()
		return
	var harness = scene.instantiate()
	root.add_child(harness)
	await harness.ready

	var world = harness.world
	_check(world != null and world == harness.get_node_or_null("TerrainWorld"),
		"harness displays the shared runtime terrain world")
	if world == null:
		_finish()
		return
	_check(
		world.get_script() == load("res://presentation/world/terrain_world.gd"),
		"the exact shared runtime-world component is used (no second implementation)"
	)
	var anchor_ui = harness.anchor_ui
	_check(
		anchor_ui != null and anchor_ui == harness.get_node_or_null("WorldAnchorUi")
		and anchor_ui.get_script() == load("res://presentation/world/world_anchor_ui.gd"),
		"harness owns one shared projected anchor UI (no second implementation)"
	)
	_check(
		harness.get_child_count() == 2,
		"harness adds nothing beyond the runtime world + anchor UI (no gameplay state)"
	)
	# N3c.7: lighting is owned by the shared runtime world — the dev harness
	# must not carry a competing rig.
	var rig = world.get_node_or_null("TerrainLighting")
	var lighting_nodes: Array = []
	_collect_lighting_nodes(harness, lighting_nodes)
	var lighting_shared := rig != null and lighting_nodes.size() == 3
	for node in lighting_nodes:
		if node.get_parent() != rig:
			lighting_shared = false
	_check(lighting_shared, "all lighting lives in the shared TerrainLighting rig")
	_check(
		world.world_map != null and world.world_map.identity.map_id == EXPECTED_MAP_ID,
		"canonical handdrawn_test_map_full_01 WorldMap loaded directly (dev harness only)"
	)
	# The harness uses the preview Auto policy; with the extension built
	# (test prerequisite) that resolves to the native backend.
	_check(
		world.backend_used == Ts08HeightSolver.BACKEND_NATIVE,
		"Auto policy resolved to the native backend (extension built)"
	)
	_check(
		int(world.counts.get("nodes", 0)) == 74129
		and int(world.counts.get("top_triangles", 0)) == 145152
		and int(world.counts.get("collision_wall_triangles", 0)) == 1852,
		"runtime world built the full reference terrain"
	)

	# N4: world anchors exposed as derived presentation data.
	_check(
		world.tile_anchors.size() == world.world_map.tile_count()
		and int(world.counts.get("tile_anchors", 0)) == world.world_map.tile_count(),
		"runtime world exposes one anchor per canonical tile"
	)

	# Picking works end to end in the harness and drives the anchor UI.
	await physics_frame
	await physics_frame
	var pick: Dictionary = world.pick_at_screen_position(root.get_visible_rect().size / 2.0)
	_check(
		pick.get("kind", "") in ["tile", "cliff"],
		"center-screen pick resolves in the harness"
	)
	print("harness center pick = %s" % str(pick))
	var marker: Control = anchor_ui.get_node("AnchorOverlay/TileMarker")
	if pick.get("kind", "") == "tile":
		_check(
			anchor_ui.focused_tile == pick["tile"],
			"tile pick focuses the picked tile in the anchor UI"
		)
		anchor_ui.refresh()
		_check(
			marker.visible
			and marker.position == world.camera.unproject_position(
				world.tile_anchors[pick["tile"]]
			),
			"marker sits at the projected world anchor of the picked tile"
		)
	else:
		_check(
			anchor_ui.focused_tile == null,
			"cliff pick never silently selects a neighboring tile"
		)
	# A miss through the same pick path clears the focus.
	var miss: Dictionary = world.pick_at_screen_position(Vector2(1.0, 1.0))
	if miss.is_empty():
		_check(
			anchor_ui.focused_tile == null and not marker.visible,
			"a missed pick clears the anchor-UI focus"
		)
	else:
		print("corner pick unexpectedly hit terrain (%s); miss-clear covered by the UI suite" % str(miss))

	_finish()


static func _collect_lighting_nodes(node: Node, out: Array) -> void:
	if node is Light3D or node is WorldEnvironment:
		out.append(node)
	for child in node.get_children():
		_collect_lighting_nodes(child, out)


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainRuntimeHarness tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
