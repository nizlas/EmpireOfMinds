# Isolated A2.8 bilateral diagnostic: same pipeline, RIGHT vs LEFT.
# Does not replace uthana_a2_walking_preview.tscn (accepted right A2.7).
extends Node3D

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const PlaybackScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_preview_playback.gd"
)
const Composition = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_equipment_composition.gd"
)

const SIDE_OFFSET := 0.22
const VIEWS: Array[String] = ["BOTH", "RIGHT", "LEFT"]

var _focus: int = 0
var _status: Label = null
var _body_cam: Camera3D = null
var _rows: Array[Dictionary] = []


func _ready() -> void:
	_build_lights()
	_build_hud()
	await _build_pair()
	_apply_camera()
	_update_hud()
	set_process(true)


func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -50.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 1.6)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.26)
	ground.material_override = mat
	add_child(ground)
	_body_cam = Camera3D.new()
	add_child(_body_cam)
	_body_cam.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(12, 12)
	_status.add_theme_font_size_override("font_size", 18)
	_status.modulate = Color(0.92, 0.95, 0.85, 1.0)
	layer.add_child(_status)


func _build_pair() -> void:
	var lib: AnimationLibrary = Native.ensure_walking_library()
	var packed: PackedScene = load(Native.UTHANA_TARGET_GLB) as PackedScene
	for side in ["right", "left"]:
		var x: float = -SIDE_OFFSET if side == "right" else SIDE_OFFSET
		var root := Node3D.new()
		root.name = "Side_%s" % side
		root.position = Vector3(x, 0.0, 0.0)
		add_child(root)
		var model := Node3D.new()
		model.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
		model.rotation = Vector3(0.0, Native.PREVIEW_MODEL_YAW, 0.0)
		root.add_child(model)
		var character: Node3D = packed.instantiate() as Node3D
		character.name = "Uthana_%s" % side
		model.add_child(character)
		var player := AnimationPlayer.new()
		character.add_child(player)
		var clip: String = PlaybackScript.attach_looping_clip(
			player, lib.get_animation(Native.WALKING_CLIP), Native.WALKING_CLIP
		)
		player.play(clip)
		player.seek(0.35, true)
		await get_tree().process_frame
		var sk: Skeleton3D = Native.find_skeleton(character)
		if sk != null:
			sk.force_update_all_bone_transforms()
		var asm: Node = Composition.make_assembler()
		asm.name = "EquipmentAssembler_%s" % side
		root.add_child(asm)
		var result: Dictionary = asm.assemble(character, side)
		var tag := Label3D.new()
		tag.text = side.to_upper()
		tag.font_size = 48
		tag.position = Vector3(0.0, 0.55, 0.0)
		tag.modulate = Color(1.0, 0.92, 0.35) if side == "right" else Color(0.55, 0.85, 1.0)
		root.add_child(tag)
		_rows.append({
			"side": side,
			"root": root,
			"character": character,
			"assembler": asm,
			"result": result,
			"player": player,
		})
		print(
			"uthana_a2_bilateral: %s assemble ok=%s class=%s"
			% [side, str(result.get("ok")), str(result.get("error_class", ""))]
		)


func _process(_delta: float) -> void:
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: InputEventKey = event as InputEventKey
	match key.keycode:
		KEY_H, KEY_TAB:
			_focus = (_focus + 1) % VIEWS.size()
			_apply_camera()
		KEY_R:
			_focus = 1
			_apply_camera()
		KEY_L:
			_focus = 2
			_apply_camera()
		KEY_SPACE:
			for row in _rows:
				var p: AnimationPlayer = row["player"]
				p.speed_scale = 0.0 if p.speed_scale > 0.0 else 1.0


func _apply_camera() -> void:
	var view: String = VIEWS[_focus]
	var look := Vector3(0.0, 0.28, 0.05)
	var from := Vector3(0.0, 0.42, 0.95)
	if view == "RIGHT":
		look = Vector3(-SIDE_OFFSET, 0.28, 0.05)
		from = Vector3(-SIDE_OFFSET + 0.35, 0.38, 0.55)
	elif view == "LEFT":
		look = Vector3(SIDE_OFFSET, 0.28, 0.05)
		from = Vector3(SIDE_OFFSET - 0.35, 0.38, 0.55)
	_body_cam.look_at_from_position(from, look, Vector3.UP)


func _update_hud() -> void:
	if _status == null:
		return
	var lines := PackedStringArray()
	lines.append("A2.8 bilateral  view=%s  (H/Tab cycle, R/L focus, Space pause)" % VIEWS[_focus])
	for row in _rows:
		var r: Dictionary = row["result"]
		var side: String = str(row["side"]).to_upper()
		var ok := "PASS" if bool(r.get("ok", false)) else str(r.get("error_class", "FAIL"))
		lines.append("%s  %s  %s" % [side, ok, str(r.get("reason", ""))])
	_status.text = "\n".join(lines)
