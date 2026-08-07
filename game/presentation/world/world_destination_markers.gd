# N7d/N7g.3 projected selection/destination/attack markers (presentation-
# only, reusable).
#
# Shows the selected own unit's tile, one destination marker per SERVED
# `move_unit` row, and one VISUALLY DISTINCT attack marker per served
# `attack_unit` row (red unrotated square vs. the green destination
# diamond) at the projected N4 tile anchors. Follows the N4 projected
# UI pattern (world_anchor_ui.gd): attach to a built TerrainWorld, read its
# `camera` and `tile_anchors` (derived presentation data — never gameplay
# authority), and re-project EVERY FRAME so markers track camera orbit,
# pitch, pan, zoom, and viewport resizing.
#
# Contract:
# - The marker sets are exactly what the caller passes from the served
#   legal-actions rows — this component never computes, filters, or invents
#   destinations or attack targets (no client-side legality, ever).
# - All controls are MOUSE_FILTER_IGNORE: TerrainWorld stays the single
#   pick-input boundary (locked N4 input contract) — "clicking a marker" is
#   a terrain pick on the marked tile, not a Control click.
# - Presentation state only: no selection ownership, no actions, no domain
#   writes. Marker style is provisional dev-visible UI, not production art.
extends CanvasLayer

const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")

const DESTINATION_MARKER_SIZE := Vector2(14.0, 14.0)
const DESTINATION_COLOR := Color(0.35, 0.95, 0.45, 0.92)
const SELECTED_MARKER_SIZE := Vector2(20.0, 20.0)
const SELECTED_COLOR := Color(0.30, 0.85, 1.0, 0.95)
# N7g.3 attack markers: distinct color AND shape (red unrotated square).
const ATTACK_MARKER_SIZE := Vector2(16.0, 16.0)
const ATTACK_COLOR := Color(0.98, 0.25, 0.20, 0.95)

# Current marker inputs (read-only mirrors for tests/diagnostics).
var selected_tile = null  # Variant: null or Vector2i
var destination_tiles: Array = []  # Array of Vector2i
var attack_tiles: Array = []  # Array of Vector2i (served attack rows)

var _world = null
var _overlay: Control = null
var _selected_marker: Control = null
var _destination_markers: Array = []  # Array of Control, 1:1 with destination_tiles
var _attack_markers: Array = []  # Array of Control, 1:1 with attack_tiles


func _init() -> void:
	layer = 11
	_overlay = Control.new()
	_overlay.name = "DestinationOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_selected_marker = _make_diamond("SelectedUnitMarker", SELECTED_MARKER_SIZE, SELECTED_COLOR)
	_overlay.add_child(_selected_marker)


# Attaches to a built TerrainWorld (needs `camera` and `tile_anchors`).
# Read-only over the world.
func attach(world) -> void:
	_world = world
	refresh()


# Replaces the marker sets: `p_selected_tile` (Variant: null or Vector2i),
# `p_destination_tiles` and `p_attack_tiles` (Vector2i lists taken 1:1 from
# the served move/attack rows).
func set_markers(p_selected_tile, p_destination_tiles: Array, p_attack_tiles: Array = []) -> void:
	selected_tile = p_selected_tile
	destination_tiles = p_destination_tiles.duplicate()
	attack_tiles = p_attack_tiles.duplicate()
	for marker in _destination_markers:
		(marker as Node).queue_free()
	_destination_markers = []
	for tile_variant in destination_tiles:
		var tile: Vector2i = tile_variant
		var marker := _make_diamond(
			"Destination_%d_%d" % [tile.x, tile.y], DESTINATION_MARKER_SIZE, DESTINATION_COLOR
		)
		_overlay.add_child(marker)
		_destination_markers.append(marker)
	for marker in _attack_markers:
		(marker as Node).queue_free()
	_attack_markers = []
	for tile_variant in attack_tiles:
		var tile: Vector2i = tile_variant
		var marker := _make_square(
			"Attack_%d_%d" % [tile.x, tile.y], ATTACK_MARKER_SIZE, ATTACK_COLOR
		)
		_overlay.add_child(marker)
		_attack_markers.append(marker)
	refresh()


func clear() -> void:
	set_markers(null, [], [])


func destination_count() -> int:
	return _destination_markers.size()


func attack_count() -> int:
	return _attack_markers.size()


func destination_marker_for_tile(tile: Vector2i) -> Control:
	return _overlay.get_node_or_null("Destination_%d_%d" % [tile.x, tile.y]) as Control


func attack_marker_for_tile(tile: Vector2i) -> Control:
	return _overlay.get_node_or_null("Attack_%d_%d" % [tile.x, tile.y]) as Control


func selected_marker() -> Control:
	return _selected_marker


# Re-projects every marker into the current camera/viewport state. Called
# every frame (and directly by set_markers and tests).
func refresh() -> void:
	var camera: Camera3D = _world.camera if _world != null else null
	var anchors: Dictionary = _world.tile_anchors if _world != null else {}
	_place_marker(_selected_marker, selected_tile, camera, anchors)
	for i in _destination_markers.size():
		_place_marker(_destination_markers[i], destination_tiles[i], camera, anchors)
	for i in _attack_markers.size():
		_place_marker(_attack_markers[i], attack_tiles[i], camera, anchors)


func _process(_delta: float) -> void:
	refresh()


func _place_marker(marker: Control, tile_variant, camera: Camera3D, anchors: Dictionary) -> void:
	if marker == null:
		return
	if tile_variant == null or camera == null or not anchors.has(tile_variant):
		marker.visible = false
		return
	var projected: Dictionary = WorldAnchorUiScript.project_anchor(camera, anchors[tile_variant])
	if not projected["visible"]:
		marker.visible = false
		return
	marker.position = projected["screen"]
	marker.visible = true


func _make_diamond(marker_name: String, marker_size: Vector2, color: Color) -> Control:
	var marker_root := Control.new()
	marker_root.name = marker_name
	marker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_root.visible = false
	var diamond := ColorRect.new()
	diamond.name = "Diamond"
	diamond.color = color
	diamond.size = marker_size
	diamond.position = -marker_size / 2.0
	diamond.pivot_offset = marker_size / 2.0
	diamond.rotation = PI / 4.0
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_root.add_child(diamond)
	return marker_root


# Attack-marker shape: an UNROTATED square, so attack targets differ from
# move destinations in both shape and color.
func _make_square(marker_name: String, marker_size: Vector2, color: Color) -> Control:
	var marker_root := Control.new()
	marker_root.name = marker_name
	marker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_root.visible = false
	var square := ColorRect.new()
	square.name = "Square"
	square.color = color
	square.size = marker_size
	square.position = -marker_size / 2.0
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_root.add_child(square)
	return marker_root
