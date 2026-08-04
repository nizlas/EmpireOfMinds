# N4 projected screen-space UI (presentation/integration-side, reusable).
#
# Shows a small provisional marker + tile label at the projected N4 world
# anchor of the focused tile. Attach to a built TerrainWorld: consumes its
# `terrain_picked` presentation output and its `tile_anchors` derived data;
# re-projects through the world's camera EVERY FRAME, so the marker tracks
# camera orbit, pitch, pan, zoom, and viewport resizing without any
# input-event coupling.
#
# Focus rules (locked N4 selection contract):
# - a resolved TILE pick focuses that tile;
# - a MISS (empty pick) clears the focus;
# - a CLIFF pick leaves the focus UNCHANGED: a cliff identifies the
#   authoritative edge plus BOTH adjacent tiles (N3c.5 picker contract,
#   docs/MAP_MODEL.md) and must never silently select either neighboring
#   tile.
#
# Authority boundary (permanent N4 rule): `focused_tile` is presentation
# focus state only — no gameplay selection, no actions, no domain writes.
# Gameplay state and legality always come from WorldMap through the
# client-server action path, never from this component. Marker/label style
# is provisional dev-visible UI, not production art.
extends CanvasLayer

const MARKER_SIZE := Vector2(10.0, 10.0)
const MARKER_COLOR := Color(1.0, 0.85, 0.25, 0.95)
const LABEL_OFFSET := Vector2(0.0, -30.0)
const LABEL_FONT_COLOR := Color(1.0, 1.0, 1.0)
const LABEL_PANEL_COLOR := Color(0.08, 0.10, 0.14, 0.78)

# Presentation focus state only (Variant: null or Vector2i tile id).
var focused_tile = null

var _world = null
var _overlay: Control = null
var _marker_root: Control = null
var _marker: ColorRect = null
var _label: Label = null


func _init() -> void:
	layer = 10
	_overlay = Control.new()
	_overlay.name = "AnchorOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_marker_root = Control.new()
	_marker_root.name = "TileMarker"
	_marker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_root.visible = false
	_overlay.add_child(_marker_root)

	_marker = ColorRect.new()
	_marker.name = "MarkerDiamond"
	_marker.color = MARKER_COLOR
	_marker.size = MARKER_SIZE
	_marker.position = -MARKER_SIZE / 2.0
	_marker.pivot_offset = MARKER_SIZE / 2.0
	_marker.rotation = PI / 4.0
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_root.add_child(_marker)

	_label = Label.new()
	_label.name = "TileLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", LABEL_FONT_COLOR)
	var panel := StyleBoxFlat.new()
	panel.bg_color = LABEL_PANEL_COLOR
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_left = 4
	panel.corner_radius_bottom_right = 4
	panel.content_margin_left = 8.0
	panel.content_margin_right = 8.0
	panel.content_margin_top = 3.0
	panel.content_margin_bottom = 3.0
	_label.add_theme_stylebox_override("normal", panel)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_root.add_child(_label)


# Attaches to a built TerrainWorld (needs `camera`, `tile_anchors`, and the
# `terrain_picked` signal). Read-only over the world.
func attach(world) -> void:
	_world = world
	world.terrain_picked.connect(_on_terrain_picked)
	refresh()


# Focuses one tile by canonical id. Returns false (no change) when the tile
# has no anchor (unknown tile).
func focus_tile(tile: Vector2i) -> bool:
	if _world == null or not _world.tile_anchors.has(tile):
		return false
	focused_tile = tile
	_label.text = "Tile (%d, %d)" % [tile.x, tile.y]
	refresh()
	return true


func clear_focus() -> void:
	focused_tile = null
	refresh()


# Projects one world anchor through a camera into screen space.
# {"visible": bool, "screen": Vector2} — not visible behind the camera.
static func project_anchor(camera: Camera3D, anchor: Vector3) -> Dictionary:
	if camera == null or camera.is_position_behind(anchor):
		return {"visible": false, "screen": Vector2.ZERO}
	return {"visible": true, "screen": camera.unproject_position(anchor)}


# Re-projects the focused anchor into the current camera/viewport state.
# Called every frame (and directly by focus changes and tests).
func refresh() -> void:
	if focused_tile == null or _world == null or _world.camera == null:
		_marker_root.visible = false
		return
	var projected := project_anchor(_world.camera, _world.tile_anchors[focused_tile])
	if not projected["visible"]:
		_marker_root.visible = false
		return
	_marker_root.position = projected["screen"]
	_label.position = LABEL_OFFSET - Vector2(_label.size.x / 2.0, 0.0)
	_marker_root.visible = true


func _process(_delta: float) -> void:
	refresh()


func _on_terrain_picked(pick: Dictionary) -> void:
	if pick.is_empty():
		clear_focus()
		return
	match pick.get("kind", ""):
		"tile":
			focus_tile(pick["tile"])
		"cliff":
			# Locked: a cliff identifies an edge + both adjacent tiles and
			# never silently selects either neighboring tile — the current
			# tile focus stays unchanged.
			pass
