# Headless test: godot --headless --path game -s res://presentation/tests/test_world_destination_markers.gd
#
# N7d projected destination/selection markers
# (game/presentation/world/world_destination_markers.gd), tested against a
# synthetic world stub (camera + tile_anchors) so the component contract is
# covered without a terrain build:
# - one destination marker per supplied tile, 1:1, exactly at the projected
#   anchor (the component never adds, drops, or invents destinations);
# - selected-unit highlight at the selected tile's projected anchor;
# - markers re-project with camera movement and per-frame refresh;
# - clearing removes every destination marker and hides the highlight;
# - anchors behind the camera / unknown tiles hide their markers;
# - every control ignores the mouse (TerrainWorld stays the single
#   pick-input boundary — marker clicks are terrain picks).
extends SceneTree

const WorldDestinationMarkersScript = preload("res://presentation/world/world_destination_markers.gd")
const OrbitCameraScript = preload("res://presentation/world/orbit_camera.gd")

const TILE_SEL := Vector2i(1, 1)
const TILE_A := Vector2i(2, 1)
const TILE_B := Vector2i(0, 1)
const TILE_UNKNOWN := Vector2i(9, 9)

var _total := 0
var _any_fail := false


class WorldStub extends Node3D:
	signal terrain_picked(pick: Dictionary)
	var camera: Camera3D = null
	var tile_anchors: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	root.add_child(viewport)

	var stub := WorldStub.new()
	stub.name = "WorldStub"
	viewport.add_child(stub)
	var camera: Camera3D = OrbitCameraScript.new()
	stub.add_child(camera)
	stub.camera = camera
	camera.configure_from_aabb(AABB(Vector3(-6.0, 0.0, -6.0), Vector3(12.0, 1.2, 12.0)))
	stub.tile_anchors = {
		TILE_SEL: Vector3(1.0, 0.7, -1.0),
		TILE_A: Vector3(2.1, 0.8, -1.2),
		TILE_B: Vector3(-0.4, 0.6, -0.9),
	}

	var markers = WorldDestinationMarkersScript.new()
	markers.name = "WorldDestinationMarkers"
	viewport.add_child(markers)
	markers.attach(stub)

	_check(markers.destination_count() == 0, "starts with no destination markers")
	_check(not markers.selected_marker().visible, "starts with a hidden selection highlight")

	# --- 1:1 destination mapping at the projected anchors ---
	markers.set_markers(TILE_SEL, [TILE_A, TILE_B])
	_check(markers.destination_count() == 2, "one marker per supplied destination tile")
	var marker_a: Control = markers.destination_marker_for_tile(TILE_A)
	var marker_b: Control = markers.destination_marker_for_tile(TILE_B)
	_check(marker_a != null and marker_b != null, "markers are addressable per tile")
	_check(
		marker_a.visible and marker_a.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"destination marker sits exactly at the projected anchor"
	)
	_check(
		markers.selected_marker().visible
			and markers.selected_marker().position
				== camera.unproject_position(stub.tile_anchors[TILE_SEL]),
		"selection highlight sits exactly at the selected tile's projected anchor"
	)
	_check(
		markers.destination_marker_for_tile(TILE_UNKNOWN) == null,
		"no marker exists for a tile that was never supplied"
	)

	# --- markers track camera movement (per-frame reprojection) ---
	camera.orbit(31.0, -9.0)
	markers.refresh()
	_check(
		marker_a.position == camera.unproject_position(stub.tile_anchors[TILE_A])
			and markers.selected_marker().position
				== camera.unproject_position(stub.tile_anchors[TILE_SEL]),
		"markers re-project after camera movement"
	)

	# --- unknown tiles / hidden states ---
	markers.set_markers(TILE_UNKNOWN, [TILE_UNKNOWN])
	_check(
		not markers.selected_marker().visible,
		"selection highlight hides for a tile without an anchor"
	)
	var unknown_marker: Control = markers.destination_marker_for_tile(TILE_UNKNOWN)
	_check(
		unknown_marker != null and not unknown_marker.visible,
		"destination marker for a tile without an anchor stays hidden"
	)

	# --- clear removes everything ---
	markers.set_markers(TILE_SEL, [TILE_A])
	markers.clear()
	_check(markers.destination_count() == 0, "clear removes every destination marker")
	_check(not markers.selected_marker().visible, "clear hides the selection highlight")
	_check(markers.selected_tile == null, "clear resets the selected tile mirror")

	# --- input transparency (single pick-input boundary stays TerrainWorld) ---
	markers.set_markers(TILE_SEL, [TILE_A, TILE_B])
	var all_ignore := true
	var control_count := 0
	for node in _all_controls(markers):
		control_count += 1
		if (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			all_ignore = false
	_check(
		control_count > 0 and all_ignore,
		"every marker control ignores the mouse (clicks stay terrain picks)"
	)

	_finish()


func _all_controls(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Control:
			out.append(child)
		out.append_array(_all_controls(child))
	return out


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("WorldDestinationMarkers tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
