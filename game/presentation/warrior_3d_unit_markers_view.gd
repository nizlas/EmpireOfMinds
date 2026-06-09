# Experimental SubViewport-based 3D unit markers (warrior + settler) on the map plane (presentation only).
class_name Warrior3DUnitMarkersView
extends Node2D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const Warrior3DWalkSyncScript = preload("res://presentation/warrior_3d_walk_sync.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")
## Internal render resolution floor; matched to blit rect (1:1 px) when drawing.
const VIEWPORT_PX_MIN: int = 128
const VIEWPORT_PX_MAX: int = 768
const VIEWPORT_SIZE_QUANTIZE: int = 32
const HEX_MOVE_WALK_ANIM_SPEED: float = 0.5
const SEMANTIC_IDLE_CLIP: String = "Idle_3"
const SEMANTIC_WALK_CLIP: String = "Walking"
## Idle contact pose already matches walk start; more blend causes leg twitch.
const WALK_START_BLEND_MAX_SEC: float = 0.05

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
## Extra SubViewport margin while walking screen-down (walk stride extends the leading foot).
@export var viewport_travel_forward_pad_ratio: float = 0.28
## Depth-merge lead along on-screen travel while hex-moving down (keeps the front foot above map art).
@export var depth_sort_forward_lead_ratio: float = 0.28
@export_group("Hex walk sync")
## Fraction of one **Idle_02** loop per hex step; position lerp follows this much of the clip timeline.
@export_range(0.2, 2.0) var hex_stride_cycle_fraction: float = 1.15

@export_group("Travel facing")
## SubViewport yaw offset paired with **map_bearing** (projected on-screen travel angle).
@export var travel_facing_yaw_offset_deg: float = 69.0

@export_group("Map animation")
@export var play_map_animation: bool = true
## Desired *visual* clip. Remapped to GLB key when **`use_glb_animation_name_remap`** is on.
@export var map_animation_name: String = "Idle_3"
@export var use_glb_animation_name_remap: bool = true
## Hex-move start: **0** = snap Idle→Walking (recommended). Max **0.05** if a hint of blend is needed.
@export_range(0.0, 0.05, 0.01) var walk_start_blend_sec: float = 0.0
## Hex-move end: eased Walking→Idle_3 crossfade (GLB **Combat_Stance** via remap).
@export_range(0.20, 0.35, 0.01) var idle_end_blend_sec: float = 0.28

@export_group("Settler framing (experimental)")
## Counter Hips bone translation in **Walking** so the GLB plays in-place inside the SubViewport.
@export var settler_neutralize_root_motion: bool = true

@export_group("Animation audit (temporary)")
@export var animation_audit_mode: bool = false
@export var animation_audit_cycle_seconds: float = 3.0

const ROOT_MOTION_ANCHOR_NAME: String = "RootMotionAnchor"
const HIPS_BONE_NAME: String = "Hips"

var play_idle_animation: bool:
	get:
		return play_map_animation
	set(value):
		play_map_animation = value

var scenario
var layout
var camera
var units_view
## Presentation redraw target while hex-move tweens run (typically **TerrainForegroundView**).
var terrain_foreground_view

var _scenes_by_type: Dictionary = {}
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
var _active_hex_moves: Dictionary = {}
var _facing_yaw_by_unit_id: Dictionary = {}


func _ready() -> void:
	Warrior3DExperimentScript.log_flag_state_once()
	_load_unit_scenes()
	visible = Warrior3DExperimentScript.is_enabled() and not _scenes_by_type.is_empty()
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
		"warrior",
	)


func _prime_animation_audit_catalog_from_scene() -> void:
	var probe_scene: PackedScene = _scene_for_type("warrior")
	if probe_scene == null:
		probe_scene = _scene_for_type("settler")
	if probe_scene == null or _audit_catalog_logged or not is_inside_tree():
		return
	var probe: Node = probe_scene.instantiate()
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


func _hex_move_duration_sec(type_id: String = "warrior") -> float:
	return Warrior3DWalkSyncScript.hex_move_duration_sec(
		HEX_MOVE_WALK_ANIM_SPEED,
		hex_stride_cycle_fraction,
		_resolved_walk_clip_length_sec(type_id),
	)


func _resolved_walk_clip_length_sec(type_id: String = "warrior") -> float:
	return Warrior3DWalkSyncScript.resolved_walk_clip_length_sec(type_id)


func _prime_walk_clip_length_from_slot(slot: Node2D) -> void:
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", "warrior"))
	var model_root: Node = viewport.find_child("ModelRoot", true, false)
	if model_root == null:
		return
	var ci: int = 0
	while ci < model_root.get_child_count():
		var player: AnimationPlayer = _find_animation_player(model_root.get_child(ci) as Node)
		if player != null:
			Warrior3DWalkSyncScript.cache_walk_clip_length_from_player(
				player,
				use_glb_animation_name_remap and not _is_animation_audit_active(),
				type_id,
			)
			return
		ci += 1


func _log_animation_player_catalog_once(
	slot: Node2D, type_id: String, player: AnimationPlayer
) -> void:
	if bool(slot.get_meta(&"eom_anim_catalog_logged", false)):
		return
	slot.set_meta(&"eom_anim_catalog_logged", true)
	var asset_path: String = Warrior3DExperimentScript.animated_scene_path_for_type(type_id)
	var idle_glb: String = _glb_clip_for_semantic(SEMANTIC_IDLE_CLIP, type_id)
	var walk_glb: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	print(
		(
			"[Unit3D anim catalog] type=%s asset=%s player_path=%s clips=%s "
			+ "idle_semantic='%s' idle_glb='%s' walk_semantic='%s' walk_glb='%s'"
		)
		% [
			type_id,
			asset_path,
			player.get_path(),
			str(player.get_animation_list()),
			SEMANTIC_IDLE_CLIP,
			idle_glb,
			SEMANTIC_WALK_CLIP,
			walk_glb,
		]
	)


func _load_warrior_scene() -> void:
	_load_unit_scenes()


func _load_unit_scenes() -> void:
	if not Warrior3DExperimentScript.is_enabled():
		return
	var ti: int = 0
	while ti < Warrior3DExperimentScript.SUPPORTED_3D_TYPE_IDS.size():
		var type_id: String = Warrior3DExperimentScript.SUPPORTED_3D_TYPE_IDS[ti]
		if not Warrior3DExperimentScript.should_render_unit_as_3d(type_id):
			ti += 1
			continue
		if _scenes_by_type.has(type_id):
			ti += 1
			continue
		var scene_path: String = Warrior3DExperimentScript.animated_scene_path_for_type(type_id)
		if scene_path.is_empty():
			ti += 1
			continue
		var scene: PackedScene = (
			ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		)
		if scene == null:
			push_warning("Warrior3DUnitMarkersView: failed to load %s" % scene_path)
		else:
			_scenes_by_type[type_id] = scene
		ti += 1


func _scene_for_type(type_id: String) -> PackedScene:
	return _scenes_by_type.get(str(type_id)) as PackedScene


func _type_id_for_unit(unit_id: int) -> String:
	var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
	if slot != null and slot.has_meta(&"eom_unit_type_id"):
		return str(slot.get_meta(&"eom_unit_type_id"))
	if _active_hex_moves.has(unit_id):
		var move_type: Variant = _active_hex_moves[unit_id].get("type_id", null)
		if move_type != null:
			return str(move_type)
	if scenario != null:
		var units: Array = scenario.units()
		var ui: int = 0
		while ui < units.size():
			var unit = units[ui]
			if int(unit.id) == unit_id:
				return str(unit.type_id)
			ui += 1
	return "warrior"


func _log_unit_animation_debug(
	type_id: String,
	asset_path: String,
	semantic: String,
	glb_clip: String,
	facing_yaw_deg: float,
) -> void:
	print(
		(
			"[Unit3D] type=%s asset=%s semantic='%s' glb_clip='%s' "
			+ "facing_yaw_deg=%.2f"
		)
		% [type_id, asset_path, semantic, glb_clip, facing_yaw_deg]
	)


func _process(delta: float) -> void:
	if not Warrior3DExperimentScript.is_enabled():
		return
	_advance_pending_animation_blends(delta)
	_ensure_idle_slots_autoplay()
	_refresh_all_settler_root_motion_cancels()
	if _is_animation_audit_active():
		_tick_animation_audit(delta)
	elif _tick_hex_moves(delta):
		_request_presentation_redraw()


func begin_hex_move(
	unit_id: int,
	type_id: String,
	from_q: int,
	from_r: int,
	to_q: int,
	to_r: int,
) -> void:
	if not Warrior3DExperimentScript.is_enabled():
		return
	if not Warrior3DExperimentScript.should_render_unit_as_3d(type_id):
		return
	if layout == null:
		return
	if camera == null:
		camera = MapCameraScript.new()
	var from_world: Vector2 = layout.hex_to_world(from_q, from_r)
	var to_world: Vector2 = layout.hex_to_world(to_q, to_r)
	var from_pres: Vector2 = camera.to_presentation(from_world)
	var to_pres: Vector2 = camera.to_presentation(to_world)
	var pres_dir: Vector2 = to_pres - from_pres
	var world_dir: Vector2 = to_world - from_world
	var facing: Dictionary = _travel_facing_from_hex_step(from_world, to_world, pres_dir, unit_id)
	var facing_yaw: float = float(facing["model_yaw"])
	_facing_yaw_by_unit_id[unit_id] = facing_yaw
	var semantic: String = SEMANTIC_WALK_CLIP
	var glb_clip: String = _glb_clip_for_semantic(semantic, type_id)
	var duration_sec: float = _hex_move_duration_sec(type_id)
	_active_hex_moves[unit_id] = {
		"type_id": type_id,
		"from_q": from_q,
		"from_r": from_r,
		"to_q": to_q,
		"to_r": to_r,
		"progress": 0.0,
		"anim_elapsed_sec": 0.0,
		"facing_yaw": facing_yaw,
		"pres_dir": pres_dir,
		"duration_sec": duration_sec,
	}
	_log_unit_animation_debug(
		type_id,
		Warrior3DExperimentScript.animated_scene_path_for_type(type_id),
		semantic,
		glb_clip,
		facing_yaw,
	)
	print(
		(
			"[Unit3D hex move] unit=%d type=%s source=(%d,%d) target=(%d,%d) "
			+ "plan_bearing_deg=%.2f map_bearing_deg=%.2f map_skew_deg=%.2f "
			+ "model_yaw_deg=%.2f duration_sec=%.3f walk_clip_len=%.3f stride_frac=%.2f anim_speed=%.2f "
			+ "world_dir=%s pres_dir=%s"
		)
		% [
			unit_id,
			type_id,
			from_q,
			from_r,
			to_q,
			to_r,
			float(facing["plan_bearing_deg"]),
			float(facing["map_bearing_deg"]),
			float(facing["map_skew_deg"]),
			facing_yaw,
			duration_sec,
			_resolved_walk_clip_length_sec(type_id),
			hex_stride_cycle_fraction,
			HEX_MOVE_WALK_ANIM_SPEED,
			str(world_dir),
			str(pres_dir),
		]
	)
	var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
	if slot != null:
		slot.set_meta(&"eom_slot_anim", "")
		slot.set_meta(&"eom_root_motion_walk_mid_logged", false)
		_apply_slot_facing(slot, unit_id)
		if type_id == "settler":
			_log_settler_root_motion_phase(slot, "before_walk")
		var walk_blend: float = -1.0
		if walk_start_blend_sec > 0.0:
			walk_blend = minf(walk_start_blend_sec, WALK_START_BLEND_MAX_SEC)
		_ensure_slot_animation(slot, glb_clip, HEX_MOVE_WALK_ANIM_SPEED, walk_blend, semantic)
		if walk_blend < 0.0:
			_update_walk_animation_for_slot(slot, 0.0, 0.0)
	_request_presentation_redraw()


func is_unit_hex_move_active(unit_id: int) -> bool:
	return _active_hex_moves.has(unit_id)


func is_unit_screen_down_hex_move_active(unit_id: int) -> bool:
	return _screen_down_travel_pres_dir(_hex_move_pres_dir_for_unit(unit_id)).length_squared() > 0.0


func _hex_move_pres_dir_for_unit(unit_id: int) -> Vector2:
	if not _active_hex_moves.has(unit_id):
		return Vector2.ZERO
	return _hex_move_pres_dir(_active_hex_moves[unit_id])


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
	if not Warrior3DExperimentScript.should_render_unit_as_3d(type_id):
		return
	_sync_markers_once_per_frame()
	var pres_override: Dictionary = _presentation_anchor_for_unit(unit_id, anchor_pres, pscale)
	anchor_pres = pres_override["anchor"] as Vector2
	pscale = float(pres_override["pscale"])
	var rect: Rect2 = _marker_display_rect(anchor_pres, pscale, type_id, unit_id)
	if rect.size.x <= 0.0:
		return
	var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
	if slot == null:
		return
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	_apply_slot_facing(slot, unit_id)
	if _active_hex_moves.has(unit_id):
		_update_walk_animation_for_slot(
			slot,
			float(_active_hex_moves[unit_id].get("anim_elapsed_sec", 0.0)),
			0.0,
		)
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
	_load_unit_scenes()
	if _scenes_by_type.is_empty():
		return
	if camera == null:
		camera = MapCameraScript.new()
	var active_ids: Dictionary = {}
	var units: Array = scenario.units()
	var i: int = 0
	while i < units.size():
		var unit = units[i]
		var type_id: String = str(unit.type_id)
		if not Warrior3DExperimentScript.should_render_unit_as_3d(type_id):
			i += 1
			continue
		var unit_id: int = int(unit.id)
		active_ids[unit_id] = true
		var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
		if slot == null:
			slot = _create_slot(type_id)
			add_child(slot)
			_slot_by_unit_id[unit_id] = slot
		slot.set_meta(&"eom_unit_type_id", type_id)
		slot.set_meta(&"eom_unit_id", unit_id)
		_sync_unit_slot(slot, unit_id, unit)
		slot.position = Vector2.ZERO
		if not _blit_via_terrain_foreground:
			var world_center: Vector2 = layout.hex_to_world(unit.position.q, unit.position.r)
			var anchor_pres: Vector2 = camera.to_presentation(world_center)
			var pscale: float = camera.perspective_scale_at(world_center)
			var pres_override: Dictionary = _presentation_anchor_for_unit(
				unit_id, anchor_pres, pscale
			)
			anchor_pres = pres_override["anchor"] as Vector2
			pscale = float(pres_override["pscale"])
			slot.position = _marker_display_rect(anchor_pres, pscale, type_id).position
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
			_active_hex_moves.erase(stale_id)
			_facing_yaw_by_unit_id.erase(stale_id)
		si += 1


func _create_slot(type_id: String = "warrior") -> Node2D:
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
	var unit_scene: PackedScene = _scene_for_type(type_id)
	if unit_scene != null:
		var model: Node = unit_scene.instantiate()
		if _uses_settler_root_motion_cancel(type_id):
			var motion_anchor := Node3D.new()
			motion_anchor.name = ROOT_MOTION_ANCHOR_NAME
			model_root.add_child(motion_anchor)
			motion_anchor.add_child(model)
		else:
			model_root.add_child(model)
	root.set_meta(&"eom_unit_type_id", type_id)
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
	_prime_walk_clip_length_from_slot(root)
	return root


func depth_sort_anchor_pres(unit_id: int, hex_anchor_pres: Vector2, pscale: float) -> Vector2:
	if layout == null or camera == null or not _active_hex_moves.has(unit_id):
		return hex_anchor_pres
	var move: Dictionary = _active_hex_moves[unit_id]
	var pres_dir: Vector2 = _hex_move_pres_dir(move)
	if pres_dir.length_squared() < 1.0:
		return hex_anchor_pres
	var fwd: Vector2 = _screen_down_travel_pres_dir(pres_dir)
	if fwd.length_squared() < 0.0001:
		var draw: Dictionary = _presentation_anchor_for_unit(unit_id, hex_anchor_pres, pscale)
		return draw["anchor"] as Vector2
	var to_world: Vector2 = layout.hex_to_world(int(move["to_q"]), int(move["to_r"]))
	var to_pres: Vector2 = camera.to_presentation(to_world)
	var draw: Dictionary = _presentation_anchor_for_unit(unit_id, hex_anchor_pres, pscale)
	var draw_pscale: float = float(draw["pscale"])
	var marker_rect: Rect2 = _marker_rect_for_type(
		draw["anchor"] as Vector2, draw_pscale, _type_id_for_unit(unit_id), units_view
	)
	var marker_h: float = marker_rect.size.y
	if marker_h <= 0.0:
		marker_h = HexLayoutScript.SIZE * 2.0 * 0.7 * draw_pscale
	var step_len: float = pres_dir.length()
	var lead: float = maxf(step_len * 0.55, marker_h * depth_sort_forward_lead_ratio)
	return to_pres + fwd * lead


func _marker_display_rect(
	anchor_pres: Vector2, pscale: float, type_id: String, unit_id: int = -1
) -> Rect2:
	var marker_rect: Rect2 = _marker_rect_for_type(anchor_pres, pscale, type_id, units_view)
	if marker_rect.size.x <= 0.0 or marker_rect.size.y <= 0.0:
		return Rect2()
	var bottom_pad: float = viewport_bottom_pad_ratio
	var side_pad: float = 0.0
	if unit_id >= 0 and _active_hex_moves.has(unit_id):
		bottom_pad += viewport_travel_forward_pad_ratio * 0.55
		side_pad = viewport_travel_forward_pad_ratio * 0.4
	var display_size := Vector2(
		marker_rect.size.x * (1.0 + side_pad),
		marker_rect.size.y * (1.0 + bottom_pad),
	)
	var pos := Vector2(
		marker_rect.position.x - marker_rect.size.x * side_pad * 0.5,
		marker_rect.position.y,
	)
	return Rect2(pos, display_size)


func _screen_down_travel_pres_dir(pres_dir: Vector2) -> Vector2:
	if pres_dir.length_squared() < 1.0:
		return Vector2.ZERO
	var fwd: Vector2 = pres_dir.normalized()
	if fwd.y <= 0.02:
		return Vector2.ZERO
	return fwd


func _hex_move_pres_dir(move: Dictionary) -> Vector2:
	var cached: Variant = move.get("pres_dir", null)
	if cached is Vector2:
		return cached as Vector2
	if layout == null or camera == null:
		return Vector2.ZERO
	var from_world: Vector2 = layout.hex_to_world(int(move["from_q"]), int(move["from_r"]))
	var to_world: Vector2 = layout.hex_to_world(int(move["to_q"]), int(move["to_r"]))
	return camera.to_presentation(to_world) - camera.to_presentation(from_world)


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


func _ensure_slot_animation(
	slot: Node2D,
	clip_name: String,
	anim_speed_scale: float = 1.0,
	blend_sec: float = -1.0,
	semantic: String = "",
) -> void:
	if not play_map_animation:
		return
	if (
		blend_sec < 0.0
		and str(slot.get_meta(&"eom_slot_anim", "")) == clip_name
		and is_equal_approx(float(slot.get_meta(&"eom_slot_anim_speed", 1.0)), anim_speed_scale)
	):
		return
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	var model_root: Node = viewport.find_child("ModelRoot", true, false)
	if model_root == null:
		return
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", "warrior"))
	var unit_id: int = int(slot.get_meta(&"eom_unit_id", -1))
	var semantic_name: String = semantic if not semantic.is_empty() else clip_name
	var ci: int = 0
	while ci < model_root.get_child_count():
		_play_clip_on_model(
			model_root.get_child(ci),
			clip_name,
			anim_speed_scale,
			blend_sec,
			type_id,
		)
		ci += 1
	_log_unit_animation_debug(
		type_id,
		Warrior3DExperimentScript.animated_scene_path_for_type(type_id),
		semantic_name,
		clip_name,
		_facing_yaw_for_unit(unit_id) if unit_id >= 0 else model_yaw_degrees,
	)
	slot.set_meta(&"eom_slot_anim", clip_name)
	slot.set_meta(&"eom_slot_anim_speed", anim_speed_scale)
	_mark_slot_anim_blend(slot, blend_sec)


func _mark_slot_anim_blend(slot: Node2D, blend_sec: float) -> void:
	if blend_sec > 0.0:
		var until_ms: int = Time.get_ticks_msec() + int(ceil(blend_sec * 1000.0))
		slot.set_meta(&"eom_anim_blend_until", until_ms)
	else:
		slot.set_meta(&"eom_anim_blend_until", 0)


func _slot_anim_blend_active(slot: Node2D) -> bool:
	return Time.get_ticks_msec() < int(slot.get_meta(&"eom_anim_blend_until", 0))


func _play_clip_on_model(
	model: Node,
	clip_name: String,
	anim_speed_scale: float = 1.0,
	blend_sec: float = -1.0,
	type_id: String = "warrior",
) -> void:
	if not model.is_inside_tree():
		return
	var player: AnimationPlayer = _find_animation_player(model)
	if player == null:
		return
	if not player.has_animation(clip_name):
		push_warning(
			"Warrior3DUnitMarkersView: clip '%s' not found on %s (type=%s)"
			% [
				clip_name,
				Warrior3DExperimentScript.animated_scene_path_for_type(type_id),
				type_id,
			]
		)
		return
	var walk_clip: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	var manual_walk_timeline: bool = clip_name == walk_clip
	player.speed_scale = anim_speed_scale
	player.process_mode = (
		Node.PROCESS_MODE_DISABLED if manual_walk_timeline else Node.PROCESS_MODE_INHERIT
	)
	var anim: Animation = player.get_animation(clip_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	if blend_sec > 0.0:
		player.play(clip_name, blend_sec, -1.0)
	elif manual_walk_timeline:
		player.play(clip_name)
		player.seek(0.0, true)
	else:
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


func _tick_hex_moves(delta: float) -> bool:
	if _active_hex_moves.is_empty():
		return false
	var any_active: bool = false
	var finished_ids: Array = []
	for unit_id_key in _active_hex_moves.keys():
		var unit_id: int = int(unit_id_key)
		var move: Dictionary = _active_hex_moves[unit_id]
		var slot: Node2D = _slot_by_unit_id.get(unit_id) as Node2D
		var stride_sec: float = _hex_move_stride_anim_sec(unit_id)
		var anim_elapsed: float = float(move.get("anim_elapsed_sec", 0.0))
		if anim_elapsed < stride_sec:
			anim_elapsed += delta * HEX_MOVE_WALK_ANIM_SPEED
			anim_elapsed = minf(anim_elapsed, stride_sec)
			move["anim_elapsed_sec"] = anim_elapsed
			_update_walk_animation_for_slot(slot, anim_elapsed, delta)
		var progress: float = 1.0 if stride_sec <= 0.0 else clampf(anim_elapsed / stride_sec, 0.0, 1.0)
		if progress >= 1.0:
			progress = 1.0
			finished_ids.append(unit_id)
		move["progress"] = progress
		_active_hex_moves[unit_id] = move
		any_active = true
	var fi: int = 0
	while fi < finished_ids.size():
		var done_id: int = int(finished_ids[fi])
		var facing_yaw: float = float(_facing_yaw_by_unit_id.get(done_id, model_yaw_degrees))
		_active_hex_moves.erase(done_id)
		var done_type_id: String = _type_id_for_unit(done_id)
		var idle_semantic: String = SEMANTIC_IDLE_CLIP
		var idle_glb: String = _glb_clip_for_semantic(idle_semantic, done_type_id)
		_log_unit_animation_debug(
			done_type_id,
			Warrior3DExperimentScript.animated_scene_path_for_type(done_type_id),
			idle_semantic,
			idle_glb,
			facing_yaw,
		)
		var slot: Node2D = _slot_by_unit_id.get(done_id) as Node2D
		if slot != null:
			slot.set_meta(&"eom_slot_anim", "")
			_apply_slot_facing(slot, done_id)
			_ensure_slot_animation(slot, idle_glb, 1.0, idle_end_blend_sec, idle_semantic)
			if done_type_id == "settler":
				_refresh_settler_root_motion_cancel(slot)
				_log_settler_root_motion_phase(slot, "after_walk")
		fi += 1
	return any_active or finished_ids.size() > 0


func _request_presentation_redraw() -> void:
	if terrain_foreground_view != null:
		terrain_foreground_view.queue_redraw()
	elif units_view != null:
		units_view.queue_redraw()
	else:
		queue_redraw()


func _sync_unit_slot(slot: Node2D, unit_id: int, _unit) -> void:
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", "warrior"))
	var catalog_player: AnimationPlayer = _walk_animation_player_for_slot(slot)
	if catalog_player != null and slot.is_inside_tree():
		_log_animation_player_catalog_once(slot, type_id, catalog_player)
	_apply_slot_facing(slot, unit_id)
	var clip_name: String = _playback_clip_for_unit(unit_id)
	var anim_speed: float = (
		HEX_MOVE_WALK_ANIM_SPEED if _active_hex_moves.has(unit_id) else 1.0
	)
	if (
		str(slot.get_meta(&"eom_slot_anim", "")) != clip_name
		or not is_equal_approx(float(slot.get_meta(&"eom_slot_anim_speed", 1.0)), anim_speed)
	):
		_ensure_slot_animation(
			slot,
			clip_name,
			anim_speed,
			-1.0,
			_semantic_animation_for_unit(unit_id),
		)


func _playback_clip_for_unit(unit_id: int) -> String:
	if _is_animation_audit_active():
		return _playback_animation_name()
	var semantic: String = _semantic_animation_for_unit(unit_id)
	return _glb_clip_for_semantic(semantic, _type_id_for_unit(unit_id))


func _semantic_animation_for_unit(unit_id: int) -> String:
	if _active_hex_moves.has(unit_id):
		return SEMANTIC_WALK_CLIP
	return SEMANTIC_IDLE_CLIP


func _glb_clip_for_semantic(semantic: String, type_id: String = "warrior") -> String:
	return Warrior3DAnimationRemapScript.glb_clip_for_visual(
		semantic,
		use_glb_animation_name_remap and not _is_animation_audit_active(),
		type_id,
	)


func _facing_yaw_for_unit(unit_id: int) -> float:
	if _active_hex_moves.has(unit_id):
		return float(_active_hex_moves[unit_id].get("facing_yaw", model_yaw_degrees))
	if _facing_yaw_by_unit_id.has(unit_id):
		return float(_facing_yaw_by_unit_id[unit_id])
	return model_yaw_degrees


static func _travel_bearing_screen_up_deg(dir: Vector2) -> float:
	return rad_to_deg(Vector2(dir.x, -dir.y).angle())


static func _bearing_delta_deg(to_deg: float, from_deg: float) -> float:
	return rad_to_deg(atan2(sin(deg_to_rad(to_deg - from_deg)), cos(deg_to_rad(to_deg - from_deg))))


func _travel_facing_from_hex_step(
	from_world: Vector2,
	to_world: Vector2,
	pres_dir: Vector2,
	unit_id: int,
) -> Dictionary:
	var world_dir: Vector2 = to_world - from_world
	if world_dir.length_squared() < 0.0001:
		var idle_yaw: float = _facing_yaw_for_unit(unit_id)
		return {
			"plan_bearing_deg": 0.0,
			"map_bearing_deg": 0.0,
			"map_skew_deg": 0.0,
			"model_yaw": idle_yaw,
		}
	# 1) Top-down plan bearing (layout / hex_to_world, Y-down corrected to screen-up).
	var plan_bearing_deg: float = _travel_bearing_screen_up_deg(world_dir)
	# 2) Same step after MapCamera.to_presentation (chord from → to on the map plane).
	var map_bearing_deg: float = _travel_bearing_screen_up_deg(pres_dir)
	var map_skew_deg: float = _bearing_delta_deg(map_bearing_deg, plan_bearing_deg)
	# 3) SubViewport model yaw follows **map** bearing (on-screen walk), not plan bearing alone.
	var model_yaw: float = _subviewport_yaw_for_map_bearing(pres_dir, unit_id)
	return {
		"plan_bearing_deg": plan_bearing_deg,
		"map_bearing_deg": map_bearing_deg,
		"map_skew_deg": map_skew_deg,
		"model_yaw": model_yaw,
	}


func _subviewport_yaw_for_map_bearing(pres_dir: Vector2, unit_id: int) -> float:
	if pres_dir.length_squared() < 0.0001:
		return _facing_yaw_for_unit(unit_id)
	var map_bearing_deg: float = _travel_bearing_screen_up_deg(pres_dir)
	return travel_facing_yaw_offset_deg + map_bearing_deg


func _model_yaw_from_travel_pres_dir(pres_dir: Vector2, unit_id: int) -> float:
	return _subviewport_yaw_for_map_bearing(pres_dir, unit_id)


static func expected_travel_yaw_from_pres_dir(
	pres_dir: Vector2,
	offset_deg: float = 69.0,
) -> float:
	if pres_dir.length_squared() < 0.0001:
		return 0.0
	return offset_deg + rad_to_deg(Vector2(pres_dir.x, -pres_dir.y).angle())


func _hex_move_stride_anim_sec(unit_id: int) -> float:
	return (
		_resolved_walk_clip_length_sec(_type_id_for_unit(unit_id))
		* hex_stride_cycle_fraction
	)


func _walk_animation_player_for_slot(slot: Node2D) -> AnimationPlayer:
	if slot == null:
		return null
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return null
	var model_root: Node = viewport.find_child("ModelRoot", true, false)
	if model_root == null:
		return null
	var ci: int = 0
	while ci < model_root.get_child_count():
		var player: AnimationPlayer = _find_animation_player(model_root.get_child(ci) as Node)
		if player != null:
			return player
		ci += 1
	return null


func _update_walk_animation_for_slot(
	slot: Node2D, anim_elapsed: float, delta: float
) -> void:
	var player: AnimationPlayer = _walk_animation_player_for_slot(slot)
	if player == null:
		return
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", "warrior"))
	var walk_clip: String = _glb_clip_for_semantic(SEMANTIC_WALK_CLIP, type_id)
	var walk_anim: Animation = player.get_animation(walk_clip)
	if walk_anim == null or walk_anim.length <= 0.0:
		return
	if _slot_anim_blend_active(slot):
		return
	if str(player.current_animation) != walk_clip:
		player.play(walk_clip)
		player.seek(0.0, true)
	var loop_len: float = maxf(walk_anim.length - 0.0001, 0.001)
	player.seek(fposmod(anim_elapsed, loop_len), true)
	player.advance(0.0)
	_refresh_settler_root_motion_cancel(slot)
	if type_id == "settler":
		var stride_sec: float = _hex_move_stride_anim_sec(
			int(slot.get_meta(&"eom_unit_id", -1))
		)
		if (
			stride_sec > 0.0
			and anim_elapsed >= stride_sec * 0.45
			and not bool(slot.get_meta(&"eom_root_motion_walk_mid_logged", false))
		):
			slot.set_meta(&"eom_root_motion_walk_mid_logged", true)
			_log_settler_root_motion_phase(slot, "during_walk")


func _advance_pending_animation_blends(delta: float) -> void:
	if delta <= 0.0:
		return
	for unit_id_key in _slot_by_unit_id.keys():
		var slot: Node2D = _slot_by_unit_id[unit_id_key] as Node2D
		if slot == null or not _slot_anim_blend_active(slot):
			continue
		var player: AnimationPlayer = _walk_animation_player_for_slot(slot)
		if player == null:
			continue
		if player.process_mode == Node.PROCESS_MODE_DISABLED:
			player.advance(delta)


func _ensure_idle_slots_autoplay() -> void:
	for unit_id_key in _slot_by_unit_id.keys():
		var unit_id: int = int(unit_id_key)
		if _active_hex_moves.has(unit_id):
			continue
		var slot: Node2D = _slot_by_unit_id[unit_id_key] as Node2D
		if slot == null or _slot_anim_blend_active(slot):
			continue
		var type_id: String = str(slot.get_meta(&"eom_unit_type_id", "warrior"))
		var idle_clip: String = _glb_clip_for_semantic(SEMANTIC_IDLE_CLIP, type_id)
		if str(slot.get_meta(&"eom_slot_anim", "")) != idle_clip:
			continue
		var player: AnimationPlayer = _walk_animation_player_for_slot(slot)
		if player == null:
			continue
		if player.process_mode != Node.PROCESS_MODE_INHERIT:
			player.process_mode = Node.PROCESS_MODE_INHERIT
		if not player.is_playing() or str(player.current_animation) != idle_clip:
			player.play(idle_clip)


func _uses_settler_root_motion_cancel(type_id: String) -> bool:
	return str(type_id) == "settler" and settler_neutralize_root_motion


func _model_root_for_slot(slot: Node2D) -> Node3D:
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return null
	return viewport.find_child("ModelRoot", true, false) as Node3D


func _root_motion_anchor_for_slot(slot: Node2D) -> Node3D:
	var model_root: Node3D = _model_root_for_slot(slot)
	if model_root == null:
		return null
	return model_root.find_child(ROOT_MOTION_ANCHOR_NAME, false, false) as Node3D


func _skeleton_for_slot(slot: Node2D) -> Skeleton3D:
	var model_root: Node3D = _model_root_for_slot(slot)
	if model_root == null:
		return null
	return _find_skeleton3d(model_root)


static func _find_skeleton3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	var children: Array = node.get_children()
	var i: int = 0
	while i < children.size():
		var found: Skeleton3D = _find_skeleton3d(children[i] as Node)
		if found != null:
			return found
		i += 1
	return null


func _hips_bone_index(skel: Skeleton3D) -> int:
	return skel.find_bone(HIPS_BONE_NAME)


func _hips_local_in_model_root(slot: Node2D) -> Vector3:
	var model_root: Node3D = _model_root_for_slot(slot)
	var skel: Skeleton3D = _skeleton_for_slot(slot)
	if model_root == null or skel == null:
		return Vector3.ZERO
	var hips_idx: int = _hips_bone_index(skel)
	if hips_idx < 0:
		return Vector3.ZERO
	var hips_global: Vector3 = skel.get_bone_global_pose(hips_idx).origin
	return model_root.global_transform.affine_inverse() * hips_global


func _invalidate_settler_root_motion_reference(slot: Node2D) -> void:
	if slot.has_meta(&"eom_hips_ref_local"):
		slot.remove_meta(&"eom_hips_ref_local")


func _try_capture_settler_hips_reference(slot: Node2D) -> bool:
	if slot.has_meta(&"eom_hips_ref_local"):
		return true
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", ""))
	if not _uses_settler_root_motion_cancel(type_id):
		return false
	var player: AnimationPlayer = _walk_animation_player_for_slot(slot)
	var skel: Skeleton3D = _skeleton_for_slot(slot)
	if player == null or skel == null or _hips_bone_index(skel) < 0:
		return false
	var idle_clip: String = _glb_clip_for_semantic(SEMANTIC_IDLE_CLIP, type_id)
	var slot_clip: String = str(slot.get_meta(&"eom_slot_anim", ""))
	var playing_idle: bool = (
		slot_clip == idle_clip
		or str(player.current_animation) == idle_clip
		or str(player.assigned_animation) == idle_clip
	)
	if not playing_idle:
		return false
	slot.set_meta(&"eom_hips_ref_local", _hips_local_in_model_root(slot))
	return true


func _refresh_settler_root_motion_cancel(slot: Node2D) -> void:
	var type_id: String = str(slot.get_meta(&"eom_unit_type_id", ""))
	if not _uses_settler_root_motion_cancel(type_id):
		return
	var anchor: Node3D = _root_motion_anchor_for_slot(slot)
	var model_root: Node3D = _model_root_for_slot(slot)
	var skel: Skeleton3D = _skeleton_for_slot(slot)
	if anchor == null or model_root == null or skel == null:
		return
	if _hips_bone_index(skel) < 0:
		return
	if not slot.has_meta(&"eom_hips_ref_local"):
		_try_capture_settler_hips_reference(slot)
	if not slot.has_meta(&"eom_hips_ref_local"):
		anchor.position = Vector3.ZERO
		return
	var hips_local: Vector3 = _hips_local_in_model_root(slot)
	var ref_local: Vector3 = slot.get_meta(&"eom_hips_ref_local", Vector3.ZERO)
	anchor.position = ref_local - hips_local


func _refresh_all_settler_root_motion_cancels() -> void:
	for unit_id_key in _slot_by_unit_id.keys():
		var slot: Node2D = _slot_by_unit_id[unit_id_key] as Node2D
		if slot == null:
			continue
		if not _uses_settler_root_motion_cancel(str(slot.get_meta(&"eom_unit_type_id", ""))):
			continue
		_refresh_settler_root_motion_cancel(slot)


func _log_settler_root_motion_phase(slot: Node2D, phase: String) -> void:
	if not _uses_settler_root_motion_cancel(str(slot.get_meta(&"eom_unit_type_id", ""))):
		return
	var anchor: Node3D = _root_motion_anchor_for_slot(slot)
	var skel: Skeleton3D = _skeleton_for_slot(slot)
	var hips_local: Vector3 = _hips_local_in_model_root(slot)
	var ref_local: Vector3 = (
		slot.get_meta(&"eom_hips_ref_local") as Vector3
		if slot.has_meta(&"eom_hips_ref_local")
		else Vector3.ZERO
	)
	var hips_idx: int = _hips_bone_index(skel) if skel != null else -1
	var hips_global: Vector3 = Vector3.ZERO
	if skel != null and hips_idx >= 0:
		hips_global = skel.get_bone_global_pose(hips_idx).origin
	var imported_root: Node3D = anchor.get_child(0) as Node3D if anchor != null and anchor.get_child_count() > 0 else null
	print(
		(
			"[Settler3D root motion] phase=%s anchor.pos=%s imported.pos=%s "
			+ "hips.local=%s hips.global=%s ref.local=%s cancel.delta=%s"
		)
		% [
			phase,
			_fmt_v3(anchor.position if anchor != null else Vector3.ZERO),
			_fmt_v3(imported_root.position if imported_root != null else Vector3.ZERO),
			_fmt_v3(hips_local),
			_fmt_v3(hips_global),
			_fmt_v3(ref_local),
			_fmt_v3(hips_local - ref_local),
		]
	)


static func _fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _apply_slot_facing(slot: Node2D, unit_id: int) -> void:
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	var model_root: Node3D = viewport.find_child("ModelRoot", true, false) as Node3D
	if model_root == null:
		return
	var yaw: float = _facing_yaw_for_unit(unit_id)
	var prev_yaw: float = float(slot.get_meta(&"eom_last_facing_yaw", yaw))
	if (
		_uses_settler_root_motion_cancel(str(slot.get_meta(&"eom_unit_type_id", "")))
		and not is_equal_approx(yaw, prev_yaw)
	):
		_invalidate_settler_root_motion_reference(slot)
	slot.set_meta(&"eom_last_facing_yaw", yaw)
	model_root.rotation_degrees = Vector3(
		model_pitch_degrees,
		model_yaw_base_offset + yaw,
		0.0,
	)
	model_root.scale = Vector3.ONE * model_scale
	model_root.position = Vector3(0.0, model_offset_y, 0.0)
	var cam: Camera3D = viewport.get_child(0) as Camera3D
	if cam != null:
		cam.size = camera_ortho_size
	_refresh_settler_root_motion_cancel(slot)


func _hex_move_progress(unit_id: int) -> float:
	if not _active_hex_moves.has(unit_id):
		return 1.0
	return clampf(float(_active_hex_moves[unit_id].get("progress", 0.0)), 0.0, 1.0)


func _presentation_anchor_for_unit(
	unit_id: int,
	default_anchor: Vector2,
	default_pscale: float,
) -> Dictionary:
	if layout == null or camera == null or not _active_hex_moves.has(unit_id):
		return {"anchor": default_anchor, "pscale": default_pscale}
	var move: Dictionary = _active_hex_moves[unit_id]
	var from_world: Vector2 = layout.hex_to_world(
		int(move["from_q"]),
		int(move["from_r"]),
	)
	var to_world: Vector2 = layout.hex_to_world(int(move["to_q"]), int(move["to_r"]))
	var t: float = _hex_move_progress(unit_id)
	# Lerp in presentation space so on-screen path matches facing (avoids perspective drift).
	var from_pres: Vector2 = camera.to_presentation(from_world)
	var to_pres: Vector2 = camera.to_presentation(to_world)
	var world: Vector2 = from_world.lerp(to_world, t)
	return {
		"anchor": from_pres.lerp(to_pres, t),
		"pscale": camera.perspective_scale_at(world),
	}
