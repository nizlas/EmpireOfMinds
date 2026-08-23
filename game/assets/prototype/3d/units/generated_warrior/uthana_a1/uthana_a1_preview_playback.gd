# A1 preview-only playback: loop / speed / pause / foot-cam without mutating a1_native_walking.res.
# Diagnostic controls only — not for production scenes.
extends Node

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)

const PREVIEW_LIBRARY_NAME := "uthana_a1_preview"
const STATUS_LABEL_NAME := "A1PlaybackStatus"

## Master is always index 0; slaves are hard-synced each frame.
var _players: Array[AnimationPlayer] = []
var _clip_ids: Array[String] = []
var _speed: float = 1.0
var _paused: bool = false
var _status_label: Label = null
var _clip_display_name: String = "Walking"
var _fixed_root_positions: Array[Vector3] = []
var _roots: Array[Node3D] = []
var _ground_lift: float = 0.0
var _lowest_sole_y: float = 0.0
var _body_camera: Camera3D = null
var _foot_camera: Camera3D = null
var _foot_view: bool = false


func configure(
	players: Array,
	clip_ids: Array,
	roots: Array = [],
	clip_display_name: String = "Walking",
	ground_lift: float = 0.0,
	lowest_sole_y: float = 0.0,
	body_camera: Camera3D = null,
	foot_camera: Camera3D = null
) -> void:
	_players.clear()
	_clip_ids.clear()
	_roots.clear()
	_fixed_root_positions.clear()
	_clip_display_name = clip_display_name
	_ground_lift = ground_lift
	_lowest_sole_y = lowest_sole_y
	_body_camera = body_camera
	_foot_camera = foot_camera
	_foot_view = false
	for i in players.size():
		var p: AnimationPlayer = players[i] as AnimationPlayer
		if p == null:
			continue
		_players.append(p)
		_clip_ids.append(str(clip_ids[i]) if i < clip_ids.size() else str(clip_ids[0]))
	for r in roots:
		if r is Node3D:
			_roots.append(r as Node3D)
			_fixed_root_positions.append((r as Node3D).position)
	_ensure_status_label()
	_apply_speed_and_pause()
	_apply_camera()
	_update_status_label()
	set_process(true)


static func duplicate_walking_as_looping(source_anim: Animation) -> Animation:
	## Preview-layer duplicate only — never write back to a1_native_walking.res.
	var dup: Animation = source_anim.duplicate(true) as Animation
	dup.loop_mode = Animation.LOOP_LINEAR
	return dup


static func attach_looping_clip(
	player: AnimationPlayer, source_anim: Animation, clip_name: String = Native.WALKING_CLIP
) -> String:
	var looping: Animation = duplicate_walking_as_looping(source_anim)
	if player.has_animation_library(PREVIEW_LIBRARY_NAME):
		player.remove_animation_library(PREVIEW_LIBRARY_NAME)
	var lib := AnimationLibrary.new()
	lib.add_animation(clip_name, looping)
	player.add_animation_library(PREVIEW_LIBRARY_NAME, lib)
	return PREVIEW_LIBRARY_NAME + "/" + clip_name


static func canonical_library_untouched() -> bool:
	if not ResourceLoader.exists(Native.WALKING_LIBRARY_PATH):
		return false
	var lib: AnimationLibrary = (
		ResourceLoader.load(Native.WALKING_LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		as AnimationLibrary
	)
	if lib == null or not lib.has_animation(Native.WALKING_CLIP):
		return false
	var walk: Animation = lib.get_animation(Native.WALKING_CLIP)
	return walk.loop_mode == Animation.LOOP_NONE


func playback_speed() -> float:
	return _speed


func is_playback_paused() -> bool:
	return _paused


func is_foot_view() -> bool:
	return _foot_view


func player_count() -> int:
	return _players.size()


func clip_id_at(index: int) -> String:
	if index < 0 or index >= _clip_ids.size():
		return ""
	return _clip_ids[index]


func position_at(index: int) -> float:
	if index < 0 or index >= _players.size():
		return -1.0
	return _players[index].current_animation_position


func set_playback_speed(speed: float) -> void:
	_speed = speed
	_apply_speed_and_pause()
	_update_status_label()


func toggle_pause() -> void:
	_paused = not _paused
	_apply_speed_and_pause()
	_update_status_label()


func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_speed_and_pause()
	_update_status_label()


func toggle_foot_view() -> void:
	_foot_view = not _foot_view
	_apply_camera()
	_update_status_label()


func seek_all(time_sec: float, update: bool = true) -> void:
	for i in _players.size():
		var p: AnimationPlayer = _players[i]
		if p.has_animation(_clip_ids[i]):
			p.seek(time_sec, update)


func max_position_delta() -> float:
	if _players.size() < 2:
		return 0.0
	var lo := INF
	var hi := -INF
	for p in _players:
		lo = minf(lo, p.current_animation_position)
		hi = maxf(hi, p.current_animation_position)
	return hi - lo


func _ensure_status_label() -> void:
	if _status_label != null and is_instance_valid(_status_label):
		return
	var layer := CanvasLayer.new()
	layer.name = "A1PlaybackHud"
	layer.layer = 100
	add_child(layer)
	_status_label = Label.new()
	_status_label.name = STATUS_LABEL_NAME
	_status_label.position = Vector2(12, 12)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.modulate = Color(0.92, 0.95, 0.85, 1.0)
	layer.add_child(_status_label)


func _update_status_label() -> void:
	if _status_label == null:
		return
	var state := "PAUSED" if _paused else "PLAYING"
	var cam := "FOOT" if _foot_view else "BODY"
	_status_label.text = (
		"%s — %.2fx — %s — %s\nGround lift: %.4f | Lowest sole Y: %.4f"
		% [_clip_display_name, _speed, state, cam, _ground_lift, _lowest_sole_y]
	)


func _apply_camera() -> void:
	if _body_camera == null or _foot_camera == null:
		return
	_body_camera.current = not _foot_view
	_foot_camera.current = _foot_view


func _apply_speed_and_pause() -> void:
	for i in _players.size():
		var p: AnimationPlayer = _players[i]
		var clip := _clip_ids[i]
		if not p.has_animation(clip):
			continue
		if p.current_animation != clip and p.has_animation(clip):
			p.play(clip)
		if _paused:
			p.speed_scale = 0.0
			p.pause()
		else:
			p.speed_scale = _speed
			if not p.is_playing():
				p.play()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: InputEventKey = event as InputEventKey
	match key.keycode:
		KEY_1:
			set_playback_speed(1.0)
			get_viewport().set_input_as_handled()
		KEY_2:
			set_playback_speed(0.5)
			get_viewport().set_input_as_handled()
		KEY_3:
			set_playback_speed(0.25)
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_F:
			toggle_foot_view()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	for i in _roots.size():
		if is_instance_valid(_roots[i]):
			var p: Vector3 = _roots[i].position
			p.x = _fixed_root_positions[i].x
			p.z = _fixed_root_positions[i].z
			_roots[i].position = p
	if _players.size() < 2:
		return
	var master: AnimationPlayer = _players[0]
	var t: float = master.current_animation_position
	var master_speed: float = master.speed_scale
	for i in range(1, _players.size()):
		var slave: AnimationPlayer = _players[i]
		slave.speed_scale = master_speed
		if absf(slave.current_animation_position - t) > 0.0005:
			slave.seek(t, true)
