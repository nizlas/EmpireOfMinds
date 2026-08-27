# Isolated A2 preview: A1 Walking + wooden club + power_grip_1h_v1.
# A2.9: the RUNTIME EQUIPMENT OWNER is the generic EquipmentAssembler,
# configured by the Uthana composition root (family/fixture/club/engine
# injected). The legacy uthana_a2_club_attachment.gd path is no longer
# instantiated here — it remains only as the parity/diagnostic fixture in
# the tests. Does not modify A1 assets, imports, or Walking data.
# H cycles body/palm/dorsal/thumb/tips views.
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
## A2.10 CALIBRATION ONLY: the hand-authored A2.7 fixture is loaded here so
## this development preview can show compiled-vs-authored side by side. The
## runtime equipment path uses the compiled artifact via the composition and
## never reads this.
const Oracle = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_warrior_hand_fixture.gd"
)

const ASSEMBLER_NODE_NAME := "UthanaA2EquipmentAssembler"
const DEBUG_LAYER_NAME := "A2GripDebugLayer"

var _model_root: Node3D = null
var _character: Node3D = null
var _ground_offset_y: float = 0.0
var _lowest_sole_y: float = 0.0
var _ground_contact: Dictionary = {}
var _playback: Node = null
var _player: AnimationPlayer = null
var _clip_id: String = ""
var _assembler: Node = null
var _body_camera: Camera3D = null
var _hand_camera: Camera3D = null
var _view_index: int = 0
var _status_label: Label = null
var _equip_result: Dictionary = {}
var _init_error: String = ""
## One-shot skinned thumb-tip isolation diagnostic (A2.4), measured after
## equip; the residual hover is a documented low-poly asset limitation.
var _tip_isolation: Dictionary = {}
## Test hook: overrides the club resource path (broken-resource smoke case).
var debug_club_path_override: String = ""
var _hud_finger: String = "index"
var _debug_draw := false
var _debug_layer: Node3D = null
const HUD_FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const VIEWS: Array[String] = [
	"BODY", "PALM", "DORSAL", "THUMB", "TIPS", "THUMB_AXIS", "THUMB_DORSAL",
	"THUMB_CONTACT",
]


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

	# A2.9: the generic assembler (with the Uthana composition root's
	# injected family/fixture/club/engine) is the runtime equipment owner.
	_assembler = Composition.make_assembler()
	_assembler.name = ASSEMBLER_NODE_NAME
	add_child(_assembler)
	if not debug_club_path_override.is_empty():
		_assembler.set_club_path_override(debug_club_path_override)
	_equip_result = _assembler.assemble(_character, "right")
	if not bool(_equip_result.get("ok", false)):
		var inv: Dictionary = _equip_result.get("invariants", {})
		var detail := ""
		if not inv.is_empty():
			detail = str(inv.get("failures", []))
		var grip_r: Dictionary = _equip_result.get("grip", {})
		if grip_r.has("thumb_wrap_failures"):
			detail += " thumb:%s" % str(grip_r.get("thumb_wrap_failures", []))
		if not (grip_r.get("thumb_contour_failures", []) as Array).is_empty():
			detail += " contour:%s" % str(grip_r.get("thumb_contour_failures", []))
		_fail_init(
			"equip failed: %s %s %s"
			% [
				_equip_result.get("reason", "?"),
				_equip_result.get("error_class", ""),
				detail,
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
	var grip_mod = _assembler.grip_modifier()
	if grip_mod != null:
		grip_mod.apply_now()
		_tip_isolation = grip_mod.measure_tip_isolation(_character)
		grip_mod.run_contour_gate(_character)
		grip_mod.run_surface_truth_gate()
	_update_hand_camera()
	_update_status()
	set_process(true)

	var meta: Dictionary = _assembler.marker_metadata()
	var inv2: Dictionary = _assembler.invariants()
	print(
		(
			"uthana_a2_preview: power grip ready confidence=%.3f invariants=%s "
			+ "owner=EquipmentAssembler "
			+ "(1/2/3 speed, Space pause, H view, G grip, D debug, [ ] finger)"
		)
		% [
			float(meta.get("marker_confidence", 0.0)),
			"PASS" if bool(inv2.get("pass", false)) else str(inv2.get("failures", [])),
		]
	)


## A2.9 runtime-ownership witness for tests and HUD.
func equipment_owner() -> String:
	return "equipment_assembler"


func _process(_delta: float) -> void:
	# Re-measure the ground-truth surface gate against the CURRENT frame's
	# achieved pose (the club follows the wrist every frame, so the pose
	# stamp changes per frame; the measurement is 14 skinned triangles).
	if _assembler != null and _assembler.is_grip_enabled():
		var g = _assembler.grip_modifier()
		if g != null and is_instance_valid(g):
			g.run_surface_truth_gate()
	_update_hand_camera()
	_update_status()
	if _debug_draw:
		_update_debug_layer()


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
			if _assembler != null:
				_assembler.set_grip_enabled(not _assembler.is_grip_enabled())
				var g = _assembler.grip_modifier()
				if _assembler.is_grip_enabled() and g != null and is_instance_valid(g):
					g.run_contour_gate(_character)
					g.run_surface_truth_gate()
			get_viewport().set_input_as_handled()
		KEY_D:
			set_debug_draw(not _debug_draw)
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:
			_cycle_hud_finger(-1)
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			_cycle_hud_finger(1)
			get_viewport().set_input_as_handled()


func set_debug_draw(enabled: bool) -> void:
	_debug_draw = enabled
	if not enabled and _debug_layer != null:
		_debug_layer.queue_free()
		_debug_layer = null


func is_debug_draw() -> bool:
	return _debug_draw


func _cycle_hud_finger(dir: int) -> void:
	var i: int = HUD_FINGERS.find(_hud_finger)
	if i < 0:
		i = 1
	i = (i + dir + HUD_FINGERS.size()) % HUD_FINGERS.size()
	_hud_finger = HUD_FINGERS[i]
	if _assembler != null and _assembler.grip_modifier() != null:
		_assembler.grip_modifier().debug_selected_finger = _hud_finger


func _apply_camera() -> void:
	if _body_camera == null or _hand_camera == null:
		return
	var body: bool = VIEWS[_view_index] == "BODY"
	_body_camera.current = body
	_hand_camera.current = not body


func _active_end_world() -> Vector3:
	var analysis: Dictionary = _assembler.weapon_analysis()
	var target_len: float = float(analysis.get("target_length", 0.0))
	var frac: float = float(analysis.get("grip_fraction", 0.12))
	var socket: Node3D = _assembler.club_socket()
	if socket == null:
		return Vector3.ZERO
	var offset: Node3D = socket.get_node_or_null("SocketOffset") as Node3D
	if offset == null:
		return Vector3.ZERO
	return offset.to_global(Vector3(0.0, (1.0 - frac) * target_len, 0.0))


func _grip_end_world() -> Vector3:
	var analysis: Dictionary = _assembler.weapon_analysis()
	var target_len: float = float(analysis.get("target_length", 0.0))
	var frac: float = float(analysis.get("grip_fraction", 0.12))
	var socket: Node3D = _assembler.club_socket()
	if socket == null:
		return Vector3.ZERO
	var offset: Node3D = socket.get_node_or_null("SocketOffset") as Node3D
	if offset == null:
		return Vector3.ZERO
	return offset.to_global(Vector3(0.0, -frac * target_len, 0.0))


## F6 acceptance views from the live anatomical frame:
## PALM (+V), DORSAL (-V), THUMB (radial +A), TIPS (+L),
## THUMB_AXIS (looking along the club shaft toward the hand),
## THUMB_DORSAL (radial outside at the TRUE nail patch station, A2.7),
## THUMB_CONTACT (side-on at the Thumb2 middle-gap station, A2.6).
func _update_hand_camera() -> void:
	if _hand_camera == null or _assembler == null or not _assembler.has_club():
		return
	var frame: Dictionary = _assembler.live_hand_frame()
	if not bool(frame.get("ok", false)):
		return
	var palm: Vector3 = frame["palm_centre"]
	var a: Vector3 = frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var dist := 0.17
	var cam_pos: Vector3 = palm
	var target: Vector3 = palm
	match VIEWS[_view_index]:
		"PALM":
			cam_pos = palm + v * dist
		"DORSAL":
			cam_pos = palm - v * dist
		"THUMB":
			cam_pos = palm + a * dist
		"TIPS":
			cam_pos = palm + l * dist
		"THUMB_AXIS":
			var socket: Node3D = _assembler.club_socket()
			if socket != null:
				var offset: Node3D = socket.get_node_or_null("SocketOffset") as Node3D
				if offset != null:
					var axis_d: Vector3 = offset.global_transform.basis.y.normalized()
					target = offset.global_transform.origin
					cam_pos = target + axis_d * dist
		"THUMB_CONTACT":
			var socket3: Node3D = _assembler.club_socket()
			var grip3 = _assembler.grip_modifier()
			if socket3 != null and grip3 != null and is_instance_valid(grip3):
				var offset3: Node3D = socket3.get_node_or_null("SocketOffset") as Node3D
				var contour3: Dictionary = grip3.last_contour()
				var t2p: Dictionary = (
					contour3.get("patches", {}) as Dictionary
				).get("t2", {})
				if offset3 != null and t2p.has("centroid"):
					var o3: Vector3 = offset3.global_transform.origin
					var d3: Vector3 = offset3.global_transform.basis.y.normalized()
					var c3: Vector3 = t2p["centroid"]
					var w3: Vector3 = c3 - o3
					var rad3: Vector3 = w3 - d3 * w3.dot(d3)
					if rad3.length_squared() > 1e-12:
						target = (c3 + o3 + d3 * w3.dot(d3)) * 0.5
						cam_pos = target + d3.cross(rad3.normalized()) * dist * 0.7
		"THUMB_DORSAL":
			var socket2: Node3D = _assembler.club_socket()
			var grip2 = _assembler.grip_modifier()
			if socket2 != null and grip2 != null and is_instance_valid(grip2):
				var offset2: Node3D = socket2.get_node_or_null("SocketOffset") as Node3D
				var surf2: Dictionary = grip2.last_surface()
				var nail2: Dictionary = surf2.get("nail", {})
				var tip: Vector3 = Vector3.ZERO
				if nail2.has("c_agg"):
					tip = nail2["c_agg"]
				else:
					var tw2: Dictionary = grip2.last_diagnostics().get("thumb", {})
					if tw2.has("pad_final"):
						tip = tw2["pad_final"]
				if offset2 != null and tip != Vector3.ZERO:
					var o2: Vector3 = offset2.global_transform.origin
					var d2: Vector3 = offset2.global_transform.basis.y.normalized()
					var w2: Vector3 = tip - o2
					var rad2: Vector3 = w2 - d2 * w2.dot(d2)
					if rad2.length_squared() > 1e-12:
						target = tip
						cam_pos = tip + rad2.normalized() * dist * 0.8
		_:
			cam_pos = palm + v * dist
	var up: Vector3 = Vector3.UP
	if absf((target - cam_pos).normalized().dot(up)) > 0.9:
		up = l
	_hand_camera.look_at_from_position(cam_pos, target, up)


## A2.3 thumb status: socket provenance, windings (R1), direction (R7),
## anatomy (R5/R6/R8/R9), shaft contact (R3), approach (R4). Thumb-to-
## finger distances are DIAGNOSTICS — no physical finger contact required.
func _thumb_status_line() -> String:
	if _assembler == null:
		return "Thumb: —"
	var grip = _assembler.grip_modifier()
	if grip == null or not is_instance_valid(grip):
		return "Thumb: —"
	var diag: Dictionary = grip.last_diagnostics()
	var tw: Dictionary = diag.get("thumb_wrap", {})
	var twg: Dictionary = diag.get("thumb_wrap_gate", {})
	if tw.is_empty():
		return "Thumb: —"
	var gap_s: float = float(tw.get("gap_final_signed", 0.0))
	var approach := "closing"
	if float(tw.get("approach_axial_fraction", 0.0)) > grip.THUMB_APPROACH_AXIAL_FRAC_MAX:
		approach = "AXIAL-DRIFT"
	elif float(tw.get("approach_radial_radii", 0.0)) > grip.THUMB_APPROACH_RADIAL_MAX_RADII:
		approach = "OUTWARD"
	var mcp_flex: float = float(tw.get("mcp_flex_deg", 0.0))
	var ip_flex: float = float(tw.get("ip_flex_deg", 0.0))
	var s_ok: bool = not (
		(mcp_flex > 15.0 and ip_flex < -5.0) or (mcp_flex < -5.0 and ip_flex > 15.0)
	)
	# Read the socket mapping off the policy the assembler actually resolved,
	# so the HUD cannot drift from the policy that ran.
	var active_policy: Script = _assembler.policy_script()
	var socket_line := (
		"Socket KEPT (generic assembler, %s): distal shift %.2fh | kappa %.0f° | transversality %.3f"
		% [
			str(_assembler.last_result().get("policy", "?")),
			float(active_policy.DISTAL_SHIFT_HAND),
			float(active_policy.KAPPA_DEG),
			absf(float(_assembler.measure_grip_invariants().get("dot_da", 0.0))),
		]
	)
	var t2f: Dictionary = tw.get("thumb_to_finger_pads_r", {})
	var tip_cls := "n/a"
	if not _tip_isolation.is_empty():
		var iso: float = float(_tip_isolation.get("isolation_excess_r", 0.0))
		if iso < 0.10:
			tip_cls = "SMOOTH (%.2fr)" % iso
		elif iso < 0.25:
			tip_cls = "MILD %.2fr (low-poly asset limit)" % iso
		else:
			tip_cls = "ISOLATED %.2fr" % iso
	var nail_cls := "n/a (compiled diagnostic only)"
	if tw.has("nail_out_dot"):
		var no2: float = float(tw.get("nail_out_dot", -9.0))
		var pi2: float = float(tw.get("pad_in_dot", -9.0))
		if no2 >= 0.3 and pi2 >= 0.3:
			nail_cls = "rigid diag ok"
		elif no2 < 0.0:
			nail_cls = "rigid diag INWARD"
		else:
			nail_cls = "rigid diag ambiguous"
	var line := (
		"%s\nThumb %s: Wf %+.0f° | Wt %+.0f° | dir %s | shaft gap %.4f pen %.4f | along %.2fr (idx %.2fr) | app %s\n"
		+ "CMC twist %+.0f° (opposition pronation) | MCP flex %+.0f° | IP flex %+.0f° | IP tw %+.0f° | S-curve %s | tip lobe %s | %s\n"
		+ "NAIL: out %+.2f | axis %.2f | pad-in %+.2f | roll %+.0f° | %s\n"
		+ "t->fingers (diag, no contact required): idx %.1fr mid %.1fr ring %.1fr pink %.1fr"
	) % [
		socket_line,
		"PASS" if bool(twg.get("pass", false)) else "FAIL",
		float(tw.get("winding_finger_median_deg", 0.0)),
		float(tw.get("winding_thumb_deg", 0.0)),
		str(tw.get("direction_class", "?")),
		maxf(gap_s, 0.0),
		maxf(-gap_s, 0.0),
		float(tw.get("pad_along_r", 0.0)),
		float(tw.get("station_index_r", 0.0)),
		approach,
		float(tw.get("cmc_twist_deg", 0.0)),
		mcp_flex,
		ip_flex,
		float(tw.get("ip_twist_deg", 0.0)),
		"OK" if s_ok else "FAIL",
		tip_cls,
		str(tw.get("classification", "")),
		float(tw.get("nail_out_dot", -9.0)),
		float(tw.get("nail_axis_dot", 9.0)),
		float(tw.get("pad_in_dot", -9.0)),
		float(tw.get("distal_roll_deg", 999.0)),
		nail_cls,
		float(t2f.get("index", 0.0)),
		float(t2f.get("middle", 0.0)),
		float(t2f.get("ring", 0.0)),
		float(t2f.get("pinky", 0.0)),
	]
	if not bool(twg.get("pass", false)):
		line += "\nFAILED: %s" % str(twg.get("failures", []))
	line += "\n" + _contour_status_line(grip)
	line += "\n" + _surface_status_line(grip)
	line += "\n" + _fixture_provenance_line()
	return line


## A2.7 ground-truth HUD: deformed skinned nail/pad patch geometry at the
## final achieved pose (the acceptance ground truth — the rigid NAIL line
## above is a compiled diagnostic only).
func _surface_status_line(grip) -> String:
	var surface: Dictionary = grip.last_surface()
	var sgate: Dictionary = grip.last_surface_gate()
	if not bool(surface.get("ok", false)):
		return "GeomTruth: — (%s)" % str(sgate.get("failures", ["not measured"]))
	var nail: Dictionary = surface.get("nail", {})
	var pad: Dictionary = surface.get("pad", {})
	var fresh: bool = str(surface.get("pose_stamp", "")) == str(grip.pose_stamp())
	var line := (
		"GeomTruth %s: NAIL_GEOM out %+.2f axis %.2f gap %+.2fr (%d tris) | "
		+ "PAD_GEOM in %+.2f gap %+.2fr (%d tris)\n"
		+ "phys distal roll %+.0f° | closest %s | pose %s | legacy(A2.5 path) "
		+ "nail_out %+.2f [superseded diagnostic]"
	) % [
		"PASS" if bool(sgate.get("pass", false)) else "FAIL",
		float(surface.get("nail_out_geom", -9.0)),
		float(surface.get("nail_axis_geom", 9.0)),
		float(nail.get("min_gap_r", 9.0)), int(nail.get("tris", 0)),
		float(surface.get("pad_in_geom", -9.0)),
		float(pad.get("min_gap_r", 9.0)), int(pad.get("tris", 0)),
		float(surface.get("distal_phys_roll_deg", 999.0)),
		str(surface.get("closest_patch", "?")),
		"FRESH" if fresh else "STALE",
		float(surface.get("legacy_nail_out", -9.0)),
	]
	if not bool(sgate.get("pass", false)):
		line += "\nGEOM FAILED: %s" % str(sgate.get("failures", []))
	return line


## A2.10 DEVELOPMENT diagnostic: which patches the fixture compiler chose
## automatically, with what confidence, on what evidence, and how the
## compiled artifact compares with the hand-authored A2.7 oracle.
##
## This is calibration read-out only. Nothing here is a production approval
## step: an ingested asset is accepted or fail-closed by the compiler and the
## grip gates without anyone reading this HUD.
func _fixture_provenance_line() -> String:
	var fx = _assembler.fixture_script() if _assembler.has_method("fixture_script") else null
	if fx == null:
		return "Fixture: —"
	var schema := str(fx.SCHEMA_VERSION)
	if not fx.has_method("evidence_for_side"):
		return "Fixture: %s (hand-authored reference)" % schema
	var art: Dictionary = fx.artifact
	var ev: Dictionary = fx.evidence_for_side("right")
	var conf: Dictionary = fx.confidence_for_side("right")
	var surf: Dictionary = fx.surface_for_side("right", null, null)
	var nail_n: Vector3 = surf.get("nail_normal_local", Vector3.ZERO)
	var pad_n: Vector3 = surf.get("pad_normal_local", Vector3.ZERO)
	var oracle: Dictionary = Oracle.right_surface()
	var on: Vector3 = oracle["nail_normal_local"]
	var op: Vector3 = oracle["pad_normal_local"]
	return (
		"Fixture COMPILED %s / %s: auto nail %d tris, pad %d tris "
		+ "from %d candidates in %d components (%d qualified)\n"
		+ "confidence overall %.3f (nail %.3f pad %.3f component %.3f bone-weight %.3f) "
		+ "| signals %s | texture signals %s\n"
		+ "rest normals nail %s pad %s | rest nail·pad %+.4f | winding stored per triangle\n"
		+ "vs authored A2.7 oracle: nail dot %.6f pad dot %.6f | mesh %s… | hash %s…"
	) % [
		str(art.get("compiler_version", "?")), schema,
		(surf.get("nail_tris", []) as Array).size(),
		(surf.get("pad_tris", []) as Array).size(),
		int(ev.get("candidate_triangles", 0)),
		int(ev.get("components", 0)),
		int(ev.get("qualified_components", 0)),
		float(conf.get("overall", 0.0)), float(conf.get("nail", 0.0)),
		float(conf.get("pad", 0.0)), float(conf.get("component", 0.0)),
		float(conf.get("bone_weight", 0.0)),
		str(ev.get("classification_signals", [])),
		"none" if (ev.get("texture_signals_used", []) as Array).is_empty() else "USED",
		str(nail_n), str(pad_n), float(surf.get("rest_nail_pad_dot", 0.0)),
		nail_n.dot(on), pad_n.dot(op),
		str(art.get("source_mesh_sha256", "")).substr(0, 8),
		str(art.get("content_hash", "")).substr(0, 8),
	]


## A2.6 distributed-contour HUD: per-patch skinned volar gaps, isolated
## middle excess over the contact corridor, bulge, continuity, curvature.
func _contour_status_line(grip) -> String:
	var contour: Dictionary = grip.last_contour()
	var cgate: Dictionary = grip.last_contour_gate()
	if not bool(contour.get("ok", false)):
		return "Contour: — (%s)" % str(cgate.get("failures", ["not measured"]))
	var patches: Dictionary = contour.get("patches", {})
	var cmc: Dictionary = patches.get("cmc", {})
	var t2: Dictionary = patches.get("t2", {})
	var t3: Dictionary = patches.get("t3", {})
	var line := (
		"Contour %s: CMC %.2f/%.2fr | T2 %.2f/%.2fr | T3 %.2f/%.2fr | pad %.2fr\n"
		+ "mid-excess %.2fr (max %.2f) | bulge %.2fr | kink %+.2fr | jump %.0f° | %s %s"
	) % [
		"PASS" if bool(cgate.get("pass", false)) else "FAIL",
		float(cmc.get("min_r", 9.0)), float(cmc.get("med_r", 9.0)),
		float(t2.get("min_r", 9.0)), float(t2.get("med_r", 9.0)),
		float(t3.get("min_r", 9.0)), float(t3.get("med_r", 9.0)),
		float(contour.get("pad_gap_r", 9.0)),
		float(contour.get("mid_excess_r", 9.0)),
		grip.CONTOUR_MID_EXCESS_MAX_R,
		float(contour.get("bulge_r", 9.0)),
		float(contour.get("kink_out_r", 9.0)),
		float(contour.get("max_jump_deg", 0.0)),
		"monotone" if bool(contour.get("monotonic_ok", false)) else "NON-MONOTONIC",
		"" if bool(cgate.get("pass", false)) else str(cgate.get("failures", [])),
	]
	return line


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
		var dbg_line := "(fix required; grip inspection impossible)"
		if _assembler != null and _assembler.has_club():
			# Gate failure: the failed pose stays visible for debugging,
			# but it is a rejected grip — never accepted.
			dbg_line = "GRIP REJECTED — debug view only\n%s" % _thumb_status_line()
		_status_label.text = (
			"A2 PREVIEW FAILED — %s\n%s"
			% [_init_error, dbg_line]
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
	var thumb_line := "Thumb wrap: —"
	var finger_line := "%s gap: — | penetration: — | delta: —" % _hud_finger.capitalize()
	if _assembler != null:
		grip_on = _assembler.is_grip_enabled()
		conf = float(_assembler.marker_metadata().get("marker_confidence", 0.0))
		var inv: Dictionary = _assembler.measure_grip_invariants()
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
		var grip = _assembler.grip_modifier()
		if grip != null and grip_on:
			var diag: Dictionary = grip.last_diagnostics()
			contact_line = (
				"Coverage %.0f° (thumb-independent) | opp-dot %+.2f (diagnostic only) | order %s"
				% [
					float(diag.get("coverage_deg", 0.0)),
					float(diag.get("opposition_dot", 0.0)),
					"OK" if bool(diag.get("ordering_ok", false)) else "BAD",
				]
			)
			thumb_line = _thumb_status_line()
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
	if _debug_draw:
		dbg = " | DEBUG"
	_status_label.text = (
		"Walking — %.2fx — %s — owner: EquipmentAssembler (generic) — marker confidence %.2f%s\n%s\n%s\n%s\n%s\nView: %s | Keys: 1/2/3 Space H G D [ ]"
	) % [
		speed, grip_txt, conf, dbg, inv_line, contact_line, thumb_line, finger_line,
		VIEWS[_view_index],
	]


## Preview-owned debug layer (A2.9: moved here from the legacy attachment;
## reads the same engine diagnostics through the generic assembler).
func _update_debug_layer() -> void:
	if _assembler == null or not _assembler.has_club():
		return
	if _debug_layer == null or not is_instance_valid(_debug_layer):
		_debug_layer = Node3D.new()
		_debug_layer.name = DEBUG_LAYER_NAME
		add_child(_debug_layer)
	for c in _debug_layer.get_children():
		c.queue_free()
	var frame: Dictionary = _assembler.live_hand_frame()
	if bool(frame.get("ok", false)):
		var p: Vector3 = frame["palm_centre"]
		_add_debug_sphere(_debug_layer, p, Color(1.0, 0.2, 0.8), 0.004)
		_add_debug_line(_debug_layer, p, p + (frame["volar"] as Vector3) * 0.03, Color(0.2, 1.0, 0.4))
		_add_debug_line(_debug_layer, p, p + (frame["across"] as Vector3) * 0.03, Color(1.0, 0.3, 0.2))
	var axis_o: Vector3 = _assembler.primary_grip_world()
	var axis_d: Vector3 = (_active_end_world() - _grip_end_world()).normalized()
	_add_debug_sphere(_debug_layer, axis_o, Color(0.95, 0.85, 0.1), 0.004)
	_add_debug_line(_debug_layer, axis_o - axis_d * 0.04, axis_o + axis_d * 0.08, Color(0.2, 0.7, 1.0))
	var grip = _assembler.grip_modifier()
	if grip == null:
		return
	var diag: Dictionary = grip.last_diagnostics()
	for finger in ["thumb", "index", "middle", "ring", "pinky"]:
		var fd: Dictionary = diag.get(finger, {})
		if fd.has("pad_final"):
			_add_debug_sphere(_debug_layer, fd["pad_final"], Color(0.2, 1.0, 0.4), 0.003)
	_draw_contour_debug(grip, diag)
	_draw_surface_truth_debug(grip)


func _draw_surface_truth_debug(grip) -> void:
	var tris: Dictionary = grip.surface_debug_triangles()
	var surface: Dictionary = grip.last_surface()
	if tris.is_empty():
		return
	var colors := {
		"nail": Color(1.0, 0.15, 0.95),
		"pad": Color(0.15, 0.95, 1.0),
	}
	for patch in ["nail", "pad"]:
		var col: Color = colors[patch]
		for tri_v in (tris.get(patch, []) as Array):
			var pts: Array = tri_v
			for k in 3:
				_add_debug_line(
					_debug_layer, pts[k] as Vector3, pts[(k + 1) % 3] as Vector3, col
				)
		var pd: Dictionary = surface.get(patch, {})
		if pd.has("c_agg") and pd.has("n_agg"):
			_add_debug_line(
				_debug_layer,
				pd["c_agg"] as Vector3,
				(pd["c_agg"] as Vector3) + (pd["n_agg"] as Vector3) * 0.02,
				col
			)
	var nail_pd: Dictionary = surface.get("nail", {})
	if nail_pd.has("c_agg"):
		var o: Vector3 = _assembler.primary_grip_world()
		var d: Vector3 = (_active_end_world() - _grip_end_world()).normalized()
		var c: Vector3 = nail_pd["c_agg"]
		var w: Vector3 = c - o
		var foot: Vector3 = o + d * w.dot(d)
		var radial: Vector3 = c - foot
		if radial.length_squared() > 1e-14:
			_add_debug_line(
				_debug_layer, foot, foot + radial.normalized() * 0.03,
				Color(0.2, 1.0, 0.3)
			)
		_add_debug_line(
			_debug_layer, foot - d * 0.03, foot + d * 0.03, Color(0.95, 0.85, 0.1)
		)


func _draw_contour_debug(grip, diag: Dictionary) -> void:
	var contour: Dictionary = grip.last_contour()
	if not bool(contour.get("ok", false)):
		return
	var patches: Dictionary = contour.get("patches", {})
	var colors := {
		"cmc": Color(1.0, 0.55, 0.15),
		"t2": Color(0.35, 0.65, 1.0),
		"t3": Color(0.85, 0.35, 1.0),
	}
	var poly: Array[Vector3] = []
	for key in ["cmc", "t2", "t3"]:
		var patch: Dictionary = patches.get(key, {})
		if not patch.has("centroid"):
			return
		var centroid: Vector3 = patch["centroid"]
		var min_p: Vector3 = patch["min_p"]
		_add_debug_sphere(_debug_layer, centroid, colors[key], 0.0025)
		var surf: Vector3 = grip.shaft_surface_point(min_p)
		var g: float = float(patch.get("min_r", 9.0))
		var gap_col := Color(0.2, 1.0, 0.3)
		if g > 0.35 or g < -0.30:
			gap_col = Color(1.0, 0.2, 0.15)
		elif g > 0.20:
			gap_col = Color(1.0, 0.9, 0.2)
		_add_debug_line(_debug_layer, min_p, surf, gap_col)
		poly.append(centroid)
	var td: Dictionary = diag.get("thumb", {})
	if td.has("pad_final"):
		poly.append(td["pad_final"])
	for i in poly.size() - 1:
		_add_debug_line(_debug_layer, poly[i], poly[i + 1], Color(0.95, 0.95, 0.95))
	var cmc_p: Vector3 = (patches.get("cmc", {}) as Dictionary).get("min_p", Vector3.ZERO)
	if td.has("pad_final"):
		_add_debug_line(
			_debug_layer,
			grip.shaft_surface_point(cmc_p),
			grip.shaft_surface_point(td["pad_final"]),
			Color(0.15, 0.9, 0.9)
		)


func _add_debug_sphere(parent: Node3D, pos: Vector3, color: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = pos


func _add_debug_line(parent: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var imm := ImmediateMesh.new()
	# ImmediateMesh vertices are in mesh local space; place node at origin.
	imm.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imm.surface_add_vertex(from)
	imm.surface_add_vertex(to)
	imm.surface_end()
	mi.mesh = imm
	parent.add_child(mi)


func assembler() -> Node:
	return _assembler


## Legacy accessor name kept for older tooling: returns the CURRENT
## equipment owner (the generic assembler), never the old attachment.
func attachment() -> Node:
	return _assembler


func equip_result() -> Dictionary:
	return _equip_result.duplicate(true)


func ground_offset_y() -> float:
	return _ground_offset_y


func preview_player() -> AnimationPlayer:
	return _player


func preview_clip_id() -> String:
	return _clip_id
