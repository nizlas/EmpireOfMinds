# Headless test: godot --headless --path game -s res://dev/tests/test_terrain_preview_smoke.gd
#
# N3c.2 preview-scene smoke test: instantiates the terrain preview scene
# exactly as the editor's F6 does (no command-line arguments) and verifies
# the real runtime chain ran (WorldMap -> Ts08CutLattice -> Ts08HeightSolver
# -> Ts08SurfaceGeometry -> dev ArrayMesh) and the scene assembled its
# meshes, orbit camera, and HUD. Backend selector defaults to Auto (native
# when the built extension is available, otherwise GDScript).
extends SceneTree

const PREVIEW_SCENE_PATH := "res://dev/terrain_preview/terrain_preview.tscn"

const EXPECTED_NODE_COUNT := 74129
const EXPECTED_TOP_TRIANGLE_COUNT := 145152
const EXPECTED_WALL_FACE_COUNT := 936

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	var scene: PackedScene = load(PREVIEW_SCENE_PATH)
	_check(scene != null, "preview scene loads")
	if scene == null:
		_finish()
		return
	var preview = scene.instantiate()
	_check(preview != null, "preview scene instantiates")
	if preview == null:
		_finish()
		return

	# From SceneTree._init the node's _ready runs on the first iteration,
	# so wait for it before inspecting the assembled scene.
	root.add_child(preview)
	await preview.ready

	_check(preview.backend_used != "", "a backend was selected and reported")
	print("smoke: backend_used=%s" % preview.backend_used)
	print("smoke: timings=%s" % str(preview.timings))
	for key in ["lattice_msec", "solve_msec", "geometry_msec", "mesh_msec"]:
		_check(
			preview.timings.has(key) and int(preview.timings[key]) >= 0,
			"timing recorded: %s" % key
		)

	_check(int(preview.counts.get("nodes", 0)) == EXPECTED_NODE_COUNT, "node count")
	_check(
		int(preview.counts.get("top_triangles", 0)) == EXPECTED_TOP_TRIANGLE_COUNT,
		"top triangle count"
	)
	_check(
		int(preview.counts.get("wall_faces", 0)) == EXPECTED_WALL_FACE_COUNT,
		"wall face count"
	)

	var top = preview.get_node_or_null("TopSurface")
	_check(
		top is MeshInstance3D and top.mesh != null and top.mesh.get_surface_count() == 1,
		"top-surface ArrayMesh present"
	)
	var walls = preview.get_node_or_null("CliffWalls")
	_check(
		walls is MeshInstance3D and walls.mesh != null and walls.mesh.get_surface_count() == 1,
		"cliff-wall ArrayMesh present"
	)

	var camera = preview.get_node_or_null("OrbitCamera")
	_check(camera is Camera3D, "orbit camera present")
	if camera is Camera3D:
		_check(camera.current, "orbit camera is current")
		var state: Dictionary = camera.camera_state()
		_check(float(state["distance"]) > 0.0, "orbit camera framed (distance > 0)")

	var hud = preview.get_node_or_null("Hud")
	_check(hud is CanvasLayer, "HUD layer present")
	if hud is CanvasLayer:
		var labels: Array[String] = []
		_collect_labels(hud, labels)
		var backend_shown := false
		var controls_shown := false
		for text in labels:
			if text.begins_with("backend: %s" % preview.backend_used):
				backend_shown = true
			if text.contains("orbit") and text.contains("zoom"):
				controls_shown = true
		_check(backend_shown, "HUD shows the backend actually used")
		_check(controls_shown, "HUD shows the desktop controls")

	_finish()


func _collect_labels(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append(node.text)
	for child in node.get_children():
		_collect_labels(child, out)


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Terrain preview smoke tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
