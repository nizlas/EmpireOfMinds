# A2 isolated club attachment: melee_1h normalize + canonical power-grip
# socket mapping (audit Section 3) + power_grip_v1. One transform owner:
# WeaponSocket_R. Hard anatomical invariants (audit Section 7) are gated
# fail-closed BEFORE any finger solving.
extends Node

const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)
const Melee1h = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_melee_1h_normalize.gd"
)
const GripShape = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_grip_shape.gd"
)
const HandFrame = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_hand_grip_frame.gd"
)
const PowerGripScript = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_power_grip.gd"
)
const PalmFrameScript = preload("res://presentation/world/one_handed_palm_frame.gd")
const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const CONTROLLER_NAME := "UthanaA2ClubAttachment"
const SOCKET_WEAPON_R := "WeaponSocket_R"
const SOCKET_OFFSET_NAME := "SocketOffset"
const CLUB_INSTANCE_NAME := "WoodenClub"
const GRIP_NODE_NAME := "UthanaA2PowerGrip"
const DEBUG_LAYER_NAME := "A2GripDebugLayer"

## Power-grip shaft obliquity: D = normalize(A + tan(KAPPA_DEG) * L).
## The oblique palmar crease angle (audit Section 3, 10..15 deg band).
const KAPPA_DEG := 12.0
## Shaft axis centre volar offset in grip radii (gate band 0.4..2.2).
const VOLAR_OFFSET_RADII := 1.2
## Shaft centre sits slightly distal of the bone palm centre, along the
## oblique palmar crease (containment gate band: <= 0.5 hand_length).
const DISTAL_SHIFT_HAND := 0.15

## Hard invariant tolerances (audit Section 7).
const DOT_DA_MIN := 0.90
const DOT_DL_MAX := 0.35
const DOT_DV_MAX := 0.25
const VOLAR_OFFSET_MIN_RADII := 0.4
const VOLAR_OFFSET_MAX_RADII := 2.2
const CENTRE_ALONG_L_MAX_HAND := 0.5
const CENTRE_ALONG_A_MAX_BREADTH := 0.6
const MCP_SPREAD_MIN_BREADTH := 0.6
const HINGE_DOT_MIN := 0.80
const STATION_REACH_MIN := 0.35
const STATION_REACH_MAX := 0.95

var _skeleton: Skeleton3D = null
var _character: Node3D = null
var _hand_bone: String = ""
var _hand_bone_idx: int = -1
var _club_socket: Node3D = null
var _club_instance: Node3D = null
var _analysis: Dictionary = {}
var _metadata: Dictionary = {}
var _shape: Dictionary = {}
var _volar: Dictionary = {}
var _invariants: Dictionary = {}
var _grip_local: Transform3D = Transform3D.IDENTITY
var _grip: SkeletonModifier3D = null
var _humanoid_height: float = 0.0
var _debug_draw: bool = false
var _debug_layer: Node3D = null
var _club_path_override: String = ""


static func club_glb_path() -> String:
	return Melee1h.club_source_path()


## Test hook (smoke tests only): broken paths still fail closed.
func set_club_path_override(path: String) -> void:
	_club_path_override = path


func _club_source_path() -> String:
	if not _club_path_override.is_empty():
		return _club_path_override
	return Melee1h.club_source_path()


func bind_to_character(character: Node3D) -> Dictionary:
	_character = character
	_skeleton = Native.find_skeleton(character)
	if _skeleton == null:
		return {"ok": false, "reason": "skeleton_missing"}
	_hand_bone = HandFrame.HAND_BONE
	_hand_bone_idx = _skeleton.find_bone(_hand_bone)
	if _hand_bone_idx < 0:
		return {"ok": false, "reason": "RightHand_missing"}
	_humanoid_height = PalmFrameScript.measure_humanoid_height(_skeleton)
	if _humanoid_height < 1e-6:
		return {"ok": false, "reason": "degenerate_height"}

	# Hard precondition: right-handed, volar-verified hand frame.
	var frame_pose: Dictionary = HandFrame.compute(_skeleton, false)
	if not bool(frame_pose.get("ok", false)):
		return {
			"ok": false,
			"reason": "hand_frame_failed",
			"error_class": frame_pose.get("error_class", "HAND_FRAME_FAILED"),
			"frame": frame_pose,
		}
	_volar = HandFrame.verify_volar(_skeleton, _character, frame_pose)
	if not bool(_volar.get("ok", false)):
		return {
			"ok": false,
			"reason": "volar_verification_failed",
			"error_class": _volar.get("error_class", "VOLAR_VERIFICATION_FAILED"),
			"volar": _volar,
		}
	process_priority = 1000
	set_process(true)
	return {
		"ok": true,
		"frame": frame_pose,
		"volar": _volar,
		"height": _humanoid_height,
	}


func equip_club() -> Dictionary:
	if _club_socket != null and is_instance_valid(_club_socket):
		return {"ok": true, "already": true, "analysis": _analysis, "metadata": _metadata}
	if _skeleton == null:
		return {"ok": false, "reason": "not_bound"}
	var path: String = _club_source_path()
	if not ResourceLoader.exists(path):
		return {"ok": false, "reason": "club_missing", "path": path}
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "club_load_failed"}
	var target_length: float = _humanoid_height * Profile.TARGET_LENGTH_RATIO
	var socket := Node3D.new()
	socket.name = SOCKET_WEAPON_R
	add_child(socket)
	var offset := Node3D.new()
	offset.name = SOCKET_OFFSET_NAME
	offset.transform = Transform3D.IDENTITY
	socket.add_child(offset)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		socket.queue_free()
		return {"ok": false, "reason": "instantiate_failed"}
	instance.name = CLUB_INSTANCE_NAME
	offset.add_child(instance)
	_force_visible(instance)

	_analysis = Melee1h.analyze(instance, target_length)
	if not bool(_analysis.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": _analysis.get("reason", "normalize_failed"),
			"error_class": _analysis.get("error_class", "NORMALIZE_FAILED"),
			"analysis": _analysis,
		}
	Melee1h.apply_normalize(instance, _analysis)
	_shape = GripShape.derive_from_normalized_club(instance)
	if not bool(_shape.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": _shape.get("reason", "shape_failed"),
			"error_class": "GRIP_SHAPE_FAILED",
			"shape": _shape,
		}
	_metadata = Melee1h.build_marker_metadata(_analysis, _humanoid_height)
	_metadata["grip_shape"] = _shape
	_metadata["radius_x"] = _shape.get("radius_x", 0.0)
	_metadata["radius_z"] = _shape.get("radius_z", 0.0)
	_metadata["radius_mean"] = _shape.get("radius_mean", 0.0)
	var envelope: Dictionary = Melee1h.validate_envelope(_analysis, _humanoid_height)
	if not bool(envelope.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": envelope.get("reason", "envelope_failed"),
			"error_class": "ENVELOPE_FAILED",
			"envelope": envelope,
			"analysis": _analysis,
		}

	# Canonical power-grip socket mapping from the rest-pose hand frame:
	# weapon +Y (shaft grip->head) -> D = normalize(A + tan(kappa) * L)
	# weapon +Z (section reference) -> volar component perpendicular to D
	# origin -> palm centre + volar offset (audit Section 3).
	var frame_rest: Dictionary = HandFrame.compute(_skeleton, true)
	if not bool(frame_rest.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": "rest_frame_failed",
			"error_class": frame_rest.get("error_class", "HAND_FRAME_FAILED"),
		}
	var r_mean: float = float(_shape.get("radius_mean", 0.01))
	var grip_world_rest: Transform3D = build_grip_socket_world(frame_rest, r_mean)
	var hand_rest: Transform3D = frame_rest["hand_transform"]
	_grip_local = hand_rest.affine_inverse() * grip_world_rest

	_club_socket = socket
	_club_instance = instance
	_follow_weapon_socket()

	# Hard anatomical preconditions, fail-closed BEFORE any finger solving.
	var frame_pose: Dictionary = HandFrame.compute(_skeleton, false)
	_invariants = evaluate_grip_invariants(
		frame_pose, offset.global_transform, r_mean
	)
	if not bool(_invariants.get("pass", false)):
		socket.queue_free()
		_club_socket = null
		_club_instance = null
		return {
			"ok": false,
			"reason": "grip_frame_preconditions_failed",
			"error_class": "GRIP_FRAME_PRECONDITION_FAILED",
			"invariants": _invariants,
		}

	var grip_ok: Dictionary = attach_grip(frame_pose)
	return {
		"ok": bool(grip_ok.get("ok", false)),
		"analysis": _analysis,
		"metadata": _metadata,
		"shape": _shape,
		"envelope": envelope,
		"volar": _volar,
		"invariants": _invariants,
		"grip": grip_ok,
		"club_path": path,
		"reason": grip_ok.get("reason", ""),
	}


## Target socket transform in the space of the given hand frame.
static func build_grip_socket_world(frame: Dictionary, radius_mean: float) -> Transform3D:
	var a: Vector3 = frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var d: Vector3 = (a + tan(deg_to_rad(KAPPA_DEG)) * l).normalized()
	var z: Vector3 = (v - d * v.dot(d)).normalized()
	var x: Vector3 = d.cross(z)
	var c: Vector3 = (
		(frame["palm_centre"] as Vector3)
		+ v * (VOLAR_OFFSET_RADII * radius_mean)
		+ l * (DISTAL_SHIFT_HAND * float(frame["hand_length"]))
	)
	return Transform3D(Basis(x, d, z), c)


## Audit Section 7 hard preconditions, measured on the ACHIEVED socket
## transform against the given hand frame. Fail-closed list of violations.
static func evaluate_grip_invariants(
	frame: Dictionary, socket_world: Transform3D, radius_mean: float
) -> Dictionary:
	var failures: Array[String] = []
	if not bool(frame.get("ok", false)):
		return {"pass": false, "failures": ["hand_frame_invalid"]}
	var a: Vector3 = frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var p: Vector3 = frame["palm_centre"]
	var hand_length: float = float(frame["hand_length"])
	var breadth: float = float(frame["knuckle_breadth"])
	var r: float = maxf(radius_mean, 1e-9)

	var det_frame: float = float(frame.get("det", 0.0))
	if det_frame < 0.99:
		failures.append("palm_basis_det")
	var det_socket: float = socket_world.basis.determinant()
	if det_socket < 0.99:
		failures.append("socket_det")

	var d: Vector3 = socket_world.basis.y.normalized()
	var c: Vector3 = socket_world.origin
	var dot_da: float = d.dot(a)
	var dot_dl: float = d.dot(l)
	var dot_dv: float = d.dot(v)
	if absf(dot_da) < DOT_DA_MIN:
		failures.append("shaft_not_transverse")
	if dot_da <= 0.0:
		failures.append("head_side_not_radial")
	if absf(dot_dl) > DOT_DL_MAX:
		failures.append("shaft_along_fingers")
	if absf(dot_dv) > DOT_DV_MAX:
		failures.append("shaft_through_palm")

	var offset_vec: Vector3 = c - p
	var volar_offset: float = offset_vec.dot(v)
	if volar_offset < VOLAR_OFFSET_MIN_RADII * r or volar_offset > VOLAR_OFFSET_MAX_RADII * r:
		failures.append("volar_offset_out_of_band")
	if absf(offset_vec.dot(l)) > CENTRE_ALONG_L_MAX_HAND * hand_length:
		failures.append("centre_outside_hand_longitudinal")
	if absf(offset_vec.dot(a)) > CENTRE_ALONG_A_MAX_BREADTH * breadth:
		failures.append("centre_outside_hand_transverse")

	var mcp: Dictionary = frame["mcp"]
	var hinge: Dictionary = frame["hinge"]
	var chain_length: Dictionary = frame["chain_length"]
	var projections := {}
	var prev := INF
	var monotonic := true
	for finger in HandFrame.FINGER_ORDER:
		var proj: float = (mcp[finger] as Vector3).dot(d)
		projections[finger] = proj
		if proj >= prev:
			monotonic = false
		prev = proj
	if not monotonic:
		failures.append("mcp_projection_not_monotonic")
	var spread: float = (
		float(projections["index"]) - float(projections["pinky"])
	)
	if spread < MCP_SPREAD_MIN_BREADTH * breadth:
		failures.append("mcp_projection_spread")

	var hinge_dots := {}
	var station_reach := {}
	for finger in HandFrame.FINGER_ORDER:
		var hd: float = absf(d.dot(hinge[finger] as Vector3))
		hinge_dots[finger] = hd
		if hd < HINGE_DOT_MIN:
			failures.append("hinge_axis_%s" % finger)
		var w: Vector3 = (mcp[finger] as Vector3) - c
		var radial: Vector3 = w - d * w.dot(d)
		var reach: float = radial.length() / maxf(float(chain_length[finger]), 1e-9)
		station_reach[finger] = reach
		if reach < STATION_REACH_MIN or reach > STATION_REACH_MAX:
			failures.append("station_reach_%s" % finger)

	return {
		"pass": failures.is_empty(),
		"failures": failures,
		"det_frame": det_frame,
		"det_socket": det_socket,
		"dot_da": dot_da,
		"dot_dl": dot_dl,
		"dot_dv": dot_dv,
		"volar_offset": volar_offset,
		"volar_offset_radii": volar_offset / r,
		"centre_along_l": offset_vec.dot(l),
		"centre_along_a": offset_vec.dot(a),
		"mcp_projections": projections,
		"mcp_spread": spread,
		"mcp_spread_over_breadth": spread / maxf(breadth, 1e-9),
		"hinge_dots": hinge_dots,
		"station_reach": station_reach,
		"radius_mean": r,
		"hand_length": hand_length,
		"knuckle_breadth": breadth,
	}


func attach_grip(frame_pose: Dictionary) -> Dictionary:
	if _skeleton == null or _character == null or _club_instance == null:
		return {"ok": false, "reason": "not_ready"}
	var existing = _skeleton.get_node_or_null(GRIP_NODE_NAME)
	if existing != null:
		_grip = existing as SkeletonModifier3D
	else:
		_grip = PowerGripScript.new()
		_grip.name = GRIP_NODE_NAME
		_skeleton.add_child(_grip)
	var cfg: Dictionary = (_grip as Object).configure(
		_character, _club_instance, _shape, frame_pose
	)
	if not bool(cfg.get("ok", false)):
		return cfg
	(_grip as Object).set_grip_enabled(true)
	(_grip as Object).apply_now()
	return cfg


func set_grip_enabled(enabled: bool) -> void:
	if _grip != null and is_instance_valid(_grip):
		(_grip as Object).set_grip_enabled(enabled)
		if enabled:
			(_grip as Object).apply_now()


func is_grip_enabled() -> bool:
	if _grip == null or not is_instance_valid(_grip):
		return false
	return bool((_grip as Object).is_grip_enabled())


func grip_modifier() -> SkeletonModifier3D:
	return _grip


func has_club() -> bool:
	return _club_socket != null and is_instance_valid(_club_socket)


func club_instance() -> Node3D:
	return _club_instance


func club_socket() -> Node3D:
	return _club_socket


func club_analysis() -> Dictionary:
	return _analysis.duplicate(true)


func grip_shape() -> Dictionary:
	return _shape.duplicate(true)


func marker_metadata() -> Dictionary:
	return _metadata.duplicate(true)


func invariants() -> Dictionary:
	return _invariants.duplicate(true)


func volar_verification() -> Dictionary:
	return _volar.duplicate(true)


func humanoid_height() -> float:
	return _humanoid_height


func hand_bone_name() -> String:
	return _hand_bone


func live_hand_frame() -> Dictionary:
	return HandFrame.compute(_skeleton, false)


## Re-evaluate the hard invariants against the CURRENT pose and socket.
func measure_grip_invariants() -> Dictionary:
	if _club_socket == null or _skeleton == null:
		return {"pass": false, "failures": ["no_club"]}
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return {"pass": false, "failures": ["no_socket_offset"]}
	return evaluate_grip_invariants(
		HandFrame.compute(_skeleton, false),
		offset.global_transform,
		float(_shape.get("radius_mean", 0.01))
	)


func set_debug_draw(enabled: bool) -> void:
	_debug_draw = enabled
	if not enabled and _debug_layer != null:
		_debug_layer.queue_free()
		_debug_layer = null


func is_debug_draw() -> bool:
	return _debug_draw


func relative_club_to_hand() -> Transform3D:
	if _club_instance == null or _skeleton == null or _hand_bone_idx < 0:
		return Transform3D()
	var hand_ortho: Transform3D = PalmFrameScript.ortho_global_pose(_skeleton, _hand_bone_idx)
	return hand_ortho.affine_inverse() * _club_instance.global_transform


func primary_grip_world() -> Vector3:
	if _club_socket == null:
		return Vector3.ZERO
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return _club_socket.global_position
	return offset.global_position


func active_end_world() -> Vector3:
	var target_len: float = float(_analysis.get("target_length", 0.0))
	var frac: float = float(_analysis.get("grip_fraction", Profile.PRIMARY_GRIP_FRACTION))
	var local := Vector3(0.0, (1.0 - frac) * target_len, 0.0)
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return Vector3.ZERO
	return offset.to_global(local)


func grip_end_world() -> Vector3:
	var target_len: float = float(_analysis.get("target_length", 0.0))
	var frac: float = float(_analysis.get("grip_fraction", Profile.PRIMARY_GRIP_FRACTION))
	var local := Vector3(0.0, -frac * target_len, 0.0)
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return Vector3.ZERO
	return offset.to_global(local)


func _process(_delta: float) -> void:
	_follow_weapon_socket()
	if _debug_draw:
		_update_debug_layer()


func _follow_weapon_socket() -> void:
	if _club_socket == null or not is_instance_valid(_club_socket):
		return
	if _skeleton == null or not is_instance_valid(_skeleton) or _hand_bone_idx < 0:
		return
	var hand_ortho: Transform3D = PalmFrameScript.ortho_global_pose(_skeleton, _hand_bone_idx)
	_club_socket.global_transform = hand_ortho * _grip_local


func _force_visible(root: Node) -> void:
	if root is Node3D:
		(root as Node3D).visible = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.visible = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _update_debug_layer() -> void:
	if _debug_layer == null or not is_instance_valid(_debug_layer):
		_debug_layer = Node3D.new()
		_debug_layer.name = DEBUG_LAYER_NAME
		add_child(_debug_layer)
	for c in _debug_layer.get_children():
		c.queue_free()
	var frame: Dictionary = live_hand_frame()
	if bool(frame.get("ok", false)):
		var p: Vector3 = frame["palm_centre"]
		_add_debug_sphere(_debug_layer, p, Color(1.0, 0.2, 0.8), 0.004)
		_add_debug_line(_debug_layer, p, p + (frame["volar"] as Vector3) * 0.03, Color(0.2, 1.0, 0.4))
		_add_debug_line(_debug_layer, p, p + (frame["across"] as Vector3) * 0.03, Color(1.0, 0.3, 0.2))
	var axis_o: Vector3 = primary_grip_world()
	var axis_d: Vector3 = (active_end_world() - grip_end_world()).normalized()
	_add_debug_sphere(_debug_layer, axis_o, Color(0.95, 0.85, 0.1), 0.004)
	_add_debug_line(_debug_layer, axis_o - axis_d * 0.04, axis_o + axis_d * 0.08, Color(0.2, 0.7, 1.0))
	if _grip == null:
		return
	var diag: Dictionary = (_grip as Object).last_diagnostics()
	for finger in ["thumb", "index", "middle", "ring", "pinky"]:
		var fd: Dictionary = diag.get(finger, {})
		if fd.has("pad_final"):
			_add_debug_sphere(_debug_layer, fd["pad_final"], Color(0.2, 1.0, 0.4), 0.003)


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
