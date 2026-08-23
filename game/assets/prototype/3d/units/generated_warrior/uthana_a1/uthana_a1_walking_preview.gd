# Isolated A1 acceptance preview: natively retargeted Uthana + shared Walking.
# Does NOT use the failed custom global_hierarchical_rest_delta baker.
extends Node3D

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const PlaybackScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)

var _model_root: Node3D = null
var _ground_offset_y: float = 0.0
var _lowest_sole_y: float = 0.0
var _hips_span: float = 0.0
var _ground_contact: Dictionary = {}
var _playback: Node = null
var _player: AnimationPlayer = null
var _clip_id: String = ""
var _canonical_library_path: String = Native.WALKING_LIBRARY_PATH
var _body_camera: Camera3D = null
var _foot_camera: Camera3D = null


func _ready() -> void:
	_build_lighting()
	_build_ground_and_forward_marker()
	_build_character_and_play()


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	_body_camera = Camera3D.new()
	_body_camera.name = "PreviewCamera"
	add_child(_body_camera)
	_body_camera.look_at_from_position(Vector3(0.85, 0.45, 0.95), Vector3(0.0, 0.28, 0.05), Vector3.UP)
	_body_camera.current = true

	# Low side view aimed at both feet / ground plane.
	_foot_camera = Camera3D.new()
	_foot_camera.name = "FootInspectionCamera"
	add_child(_foot_camera)
	_foot_camera.look_at_from_position(Vector3(0.55, 0.08, 0.35), Vector3(0.0, 0.02, 0.05), Vector3.UP)
	_foot_camera.current = false


func _build_ground_and_forward_marker() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.6)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.24, 0.26)
	ground.material_override = gmat
	add_child(ground)

	var arrow_root := Node3D.new()
	arrow_root.name = "ForwardArrow_PlusZ"
	arrow_root.position = Vector3(0.22, 0.0, 0.12)
	add_child(arrow_root)
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.albedo_color = Color(0.25, 0.95, 0.4)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.012, 0.012, 0.16)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.01, 0.08)
	shaft.material_override = amat
	arrow_root.add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := PrismMesh.new()
	head_mesh.size = Vector3(0.035, 0.05, 0.035)
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.01, 0.175)
	head.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	head.material_override = amat
	arrow_root.add_child(head)
	var label := Label3D.new()
	label.name = "ForwardLabel"
	label.text = "+Z"
	label.position = Vector3(0.0, 0.04, 0.22)
	label.font_size = 18
	label.pixel_size = 0.004
	label.modulate = Color(0.35, 1.0, 0.45)
	arrow_root.add_child(label)


func _build_character_and_play() -> void:
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	_model_root.rotation = Vector3(0.0, Native.PREVIEW_MODEL_YAW, 0.0)
	add_child(_model_root)

	var packed: PackedScene = load(Native.UTHANA_TARGET_GLB) as PackedScene
	var character: Node3D = packed.instantiate() as Node3D
	character.name = "UthanaWarrior"
	_model_root.add_child(character)

	var lib: AnimationLibrary = Native.ensure_walking_library()
	if lib == null or not lib.has_animation(Native.WALKING_CLIP):
		push_error("uthana_a1_preview: native Walking library missing")
		return
	_canonical_library_path = Native.WALKING_LIBRARY_PATH
	var source_walk: Animation = lib.get_animation(Native.WALKING_CLIP)

	_player = AnimationPlayer.new()
	_player.name = "NativeRetargetAnimationPlayer"
	character.add_child(_player)
	_clip_id = PlaybackScript.attach_looping_clip(_player, source_walk, Native.WALKING_CLIP)

	var skeleton: Skeleton3D = Native.find_skeleton(character)
	_player.play(_clip_id)
	_player.seek(0.0, true)
	await get_tree().process_frame
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()
	# Measure with ModelRoot.y = 0, then apply constant skinned-sole lift.
	_model_root.position.y = 0.0
	_ground_contact = Native.sample_sole_ground_contact(character, skeleton, _player, _clip_id, 33)
	if not bool(_ground_contact.get("ok", false)):
		push_error("uthana_a1_preview: skinned sole ground failed: %s" % _ground_contact)
		return
	_ground_offset_y = float(_ground_contact.get("ground_offset_y", 0.0))
	_lowest_sole_y = float(_ground_contact.get("lowest_sole_y", 0.0)) + _ground_offset_y
	_hips_span = float(_ground_contact.get("hips_span", 0.0))
	_model_root.position.y = _ground_offset_y

	_playback = PlaybackScript.new()
	_playback.name = "A1PreviewPlayback"
	add_child(_playback)
	_playback.configure(
		[_player],
		[_clip_id],
		[_model_root],
		Native.WALKING_CLIP,
		_ground_offset_y,
		_lowest_sole_y,
		_body_camera,
		_foot_camera
	)
	_playback.seek_all(0.0, true)

	print(
		(
			"uthana_a1_preview: looping %s sole_lift=%.4f bone_delta=%.4f verts=%s "
			+ "hips_span=%.4f (1/2/3 speed, Space pause, F foot-cam)"
		)
		% [
			_clip_id,
			_ground_offset_y,
			float(_ground_contact.get("bone_minus_sole", 0.0)),
			str(_ground_contact.get("vertex_count", 0)),
			_hips_span,
		]
	)


func ground_offset_y() -> float:
	return _ground_offset_y


func lowest_sole_y() -> float:
	return _lowest_sole_y


func hips_span() -> float:
	return _hips_span


func ground_contact() -> Dictionary:
	return _ground_contact


func preview_playback() -> Node:
	return _playback


func preview_player() -> AnimationPlayer:
	return _player


func preview_clip_id() -> String:
	return _clip_id


func canonical_library_path() -> String:
	return _canonical_library_path
