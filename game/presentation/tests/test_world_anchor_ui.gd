# Headless test: godot --headless --path game -s res://presentation/tests/test_world_anchor_ui.gd
#
# N4 projected screen-space anchor UI
# (game/presentation/world/world_anchor_ui.gd), tested against a synthetic
# world stub (camera + tile_anchors + terrain_picked) so the component
# contract is covered without a terrain build:
# - selection: a tile pick focuses the tile and shows the marker exactly at
#   the camera-projected world anchor;
# - stable projection: the marker tracks camera orbit, pitch, pan, zoom,
#   per-frame _process updates, and viewport resizing;
# - a miss (empty pick) clears the focus;
# - locked cliff rule: a cliff pick NEVER silently selects either
#   neighboring tile — the focus stays unchanged (both with and without a
#   prior focus);
# - anchors behind the camera hide the marker; unknown tiles are refused;
# - focus is presentation state only (no domain writes anywhere).
extends SceneTree

const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const OrbitCameraScript = preload("res://presentation/world/orbit_camera.gd")

const TILE_A := Vector2i(2, -1)
const TILE_B := Vector2i(-3, 4)
const TILE_BEHIND := Vector2i(9, 9)

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

	# Host everything in a SubViewport so viewport resizing is real even in
	# headless runs (the headless root window ignores size changes).
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
		TILE_A: Vector3(2.5, 0.8, -1.4),
		TILE_B: Vector3(-4.1, 0.4, 5.3),
	}

	var ui = WorldAnchorUiScript.new()
	ui.name = "WorldAnchorUi"
	viewport.add_child(ui)
	ui.attach(stub)
	var marker: Control = ui.get_node("AnchorOverlay/TileMarker")
	var label: Label = ui.get_node("AnchorOverlay/TileMarker/TileLabel")

	_check(ui.focused_tile == null and not marker.visible, "starts unfocused with a hidden marker")

	# --- selection via the terrain_picked presentation output ---
	stub.terrain_picked.emit({"kind": "tile", "tile": TILE_A})
	_check(ui.focused_tile == TILE_A, "tile pick focuses the picked tile")
	_check(marker.visible, "marker shown for a focused tile")
	_check(
		marker.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"marker sits exactly at the projected world anchor"
	)
	_check(label.text == "Tile (2, -1)", "label shows the canonical tile id")

	# --- stable projection across camera movement ---
	var before: Vector2 = marker.position
	camera.orbit(37.0, -12.0)
	ui.refresh()
	_check(
		marker.position != before
		and marker.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"marker tracks camera orbit + pitch"
	)
	camera.zoom_by(1.6)
	ui.refresh()
	_check(
		marker.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"marker tracks camera zoom"
	)
	camera.pan_screen(80.0, -55.0)
	ui.refresh()
	_check(
		marker.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"marker tracks camera pan"
	)
	camera.preset_low_angle()
	await process_frame
	_check(
		marker.position == camera.unproject_position(stub.tile_anchors[TILE_A]),
		"per-frame _process re-projects without manual refresh"
	)
	ui.refresh()
	var repeat: Vector2 = marker.position
	ui.refresh()
	_check(marker.position == repeat, "projection deterministic for a fixed camera")

	# --- viewport resizing ---
	var projected_before: Vector2 = camera.unproject_position(stub.tile_anchors[TILE_A])
	viewport.size = Vector2i(1120, 630)
	ui.refresh()
	_check(
		marker.position == camera.unproject_position(stub.tile_anchors[TILE_A])
		and marker.position != projected_before,
		"marker tracks viewport resizing"
	)

	# --- miss clears the focus ---
	stub.terrain_picked.emit({})
	_check(ui.focused_tile == null and not marker.visible, "a miss clears the focus")

	# --- locked cliff rule: never silently either neighboring tile ---
	var cliff_pick := {
		"kind": "cliff",
		"edge_key": "(2,-1)|(3,-1)",
		"tile_a": TILE_A,
		"tile_b": Vector2i(3, -1),
	}
	stub.terrain_picked.emit(cliff_pick)
	_check(
		ui.focused_tile == null and not marker.visible,
		"cliff pick without prior focus selects nothing"
	)
	stub.terrain_picked.emit({"kind": "tile", "tile": TILE_B})
	stub.terrain_picked.emit(cliff_pick)
	_check(
		ui.focused_tile == TILE_B and marker.visible,
		"cliff pick leaves an existing focus unchanged (never a neighboring tile)"
	)

	# --- behind-camera anchors hide the marker ---
	stub.tile_anchors[TILE_BEHIND] = (
		camera.position + camera.transform.basis.z * 10.0
	)
	_check(ui.focus_tile(TILE_BEHIND), "anchor behind the camera can still be focused")
	_check(not marker.visible, "marker hidden while the anchor is behind the camera")
	camera.preset_strategic()
	ui.refresh()
	_check(ui.focused_tile == TILE_BEHIND, "focus survives while hidden")

	# --- unknown tiles are refused ---
	stub.terrain_picked.emit({"kind": "tile", "tile": TILE_A})
	_check(not ui.focus_tile(Vector2i(99, 99)), "unknown tile refused")
	_check(ui.focused_tile == TILE_A, "refused focus leaves the current focus unchanged")

	_finish()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("WorldAnchorUi tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
