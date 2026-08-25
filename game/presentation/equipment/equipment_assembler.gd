# One reusable application order for rigid equipment + finger grip (A2.9:
# the actual runtime owner for the accepted right-hand preview). A rigid
# weapon has exactly one transform owner (the owner hand's socket).
# secondary_grip is an interface only — no two-handed IK.
#
# ALL family/asset/weapon/engine choices are INJECTED via
# configure_dependencies(); the generic core has no silent asset defaults
# and fails closed with named error classes when a dependency is missing.
# A composition root outside the core (e.g. the Uthana A2 one) selects the
# concrete family, fixture, weapon and engine.
extends Node

const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const GripGeom = preload("res://presentation/equipment/equipment_grip_geometry.gd")
const Policy = preload("res://presentation/equipment/grip_interaction_profile.gd")
const Solver = preload("res://presentation/equipment/hand_grip_solver.gd")
const DefaultSkinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")

const SOCKET_OFFSET_NAME := "SocketOffset"

var _skeleton: Skeleton3D = null
var _character: Node3D = null
var _profile = null
var _side: String = "right"
var _policy_id: String = Policy.POLICY_POWER_GRIP_1H
var _club_socket: Node3D = null
var _club_instance: Node3D = null
var _shape: Dictionary = {}
var _geometry: Dictionary = {}
var _invariants: Dictionary = {}
var _volar: Dictionary = {}
var _grip_local: Transform3D = Transform3D.IDENTITY
var _grip: SkeletonModifier3D = null
var _humanoid_height: float = 0.0
var _club_path_override: String = ""
var _last_result: Dictionary = {}
## Injected dependencies: family, fixture, weapon_scene or weapon_path,
## weapon_node_name, engines {policy_id: Script}, optional skinning.
var _deps: Dictionary = {}


func configure_dependencies(deps: Dictionary) -> void:
	_deps = deps.duplicate()


func dependencies() -> Dictionary:
	return _deps.duplicate()


## Test hook (smoke tests only): broken paths still fail closed.
func set_club_path_override(path: String) -> void:
	_club_path_override = path


func owner_side() -> String:
	return _side


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func club_socket() -> Node3D:
	return _club_socket


func club_instance() -> Node3D:
	return _club_instance


func grip_modifier() -> SkeletonModifier3D:
	return _grip


func has_club() -> bool:
	return _club_socket != null and is_instance_valid(_club_socket)


func grip_shape() -> Dictionary:
	return _shape.duplicate(true)


func hand_profile():
	return _profile


func marker_metadata() -> Dictionary:
	return (_geometry.get("metadata", {}) as Dictionary).duplicate(true)


func weapon_analysis() -> Dictionary:
	return (_geometry.get("analysis", {}) as Dictionary).duplicate(true)


func invariants() -> Dictionary:
	return _invariants.duplicate(true)


func volar_verification() -> Dictionary:
	return _volar.duplicate(true)


func set_grip_enabled(enabled: bool) -> void:
	if _grip != null and is_instance_valid(_grip):
		(_grip as Object).set_grip_enabled(enabled)
		if enabled:
			(_grip as Object).apply_now()


func is_grip_enabled() -> bool:
	if _grip == null or not is_instance_valid(_grip):
		return false
	return bool((_grip as Object).is_grip_enabled())


func _skinning():
	return _deps.get("skinning", DefaultSkinning)


## 1. body animation is assumed already sampled by the caller
## 2. carry overlay: interface only (not applied in this slice)
## 3. attach rigid equipment once through the owner hand + primary_grip
## 4. secondary IK: interface only
## 5. per-hand finger interaction after animation
## 6. update skeleton transforms
## 7. measure achieved skinned geometry
## 8. accept or reject fail-closed
## 9. classified diagnostics
func assemble(
	character: Node3D, side: String = "right", policy_id: String = Policy.POLICY_POWER_GRIP_1H
) -> Dictionary:
	_side = "left" if side == "left" else "right"
	_policy_id = policy_id
	_character = character
	if Policy.requires_secondary(policy_id):
		return _fail("secondary_ik_not_implemented", "SECONDARY_IK_NOT_IMPLEMENTED")
	if not Policy.is_implemented(policy_id):
		return _fail("policy_not_implemented", "POLICY_NOT_IMPLEMENTED")
	var family = _deps.get("family", null)
	if family == null:
		return _fail("family_required", "FAMILY_REQUIRED")
	var fixture = _deps.get("fixture", null)
	if fixture == null:
		return _fail("fixture_required", "FIXTURE_REQUIRED")
	var engines: Dictionary = _deps.get("engines", {})
	var engine_script: Script = engines.get(policy_id, null)
	if engine_script == null:
		return _fail("engine_required", "ENGINE_REQUIRED")
	if _club_path_override.is_empty() and not _deps.has("weapon_scene") and str(_deps.get("weapon_path", "")).is_empty():
		return _fail("weapon_source_required", "WEAPON_SOURCE_REQUIRED")
	_skeleton = _skinning().find_skeleton(character)
	if _skeleton == null:
		return _fail("skeleton_missing", "SKELETON_MISSING")
	var compiled: Dictionary = HandProfile.compile(
		_skeleton, character, _side, fixture, family, _skinning()
	)
	if not bool(compiled.get("ok", false)):
		return {
			"ok": false,
			"reason": "hand_profile_failed",
			"error_class": "HAND_PROFILE_FAILED",
			"failures": compiled.get("failures", []),
		}
	_profile = compiled["profile"]
	_humanoid_height = _skinning().measure_humanoid_height(
		_skeleton,
		family.HEIGHT_HEAD_CANDIDATES,
		family.HEIGHT_FLOOR_CANDIDATES
	)
	if _humanoid_height < 1e-6:
		return _fail("degenerate_height", "DEGENERATE_HEIGHT")
	var frame_pose: Dictionary = _profile.compute_frame(_skeleton, false)
	if not bool(frame_pose.get("ok", false)):
		return {
			"ok": false,
			"reason": "hand_frame_failed",
			"error_class": frame_pose.get("error_class", "HAND_FRAME_FAILED"),
			"frame": frame_pose,
		}
	_volar = _profile.verify_volar(_skeleton, _character, frame_pose)
	if not bool(_volar.get("ok", false)):
		return {
			"ok": false,
			"reason": "volar_verification_failed",
			"error_class": _volar.get("error_class", "VOLAR_VERIFICATION_FAILED"),
			"volar": _volar,
		}
	var attach_r: Dictionary = _attach_weapon()
	if not bool(attach_r.get("ok", false)):
		return attach_r
	# Secondary reach/IK reserved — a second transform owner is forbidden.
	if _club_instance != null and _club_instance.get_parent() != null:
		var owners := 0
		var n: Node = _club_instance
		while n != null:
			if str(n.name).begins_with("WeaponSocket_"):
				owners += 1
			n = n.get_parent()
		if owners != 1:
			return _fail("weapon_two_transform_owners", "WEAPON_TWO_TRANSFORM_OWNERS")
	var offset: Node3D = _club_socket.get_node(SOCKET_OFFSET_NAME) as Node3D
	_invariants = Policy.evaluate_grip_invariants(
		frame_pose, offset.global_transform, float(_shape.get("radius_mean", 0.01))
	)
	if not bool(_invariants.get("pass", false)):
		_clear_weapon()
		return {
			"ok": false,
			"reason": "grip_frame_preconditions_failed",
			"error_class": "GRIP_FRAME_PRECONDITION_FAILED",
			"invariants": _invariants,
		}
	var grip_ok: Dictionary = Solver.attach(
		_skeleton, _character, _club_instance, _shape, frame_pose, _profile, engine_script
	)
	_grip = grip_ok.get("grip", null)
	_last_result = {
		"ok": bool(grip_ok.get("ok", false)),
		"side": _side,
		"policy": _policy_id,
		"profile_key": compiled.get("cache_key", ""),
		"shape": _shape,
		"geometry": _geometry,
		"volar": _volar,
		"invariants": _invariants,
		"grip": grip_ok,
		"reason": grip_ok.get("reason", ""),
		"error_class": grip_ok.get("error_class", ""),
		"club_path": _club_source_path(),
		"application_order": [
			"body_animation_sampled",
			"carry_overlay_skipped",
			"owner_hand_primary_grip",
			"secondary_ik_skipped",
			"finger_interaction",
			"skeleton_update",
			"achieved_skinned_measure",
			"fail_closed_accept",
		],
	}
	return _last_result


func _attach_weapon() -> Dictionary:
	if _club_socket != null and is_instance_valid(_club_socket):
		return {"ok": true, "already": true}
	var packed: PackedScene = null
	if _club_path_override.is_empty() and _deps.has("weapon_scene"):
		packed = _deps.get("weapon_scene") as PackedScene
	else:
		var path: String = _club_source_path()
		if not ResourceLoader.exists(path):
			return _fail("club_missing", "CLUB_MISSING")
		packed = load(path) as PackedScene
	if packed == null:
		return _fail("club_load_failed", "CLUB_LOAD_FAILED")
	var socket := Node3D.new()
	socket.name = "WeaponSocket_L" if _side == "left" else "WeaponSocket_R"
	add_child(socket)
	var offset := Node3D.new()
	offset.name = SOCKET_OFFSET_NAME
	offset.transform = Transform3D.IDENTITY
	socket.add_child(offset)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		socket.queue_free()
		return _fail("instantiate_failed", "INSTANTIATE_FAILED")
	instance.name = str(_deps.get("weapon_node_name", "Weapon"))
	offset.add_child(instance)
	_force_visible(instance)
	_geometry = GripGeom.from_normalized_melee(instance, _humanoid_height, _side)
	if not bool(_geometry.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": "grip_geometry_failed",
			"error_class": "GRIP_GEOMETRY_FAILED",
			"failures": _geometry.get("failures", []),
		}
	_shape = _geometry.get("shape", {})
	var frame_rest: Dictionary = _profile.compute_frame(_skeleton, true)
	if not bool(frame_rest.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": "rest_frame_failed",
			"error_class": frame_rest.get("error_class", "HAND_FRAME_FAILED"),
		}
	var r_mean: float = float(_shape.get("radius_mean", 0.01))
	var grip_world_rest: Transform3D = Policy.build_grip_socket_world(frame_rest, r_mean)
	var hand_rest: Transform3D = frame_rest["hand_transform"]
	_grip_local = hand_rest.affine_inverse() * grip_world_rest
	_club_socket = socket
	_club_instance = instance
	_follow_weapon_socket()
	set_process(true)
	process_priority = 1000
	return {"ok": true}


func _follow_weapon_socket() -> void:
	if _skeleton == null or _club_socket == null or _profile == null:
		return
	var hand_i: int = _skeleton.find_bone(str(_profile.bones["hand"]))
	if hand_i < 0:
		return
	var hand_world: Transform3D = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(hand_i)
	)
	hand_world.basis = hand_world.basis.orthonormalized()
	_club_socket.global_transform = hand_world * _grip_local


func _process(_delta: float) -> void:
	_follow_weapon_socket()


func _clear_weapon() -> void:
	if _club_socket != null and is_instance_valid(_club_socket):
		_club_socket.queue_free()
	_club_socket = null
	_club_instance = null


func _club_source_path() -> String:
	if not _club_path_override.is_empty():
		return _club_path_override
	return str(_deps.get("weapon_path", ""))


func _fail(reason: String, error_class: String) -> Dictionary:
	_last_result = {"ok": false, "reason": reason, "error_class": error_class, "side": _side}
	return _last_result


func _force_visible(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = true
	for c in node.get_children():
		_force_visible(c)


func live_hand_frame() -> Dictionary:
	if _profile == null or _skeleton == null:
		return {"ok": false}
	return _profile.compute_frame(_skeleton, false)


## Re-evaluate the hard socket invariants against the CURRENT pose.
func measure_grip_invariants() -> Dictionary:
	if _club_socket == null or _skeleton == null or _profile == null:
		return {"pass": false, "failures": ["no_club"]}
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return {"pass": false, "failures": ["no_socket_offset"]}
	return Policy.evaluate_grip_invariants(
		_profile.compute_frame(_skeleton, false),
		offset.global_transform,
		float(_shape.get("radius_mean", 0.01))
	)


func primary_grip_world() -> Vector3:
	if _club_socket == null:
		return Vector3.ZERO
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return _club_socket.global_position
	return offset.global_transform.origin


func humanoid_height() -> float:
	return _humanoid_height
