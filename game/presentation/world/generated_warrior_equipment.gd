# Presentation-only equipment for the generated_warrior on the continuous
# WorldMap / TerrainWorld path. Club uses canonical one-handed weapon
# normalization + bind-pose palm socket. Shield offsets unchanged this slice.
# Manual bone follow (not BoneAttachment3D) so SkeletonModifier3D leg
# grounding cannot crush rigid props.
extends Node

const OneHandedWeaponNormalizeScript = preload(
	"res://presentation/world/one_handed_weapon_normalize.gd"
)
const PalmFrameScript = preload("res://presentation/world/one_handed_palm_frame.gd")
const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")

const TYPE_ID := "generated_warrior"
const CONTROLLER_NODE_NAME := "GeneratedWarriorEquipment"

const CLUB_GLB_PATH := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const SHIELD_GLB_PATH := "res://assets/prototype/3d/equipment/wooden_shield/wooden_shield.glb"

const RIGHT_HAND_BONE_CANDIDATES: Array[String] = [
	"RightHand",
	"Right_Hand",
	"hand_r",
	"Hand_R",
]
const LEFT_FOREARM_BONE_CANDIDATES: Array[String] = [
	"LeftForeArm",
	"LeftForearm",
	"Left_ForeArm",
	"forearm_l",
	"ForeArm_L",
]

const SOCKET_WEAPON_R := "WeaponSocket_R"
const SOCKET_SHIELD_L := "ShieldSocket_L"
const SOCKET_OFFSET_NAME := "SocketOffset"
const CLUB_INSTANCE_NAME := "WoodenClub"
const SHIELD_INSTANCE_NAME := "WoodenShield"
const DEBUG_VIZ_NAME := "WeaponNormalizeDebug"

## Shield offsets unchanged this correction.
const SHIELD_SOCKET := {
	"socket_name": SOCKET_SHIELD_L,
	"instance_name": SHIELD_INSTANCE_NAME,
	"glb_path": SHIELD_GLB_PATH,
	"position": Vector3(0.04, 0.08, 0.05),
	"rotation_degrees": Vector3(0.0, 90.0, 90.0),
	"scale": Vector3(0.22, 0.22, 0.22),
}

var _skeleton: Skeleton3D = null
var _bone_right_hand: String = ""
var _bone_left_forearm: String = ""
var _hand_bone_idx: int = -1
var _forearm_bone_idx: int = -1
var _club_socket: Node3D = null
var _shield_socket: Node3D = null
var _club_analysis: Dictionary = {}
var _palm_frame: Dictionary = {}
var _palm_local: Transform3D = Transform3D.IDENTITY
var _debug_logged := false


static func club_resource_path() -> String:
	return CLUB_GLB_PATH


static func shield_resource_path() -> String:
	return SHIELD_GLB_PATH


static func resources_available() -> bool:
	return (
		ResourceLoader.exists(CLUB_GLB_PATH)
		and ResourceLoader.exists(SHIELD_GLB_PATH)
		and load(CLUB_GLB_PATH) is PackedScene
		and load(SHIELD_GLB_PATH) is PackedScene
	)


static func list_skeleton_bone_names(skeleton: Skeleton3D) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_name(i))
	return out


static func resolve_right_hand_bone(skeleton: Skeleton3D) -> String:
	return _first_existing_bone(skeleton, RIGHT_HAND_BONE_CANDIDATES)


static func resolve_left_forearm_bone(skeleton: Skeleton3D) -> String:
	return _first_existing_bone(skeleton, LEFT_FOREARM_BONE_CANDIDATES)


static func _first_existing_bone(skeleton: Skeleton3D, candidates: Array[String]) -> String:
	if skeleton == null:
		return ""
	for name_variant in candidates:
		var bone_name: String = str(name_variant)
		if skeleton.find_bone(bone_name) >= 0:
			return bone_name
	return ""


static func find_skeleton(model: Node) -> Skeleton3D:
	if model == null:
		return null
	if model is Skeleton3D:
		return model as Skeleton3D
	var found: Array = model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


static func find_controller(unit_root: Node):
	if unit_root == null:
		return null
	return unit_root.get_node_or_null(CONTROLLER_NODE_NAME)


static func ensure_on_unit_root(unit_root: Node3D, type_id: String):
	if unit_root == null or str(type_id) != TYPE_ID:
		return null
	var existing = find_controller(unit_root)
	if existing != null:
		return existing
	if not resources_available():
		push_warning(
			"generated_warrior_equipment: club/shield GLBs missing or failed to load"
		)
		return null
	var model_root: Node = unit_root.get_node_or_null("ModelRoot")
	if model_root == null or model_root.get_child_count() < 1:
		push_warning("generated_warrior_equipment: ModelRoot/character missing")
		return null
	var model: Node = model_root.get_child(0)
	var skeleton: Skeleton3D = find_skeleton(model)
	if skeleton == null:
		push_warning("generated_warrior_equipment: Skeleton3D not found")
		return null
	var hand: String = resolve_right_hand_bone(skeleton)
	var forearm: String = resolve_left_forearm_bone(skeleton)
	if hand.is_empty() or forearm.is_empty():
		push_warning(
			(
				"generated_warrior_equipment: bone resolve failed "
				+ "(hand='%s' forearm='%s'); bones=%s"
			)
			% [hand, forearm, str(list_skeleton_bone_names(skeleton))]
		)
		return null
	var controller = (load("res://presentation/world/generated_warrior_equipment.gd") as GDScript).new()
	controller.name = CONTROLLER_NODE_NAME
	unit_root.add_child(controller)
	controller._bind(skeleton, hand, forearm)
	controller.equip_default_loadout()
	return controller


static func sync_units_view(units_view) -> void:
	if units_view == null:
		return
	for unit_id_variant in units_view.unit_ids():
		var unit_id: int = int(unit_id_variant)
		if str(units_view.type_id_for_unit(unit_id)) != TYPE_ID:
			continue
		var root: Node3D = units_view.root_for_unit(unit_id) as Node3D
		ensure_on_unit_root(root, TYPE_ID)


func _ready() -> void:
	process_priority = 1000
	set_process(true)


func _process(_delta: float) -> void:
	_follow_weapon_socket()
	_follow_bone(_shield_socket, _forearm_bone_idx)


func _follow_bone(socket: Node3D, bone_idx: int) -> void:
	if socket == null or not is_instance_valid(socket):
		return
	if _skeleton == null or not is_instance_valid(_skeleton) or bone_idx < 0:
		return
	var bone_global: Transform3D = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
	)
	socket.global_transform = Transform3D(
		bone_global.basis.orthonormalized(), bone_global.origin
	)


func _follow_weapon_socket() -> void:
	if _club_socket == null or not is_instance_valid(_club_socket):
		return
	if _skeleton == null or not is_instance_valid(_skeleton) or _hand_bone_idx < 0:
		return
	var hand_ortho: Transform3D = PalmFrameScript.ortho_global_pose(_skeleton, _hand_bone_idx)
	_club_socket.global_transform = hand_ortho * _palm_local


func _bind(skeleton: Skeleton3D, right_hand: String, left_forearm: String) -> void:
	_skeleton = skeleton
	_bone_right_hand = right_hand
	_bone_left_forearm = left_forearm
	_hand_bone_idx = skeleton.find_bone(right_hand)
	_forearm_bone_idx = skeleton.find_bone(left_forearm)
	_palm_frame = PalmFrameScript.compute_right_palm_frame(skeleton, right_hand)
	if bool(_palm_frame.get("ok", false)):
		_palm_local = _palm_frame["palm_local"] as Transform3D
	else:
		_palm_local = Transform3D.IDENTITY
		push_warning(
			"generated_warrior_equipment: palm frame failed (%s); using wrist"
			% _palm_frame.get("reason", "?")
		)


func bound_right_hand_bone() -> String:
	return _bone_right_hand


func bound_left_forearm_bone() -> String:
	return _bone_left_forearm


func has_club() -> bool:
	return _club_socket != null and is_instance_valid(_club_socket)


func has_shield() -> bool:
	return _shield_socket != null and is_instance_valid(_shield_socket)


func club_analysis() -> Dictionary:
	return _club_analysis.duplicate(true)


func palm_frame() -> Dictionary:
	return _palm_frame.duplicate(true)


func has_finger_grip_pose() -> bool:
	# This rig has no finger chains; grip pose is not implemented.
	return false


func equip_default_loadout() -> void:
	equip_club()
	equip_shield()


func equip_club() -> void:
	if _club_socket != null and is_instance_valid(_club_socket):
		return
	if not ResourceLoader.exists(CLUB_GLB_PATH):
		push_warning("generated_warrior_equipment: missing club glb %s" % CLUB_GLB_PATH)
		return
	var packed: PackedScene = load(CLUB_GLB_PATH) as PackedScene
	if packed == null:
		push_warning("generated_warrior_equipment: failed to load club")
		return
	var height: float = float(_palm_frame.get("humanoid_height", 0.0))
	if height < 1e-6 and _skeleton != null:
		height = PalmFrameScript.measure_humanoid_height(_skeleton)
	var target_length: float = height * Profile.TARGET_LENGTH_RATIO
	var socket := Node3D.new()
	socket.name = SOCKET_WEAPON_R
	add_child(socket)
	# Weapon-class identity offset under the palm-framed socket (no asset guess).
	var offset := Node3D.new()
	offset.name = SOCKET_OFFSET_NAME
	offset.transform = Transform3D.IDENTITY
	socket.add_child(offset)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		socket.queue_free()
		return
	instance.name = CLUB_INSTANCE_NAME
	offset.add_child(instance)
	_force_meshes_visible(instance)
	_club_analysis = OneHandedWeaponNormalizeScript.analyze(instance, target_length)
	if bool(_club_analysis.get("ok", false)):
		OneHandedWeaponNormalizeScript.apply_normalize(instance, _club_analysis)
		_club_analysis["humanoid_height"] = height
		_club_analysis["target_length_ratio"] = Profile.TARGET_LENGTH_RATIO
		if not _debug_logged:
			_log_equip_debug_once()
			_debug_logged = true
		if OneHandedWeaponNormalizeScript.debug_enabled():
			_build_club_debug_viz(offset, instance, _club_analysis)
	else:
		push_warning(
			"generated_warrior_equipment: club normalize failed (%s)"
			% _club_analysis.get("reason", "?")
		)
	_club_socket = socket
	_follow_weapon_socket()
	print(
		(
			"generated_warrior_equipment: equipped %s "
			+ "(height=%.4f target_len=%.4f palm=%s fingers=%s)"
		)
		% [
			CLUB_INSTANCE_NAME,
			height,
			target_length,
			"ok" if bool(_palm_frame.get("ok", false)) else "fallback",
			str(bool(_palm_frame.get("has_fingers", false))),
		]
	)


func unequip_club() -> void:
	_club_socket = _unequip_slot(_club_socket)
	_club_analysis = {}


func equip_shield() -> void:
	_shield_socket = _equip_shield_slot(_shield_socket)


func unequip_shield() -> void:
	_shield_socket = _unequip_slot(_shield_socket)


func _equip_shield_slot(existing: Node3D) -> Node3D:
	if existing != null and is_instance_valid(existing):
		return existing
	var cfg: Dictionary = SHIELD_SOCKET
	var glb_path: String = str(cfg.get("glb_path", ""))
	if glb_path.is_empty() or not ResourceLoader.exists(glb_path):
		push_warning("generated_warrior_equipment: missing glb %s" % glb_path)
		return null
	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		return null
	var socket := Node3D.new()
	socket.name = str(cfg.get("socket_name", "EquipmentSocket"))
	add_child(socket)
	var offset := Node3D.new()
	offset.name = SOCKET_OFFSET_NAME
	offset.position = cfg.get("position", Vector3.ZERO) as Vector3
	offset.rotation_degrees = cfg.get("rotation_degrees", Vector3.ZERO) as Vector3
	offset.scale = cfg.get("scale", Vector3.ONE) as Vector3
	socket.add_child(offset)
	var instance: Node = packed.instantiate()
	if instance == null:
		socket.queue_free()
		return null
	instance.name = str(cfg.get("instance_name", "Equipment"))
	offset.add_child(instance)
	_force_meshes_visible(instance)
	_follow_bone(socket, _forearm_bone_idx)
	print("generated_warrior_equipment: equipped %s (manual bone follow)" % instance.name)
	return socket


func _force_meshes_visible(root: Node) -> void:
	if root is Node3D:
		(root as Node3D).visible = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.visible = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _unequip_slot(existing: Node3D) -> Node3D:
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	return null


func _log_equip_debug_once() -> void:
	if not OneHandedWeaponNormalizeScript.debug_enabled():
		return
	OneHandedWeaponNormalizeScript.log_analysis_once(_club_analysis, "wooden_club")
	print(
		(
			"palm_frame: height=%.4f wrist=%s knuckle=%s palm=%s "
			+ "has_fingers=%s estimated=%s roots=%s grip_pose=%s"
		)
		% [
			float(_palm_frame.get("humanoid_height", 0.0)),
			_palm_frame.get("wrist", Vector3.ZERO),
			_palm_frame.get("knuckle_centre", Vector3.ZERO),
			_palm_frame.get("palm_centre", Vector3.ZERO),
			str(bool(_palm_frame.get("has_fingers", false))),
			str(bool(_palm_frame.get("estimated", false))),
			str(_palm_frame.get("finger_roots", {})),
			str(has_finger_grip_pose()),
		]
	)


# --- Debug visualization (EOM_WEAPON_NORMALIZE_DEBUG=1) ----------------------

func _build_club_debug_viz(offset: Node3D, _weapon_root: Node3D, analysis: Dictionary) -> void:
	var old = offset.get_node_or_null(DEBUG_VIZ_NAME)
	if old != null:
		old.queue_free()
	var viz := Node3D.new()
	viz.name = DEBUG_VIZ_NAME
	offset.add_child(viz)
	var len_y: float = float(analysis["target_length"])
	var frac: float = Profile.PRIMARY_GRIP_FRACTION
	var lower_y: float = -frac * len_y
	var upper_y: float = (1.0 - frac) * len_y
	_add_debug_sphere(viz, Vector3(0.0, lower_y, 0.0), Color(0.2, 0.9, 0.2), "LowerEndpoint")
	_add_debug_sphere(viz, Vector3(0.0, upper_y, 0.0), Color(0.9, 0.2, 0.2), "UpperEndpoint")
	_add_debug_sphere(viz, Vector3.ZERO, Color(0.95, 0.85, 0.1), "GripPoint")
	_add_debug_line(
		viz, Vector3(0.0, lower_y, 0.0), Vector3(0.0, upper_y, 0.0), Color(0.2, 0.6, 1.0), "PrincipalAxis"
	)
	_add_debug_line(
		viz, Vector3.ZERO, Vector3(0.0, 0.0, len_y * 0.35), Color(0.3, 1.0, 0.9), "CanonicalFront"
	)
	# Palm / wrist / knuckle in WeaponSocket_R local (bind-pose relatives).
	var socket: Node3D = offset.get_parent() as Node3D
	if socket != null and bool(_palm_frame.get("ok", false)):
		var palm_viz := Node3D.new()
		palm_viz.name = "PalmFrameDebug"
		socket.add_child(palm_viz)
		var palm_inv: Transform3D = (
			Transform3D(_palm_frame["palm_basis"] as Basis, _palm_frame["palm_centre"] as Vector3)
			.affine_inverse()
		)
		var wrist_local: Vector3 = palm_inv * (_palm_frame["wrist"] as Vector3)
		var knuckle_local: Vector3 = palm_inv * (_palm_frame["knuckle_centre"] as Vector3)
		_add_debug_sphere(palm_viz, wrist_local, Color(1.0, 0.5, 0.1), "Wrist")
		_add_debug_sphere(palm_viz, knuckle_local, Color(0.8, 0.4, 1.0), "KnuckleCentre")
		_add_debug_sphere(palm_viz, Vector3.ZERO, Color(1.0, 0.2, 0.8), "PalmCentre")
		var axis_len: float = len_y * 0.25
		_add_debug_line(palm_viz, Vector3.ZERO, Vector3(axis_len, 0, 0), Color(1, 0.2, 0.2), "PalmX")
		_add_debug_line(palm_viz, Vector3.ZERO, Vector3(0, axis_len, 0), Color(0.2, 1, 0.2), "PalmY")
		_add_debug_line(palm_viz, Vector3.ZERO, Vector3(0, 0, axis_len), Color(0.2, 0.4, 1), "PalmZ")
		var frame := Node3D.new()
		frame.name = "WeaponSocket_R_Frame"
		socket.add_child(frame)
		_add_debug_line(frame, Vector3.ZERO, Vector3(axis_len, 0, 0), Color(1, 0.5, 0.5), "SocketX")
		_add_debug_line(frame, Vector3.ZERO, Vector3(0, axis_len, 0), Color(0.5, 1, 0.5), "SocketY")
		_add_debug_line(frame, Vector3.ZERO, Vector3(0, 0, axis_len), Color(0.5, 0.5, 1), "SocketZ")
		var h: float = float(analysis.get("humanoid_height", 0.0))
		if h > 0.0:
			_add_debug_line(
				palm_viz,
				Vector3(axis_len * 1.2, 0.0, 0.0),
				Vector3(axis_len * 1.2, h, 0.0),
				Color(0.9, 0.9, 0.2),
				"HumanoidHeight"
			)


func _add_debug_sphere(parent: Node3D, pos: Vector3, color: Color, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.024
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_debug_line(
	parent: Node3D, from: Vector3, to: Vector3, color: Color, node_name: String
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imm.surface_add_vertex(from)
	imm.surface_add_vertex(to)
	imm.surface_end()
	mi.mesh = imm
	parent.add_child(mi)
