# Temporary diagnostic: Meshy source (left) vs Uthana target (right), same Walking phase.
# Not the acceptance preview — F6 acceptance stays on uthana_a1_walking_preview.tscn.
extends Node3D

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const PlaybackScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)

var _playback: Node = null
var _src_player: AnimationPlayer = null
var _tgt_player: AnimationPlayer = null
var _src_clip_id: String = ""
var _tgt_clip_id: String = ""
var _src_root: Node3D = null
var _tgt_root: Node3D = null
var _canonical_library_path: String = Native.WALKING_LIBRARY_PATH
var _body_camera: Camera3D = null
var _foot_camera: Camera3D = null
var _tgt_ground_lift: float = 0.0
var _tgt_lowest_sole_y: float = 0.0
var _tgt_ground_contact: Dictionary = {}


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 25.0, 0.0)
	add_child(light)
	_body_camera = Camera3D.new()
	_body_camera.name = "PreviewCamera"
	add_child(_body_camera)
	_body_camera.look_at_from_position(Vector3(0.0, 0.55, 2.2), Vector3(0.0, 0.3, 0.0), Vector3.UP)
	_body_camera.current = true

	_foot_camera = Camera3D.new()
	_foot_camera.name = "FootInspectionCamera"
	add_child(_foot_camera)
	_foot_camera.look_at_from_position(Vector3(0.0, 0.09, 0.85), Vector3(0.0, 0.02, 0.0), Vector3.UP)
	_foot_camera.current = false

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 2.0)
	ground.mesh = plane
	add_child(ground)

	await _spawn_pair()


func _spawn_pair() -> void:
	var lib: AnimationLibrary = Native.ensure_walking_library()
	if lib == null or not lib.has_animation(Native.WALKING_CLIP):
		push_error("uthana_a1_side_by_side: native Walking library missing")
		return
	_canonical_library_path = Native.WALKING_LIBRARY_PATH
	var native_walk: Animation = lib.get_animation(Native.WALKING_CLIP)

	_src_root = Node3D.new()
	_src_root.name = "SourceMeshy"
	_src_root.position = Vector3(-0.55, 0.0, 0.0)
	_src_root.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	add_child(_src_root)
	var src_char: Node3D = (load(Native.MESHY_SOURCE_GLB) as PackedScene).instantiate()
	src_char.name = "SourceCharacter"
	_src_root.add_child(src_char)
	_src_player = Native.find_animation_player(src_char)
	if _src_player == null or not _src_player.has_animation(Native.WALKING_CLIP):
		push_error("uthana_a1_side_by_side: source Walking missing")
		return
	_src_clip_id = PlaybackScript.attach_looping_clip(
		_src_player, native_walk, Native.WALKING_CLIP
	)

	_tgt_root = Node3D.new()
	_tgt_root.name = "TargetUthana"
	_tgt_root.position = Vector3(0.55, 0.0, 0.0)
	_tgt_root.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	add_child(_tgt_root)
	var tgt_char: Node3D = (load(Native.UTHANA_TARGET_GLB) as PackedScene).instantiate()
	tgt_char.name = "TargetCharacter"
	_tgt_root.add_child(tgt_char)
	_tgt_player = AnimationPlayer.new()
	_tgt_player.name = "NativeRetargetAnimationPlayer"
	tgt_char.add_child(_tgt_player)
	_tgt_clip_id = PlaybackScript.attach_looping_clip(
		_tgt_player, native_walk, Native.WALKING_CLIP
	)

	await get_tree().process_frame
	var src_sk := Native.find_skeleton(src_char)
	var tgt_sk := Native.find_skeleton(tgt_char)
	_src_player.play(_src_clip_id)
	_tgt_player.play(_tgt_clip_id)
	_src_player.seek(0.0, true)
	_tgt_player.seek(0.0, true)
	await get_tree().process_frame
	if src_sk != null:
		src_sk.force_update_all_bone_transforms()
		_src_root.position.y = 0.0
		var c1: Dictionary = Native.sample_sole_ground_contact(
			src_char, src_sk, _src_player, _src_clip_id, 25
		)
		_src_root.position.y = float(c1.get("ground_offset_y", 0.0))
	if tgt_sk != null:
		tgt_sk.force_update_all_bone_transforms()
		_tgt_root.position.y = 0.0
		_tgt_ground_contact = Native.sample_sole_ground_contact(
			tgt_char, tgt_sk, _tgt_player, _tgt_clip_id, 33
		)
		_tgt_ground_lift = float(_tgt_ground_contact.get("ground_offset_y", 0.0))
		_tgt_lowest_sole_y = (
			float(_tgt_ground_contact.get("lowest_sole_y", 0.0)) + _tgt_ground_lift
		)
		_tgt_root.position.y = _tgt_ground_lift

	_playback = PlaybackScript.new()
	_playback.name = "A1PreviewPlayback"
	add_child(_playback)
	_playback.configure(
		[_tgt_player, _src_player],
		[_tgt_clip_id, _src_clip_id],
		[_tgt_root, _src_root],
		Native.WALKING_CLIP,
		_tgt_ground_lift,
		_tgt_lowest_sole_y,
		_body_camera,
		_foot_camera
	)
	_playback.seek_all(0.0, true)

	var l_src := Label3D.new()
	l_src.text = "SOURCE Meshy"
	l_src.position = Vector3(-0.55, 0.72, 0.0)
	l_src.font_size = 28
	add_child(l_src)
	var l_tgt := Label3D.new()
	l_tgt.text = "TARGET Uthana"
	l_tgt.position = Vector3(0.55, 0.72, 0.0)
	l_tgt.font_size = 28
	add_child(l_tgt)
	print(
		(
			"uthana_a1_side_by_side: skinned sole lift tgt=%.4f; F=foot-cam; "
			+ "acceptance is uthana_a1_walking_preview.tscn"
		)
		% _tgt_ground_lift
	)


func preview_playback() -> Node:
	return _playback


func source_player() -> AnimationPlayer:
	return _src_player


func target_player() -> AnimationPlayer:
	return _tgt_player


func canonical_library_path() -> String:
	return _canonical_library_path


func ground_contact() -> Dictionary:
	return _tgt_ground_contact


func ground_offset_y() -> float:
	return _tgt_ground_lift
