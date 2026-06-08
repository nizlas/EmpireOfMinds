# Experimental SubViewport-based 3D warrior markers on the map plane (presentation only).
class_name Warrior3DUnitMarkersView
extends Node2D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
## Internal render resolution floor; matched to blit rect (1:1 px) when drawing.
const VIEWPORT_PX_MIN: int = 128
const VIEWPORT_PX_MAX: int = 768
const VIEWPORT_SIZE_QUANTIZE: int = 32

## GLB bind pose faces -Z at yaw 0 (toward SubViewport camera on +Z). Positive yaw turns screen-right
## (~48° matches unit_settler_marker three-quarter; not straight-on, not back-facing).
@export var model_yaw_degrees: float = 48.0
@export var model_yaw_base_offset: float = 0.0
@export var model_pitch_degrees: float = 0.0
## Lifts bind-pose feet above the ground plane so rotated soles stay visible.
@export var model_offset_y: float = 0.18
@export var model_scale: float = 1.0
## Oblique map-style read: elevated, camera left of subject, mild downward look (not a separate unit camera).
@export var camera_offset_x: float = -0.58
@export var camera_height: float = 2.15
@export var camera_distance: float = 1.55
## Aim above the figure so feet (y=0) land near the bottom of the SubViewport image.
@export var camera_look_y: float = 1.02
@export var camera_ortho_size: float = 1.85
## Extra transparent rows below the feet so soles/shadow are not clipped by the SubViewport edge.
@export var viewport_bottom_pad_ratio: float = 0.24

@export_group("Map animation")
@export var play_map_animation: bool = true
## Desired *visual* clip. Remapped to GLB key when **`use_glb_animation_name_remap`** is on.
@export var map_animation_name: String = "Idle_3"
@export var use_glb_animation_name_remap: bool = true

@export_group("Animation audit (temporary)")
@export var animation_audit_mode: bool = false
@export var animation_audit_cycle_seconds: float = 3.0

var play_idle_animation: bool:
	get:
		return play_map_animation
	set(value):
		play_map_animation = value

var scenario
var layout
var camera
var units_view

var _warrior_scene: PackedScene
var _slot_by_unit_id: Dictionary = {}
var _blit_via_terrain_foreground: bool = false
var _sync_markers_frame: int = -1
var _logged_map_animation: bool = false
var _runtime_anim_signature: String = ""
var _audit_catalog_logged: bool = false
var _audit_clip_names: PackedStringArray = PackedStringArray()
var _audit_clip_index: int = 0
var _audit_cycle_timer: float = 0.0
var _audit_started: bool = false


func _ready() -> void:
	_load_warrior_scene()
	visible = Warrior3DExperimentScript.is_enabled() and _warrior_scene != null
	if visible:
		_log_map_animation_selection()
	if _is_animation_audit_active():
		_prime_animation_audit_catalog_from_scene()


func _is_animation_audit_active() -> bool:
	return animation_audit_mode or Warrior3DExperimentScript.is_animation_audit_enabled()


func _resolved_map_animation_name() -> String:
	var from_export: String = map_animation_name.strip_edges()
	if not from_export.is_empty():
		return from_export
	return Warrior3DExperimentScript.map_animation_name()


func _playback_animation_name() -> String:
	var visual: String = _resolved_map_animation_name()
	if _is_animation_audit_active() and not _audit_clip_names.is_empty():
		visual = _audit_clip_names[_audit_clip_index]
	if _is_animation_audit_active():
		return visual
	return Warrior3DAnimationRemapScript.glb_clip_for_visual(
		visual,
		use_glb_animation_name_remap,
	)


func _prime_animation_audit_catalog_from_scene() -> void:
	if _warrior_scene == null or _audit_catalog_logged or not is_inside_tree():
		return
	var probe: Node = _warrior_scene.instantiate()
	add_child(probe)
	var player: AnimationPlayer = _find_animation_player(probe)
	if player != null:
		_log_animation_audit_catalog(player)
	remove_child(probe)
	probe.free()


func _log_animation_audit_catalog(player: AnimationPlayer) -> void:
	if _audit_catalog_logged:
		return
	_audit_catalog_logged = true
	_audit_clip_names = player.get_animation_list()
	print("[Warrior3D animation audit] AnimationPlayer path: %s" % player.get_path())
	print("[Warrior3D animation audit] get_animation_list(): %s" % str(_audit_clip_names))


func _tick_animation_audit(delta: float) -> void:
	if _audit_clip_names.is_empty():
		return
	if not _audit_started:
		_audit_started = true
		_audit_cycle_timer = 0.0
		_audit_clip_index = 0
		_apply_audit_clip_to_all_slots(_audit_clip_names[_audit_clip_index])
		return
	_audit_cycle_timer += delta
	if _audit_cycle_timer < maxf(animation_audit_cycle_seconds, 0.25):
		return
	_audit_cycle_timer = 0.0
	_audit_clip_index = (_audit_clip_index + 1) % _audit_clip_names.size()
	_apply_audit_clip_to_all_slots(_audit_clip_names[_audit_clip_index])


func _apply_audit_clip_to_all_slots(anim_name: String) -> void:
	print("[Warrior3D animation audit] playing: %s" % anim_name)
	for unit_id in _slot_by_unit_id:
		var slot: Node2D = _slot_by_unit_id[unit_id] as Node2D
		if slot != null:
			_ensure_slot_animation(slot, anim_name)


func _log_map_animation_selection() -> void:
	if _logged_map_animation:
		return
	_logged_map_animation = true
	var visual: String = _resolved_map_animation_name()
	var glb_clip: String = _playback_animation_name()
	print(
		"Warrior3DUnitMarkersView: play_map_animation=%s visual='%s' glb_clip='%s' remap=%s audit=%s"
		% [
			str(play_map_animation),
			visual,
			glb_clip,
			str(use_glb_animation_name_remap and not _is_animation_audit_active()),
			str(_is_animation_audit_active()),
		]
	)


func _load_warrior_scene() -> void:
	if _warrior_scene != null:
		return
	if not Warrior3DExperimentScript.is_enabled():
		return
	var scene_path: String = Warrior3DExperimentScript.warrior_scene_path()
	_warrior_scene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if _warrior_scene == null:
		push_warning("Warrior3DUnitMarkersView: failed to load %s" % scene_path)


func _process(delta: float) -> void:
	if not Warrior3DExperimentScript.is_enabled():
		return
	if _is_animation_audit_active():
		_tick_animation_audit(delta)


func set_blit_via_terrain_foreground(enabled: bool) -> void:
	_blit_via_terrain_foreground = enabled


func draw_unit_marker_at(
	canvas: CanvasItem,
	anchor_pres: Vector2,
	pscale: float,
	type_id: String,
	_owner_id: int,
	unit_id: int,
) -> void:
	if not Warrior3DExperimentScript.should_render_warrior_as_3d(type_id):
		return
	_sync_markers_once_per_frame()
	var rect: Rect2 = _marker_display_rect(anchor_pres, pscale, type_id)
	if rect.size.x <= 0.0:
		return
	var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
	if slot == null:
		return
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	_apply_viewport_size_for_blit(slot, viewport, rect)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var tex: Texture2D = viewport.get_texture()
	if tex == null:
		return
	var prev_filter: CanvasItem.TextureFilter = canvas.texture_filter
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
	canvas.texture_filter = prev_filter
	UnitsViewScript.debug_last_unit_png_rect = rect
	UnitsViewScript.debug_last_unit_png_bottom_center = (
		UnitsViewScript.unit_png_bottom_center_from_rect(rect)
	)
	if units_view != null:
		var eff: Vector2 = units_view.unit_effective_depth_presentation(
			anchor_pres, pscale, type_id
		)
		UnitsViewScript.debug_last_unit_effective_depth_point = (
			eff if eff != Vector2.ZERO else anchor_pres
		)
	else:
		UnitsViewScript.debug_last_unit_effective_depth_point = anchor_pres


func prepare_markers_for_draw() -> void:
	_sync_markers_once_per_frame()


func _sync_markers_once_per_frame() -> void:
	var frame: int = Engine.get_frames_drawn()
	if _sync_markers_frame == frame:
		return
	_sync_markers_frame = frame
	_sync_markers()


func _anim_runtime_signature() -> String:
	return "%s|%s|%s|%s" % [
		str(play_map_animation),
		_resolved_map_animation_name(),
		str(_is_animation_audit_active()),
		str(use_glb_animation_name_remap),
	]


func _discard_slots_if_animation_config_changed() -> void:
	var sig: String = _anim_runtime_signature()
	if sig == _runtime_anim_signature:
		return
	_runtime_anim_signature = sig
	for unit_id in _slot_by_unit_id.keys():
		var stale_slot: Node = _slot_by_unit_id[unit_id] as Node
		if stale_slot != null:
			stale_slot.queue_free()
	_slot_by_unit_id.clear()


func _sync_markers() -> void:
	if scenario == null or layout == null:
		return
	_discard_slots_if_animation_config_changed()
	_load_warrior_scene()
	if _warrior_scene == null:
		return
	if camera == null:
		camera = MapCameraScript.new()
	var active_ids: Dictionary = {}
	var clip_name: String = _playback_animation_name()
	var units: Array = scenario.units()
	var i: int = 0
	while i < units.size():
		var unit = units[i]
		if str(unit.type_id) != "warrior":
			i += 1
			continue
		var unit_id: int = int(unit.id)
		active_ids[unit_id] = true
		var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
		if slot == null:
			slot = _create_slot()
			add_child(slot)
			_slot_by_unit_id[unit_id] = slot
			_ensure_slot_animation(slot, clip_name)
		elif str(slot.get_meta(&"eom_slot_anim", "")) != clip_name:
			_ensure_slot_animation(slot, clip_name)
		slot.position = Vector2.ZERO
		if not _blit_via_terrain_foreground:
			var world_center: Vector2 = layout.hex_to_world(unit.position.q, unit.position.r)
			var anchor_pres: Vector2 = camera.to_presentation(world_center)
			var pscale: float = camera.perspective_scale_at(world_center)
			slot.position = _marker_display_rect(anchor_pres, pscale, "warrior").position
		i += 1
	var stale_ids: Array = _slot_by_unit_id.keys()
	var si: int = 0
	while si < stale_ids.size():
		var stale_id: int = int(stale_ids[si])
		if not active_ids.has(stale_id):
			var stale_slot: Node = _slot_by_unit_id[stale_id] as Node
			if stale_slot != null:
				stale_slot.queue_free()
			_slot_by_unit_id.erase(stale_id)
		si += 1


func _create_slot() -> Node2D:
	var root := Node2D.new()
	var viewport := SubViewport.new()
	var vp_size: Vector2i = _default_viewport_pixel_size()
	viewport.size = vp_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = camera_ortho_size
	cam.position = Vector3(camera_offset_x, camera_height, camera_distance)
	viewport.add_child(cam)
	cam.look_at_from_position(
		cam.position, Vector3(0.0, camera_look_y, 0.0), Vector3.UP
	)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	key_light.light_energy = 1.1
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(18.0, -128.0, 0.0)
	fill_light.light_energy = 0.35
	viewport.add_child(fill_light)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	if _warrior_scene != null:
		var model: Node = _warrior_scene.instantiate()
		model_root.add_child(model)
	model_root.rotation_degrees = Vector3(
		model_pitch_degrees,
		model_yaw_base_offset + model_yaw_degrees,
		0.0,
	)
	model_root.position = Vector3(0.0, model_offset_y, 0.0)
	model_root.scale = Vector3.ONE * model_scale
	viewport.add_child(model_root)
	root.add_child(viewport)
	root.set_meta("viewport", viewport)
	return root


func _marker_display_rect(anchor_pres: Vector2, pscale: float, type_id: String) -> Rect2:
	var marker_rect: Rect2 = _marker_rect_for_type(anchor_pres, pscale, type_id, units_view)
	if marker_rect.size.x <= 0.0 or marker_rect.size.y <= 0.0:
		return Rect2()
	var display_size := Vector2(
		marker_rect.size.x,
		marker_rect.size.y * (1.0 + viewport_bottom_pad_ratio),
	)
	return Rect2(marker_rect.position, display_size)


func _default_viewport_pixel_size() -> Vector2i:
	return _quantized_viewport_size(Vector2(float(VIEWPORT_PX_MIN), float(VIEWPORT_PX_MIN)))


func _quantized_viewport_size(display_size: Vector2) -> Vector2i:
	var q: int = maxi(VIEWPORT_SIZE_QUANTIZE, 1)
	var w: int = clampi(int(ceil(display_size.x)), VIEWPORT_PX_MIN, VIEWPORT_PX_MAX)
	var h: int = clampi(int(ceil(display_size.y)), VIEWPORT_PX_MIN, VIEWPORT_PX_MAX)
	w = int(ceil(float(w) / float(q))) * q
	h = int(ceil(float(h) / float(q))) * q
	return Vector2i(w, h)


func _apply_viewport_size_for_blit(slot: Node2D, viewport: SubViewport, rect: Rect2) -> void:
	var target: Vector2i = _quantized_viewport_size(rect.size)
	var prev: Vector2i = slot.get_meta(&"eom_vp_size", Vector2i.ZERO)
	if prev == target:
		return
	viewport.size = target
	slot.set_meta(&"eom_vp_size", target)


func _viewport_for_slot(slot: Node2D) -> SubViewport:
	if slot.has_meta("viewport"):
		return slot.get_meta("viewport") as SubViewport
	return slot.get_child(0) as SubViewport


static func _marker_rect_for_type(
	anchor_pres: Vector2, pscale: float, type_id: String, p_units_view
) -> Rect2:
	var height_ratio: float = 0.70
	if p_units_view != null:
		height_ratio = p_units_view.unit_icon_height_ratio
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var side: float = hex_h * height_ratio * pscale
	if p_units_view != null:
		var rect: Rect2 = p_units_view.unit_marker_texture_rect_presentation(
			anchor_pres, pscale, type_id
		)
		if rect.size.x > 0.0:
			return rect
	return Rect2(anchor_pres.x - side * 0.5, anchor_pres.y - side * 0.9, side, side)


func _ensure_slot_animation(slot: Node2D, clip_name: String) -> void:
	if not play_map_animation:
		return
	if str(slot.get_meta(&"eom_slot_anim", "")) == clip_name:
		return
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	var model_root: Node = viewport.find_child("ModelRoot", true, false)
	if model_root == null:
		return
	var ci: int = 0
	while ci < model_root.get_child_count():
		_play_clip_on_model(model_root.get_child(ci), clip_name)
		ci += 1
	slot.set_meta(&"eom_slot_anim", clip_name)


func _play_clip_on_model(model: Node, clip_name: String) -> void:
	if not model.is_inside_tree():
		return
	var player: AnimationPlayer = _find_animation_player(model)
	if player == null:
		return
	if not player.has_animation(clip_name):
		push_warning(
			"Warrior3DUnitMarkersView: clip '%s' not found on %s"
			% [clip_name, Warrior3DExperimentScript.warrior_scene_path()]
		)
		return
	if player.is_playing() and player.assigned_animation == clip_name:
		return
	var anim: Animation = player.get_animation(clip_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	player.play(clip_name)


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	var children: Array = node.get_children()
	var i: int = 0
	while i < children.size():
		var found: AnimationPlayer = _find_animation_player(children[i] as Node)
		if found != null:
			return found
		i += 1
	return null
