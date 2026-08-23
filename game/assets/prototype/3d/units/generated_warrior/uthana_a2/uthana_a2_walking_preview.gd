# Isolated A2 preview: A1 Walking + wooden club + power_grip_v1
# (canonical pose + bounded refinement). Does not modify A1 assets,
# imports, or Walking data. H cycles body/palm/dorsal/thumb/tips views.
extends Node3D

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const PlaybackScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)
const AttachmentScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_club_attachment.gd"
)

var _model_root: Node3D = null
var _character: Node3D = null
var _ground_offset_y: float = 0.0
var _lowest_sole_y: float = 0.0
var _ground_contact: Dictionary = {}
var _playback: Node = null
var _player: AnimationPlayer = null
var _clip_id: String = ""
var _attachment: Node = null
var _body_camera: Camera3D = null
var _hand_camera: Camera3D = null
var _view_index: int = 0
var _status_label: Label = null
var _equip_result: Dictionary = {}
var _init_error: String = ""
## Test hook: overrides the club resource path (broken-resource smoke case).
var debug_club_path_override: String = ""
var _hud_finger: String = "index"
const HUD_FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const VIEWS: Array[String] = ["BODY", "PALM", "DORSAL", "THUMB", "TIPS"]


func _ready() -> void:
	_build_lighting()
	_build_ground()
	_build_hud()
	await _build_character_club_and_play()


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-20.0, -50.0, 0.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)

	_body_camera = Camera3D.new()
	_body_camera.name = "BodyCamera"
	add_child(_body_camera)
	_body_camera.look_at_from_position(
		Vector3(0.85, 0.45, 0.95), Vector3(0.0, 0.28, 0.05), Vector3.UP
	)
	_body_camera.current = true

	_hand_camera = Camera3D.new()
	_hand_camera.name = "HandCloseupCamera"
	add_child(_hand_camera)
	_hand_camera.current = false


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.6)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.24, 0.26)
	ground.material_override = gmat
	add_child(ground)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "A2PreviewHud"
	layer.layer = 100
	add_child(layer)
	_status_label = Label.new()
	_status_label.name = "A2Status"
	_status_label.position = Vector2(12, 12)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.modulate = Color(0.92, 0.95, 0.85, 1.0)
	layer.add_child(_status_label)


func _build_character_club_and_play() -> void:
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	_model_root.rotation = Vector3(0.0, Native.PREVIEW_MODEL_YAW, 0.0)
	add_child(_model_root)

	var packed: PackedScene = load(Native.UTHANA_TARGET_GLB) as PackedScene
	_character = packed.instantiate() as Node3D
	_character.name = "UthanaWarrior"
	_model_root.add_child(_character)

	var lib: AnimationLibrary = Native.ensure_walking_library()
	if lib == null or not lib.has_animation(Native.WALKING_CLIP):
		_fail_init("native Walking library missing")
		return
	var source_walk: Animation = lib.get_animation(Native.WALKING_CLIP)

	_player = AnimationPlayer.new()
	_player.name = "NativeRetargetAnimationPlayer"
	_character.add_child(_player)
	_clip_id = PlaybackScript.attach_looping_clip(_player, source_walk, Native.WALKING_CLIP)

	var skeleton: Skeleton3D = Native.find_skeleton(_character)
	_player.play(_clip_id)
	_player.seek(0.0, true)
	await get_tree().process_frame
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()

	_model_root.position.y = 0.0
	_ground_contact = Native.sample_sole_ground_contact(
		_character, skeleton, _player, _clip_id, 33
	)
	if not bool(_ground_contact.get("ok", false)):
		_fail_init("skinned sole ground failed: %s" % _ground_contact)
		return
	_ground_offset_y = float(_ground_contact.get("ground_offset_y", 0.0))
	_lowest_sole_y = float(_ground_contact.get("lowest_sole_y", 0.0)) + _ground_offset_y
	_model_root.position.y = _ground_offset_y

	_attachment = AttachmentScript.new()
	_attachment.name = AttachmentScript.CONTROLLER_NAME
	add_child(_attachment)
	if not debug_club_path_override.is_empty():
		_attachment.set_club_path_override(debug_club_path_override)
	var bind: Dictionary = _attachment.bind_to_character(_character)
	if not bool(bind.get("ok", false)):
		_fail_init(
			"bind failed: %s %s"
			% [bind.get("reason", "?"), bind.get("error_class", "")]
		)
		return
	_equip_result = _attachment.equip_club()
	if not bool(_equip_result.get("ok", false)):
		var inv: Dictionary = _equip_result.get("invariants", {})
		_fail_init(
			"equip failed: %s %s %s"
			% [
				_equip_result.get("reason", "?"),
				_equip_result.get("error_class", ""),
				str(inv.get("failures", [])) if not inv.is_empty() else "",
			]
		)
		return

	_playback = PlaybackScript.new()
	_playback.name = "A2PreviewPlayback"
	add_child(_playback)
	_playback.configure(
		[_player],
		[_clip_id],
		[_model_root],
		Native.WALKING_CLIP,
		_ground_offset_y,
		_lowest_sole_y,
		_body_camera,
		null
	)
	_playback.seek_all(0.0, true)
	_update_hand_camera()
	_update_status()
	set_process(true)

	var meta: Dictionary = _attachment.marker_metadata()
	var inv: Dictionary = _attachment.invariants()
	print(
		(
			"uthana_a2_preview: power grip ready confidence=%.3f invariants=%s "
			+ "(1/2/3 speed, Space pause, H view, G grip, D debug, [ ] finger)"
		)
		% [
			float(meta.get("marker_confidence", 0.0)),
			"PASS" if bool(inv.get("pass", false)) else str(inv.get("failures", [])),
		]
	)


func _process(_delta: float) -> void:
	_update_hand_camera()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: InputEventKey = event as InputEventKey
	match key.keycode:
		KEY_1:
			if _playback != null:
				_playback.set_playback_speed(1.0)
			get_viewport().set_input_as_handled()
		KEY_2:
			if _playback != null:
				_playback.set_playback_speed(0.5)
			get_viewport().set_input_as_handled()
		KEY_3:
			if _playback != null:
				_playback.set_playback_speed(0.25)
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			if _playback != null:
				_playback.toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_H:
			_view_index = (_view_index + 1) % VIEWS.size()
			_apply_camera()
			get_viewport().set_input_as_handled()
		KEY_G:
			if _attachment != null:
				_attachment.set_grip_enabled(not _attachment.is_grip_enabled())
			get_viewport().set_input_as_handled()
		KEY_D:
			if _attachment != null:
				_attachment.set_debug_draw(not _attachment.is_debug_draw())
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:
			_cycle_hud_finger(-1)
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			_cycle_hud_finger(1)
			get_viewport().set_input_as_handled()


func _cycle_hud_finger(dir: int) -> void:
	var i: int = HUD_FINGERS.find(_hud_finger)
	if i < 0:
		i = 1
	i = (i + dir + HUD_FINGERS.size()) % HUD_FINGERS.size()
	_hud_finger = HUD_FINGERS[i]
	if _attachment != null and _attachment.grip_modifier() != null:
		_attachment.grip_modifier().debug_selected_finger = _hud_finger


func _apply_camera() -> void:
	if _body_camera == null or _hand_camera == null:
		return
	var body: bool = VIEWS[_view_index] == "BODY"
	_body_camera.current = body
	_hand_camera.current = not body


## F6 acceptance views from the live anatomical frame:
## PALM (+V), DORSAL (-V), THUMB (radial +A), TIPS (+L).
func _update_hand_camera() -> void:
	if _hand_camera == null or _attachment == null or not _attachment.has_club():
		return
	var frame: Dictionary = _attachment.live_hand_frame()
	if not bool(frame.get("ok", false)):
		return
	var palm: Vector3 = frame["palm_centre"]
	var a: Vector3 = frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var dist := 0.17
	var cam_pos: Vector3 = palm
	match VIEWS[_view_index]:
		"PALM":
			cam_pos = palm + v * dist
		"DORSAL":
			cam_pos = palm - v * dist
		"THUMB":
			cam_pos = palm + a * dist
		"TIPS":
			cam_pos = palm + l * dist
		_:
			cam_pos = palm + v * dist
	var up: Vector3 = Vector3.UP
	if absf((palm - cam_pos).normalized().dot(up)) > 0.9:
		up = l
	_hand_camera.look_at_from_position(cam_pos, palm, up)


func _fail_init(msg: String) -> void:
	_init_error = msg
	push_error("uthana_a2_preview: %s" % msg)
	_update_status()


func init_error() -> String:
	return _init_error


func _update_status() -> void:
	if _status_label == null:
		return
	if not _init_error.is_empty():
		_status_label.modulate = Color(1.0, 0.25, 0.2, 1.0)
		_status_label.text = (
			"A2 PREVIEW INIT FAILED — NO CLUB\n%s\n(fix required; grip inspection impossible)"
			% _init_error
		)
		return
	var speed := 1.0
	var paused := false
	if _playback != null:
		speed = float(_playback.playback_speed())
		paused = bool(_playback.is_playback_paused())
	var grip_on := false
	var conf := 0.0
	var inv_line := "Frame: —"
	var contact_line := "Contact: —"
	var finger_line := "%s gap: — | penetration: — | delta: —" % _hud_finger.capitalize()
	if _attachment != null:
		grip_on = _attachment.is_grip_enabled()
		conf = float(_attachment.marker_metadata().get("marker_confidence", 0.0))
		var inv: Dictionary = _attachment.measure_grip_invariants()
		inv_line = (
			"Frame %s: dotA=%.2f dotL=%.2f dotV=%.2f det=%+.0f volar=%.2fr"
			% [
				"PASS" if bool(inv.get("pass", false)) else "FAIL %s" % str(inv.get("failures", [])),
				float(inv.get("dot_da", 0.0)),
				float(inv.get("dot_dl", 0.0)),
				float(inv.get("dot_dv", 0.0)),
				float(inv.get("det_socket", 0.0)),
				float(inv.get("volar_offset_radii", 0.0)),
			]
		)
		var grip = _attachment.grip_modifier()
		if grip != null and grip_on:
			var diag: Dictionary = grip.last_diagnostics()
			contact_line = (
				"Contact: coverage %.0f° | thumb opposition %.2f | order %s"
				% [
					float(diag.get("coverage_deg", 0.0)),
					float(diag.get("opposition_dot", 0.0)),
					"OK" if bool(diag.get("ordering_ok", false)) else "BAD",
				]
			)
			var fd: Dictionary = grip.finger_diagnostic(_hud_finger)
			if not fd.is_empty():
				finger_line = (
					"%s gap: %.4f | penetration: %.4f | delta: %+.2f | %s"
					% [
						_hud_finger.capitalize(),
						float(fd.get("gap_final", 0.0)),
						float(fd.get("penetration_final", 0.0)),
						float(fd.get("refine_delta", 0.0)),
						str(fd.get("classification", "")),
					]
				)
	var grip_txt := "Grip ON" if grip_on else "Grip OFF"
	if paused:
		grip_txt = "PAUSED / " + grip_txt
	var dbg := ""
	if _attachment != null and _attachment.is_debug_draw():
		dbg = " | DEBUG"
	_status_label.text = (
		"Walking — %.2fx — %s — marker confidence %.2f%s\n%s\n%s\n%s\nView: %s | Keys: 1/2/3 Space H G D [ ]"
	) % [speed, grip_txt, conf, dbg, inv_line, contact_line, finger_line, VIEWS[_view_index]]


func attachment() -> Node:
	return _attachment


func equip_result() -> Dictionary:
	return _equip_result.duplicate(true)


func ground_offset_y() -> float:
	return _ground_offset_y


func preview_player() -> AnimationPlayer:
	return _player


func preview_clip_id() -> String:
	return _clip_id
