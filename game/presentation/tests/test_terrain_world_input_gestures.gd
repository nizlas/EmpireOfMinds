# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_world_input_gestures.gd
#
# N4 click-vs-drag input contract (game/presentation/world/terrain_world.gd):
# terrain selection is deferred until the complete press-move-release LMB
# interaction is classified. TerrainWorld is the single pick-input boundary;
# the orbit camera owns only camera movement and keeps seeing the same
# events (both receive them here, mirroring Godot's unhandled-input
# propagation).
# - a genuine click (press + release within CLICK_MAX_DRAG_PX, small natural
#   jitter allowed) picks at the release position: terrain top selects the
#   tile, a miss clears the focus, a cliff leaves it unchanged;
# - pointer movement beyond the threshold cancels the candidate for the
#   ENTIRE interaction: orbit and pan drags never select, clear, or change
#   the focus — regardless of where they start or end (terrain, sky,
#   outside the map, outside the viewport) — while the camera still moves.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
extends SceneTree

const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"
const JITTER_PX := 3.0
const DRAG_PX := 60.0

var _total := 0
var _any_fail := false
var _world = null
var _ui = null
var _camera: Camera3D = null

# Screen positions scanned once in the strategic preset.
var _tile_pos_a := Vector2.ZERO
var _tile_a := Vector2i.ZERO
var _tile_pos_b := Vector2.ZERO
var _tile_b := Vector2i.ZERO
var _cliff_pos := Vector2.ZERO
var _miss_pos := Vector2.ZERO
var _off_viewport := Vector2(-200.0, -200.0)


func _init() -> void:
	_run()


func _run() -> void:
	if not _require_native_extension():
		_finish()
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_world = TerrainWorldScript.new()
	_world.name = "TerrainWorld"
	root.add_child(_world)
	var ok: bool = _world.build(world_map, Ts08HeightSolver.BACKEND_NATIVE)
	_check(ok, "terrain world builds")
	if not ok:
		_finish()
		return
	_ui = WorldAnchorUiScript.new()
	root.add_child(_ui)
	_ui.attach(_world)
	_camera = _world.camera
	await physics_frame
	await physics_frame

	_check(_scan_screen_positions(), "scan found two tiles, a cliff, and a miss position")
	print(
		"scan: tile %s @ %s, tile %s @ %s, cliff @ %s, miss @ %s"
		% [_tile_a, _tile_pos_a, _tile_b, _tile_pos_b, _cliff_pos, _miss_pos]
	)

	# 1. A genuine click on a valid terrain top selects its tile.
	_press(_tile_pos_a)
	_release(_tile_pos_a)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "genuine click selects its tile")

	# 2. Small natural pointer jitter still counts as a click.
	_press(_tile_pos_b)
	_move_line(_tile_pos_b, _tile_pos_b + Vector2(JITTER_PX, -1.0), 2)
	_release(_tile_pos_b + Vector2(JITTER_PX, -1.0))
	await _settle()
	_check(_ui.focused_tile == _tile_b, "click with small pointer jitter still selects")

	# 3. An orbit drag selects neither its starting tile nor its ending tile.
	_click(_miss_pos)
	await _settle()
	_check(_ui.focused_tile == null, "focus cleared for the drag-from-nothing case")
	_orbit_drag(_tile_pos_a, _tile_pos_b)
	await _settle()
	_check(
		_ui.focused_tile == null,
		"orbit drag from tile to tile selects neither start nor end tile"
	)
	_camera.preset_strategic()

	# 4. An orbit drag preserves an existing selection.
	_click(_tile_pos_a)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "selection restored for the drag cases")
	_orbit_drag(_tile_pos_b, _tile_pos_b + Vector2(DRAG_PX, DRAG_PX))
	await _settle()
	_check(_ui.focused_tile == _tile_a, "orbit drag preserves the existing selection")
	_camera.preset_strategic()

	# 5. An orbit drag released over the sky preserves the selection.
	_orbit_drag(_tile_pos_b, _miss_pos)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "orbit drag released over the sky preserves the selection")
	_camera.preset_strategic()

	# 6. An orbit drag ending outside the map/viewport preserves the selection.
	_orbit_drag(_tile_pos_a, _off_viewport)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "orbit drag ending outside the viewport preserves the selection")
	_camera.preset_strategic()

	# 7. A pan gesture (Shift+LMB and MMB) never selects, clears, or changes focus.
	var target_before: Vector3 = _camera.target
	_press(_tile_pos_b, true)
	_move_line(_tile_pos_b, _tile_pos_b + Vector2(DRAG_PX, 0.0), 6, true)
	_release(_tile_pos_b + Vector2(DRAG_PX, 0.0), true)
	await _settle()
	_check(_camera.target != target_before, "pan gesture moved the camera target")
	_check(_ui.focused_tile == _tile_a, "Shift+LMB pan never changes the focus")
	_camera.preset_strategic()
	_mmb(_tile_pos_b, true)
	_move_line(_tile_pos_b, _miss_pos, 6, false, true)
	_mmb(_miss_pos, false)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "MMB pan never changes the focus")
	_camera.preset_strategic()

	# 8. A pan gesture ending outside the map preserves the selection.
	_press(_tile_pos_a, true)
	_move_line(_tile_pos_a, _off_viewport, 6, true)
	_release(_off_viewport, true)
	await _settle()
	_check(_ui.focused_tile == _tile_a, "pan ending outside the map preserves the selection")
	_camera.preset_strategic()

	# 9. A genuine click outside the map still clears focus.
	_click(_miss_pos)
	await _settle()
	_check(_ui.focused_tile == null, "genuine click outside the map clears the focus")

	# 10. Ambiguous cliff-wall behavior unchanged: a genuine cliff click
	# resolves the edge + both tiles and leaves the focus untouched.
	_click(_tile_pos_a)
	await _settle()
	_click(_cliff_pos)
	await _settle()
	_check(
		_world.last_pick.get("kind", "") == "cliff"
		and _world.last_pick.has("tile_a") and _world.last_pick.has("tile_b"),
		"cliff click still resolves the edge plus both adjacent tiles"
	)
	_check(_ui.focused_tile == _tile_a, "cliff click leaves the focus unchanged")

	# Camera movement itself stayed functional under the new classification.
	var yaw_before: float = _camera.yaw_deg
	_orbit_drag(_tile_pos_a, _tile_pos_a + Vector2(DRAG_PX, 0.0))
	_check(_camera.yaw_deg != yaw_before, "orbit drag still orbits the camera")

	_finish()


# --- gesture helpers (events delivered to both the world and the camera,
# mirroring Godot's unhandled-input propagation) ---


func _deliver(event: InputEvent) -> void:
	_world._unhandled_input(event)
	_camera._unhandled_input(event)


func _press(pos: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.shift_pressed = shift
	e.position = pos
	_deliver(e)


func _release(pos: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.shift_pressed = shift
	e.position = pos
	_deliver(e)


func _mmb(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	e.pressed = pressed
	e.position = pos
	_deliver(e)


func _move_line(from: Vector2, to: Vector2, steps: int, shift := false, mmb := false) -> void:
	for i in range(1, steps + 1):
		var pos := from.lerp(to, float(i) / float(steps))
		var e := InputEventMouseMotion.new()
		e.position = pos
		e.relative = (to - from) / float(steps)
		e.shift_pressed = shift
		if mmb:
			e.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		else:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		_deliver(e)


func _click(pos: Vector2) -> void:
	_press(pos)
	_release(pos)


func _orbit_drag(from: Vector2, to: Vector2) -> void:
	_press(from)
	_move_line(from, to, 6)
	_release(to)


func _settle() -> void:
	await physics_frame
	await physics_frame


# Scans the strategic view (side-effect-free resolver) for two distinct tile
# positions, one cliff position, and one miss position.
func _scan_screen_positions() -> bool:
	var size: Vector2 = root.get_visible_rect().size
	var tiles_found := 0
	var cliff_found := false
	var miss_found := false
	var y := 4.0
	while y < size.y:
		var x := 4.0
		while x < size.x:
			var pos := Vector2(x, y)
			var pick: Dictionary = _world._resolve_screen_pick(pos)
			if pick.is_empty():
				if not miss_found:
					_miss_pos = pos
					miss_found = true
			elif pick["kind"] == "tile":
				if tiles_found == 0:
					_tile_pos_a = pos
					_tile_a = pick["tile"]
					tiles_found = 1
				elif (
					tiles_found == 1
					and pick["tile"] != _tile_a
					and pos.distance_to(_tile_pos_a) > 40.0
					and _same_tile_around(pos, pick["tile"])
				):
					_tile_pos_b = pos
					_tile_b = pick["tile"]
					tiles_found = 2
			elif pick["kind"] == "cliff" and not cliff_found:
				_cliff_pos = pos
				cliff_found = true
			if tiles_found == 2 and cliff_found and miss_found:
				return true
			x += 4.0
		y += 4.0
	return false


# The jitter click releases a few pixels away from the press, so the tile-B
# position must resolve to the same tile across the whole jitter radius.
func _same_tile_around(pos: Vector2, tile: Vector2i) -> bool:
	for offset in [
		Vector2(JITTER_PX, -1.0),
		Vector2(-JITTER_PX, 1.0),
		Vector2(1.0, JITTER_PX),
		Vector2(-1.0, -JITTER_PX),
	]:
		var pick: Dictionary = _world._resolve_screen_pick(pos + offset)
		if pick.get("kind", "") != "tile" or pick["tile"] != tile:
			return false
	return true


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(false, "native GDExtension descriptor present (build it first)")
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			_check(false, "native GDExtension loads")
			return false
	if not ClassDB.can_instantiate(&"EomTerrainNative"):
		_check(false, "EomTerrainNative instantiable")
		return false
	return true


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainWorld input-gesture tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
